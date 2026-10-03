extends "res://sim/sim_office.gd"
# Sim 繼承鏈: 居民委託 + 武將收集冊 (Step 16, spec 06 §4 / spec 09 將軍令)
# ch.comm = {salt, active:[委託單 + accepted/prog], taken:{giver: 日}}  (taken = 嗰日已接/做過，唔再出單)
# ch.orderBook = {item id(String): n}  收集冊入面嘅將軍令 (唔佔背包重量)


func _comm(ch: Dictionary) -> Dictionary:
	if not ch.has("comm"):
		ch["comm"] = {"salt": int(rng.s), "active": [], "taken": {}}     # salt 只讀 rng 狀態，唔推進 RNG
	return ch["comm"]


func _comm_npc_near(e: Dictionary, giver: String) -> String:
	var npc: Dictionary = data.quest_npcs.get(giver, {})
	if npc.is_empty() or not bool(npc.get("commission", false)):
		return "搵唔到委託人"
	if not bool(state["quest_npcs"].get(giver, {}).get("visible", false)):
		return "呢度搵唔到%s" % npc["name"]
	if not _near(e, int(npc["x"]), int(npc["y"])):
		return "要行近%s先得" % npc["name"]
	return ""


func _comm_active_of(ch: Dictionary, giver: String) -> Dictionary:
	for c in _comm(ch)["active"]:
		if String(c["giver"]) == giver:
			return c
	return {}


# 今日呢位委託人出嘅單 ({} = 冇 / 今日做過 / 手上有佢嘅單)
func comm_offer(ch: Dictionary, giver: String) -> Dictionary:
	var cm := _comm(ch)
	var day := int(_clock()["day"])
	if int(cm["taken"].get(giver, -1)) == day or not _comm_active_of(ch, giver).is_empty():
		return {}
	return RulesCommission.offer(data, giver, day, int(cm["salt"]))


# 接委託: deliver 即派信；repair 即場修 (要技能 + 工具 + SP) 做完即完成
func cmd_comm_accept(id: int, giver: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var why := _comm_npc_near(e, giver)
	if why != "":
		return _msg(id, why)
	var ch: Dictionary = e["ch"]
	var cm := _comm(ch)
	var o := comm_offer(ch, giver)
	if o.is_empty():
		return _msg(id, "%s今日冇委託喇" % data.quest_npcs[giver]["name"])
	var day := int(_clock()["day"])
	if String(o["kind"]) == "repair":
		var err := _comm_repair_check(e, o)
		if err != "":
			return _msg(id, err)
		var broke := _adv_use(ch, String(o["skill"]))
		cm["taken"][giver] = day
		_work_gain(id, ch, String(o["skill"]), int(data.comm["repair"]["workExp"]))
		_comm_reward(e, o, "幫%s修好%s%s" % [data.quest_npcs[giver]["name"], data.names.get(int(o["item"]), ""), "（工具用爛咗）" if broke else ""])
		return
	if (cm["active"] as Array).size() >= int(data.comm["maxActive"]):
		return _msg(id, "手上委託太多（最多 %d 單）" % int(data.comm["maxActive"]))
	var c := o.duplicate(true)
	c["accepted"] = day
	if String(c["kind"]) == "hunt":
		c["prog"] = 0
	if String(c["kind"]) == "deliver":
		RulesShop.add_item(ch["bag"], int(data.comm["letterItem"]), 1)
	cm["active"].append(c)
	cm["taken"][giver] = day
	_emit({"k": "comm", "dst": id, "giver": giver, "state": "accepted", "kind": c["kind"]})
	_msg(id, "接咗委託：%s" % RulesCommission.describe(data, c))


# 即場修理條件 (同 Step 12 自己修理一樣，但唔使去工房)【自訂】
func _comm_repair_check(e: Dictionary, o: Dictionary) -> String:
	var ch: Dictionary = e["ch"]
	var sk := String(o["skill"])
	var ad: Dictionary = data.work_adv[sk]
	if not adv_unlocked(ch, sk):
		return "要識%s先修得（未解鎖）" % ad["name"]
	if work_lv(ch, sk) < int(o["lv"]):
		return "%s要 %d 級先修得" % [ad["name"], int(o["lv"])]
	if not ch.get("tools", {}).has(sk):
		return "要裝備%s工具" % ad["name"]
	if int(ch["sp"]) < RulesWork.sp_cost(RulesStats.max_sp(int(ch["level"]), ch["attrs"], ch)):
		return "SP 唔夠"
	return ""


# 返委託人覆命 (hunt 夠數 / collect 交材料)
func cmd_comm_report(id: int, giver: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var why := _comm_npc_near(e, giver)
	if why != "":
		return _msg(id, why)
	var ch: Dictionary = e["ch"]
	var c := _comm_active_of(ch, giver)
	if c.is_empty():
		return _msg(id, "你冇接%s嘅委託" % data.quest_npcs[giver]["name"])
	if not RulesCommission.can_report(c, ch["bag"]):
		return _msg(id, "委託未完成：%s" % RulesCommission.describe(data, c))
	if String(c["kind"]) == "collect":
		RulesShop.remove_item(ch["bag"], int(c["item"]), int(c["n"]))
	_comm(ch)["active"].erase(c)
	_comm_reward(e, c, "委託完成：%s" % RulesCommission.describe(data, c))


func cmd_comm_abandon(id: int, giver: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var c := _comm_active_of(e["ch"], giver)
	if c.is_empty():
		return
	_comm_drop(e["ch"], c)
	_msg(id, "放棄咗委託：%s" % RulesCommission.describe(data, c))


func _comm_drop(ch: Dictionary, c: Dictionary) -> void:
	if String(c["kind"]) == "deliver":
		RulesShop.remove_item(ch["bag"], int(data.comm["letterItem"]), 1)
	_comm(ch)["active"].erase(c)


func _comm_reward(e: Dictionary, c: Dictionary, head: String) -> void:
	var id := int(e["id"])
	var ch: Dictionary = e["ch"]
	var r: Dictionary = c["reward"]
	ch["gold"] = int(ch["gold"]) + int(r.get("gold", 0))
	ch["fame"] = int(ch.get("fame", 0)) + int(r.get("fame", 0))
	if RulesStats.gain_exp(data, ch, int(r.get("exp", 0))) > 0:
		_sync_quest_npcs()
	_sync_stats(e)
	_emit({"k": "comm", "dst": id, "giver": String(c["giver"]), "state": "done", "kind": c["kind"], "reward": r})
	_msg(id, "%s（%s）" % [head, RulesCommission.reward_text(r)])


# 送信: 同目標 NPC 傾偈 = 交信完成 (sim_quest.cmd_quest_talk 叫)；返 true = 處理咗
func _comm_on_talk(e: Dictionary, npc_id: String) -> bool:
	var ch: Dictionary = e["ch"]
	for c in _comm(ch)["active"]:
		if String(c["kind"]) != "deliver" or String(c["to"]) != npc_id:
			continue
		if not RulesShop.remove_item(ch["bag"], int(data.comm["letterItem"]), 1):
			return false
		_comm(ch)["active"].erase(c)
		_comm_reward(e, c, "將%s嘅信交咗畀%s" % [data.quest_npcs[String(c["giver"])]["name"], data.quest_npcs[npc_id]["name"]])
		return true
	return false


# 打怪計數 (sim_combat._kill_mob 叫)
func _comm_on_kill(by: Dictionary, def_id: int) -> void:
	if not by.has("ch") or not by["ch"].has("comm"):
		return
	for c in RulesCommission.on_kill(by["ch"]["comm"]["active"], def_id):
		var s := RulesCommission.describe(data, c)
		_msg(int(by["id"]), "委託：%s%s" % [s, "，返去覆命" if int(c["prog"]) >= int(c["n"]) else ""])


# 日結: 過期委託收走
func _comm_daily(day: int) -> void:
	var exp_days := int(data.comm["expireDays"])
	for e in ents.values():
		if not e.has("ch") or not e["ch"].has("comm"):
			continue
		for c in (e["ch"]["comm"]["active"] as Array).duplicate():
			if RulesCommission.expired(c, day, exp_days):
				_comm_drop(e["ch"], c)
				_msg(int(e["id"]), "委託過期：%s" % RulesCommission.describe(data, c))


# UI 記事: 手上委託
func view_commissions() -> Array:
	var ch := player_ch()
	var out: Array = []
	if ch.is_empty() or not ch.has("comm"):
		return out
	var day := int(_clock()["day"])
	var exp_days := int(data.comm["expireDays"])
	for c in ch["comm"]["active"]:
		out.append({"giver": String(c["giver"]), "name": String(data.quest_npcs[String(c["giver"])]["name"]),
			"kind": String(c["kind"]), "text": RulesCommission.describe(data, c),
			"ready": RulesCommission.can_report(c, ch["bag"]), "left": exp_days - (day - int(c["accepted"])),
			"reward": RulesCommission.reward_text(c["reward"])})
	return out


# ================= 武將收集冊【原】(sy2_6_1) =================
func _book_item() -> int:
	return int(data.comm["book"]["item"])


func is_order_item(item: int) -> bool:
	return RulesGeneral.order_general_name(String(data.names.get(item, "")), String(data.gen2_cfg["orderSuffix"])) != ""


# 許昌老丈: 6 粒屬性石各 1 換 1 本 (已有就唔換)
func cmd_book_exchange(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var npc: Dictionary = data.quest_npcs[String(data.comm["book"]["npc"])]
	if not _near(e, int(npc["x"]), int(npc["y"])):
		return _msg(id, "要行近%s先得" % npc["name"])
	var ch: Dictionary = e["ch"]
	if RulesShop.count_item(ch["bag"], _book_item()) > 0:
		return _msg(id, "%s：你已經有收集冊喇" % npc["name"])
	var stones: Array = data.comm["book"]["stones"]
	for s in stones:
		if RulesShop.count_item(ch["bag"], int(s)) <= 0:
			return _msg(id, "%s：要%s各 1 粒先換得" % [npc["name"], "、".join(stones.map(func(x): return data.names.get(int(x), "")))])
	for s in stones:
		RulesShop.remove_item(ch["bag"], int(s), 1)
	RulesShop.add_item(ch["bag"], _book_item(), 1)
	_emit({"k": "book", "dst": id, "state": "got"})
	_msg(id, "換咗 1 本%s！將軍令可以收入冊，唔佔重量" % data.names.get(_book_item(), "武將收集冊"))


# 背包所有將軍令收入冊 (要有冊)
func cmd_book_put(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var ch: Dictionary = e["ch"]
	if RulesShop.count_item(ch["bag"], _book_item()) <= 0:
		return _msg(id, "冇武將收集冊")
	var book: Dictionary = ch.get("orderBook", {})
	var n := 0
	for b in (ch["bag"] as Array).duplicate():
		var it := int(b["id"])
		var k := int(b["n"])
		if k <= 0 or not is_order_item(it):
			continue
		RulesShop.remove_item(ch["bag"], it, k)
		book[str(it)] = int(book.get(str(it), 0)) + k
		n += k
	ch["orderBook"] = book
	if n == 0:
		return _msg(id, "背包冇將軍令")
	_emit({"k": "book", "dst": id, "state": "put", "n": n})
	_msg(id, "收咗 %d 張將軍令入收集冊" % n)


# 由冊攞 1 張出返背包
func cmd_book_take(id: int, item: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var book: Dictionary = e["ch"].get("orderBook", {})
	var k := int(book.get(str(item), 0))
	if k <= 0:
		return
	if k == 1:
		book.erase(str(item))
	else:
		book[str(item)] = k - 1
	RulesShop.add_item(e["ch"]["bag"], item, 1)
	_msg(id, "由收集冊攞咗「%s」出嚟" % data.names.get(item, str(item)))


# 背包 + 冊 嘅數量 (登用用)
func order_count(ch: Dictionary, item: int) -> int:
	return RulesShop.count_item(ch["bag"], item) + int(ch.get("orderBook", {}).get(str(item), 0))


# 用走 1 張: 背包先，冇就由冊扣
func _order_consume(ch: Dictionary, item: int) -> bool:
	if RulesShop.remove_item(ch["bag"], item, 1):
		return true
	var book: Dictionary = ch.get("orderBook", {})
	var k := int(book.get(str(item), 0))
	if k <= 0:
		return false
	if k == 1:
		book.erase(str(item))
	else:
		book[str(item)] = k - 1
	return true


func view_book() -> Array:
	var ch := player_ch()
	var out: Array = []
	var book: Dictionary = ch.get("orderBook", {})
	var ids: Array = book.keys()
	ids.sort_custom(func(a, b): return int(a) < int(b))
	for k in ids:
		out.append({"item": int(k), "name": String(data.names.get(int(k), k)), "n": int(book[k])})
	return out
