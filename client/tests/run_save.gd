extends SceneTree
# 存檔層: 原子寫入 / v2 meta / .bak 後備 / 壞檔唔當空位 / 舊 v1 檔兼容
var fails := 0


func check(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("[FAIL] ", m)


func _init() -> void:
	var data := GameData.load_all()
	var sim := Sim.new(data, 1)
	sim.init_mobs()
	sim.spawn_player("測試")
	var n := 3
	SaveSys.delete_slot(n)
	check(SaveSys.slot_state(SaveSys.slot_path(n)) == "none", "冇檔 = none")
	check(SaveSys.save_slot(sim, n), "存檔成功")
	check(not FileAccess.file_exists(SaveSys.slot_path(n) + ".tmp"), "tmp 已改名")
	var inf: Dictionary = SaveSys.slot_summaries()[n - 1]
	check(str(inf.state) == "ok" and str(inf.name) == "測試", "meta 讀到名")
	check(int(inf.ts) > 0, "meta 有時間戳")
	var d = JSON.parse_string(FileAccess.get_file_as_string(SaveSys.slot_path(n)))
	check(int(d.get("v", 0)) == SaveSys.FORMAT_VER, "有版本號")
	check(SaveSys.read_slot(data, n) != null, "讀得返")
	# 再存一次 → 出 .bak
	SaveSys.save_slot(sim, n)
	check(FileAccess.file_exists(SaveSys.slot_path(n) + ".bak"), "第二次存檔有 .bak")
	# 正檔壞 → 用 .bak
	var f := FileAccess.open(SaveSys.slot_path(n), FileAccess.WRITE)
	f.store_string("{壞")
	f.close()
	check(SaveSys.slot_state(SaveSys.slot_path(n)) == "bak", "正檔壞 = bak")
	check(SaveSys.read_slot(data, n) != null, "壞檔改讀 .bak")
	check(str(SaveSys.slot_summaries()[n - 1].name) == "測試", "壞檔摘要讀 .bak")
	# 兩個都壞
	f = FileAccess.open(SaveSys.slot_path(n) + ".bak", FileAccess.WRITE)
	f.store_string("x")
	f.close()
	check(SaveSys.slot_state(SaveSys.slot_path(n)) == "bad", "兩個都壞 = bad")
	check(SaveSys.read_slot(data, n) == null, "bad 讀唔到")
	check(bool(SaveSys.slot_summaries()[n - 1].exists), "bad 仍算有檔 (唔當空位)")
	# 舊 v1 檔 (冇 meta/v)
	var v1 := {"state": d["state"], "rng": d["rng"]}
	f = FileAccess.open(SaveSys.slot_path(n), FileAccess.WRITE)
	f.store_string(JSON.stringify(v1))
	f.close()
	check(SaveSys.slot_state(SaveSys.slot_path(n)) == "ok", "v1 檔讀得")
	check(str(SaveSys.slot_summaries()[n - 1].name) == "測試", "v1 檔摘要由 state 抽")
	check(SaveSys.read_slot(data, n) != null, "v1 載入")
	SaveSys.delete_slot(n)
	check(not SaveSys.slot_exists(n) and not FileAccess.file_exists(SaveSys.slot_path(n) + ".bak"), "刪除連 .bak")
	check(SaveSys.ts_text(0) == "未存" and SaveSys.ts_text(1790000000).length() == 11, "時間文字")
	print("[TEST] save: fails ", fails)
	quit()
