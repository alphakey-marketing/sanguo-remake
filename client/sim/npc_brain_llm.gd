class_name NpcBrainLlm
extends RefCounted
# LLM 版 NPC brain (S09d, spec 09 §5)。同 `NpcBrain` 一樣嘅 `decide(ctx, pick_idx)` 介面，
# sim 只識呢個介面；換 LLM/模板唔使改 sim。
#   - `decide()` = 離線模板後備（純規則，永遠有嘢回）
#   - `decide_with()` = 有 LLM 回應文字時，用 `RulesLlm.parse_response` 揀動作；解析唔到就 fallback
# 兩者輸出都一定係白名單動作；**唔會、亦冇能力改任何數值**（數值只由 `RulesLlm.effect_of()` 決定）。

const ACTIONS := ["greet", "warn", "ignore", "acceptQuest", "hint", "rumor", "refuse"]

const LINES_WARM := ["%s又嚟喇，多謝幫手", "見到%s心情都好啲"]
const LINES_NEUTRAL := ["你好，%s"]
const LINES_WARN_KARMA := ["你...你唔好埋嚟！", "衛兵！呢個唔係好人！"]
const LINES_WARN_AFFINITY := ["走開，我唔想同你講嘢"]
const LINES_RUMOR := ["我聽講%s嘅事架", "你最近好出名喎，%s"]
const LINES_REFUSE := ["唔好意思，我唔想插手"]
const LINES_HINT := ["%s，你去東邊睇下"]
const LINES_ACCEPT := ["好，%s拜託嘅事我應承"]


static func _pick(pool: Array, pick_idx: int) -> String:
	return String(pool[maxi(0, pick_idx) % pool.size()])


# ctx: 同 NpcBrain.decide 相容，另外可選 tier / ideology / rumor_kind / quest_hint
static func decide(ctx: Dictionary, pick_idx: int = 0) -> Dictionary:
	var name := String(ctx.get("actor_name", ""))
	var aff := int(ctx.get("affinity", 0))
	var karma_tier := int(ctx.get("karma_tier", 3))
	var action := "greet"
	var pool := LINES_NEUTRAL
	if karma_tier >= 5:                                  # 惡人/殺人魔: 見到就驚
		action = "warn"
		pool = LINES_WARN_KARMA
	elif aff <= -20:                                     # 憎: 拒絕
		action = "refuse"
		pool = LINES_REFUSE
	elif aff >= 40 and String(ctx.get("rumor_kind", "")) != "":   # 熟 + 有傳聞: 講八卦
		action = "rumor"
		pool = LINES_RUMOR
	elif aff >= 10:
		pool = LINES_WARM
	elif aff >= 0 and String(ctx.get("quest_hint", "")) != "":
		action = "hint"
		pool = LINES_HINT
	var tpl := _pick(pool, pick_idx)
	var line := tpl % name if tpl.contains("%s") else tpl
	if not ACTIONS.has(action):
		action = "ignore"
	return {"action": action, "line": line}


# 有 LLM 回應文字: 解析成功（動作喺白名單）用 LLM 結果，否則 fallback 模板
static func decide_with(cfg: Dictionary, ctx: Dictionary, pick_idx: int, text: String) -> Dictionary:
	var parsed := RulesLlm.parse_response(cfg, text)
	if parsed.is_empty():
		return decide(ctx, pick_idx)
	if not ACTIONS.has(String(parsed["action"])):
		return decide(ctx, pick_idx)
	return parsed