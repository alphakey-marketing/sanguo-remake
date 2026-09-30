extends SceneTree
# AssetLib 測試 (A1): 有索引+檔 → 有圖；冇 → null (fallback)；索引缺漏唔 crash
# 跑: Godot --headless --path client --script tests/run_assetlib.gd

var fails := 0
var total := 0


func _init() -> void:
	var cov := AssetLib.coverage()
	if cov.is_empty():
		# 未跑導入器 (assets_orig 冇): 全部必須 null，遊戲靠 fallback
		check(AssetLib.item_icon(10001) == null, "冇索引 item_icon 應 null")
		check(AssetLib.face(20001) == null, "冇索引 face 應 null")
	else:
		var missing := 0
		for iid in [10001, 22001]:
			if AssetLib.has("items", iid):
				var t := AssetLib.item_icon(iid)
				check(t != null and t.get_width() == 32, "item %d 細圖 32px" % iid)
				var l := AssetLib.item_icon(iid, true)
				check(l != null and l.get_width() == 100, "item %d 大圖 100px" % iid)
			else:
				missing += 1
		check(missing < 2, "示範 item 應有圖")
		check(AssetLib.face(20001) != null, "face 20001 有圖")
	check(AssetLib.item_icon(-1) == null, "唔存在 id → null")
	check(AssetLib.face("nope") == null, "唔存在 face → null")
	print("[TEST] assetlib: %d, fail %d (coverage %s)" % [total, fails, str(cov)])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)
