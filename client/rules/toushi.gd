class_name RulesToushi
extends RefCounted
# 美女特技「透視」(S02c, spec 02 §6)【自訂】單機化:
#   - 對喺範圍內嘅 NPC/怪物用 -> 顯示隱藏資訊（HP/MP/等級/弱點屬性），喺戰鬥有優勢。
#   - 戰鬥優勢【自訂】：透視後玩家入「洞悉」(insight) 狀態，一時間物攻 +20%（見 RulesSpell.atk_mult）。
#   - 弱點屬性 = 剋住目標嗰個元素（地剋水、水剋火、火剋風、風剋地；無屬性 -> 冇弱點）。
# 純函數，無狀態；目標揀定（最近嗰隻喺範圍內）由 sim 用 sim 權威判定，呢度提供查詢。
# 時間換算: world.clock.gameMinPerTick = 2 → insight 150 tick ≈ 5 game 小時；CD 180 tick ≈ 6 game 小時


const TOUSHI_RANGE := 6          # 要幾近先透視到 (切比雪夫距離格)
const TOUSHI_CD_TICKS := 180     # 透視冷卻 (tick)
const INSIGHT_TICKS := 150       # 洞悉持續 (tick)


# 目標元素嘅弱點屬性：邊個屬性剋目標（空 = 冇弱點）【原 地剋水水剋火火剋風風剋地】
static func weakness_of(elem: String) -> String:
	return str(RulesSpell.BEATS.get(elem, ""))


# 洞悉狀態查詢: status 用 "insight" id 記 until_tick
static func is_insight(status: Dictionary, tick: int) -> bool:
	return RulesSpell.has(status, "insight", tick)