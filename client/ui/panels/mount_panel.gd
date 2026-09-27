class_name MountPanel
extends GamePanel
# 座騎面板 (Step 17a, spec 07): 頁 0「座騎」= 身邊嗰匹嘅狀態 + 騎乘/放牧 + 飼養動作 (揀道具) + 優秀值點數 + 丟棄；
# 頁 1「馬廄」= 全部座騎 + 寄養/領馬 + 買馬 + 馬用品 (要企喺馬廄隔籬)。
# 全部讀 sim.mount_view()，經 main._send 發意圖。

const ACT_ORDER := ["feed", "play", "scold", "gift", "train", "heal"]
const ACT_SHORT := {"feed": "餵食", "play": "玩耍", "scold": "責備", "gift": "送禮", "train": "訓練", "heal": "醫療"}

var pick_act := ""          # 揀緊道具嘅動作
var confirm_drop := false   # 丟棄要撳兩下
var name_edit: LineEdit     # U02: 改名輸入框
var pick_sire := ""         # U02: 揀緊種馬品種


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "座騎"
	tab_names = ["座騎", "馬廄"]


func open_tab(i: int) -> void:
	tab = i
	pick_act = ""
	confirm_drop = false
	pick_sire = ""
	set_tabs(tab_names)
	open()


func set_tab(i: int) -> void:
	pick_act = ""
	confirm_drop = false
	pick_sire = ""
	super(i)


func _view() -> Dictionary:
	var v: Dictionary = main.sim.mount_view(main.my_id)
	for m in v.get("list", []):
		m["grazeLeft"] = int(ceil(int(m["grazeLeft"]) / 7.5))        # tick → 刻，唔好每 tick 重砌
	return v


func sig() -> String:
	return JSON.stringify([tab, pick_act, confirm_drop, pick_sire, _view(), main.ch.get("bag", [])])


func _mcfg() -> Dictionary:
	return main.data.mounts


func _build_body() -> void:
	var v := _view()
	if v.is_empty():
		return
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	if tab == 0:
		_build_mine(list, v)
	else:
		_build_stable(list, v)


func _with(v: Dictionary) -> Dictionary:
	for m in v["list"]:
		if String(m["where"]) == "with" or String(m["where"]) == "graze":
			return m
	return {}


func _grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	return g


func _fill(b: Button) -> Button:
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


# ---- 頁 0: 身邊嗰匹 ----
func _build_mine(list: VBoxContainer, v: Dictionary) -> void:
	var m := _with(v)
	if m.is_empty():
		list.add_child(wrap_lbl("身邊冇座騎。去馬廄（許昌東、新野東）買馬或者領馬。", 15, UiTheme.DIM))
		return
	var cfg := _mcfg()
	var uid := int(m["uid"])
	var an: Dictionary = cfg["attrNames"]
	var st: Array = m["status"]
	var lines: Array = [
		"%s（%s・%s・%d 日）%s" % [m["name"], m["breed"], m["stageName"], int(m["age"]), "　騎緊" if bool(v["riding"]) else ""],
		"生命 %d/%d　飽食 %d　親密 %d　情緒 %s" % [int(m["life"]), int(m["lifeMax"]), int(m["satiety"]), int(m["intimacy"]), m["moodName"]],
		"疲勞 %d/%d%s" % [int(m["fatigue"]), int(m["fatigueMax"]), "　異常：" + "、".join(st) if not st.is_empty() else ""],
		"%s %d　%s %d　%s %d　%s %d　%s %d" % [an["learn"], int(m["attrs"]["learn"]), an["burst"], int(m["attrs"]["burst"]),
			an["run"], int(m["attrs"]["run"]), an["endure"], int(m["attrs"]["endure"]), an["stamina"], int(m["attrs"]["stamina"])],
		"優秀值 %d（成長 %d/%d）　騎乘移速 ×%.2f　行動力 %d" % [int(m["excel"]), int(m["grow"]), int(cfg["graze"]["growNeed"]), float(m["speed"]), int(v["ap"])]]
	if String(m["where"]) == "graze":
		lines.append("放牧中，大約仲有 %d 刻返嚟" % int(m["grazeLeft"]))
	list.add_child(wrap_lbl("\n".join(lines), 15))
	# 改名
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 6)
	list.add_child(nrow)
	name_edit = LineEdit.new()
	name_edit.max_length = 8
	name_edit.placeholder_text = "改名（最多 8 字）"
	name_edit.text = String(m.get("nick", ""))
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(name_edit)
	nrow.add_child(btn("改名", func() -> void: main._send({"t": "mount_rename", "uid": uid, "nick": name_edit.text}), 80))
	# 騎乘 / 放牧
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	list.add_child(row)
	var riding := bool(v["riding"])
	var rb := _fill(btn("落馬" if riding else "騎馬", func() -> void: main._send({"t": "mount_ride", "on": not riding})))
	rb.disabled = not riding and String(m["rideWhy"]) != ""
	row.add_child(rb)
	var grazing := String(m["where"]) == "graze"
	var gb := _fill(btn("吹哨召回" if grazing else "放牧", func() -> void: main._send({"t": "mount_graze"})))
	gb.disabled = not bool(v["hasWhistle"]) or (not grazing and String(m["grazeWhy"]) != "")
	row.add_child(gb)
	var why := String(m["rideWhy"]) if not riding and String(m["rideWhy"]) != "" else ""
	if not bool(v["hasWhistle"]):
		why += ("　" if why != "" else "") + "放牧要馴馬專用哨（馬廄有得賣）"
	elif not grazing and String(m["grazeWhy"]) != "":
		why += ("　" if why != "" else "") + String(m["grazeWhy"])
	if why != "":
		list.add_child(wrap_lbl(why, 13, UiTheme.DIM))
	# 飼養動作
	list.add_child(hsep())
	list.add_child(lbl("飼養（每個動作扣行動力 %d）" % int(cfg["apCost"]), 15, UiTheme.GOLD))
	var g := _grid(3)
	list.add_child(g)
	for act in ACT_ORDER:
		var a: String = act
		var info: Dictionary = m["acts"][a]
		var left := int(info["left"])
		var label := String(ACT_SHORT[a]) + ("" if left < 0 else " (%d)" % left)
		var need_item := not (cfg["acts"][a].get("items", []) as Array).is_empty()
		var b := _fill(btn(label, func() -> void:
			if need_item:
				pick_act = "" if pick_act == a else a
				refresh(true)
			else:
				main._send({"t": "mount_act", "uid": uid, "act": a})))
		b.disabled = String(info["why"]) != "" or int(v["ap"]) < int(cfg["apCost"]) or grazing
		if pick_act == a:
			b.add_theme_color_override("font_color", UiTheme.GOLD)
		g.add_child(b)
	if pick_act != "":
		_build_pick(list, uid, pick_act)
	# 繁衍 (Step 17b)
	_build_breed(list, v, m, uid)
	# 進階馬積點 (bpts): 揀屬性上限 +1
	if int(m.get("bpts", 0)) > 0:
		list.add_child(hsep())
		list.add_child(lbl("進階積點 %d：揀屬性上限 +1" % int(m["bpts"]), 15, UiTheme.GOLD))
		var bg := _grid(5)
		list.add_child(bg)
		var an2: Dictionary = cfg["attrNames"]
		for at2 in cfg["attrs"]:
			var aa2: String = at2
			bg.add_child(_fill(btn(String(an2[aa2]).substr(0, 2), func() -> void: main._send({"t": "mount_spend_bpt", "uid": uid, "attr": aa2}))))
	# 優秀值點數
	if int(m["points"]) > 0:
		list.add_child(hsep())
		list.add_child(lbl("優秀值點數 %d：揀屬性 +1" % int(m["points"]), 15, UiTheme.GOLD))
		var pg := _grid(5)
		list.add_child(pg)
		for at in cfg["attrs"]:
			var aa: String = at
			pg.add_child(_fill(btn(String(an[aa]).substr(0, 2), func() -> void: main._send({"t": "mount_point", "uid": uid, "attr": aa}))))
	# 丟棄
	list.add_child(hsep())
	var db := btn("確定丟棄？再撳一下" if confirm_drop else "丟棄荒野", func() -> void:
		if confirm_drop:
			confirm_drop = false
			main._send({"t": "mount_abandon", "uid": uid})
		else:
			confirm_drop = true
			refresh(true))
	db.disabled = grazing
	if confirm_drop:
		db.add_theme_color_override("font_color", UiTheme.BAD)
	list.add_child(db)


# 揀道具: 背包入面呢個動作用得嘅嘢
func _build_pick(list: VBoxContainer, uid: int, act: String) -> void:
	var items: Array = _mcfg()["acts"][act]["items"]
	var any := false
	for b in main.ch.get("bag", []):
		var it := int(b["id"])
		if not (items.has(it) or items.has(float(it))):
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(wrap_lbl("%s ×%d　%s" % [item_name(it), int(b["n"]), _eff_text(it)], 14))
		row.add_child(btn("用", func() -> void: main._send({"t": "mount_act", "uid": uid, "act": act, "item": it}), 64))
		list.add_child(row)
	if not any:
		list.add_child(wrap_lbl("背包冇啱用嘅道具，去馬廄買（飼料 / 玩具 / 寵物藥）。", 14, UiTheme.DIM))


# 繁衍 (Step 17b, spec 07 §6): 未配種 → 揀種馬品種配種；配咗種 → 胎教小遊戲 + 懶人開關 + 接生
func _build_breed(list: VBoxContainer, v: Dictionary, m: Dictionary, uid: int) -> void:
	var cfg := _mcfg()
	list.add_child(hsep())
	var preg: Dictionary = m.get("preg", {})
	if preg.is_empty():
		list.add_child(lbl("繁衍：借種馬配種（%d 金）" % int(cfg["studPrice"]), 15, UiTheme.GOLD))
		var why := String(m["breedWhy"])
		if why == "" and String(v["stable"]) == "":
			why = "要去馬廄先配得種"
		if why != "":
			list.add_child(wrap_lbl(why, 13, UiTheme.DIM))
			return
		var g := _grid(3)
		list.add_child(g)
		for b in v["breeds"]:
			var bid := String(b["id"])
			var bb := _fill(btn(b["name"], func() -> void:
				pick_sire = "" if pick_sire == bid else bid
				refresh(true)))
			if pick_sire == bid:
				bb.add_theme_color_override("font_color", UiTheme.GOLD)
			g.add_child(bb)
		if pick_sire != "":
			var cb := btn("確定配種「%s」" % pick_sire, func() -> void:
				main._send({"t": "mount_breed_start", "uid": uid, "sire": pick_sire})
				pick_sire = "")
			cb.disabled = int(v["gold"]) < int(cfg["studPrice"])
			list.add_child(cb)
		return
	# 配咗種: 胎教
	var bcfg: Dictionary = cfg["breed"]
	list.add_child(lbl("胎教：動情值 %d/%d　胎氣 %d/%d%s" % [int(preg["motive"]), int(bcfg["motiveCap"]),
		int(preg["taiqi"]), int(preg["taiqiNeed"]), "　（懶人胎教中）" if bool(preg["lazy"]) else ""], 15, UiTheme.GOLD))
	if bool(preg["ready"]):
		list.add_child(btn("胎氣夠喇！接生", func() -> void: main._send({"t": "mount_breed_claim", "uid": uid})))
		return
	var play_why := String(preg["playWhy"])
	if play_why != "":
		list.add_child(wrap_lbl(play_why, 13, UiTheme.DIM))
	else:
		var bets: Array = bcfg["bets"]
		var g2 := _grid(3)
		list.add_child(g2)
		for i in bets.size():
			var ci := i
			g2.add_child(_fill(btn(String(bets[i]), func() -> void: main._send({"t": "mount_breed_bet", "uid": uid, "choice": ci}))))
	var lazy := bool(preg["lazy"])
	list.add_child(btn("懶人胎教：%s（開咗自動 %d 日後生，積點封頂 %d）" % ["開" if not lazy else "關", int(bcfg["lazyDays"]), int(bcfg["lazyBpts"])],
		func() -> void: main._send({"t": "mount_breed_lazy", "uid": uid, "on": not lazy})))


# 道具效果簡述 (效果碼 → 中文)
func _eff_text(it: int) -> String:
	var cfg := _mcfg()
	var keys: Dictionary = cfg["effectKeys"]
	var names: Dictionary = cfg["attrNames"]
	var extra := {"satiety": "飽食", "fatigue": "疲勞", "mood": "情緒", "life": "生命"}
	var out: Array = []
	for e in main.data.info.get(it, {}).get("effects", []):
		var k := String(keys.get(str(int(e["type"])), ""))
		if k == "":
			continue
		var v := RulesMount.eff_value(int(e["value"]))
		if k.begins_with("cure:"):
			out.append("治%s" % cfg["statuses"][k.substr(5)]["name"])
		else:
			out.append("%s%+d" % [String(names.get(k, extra.get(k, k))).substr(0, 2), v])
	return " ".join(out)


# ---- 頁 1: 馬廄 ----
func _build_stable(list: VBoxContainer, v: Dictionary) -> void:
	var cfg := _mcfg()
	var at := String(v["stable"])
	var at_name := String(main.data.facilities.get(at, {}).get("name", ""))
	var ms: Array = v["list"]
	list.add_child(wrap_lbl("%s　金 %d　座騎 %d/%d" % ["喺" + at_name if at != "" else "唔喺馬廄（寄養 / 領馬 / 買馬要去馬廄）",
		int(v["gold"]), ms.size(), int(cfg["maxOwned"])], 15, UiTheme.TEXT if at != "" else UiTheme.DIM))
	var pf: Dictionary = v.get("pendingFoal", {})
	if not pf.is_empty():
		var fb := btn("提領小馬（%s，%s）" % [RulesMount.breed_def(cfg, String(pf["breed"]))["name"], "母" if String(pf["sex"]) == "f" else "公"],
			func() -> void: main._send({"t": "mount_take_foal"}))
		fb.disabled = at == "" or ms.size() >= int(cfg["maxOwned"])
		list.add_child(fb)
	for m in ms:
		var uid := int(m["uid"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var where: String = {"with": "身邊", "graze": "放牧中", "stable": "寄喺" + String(m["stableName"])}.get(String(m["where"]), "")
		row.add_child(wrap_lbl("%s（%s・%s）親密 %d　%s" % [m["name"], m["breed"], m["stageName"], int(m["intimacy"]), where], 14))
		if String(m["where"]) == "stable":
			var b := btn("領出", func() -> void: main._send({"t": "mount_take", "uid": uid}), 72)
			b.disabled = at == ""
			row.add_child(b)
		elif String(m["where"]) == "with":
			var b2 := btn("寄低", func() -> void: main._send({"t": "mount_stable", "uid": uid}), 72)
			b2.disabled = at == ""
			row.add_child(b2)
		list.add_child(row)
	if at == "":
		return
	list.add_child(hsep())
	var full := ms.size() >= int(cfg["maxOwned"])
	var gold := int(v["gold"])
	list.add_child(lbl("買幼馬（%d 金，要自己養 30 日先成年）" % int(cfg["foalPrice"]), 15, UiTheme.GOLD))
	var g := _grid(3)
	list.add_child(g)
	var tn: Dictionary = cfg["attrNames"]
	for b in cfg["breeds"]:
		var bid := String(b["id"])
		var tr_name := String(tn.get(String(b["trait"]), "平均")).substr(0, 2)
		var bb := _fill(btn("%s(%s)" % [b["name"], tr_name], func() -> void: main._send({"t": "mount_buy", "breed": bid})))
		bb.disabled = full or gold < int(cfg["foalPrice"])
		g.add_child(bb)
	var tm: Dictionary = cfg["tamed"]
	var tb := RulesMount.breed_def(cfg, String(tm["breed"]))
	var tbtn := btn("買已養大嘅%s（成年、親密 %d，%d 金）" % [tb["adult"], int(tm["intimacy"]), int(tm["price"])],
		func() -> void: main._send({"t": "mount_buy", "breed": String(tm["breed"]), "tamed": true}))
	tbtn.disabled = full or gold < int(tm["price"])
	list.add_child(tbtn)
	list.add_child(btn("馬用品（飼料 / 玩具 / 寵物藥 / 馴馬專用哨）", func() -> void:
		main.hud.shop_panel().open_shop({"stock": cfg["stableStock"], "shopName": at_name})))
	_build_battle(list, v, gold)
	list.add_child(hsep())
	list.add_child(lbl("簡易養馬指南", 15, UiTheme.GOLD))
	for t in cfg["tips"]:
		list.add_child(wrap_lbl("・" + String(t), 13, UiTheme.DIM))


# 馬戰 (Step 17b, spec 07 §7): 兵器買 3 級 + 特技拜師學（最多 3 招）
func _build_battle(list: VBoxContainer, v: Dictionary, gold: int) -> void:
	var mw: Dictionary = main.data.mount_weapons
	var level := int(main.ch["level"])
	var cur_wid := String(v["mountWeapon"])
	list.add_child(hsep())
	list.add_child(lbl("馬戰兵器（現裝：%s）" % (RulesMountBattle.weapon_def(mw, String(v["mountWeaponType"]), cur_wid).get("name", "無") if cur_wid != "" else "無"), 15, UiTheme.GOLD))
	for wtype in v["mountWeapons"]:
		var trow := HBoxContainer.new()
		trow.add_theme_constant_override("separation", 6)
		list.add_child(trow)
		trow.add_child(lbl(String(mw["types"].get(wtype, wtype)), 14, UiTheme.DIM))
		var g := _grid(3)
		list.add_child(g)
		for w in v["mountWeapons"][wtype]:
			var wid := String(w["id"])
			var owned := wid == cur_wid
			var b := _fill(btn("%s%s（Lv%d，%d 金）" % ["✓" if owned else "", w["name"], int(w["lv"]), int(w["price"])],
				func() -> void: main._send({"t": "mount_weapon_buy", "wtype": wtype, "wid": wid})))
			b.disabled = owned or level < int(w["lv"]) or gold < int(w["price"])
			if owned:
				b.add_theme_color_override("font_color", UiTheme.GOLD)
			g.add_child(b)
	var learned: Array = v["mountSkills"]
	list.add_child(hsep())
	list.add_child(lbl("馬戰特技（拜師 %d 金，最多學 %d 招，要有對應兵器）" % [int(mw["teachPrice"]), int(mw["maxSkills"])], 15, UiTheme.GOLD))
	var sg := _grid(3)
	list.add_child(sg)
	for s in v["mountSkillDefs"]:
		var sid := String(s["id"])
		var known := learned.has(sid)
		var b2 := _fill(btn("%s%s（%s）" % ["✓" if known else "", s["name"], String(mw["types"].get(String(s["weapon"]), ""))],
			func() -> void: main._send({"t": "mount_skill_learn", "skill": sid})))
		b2.disabled = known or learned.size() >= int(mw["maxSkills"]) or gold < int(mw["teachPrice"])
		if known:
			b2.add_theme_color_override("font_color", UiTheme.GOLD)
		sg.add_child(b2)
