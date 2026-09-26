class_name NpcMemory
extends RefCounted
# NPC 記憶表【自訂】(Step 5.2 R1): 結構化事件 + 好感值，唔存成句聊天記錄。
# 淨係規則層，Step 6 LLM 摘要/措辭會再讀呢個表，但唔喺呢層改。

const CAP := 12                # 每個 NPC 最多記幾多件事，舊事件被擠走 (定期摘要前嘅簡化版)
const AFFINITY_MIN := -100
const AFFINITY_MAX := 100


static func init_memory() -> Dictionary:
	return {"affinity": {}, "events": [], "rumors": {}}


# 舊存檔記憶表冇 rumors 欄 → 補返 (S09b)
static func ensure(mem: Dictionary) -> void:
	if not mem.has("rumors") or not (mem["rumors"] is Dictionary):
		mem["rumors"] = {}


# 目擊/交流一件事: 記事件 + 更新對 actor_id 嘅好感 (clamp)
static func witness(mem: Dictionary, actor_id: int, kind: String, tick: int, weight: int) -> void:
	var events: Array = mem["events"]
	events.append({"actor": actor_id, "kind": kind, "tick": tick, "weight": weight})
	if events.size() > CAP:
		events.pop_front()
	var key := str(actor_id)
	var aff: Dictionary = mem["affinity"]
	aff[key] = clampi(int(aff.get(key, 0)) + weight, AFFINITY_MIN, AFFINITY_MAX)


static func affinity(mem: Dictionary, actor_id: int) -> int:
	return int(mem["affinity"].get(str(actor_id), 0))


# 傳聞 (S09b, spec 09 §4): 記入記憶表，同一 key 覆蓋；超 cap 擠走最舊 (day 最細)
static func add_rumor(mem: Dictionary, key: String, rumor: Dictionary, cap: int = 8) -> void:
	ensure(mem)
	var rs: Dictionary = mem["rumors"]
	rs[key] = {"actor": int(rumor.get("actor", 0)), "kind": String(rumor.get("kind", "")),
		"weight": int(rumor.get("weight", 0)), "origin": String(rumor.get("origin", "")),
		"day": int(rumor.get("day", 0))}
	while rs.size() > maxi(1, cap):
		var oldest := ""
		var od := 1 << 60
		for k in rs:
			if int(rs[k].get("day", 0)) < od:
				od = int(rs[k].get("day", 0))
				oldest = String(k)
		rs.erase(oldest)


static func has_rumor(mem: Dictionary, key: String) -> bool:
	return (mem.get("rumors", {}) as Dictionary).has(key)


static func rumor_of(mem: Dictionary, key: String) -> Dictionary:
	return (mem.get("rumors", {}) as Dictionary).get(key, {})


static func rumor_count(mem: Dictionary) -> int:
	return (mem.get("rumors", {}) as Dictionary).size()


static func rumor_keys(mem: Dictionary) -> Array:
	var keys: Array = (mem.get("rumors", {}) as Dictionary).keys()
	keys.sort()
	return keys
