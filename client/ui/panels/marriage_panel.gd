class_name MarriagePanel
extends GamePanel
# 結婚面板 (U12，spec 06 §9 / 09 §6)：頁 0「喜事」求婚/喜餅買開分/預約/婚禮，
# 頁 1「配偶」配偶資料/召喚/叮嚀留言/離婚。全部讀 sim 既有 read-model（marry_view），
# 經 main._send 發意圖，唔直接改 ch。


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "結婚"
	tab_names = ["喜事", "配偶"]


func open_tab(i: int) -> void:
	tab = i
	set_tabs(tab_names)
	open()


func sig() -> String:
	return JSON.stringify([tab, main.sim.marry_view(), main.ch.get("bag", [])])


func _build_body() -> void:
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	var v: Dictionary = main.sim.marry_view()
	if v.is_empty():
		list.add_child(wrap_lbl("讀取唔到資料。", 14, UiTheme.DIM))
		return
	match tab:
		0: _build_wedding(list, v)
		_: _build_spouse(list, v)


# ---- 頁 0: 喜事 ----
func _build_wedding(list: VBoxContainer, v: Dictionary) -> void:
	var spouse: Dictionary = v.get("spouse", {})
	if not spouse.is_empty():
		list.add_child(wrap_lbl("已同%s結為夫妻，睇「配偶」頁。" % String(spouse.get("name", "")), 14, UiTheme.GOLD))
		return
	var engaged: Dictionary = v.get("engaged", {})
	var booked: Dictionary = v.get("booked", {})
	var blocks: Dictionary = v.get("blocks", {})
	list.add_child(lbl("步驟 1：求婚", 15, UiTheme.GOLD))
	if not engaged.is_empty():
		list.add_child(wrap_lbl("已向%s求婚（等待婚禮）" % String(engaged.get("name", "")), 14, UiTheme.GOOD))
	else:
		var why := String(blocks.get("propose", ""))
		var has_letter := bool(v.get("hasLetter", false))
		list.add_child(wrap_lbl("御賜函：%s　好感鎖：%d" % ["已有" if has_letter else "未有", int(v.get("affinityLock", 90))], 12, UiTheme.DIM))
		var b1 := btn("向同伴求婚" if why == "" else why, func() -> void: main._send({"t": "marry_propose"}))
		b1.disabled = why != ""
		list.add_child(b1)
	list.add_child(hsep())
	list.add_child(lbl("步驟 2：喜餅（買 → 開 → 分）", 15, UiTheme.GOLD))
	for c in (v.get("cakes", []) as Array):
		var cd := c as Dictionary
		var tier := int(cd["tier"])
		var buy_id := int(cd["buy"])
		var open_id := int(cd["open"])
		var have_buy := RulesShop.count_item(main.ch.get("bag", []), buy_id)
		var have_open := RulesShop.count_item(main.ch.get("bag", []), open_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(wrap_lbl("%s（%d 兩）" % [String(cd.get("buyName", "")), int(cd["price"])], 13))
		row.add_child(btn("買", func() -> void: main._send({"t": "marry_buy_cake", "tier": tier}), 60))
		var bo := btn("開×%d" % have_buy, func() -> void: main._send({"t": "marry_open_cake", "item": buy_id}), 70)
		bo.disabled = have_buy <= 0
		row.add_child(bo)
		var bs := btn("分×%d" % have_open, func() -> void: main._send({"t": "marry_share_cake", "item": open_id}), 70)
		bs.disabled = have_open <= 0
		row.add_child(bs)
		list.add_child(row)
	var fest: Dictionary = v.get("festive", {})
	if not fest.is_empty() and String(fest.get("city", "")) != "":
		list.add_child(wrap_lbl("婚慶氛圍：%s 城居民好感提升中（第 %d 日前）" % [String(fest.get("city", "")), int(fest.get("until", 0))], 12, UiTheme.DIM))
	list.add_child(hsep())
	list.add_child(lbl("步驟 3：預約禮堂", 15, UiTheme.GOLD))
	if not booked.is_empty():
		list.add_child(wrap_lbl("已預約，主婚人：%s" % String(booked.get("official", "")), 14, UiTheme.GOOD))
	else:
		var why2 := String(blocks.get("book", ""))
		var b2 := btn("預約禮堂" if why2 == "" else why2, func() -> void: main._send({"t": "marry_book"}))
		b2.disabled = why2 != ""
		list.add_child(b2)
	list.add_child(hsep())
	list.add_child(lbl("步驟 4：舉行婚禮", 15, UiTheme.GOLD))
	var why3 := String(blocks.get("hold", ""))
	var b3 := btn("舉行婚禮" if why3 == "" else why3, func() -> void: main._send({"t": "marry_hold"}))
	b3.disabled = why3 != ""
	list.add_child(b3)


# ---- 頁 1: 配偶 ----
func _build_spouse(list: VBoxContainer, v: Dictionary) -> void:
	var spouse: Dictionary = v.get("spouse", {})
	if spouse.is_empty():
		list.add_child(wrap_lbl("你未結婚，睇「喜事」頁開始流程。", 14, UiTheme.DIM))
		return
	list.add_child(wrap_lbl("%s　Lv%d　%s" % [String(spouse.get("name", "")), int(spouse.get("lv", 0)), String(spouse.get("classId", ""))], 15, UiTheme.GOLD))
	list.add_child(wrap_lbl("結婚 %d 年（第 %d 日）　主婚人：%s" % [int(spouse.get("years", 0)), int(spouse.get("day", 0)), String(spouse.get("official", ""))], 13))
	list.add_child(wrap_lbl("生日 %d 月 %d 日　理念 %s" % [int(spouse.get("birthMonth", 1)), int(spouse.get("birthDay", 1)), String(spouse.get("ideo", ""))], 13))
	list.add_child(wrap_lbl("目前：%s" % ("身邊" if bool(spouse.get("present", false)) else "唔喺身邊"), 13, UiTheme.DIM))
	list.add_child(hsep())
	var blocks: Dictionary = v.get("blocks", {})
	var why := String(blocks.get("summon", ""))
	var bsm := btn("召喚配偶到身邊（−%d SP）" % int(v.get("summonSp", 50)) if why == "" else why,
		func() -> void: main._send({"t": "marry_summon"}))
	bsm.disabled = why != ""
	list.add_child(bsm)
	list.add_child(hsep())
	list.add_child(lbl("叮嚀留言", 15, UiTheme.GOLD))
	_msg_edit = _msg_edit if _msg_edit != null else LineEdit.new()
	_msg_edit.text = String(v.get("message", ""))
	_msg_edit.placeholder_text = "留返幾句畀另一半"
	list.add_child(_msg_edit)
	list.add_child(btn("儲存留言", func() -> void: main._send({"t": "marry_message", "text": _msg_edit.text}), 100))
	list.add_child(hsep())
	list.add_child(lbl("離婚", 15, UiTheme.GOLD))
	var why2 := String(blocks.get("divorce", ""))
	list.add_child(wrap_lbl("要搵斷情絕愛郎，離婚要 %d 兩，婚戒會回收。" % int(v.get("divorceGold", 500000)), 12, UiTheme.DIM))
	var bdv := btn("離婚" if why2 == "" else why2, func() -> void: main._send({"t": "marry_divorce"}))
	bdv.disabled = why2 != ""
	list.add_child(bdv)


var _msg_edit: LineEdit
