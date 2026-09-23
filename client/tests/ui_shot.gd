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
	get_tree().quit(0)
