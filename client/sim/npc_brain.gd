class_name NpcBrain
extends RefCounted
# NPC「brain」介面(Step 5.4)：規則層(sim)已經結算晒數值 (好感/善惡)，brain 淨係憑呢啲
# 已結算嘅資料揀一個白名單動作 + 生成一句話，唔會、亦冇能力改任何數值。
# 依家(規則版) = 離線後備本身；Step 6 加 LLM 實作，一樣要遵守呢個介面、輸出一樣要喺白名單入面，
# sim.gd 淨係識呢個介面，換 LLM 實作嗰陣唔使改 sim.gd。

const ACTIONS := ["greet", "warn", "ignore"]      # 動作白名單，非法/唔識嘅一律 fallback "ignore"

const LINES_WARM := ["%s又嚟喇，多謝幫手", "見到%s心情都好啲"]
const LINES_NEUTRAL := ["你好，%s"]
const LINES_WARN_KARMA := ["你...你唔好埋嚟！", "衛兵！呢個唔係好人！"]
const LINES_WARN_AFFINITY := ["走開，我唔想同你講嘢"]


# S09 居民 role 對白 (按 role 分流)；activity = eat/home/sleep/work
const ROLE_LINES := {
	"villager": ["今年收成唔錯，%s", "田裏面仲有好多嘢要做"],
	"merchant": ["%s，睇下有冇啱心水嘅貨？", "生意難做，物價成日變"],
	"guard": ["%s，城內唔准鬧事", "我哋日夜巡邏，有事就叫我"],
	"stableman": ["%s，想睇匹好馬？", "馬要好好照顧先跑得快"],
	"official": ["%s，朝廷事務繁忙", "有功之人，官宅自有嘉獎"],
}
const ACTIVITY_LINES := {"eat": "食緊飯，遲啲再傾", "sleep": "好眼瞓……", "home": "收工返屋企先"}


# ctx: {actor_name: String, affinity: int, karma_tier: int(0大英雄..6殺人魔)}
# pick_idx: 揀邊句 line 用（外面由種子 RNG 揀，保持決定性），自動 wrap 入池
# 回傳 {"action": <白名單內>, "line": String}；action 一定喺 ACTIONS 入面
static func decide(ctx: Dictionary, pick_idx: int = 0) -> Dictionary:
	var name: String = ctx.get("actor_name", "")
	var aff := int(ctx.get("affinity", 0))
	var karma_tier := int(ctx.get("karma_tier", 3))
	var action := "greet"
	var pool := LINES_NEUTRAL
	if karma_tier >= 5:                          # 惡人/殺人魔: 見到就驚
		action = "warn"
		pool = LINES_WARN_KARMA
	elif aff <= -20:
		action = "warn"
		pool = LINES_WARN_AFFINITY
	elif aff >= 10:
		pool = LINES_WARM
	var tpl: String = pool[pick_idx % pool.size()]
	var line := tpl % name if tpl.contains("%s") else tpl
	if action == "greet" and aff < 10:
		var role := String(ctx.get("role", ""))
		var act := String(ctx.get("activity", ""))
		if ACTIVITY_LINES.has(act) and pick_idx % 3 == 0:
			line = ACTIVITY_LINES[act]
		elif ROLE_LINES.has(role) and pick_idx % 2 == 1:
			var rp: Array = ROLE_LINES[role]
			var rt: String = rp[(pick_idx / 2) % rp.size()]
			line = rt % name if rt.contains("%s") else rt
	if not ACTIONS.has(action):
		action = "ignore"
	return {"action": action, "line": line}
