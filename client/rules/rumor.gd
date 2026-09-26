class_name RulesRumor
extends RefCounted
# 傳聞擴散規則層 (S09b, spec 09 §4): 顯著目擊事件 → 傳聞 → 同城交換 + 跨城延遲 1~3 game 日。
# 純函數 + 數據驅動；隨機 (延遲) 由外面 sim 用 SimRng 抽 roll 傳入。
# 目擊事件 → 傳聞類型: kindMap = {"murder": {"neg": "killer", "pos": "bounty"}}。


static func cfg(residents: Dictionary) -> Dictionary:
	var c = residents.get("cfg", {})
	var r = (c as Dictionary).get("rumor", {}) if c is Dictionary else {}
	return r if r is Dictionary else {}


static func cap(residents: Dictionary) -> int:
	return maxi(1, int(cfg(residents).get("cap", 16)))


static func mem_cap(residents: Dictionary) -> int:
	return maxi(1, int(cfg(residents).get("memCap", 8)))


# 目擊事件 (kind + weight) → 值得傳播嘅傳聞類型；唔值得 = "" (spec 09 §4)
static func rumor_kind_of(kind: String, weight: int, residents: Dictionary) -> String:
	var km = cfg(residents).get("kindMap", {})
	if not (km is Dictionary) or not (km as Dictionary).has(kind):
		return ""
	var m = (km as Dictionary)[kind]
	if not (m is Dictionary):
		return ""
	if absi(weight) < int(cfg(residents).get("minWeight", 3)):
		return ""
	return String(m["neg"] if weight < 0 else m["pos"])


# 傳聞 key: 同一 actor + 類型 只留一條 (合併/更新)
static func rumor_key(actor: int, kind: String) -> String:
	return "%d:%s" % [actor, kind]


static func make_rumor(actor: int, kind: String, weight: int, origin: String, day: int) -> Dictionary:
	return {"key": rumor_key(actor, kind), "actor": actor, "kind": kind, "weight": weight,
		"origin": origin, "day": day, "cities": {origin: day}, "deliver": {}}


# 跨城延遲 (game 日): roll ∈ [0, span] → delayMin + roll (夾好 min/max)
static func delay(min_day: int, max_day: int, roll: int) -> int:
	var lo := maxi(0, min_day)
	var hi := maxi(lo, max_day)
	var span := hi - lo + 1
	return lo + (((roll % span) + span) % span)


static func delay_min(residents: Dictionary) -> int:
	return maxi(0, int(cfg(residents).get("delayMin", 1)))


static func delay_max(residents: Dictionary) -> int:
	return maxi(delay_min(residents), int(cfg(residents).get("delayMax", 3)))


# 傳聞會唔會傳去 target 城 (只傳去唔同城；同城即時)
static func reaches(origin: String, target: String) -> bool:
	return origin != target
