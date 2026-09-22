class_name NpcMemory
extends RefCounted
# NPC 記憶表【自訂】(Step 5.2 R1): 結構化事件 + 好感值，唔存成句聊天記錄。
# 淨係規則層，Step 6 LLM 摘要/措辭會再讀呢個表，但唔喺呢層改。

const CAP := 12                # 每個 NPC 最多記幾多件事，舊事件被擠走 (定期摘要前嘅簡化版)
const AFFINITY_MIN := -100
const AFFINITY_MAX := 100


static func init_memory() -> Dictionary:
	return {"affinity": {}, "events": []}


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
