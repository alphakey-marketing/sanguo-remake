class_name ContextActions
extends RefCounted
# 互動掣（三國群英傳M 嘅「對話」掣）: 行近邊樣嘢就顯示對應動作，撳 = 開面板/對話框。
# 任務答題最優先；其餘揀最近嗰個 NPC/設施（同距離 NPC 先）；野外有初階工具 (裝咗/背包) = 工作
# 全部經 main._send 發意圖；對話框內容由 source Callable 即時計（sim 權威）。

const NEAR := 3               # 同 sim_core.NEAR 一致


static func find(main: Node) -> Dictionary:
	if main.ch.is_empty():
		return {}
	var ask: Dictionary = main._active_ask()
	if not ask.is_empty():
		return {"kind": "ask", "label": "答題"}
	var me = main._me()
	if me == null:
		return {}
	# 最近嗰樣贏（同距離 NPC 優先）: 客棧門口企住個 NPC 都唔會搶走客棧
	var best := {}
	var bd := NEAR + 1
	for qn in main.quest_npcs:
		var d := _dist(me, int(qn.x), int(qn.y))
		if d < bd:
			bd = d
			best = {"kind": "quest_npc", "label": "對話", "ref": qn}
	var f := nearest_facility(main, me)
	if not f.is_empty() and _dist(me, int(f.x), int(f.y)) < bd:
		match String(f.kind):
			"shop": best = {"kind": "shop", "label": "商店", "ref": f}
			"inn": best = {"kind": "inn", "label": "客棧", "ref": f}
			"fac": best = {"kind": "fac", "label": str(main.data.facilities[f.fac]["name"]).substr(0, 3), "ref": f}
			"travel": best = {"kind": "travel", "label": "傳送", "ref": f}
	if not best.is_empty():
		return best
	if not main.sim.is_safe(int(me.x), int(me.y)) and has_work_tool(main):
		return {"kind": "work", "label": "工作"}
	return {}


# 有冇初階工具 (裝咗或者喺背包)
static func has_work_tool(main: Node) -> bool:
	var tools: Dictionary = main.ch.get("tools", {})
	for sk in main.data.work:
		if tools.has(sk):
			return true
	for b in main.ch.get("bag", []):
		if main.data.work.has(String(main.data.tool_skill.get(int(b["id"]), ""))):
			return true
	return false


static func _dist(me: Dictionary, x: int, y: int) -> int:
	return maxi(absi(int(me.x) - x), absi(int(me.y) - y))


static func _near(me: Dictionary, x: int, y: int) -> bool:
	return _dist(me, x, y) <= NEAR


# 最近嘅設施（商店/客棧/練兵場…/傳送點）
static func nearest_facility(main: Node, me: Dictionary) -> Dictionary:
	var best := {}
	var bd := 1 << 30
	for f in main.facilities:
		var d := _dist(me, int(f.x), int(f.y))
		if d <= NEAR and d < bd:
			bd = d
			best = f
	return best


static func run(main: Node, act: Dictionary) -> void:
	var hud = main.hud
	match String(act.get("kind", "")):
		"ask":
			hud.open_dialog(func() -> Dictionary: return ask_dialog(main))
		"quest_npc":
			main._send({"t": "quest_talk", "npc": String(act.ref.id)})
		"shop":
			hud.shop_panel().open_shop(act.ref)
		"inn":
			hud.open_dialog(func() -> Dictionary: return inn_dialog(main))
		"fac":
			var f: Dictionary = act.ref
			var def: Dictionary = main.data.facilities[f.fac]
			if def.has("crafts"):                 # 廚房/藥房/工房 (Step 12)
				hud.craft_panel().open_craft(str(def["name"]), def["crafts"])
			elif bool(def.get("repair", false)) and String(f.fac) != "forge":
				hud.craft_panel().open_service(str(def["name"]))
			else:
				hud.open_dialog(func() -> Dictionary: return fac_dialog(main, f))
		"travel":
			main._send({"t": "travel", "point": String(act.ref.point)})
		"work":
			hud.open_dialog(func() -> Dictionary: return work_dialog(main))


static func _leave(main: Node) -> Dictionary:
	return {"label": "離開", "cb": func() -> void: main.hud.close_panels()}


static func ask_dialog(main: Node) -> Dictionary:
	var ask: Dictionary = main._active_ask()
	if ask.is_empty():
		return {}
	var dl: Array = ask["dialog"]
	var opts: Array = []
	var q := str(ask["q"])
	for i in (ask["options"] as Array).size():
		var idx := i
		opts.append({"label": str(ask["options"][i]), "cb": func() -> void: main._send({"t": "quest_answer", "quest": q, "answer": idx})})
	return {"title": "答題", "text": "\n".join(dl) if not dl.is_empty() else "答題！", "options": opts}


# 野外工作 (Step 12): 每個有工具嘅初階技能一個掣；背包有工具未裝 = 「裝備」
static func work_dialog(main: Node) -> Dictionary:
	var ch: Dictionary = main.ch
	var tools: Dictionary = ch.get("tools", {})
	var opts: Array = []
	var lines: Array = []
	for sk in main.data.work:
		var w: Dictionary = main.data.work[sk]
		var lv: int = main.sim.work_lv(ch, sk)
		var skill := String(sk)
		if tools.has(sk):
			lines.append("%s Lv%d  工具耐久 %d" % [w["name"], lv, int(tools[sk]["dur"])])
			opts.append({"label": "%s" % w["name"], "cb": func() -> void: main._send({"t": "work", "skill": skill})})
			continue
		for tid in [int(w["tool"]), int(w["starterTool"])]:
			if RulesShop.count_item(ch.get("bag", []), tid) > 0:
				var t: int = tid
				opts.append({"label": "裝%s" % main.item_names.get(tid, "工具"), "cb": func() -> void: main._send({"t": "equip_tool", "skill": skill, "item": t})})
				break
	opts.append(_leave(main))
	var text := "\n".join(lines) if not lines.is_empty() else "未裝工具：撳「裝…」裝備背包入面嘅工具。"
	return {"title": "工作", "text": text + "\nSP %d（每次扣 10%% 最大 SP）" % int(ch.get("sp", 0)), "options": opts}


static func inn_dialog(main: Node) -> Dictionary:
	var ch: Dictionary = main.ch
	var cost := int(main.inn_cost)
	var gold := int(ch.get("gold", 0))
	return {"title": "客棧", "text": "住宿 %d 金：回滿 HP / MP / SP。\n你而家有 %d 金。" % [cost, gold],
		"options": [{"label": "休息 (%d 金)" % cost, "cb": func() -> void: main._send({"t": "rest"}), "disabled": gold < cost}, _leave(main)]}


static func fac_dialog(main: Node, f: Dictionary) -> Dictionary:
	var ch: Dictionary = main.ch
	var key := String(f.fac)
	var def: Dictionary = main.data.facilities[key]
	if key == "forge":
		return forge_dialog(main, def)
	if bool(def.get("donation", false)):
		return donate_dialog(main, def)
	var text := str(def.get("desc", ""))
	if key == "training":
		text += "\n歷練 %d/100（下次升級 武/智/敏/靈 +%d）" % [int(ch.get("lilian", 0)), int(ch.get("lilian", 0)) / 10]
	else:
		var attr := str(def.get("attr", ""))
		text += "\n%s 而家 %d" % ["政治" if attr == "pol" else "魅力", int(ch["attrs"].get(attr, 0))]
	text += "\n金 %d" % int(ch.get("gold", 0))
	return {"title": str(def["name"]), "text": text,
		"options": [{"label": "使用", "cb": func() -> void: main._send({"t": "facility", "key": key})}, _leave(main)]}


# 捐贈官令 (Step 13): 捐金錢 3 檔 / 捐晒背包物資
static func donate_dialog(main: Node, def: Dictionary) -> Dictionary:
	var ch: Dictionary = main.ch
	var cfg: Dictionary = main.data.donation
	var gold := int(ch.get("gold", 0))
	var ap: int = main.sim.ap_of(ch)
	var can := ap >= int(cfg["apCost"])
	var items: Array = main.sim.donatable_items(ch)
	var counts := {}
	for it in items:
		counts[int(it[0])] = int(it[1])
	var units := RulesTiandi.donation_units(counts, main.data.donation_rates)
	var text := "%s\n名聲 %d　行動力 %d/%d（每次捐扣 %d）\n金 %d　可捐物資 %d 單位（%d 起）" %[str(def.get("desc", "")),
		int(ch.get("fame", 0)), ap, main.sim.ap_max(ch), int(cfg["apCost"]), gold, units, int(cfg["unitsMin"])]
	var opts: Array = []
	for amt in [int(cfg["goldMin"]), 10000, int(cfg["goldMax"])]:
		var a: int = amt
		opts.append({"label": "捐 %d 金" % a, "cb": func() -> void: main._send({"t": "donate_gold", "amount": a}),
			"disabled": gold < a or not can})
	opts.append({"label": "捐晒物資 (%d 單位)" % units, "cb": func() -> void: main._send({"t": "donate_items", "items": items}),
		"disabled": units < int(cfg["unitsMin"]) or not can})
	opts.append(_leave(main))
	return {"title": str(def["name"]), "text": text, "options": opts}


# 打鐵鋪（義士融合 QTE）: 未開始 = 「開始融合」；開始咗 = 集氣棒 + 「敲！」
static func forge_dialog(main: Node, def: Dictionary) -> Dictionary:
	var ch: Dictionary = main.ch
	var fs: Dictionary = ch.get("fusing", {})
	if fs.is_empty():
		var yishi := str(ch.get("classId", "")) == "yishi"
		return {"title": str(def.get("name", "打鐵鋪")),
			"text": "融合【義士】：將屬性石燒入裝緊嗰把武器（只能 1 粒）。\n要: 背包有屬性石 + 武器未嵌石 + 10 級以上。",
			"options": [{"label": "開始融合", "cb": func() -> void: main._send({"t": "fusion_start"}), "disabled": not yishi},
				{"label": "修理服務", "cb": func() -> void: main.hud.craft_panel().open_service(str(def.get("name", "打鐵鋪")))}, _leave(main)]}
	var jd: Dictionary = main.data.jewel_by_item.get(int(fs["jewel"]), {})
	var start := int(fs["start"])
	return {"title": "融合中", "text": "%s → %s\n指針入金色窗口就撳「敲！」" % [jd.get("name", "?"), main.item_names.get(int(fs["weapon"]), "?")],
		"qte": func() -> float: return RulesJewel.fusion_pos(main.sim.tick - start),
		"options": [{"label": "敲！", "cb": func() -> void: main._send({"t": "fusion_hit"})}]}
