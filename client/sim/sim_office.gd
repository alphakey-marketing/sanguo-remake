extends "res://sim/sim_recruit.gd"
# Sim 繼承鏈: 名聲 / 頭銜 / 官宅 / 官令 (Step 14, spec 08 §1~3, spec 06 §3)
# 官宅 = facilities.json 有 office:true 嘅設施 (兼捐獻處)。規則喺 rules/title.gd
# ch.titleRank / ch.office {orderDay, order:{id, from, to?, met:[]}} / ch.contrib / ch.polExp


# 企喺邊間官宅隔籬 → facility key ("" = 唔喺)
func office_near(e: Dictionary) -> String:
	return _fac_near(e, "office")


func office_keys() -> Array:
	var out: Array = []
	for k in data.facilities:
		var f = data.facilities[k]
		if f is Dictionary and bool(f.get("office", false)):
			out.append(String(k))
	out.sort()
	return out


func _office_of(ch: Dictionary) -> Dictionary:
	if not ch.has("office"):
		ch["office"] = {}
	return ch["office"]


func order_def(order_id: String) -> Dictionary:
	for o in data.office["orders"]:
		if String(o["id"]) == order_id:
			return o
	return {}


# ================= 討取頭銜 (spec 08 §2) =================
func cmd_claim_title(id: int, rank: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	if office_near(e) == "":
		return _msg(id, "要去官宅先討取得頭銜")
	var ch: Dictionary = e["ch"]
	var why := RulesTitle.claim_check(data.titles, rank, int(ch.get("titleRank", 0)), int(ch.get("fame", 0)), int(ch["gold"]))
	if why != "":
		return _msg(id, why)
	var t := RulesTitle.def_of(data.titles, rank)
	ch["gold"] = int(ch["gold"]) - int(t["gold"])
	ch["titleRank"] = rank
	ch["titleCompete"] = true    # S08d: 入名額競爭系統 (每月初一守位考驗)
	_emit({"k": "title", "id": id, "rank": rank, "name": String(t["name"])})
	_msg(id, "朝廷受落，御賜頭銜「%s」(第 %d 階)！扣資金 %d；行動力上限 %d、每月俸祿 %d" % [t["name"], rank,
		int(t["gold"]), int(t["ap"]), int(t["salary"])])


# 每月初一派俸祿【原】(日結 hook)
func _salary_daily(day: int) -> void:
	if not RulesTitle.is_month_start(day, int(data.world["clock"].get("monthDays", 30))):
		return
	for e in ents.values():
		if not e.has("ch"):
			continue
		var pay := RulesTitle.salary(data.titles, int(e["ch"].get("titleRank", 0)))
		if pay <= 0:
			continue
		e["ch"]["gold"] = int(e["ch"]["gold"]) + pay
		_emit({"k": "salary", "id": int(e["id"]), "gold": pay})
		_msg(int(e["id"]), "月初俸祿：%s 領 %d 金" % [RulesTitle.name_of(data.titles, int(e["ch"]["titleRank"])), pay])


# ================= 官令 (spec 06 §3)【原】每日 1 次、扣行動力 10、頭銜解鎖 =================
# 接令前檢查 → "" = 得 (UI 用嚟灰掣)
func order_block(ch: Dictionary, order_id: String) -> String:
	var o := order_def(order_id)
	if o.is_empty():
		return "冇呢條官令"
	if RulesKarma.office_blocked(int(ch.get("karma", 0))):
		return "罪犯以下唔接得官令"
	return RulesTitle.order_block(o, int(ch.get("titleRank", 0)), ap_of(ch), int(_clock()["day"]), _office_of(ch),
		_office_ap_cost(ch))


func cmd_office_order(id: int, order_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var here := office_near(e)
	if here == "":
		return _msg(id, "要去官宅先接得官令")
	var ch: Dictionary = e["ch"]
	var why := order_block(ch, order_id)
	if why != "":
		return _msg(id, why)
	var o := order_def(order_id)
	var off := _office_of(ch)
	var od := {"id": order_id, "from": here}
	if String(o["kind"]) == "deliver":
		for k in office_keys():
			if k != here:
				od["to"] = k
				break
		if not od.has("to"):
			return _msg(id, "冇第二間官宅可以送")
		RulesShop.add_item(ch["bag"], int(o["item"]), 1)
	elif String(o["kind"]) == "census":
		od["met"] = []
	elif String(o["kind"]) == "escort":
		od["npc"] = int(_spawn_office_npc(e, "escort")["id"])
	elif String(o["kind"]) == "rescue":
		od["npc"] = int(_spawn_office_npc(e, "rescue")["id"])
	ch["ap"] = ap_of(ch) - _office_ap_cost(ch)
	off["orderDay"] = int(_clock()["day"])
	off["order"] = od
	_emit({"k": "office_order", "id": id, "order": order_id, "started": true})
	_msg(id, "接咗官令「%s」：%s（行動力 -%d）" % [o["name"], order_text(ch), _office_ap_cost(ch)])


# 而家手上官令嘅說明 (UI/訊息用)
func order_text(ch: Dictionary) -> String:
	var od: Dictionary = _office_of(ch).get("order", {})
	if od.is_empty():
		return ""
	var o := order_def(String(od["id"]))
	match String(o["kind"]):
		"supply":
			return String(o["desc"]) % int(o["units"]) + "（背包有 %d 單位）" % supply_units(ch, o)
		"deliver":
			return String(o["desc"]) % String(data.facilities[String(od["to"])]["name"])
		"census":
			return String(o["desc"]) % [String(data.facilities[String(od["from"])].get("city", "城")), int(o["n"])] + \
				"（%d/%d）" % [(od.get("met", []) as Array).size(), int(o["n"])]
		"buy":
			return String(o["desc"]) % data.names.get(int(o["item"]), "武器") + "（背包 %d 件）" % RulesShop.count_item(ch["bag"], int(o["item"]))
		"recruit":
			return String(o["desc"]) + ("（已有文官跟隨）" if _office_recruit_ok(ch) else "（未登用文官）")
		"escort", "rescue":
			return String(o["desc"]) % String(data.map_by_id[String(o["zone"])]["name"]) + "　" + _office_npc_status(od)
		_:
			if String(od.get("id", "")) == "relief":
				return "救災：%s（%d/%d）" % [_city_name(String(od.get("city", ""))), int(od.get("done", 0)), int(od.get("need", 0))]
	return ""


# 軍備動員: 背包可交嘅材料 (指定技能嘅初階材料，唔計任務道具) → 捐獻單位
func _supply_counts(ch: Dictionary, o: Dictionary) -> Dictionary:
	var counts := {}
	for s in ch.get("bag", []):
		var iid := int(s["id"])
		if (o["skills"] as Array).has(String(data.mat_skill.get(iid, ""))) and data.donation_rates.has(iid):
			counts[iid] = int(counts.get(iid, 0)) + int(s["n"])
	return counts


func supply_units(ch: Dictionary, o: Dictionary) -> int:
	return RulesTiandi.donation_units(_supply_counts(ch, o), data.donation_rates)


# 覆命: 喺啱嘅官宅 + 完成條件 → 名聲/貢獻/政治經驗
func cmd_office_turnin(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var off := _office_of(ch)
	var od: Dictionary = off.get("order", {})
	if od.is_empty():
		return _msg(id, "手上冇官令")
	var here := office_near(e)
	if here == "":
		return _msg(id, "要去官宅先覆命得")
	var o := order_def(String(od["id"]))
	# 救災官令 (S08c) 唔喺 orders 表，專屬流程: 要返接令嗰間官宅 + 做完次數
	if String(od.get("id", "")) == "relief":
		if here != String(od.get("from", "")):
			return _msg(id, "返%s官宅先覆命得" % _city_name(String(od.get("city", ""))))
		if int(od.get("done", 0)) < int(od.get("need", 0)):
			return _msg(id, "救災仲未做完 (%d/%d)" % [int(od.get("done", 0)), int(od.get("need", 0))])
		off["order"] = {}
		_relief_reward(e, ch, od)
		return
	match String(o["kind"]):
		"supply":
			var need := int(o["units"])
			if supply_units(ch, o) < need:
				return _msg(id, "物資唔夠：要 %d 單位 (而家 %d)" % [need, supply_units(ch, o)])
			var counts := _supply_counts(ch, o)
			var left := need
			for iid in counts:
				if left <= 0:
					break
				var rate := int(data.donation_rates[iid])
				var take := mini(int(counts[iid]), (left + rate - 1) / rate)
				RulesShop.remove_item(ch["bag"], int(iid), take)
				left -= take * rate
		"deliver":
			if here != String(od["to"]):
				return _msg(id, "軍函要送去%s" % data.facilities[String(od["to"])]["name"])
			if not RulesShop.remove_item(ch["bag"], int(o["item"]), 1):
				return _msg(id, "軍函唔見咗……放棄官令再接過啦")
		"census":
			if here != String(od["from"]):
				return _msg(id, "返%s覆命" % data.facilities[String(od["from"])]["name"])
			if (od.get("met", []) as Array).size() < int(o["n"]):
				return _msg(id, "仲未訪問夠 %d 個人" % int(o["n"]))
		"buy":
			if not RulesShop.remove_item(ch["bag"], int(o["item"]), 1):
				return _msg(id, "仲未買到指定武器：%s" % data.names.get(int(o["item"]), "武器"))
		"recruit":
			if not _office_recruit_ok(ch):
				return _msg(id, "要登用緊 1 位文官先覆命得")
		"escort":
			var enpc := ent(int(od.get("npc", 0)))
			if enpc.is_empty() or bool(enpc.get("down", false)):
				return _msg(id, "護送對象已經唔喺度……放棄官令再接過啦")
			if map_id_at(int(enpc["x"]), int(enpc["y"])) != String(o["zone"]):
				return _msg(id, "仲未護送到%s" % String(data.map_by_id[String(o["zone"])]["name"]))
			_remove_ent(int(enpc["id"]))
		"rescue":
			var rnpc := ent(int(od.get("npc", 0)))
			if rnpc.is_empty() or bool(rnpc.get("down", false)):
				return _msg(id, "流落官員已經唔喺度……放棄官令再接過啦")
			if not bool(rnpc["gen"].get("rescued", false)) or here != String(od["from"]):
				return _msg(id, "帶流落官員返%s先覆命得" % String(data.facilities[String(od["from"])]["name"]))
			_remove_ent(int(rnpc["id"]))
	off["order"] = {}
	_order_reward(e, ch, o)


func _order_reward(e: Dictionary, ch: Dictionary, o: Dictionary) -> void:
	var id := int(e["id"])
	var fame := int(o.get("fame", 0))
	var contrib := int(o.get("contrib", 0))
	ch["fame"] = int(ch.get("fame", 0)) + fame
	ch["contrib"] = int(ch.get("contrib", 0)) + contrib
	var tail := ""
	var pe := int(o.get("polExp", 0))
	if pe > 0:
		var r := RulesTiandi.cha_gain(int(ch["attrs"]["pol"]), int(ch.get("polExp", 0)), pe,
			{"chaExpPerPoint": data.office["polExpPerPoint"], "chaCap": data.office["polCap"]})
		ch["attrs"]["pol"] = int(r["cha"])
		ch["polExp"] = int(r["exp"])
		tail = "，政治經驗 +%d" % pe + ("，政治 +%d" % int(r["ups"]) if int(r["ups"]) > 0 else "")
		_sync_stats(e)
	var pay := 0
	if String(o.get("kind", "")) == "escort":
		pay = RulesTitle.salary(data.titles, int(ch.get("titleRank", 0))) * int(o.get("salaryMult", 1))
		ch["gold"] = int(ch["gold"]) + pay
		tail += "，俸祿獎勵 +%d 金" % pay
	_emit({"k": "office_order", "id": id, "order": String(o["id"]), "done": true, "fame": fame, "contrib": contrib})
	_msg(id, "官令「%s」完成：名聲 +%d，官宅貢獻 +%d%s" % [o["name"], fame, contrib, tail])


# 御賜工具清單 (S05b spec 05 §5)：真任務 (S06c 團體任務) 未接前，暫用官宅貢獻兌換
func godgiven_tools() -> Array:
	var out: Array = []
	var contrib_cfg: Dictionary = data.work_meta["toolRedeemContrib"]
	for tid in data.tool_tier:
		if String(data.tool_tier[tid]) != "godgiven":
			continue
		var skill := String(data.tool_skill.get(tid, ""))
		var cost := int(contrib_cfg["basic"]) if data.work.has(skill) else int(contrib_cfg["advanced"])
		out.append({"item": int(tid), "skill": skill, "cost": cost})
	return out


# 兌換御賜工具: 扣官宅貢獻換 1 件入背包 (暫代過渡，真任務來源等 S06c 團體任務)
func cmd_office_redeem_tool(id: int, item_id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	if office_near(e) == "":
		return _msg(id, "要去官宅先兌換得御賜工具")
	if String(data.tool_tier.get(item_id, "")) != "godgiven":
		return _msg(id, "呢件唔係御賜工具")
	var ch: Dictionary = e["ch"]
	var skill := String(data.tool_skill.get(item_id, ""))
	var contrib_cfg: Dictionary = data.work_meta["toolRedeemContrib"]
	var cost := int(contrib_cfg["basic"]) if data.work.has(skill) else int(contrib_cfg["advanced"])
	if int(ch.get("contrib", 0)) < cost:
		return _msg(id, "官宅貢獻不足 (要 %d，而家 %d)" % [cost, int(ch.get("contrib", 0))])
	ch["contrib"] = int(ch["contrib"]) - cost
	RulesShop.add_item(ch["bag"], item_id, 1)
	_emit({"k": "office_redeem_tool", "id": id, "item": item_id, "contrib": cost})
	_msg(id, "兌換咗「%s」，扣官宅貢獻 %d" % [data.names.get(item_id, str(item_id)), cost])


# 放棄: 收返軍函；行動力唔退、今日唔可以再接
func cmd_office_abandon(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var ch: Dictionary = e["ch"]
	var off := _office_of(ch)
	var od: Dictionary = off.get("order", {})
	if od.is_empty():
		return
	var o := order_def(String(od["id"]))
	if String(o.get("kind", "")) == "deliver":
		RulesShop.remove_item(ch["bag"], int(o["item"]), 1)
	elif String(o.get("kind", "")) in ["escort", "rescue"]:
		var npc := ent(int(od.get("npc", 0)))
		if not npc.is_empty():
			_remove_ent(int(npc["id"]))
	off["order"] = {}
	_msg(id, "放棄咗官令「%s」" % o.get("name", "?"))


# 戶口普查: 喺接令嗰個城同 NPC 傾偈 (任務 NPC / Tier1 人才)，同一個人只計一次
func _office_on_talk(e: Dictionary, key: String, x: int, y: int) -> void:
	if not e.has("ch"):
		return
	var od: Dictionary = _office_of(e["ch"]).get("order", {})
	if od.is_empty() or String(order_def(String(od["id"])).get("kind", "")) != "census":
		return
	var f: Dictionary = data.facilities[String(od["from"])]
	if map_id_at(x, y) != map_id_at(int(f["x"]), int(f["y"])):
		return
	var met: Array = od["met"]
	if met.has(key):
		return
	met.append(key)
	var n := int(order_def(String(od["id"]))["n"])
	_msg(int(e["id"]), "戶口普查：訪問咗 %d/%d 人" % [mini(met.size(), n), n])


# ================= 官宅貢獻換行動丹 (spec 01 §10 單機化) =================
func cmd_office_pill(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	if office_near(e) == "":
		return _msg(id, "要去官宅先換得")
	var ch: Dictionary = e["ch"]
	var cost := int(data.office["pillCost"])
	if int(ch.get("contrib", 0)) < cost:
		return _msg(id, "官宅貢獻不足 (要 %d)" % cost)
	ch["contrib"] = int(ch.get("contrib", 0)) - cost
	var item := int(data.office["pillItem"])
	RulesShop.add_item(ch["bag"], item, 1)
	_msg(id, "用 %d 貢獻換咗 1 粒%s" % [cost, data.names.get(item, "行動丹")])

# 朝廷求才: 而家係咪跟緊一位文官同伴
func _office_recruit_ok(ch: Dictionary) -> bool:
	var comp := ent(int(ch.get("recruit", {}).get("comp", 0)))
	if comp.is_empty() or not comp.has("gen"):
		return false
	var g: Dictionary = data.general_by_id.get(int(comp["gen"]["gid"]), {})
	return String(g.get("type", "")) == "wen"


# 每 tick: 護衛/救援官令嘅 NPC 死咗 (down) → 官令自動失敗，唔退行動力 (Step S06a)
func _office_tick() -> void:
	var pe := ent(int(state["player_id"]))
	if pe.is_empty() or not pe.has("ch"):
		return
	var ch: Dictionary = pe["ch"]
	var off := _office_of(ch)
	var od: Dictionary = off.get("order", {})
	if od.is_empty() or not od.has("npc"):
		return
	var o := order_def(String(od["id"]))
	var npc := ent(int(od["npc"]))
	if npc.is_empty() or bool(npc.get("down", false)):
		off["order"] = {}
		if not npc.is_empty():
			_remove_ent(int(npc["id"]))
		_msg(int(pe["id"]), "官令「%s」失敗：官員遇害，官令自動取消（行動力唔退）" % String(o.get("name", "?")))


# ================= 義舉證明 (S08a, spec 08 §1)【原 sy2_8_3 四類 20 項；名聲值自訂】 =================
# 只有許昌嘅朝廷官員 (data.office.merit.imperialOffice) 受理。
func _merit_cfg() -> Dictionary:
	return data.office["merit"]


# 20 項義舉證明清單 (read-model；owned/can/why 供 UI 灰掣用)
func merit_list(ch: Dictionary) -> Array:
	var cfg := _merit_cfg()
	var cat_names := {}
	for c in cfg["cats"]:
		cat_names[String(c["id"])] = String(c["name"])
	var rank := int(ch.get("titleRank", 0))
	var out: Array = []
	for it in cfg["items"]:
		var iid := int(it["id"])
		var why := RulesMerit.block(cfg, iid, rank, data.titles)
		out.append({"id": iid, "name": String(it["name"]), "cat": String(it["cat"]),
			"catName": String(cat_names.get(String(it["cat"]), "")), "reqRank": int(it["reqRank"]),
			"fame": int(it["fame"]), "owned": RulesShop.count_item(ch["bag"], iid),
			"can": why == "", "why": why})
	return out


# 繳交 1 件義舉證明 → 名聲 (冇行動力成本，spec 08 §1)
func cmd_merit_turnin(id: int, item_id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var cfg := _merit_cfg()
	var off_key := String(cfg["imperialOffice"])
	if office_near(e) != off_key:
		return _msg(id, "義舉證明只有許昌嘅朝廷官員受理，要去%s" % String(data.facilities[off_key]["name"]))
	var ch: Dictionary = e["ch"]
	var why := RulesMerit.block(cfg, item_id, int(ch.get("titleRank", 0)), data.titles)
	if why != "":
		return _msg(id, why)
	if RulesShop.count_item(ch["bag"], item_id) <= 0:
		return _msg(id, "背包冇呢件義舉證明")
	RulesShop.remove_item(ch["bag"], item_id, 1)
	var fame := RulesMerit.fame_of(cfg, item_id)
	ch["fame"] = int(ch.get("fame", 0)) + fame
	_emit({"k": "merit", "id": id, "item": item_id, "fame": fame})
	_msg(id, "繳交義舉證明「%s」：名聲 +%d" % [String(RulesMerit.item_def(cfg, item_id).get("name", str(item_id))), fame])


# ================= 城池進貢 (S08a, spec 08 §1)【自訂】 =================
func _tribute_cfg() -> Dictionary:
	return data.office["tribute"]


# 設施 key → world city id ("" = 唔屬 any 城池)
func _facility_city_id(key: String) -> String:
	var mp := String((data.facilities.get(key, {}) as Dictionary).get("map", ""))
	for c in data.world["cities"]:
		if String(c["id"]) == mp:
			return mp
	return ""


func _city_name(city_id: String) -> String:
	for c in data.world["cities"]:
		if String(c["id"]) == city_id:
			return String(c["name"])
	return String(data.map_by_id.get(city_id, {}).get("name", city_id))


# 玩家喺某城嘅好感 (舊存檔冇 → 0)
func city_favor(ch: Dictionary, city_id: String) -> int:
	return int((ch.get("cityFavor", {}) as Dictionary).get(city_id, 0))


# 各城好感 read-model
func city_favor_view(ch: Dictionary) -> Array:
	var out: Array = []
	for c in data.world["cities"]:
		var cid := String(c["id"])
		out.append({"id": cid, "name": String(c["name"]), "favor": city_favor(ch, cid)})
	return out


# 進貢物資 (捐獻處): 唔扣行動力，提升該城好感 + 名聲【自訂】。items = [[item id, n], ...]
func cmd_city_tribute(id: int, items: Array) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var here := _fac_near(e, "donation")
	if here == "":
		return _msg(id, "要去捐獻處先進貢得")
	var city := _facility_city_id(here)
	if city == "":
		return _msg(id, "呢度唔屬任何城池，進貢唔到")
	var ch: Dictionary = e["ch"]
	var counts := {}
	for it in items:
		var iid := int(it[0])
		var n := int(it[1])
		if n <= 0 or not data.donation_rates.has(iid) or RulesQuest.is_quest_item(data, iid):
			continue
		counts[iid] = int(counts.get(iid, 0)) + n
	if counts.is_empty():
		return _msg(id, "冇物資可以進貢")
	for iid in counts:
		if RulesShop.count_item(ch["bag"], iid) < int(counts[iid]):
			return _msg(id, "背包冇咁多%s" % data.names.get(iid, str(iid)))
	var units := RulesTiandi.donation_units(counts, data.donation_rates)
	if units <= 0:
		return _msg(id, "冇物資可以進貢")
	for iid in counts:
		RulesShop.remove_item(ch["bag"], iid, int(counts[iid]))
	var cfg := _tribute_cfg()
	var old := city_favor(ch, city)
	var nf := RulesMerit.favor_cap(old + RulesMerit.favor_gain(units, cfg), cfg)
	var gain := nf - old
	var fame := RulesMerit.tribute_fame(units, cfg)
	if not ch.has("cityFavor"):
		ch["cityFavor"] = {}
	ch["cityFavor"][city] = nf
	ch["fame"] = int(ch.get("fame", 0)) + fame
	_emit({"k": "city_tribute", "id": id, "city": city, "units": units, "favor": gain, "fame": fame})
	var tail := "，名聲 +%d" % fame if fame > 0 else ""
	_msg(id, "進貢 %d 單位物資入%s：好感 +%d%s" % [units, _city_name(city), gain, tail])


# ================= 官宅內政 6 種 (S08b, spec 08 §3 / 攻略 sy2_8_8) =================
# 開墾(墾荒種地)/商業(商業開發)/畜牧(照顧牲畜)/礦產(探索礦能)/防禦(增強防禦)/鑄造(技術開發)
# 執行 = 喺官宅做一次：提昇所在城池對應屬性 0~100 + 該專長 exp（清 S01c 內政延後）。
# 需有身份（頭銜 ≥ minTitleRank）【原】；扣行動力 = 官令同價（武將協助 S09c 會減）。
# 武將政治協助：_domestic_assist_bonus(ch)（S09c override，而家 0.0）。

func domestic_cfg() -> Dictionary:
	return data.office.get("domestic", {})


func domestic_def(job_id: String) -> Dictionary:
	for j in domestic_cfg().get("jobs", []):
		if String(j["id"]) == job_id:
			return j
	return {}


func domestic_jobs() -> Array:
	return domestic_cfg().get("jobs", [])


# 做唔做得："" = 得，否則理由（UI 灰掣 + cmd 檢查）
func domestic_block(ch: Dictionary, city_id: String, job_id: String) -> String:
	var cfg := domestic_cfg()
	var j := domestic_def(job_id)
	if j.is_empty():
		return "冇呢種內政"
	if city_id == "":
		return "要喺官宅先做得內政"
	var need := int(cfg.get("minTitleRank", 1))
	if int(ch.get("titleRank", 0)) < need:
		return "要官身（頭銜 ≥ %d 階）先做得內政" % need
	var cost := _office_ap_cost(ch)
	if ap_of(ch) < cost:
		return "行動力不足 (要 %d)" % cost
	var key := String(j["attr"])
	if RulesCity.attr_of(city_attrs(city_id), key, _city_attr_cfg()) >= 100:
		return "城池「%s」已經封頂 (100)" % RulesCity.name_of(_city_attr_cfg(), key)
	return ""


# 內政 read-model（UI 用）：城池屬性 + 6 種工作 can/why/gain
func domestic_view(id: int) -> Dictionary:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return {}
	var ch: Dictionary = e["ch"]
	var here := office_near(e)
	var city := _facility_city_id(here) if here != "" else ""
	var cfg := domestic_cfg()
	var attrs := city_attrs(city) if city != "" else {}
	var rows: Array = []
	for k in RulesCity.KEYS:
		rows.append({"key": k, "name": RulesCity.name_of(_city_attr_cfg(), k), "val": RulesCity.attr_of(attrs, k, _city_attr_cfg())})
	var jobs: Array = []
	for j in domestic_jobs():
		var why := domestic_block(ch, city, String(j["id"]))
		var lv := expert_lv(ch, String(j["expert"]))
		var assist := _domestic_assist_bonus(ch)
		jobs.append({"id": String(j["id"]), "name": String(j["name"]), "attr": String(j["attr"]),
			"attrName": RulesCity.name_of(_city_attr_cfg(), String(j["attr"])), "expert": String(j["expert"]),
			"expertLv": lv, "gain": RulesCity.attr_gain(int(cfg.get("baseGain", 2)), RulesExpert.domestic_mult(lv) + assist),
			"can": why == "", "why": why})
	return {"city": city, "cityName": _city_name(city), "office": here, "apCost": _office_ap_cost(ch),
		"minTitleRank": int(cfg.get("minTitleRank", 1)), "attrs": rows, "jobs": jobs}


func cmd_domestic(id: int, job_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var here := office_near(e)
	if here == "":
		return _msg(id, "要去官宅先做得內政")
	var city := _facility_city_id(here)
	if city == "":
		return _msg(id, "呢度唔屬任何城池，做唔到內政")
	var ch: Dictionary = e["ch"]
	var why := domestic_block(ch, city, job_id)
	if why != "":
		return _msg(id, why)
	var cfg := domestic_cfg()
	var j := domestic_def(job_id)
	var key := String(j["attr"])
	var attrs := city_attrs(city)
	var cur := RulesCity.attr_of(attrs, key, _city_attr_cfg())
	var before_lv := expert_lv(ch, String(j["expert"]))
	var gain := RulesCity.attr_gain(int(cfg.get("baseGain", 2)), RulesExpert.domestic_mult(before_lv) + _domestic_assist_bonus(ch))
	gain = mini(gain, 100 - cur)
	attrs[key] = cur + gain
	city_attrs_set(city, attrs)
	ch["ap"] = ap_of(ch) - _office_ap_cost(ch)
	RulesExpert.add_exp(ch, data.experts, String(j["expert"]), int(cfg.get("expertExp", 3)))
	var after_lv := expert_lv(ch, String(j["expert"]))
	var tail := ""
	if after_lv > before_lv:
		tail = "，「%s」專長升到 %d 級！" % [String(data.experts["skills"].get(String(j["expert"]), {}).get("name", j["expert"])), after_lv]
	_emit({"k": "domestic", "id": id, "job": job_id, "city": city, "attr": key, "gain": gain, "val": int(attrs[key]),
		"expert": String(j["expert"]), "expertExp": int(cfg.get("expertExp", 3))})
	_msg(id, "內政「%s」完成：%s 屬性 +%d（而家 %d）%s" % [j["name"], RulesCity.name_of(_city_attr_cfg(), key), gain, int(attrs[key]), tail])


# ================= 救災 (S08c, spec 08 §6 / 攻略 sy2_8_12) =================
# 流程【原 sy2_8_12】: 公佈欄睇天災 → 官宅功曹領救災官令 (扣行動力 10) → 買對應救災物品 →
#   去救災區做 N 次 (每次扣 SP + 用 1 份物品；小 10/中 20/大 30【自訂】) → 返官宅覆命
#   (名聲 +10【原】/ 政治 exp / 救災專長 exp【自訂】)。做嘅次數令該城天災強度遞減。
# 救災官令共用 ch.office.order，但唔喺 office.orders 表 (動態綁城池/天災)，有專屬 cmd。

func relief_cfg() -> Dictionary:
	return data.office.get("relief", {})


func _relief_item(disaster_id: String) -> int:
	return RulesDisaster.relief_item_of(data.world["disasters"], disaster_id)


# 城池而家生效中嘅天災 (第一條；冇 = {})
func _active_disaster(city_id: String) -> Dictionary:
	for d in state["disasters"]:
		if String(d.get("city", "")) == city_id:
			return d
	return {}


func _disaster_name(disaster_id: String) -> String:
	for d in data.world["disasters"]:
		if String(d["id"]) == disaster_id:
			return String(d["name"])
	return disaster_id


# 企喺邊個城門公佈欄隔籬 → facility key ("" = 唔喺)
func bulletin_near(e: Dictionary) -> String:
	return _fac_near(e, "bulletin")


# 企喺邊個救災區隔籬 → {key, cityId, name} ({}=唔喺)
func relief_near(e: Dictionary) -> Dictionary:
	for k in data.facilities:
		var f = data.facilities[k]
		if f is Dictionary and bool(f.get("relief", false)) and _near(e, int(f["x"]), int(f["y"])):
			return {"key": String(k), "cityId": String(f.get("cityId", "")), "name": String(f.get("name", ""))}
	return {}


# 公佈欄: 各城現時天災 + 對應救災物品 (S08c 步驟 1)
func bulletin_view(id: int) -> Dictionary:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return {}
	var cities: Array = []
	for c in data.world["cities"]:
		var cid := String(c["id"])
		var rows: Array = []
		for d in state["disasters"]:
			if String(d.get("city", "")) != cid:
				continue
			var iid := _relief_item(String(d["id"]))
			rows.append({"id": String(d["id"]), "name": String(d["name"]), "size": String(d["size"]),
				"endDay": int(d.get("endDay", 0)), "item": iid, "itemName": String(data.names.get(iid, ""))})
		cities.append({"id": cid, "name": String(c["name"]), "disasters": rows})
	return {"at": bulletin_near(e) != "", "bulletin": bulletin_near(e), "cities": cities}


# 領救災官令檢查 ("" = 得)
func relief_block(ch: Dictionary, city_id: String) -> String:
	if city_id == "":
		return "要喺城內官宅先領得救災官令"
	if RulesKarma.office_blocked(int(ch.get("karma", 0))):
		return "罪犯以下唔接得官令"
	var cfg := relief_cfg()
	if int(ch.get("titleRank", 0)) < int(cfg.get("minTitleRank", 0)):
		return "要官身（頭銜 ≥ %d 階）先領得救災官令" % int(cfg.get("minTitleRank", 0))
	if _active_disaster(city_id).is_empty():
		return "呢個城而家冇天災"
	if not (_office_of(ch).get("order", {}) as Dictionary).is_empty():
		return "仲有官令喺手，做完先接得"
	if ap_of(ch) < _office_ap_cost(ch):
		return "行動力不足 (要 %d)" % _office_ap_cost(ch)
	return ""


# 救災 read-model (官宅 UI 用)
func relief_view(id: int) -> Dictionary:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return {}
	var ch: Dictionary = e["ch"]
	var here := office_near(e)
	var city := _facility_city_id(here) if here != "" else ""
	var d := _active_disaster(city) if city != "" else {}
	var need := RulesDisaster.relief_need(String(d.get("size", "")), relief_cfg()) if not d.is_empty() else 0
	var iid := _relief_item(String(d.get("id", ""))) if not d.is_empty() else 0
	var od: Dictionary = _office_of(ch).get("order", {})
	var active := String(od.get("id", "")) == "relief"
	return {"city": city, "cityName": _city_name(city), "cityHasDisaster": not d.is_empty(),
		"disaster": d, "need": need, "item": iid, "itemName": String(data.names.get(iid, "")),
		"owned": RulesShop.count_item(ch["bag"], iid) if iid > 0 else 0,
		"hasOrder": active, "done": int(od.get("done", 0)) if active else 0,
		"apCost": _office_ap_cost(ch), "spCost": int(relief_cfg().get("spCost", 10)), "block": relief_block(ch, city)}


# 領救災官令 (官宅功曹): 扣行動力 10，記低該城目標天災
func cmd_office_relief(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var here := office_near(e)
	if here == "":
		return _msg(id, "要去官宅先領得救災官令")
	var city := _facility_city_id(here)
	var ch: Dictionary = e["ch"]
	var why := relief_block(ch, city)
	if why != "":
		return _msg(id, why)
	var d := _active_disaster(city)
	var need := RulesDisaster.relief_need(String(d["size"]), relief_cfg())
	var off := _office_of(ch)
	off["orderDay"] = int(_clock()["day"])
	off["order"] = {"id": "relief", "from": here, "city": city, "disaster": String(d["id"]), "need": need, "done": 0}
	ch["ap"] = ap_of(ch) - _office_ap_cost(ch)
	var iid := _relief_item(String(d["id"]))
	_emit({"k": "office_order", "id": id, "order": "relief", "started": true})
	_msg(id, "領咗救災官令：%s 正發生「%s」(規模 %s)，去救災區做 %d 次；記住買「%s」。" % [
		_city_name(city), String(d["name"]), String(d["size"]), need, String(data.names.get(iid, "救災物品"))])


# 喺救災區執行一次救災 (扣 SP + 用 1 份物品；令天災強度遞減)
func cmd_relief_work(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var od: Dictionary = _office_of(ch).get("order", {})
	if String(od.get("id", "")) != "relief":
		return _msg(id, "手上冇救災官令")
	var near := relief_near(e)
	if near.is_empty():
		return _msg(id, "要去救災區先做到救災工作")
	var city := String(od.get("city", ""))
	if String(near["cityId"]) != city:
		return _msg(id, "呢度唔係%s嘅救災區" % _city_name(city))
	var need := int(od.get("need", 0))
	var done := int(od.get("done", 0))
	if done >= need:
		return _msg(id, "救災工作做完，返官宅覆命啦")
	var d := _active_disaster(city)
	if d.is_empty() or String(d.get("id", "")) != String(od.get("disaster", "")):
		return _msg(id, "天災已經過去，唔使再救（可以放棄官令）")
	var iid := _relief_item(String(od.get("disaster", "")))
	if iid <= 0 or RulesShop.count_item(ch["bag"], iid) <= 0:
		return _msg(id, "冇「%s」做唔到救災 (去工具店買)" % String(data.names.get(iid, "救災物品")))
	var sp_cost := maxi(1, int(relief_cfg().get("spCost", 10)))
	if int(ch.get("sp", 0)) < sp_cost:
		return _msg(id, "氣力不足 (要 %d SP)" % sp_cost)
	RulesShop.remove_item(ch["bag"], iid, 1)
	ch["sp"] = maxi(0, int(ch["sp"]) - sp_cost)
	done += 1
	od["done"] = done
	RulesDisaster.relief_weaken(d, done, need)
	_emit({"k": "relief_work", "id": id, "city": city, "done": done, "need": need, "item": iid})
	if done >= need:
		_msg(id, "「%s」救災工作完成 (%d/%d)！返官宅覆命。" % [String(d["name"]), done, need])
	else:
		_msg(id, "救災進度 %d/%d（%s 災情減弱咗）" % [done, need, String(d["name"])])


# 覆命獎勵: 名聲 +10 + 政治 exp + 救災專長 exp (行動力喺接令時已扣)
func _relief_reward(e: Dictionary, ch: Dictionary, od: Dictionary) -> void:
	var id := int(e["id"])
	var cfg := relief_cfg()
	var fame := int(cfg.get("fame", 10))
	ch["fame"] = int(ch.get("fame", 0)) + fame
	var tail := ""
	var pe := int(cfg.get("polExp", 0))
	if pe > 0:
		var r := RulesTiandi.cha_gain(int(ch["attrs"]["pol"]), int(ch.get("polExp", 0)), pe,
			{"chaExpPerPoint": data.office["polExpPerPoint"], "chaCap": data.office["polCap"]})
		ch["attrs"]["pol"] = int(r["cha"])
		ch["polExp"] = int(r["exp"])
		tail += "，政治經驗 +%d" % pe + ("，政治 +%d" % int(r["ups"]) if int(r["ups"]) > 0 else "")
		_sync_stats(e)
	var skill := String(cfg.get("expert", "jiuzai"))
	var before_lv := expert_lv(ch, skill)
	RulesExpert.add_exp(ch, data.experts, skill, int(cfg.get("expertExp", 0)))
	var after_lv := expert_lv(ch, skill)
	if after_lv > before_lv:
		var nm := String((data.experts["skills"] as Dictionary).get(skill, {}).get("name", skill))
		tail += "，「%s」專長升到 %d 級！" % [nm, after_lv]
	_emit({"k": "office_order", "id": id, "order": "relief", "done": true, "fame": fame, "contrib": 0})
	_msg(id, "救災官令完成：%s「%s」災情已緩，名聲 +%d%s" % [
		_city_name(String(od.get("city", ""))), _disaster_name(String(od.get("disaster", ""))), fame, tail])


# ================= S08d 名額競爭 (spec 08 §2 / 攻略 sy2_8_3) =================
# 【原】各階頭銜有名額限制，每月要競爭守位，輸咗跌返上一階。
# 單機化【自訂】: 每月初一 3 個 NPC 挑戰者 (獨立 SimRng，唔佔主 rng) 同玩家鬥名望。
func competition_cfg() -> Dictionary:
	return RulesTitle.comp_cfg(data.office)


# 玩家係咪入咗名額競爭系統 (由 cmd_claim_title 設定；舊存檔冇 = false，照唔競爭保兼容)
func title_competing(ch: Dictionary) -> bool:
	return bool(ch.get("titleCompete", false))


# 每月初一守位考驗 (sim.gd _daily_hook 叫)
func _title_contest_daily(day: int) -> void:
	var cfg := competition_cfg()
	if not bool(cfg.get("enabled", false)):
		return
	if not RulesTitle.is_month_start(day, int(data.world["clock"].get("monthDays", 30))):
		return
	for e in ents.values():
		if not e.has("ch"):
			continue
		var ch: Dictionary = e["ch"]
		if title_competing(ch):
			_title_contest(int(e["id"]), ch, day, cfg)


# 一次守位考驗: 3 NPC 挑戰者 (獨立 SimRng) vs 玩家名望；輸 → 跌一階 (spec 08 §2)
func _title_contest(id: int, ch: Dictionary, day: int, cfg: Dictionary) -> void:
	var rank := int(ch.get("titleRank", 0))
	if rank < int(cfg.get("minRank", 1)):
		return
	var t := RulesTitle.def_of(data.titles, rank)
	if t.is_empty():
		return
	var crng := SimRng.new(800001 + day * 3181 + rank * 101)
	var npc_scores: Array = []
	for _i in int(cfg.get("competitors", 3)):
		npc_scores.append(RulesTitle.npc_score(int(t["fame"]), crng.next(), cfg))
	var ps := RulesTitle.comp_score(int(ch.get("fame", 0)), cfg)
	var won := RulesTitle.defend_ok(ps, npc_scores)
	var best := 0
	for s in npc_scores:
		best = maxi(best, int(s))
	ch["titleContest"] = {"day": day, "rank": rank, "score": ps, "npc": npc_scores, "won": won}
	if won:
		_emit({"k": "title_contest", "id": id, "rank": rank, "won": true, "score": ps, "npcBest": best})
		_msg(id, "月初頭銜守位考驗：你以 %d 名望壓過 %d 位挑戰者（最強 %d），坐穩「%s」。" % [ps, npc_scores.size(), best, String(t["name"])])
	else:
		var nr := maxi(0, rank - 1)
		ch["titleRank"] = nr
		_emit({"k": "title_contest", "id": id, "rank": rank, "won": false, "score": ps, "npcBest": best, "dropTo": nr})
		_msg(id, "月初守位失敗：你 %d 名望不敵挑戰者（最強 %d），頭銜由「%s」跌返「%s」。" % [ps, best, String(t["name"]), RulesTitle.name_of(data.titles, nr)])


# UI read-model: 名額競爭狀態 + 上次考驗結果
func title_contest_view(id: int) -> Dictionary:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return {}
	var ch: Dictionary = e["ch"]
	return {
		"competing": title_competing(ch),
		"rank": int(ch.get("titleRank", 0)),
		"fame": int(ch.get("fame", 0)),
		"competitors": int(competition_cfg().get("competitors", 3)),
		"last": ch.get("titleContest", {}),
	}


# ================= S08e 義勇軍成立 + 定居 + 帶兵量 (spec 08 §4~§5 / 攻略 sy2_8_2、sy2_9_19) =================
# ch["militia"] = {founded, name, password, city, grade, supporters:[{id,name}], foundedDay}
# ch["homeCity"] = 定居城池 id ("" = 未定居)；rules/quest.gd pre.militia 睇 ch.militia.founded (S06c 掛鈎)。
func militia_cfg() -> Dictionary:
	return RulesMilitia.cfg(data.office)


# 讀寫 helper: 補齊預設欄 (寫入用；view 用 _militia_read 唔改 state)
func _militia_of(ch: Dictionary) -> Dictionary:
	if not ch.has("militia") or not (ch["militia"] is Dictionary):
		ch["militia"] = {}
	var m: Dictionary = ch["militia"]
	if not m.has("founded"):
		m["founded"] = false
	if not m.has("name"):
		m["name"] = ""
	if not m.has("password"):
		m["password"] = ""
	if not m.has("city"):
		m["city"] = ""
	if not m.has("grade"):
		m["grade"] = 1
	if not m.has("foundedDay"):
		m["foundedDay"] = -1
	if not m.has("supporters"):
		m["supporters"] = []
	return m


# view 用: 淨讀，冇 key 亦唔寫
func _militia_read(ch: Dictionary) -> Dictionary:
	var m = ch.get("militia", {})
	return m if m is Dictionary else {}


# 單位格 → 城池 id ("" = 唔喺城池)
func city_at(e: Dictionary) -> String:
	return String(data.map_at(int(e["x"]), int(e["y"])).get("city", ""))


# 定居城市清單 (maps.json kind:city；去重；newbie flag) —— 唔另開地圖，用現有城池
func _settle_cities() -> Array:
	var cfg := militia_cfg()
	var seen := {}
	var out: Array = []
	for md in data.maps:
		var cid := String(md.get("city", ""))
		if cid == "" or seen.has(cid):
			continue
		seen[cid] = true
		out.append({"id": cid, "name": String(md["name"]), "map": String(md["id"]), "newbie": RulesMilitia.is_newbie(cfg, cid)})
	return out


func _settle_city_name(city_id: String) -> String:
	for c in _settle_cities():
		if String(c["id"]) == city_id:
			return String(c["name"])
	return city_id


func home_city(ch: Dictionary) -> String:
	return String(ch.get("homeCity", ""))


# 定居 read-model
func settle_view(id: int) -> Dictionary:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return {}
	var ch: Dictionary = e["ch"]
	return {"at": city_at(e), "home": home_city(ch), "cities": _settle_cities()}


# 定居: 要企喺目標城池入面 (sim 只用座標判斷，唔需要新設施)
func cmd_settle(id: int, city: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var here := city_at(e)
	if here == "":
		return _msg(id, "要喺城池入面先定居得")
	if String(city) != here:
		return _msg(id, "你唔喺「%s」入面" % _settle_city_name(city))
	var why := RulesMilitia.settle_block(militia_cfg(), here, home_city(ch))
	if why != "":
		return _msg(id, why)
	ch["homeCity"] = here
	_emit({"k": "settle", "id": id, "city": here, "newbie": RulesMilitia.is_newbie(militia_cfg(), here)})
	_msg(id, "你定居喺「%s」。%s" % [_settle_city_name(here),
		"（新手城，唔可以喺度成立義勇軍）" if RulesMilitia.is_newbie(militia_cfg(), here) else "（可以喺度成立義勇軍）"])


# 遊說居民擁護 (近距離 + Lv/好感門檻；成功記快照，居民走咗都算)
func cmd_militia_invite(id: int, npc_id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var npc := ent(npc_id)
	if npc.is_empty() or not npc.has("ch"):
		return _msg(id, "搵唔到嗰個人")
	if not (state["bots"] as Array).has(int(npc_id)):
		return _msg(id, "佢唔係居民，唔可以擁護你")
	if int(npc["hp"]) <= 0:
		return _msg(id, "佢唔喺度")
	if maxi(absi(int(npc["x"]) - int(e["x"])), absi(int(npc["y"]) - int(e["y"]))) > NEAR:
		return _msg(id, "要行近%s先遊說得" % str(npc["name"]))
	var m := _militia_of(ch)
	var already := false
	for s in m["supporters"]:
		if int((s as Dictionary).get("id", 0)) == int(npc_id):
			already = true
	var lv := int(npc["ch"].get("level", 1))
	var favor := NpcMemory.affinity(npc["mem"], id) if npc.has("mem") else 0
	var why := RulesMilitia.invite_block(militia_cfg(), lv, favor, already, bool(m["founded"]))
	if why != "":
		return _msg(id, why)
	m["supporters"].append({"id": int(npc_id), "name": str(npc["name"])})
	var need := int(militia_cfg().get("supporterNeed", 10))
	_emit({"k": "militia_invite", "id": id, "npc": int(npc_id), "name": str(npc["name"]), "count": (m["supporters"] as Array).size()})
	_msg(id, "%s 願意擁護你！擁護者 %d/%d" % [str(npc["name"]), (m["supporters"] as Array).size(), need])


# 成立義勇軍【原 sy2_8_2】: 【團】→【起義】輸入名號 + 暗號
func cmd_militia_found(id: int, name: String, password: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var cfg := militia_cfg()
	var nb := RulesMilitia.name_block(cfg, name)
	if nb != "":
		return _msg(id, nb)
	var m := _militia_of(ch)
	var sup := (m["supporters"] as Array).size()
	var home := home_city(ch)
	var why := RulesMilitia.found_block(data.titles, cfg, ch, sup, home)
	if why != "":
		return _msg(id, why)
	ch["gold"] = int(ch["gold"]) - int(cfg["fund"])
	m["founded"] = true
	m["name"] = name.strip_edges()
	m["password"] = password
	m["city"] = home
	m["grade"] = 1
	m["foundedDay"] = int(_clock()["day"])
	_emit({"k": "militia_found", "id": id, "name": String(m["name"]), "city": home, "supporters": sup, "fund": int(cfg["fund"])})
	_msg(id, "義勇軍「%s」成立！根據地 %s，擁護者 %d 人自動入會，你係頭目（階級 %s）。扣經費 %d 兩。" % [
		String(m["name"]), _settle_city_name(home), sup, RulesMilitia.grade_name(cfg, 1), int(cfg["fund"])])


# 義勇軍 read-model: 狀態 + 帶兵量 + 4 成立條件
func militia_view(id: int) -> Dictionary:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return {}
	var ch: Dictionary = e["ch"]
	var cfg := militia_cfg()
	var m := _militia_read(ch)
	var sup := (m.get("supporters", []) as Array).size()
	var home := home_city(ch)
	var rank := int(ch.get("titleRank", 0))
	var conds: Array = [
		{"key": "title", "ok": rank >= int(cfg.get("minTitleRank", 6)), "text": "頭銜「南中郎將」以上"},
		{"key": "fame", "ok": int(ch.get("fame", 0)) >= int(cfg.get("minFame", 3000)), "text": "名聲 ≥ %d" % int(cfg.get("minFame", 3000))},
		{"key": "supporters", "ok": sup >= int(cfg.get("supporterNeed", 10)), "text": "擁護者 %d/%d" % [sup, int(cfg.get("supporterNeed", 10))]},
		{"key": "fund", "ok": int(ch.get("gold", 0)) >= int(cfg.get("fund", 200000)), "text": "經費 %d 兩" % int(cfg.get("fund", 200000))},
		{"key": "settle", "ok": home != "" and not RulesMilitia.is_newbie(cfg, home), "text": "定居非新手城"},
	]
	return {
		"founded": bool(m.get("founded", false)),
		"name": String(m.get("name", "")),
		"city": String(m.get("city", "")),
		"cityName": _settle_city_name(String(m.get("city", ""))),
		"grade": int(m.get("grade", 1)),
		"gradeName": RulesMilitia.grade_name(cfg, int(m.get("grade", 1))),
		"supporters": m.get("supporters", []),
		"supporterCount": sup,
		"supporterNeed": int(cfg.get("supporterNeed", 10)),
		"rank": rank,
		"soldiers": RulesMilitia.max_soldiers(data.titles, cfg, rank, int(m.get("grade", 1)), int(ch.get("level", 1)), bool(m.get("founded", false))),
		"homeCity": home,
		"homeName": _settle_city_name(home),
		"conditions": conds,
	}


# ================= S08f 營地建設 + 義勇軍工作 22 項 + 評定會議 (spec 08 §7~§8 / 攻略 sy2_8_6、sy2_8_8) =================
# m["camp"] = {facilities:{id:level}, build:{fac,target,progress,need}, stores:{}, trade:{city:0~100}, train:0}
# m["merit"] / m["performance"] (0~900+) / m["eval"] = {kinds:[], lastMerit, lastDay, settledPeriod}
# m["role"] (單機玩家固定頭目 banner) / m["hasCity"] (S10 佔城前 false → 淨得監督/商情)。

func camp_cfg() -> Dictionary:
	return data.camp


func _camp_read(m: Dictionary) -> Dictionary:
	var c = m.get("camp", {})
	return c if c is Dictionary else {"facilities": {}, "build": {}, "stores": {}, "trade": {}, "train": 0}


# 寫入用: 補齊 camp/eval 預設欄 (舊存檔兼容)
func _camp_of(ch: Dictionary) -> Dictionary:
	var m := _militia_of(ch)
	if not m.has("camp") or not (m["camp"] is Dictionary):
		m["camp"] = {}
	var c: Dictionary = m["camp"]
	if not c.has("facilities") or not (c["facilities"] is Dictionary):
		c["facilities"] = {}
	for f in camp_cfg().get("facilities", []):
		var fid := String(f["id"])
		if not c["facilities"].has(fid):
			c["facilities"][fid] = int(f.get("initial", 0))
	if not c.has("build") or not (c["build"] is Dictionary):
		c["build"] = {}
	if not c.has("stores") or not (c["stores"] is Dictionary):
		c["stores"] = {}
	for k in ["gold", "grain", "militaryGrain", "soldiers", "horses", "resource", "medicine", "products", "arms", "officers"]:
		if not c["stores"].has(k):
			c["stores"][k] = 0
	if not c.has("trade") or not (c["trade"] is Dictionary):
		c["trade"] = {}
	if not c.has("train"):
		c["train"] = 0
	if not m.has("merit"):
		m["merit"] = 0
	if not m.has("performance"):
		m["performance"] = 0
	if not m.has("eval") or not (m["eval"] is Dictionary):
		m["eval"] = {}
	var ev: Dictionary = m["eval"]
	if not ev.has("kinds"):
		ev["kinds"] = []
	if not ev.has("lastMerit"):
		ev["lastMerit"] = 0
	if not ev.has("lastDay"):
		ev["lastDay"] = -1
	if not ev.has("settledPeriod"):
		ev["settledPeriod"] = ""
	if not m.has("role"):
		m["role"] = "banner"
	if not m.has("hasCity"):
		m["hasCity"] = false
	return c


func militia_role(ch: Dictionary) -> String:
	return String(_militia_read(ch).get("role", "banner"))


func militia_has_city(ch: Dictionary) -> bool:
	return bool(_militia_read(ch).get("hasCity", false))


func _at_home(e: Dictionary, m: Dictionary) -> bool:
	var city := String(m.get("city", ""))
	return city != "" and city_at(e) == city


func _fac_level(m: Dictionary, fac_id: String) -> int:
	var facs = _camp_read(m).get("facilities", {})
	if facs is Dictionary and facs.has(fac_id):
		return int(facs[fac_id])
	return RulesCamp.initial_level(camp_cfg(), fac_id)


func _stores(m: Dictionary) -> Dictionary:
	var s = _camp_read(m).get("stores", {})
	return s if s is Dictionary else {}


func _store_facility(store: String) -> String:
	match store:
		"gold":
			return "treasury"
		"grain", "militaryGrain":
			return "granary"
		"soldiers", "horses":
			return "barracks"
		"resource", "medicine", "products":
			return "resstore"
		"arms":
			return "armsstore"
	return ""


func _store_cap(m: Dictionary, store: String) -> int:
	var fac := _store_facility(store)
	if fac == "":
		return -1
	return RulesCamp.facility_cap(camp_cfg(), fac, _fac_level(m, fac), store)


# 加物資入義勇軍倉庫 (受設施上限封頂)；回傳實際加咗幾多
func _store_add(c: Dictionary, m: Dictionary, store: String, amount: int) -> int:
	var cur := int((c.get("stores", {}) as Dictionary).get(store, 0))
	var cap := _store_cap(m, store)
	var add := amount
	if cap >= 0:
		add = mini(add, maxi(0, cap - cur))
	c["stores"][store] = cur + add
	return add


# 營地 read-model (UI 用)
func camp_view(id: int) -> Dictionary:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return {}
	var ch: Dictionary = e["ch"]
	var cfg := camp_cfg()
	var m := _militia_read(ch)
	var c := _camp_read(m)
	var founded := bool(m.get("founded", false))
	var at_home := founded and _at_home(e, m)
	var level := _fac_level(m, "camp")
	var facs: Array = []
	var cfacs: Dictionary = c.get("facilities", {})
	for f in cfg.get("facilities", []):
		var fid := String(f["id"])
		var lv := int(cfacs.get(fid, int(f.get("initial", 0))))
		var row := {"id": fid, "name": String(f["name"]), "level": lv, "func": String(f.get("func", "")), "initial": int(f.get("initial", 0))}
		if lv < RulesCamp.max_level(cfg):
			var t := lv + 1
			row["nextLevel"] = t
			row["cost"] = RulesCamp.upgrade_cost(cfg, fid, t)
		facs.append(row)
	return {
		"founded": founded, "atHome": at_home, "city": String(m.get("city", "")),
		"cityName": _settle_city_name(String(m.get("city", ""))),
		"level": level, "maxLevel": RulesCamp.max_level(cfg), "workCap": RulesCamp.work_cap(cfg, level),
		"roles": cfg.get("roles", []), "role": String(m.get("role", "banner")), "roleName": RulesCamp.role_name(cfg, String(m.get("role", "banner"))),
		"positions": RulesCamp.positions_at(cfg, level), "facilities": facs, "build": c.get("build", {}),
		"stores": c.get("stores", {}), "train": int(c.get("train", 0)), "trade": c.get("trade", {}),
		"merit": int(m.get("merit", 0)), "performance": int(m.get("performance", 0)),
		"canUpgradeRole": RulesCamp.can_upgrade_role(cfg, String(m.get("role", "banner"))),
	}


func _camp_upgrade_block(e: Dictionary, ch: Dictionary, fac_id: String) -> String:
	var cfg := camp_cfg()
	var m := _militia_read(ch)
	if not bool(m.get("founded", false)):
		return "未成立義勇軍，起唔到營地"
	if not RulesCamp.can_upgrade_role(cfg, String(m.get("role", "banner"))):
		return "得頭目/參軍先指定到升級"
	if not _at_home(e, m):
		return "要返根據地「%s」先指定到升級" % _settle_city_name(String(m.get("city", "")))
	var f := RulesCamp.def_of(cfg, fac_id)
	if f.is_empty():
		return "冇呢個設施"
	var lv := _fac_level(m, fac_id)
	if lv >= RulesCamp.max_level(cfg):
		return "「%s」已經封頂" % String(f["name"])
	if not (_camp_read(m).get("build", {}) as Dictionary).is_empty():
		return "仲有建設緊，監督完先"
	var cost := RulesCamp.upgrade_cost(cfg, fac_id, lv + 1)
	if int(ch.get("gold", 0)) < int(cost["gold"]):
		return "軍資唔夠 (要 %d 兩)" % int(cost["gold"])
	for iid in cost["materials"]:
		var need := int(cost["materials"][iid])
		if RulesShop.count_item(ch["bag"], int(iid)) < need:
			return "材料唔夠：%s ×%d" % [String(data.names.get(int(iid), str(iid))), need]
	return ""


# 頭目/參軍指定升級：即扣軍資 + 材料，開一個建設（等成員監督到 100 完成度）
func cmd_camp_upgrade(id: int, fac_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var why := _camp_upgrade_block(e, ch, fac_id)
	if why != "":
		return _msg(id, why)
	var cfg := camp_cfg()
	var m := _militia_of(ch)
	var c := _camp_of(ch)
	var lv := int(c["facilities"][fac_id])
	var t := lv + 1
	var cost := RulesCamp.upgrade_cost(cfg, fac_id, t)
	ch["gold"] = int(ch["gold"]) - int(cost["gold"])
	for iid in cost["materials"]:
		RulesShop.remove_item(ch["bag"], int(iid), int(cost["materials"][iid]))
	c["build"] = {"fac": fac_id, "target": t, "progress": 0.0, "need": RulesCamp.supervise_target(cfg)}
	_emit({"k": "camp_upgrade", "id": id, "fac": fac_id, "target": t, "gold": int(cost["gold"])})
	_msg(id, "指定升級「%s」到 %d 級：扣 %d 兩 + 材料，等成員監督建設。" % [String(RulesCamp.def_of(cfg, fac_id).get("name", fac_id)), t, int(cost["gold"])])


# 設施升級完成度 +1 次（評定「監督」工作之一）；fac_id 要同 build 對上
func cmd_camp_supervise(id: int, fac_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var m := _militia_read(e["ch"])
	var build: Dictionary = _camp_read(m).get("build", {})
	if build.is_empty() or String(build.get("fac", "")) != fac_id:
		return _msg(id, "而家冇建設緊呢個設施")
	cmd_militia_work(id, "jiandu")


# ---- 義勇軍工作 ----
func _work_expert_lv(ch: Dictionary, w: Dictionary) -> int:
	var e := String(w.get("expert", ""))
	return expert_lv(ch, e) if e != "" else 0


# 工作可唔做得："" = 得
func _work_block(e: Dictionary, ch: Dictionary, work_id: String) -> String:
	var cfg := camp_cfg()
	var m := _militia_read(ch)
	if not bool(m.get("founded", false)):
		return "未成立義勇軍"
	var w := RulesMilitiaWork.def_of(cfg, work_id)
	if w.is_empty() or not RulesMilitiaWork.is_available(cfg, bool(m.get("hasCity", false)), work_id):
		return "冇呢種工作 (或者未擁有城池)"
	if ap_of(ch) < _office_ap_cost(ch):
		return "行動力不足 (要 %d)" % _office_ap_cost(ch)
	var c := _camp_read(m)
	match String(w.get("kind", "")):
		"supervise":
			if (c.get("build", {}) as Dictionary).is_empty():
				return "冇設施喺建設緊"
		"internal":
			if RulesCity.attr_of(city_attrs(String(m.get("city", ""))), String(w["attr"]), _city_attr_cfg()) >= 100:
				return "城池「%s」已經封頂 (100)" % RulesCity.name_of(_city_attr_cfg(), String(w["attr"]))
		"recruit":
			var cap := _store_cap(m, "soldiers")
			if cap >= 0 and int(_stores(m).get("soldiers", 0)) >= cap:
				return "士兵已經滿咗 (上限 %d)" % cap
		"armament", "donate":
			if w.has("costGold") and int(ch.get("gold", 0)) < int(w["costGold"]):
				return "軍費唔夠 (要 %d 兩)" % int(w["costGold"])
			for ci in w.get("costItems", []):
				var need := int(ci[1])
				if RulesShop.count_item(ch["bag"], int(ci[0])) < need:
					return "物資唔夠：%s ×%d" % [String(data.names.get(int(ci[0]), str(ci[0]))), need]
			for cs in w.get("costStore", []):
				if int(_stores(m).get(String(cs[0]), 0)) < int(cs[1]):
					return "義勇軍庫存唔夠：%s" % String(cs[0])
	return ""


# 執行一件工作效果；回傳描述字串。會 mutate ch/m/c
func _work_apply(e: Dictionary, ch: Dictionary, m: Dictionary, c: Dictionary, w: Dictionary) -> String:
	var cfg := camp_cfg()
	var kind := String(w.get("kind", ""))
	var wid := String(w["id"])
	var lv := _work_expert_lv(ch, w)
	var exp_id := String(w.get("expert", ""))
	match kind:
		"internal":
			var city := String(m.get("city", ""))
			var attrs := city_attrs(city)
			var key := String(w["attr"])
			var cur := RulesCity.attr_of(attrs, key, _city_attr_cfg())
			var g := RulesCity.attr_gain(int(data.office.get("domestic", {}).get("baseGain", 2)), _work_mult(w, lv))
			g = mini(g, 100 - cur)
			attrs[key] = cur + g
			city_attrs_set(city, attrs)
			if exp_id != "":
				RulesExpert.add_exp(ch, data.experts, exp_id, 3)
			return "%s +%d（而家 %d）" % [RulesCity.name_of(_city_attr_cfg(), key), g, cur + g]
		"supervise":
			var build: Dictionary = c["build"]
			var pts := RulesCamp.supervise_points(cfg, int((ch.get("attrs", {}) as Dictionary).get("pol", 0)), work_lv(ch, "carpentry"), String(m.get("role", "banner")))
			build["progress"] = minf(float(build.get("need", 100)), float(build.get("progress", 0.0)) + pts)
			c["build"] = build
			var fac_id := String(build["fac"])
			var tail := "完成度 %.1f/%.1f" % [float(build["progress"]), float(build["need"])]
			if float(build["progress"]) >= float(build["need"]):
				c["facilities"][fac_id] = int(build["target"])
				c["build"] = {}
				_emit({"k": "camp_built", "id": int(e["id"]), "fac": fac_id, "level": int(c["facilities"][fac_id])})
				tail = "「%s」升到 %d 級！" % [String(RulesCamp.def_of(cfg, fac_id).get("name", fac_id)), int(c["facilities"][fac_id])]
			return tail
		"trade":
			var city2 := String(m.get("city", ""))
			var t2: Dictionary = c["trade"]
			var nv := mini(100, int(t2.get(city2, 0)) + 5)
			t2[city2] = nv
			c["trade"] = t2
			if exp_id != "":
				RulesExpert.add_exp(ch, data.experts, exp_id, 3)
			return "%s 商情情報值 %d" % [_settle_city_name(city2), nv]
		"train":
			var add_t := maxi(1, int(round(RulesExpert.militia_mult(lv))))
			c["train"] = mini(100, int(c.get("train", 0)) + add_t)
			if exp_id != "":
				RulesExpert.add_exp(ch, data.experts, exp_id, 3)
			return "營地訓練度 +%d（而家 %d）" % [add_t, int(c["train"])]
		"recruit":
			var got := _store_add(c, m, "soldiers", 10000)
			return "招募士兵 +%d（而家 %d）" % [got, int(c["stores"]["soldiers"])]
		"armament", "donate":
			if w.has("costGold"):
				ch["gold"] = int(ch["gold"]) - int(w["costGold"])
			for ci2 in w.get("costItems", []):
				RulesShop.remove_item(ch["bag"], int(ci2[0]), int(ci2[1]))
			for cs2 in w.get("costStore", []):
				var sk := String(cs2[0])
				c["stores"][sk] = int(c["stores"].get(sk, 0)) - int(cs2[1])
			var store := String(w["store"])
			var got2 := _store_add(c, m, store, int(w.get("amount", 0)))
			if exp_id != "":
				RulesExpert.add_exp(ch, data.experts, exp_id, 3)
			return "%s +%d（而家 %d）" % [store, got2, int(c["stores"][store])]
	return ""


func _work_mult(w: Dictionary, lv: int) -> float:
	match String(w.get("mult", "domestic")):
		"militia":
			return RulesExpert.militia_mult(lv)
		"relief":
			return RulesExpert.relief_mult(lv)
	return RulesExpert.domestic_mult(lv)


func _eval_assigned(m: Dictionary, work_id: String) -> bool:
	var kinds: Array = (m.get("eval", {}) as Dictionary).get("kinds", [])
	var a := RulesMilitiaWork.assignment_of(camp_cfg(), work_id)
	return a != "" and kinds.has(a)


# 工作 read-model
func militia_work_view(id: int) -> Dictionary:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return {}
	var ch: Dictionary = e["ch"]
	var cfg := camp_cfg()
	var m := _militia_read(ch)
	var founded := bool(m.get("founded", false))
	var has_city := bool(m.get("hasCity", false))
	var rows: Array = []
	for w in RulesMilitiaWork.available(cfg, has_city):
		var wid := String(w["id"])
		var why := _work_block(e, ch, wid)
		var assigned := _eval_assigned(m, wid)
		rows.append({"id": wid, "name": String(w["name"]), "series": String(w["series"]), "kind": String(w["kind"]),
			"assignment": RulesMilitiaWork.assignment_of(cfg, wid), "assigned": assigned,
			"expert": String(w.get("expert", "")), "perf": RulesMilitiaWork.performance_gain(cfg, wid, _work_expert_lv(ch, w), assigned),
			"can": why == "", "why": why})
	return {"founded": founded, "hasCity": has_city, "city": String(m.get("city", "")),
		"cityName": _settle_city_name(String(m.get("city", ""))), "apCost": _office_ap_cost(ch),
		"works": rows, "allWorks": RulesMilitiaWork.works(cfg).size()}


# 執行義勇軍工作（每日一次扣行動力 10）
func cmd_militia_work(id: int, work_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var why := _work_block(e, ch, work_id)
	if why != "":
		return _msg(id, why)
	var cfg := camp_cfg()
	var m := _militia_of(ch)
	var c := _camp_of(ch)
	var w := RulesMilitiaWork.def_of(cfg, work_id)
	var assigned := _eval_assigned(m, work_id)
	var gain := RulesMilitiaWork.performance_gain(cfg, work_id, _work_expert_lv(ch, w), assigned)
	var detail := _work_apply(e, ch, m, c, w)
	ch["ap"] = ap_of(ch) - _office_ap_cost(ch)
	m["performance"] = int(m.get("performance", 0)) + gain
	_emit({"k": "militia_work", "id": id, "work": work_id, "perf": gain, "assigned": assigned})
	_msg(id, "義勇軍工作「%s」完成：%s；績效 +%d%s" % [String(w["name"]), detail, gain, "（獲指派加成）" if assigned else ""])


# ---- 評定會議 (spec 08 §4 / 攻略 sy2_8_5) ----
func _period_of(day: int) -> String:
	var md := int(data.world["clock"].get("monthDays", 30))
	return str(int((day - 1) / md))


func eval_view(id: int) -> Dictionary:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return {}
	var ch: Dictionary = e["ch"]
	var cfg := camp_cfg()
	var m := _militia_read(ch)
	var ev: Dictionary = m.get("eval", {})
	return {"founded": bool(m.get("founded", false)), "kinds": ev.get("kinds", []),
		"assignmentKinds": RulesMilitiaWork.assignment_kinds(cfg), "maxAssignments": RulesMilitiaWork.max_assignments(cfg),
		"performance": int(m.get("performance", 0)), "merit": int(m.get("merit", 0)),
		"lastMerit": int(ev.get("lastMerit", 0)), "lastDay": int(ev.get("lastDay", -1)),
		"nextDelta": RulesMilitiaWork.merit_delta(cfg, int(m.get("performance", 0))),
		"table": cfg.get("meritTable", [])}


func _eval_set_kinds(id: int, ch: Dictionary, kinds: Array) -> String:
	var cfg := camp_cfg()
	var allow := RulesMilitiaWork.assignment_kinds(cfg)
	var seen := {}
	var out: Array = []
	for k in kinds:
		var ks := String(k)
		if not allow.has(ks):
			return "唔可以指派「%s」" % ks
		if seen.has(ks):
			continue
		seen[ks] = true
		out.append(ks)
	if out.size() > RulesMilitiaWork.max_assignments(cfg):
		return "最多指派 %d 種工作" % RulesMilitiaWork.max_assignments(cfg)
	_camp_of(ch)    # 確保 _camp_of 已補 camp 欄
	var m := _militia_of(ch)
	var ev: Dictionary = m["eval"]
	ev["kinds"] = out
	return ""


# 指派本月工作 (捐獻/監督/商情)
func cmd_eval_assign(id: int, kinds: Array) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var m := _militia_read(ch)
	if not bool(m.get("founded", false)):
		return _msg(id, "未成立義勇軍，開唔到評定會議")
	var why := _eval_set_kinds(id, ch, kinds)
	if why != "":
		return _msg(id, why)
	_emit({"k": "eval_assign", "id": id, "kinds": kinds})
	_msg(id, "指派本月工作：%s" % ("、".join(_kind_names(kinds)) if not kinds.is_empty() else "（無）"))


func _kind_names(kinds: Array) -> Array:
	var names := {"donate": "捐獻", "supervise": "監督", "trade": "商情"}
	var out: Array = []
	for k in kinds:
		out.append(String(names.get(String(k), k)))
	return out


# 召開評定會議：結算上期績效 → 功績、績效歸 0、指派新工作
func cmd_eval_meeting(id: int, kinds: Array) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var cfg := camp_cfg()
	var m := _militia_read(ch)
	if not bool(m.get("founded", false)):
		return _msg(id, "未成立義勇軍，開唔到評定會議")
	if String(m.get("role", "banner")) != "banner":
		return _msg(id, "得頭目先召開到評定會議")
	var why := _eval_set_kinds(id, ch, kinds)
	if why != "":
		return _msg(id, why)
	var mm := _militia_of(ch)
	var perf := int(mm.get("performance", 0))
	var delta := RulesMilitiaWork.merit_delta(cfg, perf)
	mm["merit"] = int(mm.get("merit", 0)) + delta
	mm["performance"] = 0
	var ev: Dictionary = mm["eval"]
	ev["lastMerit"] = delta
	ev["lastDay"] = int(_clock()["day"])
	ev["settledPeriod"] = _period_of(int(_clock()["day"]))
	_emit({"k": "eval_meeting", "id": id, "performance": perf, "merit": delta, "total": int(mm["merit"])})
	_msg(id, "召開評定會議：上期績效 %d → 功績 %+d（總功績 %d）；績效歸零，重新指派。" % [perf, delta, int(mm["merit"])])


# 每月初一自動結算各義勇軍成員績效 → 功績 (spec 08 §4)
func _eval_daily(day: int) -> void:
	if not RulesTitle.is_month_start(day, int(data.world["clock"].get("monthDays", 30))):
		return
	var period := _period_of(day)
	for e in ents.values():
		if not e.has("ch"):
			continue
		var ch: Dictionary = e["ch"]
		var m = ch.get("militia", {})
		if not (m is Dictionary) or not bool(m.get("founded", false)):
			continue
		var ev: Dictionary = m.get("eval", {})
		if String(ev.get("settledPeriod", "")) == period:
			continue
		var perf := int(m.get("performance", 0))
		var delta := RulesMilitiaWork.merit_delta(camp_cfg(), perf)
		m["merit"] = int(m.get("merit", 0)) + delta
		ev["lastMerit"] = delta
		ev["lastDay"] = day
		ev["settledPeriod"] = period
		m["eval"] = ev
		ch["militia"] = m
		_emit({"k": "eval_merit", "id": int(e["id"]), "performance": perf, "merit": delta, "total": int(m["merit"])})
		_msg(int(e["id"]), "月初評定：上期績效 %d → 功績 %+d（總功績 %d）" % [perf, delta, int(m["merit"])])


# 團體任務完成 → 義勇軍績效 (spec 06 §6 / spec 08 §8 接軌)
func _on_militia_quest_done(q: Dictionary) -> void:
	if String(q.get("type", "")) != "group":
		return
	var pid := int(state["player_id"])
	var p := ent(pid)
	if p.is_empty() or not p.has("ch"):
		return
	var m = p["ch"].get("militia", {})
	if not (m is Dictionary) or not bool(m.get("founded", false)):
		return
	m["performance"] = int(m.get("performance", 0)) + int(camp_cfg().get("questPerf", 30))
	p["ch"]["militia"] = m


# 每月/每日重複任務：完成旗標到期清零 (S06c 延後：每月重複/日窗口)
func _militia_quest_reset(day: int) -> void:
	var md := int(data.world["clock"].get("monthDays", 30))
	var month_start := RulesTitle.is_month_start(day, md)
	for e in ents.values():
		if not e.has("ch"):
			continue
		var ch: Dictionary = e["ch"]
		var qd = ch.get("questDone", {})
		if not (qd is Dictionary) or qd.is_empty():
			continue
		for q in data.quests:
			var rp := String(q.get("repeat", ""))
			if rp == "":
				continue
			var qid := String(q["id"])
			if not bool(qd.get(qid, false)):
				continue
			if rp == "daily" or (rp == "monthly" and month_start):
				qd.erase(qid)
		ch["questDone"] = qd
