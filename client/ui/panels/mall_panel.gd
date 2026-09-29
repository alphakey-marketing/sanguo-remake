class_name MallPanel
extends GamePanel
# 貨金商城 (S11a【自訂】單機化): 精選 cat 250 商城道具以金錢(兩)賣。系統→店鋪入口。
# 貨單/價 data/mall.json (sim.mall_view)；買 = sim.cmd_mall_buy (main._send t=mall_buy)。

var buying := -1          # 揀咗嗰件 id（顯示數量掣）


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "貨金商城"
	set_tabs(["購買"])


func sig() -> String:
	return JSON.stringify([main.sim.mall_view(main.my_id), buying])


func _build_body() -> void:
	var v := mall_view_d()
	if v.is_empty():
		body.add_child(lbl("貨金商城而家冇貨", UiTheme.FONT, UiTheme.DIM))
		return
	body.add_child(lbl("金錢：%d 兩" % int(v.get("gold", 0)), UiTheme.FONT, UiTheme.GOLD))
	body.add_child(wrap_lbl("精選商城道具（單機化，以金兩買）：", UiTheme.FONT, UiTheme.DIM))
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	for it in v["stock"] as Array:
		var iid := int(it["id"])
		var price := int(it["price"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		list.add_child(row)
		var name_lb := wrap_lbl("%s　%d 兩" % [str(it.get("name", "")), price], UiTheme.FONT)
		name_lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lb)
		if buying == iid:
			for n in [1, 5, 10]:
				row.add_child(btn("×%d" % n, func() -> void:
					main._send({"t": "mall_buy", "item": iid, "n": n})
					main._log("貨金商城買 %s ×%d" % [str(it.get("name", "")), n])
					refresh(true), 64))
		else:
			row.add_child(btn("買", func() -> void:
				buying = iid
				refresh(true), 64))


func mall_view_d() -> Dictionary:
	return main.sim.mall_view(main.my_id) if main.has_method("my_id") and main.sim != null and main.my_id > 0 else {}