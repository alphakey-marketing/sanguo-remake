class_name CampPanel
extends GamePanel
# 營地面板 (U09，spec 08 §7): 頁 0「設施」升級/監督建設；頁 1「工作」22 項義勇軍工作；
# 頁 2「評定」指派本月工作 + 召開評定會議；頁 3「倉庫」庫存/商情/訓練度。
# 全部讀 sim 既有 read-model（camp_view/militia_work_view/eval_view），經 main._send 發意圖。


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "營地"
	tab_names = ["設施", "工作", "評定", "倉庫"]


func open_tab(i: int) -> void:
	tab = i
	set_tabs(tab_names)
	open()


func sig() -> String:
	return JSON.stringify([tab, main.sim.camp_view(main.my_id), main.sim.militia_work_view(main.my_id), main.sim.eval_view(main.my_id)])


func _build_body() -> void:
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	var v: Dictionary = main.sim.camp_view(main.my_id)
	if v.is_empty():
		list.add_child(wrap_lbl("讀取唔到角色資料。", 14, UiTheme.DIM))
		return
	if not bool(v.get("founded", false)):
		list.add_child(wrap_lbl("未成立義勇軍，起唔到營地。", 14, UiTheme.DIM))
		return
	list.add_child(wrap_lbl("「%s」　根據地 %s　營地 %d 級　%s" %
		[String(v.get("roleName", "")), String(v["cityName"]), int(v["level"]), "（喺根據地）" if bool(v.get("atHome", false)) else "（唔喺根據地）"], 14, UiTheme.GOLD))
	list.add_child(wrap_lbl("功績 %d　本期績效 %d　工作指派上限 %d" % [int(v.get("merit", 0)), int(v.get("performance", 0)), int(v.get("workCap", 0))], 13))
	list.add_child(hsep())
	match tab:
		0: _build_facilities(list, v)
		1: _build_works(list, v)
		2: _build_eval(list, v)
		_: _build_stores(list, v)


# ---- 頁 0: 設施 ----
func _build_facilities(list: VBoxContainer, v: Dictionary) -> void:
	var can_upgrade := bool(v.get("canUpgradeRole", false))
	var build: Dictionary = v.get("build", {})
	if not build.is_empty():
		list.add_child(wrap_lbl("建設緊：「%s」→ %d 級　完成度 %.1f/%.1f" %
			[String(build.get("fac", "")), int(build.get("target", 0)), float(build.get("progress", 0.0)), float(build.get("need", 100))], 14, UiTheme.GOLD))
		list.add_child(btn("監督（等同義勇軍工作「監督」）", func() -> void:
			main._send({"t": "camp_supervise", "fac": String(build.get("fac", ""))})))
		list.add_child(hsep())
	if not can_upgrade:
		list.add_child(wrap_lbl("得頭目/參軍先指定到升級（其他人可以「監督」建設中設施）。", 14, UiTheme.DIM))
	for f in (v.get("facilities", []) as Array):
		var fd := f as Dictionary
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var hd := HBoxContainer.new()
		hd.add_theme_constant_override("separation", 6)
		hd.add_child(wrap_lbl("%s　%d 級" % [String(fd["name"]), int(fd["level"])], 14))
		if fd.has("cost") and can_upgrade and build.is_empty():
			var cost: Dictionary = fd["cost"]
			var b := btn("升級 (%d 兩)" % int(cost.get("gold", 0)), func() -> void:
				main._send({"t": "camp_upgrade", "fac": String(fd["id"])}), 110)
			hd.add_child(b)
		elif fd.has("cost"):
			hd.add_child(wrap_lbl("(未達封頂)", 12, UiTheme.DIM))
		else:
			hd.add_child(wrap_lbl("已封頂", 12, UiTheme.DIM))
		row.add_child(hd)
		row.add_child(wrap_lbl(String(fd.get("func", "")), 12, UiTheme.DIM))
		list.add_child(row)


# ---- 頁 1: 工作 ----
func _build_works(list: VBoxContainer, v: Dictionary) -> void:
	var wv: Dictionary = main.sim.militia_work_view(main.my_id)
	if wv.is_empty():
		return
	list.add_child(wrap_lbl("行動力消耗：每次 %d" % int(wv.get("apCost", 0)), 13, UiTheme.DIM))
	list.add_child(hsep())
	var series := {}
	for w in (wv.get("works", []) as Array):
		var wd := w as Dictionary
		var s := String(wd.get("series", ""))
		if not series.has(s):
			series[s] = []
		(series[s] as Array).append(wd)
	for s in series.keys():
		list.add_child(lbl(String(s), 14, UiTheme.GOLD))
		for wd2 in (series[s] as Array):
			var wdd := wd2 as Dictionary
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var tag := "（獲指派）" if bool(wdd.get("assigned", false)) else ""
			row.add_child(wrap_lbl("%s%s　績效+%d" % [String(wdd["name"]), tag, int(wdd.get("perf", 0))], 13))
			var can := bool(wdd.get("can", false))
			var wid := String(wdd["id"])
			var b := btn("做" if can else String(wdd.get("why", "")), func() -> void:
				main._send({"t": "militia_work", "work": wid}), 100)
			b.disabled = not can
			row.add_child(b)
			list.add_child(row)


# ---- 頁 2: 評定 ----
func _build_eval(list: VBoxContainer, _v: Dictionary) -> void:
	var ev: Dictionary = main.sim.eval_view(main.my_id)
	if ev.is_empty():
		return
	list.add_child(wrap_lbl("本期績效 %d　預估功績變動 %+d" % [int(ev.get("performance", 0)), int(ev.get("nextDelta", 0))], 14))
	if int(ev.get("lastDay", -1)) >= 0:
		list.add_child(wrap_lbl("上次結算：績效 %d → 功績 %+d" % [int(ev.get("lastMerit", 0)), int(ev.get("lastMerit", 0))], 12, UiTheme.DIM))
	list.add_child(hsep())
	list.add_child(lbl("本月指派工作（最多 %d 種）" % int(ev.get("maxAssignments", 0)), 14, UiTheme.GOLD))
	var kinds: Array = ev.get("kinds", [])
	var boxes := {}
	for k in (ev.get("assignmentKinds", []) as Array):
		var ks := String(k)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var cb := CheckBox.new()
		cb.button_pressed = kinds.has(ks)
		boxes[ks] = cb
		row.add_child(cb)
		row.add_child(wrap_lbl(_kind_name(ks), 14))
		list.add_child(row)
	var pick := func() -> Array:
		var out: Array = []
		for k2 in boxes.keys():
			if (boxes[k2] as CheckBox).button_pressed:
				out.append(k2)
		return out
	list.add_child(btn("指派", func() -> void: main._send({"t": "eval_assign", "kinds": pick.call()}), 100))
	list.add_child(btn("召開評定會議（頭目限定：結算 + 重新指派）", func() -> void: main._send({"t": "eval_meeting", "kinds": pick.call()})))


func _kind_name(k: String) -> String:
	match k:
		"donate": return "捐獻"
		"supervise": return "監督"
		"trade": return "商情"
	return k


# ---- 頁 3: 倉庫 ----
func _build_stores(list: VBoxContainer, v: Dictionary) -> void:
	list.add_child(lbl("庫存", 15, UiTheme.GOLD))
	var stores: Dictionary = v.get("stores", {})
	if stores.is_empty():
		list.add_child(wrap_lbl("暫時冇庫存。", 14, UiTheme.DIM))
	for k in stores.keys():
		list.add_child(wrap_lbl("%s：%d" % [String(k), int(stores[k])], 14))
	list.add_child(hsep())
	list.add_child(lbl("商情情報值", 15, UiTheme.GOLD))
	var trade: Dictionary = v.get("trade", {})
	if trade.is_empty():
		list.add_child(wrap_lbl("暫時冇情報。", 14, UiTheme.DIM))
	for c in trade.keys():
		list.add_child(wrap_lbl("%s：%d" % [String(c), int(trade[c])], 14))
	list.add_child(hsep())
	list.add_child(wrap_lbl("訓練度：%d" % int(v.get("train", 0)), 14, UiTheme.GOLD))
	_build_adv(list, v)


# ---- 營地進階 (召喚部將 / 材料庫轉入轉出 / 兵營情報) ----
func _build_adv(list: VBoxContainer, v: Dictionary) -> void:
	var adv: Dictionary = v.get("adv", {})
	list.add_child(hsep())
	list.add_child(lbl("進階功能", 15, UiTheme.GOLD))
	var atk := bool(v.get("atHome", false))
	if not atk:
		list.add_child(wrap_lbl("返到根據地先用得。", 13, UiTheme.DIM))
	var intel: Dictionary = main.sim.camp_intel_view(main.my_id)
	list.add_child(lbl("兵營情報", 14))
	if not bool(intel.get("ok", false)):
		list.add_child(wrap_lbl(String(intel.get("why", "")), 13, UiTheme.DIM))
	for g in (intel.get("generals", []) as Array):
		var gd := g as Dictionary
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(wrap_lbl("%s　戰等 %d　%s" % [String(gd["name"]), int(gd["lv"]), String(gd["status"])], 13))
		if String(gd["status"]) == "今月外出" and int(v["level"]) >= int(adv.get("callBackLevel", 5)):
			var gid := int(gd["id"])
			row.add_child(btn("召喚回營 (餘 %d)" % int(v.get("callBackLeft", 0)), func() -> void:
				main._send({"t": "camp_call_back", "gid": gid}), 130))
		list.add_child(row)
	list.add_child(lbl("材料庫", 14))
	var mi: Dictionary = v.get("matItems", {})
	if mi.is_empty():
		list.add_child(wrap_lbl("材料庫空。", 13, UiTheme.DIM))
	for k in mi.keys():
		var item := int(k)
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 6)
		row2.add_child(wrap_lbl("%s ×%d" % [String(main.sim.data.names.get(item, k)), int(mi[k])], 13))
		row2.add_child(btn("轉出", func() -> void:
			main._send({"t": "camp_mat", "item": item, "n": 1, "dir": "out"}), 70))
		list.add_child(row2)
	list.add_child(wrap_lbl("轉入：喺背包揀材料 (材料庫 %d 級起)、轉出 (%d 級起)。" % [int(adv.get("matInLevel", 9)), int(adv.get("matOutLevel", 10))], 12, UiTheme.DIM))
