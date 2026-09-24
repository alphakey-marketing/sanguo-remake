class_name RecruitPanel
extends GamePanel
# 登用面板 (Step 13.5, spec 09 §3): 調查 → 揀候選 → 擂台/問答；有同伴就顯示同伴 + 戰鬥指令 + 送補品 + 解散。
# 全部讀 sim.recruit_view()，經 main._send 發意圖。

func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "登用"


func sig() -> String:
	var v: Dictionary = main.sim.recruit_view()
	var c: Dictionary = v.get("comp", {})
	if not c.is_empty():            # HP 郁得好密: 只取整數 10% 級數，唔好每下重砌
		c = c.duplicate()
		c["hp"] = int(c["hp"]) * 10 / maxi(1, int(c["maxHp"]))
		v["comp"] = c
	return JSON.stringify([v, _gifts().size()])


func _build_body() -> void:
	var v: Dictionary = main.sim.recruit_view()
	if v.is_empty():
		return
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	if not (v["quiz"] as Dictionary).is_empty():
		_build_quiz(list, v["quiz"])
	elif String(v["pending"]) == "arena":
		list.add_child(wrap_lbl("擂台 PK 緊：%s\n打到佢 HP 0 就制服；你 HP 0 或者走開太遠 = 輸（唔會死）。" % v["pendingName"], 15))
		list.add_child(btn("返去打", func() -> void: main.hud.close_panels()))
		list.add_child(btn("認輸", func() -> void: main._send({"t": "recruit_cancel"})))
	elif not (v["comp"] as Dictionary).is_empty():
		_build_comp(list, v["comp"])
	else:
		_build_survey(list, v)


func _build_survey(list: VBoxContainer, v: Dictionary) -> void:
	var ch: Dictionary = main.ch
	list.add_child(wrap_lbl("理念「%s」　Lv%d\n喺城池街道「調查」搵人才：每日 1 次；成功登用嗰個月唔可以再調查。武將要擂台 PK，文官要答三國問答（10 題啱 8）。" %
		[str(ch.get("ideology", "")) if str(ch.get("ideology", "")) != "" else "未定（只登得出仕人才）", int(ch.get("level", 1))], 14, UiTheme.DIM))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	list.add_child(h)
	var blocked := String(v["block"]) != ""
	for k in [["wu", "調查武將"], ["wen", "調查文官"]]:
		var kind: String = k[0]
		var b := btn(k[1], func() -> void: main._send({"t": "recruit_survey", "kind": kind}))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = blocked
		h.add_child(b)
	if blocked:
		list.add_child(lbl(String(v["block"]), 14, UiTheme.BAD))
	var cands: Array = v["cands"]
	if cands.is_empty():
		return
	list.add_child(hsep())
	list.add_child(lbl("候選人才（揀一位接受考驗）", 15, UiTheme.GOLD))
	for c in cands:
		var gid := int(c["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var info := wrap_lbl("%s%s　戰等 %d　%s%s　%s" % ["★" if bool(c["t1"]) else "", c["name"], int(c["lv"]),
			RulesRecruit.type_name(String(c["type"])), c["sub"], c["ideo"]], 14)
		row.add_child(info)
		var b := btn("PK" if String(c["type"]) == "wu" else "問答", func() -> void: main._send({"t": "recruit_pick", "gid": gid}), 72)
		b.disabled = String(c.get("why", "")) != ""
		row.add_child(b)
		list.add_child(row)


func _build_quiz(list: VBoxContainer, q: Dictionary) -> void:
	list.add_child(lbl("%s 考你三國問答　第 %d/%d 題　答啱 %d" % [q["name"], int(q["i"]) + 1, int(q["n"]), int(q["ok"])], 15, UiTheme.GOLD))
	list.add_child(wrap_lbl(str(q["q"]), 17))
	var opts: Array = q["opts"]
	for i in opts.size():
		var idx := i
		var b := btn("%s. %s" % ["ABCD"[i], opts[i]], func() -> void: main._send({"t": "recruit_answer", "answer": idx}))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(b)
	list.add_child(btn("放棄", func() -> void: main._send({"t": "recruit_cancel"})))


func _build_comp(list: VBoxContainer, c: Dictionary) -> void:
	list.add_child(lbl("%s　Lv%d　%s%s" % [c["name"], int(c["lv"]), RulesRecruit.type_name(String(c["type"])), c["sub"]], 17, UiTheme.GOLD))
	list.add_child(lbl("HP %d/%d　忠誠 %d　剩 %d 日" % [int(c["hp"]), int(c["maxHp"]), int(c["loyalty"]), int(c["daysLeft"])], 15,
		UiTheme.BAD if int(c["loyalty"]) < 40 else UiTheme.TEXT))
	list.add_child(lbl("戰鬥指令", 14, UiTheme.DIM))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	list.add_child(g)
	for o in RulesRecruit.ORDERS:
		var order: String = o
		var b := btn(("● " if order == String(c["order"]) else "") + str(RulesRecruit.ORDER_NAMES[order]),
			func() -> void: main._send({"t": "companion_order", "order": order}))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(b)
	var gifts := _gifts()
	if not gifts.is_empty():
		list.add_child(lbl("送補品（回血 + 忠誠）", 14, UiTheme.DIM))
		for it in gifts.slice(0, 3):
			var item: int = it
			list.add_child(btn("送 %s ×%d" % [item_name(item), RulesShop.count_item(main.ch.get("bag", []), item)],
				func() -> void: main._send({"t": "companion_gift", "item": item})))
	list.add_child(hsep())
	list.add_child(btn("解散（叫佢返去）", func() -> void: main._send({"t": "companion_dismiss"})))


# 背包入面嘅回復品 (補品)
func _gifts() -> Array:
	var out: Array = []
	for b in main.ch.get("bag", []):
		if main.data.heals.has(int(b["id"])) and not out.has(int(b["id"])):
			out.append(int(b["id"]))
	return out
