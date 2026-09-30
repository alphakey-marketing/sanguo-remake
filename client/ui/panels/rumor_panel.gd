class_name RumorPanel
extends GamePanel
# 頁 0「情報冊」= 辯士特技「竊聽」線索 (S02c-辯士, spec 02 §6【自訂】)：sim 權威 ch.rumors []（竊聽成功時記低，持久存檔）。
# 頁 1「傳聞」= 傳聞大表 (spec 09)：而家傳緊嘅傳聞（邊個、乜事、源自邊城、傳到邊啲城）。面板淨係讀。

const KIND_TEXT := {"killer": "惡名（殺人）", "bounty": "英雄事跡（除害）"}


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "情報冊"
	tab_names = ["情報冊", "傳聞"]


func open() -> void:
	set_tabs(tab_names)
	super()


func sig() -> String:
	var r: Array = main.ch.get("rumors", [])
	return JSON.stringify([tab, r.size(), main.sim.rumor_view()])


func _build_body() -> void:
	if tab == 1:
		_build_rumors()
		return
	body.add_child(wrap_lbl("辯士喺居民側邊竊聽到嘅傳聞線索（耳邊「…」）。", 13))
	var rumors: Array = main.ch.get("rumors", [])
	if rumors.is_empty():
		body.add_child(lbl("（未竊聽到任何傳聞——去居民聚集處用「竊聽」）", 13, UiTheme.GOLD))
	for line in rumors:
		body.add_child(lbl("• " + str(line), 13))


func rumor_line(r: Dictionary) -> String:
	var actor := int(r["actor"])
	var nm := "你" if actor == main.my_id else String(main.sim.ent(actor).get("name", "無名氏"))
	var cities: Array = []
	for c in r["cities"]:
		cities.append(String(main.sim._city_name(String(c))))
	return "%s：%s\n　源自%s，第 %d 日；已傳到 %s（份量 %d）" % [nm, KIND_TEXT.get(String(r["kind"]), String(r["kind"])),
		String(main.sim._city_name(String(r["origin"]))), int(r["day"]), "、".join(PackedStringArray(cities)), int(r["weight"])]


func _build_rumors() -> void:
	body.add_child(wrap_lbl("各城而家傳緊嘅傳聞（傳遍要幾日）。", 13))
	var rs: Array = main.sim.rumor_view()
	if rs.is_empty():
		body.add_child(lbl("（暫時冇傳聞）", 13, UiTheme.GOLD))
	for r in rs:
		body.add_child(wrap_lbl("• " + rumor_line(r), 13))
