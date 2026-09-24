class_name RulesTiandi
extends RefCounted
# 天地商行自動化 + 捐贈官令 純函數 (Step 13, spec 05 §3/§7, spec 08 §1)
# 【原】= 功能/捐獻轉換率表；【自訂】= 負重改件數、名聲/魅力經驗比率 (數值見 world.json tiandi、data/donation.json)
# bag/storage = [{id, n}]；mat_skill = 材料 item id -> 初階技能 key


# 一堆物品總件數
static func stack_total(arr: Array) -> int:
	var t := 0
	for s in arr:
		t += int(s["n"])
	return t


# 背包入面工作材料總件數 (= 負重【自訂】)
static func mat_load(bag: Array, mat_skill: Dictionary) -> int:
	var t := 0
	for s in bag:
		if mat_skill.has(int(s["id"])):
			t += int(s["n"])
	return t


# 負重滿 → 腳伕搬晒背包材料【原】: 勾咗嘅技能 → 入倉 (到倉滿為止)；冇勾 / 入唔落 → 賣市集
# 回傳 {deposit: [[id, n]], sell: [[id, n]]}，按背包次序 (決定性)
static func plan_haul(bag: Array, mat_skill: Dictionary, deposit_skills: Array, storage_used: int, storage_cap: int) -> Dictionary:
	var dep: Array = []
	var sell: Array = []
	var room := maxi(0, storage_cap - storage_used)
	for s in bag:
		var id := int(s["id"])
		var n := int(s["n"])
		if not mat_skill.has(id) or n <= 0:
			continue
		var put := 0
		if deposit_skills.has(String(mat_skill[id])):
			put = mini(n, room)
			room -= put
		if put > 0:
			dep.append([id, put])
		if n - put > 0:
			sell.append([id, n - put])
	return {"deposit": dep, "sell": sell}


# 工具轉賣價【自訂】= 原價 × 耐久% / 2
static func tool_resale(price: int, dur: int, max_dur: int) -> int:
	if max_dur <= 0:
		return 0
	return int(floor(float(price) * float(clampi(dur, 0, max_dur)) / float(max_dur) / 2.0))


# ---- 捐贈官令 ----

# 捐金錢範圍【原】3000~50000
static func gold_ok(gold: int, cfg: Dictionary) -> bool:
	return gold >= int(cfg["goldMin"]) and gold <= int(cfg["goldMax"])


# 物資 → 捐獻單位【原】: counts = {item id: n}，rates = {item id: 單位}；表外物品 = 0
static func donation_units(counts: Dictionary, rates: Dictionary) -> int:
	var t := 0
	for k in counts:
		t += int(counts[k]) * int(rates.get(int(k), 0))
	return t


# 名聲【自訂】: kind = "gold" (金錢) / "units" (捐獻單位)
static func donation_fame(kind: String, amount: int, cfg: Dictionary) -> int:
	var per := int(cfg["goldPerFame"]) if kind == "gold" else int(cfg["unitsPerFame"])
	return amount / maxi(1, per)


# 魅力經驗【自訂】: 每 chaExpPerPoint 經驗魅力 +1，到 chaCap 停 (exp 歸 0)。回傳 {cha, exp, ups}
static func cha_gain(cha: int, cur_exp: int, add: int, cfg: Dictionary) -> Dictionary:
	var per := maxi(1, int(cfg["chaExpPerPoint"]))
	var cap := int(cfg["chaCap"])
	var ups := 0
	cur_exp += add
	while cha < cap and cur_exp >= per:
		cur_exp -= per
		cha += 1
		ups += 1
	if cha >= cap:
		cur_exp = 0
	return {"cha": cha, "exp": cur_exp, "ups": ups}
