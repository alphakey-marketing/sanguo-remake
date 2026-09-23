class_name CharPanel
extends GamePanel
# 角色面板: 左 = 屬性 + 分配點數（＋/－ 先暫存，撳「確認分配」先送 sim）；右 = 角色資料。
# 「建議分配」係玩家自己撳嘅選項（按職業比例派晒），唔會自動派。政治/魅力唔用得點數，放右邊資料。

const ATTR_NAMES := {"str": "武力", "agi": "敏捷", "int": "智力", "spi": "靈力", "pol": "政治", "cha": "魅力"}
var pending := {}             # attr -> 暫存加咗幾多


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "角色"


func open() -> void:
	pending = {}
	super()


func sig() -> String:
	var ch: Dictionary = main.ch
	return JSON.stringify([pending, ch.get("attrs", {}), ch.get("attrPoints", 0), ch.get("level", 1), ch.get("hp", 0),
		ch.get("mp", 0), ch.get("sp", 0), ch.get("gold", 0), ch.get("karma", 0), ch.get("lilian", 0), ch.get("title", "")])


func _left() -> int:
	var used := 0
	for k in pending:
		used += int(pending[k])
	return int(main.ch.get("attrPoints", 0)) - used


func _build_body() -> void:
	var ch: Dictionary = main.ch
	if ch.is_empty():
		return
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	body.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var sc := scroll()
	row.add_child(sc)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(right)
	var left_n := _left()
	left.add_child(lbl("可分配點數 %d" % left_n, 16, UiTheme.GOOD if left_n > 0 else UiTheme.DIM))
	var gs := scroll()
	left.add_child(gs)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 3)
	gs.add_child(grid)
	var attrs: Dictionary = ch.get("attrs", {})
	for k in RulesStats.RAIDABLE:
		var base := int(attrs.get(k, 0))
		var add := int(pending.get(k, 0))
		grid.add_child(lbl(String(ATTR_NAMES[k]), 16))
		var v := lbl(str(base + add) + (" (+%d)" % add if add > 0 else ""), 16, UiTheme.GOOD if add > 0 else UiTheme.TEXT)
		v.custom_minimum_size.x = 76
		grid.add_child(v)
		var mb := btn("－", func() -> void:
			pending[k] = maxi(0, add - 1)
			refresh(true), 48)
		mb.disabled = add <= 0
		grid.add_child(mb)
		var pb := btn("＋", func() -> void:
			pending[k] = add + 1
			refresh(true), 48)
		pb.disabled = left_n <= 0 or base + add >= RulesStats.ATTR_CAP
		grid.add_child(pb)
	var h := HBoxContainer.new()
	var ok := btn("確認分配", _confirm)
	ok.disabled = left_n == int(ch.get("attrPoints", 0))
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ok)
	var rs := btn("重設", func() -> void:
		pending = {}
		refresh(true), 64)
	h.add_child(rs)
	if int(ch.get("attrPoints", 0)) > 0:
		h.add_child(btn("建議分配", func() -> void:
			pending = {}
			main._send({"t": "auto_assign"}), 96))
	left.add_child(h)
	# 右: 資料
	var lv := int(ch["level"])
	var cls: Dictionary = main.data.classes.get(str(ch.get("classId", "")), {})
	right.add_child(lbl("%s  Lv%d %s" % [str(ch.get("name", "")), lv, str(cls.get("name", ""))], 17, UiTheme.GOLD))
	var lines := [
		"稱號「%s」" % (str(ch.get("title", "")) if str(ch.get("title", "")) != "" else "未設"),
		"善惡 %s (%d)" % [RulesKarma.tier_name(int(ch.get("karma", 0))), int(ch.get("karma", 0))],
		"理念 %s" % (str(ch.get("ideology", "")) if str(ch.get("ideology", "")) != "" else "未測"),
		"生日 %d月%d日" % [int(ch.get("birthMonth", 1)), int(ch.get("birthDay", 1))],
		"政治 %d  魅力 %d（私塾/寺廟修練）" % [int(attrs.get("pol", 0)), int(attrs.get("cha", 0))],
		"HP %d/%d" % [int(ch["hp"]), RulesStats.max_hp(lv, attrs)],
		"MP %d/%d" % [int(ch["mp"]), RulesStats.max_mp(lv, attrs)],
		"SP %d/%d" % [int(ch["sp"]), RulesStats.max_sp(lv, attrs)],
		"經驗 %d/%d" % [int(ch.get("exp", 0)), RulesStats.exp_to_next(lv)],
		"歷練 %d/100" % int(ch.get("lilian", 0)),
		"金 %d" % int(ch.get("gold", 0)),
		"武器 %s" % (item_name(int(ch.get("equip", {}).get("weapon", 0))) if int(ch.get("equip", {}).get("weapon", 0)) > 0 else "（冇）"),
	]
	for l in lines:
		right.add_child(lbl(str(l), 14))


func _confirm() -> void:
	for k in pending:
		for i in int(pending[k]):
			main._send({"t": "raise_attr", "attr": k})
	pending = {}
	refresh(true)
