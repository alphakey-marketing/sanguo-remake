class_name RumorPanel
extends GamePanel
# 辯士特技「竊聽」情報冊 (S02c-辯士, spec 02 §6【自訂】): 列出竊聽返嚟嘅傳聞線索。
# sim 權威: ch.rumors []（竊聽成功時由 sim 記低，持久存檔）。面板淨係讀。


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "情報冊（竊聽）"


func sig() -> String:
	var r: Array = main.ch.get("rumors", [])
	return JSON.stringify([r.size()])


func _build_body() -> void:
	body.add_child(wrap_lbl("辯士喺居民側邊竊聽到嘅傳聞線索（耳邊「…」）。", 13))
	var rumors: Array = main.ch.get("rumors", [])
	if rumors.is_empty():
		body.add_child(lbl("（未竊聽到任何傳聞——去居民聚集處用「竊聽」）", 13, UiTheme.GOLD))
	for line in rumors:
		body.add_child(lbl("• " + str(line), 13))