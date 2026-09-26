extends SceneTree
# S09e 測試 (spec 06 §9 / 09 §6): 結婚 — 御賜函/喜餅/開餅盒/分餅/禮堂/婚禮/婚戒召喚/配偶頁/叮嚀/離婚。
# 跑: Godot --headless --path client --script tests/run_marry.gd  (失敗 exit 1)

var fails := 0
var total := 0
var M: Dictionary = {}


func _init() -> void:
	var data := GameData.load_all()
	M = data.marry
	t_data(data)
	t_rules(data)
	t_items(data)
	t_propose(data)
	t_cake(data)
	t_share(data)
	t_wedding(data)
	t_summon(data)
	t_message_divorce(data)
	t_spouse_daily(data)
	t_view(data)
	t_roundtrip(data)
	t_old_save(data)
	t_determinism(data)
	print("[TEST] marry scenarios: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


func _at(sim: Sim, day: int, ke: int) -> void:
	var tpd := 1440 / int(sim.data.world["clock"]["gameMinPerTick"])
	sim.state["tick"] = day * tpd + int(ceil(ke * 15.0 / float(sim.data.world["clock"]["gameMinPerTick"]))) - 1
	sim.step()


func _new(data: GameData, cls: String = "yishi", seed: int = 200) -> Array:
	var sim := Sim.new(data, seed)
	var pid := sim.spawn_player("t", cls)
	var ch := sim.player_ch()
	var msgs: Array = []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "msg":
			msgs.append(String(ev["text"])))
	return [sim, pid, ch, msgs]


func _put(sim: Sim, id: int, x: int, y: int) -> void:
	var e := sim.ent(id)
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y
	e.erase("path")


# 設好一個玩家 + 同伴 (好感 95)，供流程測試
func _with_comp(data: GameData, cls: String = "yishi", seed: int = 201) -> Array:
	var r := _new(data, cls, seed)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	ch["level"] = 15
	_at(sim, 1, 40)
	var off: Dictionary = data.quest_npcs["marry_official"]
	_put(sim, pid, int(off["x"]), int(off["y"]))     # 結婚村 (NPC 已被 place() 轉全域座標)
	var pe := sim.ent(pid)
	var g: Dictionary = data.generals[0]
	var c: Dictionary = sim._spawn_companion(pe, g)
	if not ch.has("recruit"):
		ch["recruit"] = {}
	ch["recruit"]["comp"] = int(c["id"])
	c["gen"]["loyalty"] = 95
	return r


func _give(sim: Sim, pid: int, item: int, n: int = 1) -> void:
	sim.cmd_debug_give(pid, item, n)


# ================= 資料 =================

func t_data(data: GameData) -> void:
	check(not RulesMarry.cfg(M).is_empty(), "資料: marry.json cfg 載入")
	check(RulesMarry.affinity_lock(M) == 90, "資料: 好感鎖 90")
	check(RulesMarry.summon_sp(M) == 50, "資料: 召喚耗 50 SP")
	check(RulesMarry.divorce_gold(M) == 500000, "資料: 離婚 50 萬兩")
	check(RulesMarry.ring_item(M) == 23030, "資料: 婚戒 = 23030")
	check(int(RulesMarry.letters(M).get("M", 0)) == 51627, "資料: 男方御賜函 51627")
	check(int(RulesMarry.letters(M).get("F", 0)) == 51628, "資料: 女方御賜函 51628")
	check(RulesMarry.cakes(M).size() == 4, "資料: 4 款喜餅")
	var nt: Dictionary = data.marry.get("npcs", {})
	for role in ["baker", "box", "official", "divorce"]:
		check(data.quest_npcs.has(String(nt.get(role, ""))), "資料: NPC %s 存在" % role)
	var ids := {}
	for q in data.quests:
		ids[String(q["id"])] = q
	check(ids.has("marry_letter_m") and String(ids["marry_letter_m"]["type"]) == "marry", "資料: 男方御賜函任務")
	check(ids.has("marry_letter_f") and String(ids["marry_letter_f"]["type"]) == "marry", "資料: 女方御賜函任務")
	check(String(ids["marry_letter_m"]["giver"]) == "marry_official", "資料: 御賜函 giver = 朝廷官員")


func t_items(data: GameData) -> void:
	for c in RulesMarry.cakes(M):
		check(data.item_ids.has(int(c["buy"])), "道具: 喜餅 %d 存在" % int(c["buy"]))
		check(data.item_ids.has(int(c["open"])), "道具: 開餅 %d 存在" % int(c["open"]))
		for cc in c.get("contents", []):
			check(data.item_ids.has(int(cc[0])), "道具: 點心 %d 存在" % int(cc[0]))
			check(data.heals.has(int(cc[0])), "道具: 點心 %d 可回 HP/MP/SP" % int(cc[0]))


# ================= 純函數 =================

func t_rules(data: GameData) -> void:
	var chm := {"classId": "yishi"}
	var chf := {"classId": "shinu"}
	check(RulesMarry.gender_of(data, chm) == "M", "規則: 義士 = 男")
	check(RulesMarry.gender_of(data, chf) == "F", "規則: 仕女 = 女")
	check(RulesMarry.letter_for(M, "M") == 51627 and RulesMarry.letter_for(M, "F") == 51628, "規則: letter_for")
	check(RulesMarry.has_letter([{"id": 51627, "n": 1}], M, "M"), "規則: 有男方御賜函")
	check(not RulesMarry.has_letter([{"id": 51627, "n": 1}], M, "F"), "規則: 男方函唔算女方")
	check(RulesMarry.cake_tiers(M) == [1, 2, 3, 4], "規則: 4 個價位")
	check(RulesMarry.open_result(M, 51623) == 51619, "規則: 1000 喜餅 → 雙雙對對餅")
	check(RulesMarry.open_result(M, 51626) == 51622, "規則: 5000 喜餅 → 真愛不滅餅")
	var c1 := RulesMarry.contents(M, 51619)
	check(c1.size() == 2 and int(c1[0][0]) == 29106 and int(c1[1][1]) == 2, "規則: 雙雙對對餅內容")
	check(RulesMarry.cake_by_tier(M, 9).is_empty(), "規則: 冇嘅 tier = {}")
	# blocks
	var bag_m := [{"id": 51627, "n": 1}]
	var comp := {"gen": {"loyalty": 95}}
	var ch_ok := {"bag": bag_m, "marry": {}}
	check(RulesMarry.propose_block(M, ch_ok, comp, "M") == "", "規則: 求婚條件齊 = 得")
	check(RulesMarry.propose_block(M, {"bag": [], "marry": {}}, comp, "M") != "", "規則: 冇御賜函 = 唔得")
	check(RulesMarry.propose_block(M, ch_ok, {"gen": {"loyalty": 40}}, "M") != "", "規則: 好感唔夠 = 唔得")
	check(RulesMarry.propose_block(M, {"bag": bag_m, "marry": {"spouse": {"gid": 1}}}, comp, "M") != "", "規則: 已婚 = 唔得")
	var ch_eng := {"bag": bag_m, "marry": {"engaged": {"gid": 1}}}
	check(RulesMarry.book_block(M, ch_eng) == "", "規則: 訂親可預約")
	check(RulesMarry.hold_block(M, ch_eng) != "", "規則: 未預約唔可婚禮")
	check(RulesMarry.hold_block(M, {"marry": {"engaged": {"gid": 1}, "booked": {"day": 1}}}) == "", "規則: 已預約可婚禮")
	check(RulesMarry.divorce_block(M, {"marry": {"spouse": {"gid": 1}}}) == "", "規則: 已婚可離婚")
	check(RulesMarry.divorce_block(M, {"marry": {}}) != "", "規則: 未婚唔可離婚")
	check(RulesMarry.summon_block(M, {"marry": {"spouse": {"gid": 1}}, "bag": [{"id": 23030, "n": 1}]}, false) == "", "規則: 有戒可召喚")
	check(RulesMarry.summon_block(M, {"marry": {}}, true) != "", "規則: 未婚唔可召喚")


# ================= 求婚 =================

func t_propose(data: GameData) -> void:
	var r := _with_comp(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	sim.cmd_marry_propose(pid)
	check(String(sim.marry_view()["blocks"]["propose"]).contains("御賜函"), "求婚: 冇御賜函被拒")
	_give(sim, pid, 51627, 1)
	sim.cmd_marry_propose(pid)
	var mv := sim.marry_view()
	check(not (mv["engaged"] as Dictionary).is_empty(), "求婚: 成功訂親")
	var c := sim.ent(int(ch["recruit"]["comp"]))
	check(int(mv["engaged"]["gid"]) == int(c["gen"]["gid"]) and String(mv["engaged"]["name"]) == String(c["name"]), "求婚: 鎖定同伴")
	check(not RulesMarry.has_letter(ch["bag"], M, "M") == false, "求婚: 御賜函仍喺身 (唔消耗)")
	# 已婚唔可再求婚
	sim.cmd_marry_propose(pid)
	check(String(sim.marry_view()["blocks"]["propose"]).contains("訂"), "求婚: 已訂親被拒")


# ================= 喜餅 =================

func t_cake(data: GameData) -> void:
	var r := _with_comp(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	ch["gold"] = 100000
	_give(sim, pid, 51627, 1)
	sim.cmd_marry_propose(pid)
	# 買
	sim.cmd_marry_buy_cake(pid, 1)
	check(RulesShop.has_item(ch["bag"], 51623, 1), "喜餅: 買到 1000 喜餅")
	check(int(ch["gold"]) == 100000 - 1000, "喜餅: 扣錢")
	# 冇錢
	var ch2 := ch
	var before := int(ch2["gold"])
	ch2["gold"] = 0
	sim.cmd_marry_buy_cake(pid, 4)
	check(not RulesShop.has_item(ch2["bag"], 51626, 1), "喜餅: 冇錢買唔到")
	ch2["gold"] = before
	# 開餅盒 (要行近師傅)
	sim.cmd_marry_open_cake(pid, 51623)
	check(RulesShop.has_item(ch["bag"], 51619, 1) and not RulesShop.has_item(ch["bag"], 51623, 1), "喜餅: 開餅盒轉換")
	# 非喜餅唔開
	sim.cmd_marry_open_cake(pid, 51623)
	check(RulesShop.count_item(ch["bag"], 51619) == 1, "喜餅: 再開冇貨唔變")


# ================= 分餅 =================

func t_share(data: GameData) -> void:
	var r := _with_comp(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	sim.add_residents()
	ch["gold"] = 100000
	_give(sim, pid, 51627, 1)
	sim.cmd_marry_propose(pid)
	sim.cmd_marry_buy_cake(pid, 1)
	sim.cmd_marry_open_cake(pid, 51623)
	sim.cmd_marry_share_cake(pid, 51619)
	check(RulesShop.has_item(ch["bag"], 29106, 3), "分餅: 綠豆碰 ×3 入袋")
	check(RulesShop.has_item(ch["bag"], 29108, 2), "分餅: 鳳梨酥 ×2 入袋")
	check(not RulesShop.has_item(ch["bag"], 51619, 1), "分餅: 用咗開餅")
	# 居民好感 +10
	var found := 0
	var aff := 0
	for bid in sim.state["bots"]:
		var b := sim.ent(int(bid))
		if String(b.get("ch", {}).get("homeCity", "")) == "xuchang":
			found += 1
			aff = NpcMemory.affinity(b["mem"], pid)
			break
	check(found > 0 and aff == RulesMarry.share_affinity(M), "分餅: 同城居民好感 +10 (got %d)" % aff)
	var fest: Dictionary = sim.marry_view()["festive"]
	check(String(fest.get("city", "")) == "xuchang" and int(fest.get("until", 0)) > 1, "分餅: 婚慶氛圍 1 日")
	# 點心真係回得到 HP/MP/SP
	ch["hp"] = 1
	sim.cmd_use_item(pid, 29106)
	check(int(ch["hp"]) > 1, "分餅: 點心回 HP")


# ================= 婚禮 =================

func t_wedding(data: GameData) -> void:
	var r := _with_comp(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_give(sim, pid, 51627, 1)
	sim.cmd_marry_propose(pid)
	# 未預約唔可婚禮
	sim.cmd_marry_hold(pid)
	check((sim.marry_view()["spouse"] as Dictionary).is_empty(), "婚禮: 未預約冇配偶")
	sim.cmd_marry_book(pid)
	check(not (sim.marry_view()["booked"] as Dictionary).is_empty(), "婚禮: 預約成功")
	var c := sim.ent(int(ch["recruit"]["comp"]))
	sim.cmd_marry_hold(pid)
	var mv := sim.marry_view()
	check(not (mv["spouse"] as Dictionary).is_empty(), "婚禮: 有配偶")
	check(int(mv["spouse"]["gid"]) == int(c["gen"]["gid"]), "婚禮: 配偶 = 同伴 gid")
	check(bool(c["gen"].get("married", false)) and int(c["gen"]["until"]) == 0, "婚禮: 同伴變配偶唔期滿")
	check(int(c["gen"]["loyalty"]) >= RulesMarry.affinity_lock(M), "婚禮: 好感鎖 ≥90")
	check(RulesShop.has_item(ch["bag"], RulesMarry.ring_item(M), 1), "婚禮: 獲贈婚戒")
	check((mv["booked"] as Dictionary).is_empty() and (mv["engaged"] as Dictionary).is_empty(), "婚禮: 清預約/訂親")


# ================= 召喚 =================

func t_summon(data: GameData) -> void:
	var r := _with_comp(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_give(sim, pid, 51627, 1)
	sim.cmd_marry_propose(pid)
	sim.cmd_marry_book(pid)
	sim.cmd_marry_hold(pid)
	ch["sp"] = 500
	_put(sim, pid, 5, 5)                       # 行遠離伴侶
	sim.cmd_marry_summon(pid)
	check(int(ch["sp"]) == 450, "召喚: 扣 50 SP")
	var c := sim.ent(int(ch["recruit"]["comp"]))
	check(maxi(absi(int(c["x"]) - int(sim.ent(pid)["x"])), absi(int(c["y"]) - int(sim.ent(pid)["y"]))) <= 3, "召喚: 伴侶嚟到身邊")
	# SP 唔夠
	ch["sp"] = 10
	var px := int(c["x"])
	sim.cmd_marry_summon(pid)
	check(int(ch["sp"]) == 10 and int(c["x"]) == px, "召喚: SP 唔夠召喚唔到")
	# 同伴實體消失後可由武將表重生
	ch["sp"] = 500
	sim._remove_ent(int(c["id"]))
	sim.cmd_marry_summon(pid)
	check(not sim._spouse_ent(ch).is_empty(), "召喚: 實體唔見可重生")
	check(int(ch["sp"]) == 450, "召喚: 重生照扣 SP")


# ================= 叮嚀 / 離婚 =================

func t_message_divorce(data: GameData) -> void:
	var r := _with_comp(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_give(sim, pid, 51627, 1)
	sim.cmd_marry_propose(pid)
	sim.cmd_marry_book(pid)
	sim.cmd_marry_hold(pid)
	sim.cmd_marry_message(pid, "記得食飯，唔好打太多怪")
	check(String(sim.marry_view()["message"]) == "記得食飯，唔好打太多怪", "叮嚀: 留言存低")
	var long := "x".repeat(80)
	sim.cmd_marry_message(pid, long)
	check(String(sim.marry_view()["message"]).length() == RulesMarry.message_max_len(M), "叮嚀: 超長截斷")
	# 已婚同伴唔可以免職
	sim.cmd_companion_dismiss(pid)
	check(not sim._spouse_ent(ch).is_empty(), "離婚: 配偶唔可以就咁免職")
	# 錢唔夠
	ch["gold"] = 100
	sim.cmd_marry_divorce(pid)
	check(not (sim.marry_view()["spouse"] as Dictionary).is_empty(), "離婚: 錢唔夠唔離得")
	# 離婚
	ch["gold"] = 1000000
	var spouse_id := int(ch["marry"]["spouse"]["comp"])
	sim.cmd_marry_divorce(pid)
	var mv := sim.marry_view()
	check((mv["spouse"] as Dictionary).is_empty(), "離婚: 配偶頁清空")
	check(int(ch["gold"]) == 1000000 - 500000, "離婚: 扣 50 萬兩")
	check(not RulesShop.has_item(ch["bag"], RulesMarry.ring_item(M), 1), "離婚: 婚戒回收")
	check(String(mv["message"]) == "", "離婚: 叮嚀清空")
	check(sim.ent(spouse_id).is_empty(), "離婚: 伴侶實體離場")


# ================= 配偶唔會期滿 =================

func t_spouse_daily(data: GameData) -> void:
	var r := _with_comp(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_give(sim, pid, 51627, 1)
	sim.cmd_marry_propose(pid)
	sim.cmd_marry_book(pid)
	sim.cmd_marry_hold(pid)
	var c := sim._spouse_ent(ch)
	c["gen"]["loyalty"] = 5                        # 就算忠誠再低
	sim._recruit_daily(int(sim._clock()["day"]) + 3650)
	check(not sim._spouse_ent(ch).is_empty(), "配偶: 過期/低忠誠都唔會離開")


# ================= 讀取 =================

func t_view(data: GameData) -> void:
	var r := _with_comp(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var mv := sim.marry_view()
	check(String(mv["gender"]) == "M", "讀取: 性別")
	check(int(mv["affinityLock"]) == 90 and int(mv["summonSp"]) == 50, "讀取: 設定數值")
	check((mv["cakes"] as Array).size() == 4, "讀取: 婚禮頁 4 款餅")
	check(String(((mv["cakes"] as Array)[0] as Dictionary)["openName"]) != "", "讀取: 餅名")
	check(not bool(mv["hasLetter"]), "讀取: 未有御賜函")
	_give(sim, pid, 51627, 1)
	check(bool(sim.marry_view()["hasLetter"]), "讀取: 有御賜函")


# ================= 存檔 =================

func t_roundtrip(data: GameData) -> void:
	var r := _with_comp(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_give(sim, pid, 51627, 1)
	sim.cmd_marry_propose(pid)
	sim.cmd_marry_book(pid)
	sim.cmd_marry_hold(pid)
	sim.cmd_marry_message(pid, "同心")
	ch["gold"] = 900000
	var s1 := sim.save_string()
	var sim2: Sim = Sim.load_string(data, s1)
	check(s2_ok(sim2), "存檔: load 成功")
	var ch2 := sim2.player_ch()
	check(not (ch2.get("marry", {}).get("spouse", {}) as Dictionary).is_empty(), "存檔: 配偶保留")
	check(String(ch2["marry"]["message"]) == "同心", "存檔: 叮嚀保留")
	check(int(ch2["marry"]["spouse"]["gid"]) == int(ch["marry"]["spouse"]["gid"]), "存檔: 配偶 gid 一致")
	check(sim2.save_string() == s1, "存檔: save→load→save 一致")


func s2_ok(sim: Variant) -> bool:
	return sim != null


func t_old_save(data: GameData) -> void:
	# 舊存檔冇 marry 欄 → load 後自動補
	var r := _with_comp(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	ch.erase("marry")
	sim.state.erase("marry")
	var s := sim.save_string()
	var sim2: Sim = Sim.load_string(data, s)
	check(s2_ok(sim2), "舊存檔: load 成功")
	check(sim2.state.has("marry"), "舊存檔: state.marry 補返")
	sim2.marry_view()                                 # 惰性補 ch.marry
	check(sim2.player_ch().has("marry"), "舊存檔: ch.marry 惰性補返")
	sim2.cmd_marry_propose(int(pid))
	check(true, "舊存檔: 指令唔會 crash")


func t_determinism(data: GameData) -> void:
	var a := _run_seq(data, 301)
	var b := _run_seq(data, 301)
	check(a == b, "決定性: 同種子同結果")


func _run_seq(data: GameData, seed: int) -> String:
	var r := _with_comp(data, "yishi", seed)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	sim.add_residents()
	ch["gold"] = 100000
	_give(sim, pid, 51627, 1)
	sim.cmd_marry_propose(pid)
	sim.cmd_marry_buy_cake(pid, 1)
	sim.cmd_marry_open_cake(pid, 51623)
	sim.cmd_marry_share_cake(pid, 51619)
	sim.cmd_marry_book(pid)
	sim.cmd_marry_hold(pid)
	sim.cmd_marry_summon(pid)
	return sim.save_string()