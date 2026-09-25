class_name HudLayout
extends RefCounted
# 手機 HUD 版面（三國群英傳M 風格）: 純函數，畫同判定共用同一份，唔會再錯位。
#   左上 = 角色框（撳 = 角色面板）+ 日誌右邊同伴框（有登用同伴先顯示，撳 = 登用面板）；右上 = 選單列（背包/角色/記事/更多）+ 下面小地圖（撳 = 地圖面板）
#   左下 = 浮動搖桿區；右下 = 普攻大圓 + 技能扇形 4 格 + 切換目標 + 自動 + 互動掣 (上面 = 騎馬掣)
# 座標 = viewport 虛擬 px（640x360 起跳，aspect=expand 會變闊）。safe = 瀏海/圓角安全區（虛擬 px）。
# 每個元件: {"kind": "circle", "c": Vector2, "r": float} 或 {"kind": "rect", "rect": Rect2}
# 測試: tests/run_hud.gd（冇重疊、夠大、喺安全區內、唔入搖桿區）

const MIN_TOUCH := 44.0        # 手指最細目標 ≈ 9mm
const ATK_R := 46.0            # 普攻大圓
const SKILL_R := 22.0          # 技能圓
const SKILL_DIST := 104.0      # 技能圓心距普攻圓心 (前 4 格)
const SKILL_DIST2 := 150.0     # 額外 2 格 (S01a: 5 級後) 用大半徑，避免同前 4 格重疊
const SKILL_ANGLES := [180.0, 210.0, 240.0, 270.0, 218.0, 248.0]   # 左 → 上 扇形（Godot y 向下）；前 4 個 = 5 級前；S01a: 5 級後開埋後 2 個 (用 SKILL_DIST2)
const SMALL_R := 22.0          # 切換目標 / 自動
const MENU := ["menu_bag", "menu_char", "menu_quest", "menu_more"]
const MENU_LABELS := {"menu_bag": "背包", "menu_char": "角色", "menu_quest": "記事", "menu_more": "更多"}
const MENU_SZ := 48.0
const MENU_GAP := 4.0
const MINI_SZ := Vector2(112, 50)   # 小地圖 (spec 12 §6)
const COMP_SZ := Vector2(120, 46)   # 同伴框 (Step 13.5)


# 系統介面鍵數 (S01a, spec 01 §5): 5 級前 4 鍵，5 級後 6 鍵
static func skill_cap(level: int) -> int:
	return SKILL_ANGLES.size() if level >= GameData.NEWBIE_LEVEL else 4


static func build(size: Vector2, safe: Rect2 = Rect2()) -> Dictionary:
	if safe.size == Vector2.ZERO:
		safe = Rect2(Vector2.ZERO, size)
	var L := safe.position.x
	var T := safe.position.y
	var R := safe.end.x
	var B := safe.end.y
	var out := {}
	# 左上角色框（整塊撳得）
	out["portrait"] = {"kind": "rect", "rect": Rect2(L + 6, T + 6, 244, 98)}
	# 同伴框 (Step 13.5): 日誌右邊，搖桿區上面
	out["companion"] = {"kind": "rect", "rect": Rect2(L + 312, T + 108, COMP_SZ.x, COMP_SZ.y)}
	# 右上選單列（由右向左排）
	for i in MENU.size():
		var x := R - 6 - MENU_SZ * (i + 1) - MENU_GAP * i
		out[MENU[MENU.size() - 1 - i]] = {"kind": "rect", "rect": Rect2(x, T + 6, MENU_SZ, MENU_SZ)}
	# 小地圖: 選單列下面靠右（區名/時辰寫喺入面）
	out["minimap"] = {"kind": "rect", "rect": Rect2(R - 6 - MINI_SZ.x, T + 6 + MENU_SZ + 4, MINI_SZ.x, MINI_SZ.y)}
	# 右下戰鬥群
	var ac := Vector2(R - 74, B - 72)
	out["attack"] = {"kind": "circle", "c": ac, "r": ATK_R}
	for i in SKILL_ANGLES.size():
		var a := deg_to_rad(float(SKILL_ANGLES[i]))
		var d := SKILL_DIST if i < 4 else SKILL_DIST2
		out["skill%d" % i] = {"kind": "circle", "c": ac + Vector2(cos(a), sin(a)) * d, "r": SKILL_R}
	out["target"] = {"kind": "circle", "c": Vector2(R - 26, B - 136), "r": SMALL_R}
	out["auto"] = {"kind": "circle", "c": Vector2(R - 28, B - 214), "r": SMALL_R}
	# 互動掣（對話/商店/客棧/傳送…）: 技能扇形左邊一粒大 pill
	var s0: Vector2 = out["skill0"]["c"]
	out["context"] = {"kind": "rect", "rect": Rect2(s0.x - SKILL_R - 10 - 92, B - 72 - 26, 92, 52)}
	# 騎馬/落馬掣 (Step 17a): 互動掣上面，身邊有座騎先顯示
	var cr: Rect2 = out["context"]["rect"]
	out["mount"] = {"kind": "circle", "c": Vector2(cr.position.x + 46, cr.position.y - 30), "r": SMALL_R}
	return out


# 搖桿區: 左下，右邊界唔越過互動掣；有面板開住時 HUD 唔會路由（見 mobile_hud）
static func joy_zone(size: Vector2, safe: Rect2 = Rect2()) -> Rect2:
	if safe.size == Vector2.ZERO:
		safe = Rect2(Vector2.ZERO, size)
	var ctx: Rect2 = build(size, safe)["context"]["rect"]
	var top := safe.position.y + 156.0            # 角色框 + 日誌下面
	var right := minf(safe.position.x + size.x * 0.5, ctx.position.x - 8.0)
	return Rect2(safe.position.x, top, right - safe.position.x, safe.end.y - top)


# 日誌（唔撳得，淨係畫）: 角色框下面
static func log_rect(safe: Rect2) -> Rect2:
	return Rect2(safe.position.x + 6, safe.position.y + 108, 300, 44)


static func contains(el: Dictionary, p: Vector2) -> bool:
	if el["kind"] == "circle":
		return p.distance_to(el["c"]) <= float(el["r"])
	return (el["rect"] as Rect2).has_point(p)


static func bounds(el: Dictionary) -> Rect2:
	if el["kind"] == "circle":
		var r := float(el["r"])
		return Rect2(el["c"] - Vector2(r, r), Vector2(r, r) * 2.0)
	return el["rect"]


# 兩個元件有冇重疊（circle-circle 用距離；其餘用 bounds / 圓對矩形最近點）
static func overlaps(a: Dictionary, b: Dictionary) -> bool:
	if a["kind"] == "circle" and b["kind"] == "circle":
		return (a["c"] as Vector2).distance_to(b["c"]) < float(a["r"]) + float(b["r"])
	if a["kind"] == "circle" or b["kind"] == "circle":
		var c: Dictionary = a if a["kind"] == "circle" else b
		var r: Rect2 = (b if c == a else a)["rect"]
		var cc: Vector2 = c["c"]
		var near := Vector2(clampf(cc.x, r.position.x, r.end.x), clampf(cc.y, r.position.y, r.end.y))
		return cc.distance_to(near) < float(c["r"])
	return (a["rect"] as Rect2).intersects(b["rect"])


# 撳中邊個（ids = 目前顯示緊嘅元件；次序 = 優先）
static func hit(layout: Dictionary, ids: Array, p: Vector2) -> String:
	for id in ids:
		if layout.has(id) and contains(layout[id], p):
			return String(id)
	return ""
