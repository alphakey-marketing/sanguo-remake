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
