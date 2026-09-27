class_name CivicPanel
extends GamePanel
# 民心/法令面板 (U10，spec 08 §9~10): 顯示根據地城池民心/人口/稅率/6 條法令；
# 城主可以撳掣改稅率/法令（未佔城 = read-model active false，全部顯示但唔可改，S10 先解鎖）。
# 全部讀 sim 既有 read-model（militia_view/city_gov_view），經 main._send 發意圖。

const TAX_OPTS := [["low", "低"], ["normal", "正常"], ["high", "高"]]


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "民心/法令"


func sig() -> String:
	var mv: Dictionary = main.sim.militia_view(main.my_id)
	var city := String(mv.get("city", ""))
	return JSON.stringify([mv, main.sim.city_gov_view(city)])


func _build_body() -> void:
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	var mv: Dictionary = main.sim.militia_view(main.my_id)
	if not bool(mv.get("founded", false)):
		list.add_child(wrap_lbl("未成立義勇軍，未有根據地城池。", 14, UiTheme.DIM))
		return
	var city := String(mv.get("city", ""))
	var v: Dictionary = main.sim.city_gov_view(city)
	if v.is_empty():
		list.add_child(wrap_lbl("讀取唔到城池資料。", 14, UiTheme.DIM))
		return
	list.add_child(wrap_lbl("根據地：%s" % String(v.get("name", city)), 15, UiTheme.GOLD))
	if not bool(v.get("active", false)):
		list.add_child(wrap_lbl("未佔領呢座城，民心/法令未啟動（要打落城池先，留返後續 Step）。", 14, UiTheme.DIM))
		list.add_child(hsep())
	list.add_child(wrap_lbl("民心 %d/100　人口 %d" % [int(v.get("morale", 100)), int(v.get("pop", 0))], 14))
	list.add_child(hsep())
	list.add_child(lbl("稅率", 15, UiTheme.GOLD))
	var cur_tax := String(v.get("tax", "low"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for t in TAX_OPTS:
		var tid := String(t[0])
		var on := tid == cur_tax
		var b := btn(("✓ " if on else "") + String(t[1]), func() -> void: main._send({"t": "city_tax", "tax": tid}), 80)
		b.disabled = on
		row.add_child(b)
	list.add_child(row)
	list.add_child(wrap_lbl("高稅：每月民心 -%d（金庫收入代價，S10 後生效）" % -int((main.data.world["cityMorale"] as Dictionary).get("taxDrop", {}).get("high", 0)), 12, UiTheme.DIM))
	list.add_child(hsep())
	list.add_child(lbl("城池法令（每月改一次，行動力 -%d）" % int(v.get("apCost", 100)), 15, UiTheme.GOLD))
	var last_day := int(v.get("lastLawDay", -1))
	for l in (v.get("laws", []) as Array):
		var ld := l as Dictionary
		var lid := String(ld["id"])
		var on2 := bool(ld.get("on", true))
		var lrow := VBoxContainer.new()
		lrow.add_theme_constant_override("separation", 2)
		var hd := HBoxContainer.new()
		hd.add_theme_constant_override("separation", 6)
		hd.add_child(wrap_lbl(String(ld.get("name", lid)), 14))
		hd.add_child(btn("開" if on2 else "關", func() -> void: main._send({"t": "city_law", "law": lid, "on": not on2}), 60))
		lrow.add_child(hd)
		lrow.add_child(wrap_lbl(String(ld.get("desc", "")), 12, UiTheme.DIM))
		list.add_child(lrow)
	if last_day >= 0:
		list.add_child(wrap_lbl("上次改法令：第 %d 日" % last_day, 12, UiTheme.DIM))
