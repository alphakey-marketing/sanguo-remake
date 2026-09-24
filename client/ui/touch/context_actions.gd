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
	for gn in main.generals:                  # Tier1 武將 (Step 13.5)
		var d := _dist(me, int(gn.x), int(gn.y))
		if d < bd:
			bd = d
			best = {"kind": "general", "label": "人才", "ref": gn}
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
	if String(main.cur_map.get("kind", "")) == "city":      # 城池街道【原】: 調查 (登用, Step 13.5)
		return {"kind": "survey", "label": "調查"}
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
			var qn: Dictionary = act.ref
			if bool(qn.get("comm", false)):          # 居民委託人 (Step 16)
				var nid := String(qn.id)
				hud.open_dialog(func() -> Dictionary: return comm_dialog(main, nid))
			elif String(qn.get("svc", "")) == "book":  # 許昌老丈: 收集冊
				hud.open_dialog(func() -> Dictionary: return book_npc_dialog(main))
			else:
				main._send({"t": "quest_talk", "npc": String(qn.id)})
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
		"general":
			var gid := int(act.ref.id)
			hud.open_dialog(func() -> Dictionary: return general_dialog(main, gid))
		"survey":
			hud.open_panel("recruit")


static func _leave(main: Node) -> Dictionary:
	return {"label": "離開", "cb": func() -> void: main.hud.close_panels()}


# 居民委託 (Step 16): 傾偈 (送信到手亦喺度交) / 接今日委託 / 覆命 / 放棄
static func comm_dialog(main: Node, nid: String) -> Dictionary:
	var ch: Dictionary = main.ch
	var npc: Dictionary = main.data.quest_npcs[nid]
	var lines: Array = []
	var opts: Array = [{"label": "傾偈", "cb": func() -> void:
		main._send({"t": "quest_talk", "npc": nid})
		main.hud.close_panels()}]
	var act := {}
	for c in main.sim.view_commissions():
		if String(c["giver"]) == nid:
			act = c
	if not act.is_empty():
		lines.append("你接咗佢嘅委託：%s" % act["text"])
		lines.append("報酬：%s　（仲有 %d 日）" % [act["reward"], int(act["left"])])
		if String(act["kind"]) == "hunt" or String(act["kind"]) == "collect":
			opts.append({"label": "覆命", "cb": func() -> void: main._send({"t": "comm_report", "giver": nid}), "disabled": not bool(act["ready"])})
		opts.append({"label": "放棄委託", "cb": func() -> void: main._send({"t": "comm_abandon", "giver": nid})})
	else:
		var o: Dictionary = main.sim.comm_offer(ch, nid)
		if o.is_empty():
			lines.append("%s：今日冇嘢要麻煩你喇，聽日再嚟。" % npc["name"])
		else:
			lines.append("%s有個委託：%s" % [npc["name"], RulesCommission.describe(main.data, o)])
			lines.append("報酬：%s" % RulesCommission.reward_text(o["reward"]))
			var full: bool = main.sim.view_commissions().size() >= int(main.data.comm["maxActive"]) and String(o["kind"]) != "repair"
			if full:
				lines.append("（手上委託已滿 %d 單）" % int(main.data.comm["maxActive"]))
			opts.append({"label": "幫佢修" if String(o["kind"]) == "repair" else "接委託",
				"cb": func() -> void: main._send({"t": "comm_accept", "giver": nid}), "disabled": full})
	opts.append(_leave(main))
	return {"title": str(npc["name"]), "text": "
".join(lines), "options": opts}


# 許昌老丈 (Step 16): 6 屬性石換武將收集冊；有冊可以收將軍令 / 查閱
static func book_npc_dialog(main: Node) -> Dictionary:
	var ch: Dictionary = main.ch
	var bk: Dictionary = main.data.comm["book"]
	var book := int(bk["item"])
	var has_book := RulesShop.count_item(ch["bag"], book) > 0
	var names: Array = []
	var ok := true
	for s in bk["stones"]:
		var have := RulesShop.count_item(ch["bag"], int(s)) > 0
		ok = ok and have
		names.append("%s%s" % [main.data.names.get(int(s), "?"), "✓" if have else "✗"])
	var text := "老丈：「將軍令收入武將收集冊，唔佔背包位，登用時照用得。」
換冊要：%s" % "、".join(names)
	var opts: Array = []
	if has_book:
		text += "
你已經有收集冊。"
		opts.append({"label": "收入將軍令", "cb": func() -> void: main._send({"t": "book_put"})})
		opts.append({"label": "查閱收集冊", "cb": func() -> void: main.hud.open_dialog(func() -> Dictionary: return book_dialog(main))})
	else:
		opts.append({"label": "換收集冊", "cb": func() -> void: main._send({"t": "book_exchange"}), "disabled": not ok})
	opts.append(_leave(main))
	return {"title": "老丈", "text": text, "options": opts}


# 查閱武將收集冊: 每張將軍令一個「攞出」掣
static func book_dialog(main: Node) -> Dictionary:
	var list: Array = main.sim.view_book()
	var opts: Array = [{"label": "收入背包嘅將軍令", "cb": func() -> void: main._send({"t": "book_put"})}]
	var lines: Array = []
	for b in list:
		lines.append("・%s ×%d" % [b["name"], int(b["n"])])
		var it := int(b["item"])
		opts.append({"label": "攞出%s" % str(b["name"]).replace("將軍令", ""), "cb": func() -> void: main._send({"t": "book_take", "item": it})})
	opts.append(_leave(main))
	return {"title": "武將收集冊", "text": "（冊內未有將軍令）" if lines.is_empty() else "
".join(lines), "options": opts}


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


# Tier1 武將 (Step 13.5): 簡介 + 傾偈 / 登用 (開登用面板調查)
static func general_dialog(main: Node, gid: int) -> Dictionary:
	var g: Dictionary = main.data.general_by_id.get(gid, {})
	if g.is_empty():
		return {}
	var idle: Array = g.get("idle", [])
	var text := "戰等 %d　%s%s　理念「%s」\n「%s」\n想登用：喺城入面用「調查」（每日 1 次）。" % [int(g["lv"]),
		RulesRecruit.type_name(String(g["type"])), g["sub"], g["ideo"], str(idle[0]) if not idle.is_empty() else "……"]
	return {"title": str(g["name"]), "text": text, "options": [
		{"label": "傾偈", "cb": func() -> void: main._send({"t": "general_talk", "gid": gid})},
		{"label": "登用…", "cb": func() -> void: main.hud.open_panel("recruit")}, _leave(main)]}


static func inn_dialog(main: Node) -> Dictionary:
	var ch: Dictionary = main.ch
	var cost := int(main.inn_cost)
	var gold := int(ch.get("gold", 0))
	var th: Dictionary = main.data.world["thirst"]
	var tea := int(th["teaCost"])
	var thirst: int = main.sim.thirst_of(ch)
	return {"title": "客棧", "text": "住宿 %d 金：回滿 HP / MP / SP。\n喝茶 %d 金：飲水度 +%d、回 MP。\n你而家有 %d 金，飲水度 %d/%d。" % [cost,
			tea, int(th["tea"]), gold, thirst, int(th["max"])],
		"options": [{"label": "休息 (%d 金)" % cost, "cb": func() -> void: main._send({"t": "rest"}), "disabled": gold < cost},
			{"label": "喝茶 (%d 金)" % tea, "cb": func() -> void: main._send({"t": "tea"}), "disabled": gold < tea or thirst >= int(th["max"])},
			_leave(main)]}


static func fac_dialog(main: Node, f: Dictionary) -> Dictionary:
	var ch: Dictionary = main.ch
	var key := String(f.fac)
	var def: Dictionary = main.data.facilities[key]
	if key == "forge":
		return forge_dialog(main, def)
	if bool(def.get("office", false)):
		return office_dialog(main, def)
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


# 官宅 (Step 14): 討取頭銜 / 官令 (接/覆命/放棄) / 捐獻 / 貢獻換行動丹
static func office_dialog(main: Node, def: Dictionary) -> Dictionary:
	var ch: Dictionary = main.ch
	var tt: Array = main.data.titles
	var cur := int(ch.get("titleRank", 0))
	var fame := int(ch.get("fame", 0))
	var gold := int(ch.get("gold", 0))
	var off: Dictionary = main.data.office
	var lines: Array = [
		"頭銜 %s（第 %d 階）　名聲 %d　金 %d" % [RulesTitle.name_of(tt, cur), cur, fame, gold],
		"行動力 %d/%d　官宅貢獻 %d　月俸 %d" % [main.sim.ap_of(ch), main.sim.ap_max(ch), int(ch.get("contrib", 0)), RulesTitle.salary(tt, cur)]]
	var opts: Array = []
	# 討取: 名聲夠嘅最高階；未夠就顯示下一階要幾多
	var best := RulesTitle.fame_rank(tt, fame)
	if best > cur:
		var t := RulesTitle.def_of(tt, best)
		var rk := best
		opts.append({"label": "討取「%s」(%d 金)" % [t["name"], int(t["gold"])], "cb": func() -> void: main._send({"t": "claim_title", "rank": rk}),
			"disabled": gold < int(t["gold"])})
	elif cur < tt.size():
		var nx := RulesTitle.def_of(tt, cur + 1)
		lines.append("下一階「%s」要名聲 %d、資金 %d" % [nx["name"], int(nx["fame"]), int(nx["gold"])])
	var od: Dictionary = ch.get("office", {}).get("order", {})
	if od.is_empty():
		opts.append({"label": "官令…", "cb": func() -> void: main.hud.open_dialog(func() -> Dictionary: return order_dialog(main, def))})
	else:
		var o: Dictionary = main.sim.order_def(str(od["id"]))
		lines.append("官令「%s」：%s" % [o.get("name", "?"), main.sim.order_text(ch)])
		opts.append({"label": "覆命", "cb": func() -> void: main._send({"t": "office_turnin"})})
		opts.append({"label": "放棄官令", "cb": func() -> void: main._send({"t": "office_abandon"})})
	opts.append({"label": "捐獻…", "cb": func() -> void: main.hud.open_dialog(func() -> Dictionary: return donate_dialog(main, def))})
	opts.append({"label": "換行動丹 (%d 貢獻)" % int(off["pillCost"]), "cb": func() -> void: main._send({"t": "office_pill"}),
		"disabled": int(ch.get("contrib", 0)) < int(off["pillCost"])})
	opts.append(_leave(main))
	return {"title": str(def.get("name", "官宅")), "text": "\n".join(lines), "options": opts}


# 官令清單 (每日 1 次、扣行動力 10)：未解鎖/今日接過 = 灰
static func order_dialog(main: Node, def: Dictionary) -> Dictionary:
	var ch: Dictionary = main.ch
	var lines: Array = ["官令每日接 1 次，每次扣行動力 %d。" % int(main.data.office["apCost"])]
	var opts: Array = []
	for o in main.data.office["orders"]:
		var oid := str(o["id"])
		var why: String = main.sim.order_block(ch, oid)
		lines.append("・%s（%s 起）名聲 +%d%s" % [o["name"], o["rankName"], int(o["fame"]), "" if why == "" else "　— " + why])
		var take := func() -> void:
			main._send({"t": "office_order", "order": oid})
			main.hud.open_dialog(func() -> Dictionary: return office_dialog(main, def))
		opts.append({"label": str(o["name"]), "cb": take, "disabled": why != ""})
	opts.append({"label": "返回", "cb": func() -> void: main.hud.open_dialog(func() -> Dictionary: return office_dialog(main, def))})
	return {"title": "官令", "text": "\n".join(lines), "options": opts}


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
