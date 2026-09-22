class_name RulesStats
extends RefCounted
# 屬性/成長/經驗。全部【自訂】數值（攻略只講「升級時武/智/敏/靈提升」、「5 級脫新手」）
# attrs = {str, agi, int, spi, pol, cha}；character = Dictionary（可直接序列化）

const NEWBIE_LEVEL := 5    # 【原】5 級脫離新手
const MAX_LEVEL := 100     # 【原】三轉 100 級
const ATTR_KEYS := ["str", "agi", "int", "spi", "pol", "cha"]


static func max_hp(lv: int, a: Dictionary) -> int:
	return int(60 + lv * 15 + a["str"] * 4)


static func max_mp(lv: int, a: Dictionary) -> int:
	return int(20 + lv * 5 + a["spi"] * 3 + a["int"] * 2)


static func max_sp(lv: int, a: Dictionary) -> int:
	return int(50 + lv * 3 + a["agi"] * 2)


# 升到下一級所需經驗
static func exp_to_next(lv: int) -> int:
	return MathX.js_round(20.0 * pow(lv, 1.8))


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
	return {
		"name": char_name, "classId": class_id, "level": 1, "exp": 0, "attrs": attrs,
		"hp": max_hp(1, attrs), "mp": max_mp(1, attrs), "sp": max_sp(1, attrs),
		"gold": int(st.get("gold", 0)), "karma": 0, "bag": bag, "equip": equip,
	}


# 加經驗，可連升多級；升級回滿 HP/MP/SP。回傳升咗幾級
static func gain_exp(data: GameData, ch: Dictionary, amount: int) -> int:
	var cls: Dictionary = data.classes[ch["classId"]]
	var ups := 0
	ch["exp"] = int(ch["exp"]) + amount
	while int(ch["level"]) < MAX_LEVEL and int(ch["exp"]) >= exp_to_next(int(ch["level"])):
		ch["exp"] = int(ch["exp"]) - exp_to_next(int(ch["level"]))
		ch["level"] = int(ch["level"]) + 1
		ups += 1
	if int(ch["level"]) >= MAX_LEVEL:
		ch["exp"] = 0
	if ups > 0:
		var lv := int(ch["level"])
		ch["attrs"] = attrs_at(cls, lv)
		# 歷練【原】: 練兵場對練儲歷練，升呢時每 10 歷練 武/智/敏/靈 +1，消耗對應歷練
		var lilian := int(ch.get("lilian", 0))
		var bonus := lilian / 10
		if bonus > 0:
			for k in ["str", "agi", "int", "spi"]:
				ch["attrs"][k] = int(ch["attrs"][k]) + bonus
			ch["lilian"] = lilian - bonus * 10
		ch["hp"] = max_hp(lv, ch["attrs"])
		ch["mp"] = max_mp(lv, ch["attrs"])
		ch["sp"] = max_sp(lv, ch["attrs"])
	return ups
