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
	_emit({"k": "office_order", "id": id, "order": String(o["id"]), "done": true, "fame": fame, "contrib": contrib})
	_msg(id, "官令「%s」完成：名聲 +%d，官宅貢獻 +%d%s" % [o["name"], fame, contrib, tail])


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
