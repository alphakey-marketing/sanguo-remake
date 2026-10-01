extends Node
# 原版地圖截圖 (驗人物有無俾地板/物件遮): Godot --path client -- --origshot  (要 GPU，唔好 --headless)
# 每張圖影兩個位: 出生點 + 圖中央最近嘅行得格；存 user://origshot_<map>_<n>.png

var m: Node


func _ready() -> void:
	m = get_parent()
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func put(x: int, y: int) -> void:
	var e: Dictionary = m.sim.ent(m.my_id)
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y
	m._refresh()


func shot(name_: String) -> void:
	await frames(30)
	var p := "user://origshot_%s.png" % name_
	get_viewport().get_texture().get_image().save_png(p)
	print("SHOT ", ProjectSettings.globalize_path(p))


func _run() -> void:
	await frames(5)
	var d: GameData = m.data
	var W := GameData.WORLD_W
	if OS.get_environment("LINKSHOT") != "":        # 許昌西門 -> 1929 -> 陳留1749: 每個傳送點門口 + 落腳點
		for q in OS.get_environment("LINKSHOT").split(","):
			var pd: Dictionary = d.tp_by_id.get(q, {})
			if pd.is_empty():
				continue
			put(int(pd["x"]), int(pd["y"]))
			await shot("link_" + q + "_door")
			var lc: Array = pd["land"]
			put(int(lc[0]), int(lc[1]))
			await shot("link_" + q + "_land")
		get_tree().quit()
		return
	for md in d.maps:
		var id := String(md["id"])
		if not (id.begins_with("xc") or id == "xuchang_o"):
			continue
		var ox := int(md["ox"])
		var oy := int(md["oy"])
		var cx := ox + int(md["w"]) / 2
		var cy := oy + int(md["h"]) / 2
		var best := -1
		var bd := 1 << 30
		for y in range(oy, oy + int(md["h"])):
			for x in range(ox, ox + int(md["w"])):
				if d.walk[y * W + x] == 1 and not d.portal_at.has(y * W + x):
					var dd := absi(x - cx) + absi(y - cy)
					if dd < bd:
						bd = dd
						best = y * W + x
		if id == "xuchang_o":                       # 城池: 3x3 個取樣點各影一張
			for gi in 9:
				var tx := ox + int(md["w"]) * (gi % 3 * 2 + 1) / 6
				var ty := oy + int(md["h"]) * (gi / 3 * 2 + 1) / 6
				var bb := -1
				var bdd := 1 << 30
				for y in range(ty - 12, ty + 12):
					for x in range(tx - 12, tx + 12):
						if d.walk[y * W + x] == 1 and not d.portal_at.has(y * W + x) and absi(x - tx) + absi(y - ty) < bdd:
							bdd = absi(x - tx) + absi(y - ty)
							bb = y * W + x
				if bb >= 0:
					put(bb % W, bb / W)
					await shot("city_%d" % gi)
			continue
		var sp: Array = md["spawn"]
		put(int(sp[0]), int(sp[1]))
		await shot(id + "_a")
		if best >= 0:
			put(best % W, best / W)
			await shot(id + "_b")
	get_tree().quit()
