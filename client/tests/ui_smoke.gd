extends Node
# 觸控 UI 煙霧測試（main.gd --uitest 會掛呢個 node）: 模擬撳 HUD 掣 / 面板掣 / 拖搖桿，驗證會發正確意圖。
# 跑: Godot --headless --path client -- --uitest   （print PASS / FAIL，exit code 反映成敗）

var m: Node
var hud: MobileHud
var fails := 0
var total := 0


func _ready() -> void:
	m = get_parent()
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("FAIL: ui smoke timeout / script error")
		get_tree().quit(1))
	_run.call_deferred()


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] ui: " + msg)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# 等條件成立（最多 secs 秒）
func until(cond: Callable, secs := 3.0) -> bool:
	var t := 0.0
	while t < secs:
		if cond.call():
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return bool(cond.call())


func center(id: String) -> Vector2:
	return HudLayout.bounds(hud.layout[id]).get_center()


func mouse(pos: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = _win(pos)
	ev.global_position = ev.position
	Input.parse_input_event(ev)


func click(pos: Vector2) -> void:
	mouse(pos, true)
	await frames(1)
	mouse(pos, false)
	await frames(2)


func touch(pos: Vector2, down: bool, idx := 0) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.pressed = down
	ev.position = _win(pos)
	Input.parse_input_event(ev)


# viewport 虛擬座標 → window 座標（Input.parse_input_event 行真實流程: _input → GUI → _unhandled_input）
func _win(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func find_btn(root: Node, prefix: String) -> Button:
	for c in root.get_children():
		if c is Button and (c as Button).text.begins_with(prefix) and (c as Button).is_visible_in_tree():
			return c
		var r := find_btn(c, prefix)
		if r != null:
			return r
	return null


func press(root: Node, prefix: String) -> bool:
	var b := find_btn(root, prefix)
	if b == null or b.disabled:
		print("  (搵唔到/用唔到掣: %s)" % prefix)
		return false
	b.pressed.emit()
	return true


func put(x: int, y: int) -> void:
	var e: Dictionary = m.sim.ent(m.my_id)
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y
	m.target_id = -1
	m._send({"t": "move", "x": x, "y": y})     # 取消追怪
	m._refresh()


func _run() -> void:
	await frames(3)
	hud = m.hud
	var ch: Dictionary = m.ch
	# 1. 選單列: 背包 / 角色(頭像) / 記事 / 更多
	await click(center("menu_bag"))
	check(hud.any_panel_open() and hud.panels["bag"].visible, "撳背包掣應該開背包面板")
	hud.close_panels()
	await click(center("portrait"))
	check(hud.panels.has("char") and hud.panels["char"].visible, "撳頭像應該開角色面板")
	# 2. 面板開住: 世界唔會收到點擊（唔會行路）
	var e0: Dictionary = m.sim.ent(m.my_id)
	var tx0 := int(e0["tx"])
	mouse(Vector2(20, 300), true)
	await frames(2)
	mouse(Vector2(20, 300), false)
	check(int(m.sim.ent(m.my_id)["tx"]) == tx0, "面板開住唔應該行路")
	# 3. 角色面板: ＋ 暫存，確認先送
	ch["attrPoints"] = 2
	var str0 := int(ch["attrs"]["str"])
	var cp: GamePanel = hud.panels["char"]
	cp.refresh(true)
	await frames(1)
	press(cp, "＋")
	await frames(1)
	check(int(ch["attrs"]["str"]) == str0, "＋ 未確認唔應該改屬性")
	press(cp, "確認分配")
	await frames(1)
	check(int(ch["attrs"]["str"]) == str0 + 1 and int(ch["attrPoints"]) == 1, "確認分配後武力 +1 (而家 %d)" % int(ch["attrs"]["str"]))
	hud.close_panels()
	# 4. 行近武器店 → 互動掣 = 商店 → 揀貨 → 確認買入
	put(20, 7)
	check(await until(func() -> bool: return String(hud.ctx.get("kind", "")) == "shop"), "近武器店互動掣應該係商店 (%s)" % hud.ctx)
	await click(center("context"))
	var sp: GamePanel = hud.panels.get("shop")
	check(sp != null and sp.visible, "撳互動掣應該開商店")
	if sp != null:
		ch["gold"] = 5000
		sp.refresh(true)
		press(sp, m.item_names[10001])
		await frames(1)
		var gold0 := int(ch["gold"])
		press(sp, "確認買入")
		await frames(1)
		check(int(ch["gold"]) < gold0 and RulesShop.has_item(ch["bag"], 10001, 1), "確認買入應該扣錢入背包")
	hud.close_panels()
	# 5. 背包: 揀武器 → 裝備（玩家自己撳）
	ch["equip"]["weapon"] = 0
	hud.bag_panel().open_filter("")
	var bp: BagPanel = hud.panels["bag"]
	await frames(1)
	press(bp, m.item_names[10001].substr(0, 4))
	await frames(1)
	press(bp, "裝備武器")
	await frames(1)
	check(int(ch["equip"]["weapon"]) == 10001, "背包撳裝備武器應該裝上")
	hud.close_panels()
	# 6. 客棧對話框: 休息扣錢
	put(10, 6)
	check(await until(func() -> bool: return String(hud.ctx.get("kind", "")) == "inn"), "近客棧互動掣應該係客棧 (%s)" % hud.ctx)
	await click(center("context"))
	var dp: GamePanel = hud.panels.get("dialog")
	check(dp != null and dp.visible, "客棧應該開對話框")
	if dp != null:
		var g1 := int(ch["gold"])
		press(dp, "休息")
		await frames(1)
		check(int(ch["gold"]) == g1 - int(m.inn_cost), "休息應該扣住宿費")
	hud.close_panels()
	# 7. 觸控路徑: 放手先發 / 滑走取消
	touch(center("menu_quest"), true)
	await frames(1)
	check(not hud.any_panel_open(), "選單掣撳落未放手唔應該開")
	touch(center("menu_quest"), false)
	await frames(1)
	check(hud.panels.has("quest") and hud.panels["quest"].visible, "觸控放手應該開記事")
	hud.close_panels()
	touch(center("menu_more"), true)
	await frames(1)
	touch(Vector2(320, 200), false)
	await frames(1)
	check(not hud.any_panel_open(), "撳落再滑走放手應該取消")
	# 8. 按住普攻 = 連打（計發幾多次）
	var n := [0]
	var cb := func() -> void: n[0] += 1
	hud.attack_pressed.connect(cb)
	touch(center("attack"), true, 1)
	await until(func() -> bool: return n[0] >= 3, 3.0)
	touch(center("attack"), false, 1)
	hud.attack_pressed.disconnect(cb)
	check(n[0] >= 3, "按住普攻應該連發 (得 %d)" % n[0])
	# 9. 搖桿: 喺搖桿區拖右 → 方向向右；拉出圈外底座跟手
	var z: Rect2 = hud.joy.zone
	var p0 := z.get_center()
	touch(p0, true, 2)
	var dr := InputEventScreenDrag.new()
	dr.index = 2
	dr.position = _win(p0 + Vector2(120, 0))
	Input.parse_input_event(dr)
	await frames(1)
	check(hud.joy_active() and hud.joy_dir().x > 0.9, "搖桿拖右應該向右 (%s)" % hud.joy_dir())
	check(hud.joy.base.x > p0.x, "拉出圈外底座應該跟手")
	touch(p0 + Vector2(120, 0), false, 2)
	await frames(1)
	check(not hud.joy_active(), "放手搖桿應該停")
	# 10. 點遠處設施 → 自動行過去 → 到咗開面板
	put(20, 14)
	await frames(2)
	var shop_screen: Vector2 = Vector2(20, 5) * m.TILE + Vector2(m.TILE, m.TILE) * 0.5 - m.cam
	await click(shop_screen)
	check(not m.pending.is_empty(), "點遠處商店應該記住 pending 行過去")
	check(await until(func() -> bool: return hud.panels.has("shop") and hud.panels["shop"].visible, 15.0), "行到商店應該自動開商店面板")
	hud.close_panels()
	print("[TEST] ui_smoke: %d, fail %d" % [total, fails])
	print("PASS: ui smoke" if fails == 0 else "FAIL: ui smoke")
	get_tree().quit(1 if fails > 0 else 0)

