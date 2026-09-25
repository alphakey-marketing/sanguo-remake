class_name RulesQieting
extends RefCounted
# 辯士特技「竊聽」(S02c, spec 02 §6【自訂】單機化):
#   - 喺居民側邊竊聽對話 -> 得任務情報：傳聞線索（耳邊「…」）。
#   - 居民 = 附近 bot（野區居民，見 bot_sys.gd）或者附近任務 NPC（master 等）。
#   - 竊聽到 -> 記入 ch.rumors（情報冊，持久存檔），設冷卻。
# 純函數，無狀態；傳聞內容 = data.rumors (list)；揀邊條由 sim 用 SimRng，sim 權威判定。

const QIETING_RANGE := 3       # 要幾近先竊聽到 (切比雪夫距離格)
const QIETING_CD_TICKS := 300  # 竊聽冷卻 (tick；1440 tick = 1 game 日)


# 呢條傳聞聽過未（按內容去重）
static func heard(ch: Dictionary, line: String) -> bool:
	return (ch.get("rumors", []) as Array).has(line)


# 揀一條未聽過嘅傳聞（全聽晒先重複），rng 揀位保決定性
static func pick_unheard(data: GameData, ch: Dictionary, rng: Callable) -> String:
	var pool: Array = data.rumors
	if pool.is_empty():
		return ""
	var seen: Array = ch.get("rumors", [])
	if seen.size() < pool.size():
		# 未聽晒: 喺未聽嗰啲入面用 rng 揀 (保決定性, 唔靠 seen 次序)
		var unseen: Array = []
		for i in pool.size():
			if not seen.has(String(pool[i])):
				unseen.append(i)
		if not unseen.is_empty():
			var k := int(floor(MathX.roll(rng) * unseen.size()))
			return String(pool[unseen[k]])
	# 全聽晒: 隨機重複
	var idx := int(floor(MathX.roll(rng) * pool.size()))
	return String(pool[idx])