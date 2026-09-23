extends SceneTree
# Step 7.5 工具: 重算 rules.json 入面 createCharacter / gainExp 嘅 expect（因為行為由舊「自動 growth」改做「自由點數」，頂部 vectors 已過時）。
# 跑: Godot --headless --path client --script tests/_regen_vectors.gd (> scratchpad/regen.txt)
# 再用 python 將輸出 patch 返入 tests/vectors/rules.json。


func _init() -> void:
	var path := ProjectSettings.globalize_path("res://") + "../tests/vectors/rules.json"
	var vecs: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	var data := GameData.load_all()
	var out := []
	for i in vecs.size():
		var v: Dictionary = vecs[i]
		match String(v["fn"]):
			"createCharacter":
				var a: Array = v["args"]
				out.append({"i": i, "expect": RulesStats.create_character(data, a[0], a[1])})
			"gainExp":
				var a2: Array = v["args"]
				var ch: Dictionary = (a2[0] as Dictionary).duplicate(true)
				var ups := RulesStats.gain_exp(data, ch, int(a2[1]))
				out.append({"i": i, "expect": {"ch": ch, "ups": ups}})
	print(JSON.stringify(out))
	quit(0)