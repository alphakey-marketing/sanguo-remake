class_name RulesGuard
extends RefCounted
# 捕快 NPC 純函數【自訂】: 每城 2 隻 50~75 級，日間時辰巡邏、其餘時辰企定位、見紅名罪犯主動追打。
# 設定喺 data/guards.json cfg。

static func cfg(guards: Dictionary) -> Dictionary:
	return guards.get("cfg", {})


# 第 idx 隻 (0-based) 嘅等級: perCity 隻平均分佈喺 [levelMin, levelMax]
static func level_of(g: Dictionary, idx: int, per_city: int) -> int:
	var lo := int(g.get("levelMin", 50))
	var hi := int(g.get("levelMax", 75))
	if per_city <= 1:
		return lo
	return lo + int(round(float(hi - lo) * float(idx) / float(per_city - 1)))


# 而家時辰係咪巡邏時辰 (否則企定位)
static func is_patrol_time(g: Dictionary, shichen: int) -> bool:
	var ps: Array = g.get("patrolShichen", [])
	for s in ps:      # JSON 載入整數變 float (3.0)，Array.has(int) 唔可靠 → 逐個 int 比
		if int(s) == shichen:
			return true
	return false


# 企定位: 客棧座標 + 固定偏移 (唔係城門口)
static func stand_pos(inn_x: int, inn_y: int, g: Dictionary) -> Vector2i:
	var off: Array = g.get("standOffset", [3, 3])
	return Vector2i(inn_x + int(off[0]), inn_y + int(off[1]))


# 巡邏點: 以企定位為中心，順序行 4 個方向點 (決定性循環，唔使額外 rng)
static func patrol_point(stand: Vector2i, radius: int, step: int) -> Vector2i:
	var pts := [
		Vector2i(stand.x + radius, stand.y),
		Vector2i(stand.x, stand.y + radius),
		Vector2i(stand.x - radius, stand.y),
		Vector2i(stand.x, stand.y - radius),
	]
	return pts[step % pts.size()]


# 罪犯喺 aggroRange 內 → 主動鎖定 (玩家或居民都算，唔理安全區——捕快喺城入面照打)
static func in_aggro_range(gx: int, gy: int, tx: int, ty: int, g: Dictionary) -> bool:
	var d := maxi(absi(gx - tx), absi(gy - ty))
	return d <= int(g.get("aggroRange", 10))


# 紅名罪犯判定: 居民睇 ch.criminal 旗；玩家睇善惡階 = 殺人魔 (tier 6, ≤ -16001，同城門拒入一致)
static func is_red_target(ch: Dictionary, is_player: bool) -> bool:
	if is_player:
		return RulesKarma.tier(int(ch.get("karma", 0))) == 6
	return bool(ch.get("criminal", false))
