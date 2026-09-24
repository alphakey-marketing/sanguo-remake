extends Node
# 手機 UI 截圖（main.gd --uishot 會掛）: HUD / 背包 / 商店 / 角色 / 對話框 各影一張，存 user://uishot_*.png 後退出。
# 要有 GPU（唔好加 --headless）: Godot --path client -- --uishot

var m: Node


func _ready() -> void:
	m = get_parent()
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func shot(name_: String) -> void:
	await frames(4)
	var img := get_viewport().get_texture().get_image()
	var p := "user://uishot_%s.png" % name_
	img.save_png(p)
	print("SHOT ", ProjectSettings.globalize_path(p))


func put(x: int, y: int) -> void:
	var e: Dictionary = m.sim.ent(m.my_id)
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y
	m._refresh()


func _run() -> void:
	await frames(5)
	var hud: MobileHud = m.hud
	var ch: Dictionary = m.ch
	ch["attrPoints"] = 3
	ch["gold"] = 800
	for id in [29054, 10002, 30513]:
		RulesShop.add_item(ch["bag"], id, 2)
	m._log("殺怪 +12 經驗 +5 金")
	m._log("自動掛機 開")
	var shp: Dictionary = m.data.shops[0]
	put(int(shp["x"]), int(shp["y"]) + 1)
	m.target_id = -1
	await frames(20)
	await shot("hud_shop_near")
	hud.bag_panel().open_filter("")
	var bp: BagPanel = hud.panels["bag"]
	bp.sel = 10002
	bp.refresh(true)
	await shot("bag")
	hud.close_panels()
	ContextActions.run(m, hud.ctx)
	var sp: ShopPanel = hud.panels["shop"]
	sp.sel = 10001
	sp.qty = 2
	sp.refresh(true)
	await shot("shop")
	hud.open_panel("char")
	var cp: CharPanel = hud.panels["char"]
	cp.pending = {"str": 1}
	cp.refresh(true)
	await shot("char")
	# 裝備 (Step 11.6): 背包揀防具比較 + 角色裝備頁紙娃娃
	m._send({"t": "debug_give", "item": 16001, "n": 1})
	m._send({"t": "debug_give", "item": 19001, "n": 1})
	m._send({"t": "equip", "item": 16001})
	cp.set_tab(1)
	cp.sel_slot = "head"
	cp.refresh(true)
	await shot("char_equip")
	cp.set_tab(0)
	hud.close_panels()
	hud.bag_panel().open_filter("")
	bp.sel = 19001
	bp.sel_slot = ""
	bp.refresh(true)
	await shot("bag_armor")
	hud.close_panels()
	put(m.sim.inn_pos.x, m.sim.inn_pos.y + 1)
	await frames(15)
	ContextActions.run(m, {"kind": "inn"})
	await shot("inn")
	hud.close_panels()
	put(35, 35)
	await frames(30)
	await shot("hud_field")
	# 地圖世界 (spec 12): 城中心 / 皇城 / 屯田 / 潁水橋 / 洞窟 / 地圖面板
	var xc: Dictionary = m.data.map_by_id["xuchang"]
	put(int(xc["ox"]) + 35, int(xc["oy"]) + 26)
	await frames(10)
	await shot("map_city")
	put(int(xc["ox"]) + 35, int(xc["oy"]) + 20)
	await frames(10)
	await shot("map_palace")
	put(70, 14)
	await frames(10)
	await shot("map_farm")
	put(41, 64)
	await frames(10)
	await shot("map_bridge")
	var cv: Dictionary = m.data.map_by_id["runan_f1"]
	put(int(cv["ox"]) + 20, int(cv["oy"]) + 12)
	await frames(10)
	await shot("map_cave")
	put(35, 35)
	await frames(5)
	hud.open_panel("map")
	await shot("panel_area")
	(hud.panels["map"] as MapPanel).set_tab(1)
	await shot("panel_world")
	# B2 (Step 11.7): 新野城 / 博望坡 / 昆陽故城 / 宛城道淯水 + 天下頁揀新野
	(hud.panels["map"] as MapPanel).select_node("xinye")
	await shot("panel_world_xinye")
	hud.close_panels()
	for it in [["xinye", 31, 24, "map_xinye"], ["bowang", 46, 30, "map_bowang"], ["kunyang", 46, 44, "map_kunyang"], ["wancheng_road", 31, 16, "map_wancheng"], ["runan_road", 80, 22, "map_runan_road"],
			["chenliu", 47, 16, "map_chenliu"], ["yudu", 20, 25, "map_yudu"], ["runan_city", 48, 20, "map_runan_city"],
			["wancheng", 35, 31, "map_wancheng_city"], ["gangkou", 45, 26, "map_gangkou"], ["hanshui", 40, 14, "map_hanshui"],
			["xiangyang", 37, 24, "map_xiangyang"], ["xy_prison", 18, 10, "map_prison"],   # B2.5
			["longzhong", 20, 24, "map_longzhong"], ["caolu", 14, 13, "map_caolu"], ["xiangyang", 8, 24, "map_xiangyang_west"]]:   # B3
		var md: Dictionary = m.data.map_by_id[it[0]]
		put(int(md["ox"]) + int(it[1]), int(md["oy"]) + int(it[2]))
		await frames(10)
		await shot(it[3])
	# 進階生產 (Step 12): 工房製作頁 / 修理頁 / 打鐵鋪修理服務 / 角色技能頁
	m._send({"t": "debug_work_lv", "add": 55})
	for id in [26004, 25001, 25002, 25003]:
		m._send({"t": "debug_give", "item": id, "n": 30})
	var wf: Dictionary = m.data.facilities["workshop"]
	put(int(wf["x"]), int(wf["y"]) + 1)
	await frames(10)
	m._send({"t": "equip_tool", "skill": "smithing", "item": 26004})
	var crp: CraftPanel = hud.craft_panel()
	crp.open_craft(str(wf["name"]), wf["crafts"])
	crp.sel = 10002
	crp.refresh(true)
	await shot("craft")
	ch["equip"]["dur"][str(int(ch["equip"]["weapon"]))] = 3
	crp.set_tab(3)
	crp.sel = int(ch["equip"]["weapon"])
	crp.refresh(true)
	await shot("craft_repair")
	crp.open_service("打鐵鋪")
	crp.sel = int(ch["equip"]["weapon"])
	crp.refresh(true)
	await shot("craft_service")
	hud.open_panel("char")
	(hud.panels["char"] as CharPanel).set_tab(2)
	await shot("char_work")
	hud.close_panels()
	# 登用 (Step 13.5): 皇城前武將 / 調查候選 / 問答 / 同伴框 + 同伴面板
	ch["level"] = 5
	ch["ideology"] = "義理"
	m.sim.state["tick"] = 720 + 300 - 1                # 第 1 日巳時 (曹營全員喺度)
	m.sim.step()
	put(int(xc["ox"]) + 36, int(xc["oy"]) + 19)
	await frames(10)
	await shot("recruit_generals")
	hud.open_panel("recruit")
	m._send({"t": "recruit_survey", "kind": "wen"})
	(hud.panels["recruit"] as GamePanel).refresh(true)
	await shot("recruit_survey")
	var cands: Array = m.sim.recruit_view()["cands"]
	if not cands.is_empty():
		m._send({"t": "recruit_pick", "gid": int(cands[0]["id"])})
		(hud.panels["recruit"] as GamePanel).refresh(true)
		await shot("recruit_quiz")
		for i in 10:
			var qv: Dictionary = m.sim.recruit_quiz_view()
			if qv.is_empty():
				break
			for q in m.data.quiz_generals:
				if String(q["q"]) == String(qv["q"]):
					m._send({"t": "recruit_answer", "answer": int(q["a"])})
					break
	hud.close_panels()
	await frames(10)
	await shot("recruit_companion_hud")
	m._send({"t": "debug_give", "item": 54807, "n": 1})     # Step 15: 寶物 + 武將補品 → 面板有贈與掣
	m._send({"t": "debug_give", "item": 30015, "n": 2})
	hud.open_panel("recruit")
	await shot("recruit_companion_panel")
	get_tree().quit(0)
