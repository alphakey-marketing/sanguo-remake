class_name RulesStealth
extends RefCounted
# 巫女特技「潛行」(S02c, spec 02 §6)【自訂】單機化:
#   - 潛行狀態 10 分鐘唔會被主動怪仇恨 (CD 1 game 日)。
#   - 啟動前要過小遊戲「行車之間穿越」: 幾卡車排隊駛過，玩家要喺每卡車之間嗰下空隙穿越。
# 時間換算: world.clock.gameMinPerTick = 2 → 10 game 分鐘 = 5 tick；1 game 日 = 1440 分 = 720 tick。
# 純函數，無狀態；模式 (車空隙 offset) 由 sim 用 SimRng 生成，sim 權威判定，呢度提供查詢。


const STEALTH_TICKS := 5         # 潛行持續 10 分鐘 => 5 tick (gameMinPerTick=2)
const STEALTH_CD_TICKS := 720    # CD 1 game 日 => 720 tick

const GAP_COUNT := 3             # 要穿過幾多卡車之間
const CART_PERIOD := 10          # 每卡車週期 tick (車 + 空隙)
const GAP_W := 3                 # 每卡車之間安全空隙 tick 長


# RNG 生成每卡車空隙於其週期入面嘅 offset (0~週期-GAP_W)。全部 ∪ 逐卡車順序穿越。
# rng = Callable 回傳 [0,1) (sim 傳 rng_fn, seeds SimRng)。
static func make_pattern(rng: Callable) -> Array:
	var out: Array = []
	var span := CART_PERIOD - GAP_W + 1
	for i in GAP_COUNT:
		out.append(int(floor(MathX.roll(rng) * span)))
	return out


# 咖 gap 嘅安全窗 [t0, t0+GAP_W) (t0 = start + i*CART_PERIOD + offset[i])
static func gap_open(pattern: Array, start: int, idx: int, now: int) -> bool:
	if idx < 0 or idx >= GAP_COUNT:
		return false
	var off := int(pattern[idx])
	var t0 := start + idx * CART_PERIOD + off
	return now >= t0 and now < t0 + GAP_W


# 穿越一次: 喺現時咖 gap (第 crossed 個) 穿越成功?
static func cross_pattern(pattern: Array, start: int, crossed: int, now: int) -> bool:
	return gap_open(pattern, start, crossed, now)


# 潛行狀態查詢: status 用 "stealth" id 記 until_tick
static func is_stealth(status: Dictionary, tick: int) -> bool:
	return RulesSpell.has(status, "stealth", tick)