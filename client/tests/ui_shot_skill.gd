extends Node
# 特技/寶箱/融合 UI 截圖 (main.gd --skillshot): 要有 GPU (唔好加 --headless)
# Godot --path client -- --skillshot

var m: Node


func _ready() -> void:
	m = get_parent()
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func shot(name_: String) -> void:
	await frames(6)
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://skillshot_%s.png" % name_)
	print("SHOT ", ProjectSettings.globalize_path("user://skillshot_%s.png" % name_))


func put(x: int, y: int) -> void:
	var e: Dictionary = m.sim.ent(m.my_id)
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y
	m._refresh()


func _run() -> void:
	await frames(8)
	var ch: Dictionary = m.sim.player_ch()
	ch["level"] = 30
	# 野外 (35,35): 影寶箱 (鎖住) + 各職特技掣
	put(35, 35)
	var me: Dictionary = m.sim.ent(m.my_id)
	var chest: Dictionary = m.sim._new_ent("寶箱", "chest", Vector2i(36, 35))
	chest["hp"] = 1
	chest["max_hp"] = 1
	chest["locked"] = true
	chest["key"] = 1
	chest["drop"] = {"gold": 30, "items": []}
	for cls_sk in [["shinu", "unlock"], ["daoshi", "chaodu"], ["wunu", "yinxing"], ["bianshi", "qieting"], ["meinu", "toushi"], ["yishi", ""]]:
		ch["classId"] = cls_sk[0]
		ch["classSkill"] = cls_sk[1]
		m._refresh()
		await frames(10)
		await shot("hud_" + cls_sk[0])
	# 開鎖面板
	ch["classId"] = "shinu"
	ch["classSkill"] = "unlock"
	m._send({"t": "use_skill", "skill": "unlock"})
	await frames(10)
	await shot("unlock_panel")
	m.hud.close_panels()
	# 打鐵鋪融合對話 (義士)
	ch["classId"] = "yishi"
	var fg: Dictionary = m.data.facilities["forge"]
	var fm: Dictionary = m.data.map_by_id.get(str(fg["map"]), {})
	put(int(fg["x"]), int(fg["y"]) + 1)
	await frames(15)
	RulesShop.add_item(ch["bag"], 32001, 1)
	ContextActions.run(m, {"kind": "fac", "ref": {"fac": "forge", "x": int(fg["x"]), "y": int(fg["y"])}})
	await shot("forge_dialog")
	get_tree().quit(0)
