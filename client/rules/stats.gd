class_name RulesStats
extends RefCounted
# 屬性/成長/經驗。全部【自訂】數值（攻略只講「升級時武/智/敏/靈提升」、「5 級脫新手」）
# attrs = {str, agi, int, spi, pol, cha}；character = Dictionary（可直接序列化）

const NEWBIE_LEVEL := 5    # 【原】5 級脫離新手
const MAX_LEVEL := 100     # 【原】三轉 100 級
const ATTR_KEYS := ["str", "agi", "int", "spi", "pol", "cha"]
const RAIDABLE := ["str", "agi", "int", "spi"]   # 升級點數分配嘅四屬性 (spec 01 §5)
const UPGRADE_POINTS := 3  # 【自訂】每升 1 級發幾多點
const ATTR_CAP := 99       # 【原】修練/點數上限 99


static func max_hp(lv: int, a: Dictionary) -> int:
	return int(60 + lv * 15 + a["str"] * 4)


static func max_mp(lv: int, a: Dictionary) -> int:
	return int(20 + lv * 5 + a["spi"] * 3 + a["int"] * 2)


static func max_sp(lv: int, a: Dictionary) -> int:
	return int(50 + lv * 3 + a["agi"] * 2)


# 玩家術防【自訂】(spec 02 §3): 隨等級+靈力；護鏡/光鏡/仙鏡 buff 喺 sim 再乘倍率
static func player_spell_def(lv: int, spi: int) -> int:
	return int(floor(lv / 3.0)) + maxi(0, int(floor((spi - 10.0) / 4.0)))


# 升到下一級所需經驗
static func exp_to_next(lv: int) -> int:
	return ExpTable.need(lv)             # 用家提供升級表 (rules/exp_table.gd)


# 基礎屬性 (建角用) + 自動派點後嘅預期屬性 (UI 預覽用)
static func attrs_at(cls: Dictionary, lv: int) -> Dictionary:
	var a := {}
	for k in ATTR_KEYS:
		a[k] = int(cls["base"][k])
	for k in cls["growth"]:
		a[k] = int(a[k]) + int(cls["growth"][k]) * (lv - 1)
	return a


# 失敗回 {} 並 push_error
static func create_character(data: GameData, char_name: String, class_id: String) -> Dictionary:
	var cls: Dictionary = data.classes.get(class_id, {})
	if cls.is_empty() or not cls["enabled"]:
		push_error("職業未開放: " + class_id)
		return {}
	if char_name.length() < 1 or char_name.length() > 8:   # 【原】≤8 字
		push_error("名字要 1~8 字")
		return {}
	var st: Dictionary = data.starter.get(class_id, {})
	var attrs := attrs_at(cls, 1)
	var bag: Array = []
	for i in st.get("items", []):
		bag.append({"id": int(i["id"]), "n": int(i["n"])})
	var equip := {}
	if not st.is_empty():
		equip = {"weapon": int(st["weapon"]), "boots": int(st["boots"])}
	var face := {}
	for part in data.face_parts:
		face[part] = 1
	return {
		"name": char_name, "classId": class_id, "level": 1, "exp": 0, "tier": 0, "attrs": attrs,
		"hp": max_hp(1, attrs), "mp": max_mp(1, attrs), "sp": max_sp(1, attrs),
		"gold": int(st.get("gold", 0)), "karma": 0, "bag": bag, "equip": equip, "status": {},
		# Step 7.5 建角欄位 (spec 01 §1/§11)
		"title": "", "face": face,
		"ideology": "", "quizAnswers": [], "attrPoints": 0, "raised": {},
		# Step 8 任務欄位 (spec 06 §1.2): 進行中 questId -> {stage, startDay, flags}；完成記錄
		"quests": {}, "questDone": {},
		# S02c 職業特技 (spec 02 §6): 學到 = ch.classSkill = skill id（單一格；未學 = ""）
		"classSkill": "",
	}


# 加經驗，可連升多級；升級回滿 HP/MP/SP。每升 1 級發 UPGRADE_POINTS 點畀玩家分配 (spec 01 §5)。回傳升咗幾級
static func gain_exp(data: GameData, ch: Dictionary, amount: int) -> int:
	var ups := 0
	ch["exp"] = int(ch["exp"]) + amount
	while int(ch["level"]) < MAX_LEVEL and int(ch["exp"]) >= exp_to_next(int(ch["level"])):
		ch["exp"] = int(ch["exp"]) - exp_to_next(int(ch["level"]))
		ch["level"] = int(ch["level"]) + 1
		ups += 1
		ch["attrPoints"] = int(ch.get("attrPoints", 0)) + UPGRADE_POINTS
	if int(ch["level"]) >= MAX_LEVEL:
		ch["exp"] = 0
	if ups > 0:
		var lv := int(ch["level"])
		var attrs: Dictionary = ch["attrs"]
		ch["hp"] = max_hp(lv, attrs)
		ch["mp"] = max_mp(lv, attrs)
		ch["sp"] = max_sp(lv, attrs)
	return ups


# 升級提示 (P4): lv_from → lv_to 之間新解鎖嘅術法 / 絕招（只列本職）
static func unlock_hints(data: GameData, class_id: String, lv_from: int, lv_to: int) -> Array:
	var out: Array = []
	for sp in data.spells:
		if int(sp["lv"]) > lv_from and int(sp["lv"]) <= lv_to and (sp["classes"] as Array).has(class_id):
			out.append("可學術法「%s」" % str(sp["name"]))
	for u in data.ultimates:
		if str(u["class"]) == class_id and int(u.get("reqLevel", 0)) > lv_from and int(u.get("reqLevel", 0)) <= lv_to:
			out.append("絕招「%s」等級夠用 (要先完成任務)" % str(u["name"]))
	return out


# 升級點數分配: 得 str/agi/int/spi 可以用; 政治/魅力唔用得分點 (spec 01 §5)。
# 回 0=成功 / 1=冇點 / 2=唔係可分配屬性 / 3=屬性已到上限
static func can_raise(ch: Dictionary, attr: String) -> int:
	if not RAIDABLE.has(attr):
		return 2
	if int(ch.get("attrPoints", 0)) <= 0:
		return 1
	if int(ch["attrs"][attr]) >= ATTR_CAP:
		return 3
	return 0


# 扣 1 點，屬性 +1（上限內）。回同 can_raise。最大值唔會超 ATTR_CAP
static func raise_attr(ch: Dictionary, attr: String) -> int:
	var code := can_raise(ch, attr)
	if code != 0:
		return code
	ch["attrPoints"] = int(ch["attrPoints"]) - 1
	ch["attrs"][attr] = int(ch["attrs"][attr]) + 1
	var raised: Dictionary = ch.get("raised", {})
	ch["raised"] = raised
	raised[attr] = int(raised.get(attr, 0)) + 1
	return 0


# 自動分配: 按 classes.json.growth 建議比例 (純 UI 提示) 派晒所有點。確定性、唔用 RNG。
# 分配落 RAIDABLE；派到 99 上限就唔再派嗰隻，餘點留低。
static func auto_assign_points(ch: Dictionary, cls: Dictionary) -> void:
	var w := {}
	var total := 0
	for k in RAIDABLE:
		var weight := int(cls["growth"].get(k, 0))
		w[k] = weight
		total += weight
	if total <= 0:                       # 冇建議比例 → 四屬平均
		for k in RAIDABLE:
			w[k] = 1
		total = RAIDABLE.size()
	var pts := int(ch["attrPoints"])
	if pts <= 0:
		return
	var spent := {}
	for k in RAIDABLE:
		spent[k] = 0
	var guard := pts + 64
	while pts > 0 and guard > 0:
		guard -= 1
		var best := ""
		var best_deficit := -1.0
		for k in RAIDABLE:
			if int(ch["attrs"][k]) >= ATTR_CAP:
				continue
			var deficit := float(w[k]) - float(spent[k]) * float(total) / float(pts + spent_total(spent))
			if deficit > best_deficit:
				best_deficit = deficit
				best = k
		if best == "":                  # 四屬全部到 99
			break
		spent[best] = int(spent[best]) + 1
		pts -= 1
	for k in RAIDABLE:
		if int(spent[k]) > 0:
			ch["attrs"][k] = int(ch["attrs"][k]) + int(spent[k])
			var raised: Dictionary = ch.get("raised", {})
			ch["raised"] = raised
			raised[k] = int(raised.get(k, 0)) + int(spent[k])
	ch["attrPoints"] = pts


static func spent_total(spent: Dictionary) -> int:
	var t := 0
	for k in spent:
		t += int(spent[k])
	return t


