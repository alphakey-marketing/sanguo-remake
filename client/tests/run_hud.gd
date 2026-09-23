extends SceneTree
# 手機 HUD 版面測試: 各種屏幕比例 + 瀏海安全區下，掣夠大、唔重疊、唔出界、唔入搖桿區；hit() 判定啱。
# 跑: Godot --headless --path client --script tests/run_hud.gd   (失敗 exit 1)

var fails := 0
var total := 0

const SIZES := [Vector2(640, 360), Vector2(720, 360), Vector2(800, 360), Vector2(853, 360), Vector2(640, 480)]
const SAFES := [Vector4(0, 0, 0, 0), Vector4(32, 0, 0, 0), Vector4(0, 0, 32, 0), Vector4(24, 0, 24, 10)]   # 左/上/右/下 inset


func _init() -> void:
	for s in SIZES:
		for ins in SAFES:
			t_layout(s, ins)
	t_hit()
	print("[TEST] hud: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


func t_layout(size: Vector2, ins: Vector4) -> void:
	var safe := Rect2(ins.x, ins.y, size.x - ins.x - ins.z, size.y - ins.y - ins.w)
	var lay := HudLayout.build(size, safe)
	var tag := "%s inset%s" % [size, ins]
	var ids: Array = lay.keys()
	var joy := HudLayout.joy_zone(size, safe)
	for id in ids:
		var el: Dictionary = lay[id]
		var b := HudLayout.bounds(el)
		check(b.size.x >= HudLayout.MIN_TOUCH and b.size.y >= HudLayout.MIN_TOUCH, "%s %s 太細 %s" % [tag, id, b.size])
		check(safe.encloses(b), "%s %s 出咗安全區 %s" % [tag, id, b])
		check(not joy.intersects(b), "%s %s 入咗搖桿區" % [tag, id])
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			check(not HudLayout.overlaps(lay[ids[i]], lay[ids[j]]), "%s %s 同 %s 重疊" % [tag, ids[i], ids[j]])
	check(joy.size.x >= 200 and joy.size.y >= 150, "%s 搖桿區太細 %s" % [tag, joy.size])
	check(not joy.intersects(HudLayout.log_rect(safe)), "%s 日誌入咗搖桿區" % tag)


func t_hit() -> void:
	var lay := HudLayout.build(Vector2(640, 360))
	var ids := ["attack", "skill0", "skill1", "skill2", "skill3", "target", "auto", "context"] + HudLayout.MENU
	for id in ids:
		var b := HudLayout.bounds(lay[id])
		check(HudLayout.hit(lay, ids, b.get_center()) == id, "撳 %s 中心應該中 %s" % [id, id])
	# 圓形掣: bounds 角位唔算中（舊版方形判定 bug）
	var ab := HudLayout.bounds(lay["attack"])
	check(HudLayout.hit(lay, ["attack"], ab.position + Vector2(2, 2)) == "", "普攻圓外角位唔應該中")
	# 隱藏咗嘅掣唔會中
	var c: Vector2 = lay["skill0"]["c"]
	check(HudLayout.hit(lay, ["attack"], c) == "", "唔喺 ids 嘅掣唔應該中")
