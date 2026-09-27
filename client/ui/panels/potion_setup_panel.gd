class_name PotionSetupPanel
extends GamePanel
# 快捷補品欄設定 (U-fix): 3 格，撳格 → 列背包裡回 HP/MP 嘅補品揀一件裝落去；再撳一次可以卸走。

var editing_slot := -1


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "快捷補品欄"
	set_tabs([])


func sig() -> String:
	return JSON.stringify([main.potion_slots, editing_slot, main.ch.get("bag", [])])


func _heal_items() -> Array:
	var out: Array = []
	for b in main.ch.get("bag", []):
		var id := int(b["id"])
		if main.data.heals.has(id):
			out.append({"id": id, "n": int(b["n"])})
	return out


func _build_body() -> void:
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	sc.add_child(list)
	list.add_child(wrap_lbl("3 格快捷欄，裝住嘅補品移動手制上面撳一下即用。", 13, UiTheme.DIM))
	for i in main.potion_slots.size():
		var id := int(main.potion_slots[i])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		list.add_child(row)
		row.add_child(lbl("格 %d：%s" % [i + 1, item_name(id) if id > 0 else "（空）"], 15,
			UiTheme.GOLD if editing_slot == i else UiTheme.TEXT))
		var i_ := i
		row.add_child(btn("揀" if editing_slot != i else "揀緊…", func() -> void:
			editing_slot = i_
			refresh(true), 60))
		if id > 0:
			row.add_child(btn("卸空", func() -> void:
				main.potion_slots[i_] = 0
				refresh(true), 60))
	if editing_slot >= 0:
		list.add_child(hsep())
		list.add_child(lbl("揀件回 HP/MP 嘅補品裝入格 %d：" % (editing_slot + 1), 14, UiTheme.GOLD))
		var heals := _heal_items()
		if heals.is_empty():
			list.add_child(lbl("背包冇回 HP/MP 嘅補品。", 13, UiTheme.DIM))
		for it in heals:
			var id2 := int(it["id"])
			var slot := editing_slot
			list.add_child(btn("%s x%d" % [item_name(id2), int(it["n"])], func() -> void:
				main.potion_slots[slot] = id2
				editing_slot = -1
				refresh(true), 0))
