extends SceneTree
# AudioBus smoke: 索引有嘅音效都載到 (冇素材就 skip)
func _init() -> void:
	var fail := 0
	var n := 0
	for k in ["bgm_town", "hit", "spell", "click"]:
		var p := AssetLib.audio_path(k)
		if p == "":
			continue
		n += 1
		var o := AudioStreamOggVorbis.load_from_file(p)
		if o == null or o.get_length() <= 0.0:
			fail += 1
			print("FAIL load ", k)
	print("[TEST] audio: %d loaded, fail %d" % [n, fail])
	quit(1 if fail > 0 else 0)
