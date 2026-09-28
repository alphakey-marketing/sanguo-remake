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


# 子節點有冇 Label 包含 text
func _has_text(root: Node, text: String) -> bool:
	if root is Label and (root as Label).text.contains(text):
		return true
	for c in root.get_children():
		if _has_text(c, text):
			return true
	return false


func put(x: int, y: int) -> void:
	var e: Dictionary = m.sim.ent(m.my_id)
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y
	m.target_id = -1
	m._send({"t": "move", "x": x, "y": y})     # 取消追怪
	m._refresh()


# 玩家 msg 事件計數 (S02c 特技掣冇寶箱提示驗證用)
var _msg_n := 0
var _msg_hooked := false

func _msg_count() -> int:
	if not _msg_hooked:
		_msg_hooked = true
		m.sim.event_emitted.connect(func(ev: Dictionary) -> void:
			if String(ev.get("k", "")) == "msg" and int(ev.get("dst", -1)) == m.my_id:
				_msg_n += 1)
	return _msg_n


# 互動掣而家指住邊個任務 NPC ("" = 唔係任務 NPC)
func ctx_npc() -> String:
	var r: Variant = hud.ctx.get("ref")
	if String(hud.ctx.get("kind", "")) != "quest_npc" or not r is Dictionary:
		return ""
	return str(r.get("id", ""))


# 武器店 / 客棧 門口 (全域座標, 由 data 讀)
func shop_pos() -> Vector2i:
	for sh in m.data.shops:
		if String(sh["id"]) == "weapon":
			return Vector2i(int(sh["x"]), int(sh["y"]))
	return Vector2i.ZERO


# 離 c 至少 dmin 格、最近嘅行得格
func free_away(c: Vector2i, dmin: int) -> Vector2i:
	for r in range(dmin, dmin + 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and m.sim.is_free(c.x + dx, c.y + dy):
					return Vector2i(c.x + dx, c.y + dy)
	return c


func _run() -> void:
	await frames(3)
	hud = m.hud
	# 0. 建角面板 (S01b): 姓名 → 稱號 → 生日 → 職業 → 臉譜 → 理念測驗 → 確認，撳出發先完成
	hud.open_panel("create")
	var cp: GamePanel = hud.panels["create"]
	check(cp.visible, "開建角面板應該顯示")
	var cch: Dictionary = m.ch
	var name_ed: LineEdit = (cp as CreatePanel).name_edit
	name_ed.text = "劉備"
	press(cp, "確定")
	await frames(1)
	check(str(cch.get("name", "")) == "劉備", "建角: 確定姓名後 ch.name 應該改咗 (而家 %s)" % str(cch.get("name", "")))
	cp.set_tab(1)
	var title_ed: LineEdit = (cp as CreatePanel).title_edit
	title_ed.text = "遊俠"
	press(cp, "確定")
	await frames(1)
	check(str(cch.get("title", "")) == "遊俠", "建角: 確定稱號後 ch.title 應該改咗")
	cp.set_tab(2)
	var bm0 := int(cch.get("birthMonth", 1))
	press(cp, "＋")
	await frames(1)
	check(int(cch.get("birthMonth", 1)) != bm0, "建角: 生日月＋應該改咗 birthMonth")
	cp.set_tab(4)
	var hair0 := int(cch.get("face", {}).get("hair", 1))
	press(cp, "頭髮")
	await frames(1)
	check(int(cch.get("face", {}).get("hair", 1)) != hair0, "建角: 撳臉譜部位應該循環款式")
	cp.set_tab(5)
	for i in (m.data.quiz as Array).size():
		(cp as CreatePanel)._quiz_pick(0)
		await frames(1)
	check(str(cch.get("ideology", "")) != "", "建角: 答完 12 題應該決定理念")
	check(bool(cch.get("nameLocked", false)), "建角: 理念一決定，姓名應該鎖定")
	cp.set_tab(0)
	await frames(1)
	check(not (cp as CreatePanel).body.get_children().any(func(c): return c is LineEdit), "建角: 姓名鎖定後唔應該再顯示輸入框")
	check(str(cch.get("name", "")) == "劉備", "建角: 姓名鎖定後唔可以再改")
	cp.set_tab(6)
	press(cp, "✕")
	await frames(1)
	check(cp.visible, "建角未撳出發，撳 ✕ 唔應該關到面板")
	press(cp, "出發！")
	await frames(1)
	check(not cp.visible, "建角: 撳出發後面板應該關咗")
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
	cp = hud.panels["char"]
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
	var sp0 := shop_pos()
	put(sp0.x, sp0.y + 1)
	# ctx 每 0.2s 先更新一次；put() 瞬移後要等 ctx 真正指住武器店（唔係前一步殘留嘅其他商店）
	check(await until(func() -> bool:
		var _st: Array = hud.ctx.get("ref", {}).get("stock", []) as Array
		return String(hud.ctx.get("kind", "")) == "shop" and (!_st.is_empty() and int(_st[0]) == 10001)),
		"近武器店互動掣應該係武器店 (%s)" % hud.ctx)
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
	ch["equip"]["weapons"][int(ch["equip"]["wslot"])] = 0
	ch["equip"]["weapon"] = 0
	hud.bag_panel().open_filter("")
	var bp: BagPanel = hud.panels["bag"]
	await frames(1)
	press(bp, m.item_names[10001].substr(0, 4))
	await frames(1)
	press(bp, "裝備武器")
	await frames(1)
	check(int(ch["equip"]["weapon"]) == 10001, "背包撳裝備武器應該裝上")
	# 5b. 背包: 揀防具 → 裝備（頭部）(Step 11.6)
	m._send({"t": "debug_give", "item": 16001, "n": 1})
	bp.refresh(true)
	await frames(1)
	press(bp, m.item_names[16001].substr(0, 4))
	await frames(1)
	press(bp, "裝備（")
	await frames(1)
	check(int(ch["equip"]["head"]) == 16001, "背包撳裝備防具應該著上頭部")
	hud.close_panels()
	# 5c. 角色面板裝備頁: 撳頭部格 → 卸下；撳武2 → 切換做現用
	hud.open_panel("char")
	var chp: GamePanel = hud.panels["char"]
	chp.set_tab(1)
	await frames(1)
	press(chp, "頭部")
	await frames(1)
	press(chp, "卸下")
	await frames(1)
	check(int(ch["equip"]["head"]) == 0, "裝備頁撳卸下應該卸頭部")
	press(chp, "武2")
	await frames(1)
	press(chp, "切換做現用")
	await frames(1)
	check(int(ch["equip"]["wslot"]) == 1, "裝備頁切換武器槽 2")
	m._send({"t": "switch_weapon", "wslot": 0})
	chp.set_tab(0)
	hud.close_panels()
	# 6. 客棧對話框: 休息扣錢
	put(m.sim.inn_pos.x, m.sim.inn_pos.y + 1)
	check(await until(func() -> bool: return String(hud.ctx.get("kind", "")) == "inn"), "近客棧互動掣應該係客棧 (%s)" % hud.ctx)
	await click(center("context"))
	var dp: GamePanel = hud.panels.get("dialog")
	check(dp != null and dp.visible, "客棧應該開對話框")
	if dp != null:
		ch["level"] = GameData.NEWBIE_LEVEL      # 5 級後先收住宿費 (S01a)
		var g1 := int(ch["gold"])
		press(dp, "休息")
		await frames(1)
		check(int(ch["gold"]) == g1 - int(m.inn_cost), "休息應該扣住宿費")
		ch["thirst"] = 10                           # 喝茶 (Step 14)
		dp.refresh(true)
		await frames(1)
		press(dp, "喝茶")
		await frames(1)
		check(int(ch["thirst"]) == 60, "喝茶: 飲水度 +50 (%d)" % int(ch["thirst"]))
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
	var far := free_away(sp0, 7)
	put(far.x, far.y)
	await frames(2)
	var shop_screen: Vector2 = Vector2(sp0) * m.TILE + Vector2(m.TILE, m.TILE) * 0.5 - m.cam
	await click(shop_screen)
	check(not m.pending.is_empty(), "點遠處商店應該記住 pending 行過去")
	check(await until(func() -> bool: return hud.panels.has("shop") and hud.panels["shop"].visible, 15.0), "行到商店應該自動開商店面板")
	hud.close_panels()
	# 11. 地圖面板天下頁: 撳新野 →「自動前往」→ sim 記住目的地；搖桿郁 = 取消 (Step 11.7)
	await click(center("minimap"))
	var mp = hud.panels.get("map")
	check(mp != null and mp.visible, "撳小地圖應該開地圖面板")
	mp.set_tab(1)
	mp.select_node("xinye")
	await frames(1)
	check(press(mp, "自動前往"), "天下頁揀新野應該有「自動前往」掣")
	await frames(1)
	check(String(m.sim.ent(m.my_id).get("goto", "")) == "xinye" and not hud.any_panel_open(), "自動前往: sim 記住去新野 + 關面板")
	touch(p0, true, 2)
	var dr2 := InputEventScreenDrag.new()
	dr2.index = 2
	dr2.position = _win(p0 + Vector2(0, 120))
	Input.parse_input_event(dr2)
	check(await until(func() -> bool: return not m.sim.ent(m.my_id).has("goto")), "搖桿郁應該取消自動尋路")
	touch(p0 + Vector2(0, 120), false, 2)
	await frames(1)
	# 12. 工房 (Step 12): 互動掣 → 生產面板 → 揀柳葉刀 → 製作；修理頁 → 自己修
	m._send({"t": "debug_work_lv", "add": 49})
	m._send({"t": "debug_give", "item": 26004, "n": 1})
	m._send({"t": "debug_give", "item": 25001, "n": 200})
	var wf: Dictionary = m.data.facilities["workshop"]
	put(int(wf["x"]), int(wf["y"]) + 1)
	check(await until(func() -> bool: return String(hud.ctx.get("kind", "")) == "fac"), "近工房互動掣應該係設施 (%s)" % hud.ctx)
	await click(center("context"))
	var cp2: GamePanel = hud.panels.get("craft")
	check(cp2 != null and cp2.visible, "撳互動掣應該開生產面板")
	if cp2 != null:
		check(press(cp2, "裝備鐵鎚"), "生產面板: 背包有鐵鎚應該有「裝備鐵鎚」掣")
		await frames(1)
		cp2.refresh(true)
		press(cp2, m.item_names[10001])
		await frames(1)
		var bag_w := RulesShop.count_item(ch["bag"], 25001)
		for i in 5:
			ch["sp"] = 99999
			press(cp2, "製作")
			await frames(1)
		check(RulesShop.count_item(ch["bag"], 25001) < bag_w, "撳製作應該用咗材料")
		ch["equip"]["dur"][str(int(ch["equip"]["weapon"]))] = 1
		cp2.set_tab(3)                                  # 冶鐵/修繕/木匠/修理
		await frames(1)
		press(cp2, m.item_names[int(ch["equip"]["weapon"])])
		await frames(1)
		press(cp2, "自己修理")
		await frames(1)
		var w2 := int(ch["equip"]["weapon"])
		check(int(ch["equip"]["dur"][str(w2)]) == int(m.data.weapons[w2]["max_dur"]), "修理頁: 自己修理應該回滿耐久")
	hud.close_panels()
	# 13. 許昌官宅 (Step 13/14): 互動掣 → 官宅對話框 →「捐獻…」→ 捐 3000 金 → 名聲 +3、扣行動力
	var df: Dictionary = m.data.facilities["donate_xc"]
	put(int(df["x"]), int(df["y"]) + 1)
	check(await until(func() -> bool: return String(hud.ctx.get("kind", "")) == "fac" and String(hud.ctx.get("ref", {}).get("fac", "")) == "donate_xc"),
		"近官宅互動掣應該係官宅 (%s)" % hud.ctx)
	await click(center("context"))
	var dp2: GamePanel = hud.panels.get("dialog")
	check(dp2 != null and dp2.visible, "官宅應該開對話框")
	if dp2 != null:
		ch["gold"] = 10000
		var fame0 := int(ch.get("fame", 0))
		dp2.refresh(true)
		await frames(1)
		check(press(dp2, "捐獻"), "官宅有「捐獻…」掣")
		await frames(1)
		dp2.refresh(true)
		press(dp2, "捐 3000 金")
		await frames(1)
		check(int(ch["gold"]) == 7000 and int(ch.get("fame", 0)) == fame0 + 3 and int(ch["ap"]) == 90, "撳捐 3000 金: 扣錢 + 名聲 +3 + 扣行動力")
	hud.close_panels()
	# 13b. 官宅 (Step 14): 討取頭銜 → 官令… → 接黃巾軍備動員
	await click(center("context"))
	if dp2 != null:
		ch["fame"] = 1200
		dp2.refresh(true)
		await frames(1)
		check(press(dp2, "討取「裨將軍」"), "名聲 1200: 官宅有「討取「裨將軍」」掣")
		await frames(1)
		check(int(ch.get("titleRank", 0)) == 2 and int(ch["gold"]) == 6000, "撳討取: 裨將軍 + 扣 1000 資金")
		dp2.refresh(true)
		press(dp2, "官令")
		await frames(1)
		dp2.refresh(true)
		press(dp2, "黃巾軍備動員")
		await frames(1)
		check(String(ch.get("office", {}).get("order", {}).get("id", "")) == "arms" and int(ch["ap"]) == 80, "撳官令: 接咗軍備動員、扣行動力 10")
		dp2.refresh(true)
		check(find_btn(dp2, "覆命") != null, "接咗官令: 官宅對話框有「覆命」掣")
	hud.close_panels()
	# 14. 背包「腳伕」頁 (Step 13): 訂閱後勾存採礦 + 自動買工具
	ch["storageSub"] = true
	var bp2: BagPanel = hud.bag_panel()
	bp2.open_filter("")
	bp2.set_tab(2)
	await frames(1)
	press(bp2, "　存 採礦")
	await frames(1)
	bp2.refresh(true)
	press(bp2, "　自動買工具")
	await frames(1)
	check((ch["tiandi"]["deposit"] as Array).has("mining") and bool(ch["tiandi"]["buyTool"]), "腳伕頁: 勾存採礦 + 自動買工具 (%s)" % ch.get("tiandi"))
	hud.close_panels()
	# 15. 登用 (Step 13.5): 行近典韋 → 人才對話框 → 登用面板 → 調查文官 → 問答全啱 → 同伴框 → 改指令
	ch["level"] = 5
	ch["ideology"] = "義理"
	var dw: Dictionary = {}
	for g in m.data.generals_t1:
		if String(g["name"]) == "典韋":
			dw = g
	put(int(dw["x"]) + 1, int(dw["y"]))
	check(await until(func() -> bool: return String(hud.ctx.get("kind", "")) == "general"), "近典韋互動掣應該係人才 (%s)" % hud.ctx)
	await click(center("context"))
	var dp3: GamePanel = hud.panels.get("dialog")
	check(dp3 != null and dp3.visible and press(dp3, "登用"), "人才對話框應該有「登用…」掣")
	await frames(1)
	var rp: GamePanel = hud.panels.get("recruit")
	check(rp != null and rp.visible, "撳登用應該開登用面板")
	if rp != null:
		press(rp, "調查文官")
		await frames(1)
		rp.refresh(true)
		check(press(rp, "問答"), "調查文官之後應該有候選 + 問答掣")
		await frames(1)
		for i in 10:
			var qv: Dictionary = m.sim.recruit_quiz_view()
			if qv.is_empty():
				break
			var a := 0
			for q in m.data.quiz_generals:
				if String(q["q"]) == String(qv["q"]):
					a = int(q["a"])
			rp.refresh(true)
			press(rp, "ABCD"[a] + ".")
			await frames(1)
		check(not m.sim.companion_view().is_empty(), "問答全啱應該登用到同伴")
	hud.close_panels()
	await frames(2)
	check(hud.visible_ids().has("companion"), "有同伴: HUD 顯示同伴框")
	await click(center("companion"))
	check(hud.panels.has("recruit") and hud.panels["recruit"].visible, "撳同伴框應該開登用面板")
	if rp != null:
		rp.refresh(true)
		press(rp, "主動攻擊")
		await frames(1)
		check(String(m.sim.companion_view().get("order", "")) == "active", "同伴指令: 主動攻擊")
		# 16. 登用 v2 (Step 15): 招式開關 + 贈與寶物 + 特技顯示
		rp.refresh(true)
		press(rp, "用絕招/術法")
		await frames(1)
		check(String(m.sim.companion_view().get("skillMode", "")) == "on", "同伴指令: 用絕招/術法")
		var comp_e: Dictionary = m.sim.ent(int(m.sim.companion_view()["id"]))
		put(int(comp_e["x"]) + 1, int(comp_e["y"]))
		RulesShop.add_item(ch["bag"], 54807, 1)
		rp.refresh(true)
		check(press(rp, "贈 物攻之石I"), "登用面板應該有「贈 物攻之石I」掣")
		await frames(1)
		check((m.sim.companion_view().get("treasures", []) as Array).size() == 1, "贈與寶物: 同伴寶物格 1 件")
		rp.refresh(true)
		check(_has_text(rp, "特技「"), "登用面板顯示特技")
	hud.close_panels()
	# 17. 居民委託 (Step 16): 行近賣菜嬸 → 委託對話框 → 接委託 → 記事有委託
	var cn: Dictionary = m.data.quest_npcs["citizen_1"]
	put(int(cn["x"]) + 1, int(cn["y"]))
	check(await until(func() -> bool: return ctx_npc() == "citizen_1"), "近賣菜嬸互動掣 = 對話 (%s)" % hud.ctx)
	await click(center("context"))
	var dp4: GamePanel = hud.panels.get("dialog")
	check(dp4 != null and dp4.visible and find_btn(dp4, "傾偈") != null, "委託人開委託對話框 (有「傾偈」)")
	var offer: Dictionary = m.sim.comm_offer(ch, "citizen_1")
	if dp4 != null and not offer.is_empty() and String(offer["kind"]) != "repair":
		check(press(dp4, "接委託"), "委託對話框有「接委託」掣")
		await frames(1)
		check((ch.get("comm", {}).get("active", []) as Array).size() == 1, "撳接委託: 手上 1 單")
		dp4.refresh(true)
		check(find_btn(dp4, "放棄委託") != null, "接咗: 對話框有「放棄委託」")
		hud.close_panels()
		hud.open_panel("quest")
		await frames(1)
		check(_has_text(hud.panels["quest"], "委託・賣菜嬸"), "記事顯示委託")
	elif dp4 != null:
		check(find_btn(dp4, "幫佢修") != null or offer.is_empty(), "修理委託: 有「幫佢修」掣")
	hud.close_panels()
	# 18. 武將收集冊 (Step 16): 老丈 6 石換冊 → 收入將軍令 → 背包查閱
	var lz: Dictionary = m.data.quest_npcs["laozhang"]
	put(int(lz["x"]) + 1, int(lz["y"]))
	for st in m.data.comm["book"]["stones"]:
		RulesShop.add_item(ch["bag"], int(st), 1)
	RulesShop.add_item(ch["bag"], 62093, 1)
	check(await until(func() -> bool: return ctx_npc() == "laozhang"), "近老丈互動掣 = 對話")
	await click(center("context"))
	var dp5: GamePanel = hud.panels.get("dialog")
	check(dp5 != null and press(dp5, "換收集冊"), "老丈對話框有「換收集冊」")
	await frames(1)
	check(RulesShop.count_item(ch["bag"], int(m.data.comm["book"]["item"])) == 1, "撳換收集冊: 得冊")
	dp5.refresh(true)
	check(press(dp5, "收入將軍令"), "有冊: 「收入將軍令」掣")
	await frames(1)
	check(int(ch.get("orderBook", {}).get("62093", 0)) == 1 and RulesShop.count_item(ch["bag"], 62093) == 0, "將軍令入咗冊")
	dp5.refresh(true)
	press(dp5, "查閱收集冊")
	await frames(1)
	check(_has_text(hud.panels["dialog"], "孫堅將軍令"), "查閱收集冊顯示孫堅將軍令")
	hud.close_panels()
	# 19. 驛站 (Step 16.5 B3): 行近許昌驛站 → 互動掣「驛站」→ 揀襄陽 → 扣車費去到襄陽
	var stn: Dictionary = m.data.facilities["station_xc"]
	put(int(stn["x"]), int(stn["y"]) + 1)
	check(await until(func() -> bool: return String(hud.ctx.get("label", "")) == "驛站"), "近驛站互動掣 = 驛站 (%s)" % hud.ctx)
	ch["gold"] = 1000
	await click(center("context"))
	var dp6: GamePanel = hud.panels.get("dialog")
	var fare := RulesStation.fare(m.sim.map_hops("xuchang", "xiangyang"), m.data.world["station"])
	check(dp6 != null and dp6.visible and find_btn(dp6, "襄陽驛站 (%d 金)" % fare) != null, "驛站對話框列出襄陽 (%d 金)" % fare)
	check(dp6 != null and press(dp6, "襄陽驛站"), "撳襄陽驛站")
	await frames(2)
	var me6: Dictionary = m.sim.ent(m.my_id)
	check(m.sim.map_id_at(int(me6["x"]), int(me6["y"])) == "xiangyang" and int(ch["gold"]) == 1000 - fare, "搭驛站: 去到襄陽、扣 %d 金" % fare)
	check(not dp6.visible, "搭完車對話框閂咗")
	hud.close_panels()
	# 20. 馬廄 (Step 17a): 行近許昌馬廄 → 互動掣「馬廄」→ 座騎面板馬廄頁 → 買成年馬 → HUD 騎馬掣 → 座騎頁飼養
	var stb: Dictionary = m.data.facilities["stable_xc"]
	var stp: Vector2i = m.sim._free_near(int(stb["x"]), int(stb["y"]))
	put(stp.x, stp.y)
	check(await until(func() -> bool: return String(hud.ctx.get("label", "")) == "馬廄"), "近馬廄互動掣 = 馬廄 (%s)" % hud.ctx)
	ch["gold"] = 30000
	await click(center("context"))
	var mtp: GamePanel = hud.panels.get("mount")
	check(mtp != null and mtp.visible and mtp.tab == 1, "馬廄開座騎面板馬廄頁")
	check(not ("mount" in hud.visible_ids()), "冇馬唔顯示騎馬掣")
	check(mtp != null and press(mtp, "買已養大"), "撳買成年馬")
	await frames(2)
	check((ch.get("mounts", []) as Array).size() == 1 and int(ch["gold"]) == 10000, "買咗成年馬 (20000 金)")
	hud.close_panels()
	await frames(1)
	check("mount" in hud.visible_ids(), "有馬跟身 → HUD 騎馬掣")
	await click(center("mount"))
	check(bool(ch.get("riding", false)), "撳騎馬掣 → 騎上")
	await click(center("mount"))
	check(not bool(ch.get("riding", false)), "再撳 → 落馬")
	await click(center("menu_more"))
	check(press(hud.panels["more"], "座騎"), "更多 → 座騎")
	await frames(2)
	mtp = hud.panels.get("mount")
	check(mtp.visible and mtp.tab == 0 and _has_text(mtp, "火焰紅馬"), "座騎頁顯示身邊嗰匹")
	var mood0 := int(ch["mounts"][0]["mood"])
	check(press(mtp, "玩耍"), "撳玩耍")
	await frames(2)
	check(int(ch["mounts"][0]["mood"]) > mood0, "玩耍: 情緒升")
	mtp.refresh(true)
	check(press(mtp, "餵食"), "撳餵食 → 揀道具")
	await frames(2)
	check(_has_text(mtp, "背包冇啱用嘅道具"), "冇飼料有提示")
	RulesShop.add_item(ch["bag"], 31001, 2)
	mtp.refresh(true)
	check(press(mtp, "用"), "揀乾糧用")
	await frames(2)
	check(RulesShop.count_item(ch["bag"], 31001) == 1, "餵咗一份乾糧")
	mtp.set_tab(1)
	await frames(1)
	check(press(mtp, "馬用品"), "馬廄頁 → 馬用品")
	await frames(2)
	check(hud.panels["shop"].visible, "開到馬用品店")
	hud.close_panels()
	# S02c 技能扇形: 學咗絕招逐招一格 + 職業特技掣（仕女開鎖；HUD 內容同職業無關，直接驗 slot 列表）
	m._send({"t": "debug_learn", "kind": "ult", "what": "huxiao"})
	m._send({"t": "debug_learn", "kind": "ult", "what": "jinhu"})
	ch["classSkill"] = "unlock"
	await frames(1)
	var slots: Array = hud.skill_slots()
	var n_ult := 0
	var has_skill := false
	for sl in slots:
		if String(sl["kind"]) == "ult" and str(sl["ult"]) != "":
			n_ult += 1
		if String(sl["kind"]) == "skill" and str(sl["skill"]) == "unlock":
			has_skill = true
	check(n_ult >= 2, "多絕招: 技能扇形逐招一格 (得 %d 格)" % n_ult)
	check(has_skill, "特技掣: 技能扇形有開鎖一格")
	# 撳特技掣 → 冇寶箱 → 唔會炸，出提示 (msg 事件)
	var m0 := _msg_count()
	hud.skill_pressed.emit({"kind": "skill", "skill": "unlock"})
	await frames(1)
	check(_msg_count() == m0 + 1, "撳特技掣冇寶箱 → 有提示")
	# S02c 道士超渡: 同一特技掣換 id, 撳落去 (冇同伴倒下) → 照出提示
	ch["classSkill"] = "chaodu"
	var m1 := _msg_count()
	hud.skill_pressed.emit({"kind": "skill", "skill": "chaodu"})
	await frames(1)
	check(_msg_count() == m1 + 1, "撳超渡掣冇倒下同伴 → 有提示")
	# S02c 巫女潛行: 特技掣換 id, 撳落去 (冇 CD) → 開行車 QTE (stealth_open) + 面板
	ch["classId"] = "wunu"
	ch["classSkill"] = "yinxing"
	var m2 := _msg_count()
	hud.skill_pressed.emit({"kind": "skill", "skill": "yinxing"})
	await frames(2)
	check(_msg_count() == m2 + 1, "撳潛行掣 → 有提示")
	check(hud.panels.has("stealth") and (hud.panels["stealth"] as GamePanel).visible, "潛行掣 → 開咗行車面板")
	hud.close_panels()
	# S02c-辯士 竊聽: 特技掣換 id, 撳落去 (冇居民) → 出提示 (唔炸)
	ch["classId"] = "bianshi"
	ch["classSkill"] = "qieting"
	var m3 := _msg_count()
	hud.skill_pressed.emit({"kind": "skill", "skill": "qieting"})
	await frames(1)
	check(_msg_count() == m3 + 1, "撳竊聽掣冇居民 → 有提示")
	# S02c-美女 透視: 特技掣換 id, 撳落去 → 出提示 (有目標就透視/冇就提示, 唔炸)
	ch["classId"] = "meinu"
	ch["classSkill"] = "toushi"
	var m4 := _msg_count()
	hud.skill_pressed.emit({"kind": "skill", "skill": "toushi"})
	await frames(1)
	check(_msg_count() >= m4 + 1, "撳透視掣 → 有提示")
	# S03c 死亡: 死亡算式文言 + 真實死一次 (uitest 唔彈窗但處理唔炸 + 還魂丹消耗)
	var dr_test: String = m._death_report({"exp_lost": 12, "dropped": [{"id": 65210, "n": 1}], "lucky": false, "huhushen": true, "revived": false})
	check(dr_test.contains("扣經驗 12") and dr_test.contains("跌咗物品") and dr_test.contains("護身符令經驗損失減半"), "死亡結算: _death_report 文言")
	m._send({"t": "debug_give", "item": 65030, "n": 1})
	ch["karma"] = -30000
	var died0: Array = [0]
	var pid_d: int = int(m.my_id)
	m.sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "die" and int(ev.get("dst", 0)) == pid_d:
			died0[0] += 1)
	m.sim.damage(m.sim.ent(pid_d), 99999, {})
	check(int(died0[0]) == 1, "死亡: die 事件觸發")
	check(int(ch["hp"]) > 0, "死亡: 復活返客棧 (HP>0)")
	check(int(m.sim.ent(pid_d)["x"]) == m.sim.inn_pos.x and int(m.sim.ent(pid_d)["y"]) == m.sim.inn_pos.y, "死亡: 傳返客棧")
	check(RulesShop.count_item(ch["bag"], 65030) == 0, "死亡: 還魂丹消耗")
	# S04a 地面掉落物: 殺怪跌落地 → view_ents 透出 → 互動掣=拾取 → 撳落袋 + 實體消失
	# 搵一格附近冇設施/NPC/武將嘅自由格 (確保互動掣唔會被搶)
	var pme_: Dictionary = m._me()
	var px0: int = int(pme_.get("x", 0))
	var py0: int = int(pme_.get("y", 0))
	var spot := Vector2i(px0, py0)
	var spot_ok := false
	for r in range(1, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c2 := Vector2i(px0 + dx, py0 + dy)
				if not m.sim.is_free(c2.x, c2.y):
					continue
				var mm_: Dictionary = {"x": c2.x, "y": c2.y}
				var blocked := false
				for f2 in m.facilities:
					if ContextActions._near(mm_, int(f2.x), int(f2.y)): blocked = true; break
				if blocked: continue
				for q2 in m.quest_npcs:
					if ContextActions._near(mm_, int(q2.x), int(q2.y)): blocked = true; break
				if blocked: continue
				for g2 in m.generals:
					if ContextActions._near(mm_, int(g2.x), int(g2.y)): blocked = true; break
				if not blocked:
					spot = c2
					spot_ok = true
					break
			if spot_ok:
				break
		if spot_ok:
			break
	m.sim.data.monsters[999998] = {"id": 999998, "name": "測怪", "level": 5, "hp": 50, "exp": 10,
		"gold": [0, 0], "drops": [{"item": 29042, "p": 1.0}], "rareDrops": [], "alignment": 0}
	var mm2 = m.sim._spawn_mob(999998, "field_1")
	mm2["x"] = spot.x
	mm2["y"] = spot.y
	mm2["tx"] = spot.x
	mm2["ty"] = spot.y
	m.sim.damage(mm2, 99999, m.sim.ent(int(m.my_id)))
	m.sim.data.monsters.erase(999998)
	m._refresh()
	await frames(2)
	var ditem := 0
	for e in m.ents:
		if bool(e.get("dropped", false)):
			ditem = int(e["id"])
	check(ditem != 0, "掉落: view_ents 透出 dropped 實體")
	# 行到跌落地點 → 互動掣 = 拾取
	m.sim.ent(int(m.my_id))["x"] = spot.x
	m.sim.ent(int(m.my_id))["y"] = spot.y
	m.sim.ent(int(m.my_id))["tx"] = spot.x
	m.sim.ent(int(m.my_id))["ty"] = spot.y
	m._refresh()
	var ctx_ok := await until(func() -> bool: return String(hud.ctx.get("kind", "")) == "pickup", 2.0)
	check(ctx_ok, "掉落: 企正互動掣 = 拾取 (%s)" % str(hud.ctx.get("kind", "")))
	var had_x := RulesShop.count_item(m.ch["bag"], 29042)
	m._send({"t": "pick", "drop": ditem})
	await frames(2)
	check(RulesShop.count_item(m.ch["bag"], 29042) == had_x + 1, "掉落: 撳拾取落袋")
	check(ditem > 0 and m.sim.ent(ditem).is_empty(), "掉落: 拾取後實體消失")
	# S04b 術法怪吟唱線索: 術距內 → 吟唱 → view_ents 透出 castX/castY/castSpell (UI 畫紅圈)
	var pcast_: Dictionary = m._me()
	var c2x: int = int(pcast_.get("x", 0))
	var c2y: int = int(pcast_.get("y", 0))
	var c2_ok := false
	for r in range(1, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cc := Vector2i(c2x + dx, c2y + dy)
				if m.sim.is_free(cc.x, cc.y):
					c2x = cc.x; c2y = cc.y; c2_ok = true
					break
			if c2_ok: break
		if c2_ok: break
	check(c2_ok, "吟唱線索: 揾到術法怪站位 (術距內)")
	if c2_ok:
		var csp_: Variant = m.sim._spawn_mob(1007, "field_1")   # 火之術(小) range5
		csp_["x"] = c2x; csp_["y"] = c2y; csp_["tx"] = c2x; csp_["ty"] = c2y
		var mmob: Dictionary = csp_["mob"]
		mmob["home_x"] = c2x; mmob["home_y"] = c2y
		mmob["state"] = "chase"; mmob["target"] = int(m.my_id)
		var casting_seen := false
		for _i in 14:
			m.sim.step()
			for e in m.sim.view_ents():
				if int(e["id"]) == int(csp_["id"]) and bool(e.get("casting", false)) \
						and String(e.get("castSpell", "")) == "huo_s":
					casting_seen = true
			if casting_seen: break
		check(casting_seen, "吟唱線索: 術法怪吟唱中 + castSpell 透出")
		if not m.sim.ent(int(csp_["id"])).is_empty():
			m.sim.damage(m.sim.ent(int(csp_["id"])), 99999, m.sim.ent(int(m.my_id)))
	# S04c 戰役：記事「戰役」tab + 大地圖標示底下嘅 read-model (view_battles)
	m.sim.state["clock"]["ke"] = 0          # 子時 = 褚飛燕窗
	var vb: Dictionary = m.sim.view_battles(int(m.my_id))
	check((vb["list"] as Array).size() == 6, "戰役: view_battles 回 6 場日程")
	check(String(vb["open"]) == "chufeiyan", "戰役: 子時開褚飛燕窗 (%s)" % str(vb["open"]))
	hud.open_panel("quest")
	var qpb: GamePanel = hud.panels["quest"]
	qpb.set_tab(2)                            # 記事「戰役」頁
	qpb.refresh(true)
	await frames(2)
	check(qpb.tab == 2, "戰役: 記事切到戰役 tab")
	hud.close_panels()
	m.sim.state["clock"]["ke"] = 90         # 窗與窗之間 → view_battles open 空
	check(String(m.sim.view_battles(int(m.my_id))["open"]).is_empty(), "戰役: 冇窗口時 open 空")
	# S04d 特殊場景：記事「場景」tab + 入口對話 + 入場/離場煙霧
	m.sim.state["clock"]["day"] = 0          # 初一 = 桃花渡/七彩奪寶陣開門
	var vs: Dictionary = m.sim.view_scenes(int(m.my_id))
	check((vs["list"] as Array).size() == 2, "場景: view_scenes 回 2 個特殊場景")
	hud.open_panel("quest")
	var qpb2: GamePanel = hud.panels["quest"]
	qpb2.set_tab(3)                           # 記事「場景」頁
	qpb2.refresh(true)
	await frames(2)
	check(qpb2.tab == 3, "場景: 記事切到場景 tab")
	hud.close_panels()
	var gate: Dictionary = m.sim._scene_gate("taohuadu")
	var scene_ent: Dictionary = m.sim.ent(int(m.my_id))
	scene_ent["x"] = int(gate["x"]); scene_ent["tx"] = int(scene_ent["x"])
	scene_ent["y"] = int(gate["y"]) + 1; scene_ent["ty"] = int(scene_ent["y"])
	scene_ent.erase("path")
	scene_ent["ch"]["level"] = 80
	m.sim._sync_quest_npcs()
	var sd := ContextActions.scene_dialog(m, "taohuadu")
	check(not (sd["options"] as Array).is_empty(), "場景: 入口對話有選項")
	m._send({"t": "scene_enter", "sid": "taohuadu"})
	check(m.sim.ent(int(m.my_id)).has("scene"), "場景: 撳「進入場景」入到桃花渡")
	m._send({"t": "scene_leave"})
	check(not m.sim.ent(int(m.my_id)).has("scene"), "場景: 撳「離開場景」返到出面")
	print("[TEST] ui_smoke: %d, fail %d" % [total, fails])
	print("PASS: ui smoke" if fails == 0 else "FAIL: ui smoke")
	get_tree().quit(1 if fails > 0 else 0)

