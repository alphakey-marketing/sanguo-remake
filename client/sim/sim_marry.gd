extends "res://sim/sim_recruit.gd"
# Sim 繼承鏈: 結婚系統 (S09e, spec 06 §9 / 09 §6)
# 流程: 御賜函任務 (quests.json type=marry, 見 rules/quest.gd pre.gender) → 買喜餅 →
#      開餅盒 → 分餅 (點心回 HP/MP/SP) → 預約禮堂 + 主婚人 → 婚禮 → 婚戒 (無限召喚, 50 SP) →
#      配偶頁 / 叮嚀留言 / 離婚 (斷情絕愛郎 50 萬兩, 回收婚戒)。
# 對象 = 登用武將同伴 (ch.recruit.comp)。狀態: ch.marry = {engaged, booked, spouse, message}。
# UI (婚禮面板/配偶頁) 屬 relay 範圍外 → 只出 cmd_* 意圖 + marry_view() read-model。

const MARRY_WITNESS := WITNESS_RANGE


# ================= 狀態 =================
func _marry(m: Dictionary) -> Dictionary:
	return m


func _marry_state(ch: Dictionary) -> Dictionary:
	if not ch.has("marry") or not (ch["marry"] is Dictionary):
		ch["marry"] = {}
	var ms: Dictionary = ch["marry"]
	for k in ["engaged", "booked", "spouse"]:
		if not ms.has(k) or not (ms[k] is Dictionary):
			ms[k] = {}
	if not ms.has("message"):
		ms["message"] = ""
	return ms


# 舊存檔兼容: 補 state.marry (ch.marry 由 _marry_state 惰性補)
func _ensure_marry() -> void:
	_world_marry()


func _world_marry() -> Dictionary:
	if not state.has("marry") or not (state["marry"] is Dictionary):
		state["marry"] = {"festive": {}}
	var w: Dictionary = state["marry"]
	if not w.has("festive") or not (w["festive"] is Dictionary):
		w["festive"] = {}
	return w


func _marry_npc(npc_id: String) -> Dictionary:
	return data.quest_npcs.get(npc_id, {})


func _marry_near(e: Dictionary, npc_id: String) -> bool:
	var npc := _marry_npc(npc_id)
	if npc.is_empty():
		return false
	return _near(e, int(npc["x"]), int(npc["y"]))


func _marry_msg_near(id: int, npc_id: String) -> bool:
	var npc := _marry_npc(npc_id)
	if not _marry_near(ent(id), npc_id):
		_msg(id, "要行近%s先得" % npc.get("name", "NPC"))
		return false
	return true


func _marry_emit(id: int, kind: String, extra: Dictionary = {}) -> void:
	var ev := {"k": "marry", "dst": id, "kind": kind, "view": marry_view()}
	for k in extra:
		ev[k] = extra[k]
	_emit(ev)


func _year_days() -> int:
	var md := int(data.world.get("clock", {}).get("monthDays", 30))
	return maxi(1, md) * 12


# ================= 求婚 (spec 06 §9 步驟 1~2 前置) =================
# 有御賜函 + 同伴好感 ≥ affinitLock → 訂親 (鎖定對象 = 當前同伴)
func cmd_marry_propose(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var ms := _marry_state(ch)
	var comp := _companion_of(e)
	var gender := RulesMarry.gender_of(data, ch)
	var why := RulesMarry.propose_block(data.marry, ch, comp, gender)
	if why != "":
		return _msg(id, why)
	ms["engaged"] = {"gid": int(comp["gen"]["gid"]), "name": String(comp["name"]),
		"lv": int(comp["level"]), "since": int(_clock()["day"])}
	_msg(id, "你向%s求婚，%s點頭答應咗！" % [comp["name"], comp["name"]])
	_msg(id, "下一步：買喜餅 → 開餅盒 → 分送親友 → 預約禮堂。")
	_marry_emit(id, "propose", {"name": String(comp["name"])})


# ================= 喜餅 (spec 06 §9 步驟 2) =================
func cmd_marry_buy_cake(id: int, tier: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	if not _marry_msg_near(id, String(data.marry.get("npcs", {}).get("baker", ""))):
		return
	var cake := RulesMarry.cake_by_tier(data.marry, tier)
	if cake.is_empty():
		return _msg(id, "冇呢款喜餅")
	var price := int(cake["price"])
	var ch: Dictionary = e["ch"]
	if int(ch["gold"]) < price:
		return _msg(id, "唔夠錢（要 %d 兩）" % price)
	ch["gold"] = int(ch["gold"]) - price
	RulesShop.add_item(ch["bag"], int(cake["buy"]), 1)
	_msg(id, "買咗 %s（%d 兩）" % [data.names.get(int(cake["buy"]), "喜餅"), price])
	_marry_emit(id, "buy_cake", {"tier": tier, "item": int(cake["buy"])})


# 開餅盒: 喜餅 → 對應喜餅（雙雙對對餅等）
func cmd_marry_open_cake(id: int, buy_item: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	if not _marry_msg_near(id, String(data.marry.get("npcs", {}).get("box", ""))):
		return
	var cake := RulesMarry.cake_by_buy(data.marry, buy_item)
	if cake.is_empty():
		return _msg(id, "呢件唔係喜餅")
	var ch: Dictionary = e["ch"]
	if not RulesShop.remove_item(ch["bag"], buy_item, 1):
		return _msg(id, "背包冇呢件喜餅")
	var open_id := int(cake["open"])
	RulesShop.add_item(ch["bag"], open_id, 1)
	_msg(id, "開餅盒師傅打開餅盒，變成 %s！" % data.names.get(open_id, "喜餅"))
	_marry_emit(id, "open_cake", {"buy": buy_item, "open": open_id})


# 分送親友: 開喜餅 → 點心入袋 (回 HP/MP/SP) + 全城居民好感 +10 (婚慶氛圍 1 日)
func cmd_marry_share_cake(id: int, open_item: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var ms := _marry_state(ch)
	if (ms.get("engaged", {}) as Dictionary).is_empty() and (ms.get("spouse", {}) as Dictionary).is_empty():
		return _msg(id, "要先向同伴求婚先分得喜餅")
	var contents := RulesMarry.contents(data.marry, open_item)
	if contents.is_empty():
		return _msg(id, "呢件唔係開好嘅喜餅")
	if not RulesShop.remove_item(ch["bag"], open_item, 1):
		return _msg(id, "背包冇呢件喜餅")
	var names: Array = []
	for c in contents:
		RulesShop.add_item(ch["bag"], int(c[0]), int(c[1]))
		names.append("%s×%d" % [data.names.get(int(c[0]), str(c[0])), int(c[1])])
	var city := city_id_at(int(e["x"]), int(e["y"]))
	var gain := RulesMarry.share_affinity(data.marry)
	var n := _spread_festive(int(e["id"]), city, gain)
	var w := _world_marry()
	w["festive"] = {"city": city, "until": int(_clock()["day"]) + RulesMarry.festive_days(data.marry)}
	_msg(id, "分咗%s，%d 位居民對你好感 +%d" % [", ".join(names), n, gain])
	_marry_emit(id, "share_cake", {"item": open_item, "residents": n, "contents": contents})


# 同城居民好感提升 (分餅/婚慶) + 落婚慶氛圍; 回傳受惠居民數
func _spread_festive(_pid: int, city: String, gain: int) -> int:
	if city == "":
		return 0
	var n := 0
	for bid in state.get("bots", []):
		var b := ent(int(bid))
		if b.is_empty() or not b.has("mem"):
			continue
		if String(b.get("ch", {}).get("homeCity", "")) != city:
			continue
		NpcMemory.witness(b["mem"], _pid, "festive", tick, gain)
		n += 1
	return n


# ================= 禮堂 / 婚禮 (spec 06 §9 步驟 3~4) =================
# 預約禮堂 + 主婚人 (朝廷官員 NPC)
func cmd_marry_book(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	if not _marry_msg_near(id, String(data.marry.get("npcs", {}).get("official", ""))):
		return
	var ch: Dictionary = e["ch"]
	var why := RulesMarry.book_block(data.marry, ch)
	if why != "":
		return _msg(id, why)
	var ms := _marry_state(ch)
	var day := int(_clock()["day"])
	ms["booked"] = {"day": day, "official": String(data.marry.get("npcs", {}).get("official", ""))}
	_msg(id, "朝廷官員應承做主婚人，婚禮預約咗。")
	_marry_emit(id, "book", {"day": day})


# 舉行婚禮: 送婚戒 + 結為夫妻 (配偶好感鎖)
func cmd_marry_hold(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	if not _marry_msg_near(id, String(data.marry.get("npcs", {}).get("official", ""))):
		return
	var ch: Dictionary = e["ch"]
	var why := RulesMarry.hold_block(data.marry, ch)
	if why != "":
		return _msg(id, why)
	var comp := _companion_of(e)
	if comp.is_empty():
		return _msg(id, "同伴唔喺度，婚禮搞唔成")
	var ms := _marry_state(ch)
	var day := int(_clock()["day"])
	var gid := int(comp["gen"]["gid"])
	ms["spouse"] = {"gid": gid, "name": String(comp["name"]), "lv": int(comp["level"]),
		"classId": String(comp["ch"].get("classId", "")), "ideo": String(comp["ch"].get("ideology", "")),
		"karma": int(comp["ch"].get("karma", 0)), "birthMonth": int(comp["ch"].get("birthMonth", 1)),
		"birthDay": int(comp["ch"].get("birthDay", 1)), "day": day,
		"official": String(data.marry.get("npcs", {}).get("official", "")), "comp": int(comp["id"])}
	ms["engaged"] = {}
	ms["booked"] = {}
	comp["gen"]["married"] = true
	comp["gen"]["until"] = 0                      # 配偶唔會登用期滿
	comp["gen"]["loyalty"] = maxi(int(comp["gen"]["loyalty"]), RulesMarry.affinity_lock(data.marry))
	var ring := RulesMarry.ring_item(data.marry)
	if ring != 0 and RulesShop.count_item(ch["bag"], ring) <= 0:
		RulesShop.add_item(ch["bag"], ring, 1)
	_msg(id, "禮成！你同%s結為夫妻，獲贈婚戒（無限召喚，耗 %d SP）。" % [comp["name"], RulesMarry.summon_sp(data.marry)])
	_marry_emit(id, "hold", {"gid": gid, "ring": ring})


# ================= 婚戒召喚 (spec 06 §9 步驟 5) =================
# 無限召喚伴侶到身邊，每次耗 50 SP
func cmd_marry_summon(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var ms := _marry_state(ch)
	var spouse: Dictionary = ms.get("spouse", {})
	if spouse.is_empty():
		return _msg(id, "你未結婚")
	var comp := _spouse_ent(ch)
	var why := RulesMarry.summon_block(data.marry, ch, not comp.is_empty())
	if why != "":
		return _msg(id, why)
	var cost := RulesMarry.summon_sp(data.marry)
	if int(ch["sp"]) < cost:
		return _msg(id, "SP 唔夠（要 %d）" % cost)
	ch["sp"] = int(ch["sp"]) - cost
	if comp.is_empty():
		comp = _spawn_spouse(e, ch)
		if comp.is_empty():
			ch["sp"] = int(ch["sp"]) + cost      # 召喚失敗退 SP
			return _msg(id, "搵唔到伴侶")
	var p := _free_near(int(e["x"]), int(e["y"]))
	_put_ent(comp, p.x, p.y)
	_sync_stats(e)
	_msg(id, "%s應召嚟到你身邊（SP −%d）" % [comp["name"], cost])
	_marry_emit(id, "summon", {"gid": int(spouse["gid"])})


# 配偶實體 (由 ch.marry.spouse.comp 搵; 冇 = {})
func _spouse_ent(ch: Dictionary) -> Dictionary:
	var sp: Dictionary = _marry_state(ch).get("spouse", {})
	var c := ent(int(sp.get("comp", 0)))
	if c.is_empty() or not c.has("gen"):
		return {}
	return c


# 配偶實體唔見咗 (被免職/離場) → 由武將表重新生成
func _spawn_spouse(pe: Dictionary, ch: Dictionary) -> Dictionary:
	var sp: Dictionary = _marry_state(ch).get("spouse", {})
	var g: Dictionary = data.general_by_id.get(int(sp.get("gid", 0)), {})
	if g.is_empty():
		return {}
	var c := _spawn_companion(pe, g)
	c["gen"]["married"] = true
	c["gen"]["until"] = 0
	c["gen"]["loyalty"] = maxi(int(c["gen"]["loyalty"]), RulesMarry.affinity_lock(data.marry))
	_gen_state(int(g["id"]))["serving"] = true
	ch["marry"]["spouse"]["comp"] = int(c["id"])
	return c


# 免職配偶: 已婚同伴唔可以就咁打發，要離婚先 (override sim_recruit.cmd_companion_dismiss)
func cmd_companion_dismiss(id: int) -> void:
	var c := _companion_of(ent(id))
	if not c.is_empty() and bool(c["gen"].get("married", false)):
		return _msg(id, "配偶唔可以就咁打發走，要去搵斷情絕愛郎離婚先")
	super(id)


# ================= 配偶頁 / 叮嚀留言 / 離婚 (spec 09 §6) =================
func cmd_marry_message(id: int, text: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ms := _marry_state(e["ch"])
	if (ms.get("spouse", {}) as Dictionary).is_empty():
		return _msg(id, "你未結婚")
	var t := text.strip_edges().substr(0, RulesMarry.message_max_len(data.marry))
	ms["message"] = t
	_msg(id, "留咗俾另一半嘅叮嚀：「%s」" % t)
	_marry_emit(id, "message", {})


# 離婚: 斷情絕愛郎, 50 萬兩, 回收婚戒, 配偶頁消失
func cmd_marry_divorce(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	if not _marry_msg_near(id, String(data.marry.get("npcs", {}).get("divorce", ""))):
		return
	var ch: Dictionary = e["ch"]
	var ms := _marry_state(ch)
	var why := RulesMarry.divorce_block(data.marry, ch)
	if why != "":
		return _msg(id, why)
	var cost := RulesMarry.divorce_gold(data.marry)
	if int(ch["gold"]) < cost:
		return _msg(id, "唔夠錢（離婚要 %d 兩）" % cost)
	ch["gold"] = int(ch["gold"]) - cost
	var comp := _spouse_ent(ch)
	if not comp.is_empty():
		_companion_leave(comp, "離婚", false)
	var ring := RulesMarry.ring_item(data.marry)
	if ring != 0:
		var have := RulesShop.count_item(ch["bag"], ring)
		if have > 0:
			RulesShop.remove_item(ch["bag"], ring, have)     # 婚戒回收
	ms["spouse"] = {}
	ms["message"] = ""
	_msg(id, "斷情絕愛郎搖搖頭，你嘅婚姻到此為止（婚戒回收，−%d 兩）。" % cost)
	_marry_emit(id, "divorce", {})


# ================= 讀取 (UI 配偶頁用) =================
func marry_view() -> Dictionary:
	var e := ent(int(state["player_id"]))
	if e.is_empty() or not e.has("ch"):
		return {}
	var ch: Dictionary = e["ch"]
	var ms := _marry_state(ch)
	var gender := RulesMarry.gender_of(data, ch)
	var lock := RulesMarry.affinity_lock(data.marry)
	var comp := _companion_of(e)
	var cakes: Array = []
	for c in RulesMarry.cakes(data.marry):
		var cons: Array = []
		for cc in c.get("contents", []):
			cons.append({"id": int(cc[0]), "n": int(cc[1]), "name": data.names.get(int(cc[0]), "")})
		cakes.append({"tier": int(c["tier"]), "buy": int(c["buy"]), "buyName": data.names.get(int(c["buy"]), ""),
			"price": int(c["price"]), "open": int(c["open"]), "openName": data.names.get(int(c["open"]), ""), "contents": cons})
	var spouse: Dictionary = ms.get("spouse", {})
	var out := {
		"gender": gender,
		"letter": RulesMarry.letter_for(data.marry, gender),
		"hasLetter": RulesMarry.has_letter(ch.get("bag", []), data.marry, gender),
		"affinityLock": lock, "summonSp": RulesMarry.summon_sp(data.marry),
		"divorceGold": RulesMarry.divorce_gold(data.marry), "ringItem": RulesMarry.ring_item(data.marry),
		"hasRing": RulesMarry.has_ring(ch.get("bag", []), data.marry),
		"engaged": ms.get("engaged", {}), "booked": ms.get("booked", {}),
		"spouse": {}, "message": String(ms.get("message", "")),
		"cakes": cakes,
		"festive": (_world_marry().get("festive", {}) as Dictionary),
		"blocks": {
			"propose": RulesMarry.propose_block(data.marry, ch, comp, gender),
			"book": RulesMarry.book_block(data.marry, ch),
			"hold": RulesMarry.hold_block(data.marry, ch),
			"divorce": RulesMarry.divorce_block(data.marry, ch),
			"summon": RulesMarry.summon_block(data.marry, ch, not comp.is_empty() and bool(comp["gen"].get("married", false))),
		},
	}
	if not spouse.is_empty():
		var years := 0
		var married_day := int(spouse.get("day", 0))
		if married_day > 0:
			years = maxi(0, (int(_clock()["day"]) - married_day) / _year_days())
		out["spouse"] = {"gid": int(spouse.get("gid", 0)), "name": String(spouse.get("name", "")),
			"lv": int(spouse.get("lv", 0)), "classId": String(spouse.get("classId", "")),
			"ideo": String(spouse.get("ideo", "")), "karma": int(spouse.get("karma", 0)),
			"birthMonth": int(spouse.get("birthMonth", 1)), "birthDay": int(spouse.get("birthDay", 1)),
			"day": married_day, "years": years, "official": String(spouse.get("official", "")),
			"present": not _spouse_ent(ch).is_empty()}
	return out