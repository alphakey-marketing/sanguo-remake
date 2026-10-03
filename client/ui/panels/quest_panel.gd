class_name QuestPanel
extends GamePanel
# 記事面板: 進行中任務（全文提示，可以拖捲）/ 已完成 / 戰役 / 場景 / 指引。

const TYPE_LABEL := {
	"newbie": "新手", "general": "職業/特技", "ultimate": "絕招", "history": "歷史",
	"group": "義勇軍", "expert": "專長", "marry": "結婚",
}
const TYPE_ORDER := ["newbie", "general", "ultimate", "history", "expert", "group", "marry"]
var _guide_open := {}          # quest id -> bool，指引頁撳落展開/摺埋詳情

func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "任務"
	set_tabs(["進行中", "完成", "戰役", "場景", "地標", "指引"])


func sig() -> String:
	return JSON.stringify([tab, main.sim.view_quests(), main.sim.view_commissions(),
		main.sim.view_battles(main.my_id), main.sim.view_scenes(main.my_id)])


func _build_body() -> void:
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	sc.add_child(list)
	var n := 0
	for q in main.sim.view_quests():
		if tab > 1:           # 戰役/場景/指引唔應該顯示呢個進行中/完成 quest list
			break
		var act := bool(q.get("active", false))
		var done := bool(q.get("done", false))
		if (tab == 0 and not act) or (tab == 1 and not done):
			continue
		n += 1
		list.add_child(lbl(("● " if act else "✓ ") + str(q["name"]), 16, UiTheme.GOLD if act else UiTheme.GOOD))
		if act and str(q.get("hint", "")) != "":
			list.add_child(wrap_lbl("　" + str(q["hint"]), 14, UiTheme.TEXT))
	if tab == 0:                           # 居民委託 (Step 16)
		for c in main.sim.view_commissions():
			n += 1
			list.add_child(lbl("◆ 委託・%s" % c["name"], 16, UiTheme.GOLD))
			list.add_child(wrap_lbl("　%s%s（仲有 %d 日，報酬 %s）" % [c["text"], "　可以覆命" if bool(c["ready"]) else "",
				int(c["left"]), c["reward"]], 14, UiTheme.TEXT))
	if n == 0 and tab < 2:
		list.add_child(lbl("未有任務 — 去城門口搵神秘老人" if tab == 0 else "未完成任何任務", 14, UiTheme.DIM))
	if tab == 2:                           # 戰役日程 (S04c, spec 06 §7 / spec 04 §5)
		_battle_section(list)
	if tab == 3:                           # 特殊場景日程 (S04d, spec 04 §4)
		_scene_section(list)
	if tab == 4:                           # 地標典籍 (UAT-feedback): 探到嘅史蹟可重睇典故
		_landmark_section(list)
	if tab == 5:                           # 任務指引 (U17): 全部任務點揀/邊度接，靜態查詢，唔碰 sim
		_guide_section(list)


func _battle_section(list: Node) -> void:
	var vb: Dictionary = main.sim.view_battles(main.my_id)
	list.add_child(lbl("今日戰役（每日窗口重開，武等上限內先入得）", 14, UiTheme.TEXT))
	for b in vb["list"]:
		var open := bool(b["open"])
		list.add_child(lbl("%s%s　%s（武≤%d）　%s" % ["● " if open else "○ ", b["name"],
			RulesClock.format_ke(int(b["startKe"])), int(b["maxLevel"]),
			RulesClock.format_ke(int(b["endKe"]))], 15, UiTheme.GOLD if open else UiTheme.TEXT))
	if bool(vb["inBattle"]):
		list.add_child(lbl("── 而家喺戰役入面 ──", 15, UiTheme.GOLD))
		list.add_child(wrap_lbl("%s 第 %d/%d 層，打完自動離場；內陣亡唔跌經驗/物品" % [vb["battleName"],
			int(vb["floor"]), int(vb["totalFloors"])], 14, UiTheme.TEXT))
	else:
		list.add_child(wrap_lbl("去「義勇士兵」（許昌練兵場）報名，打贏尾層大頭目即完成。", 14, UiTheme.DIM))


# 特殊場景日程 (S04d, spec 04 §4): game 日曆窗口開門 + 玩家進度
func _scene_section(list: Node) -> void:
	var vs: Dictionary = main.sim.view_scenes(main.my_id)
	list.add_child(lbl("特殊場景（game 日曆開門）　今日 = %d日" % int(vs["dayOfMonth"]), 14, UiTheme.TEXT))
	for s in vs["list"]:
		var open := bool(s["open"])
		list.add_child(lbl("%s%s　（武等 ≥%d，每月%s）" % ["● " if open else "○ ", s["name"],
			int(s["minLevel"]), s["openDays"]], 15, UiTheme.GOLD if open else UiTheme.TEXT))
	if bool(vs["inScene"]):
		list.add_child(lbl("── 而家喺場景入面 ──", 15, UiTheme.GOLD))
		list.add_child(wrap_lbl("%s 第 %d/%d 層；打完每層大頭目過下一層，尾層打完自動離開；內陣亡唔跌經驗/物品" % [
			vs["sceneName"], int(vs["layer"]), int(vs["totalLayers"])], 14, UiTheme.TEXT))
	else:
		list.add_child(wrap_lbl("去荊州港口搵場景入口（開門日先入得）。", 14, UiTheme.DIM))


# 地標典籍 (UAT-feedback, spec 12 §5): 按地圖列出探到嘅史蹟地標，撳開得（▸▾）重睇典故全文
var _lm_open := {}
func _landmark_section(list: Node) -> void:
	var lms: Array = main.sim.view_landmarks()
	if lms.is_empty():
		list.add_child(lbl("未探到任何史蹟地標——去野外城鎮踩踩（首次踏入會彈典故）", 14, UiTheme.DIM))
		return
	var total := 0
	for s in lms:
		if bool(s["seen"]):
			total += 1
	list.add_child(lbl("史蹟地標　已探 %d / %d" % [total, lms.size()], 14, UiTheme.TEXT))
	# 按地圖分組 (地圖檔順序派，決定性)
	var by_map := {}
	var order: Array = []
	for s in lms:
		var k := String(s["map"])
		if not by_map.has(k):
			by_map[k] = []
			order.append(k)
		(by_map[k] as Array).append(s)
	for mid in order:
		list.add_child(lbl("── %s ──" % str(by_map[mid][0]["mapName"]), 15, UiTheme.GOLD))
		for s in by_map[mid]:
			list.add_child(_lm_row(s))
func _lm_row(s: Dictionary) -> Node:
	var lid := String(s["id"])
	var open := bool(_lm_open.get(lid, false))
	var col := UiTheme.TEXT
	var mark := "☆"
	if bool(s["seen"]):
		mark = "●"
		col = UiTheme.GOLD
	var head := btn("%s %s %s" % [mark, str(s["name"]), "▾" if open else "▸"], func() -> void:
		_lm_open[lid] = not open
		refresh(true))
	head.add_theme_color_override("font_color", col)
	head.add_theme_color_override("font_hover_color", col)
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var box := VBoxContainer.new()
	box.add_child(head)
	if open:
		box.add_child(wrap_lbl("　　・" + str(s["text"]), 13, UiTheme.TEXT))
	return box


# 任務指引 (U17): 靜態讀 data/quests.json + quest_npcs.json，列晒全部任務點揀/邊度接，
# 唔發 sim 意圖；狀態（進行中/完成）由 sim.view_quests() 對返個 id 標記。
func _guide_section(list: Node) -> void:
	var status := {}
	for q in main.sim.view_quests():
		status[String(q["id"])] = q
	var by_type := {}
	for q in main.data.quests:
		if bool(q.get("hidden", false)):
			continue
		var t := String(q.get("type", "?"))
		if not by_type.has(t):
			by_type[t] = []
		(by_type[t] as Array).append(q)
	list.add_child(lbl("任務指引 — 全部任務點揀、邊度接", 14, UiTheme.TEXT))
	for t in TYPE_ORDER:
		if not by_type.has(t):
			continue
		list.add_child(lbl(str(TYPE_LABEL.get(t, t)), 16, UiTheme.GOLD))
		for q in by_type[t]:
			_guide_row(list, q, status.get(String(q["id"]), {}))
	_guide_battles(list)
	_guide_scenes(list)


# 指引: 戰役 (data/battles.json) 唔喺 quests.json，另外列: 邊度報名 / 武等上限 / 每層 boss + 掉寶
func _guide_battles(list: Node) -> void:
	if main.data.battles.is_empty():
		return
	list.add_child(lbl("戰役", 16, UiTheme.GOLD))
	var npc: Dictionary = main.data.quest_npcs.get("battle_herald", {})
	var where := _map_name(String(npc.get("map", "")))
	for b in main.data.battles:
		if not bool(b.get("playable", false)):
			continue
		var bid := "battle:" + String(b["id"])
		var open := bool(_guide_open.get(bid, false))
		var head := btn("☆ %s %s" % [str(b["name"]), "▾" if open else "▸"], func() -> void:
			_guide_open[bid] = not open
			refresh(true))
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(head)
		if not open:
			continue
		list.add_child(lbl("　報名：%s（%s）　武等上限 %d　開窗 %s~%s" % [str(npc.get("name", "義勇士兵")), where,
			int(b["maxLevel"]), RulesClock.format_ke(int(b["window"]["startKe"])), RulesClock.format_ke(int(b["window"]["endKe"]))],
			13, UiTheme.DIM))
		var i := 0
		for f in b["floors"]:
			i += 1
			var drops: Array = []
			for d in f["drops"]:
				drops.append(str(main.data.names.get(int(d[0]), "?")))
			list.add_child(wrap_lbl("　第%d層 %s　掉：%s" % [i, str(f["boss"]), "、".join(drops.slice(0, 4))], 13, UiTheme.DIM))


# 指引: 特殊場景 (data/scenes.json)
func _guide_scenes(list: Node) -> void:
	if main.data.scenes.is_empty():
		return
	list.add_child(lbl("特殊場景", 16, UiTheme.GOLD))
	for sc in main.data.scenes:
		list.add_child(wrap_lbl("☆ %s　（武等 ≥%d，入口：%s）" % [str(sc["name"]), int(sc.get("minLevel", 1)),
			_map_name(String(sc.get("entryMap", "")))], 13, UiTheme.TEXT))


func _guide_row(list: Node, q: Dictionary, st: Dictionary) -> void:
	var mark := "☆"
	var color := UiTheme.TEXT
	if bool(st.get("done", false)):
		mark = "✓"
		color = UiTheme.GOOD
	elif bool(st.get("active", false)):
		mark = "●"
		color = UiTheme.GOLD
	var qid := String(q["id"])
	var open := bool(_guide_open.get(qid, false))
	var head := btn("%s %s %s %s" % [mark, str(q["name"]), "" , "▾" if open else "▸"], func() -> void:
		_guide_open[qid] = not open
		refresh(true))
	head.add_theme_color_override("font_color", color)
	head.add_theme_color_override("font_hover_color", color)
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	list.add_child(head)
	if not open:
		return
	var giver := String(q.get("giver", ""))
	if giver != "":
		var npc: Dictionary = main.data.quest_npcs.get(giver, {})
		var where := _map_name(String(npc.get("map", "")))
		var npc_name := String(npc.get("name", giver))
		list.add_child(lbl("　接任務：%s（%s）" % [npc_name, where] if where != "" else "　接任務：%s" % npc_name,
			13, UiTheme.DIM))
	var pre_txt := _pre_summary(q.get("pre", {}))
	if pre_txt != "":
		list.add_child(lbl("　條件：%s" % pre_txt, 13, UiTheme.DIM))
	var hint := String(q.get("preHint", ""))
	if hint != "" and not bool(st.get("active", false)) and not bool(st.get("done", false)):
		list.add_child(wrap_lbl("　　%s" % hint, 13, UiTheme.DIM))
	if bool(st.get("active", false)) and String(st.get("hint", "")) != "":
		list.add_child(wrap_lbl("　　現況：%s" % str(st["hint"]), 13, UiTheme.TEXT))
	var reward := _reward_summary(q.get("reward", {}))
	if reward != "":
		list.add_child(lbl("　獎勵：%s" % reward, 13, UiTheme.DIM))


func _map_name(map_id: String) -> String:
	if map_id == "":
		return ""
	for md in main.data.maps:
		if String(md.get("id", "")) == map_id:
			return String(md.get("name", map_id))
	return map_id


func _reward_summary(r: Dictionary) -> String:
	var parts: Array = []
	if int(r.get("exp", 0)) > 0:
		parts.append("經驗 %d" % int(r["exp"]))
	if int(r.get("gold", 0)) > 0:
		parts.append("金 %d" % int(r["gold"]))
	for it in r.get("items", []):
		var arr: Array = it
		parts.append("%s x%d" % [item_name(int(arr[0])), int(arr[1])])
	if r.has("ultimate"):
		parts.append("絕招")
	if r.has("expert"):
		parts.append("專長認證")
	return "、".join(parts)


func _pre_summary(pre: Dictionary) -> String:
	var parts: Array = []
	if pre.has("minLevel"):
		parts.append("等級≥%d" % int(pre["minLevel"]))
	if pre.has("maxLevel"):
		parts.append("等級≤%d" % int(pre["maxLevel"]))
	if pre.has("classId"):
		parts.append("職業：%s" % str(pre["classId"]))
	if pre.has("militia"):
		parts.append("要加入義勇軍")
	if pre.has("gender"):
		parts.append("性別：%s" % str(pre["gender"]))
	if pre.has("classAny"):
		parts.append("職業之一：%s" % ", ".join(pre["classAny"]))
	for k in pre.get("attr", {}):
		parts.append("%s≥%d" % [str(k), int(pre["attr"][k])])
	return "、".join(parts)
