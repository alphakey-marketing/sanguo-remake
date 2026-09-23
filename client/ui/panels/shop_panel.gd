class_name ShopPanel
extends GamePanel
# 商店面板: 頁籤 買 / 賣。左 = 貨品列表（可以拖捲）；右 = 詳情 + 數量 + 確認。
# 價錢: 買 = 市場價 × 魅力折扣；賣 = 市場價 50%（main._buy_price / _sell_price，同 sim 一致）

var shop: Dictionary = {}     # main.facilities 入面嗰間店
var sel := 0
var qty := 1


func _init(m: Node) -> void:
	super(m)
	set_tabs(["買", "賣"])


func open_shop(f: Dictionary) -> void:
	shop = f
	title_lbl.text = str(f.get("shopName", "商店"))
	sel = 0
	qty = 1
	tab = 0
	set_tabs(tab_names)
	open()


func set_tab(i: int) -> void:
	sel = 0
	qty = 1
	super(i)


func sig() -> String:
	var ch: Dictionary = main.ch
	return JSON.stringify([tab, sel, qty, ch.get("gold", 0), ch.get("bag", []), ch.get("attrs", {}).get("cha", 0)])


func _stock() -> Array:
	return shop.get("stock", []) as Array


func _bag_n(id: int) -> int:
	for b in main.ch.get("bag", []):
		if int(b["id"]) == id:
			return int(b["n"])
	return 0


func _build_body() -> void:
	var ch: Dictionary = main.ch
	if ch.is_empty():
		return
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.3
	row.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	row.add_child(right)
	left.add_child(lbl("金 %d" % int(ch["gold"]), 15, Color(1, 0.9, 0.5)))
	var sc := scroll()
	left.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	sc.add_child(list)
	var ids: Array = []
	if tab == 0:
		ids = _stock()
	else:
		for b in ch["bag"]:
			ids.append(int(b["id"]))
	if ids.is_empty():
		list.add_child(lbl("（背包空）" if tab == 1 else "（冇貨）", 14, UiTheme.DIM))
	for idv in ids:
		var id := int(idv)
		var price: int = main._buy_price(id) if tab == 0 else main._sell_price(id)
		var t := "%s   %d 金" % [item_name(id), price]
		if tab == 1:
			t = "%s x%d   %d 金" % [item_name(id), _bag_n(id), price]
		var b := btn(t, func() -> void:
			sel = id
			qty = 1
			refresh(true))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.set_pressed_no_signal(sel == id)
		if tab == 1 and main.quest_items.has(id):
			b.add_theme_color_override("font_color", UiTheme.DIM)
		list.add_child(b)
	_build_detail(right, ch)


func _build_detail(p: Control, ch: Dictionary) -> void:
	if sel == 0:
		p.add_child(lbl("揀一件貨品" if tab == 0 else "揀要賣嘅物品", 14, UiTheme.DIM))
		return
	var id := sel
	p.add_child(lbl(item_name(id), 18, UiTheme.GOLD))
	for s in item_desc(id):
		p.add_child(wrap_lbl(str(s), 13, UiTheme.DIM))
	if tab == 0:
		var price: int = main._buy_price(id)
		var max_n := mini(99, int(ch["gold"]) / maxi(1, price))
		p.add_child(stepper(qty, max_n, func(n: int) -> void:
			qty = n
			refresh(true)))
		var total := price * qty
		var ok := total <= int(ch["gold"])
		p.add_child(lbl("合共 %d 金%s" % [total, "" if ok else "（唔夠錢）"], 15, UiTheme.TEXT if ok else UiTheme.BAD))
		var b := btn("確認買入", func() -> void:
			main._send({"t": "buy", "item": id, "n": qty})
			qty = 1)
		b.disabled = not ok
		p.add_child(b)
	else:
		var have := _bag_n(id)
		if main.quest_items.has(id):
			p.add_child(lbl("任務道具唔賣得", 15, UiTheme.BAD))
			return
		if have == 0:
			sel = 0
			return
		qty = mini(qty, have)
		p.add_child(stepper(qty, have, func(n: int) -> void:
			qty = n
			refresh(true)))
		p.add_child(lbl("得 %d 金" % (main._sell_price(id) * qty), 15, UiTheme.GOOD))
		p.add_child(btn("確認賣出", func() -> void:
			main._send({"t": "sell", "item": id, "n": qty})
			qty = 1))
