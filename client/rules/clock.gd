class_name RulesClock
extends RefCounted
# 世界時鐘純函數【自訂】: 十二時辰×8 刻 = 96 刻/日; 四季 30 日/季。
# 所有函數無狀態，輸入參數 → 輸出，方便測試。

const MIN_PER_DAY := 1440
const MIN_PER_KE := 15
const SHICHEN_NAMES := ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
const SEASON_NAMES := ["春", "夏", "秋", "冬"]


# 由 tick 推 game 分鐘 (每日 = 1440 game 分)
static func game_minutes(tick: int, game_min_per_tick: int) -> int:
	return tick * game_min_per_tick


static func ke_of_tick(tick: int, game_min_per_tick: int) -> int:
	return (game_minutes(tick, game_min_per_tick) / MIN_PER_KE) % 96


static func day_of_tick(tick: int, game_min_per_tick: int) -> int:
	return game_minutes(tick, game_min_per_tick) / MIN_PER_DAY


# 時辰 index 0(子)~11(亥)
static func shichen_of_ke(ke: int) -> int:
	return (ke / 8) % 12


static func season_of_day(day: int, season_days: int) -> int:
	return (day / season_days) % 4


static func is_night(ke: int, night_start_ke: int, night_end_ke: int) -> bool:
	if night_start_ke <= night_end_ke:
		return ke >= night_start_ke and ke < night_end_ke
	return ke >= night_start_ke or ke < night_end_ke


# 顯示: "午時 3 刻"  (第 ke_in_shichen 刻, 1 起)
static func format_ke(ke: int) -> String:
	var shi := shichen_of_ke(ke)
	return "%s時 %d 刻" % [SHICHEN_NAMES[shi], (ke % 8) + 1]


static func format(ke: int, day: int, season_days: int) -> String:
	return "%s · 第 %d 日 · %s" % [format_ke(ke), day + 1, SEASON_NAMES[season_of_day(day, season_days)]]