extends SceneTree
# 歷史任務 + 居民委託 + 武將收集冊測試 (Step 16, spec 06 §4):
# 資料驗證 / 純函數 (pre.attr、takeItems、questOnly/strictWindow、委託出單) / 6 條歷史任務全線 /
# 門禁 (監獄時辰、丁府鑰匙) / 安全區 PK / 收集冊 + 登用 / 4 種委託 / 過期 / 存檔 roundtrip / 決定性
# 跑: Godot --headless --path client --script tests/run_hist.gd   (失敗 exit 1)

var fails := 0
var total := 0

const ORDERS := {"hist_sunjian": 62093, "hist_yudu": 62092, "hist_chengong": 62094,
	"hist_yuanshao": 62097, "hist_dongzhuo": 62073, "hist_dingyuan": 62072, "hist_longzhong": 62246}


func _init() -> void:
	var data := GameData.load_all()
	t_validate(data)
	t_pure(data)
	t_sunjian(data)
	t_yudu(data)
	# t_chengong 封存: 監獄門禁測試用舊襄陽圖 (data/archive)
	t_yuanshao(data)
	t_gate_f4(data)
	t_dongzhuo(data)
	t_dingyuan(data)
	t_book(data)
	t_comm_offer(data)
	t_comm_hunt_collect(data)
	t_comm_deliver_repair(data)
	t_comm_limits(data)
	t_roundtrip(data)
	t_determinism(data)
	print("[TEST] hist: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


# ---------- helpers ----------
func _new(data: GameData, seed: int, lv: int = 12) -> Array:
	var sim := Sim.new(data, seed)
	var id := sim.spawn_player("t")
	var ch: Dictionary = sim.player_ch()
	ch["level"] = lv
	sim._sync_quest_npcs()
	return [sim, id, ch]


func _put(sim: Sim, id: int, x: int, y: int) -> void:
	var e := sim.ent(id)
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y
	e.erase("path")


func _talk(sim: Sim, id: int, npc_id: String) -> void:
	var n: Dictionary = sim.data.quest_npcs[npc_id]
	_put(sim, id, int(n["x"]) + 1, int(n["y"]))
	sim.cmd_quest_talk(id, npc_id)


# 去到第 day 日 ke 刻 (會行一次 step → 時鐘/日結/NPC 可見性更新)
func _at(sim: Sim, day: int, ke: int) -> void:
	var tpd := 1440 / int(sim.data.world["clock"]["gameMinPerTick"])
	sim.state["tick"] = day * tpd + int(ceil(ke * 15.0 / float(sim.data.world["clock"]["gameMinPerTick"]))) - 1
	sim.step()


func _n(ch: Dictionary, item: int) -> int:
	return RulesShop.count_item(ch["bag"], item)


func _stage(ch: Dictionary, qid: String) -> int:
	return int(ch.get("quests", {}).get(qid, {}).get("stage", -1))


func _done(ch: Dictionary, qid: String) -> bool:
	return bool(ch.get("questDone", {}).get(qid, false))


func _vis(sim: Sim, npc: String) -> bool:
	return bool(sim.state["quest_npcs"].get(npc, {}).get("visible", false))


func _boss(sim: Sim, qid: String) -> Dictionary:
	for e in sim.ents.values():
		if e["kind"] == "mob" and str(e.get("mob", {}).get("quest_boss", "")) == qid:
			return e
	return {}


# 行近 npc 對話 → 召喚 boss → 直接打死
func _fight(sim: Sim, id: int, npc: String, qid: String) -> bool:
	_talk(sim, id, npc)
	var b := _boss(sim, qid)
	if b.is_empty():
		return false
	sim._kill_mob(b, sim.ent(id))
	return true


func _portal(sim: Sim, pid: String) -> Dictionary:
	return sim.travel_point_by_id(pid)


func _map_of(sim: Sim, id: int) -> String:
	var e := sim.ent(id)
	return sim.map_id_at(int(e["x"]), int(e["y"]))


# ---------- 資料驗證 ----------
func t_validate(data: GameData) -> void:
	var errs := RulesQuest.validate(data)
	check(errs.is_empty(), "quests/quest_npcs 驗證 (errors: %s)" % str(errs))
	var e2 := RulesCommission.validate(data)
	check(e2.is_empty(), "commissions 驗證 (errors: %s)" % str(e2))
	var hist := data.quests.filter(func(q): return String(q["type"]) == "history" and String(q.get("src", "")) != "orig")
	check(hist.size() == 9, "歷史任務 9 條 (不計 src=orig 原版導入；S06b 加齊 5 條：孫堅匿璽/張公公謀害何進/黃蓋/曹阿瞞/討伐張角) (而家 %d)" % hist.size())
	for q in hist:
		if ORDERS.has(String(q["id"])):      # 只有首批 7 條有將軍令獎勵
			var items: Array = (q["reward"]["items"] as Array).map(func(x): return int(x[0]))
			check(items.has(int(ORDERS[String(q["id"])])), "%s 獎勵有將軍令" % q["id"])
			check(String(data.names.get(int(ORDERS[String(q["id"])]), "")).ends_with("將軍令"), "%s 將軍令 item 名啱" % q["id"])
		var n: Dictionary = data.quest_npcs[String(q["giver"])]
		check(data.map_by_id.has(String(n["map"])), "%s giver 喺已有地圖" % q["id"])
	for nid in ["huyu", "yudu", "dingyuan", "prison_clerk", "caocao_pr"]:
		check(bool(data.quest_npcs[nid].get("questOnly", false)), "%s = questOnly" % nid)
	for mid in [1012, 1013, 1014]:
		check(data.monsters.has(mid) and (data.monsters[mid]["drops"] as Array).is_empty(), "boss %d 存在 + 冇掉落" % mid)
	# 壞數據報錯
	var bad := GameData.new()
	bad.quests = [{"id": "q", "type": "history", "pre": {"attr": {"luck": 3}},
		"stages": [{"type": "talk", "npc": "x", "takeItems": [[999999, 1]]}, {"type": "fight", "npc": "x", "monster": 424242, "done": true}]}]
	bad.quest_npc_list = []
	var e3 := RulesQuest.validate(bad)
	var joined := " ".join(e3)
	check(joined.contains("takeItems") and joined.contains("fight monster") and joined.contains("pre.attr"), "壞 takeItems/monster/attr 報錯: %s" % joined)


# ---------- 純函數 ----------
func t_pure(data: GameData) -> void:
	var ch := RulesStats.create_character(data, "t", "yishi")
	var qy := {"id": "x", "pre": {"attr": {"cha": 10}}}
	ch["attrs"]["cha"] = 9
	check(not RulesQuest.pre_ok(data, qy, ch), "pre.attr: 魅力 9 < 10 唔得")
	ch["attrs"]["cha"] = 10
	check(RulesQuest.pre_ok(data, qy, ch), "pre.attr: 魅力 10 得")
	# questOnly: 平時唔見；任務要佢先見
	var huyu: Dictionary = data.quest_npcs["huyu"]
	ch["level"] = 12
	check(not RulesQuest.npc_visible(huyu, ch, 40), "questOnly: 平時唔見")
	check(not RulesQuest.npc_shown(huyu, ch, 40, data.quests), "questOnly: 冇任務唔顯示")
	ch["quests"] = {"hist_sunjian": {"stage": 1, "flags": {}}}
	check(RulesQuest.npc_shown(huyu, ch, 40, data.quests), "questOnly: 任務 fight stage 顯示")
	# strictWindow: 任務要佢都要守時辰
	var dz: Dictionary = data.quest_npcs["dongzhuo"]
	ch["quests"] = {"hist_dongzhuo": {"stage": 1, "flags": {}}}
	check(RulesQuest.npc_shown(dz, ch, 40, data.quests), "董卓: 午時 (ke 40) 見到")
	check(not RulesQuest.npc_shown(dz, ch, 10, data.quests), "董卓: 丑時 (ke 10) 任務進行中都唔見 (strictWindow)")
	check(RulesQuest.npc_shown(data.quest_npcs["stray_dog"], {"level": 1, "quests": {"newbie_dog": {"stage": 0}}}, 40, data.quests),
		"舊行為: 非 strict NPC 任務進行中照常駐")
	# takeItems: 唔齊唔推進、唔扣；齊就扣
	var q := {"id": "tq", "type": "history", "giver": "sunjian", "stages": [
		{"type": "talk", "npc": "sunjian", "takeItems": [[56037, 1], [56035, 1]], "done": true}], "reward": {"fame": 5}}
	var c2 := RulesStats.create_character(data, "t", "yishi")
	c2["fame"] = 0
	RulesShop.add_item(c2["bag"], 56037, 1)
	var r := RulesQuest.on_npc_talk(data, c2, q, "sunjian", 0)
	check(not bool(r["done"]) and _n(c2, 56037) == 1, "takeItems 唔齊: 唔完成、唔扣")
	check(String(r["msg"]).contains("殺人滅口函"), "takeItems 唔齊: 提示缺咩 (%s)" % r["msg"])
	RulesShop.add_item(c2["bag"], 56035, 1)
	r = RulesQuest.on_npc_talk(data, c2, q, "sunjian", 0)
	check(bool(r["done"]) and _n(c2, 56037) == 0 and _n(c2, 56035) == 0, "takeItems 齊: 完成 + 扣晒")
	check(int(c2["fame"]) == 5, "reward fame")
	# polExp reward: 同官令一樣換算
	var c3 := RulesStats.create_character(data, "t", "yishi")
	var pol0 := int(c3["attrs"]["pol"])
	var per := int(data.office["polExpPerPoint"])
	RulesQuest.apply_reward(data, c3, {"polExp": per})
	check(int(c3["attrs"]["pol"]) == pol0 + 1 and int(c3.get("polExp", 0)) == 0, "polExp %d = 政治 +1" % per)
	RulesQuest.apply_reward(data, c3, {"polExp": 3})
	check(int(c3["polExp"]) == 3, "polExp 零頭保留")


# ---------- 少年孫堅打海賊 (全線) ----------
func t_sunjian(data: GameData) -> void:
	var r := _new(data, 101, 9)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var fame0 := int(ch.get("fame", 0))
	_talk(sim, id, "sunjian")
	check(_stage(ch, "hist_sunjian") == -1, "孫堅: 9 級接唔到 (武功 10+)")
	ch["level"] = 10
	check(not _vis(sim, "huyu"), "胡玉: 未接任務唔見")
	_talk(sim, id, "sunjian")
	check(_stage(ch, "hist_sunjian") == 1 and _n(ch, 56037) == 1, "孫堅: 接任務得孫堅請託信")
	check(_vis(sim, "huyu"), "胡玉: 任務進行中出現")
	_talk(sim, id, "sunjian")
	check(_stage(ch, "hist_sunjian") == 1, "孫堅: 未打胡玉再傾唔推進")
	check(_fight(sim, id, "huyu", "hist_sunjian"), "胡玉: 對話召喚 boss")
	check(_n(ch, 56035) == 1 and _stage(ch, "hist_sunjian") == 2, "打贏胡玉: 得殺人滅口函")
	check(_boss(sim, "hist_sunjian").is_empty(), "boss 死咗唔重生")
	_talk(sim, id, "sunjian")
	check(_done(ch, "hist_sunjian"), "孫堅任務完成")
	check(_n(ch, 62093) == 1 and _n(ch, 23053) == 1 and _n(ch, 32106) == 1 and _n(ch, 29017) == 5,
		"孫堅獎勵: 將軍令 + 迷情戒指 + 三界之石 + 戰國七雄×5")
	check(int(ch["fame"]) == fame0 + 30, "孫堅獎勵: 名聲 +30")
	check(_n(ch, 56037) == 0 and _n(ch, 56035) == 0, "信物收返")
	check(not _vis(sim, "huyu"), "完成後胡玉消失")
	_talk(sim, id, "sunjian")
	check(_n(ch, 62093) == 1, "完成咗唔可以重接")


# ---------- 聲東擊西退于毒 ----------
func t_yudu(data: GameData) -> void:
	var r := _new(data, 102)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	_talk(sim, id, "wanggong")
	check(_n(ch, 56041) == 1, "王肱: 得求救信")
	_talk(sim, id, "yudu")
	check(_boss(sim, "hist_yudu").is_empty(), "未得出兵令: 于毒唔會開打")
	RulesShop.remove_item(ch["bag"], 56041, 1)
	_talk(sim, id, "caocao_cl")
	check(_stage(ch, "hist_yudu") == 1, "曹操: 冇求救信唔推進")
	RulesShop.add_item(ch["bag"], 56041, 1)
	_talk(sim, id, "caocao_cl")
	check(_stage(ch, "hist_yudu") == 2 and _n(ch, 56042) == 1 and _n(ch, 56041) == 0, "曹操: 收求救信、得代征出兵令")
	RulesShop.remove_item(ch["bag"], 56042, 1)
	_talk(sim, id, "yudu")
	check(_boss(sim, "hist_yudu").is_empty(), "冇出兵令: 開唔到戰")
	RulesShop.add_item(ch["bag"], 56042, 1)
	check(_fight(sim, id, "yudu", "hist_yudu"), "于毒: 帶出兵令開戰")
	check(_done(ch, "hist_yudu") and _n(ch, 56042) == 0, "打贏于毒: 完成 + 收出兵令")
	check(_n(ch, 62092) == 1 and _n(ch, 32111) == 1 and _n(ch, 23058) == 1 and _n(ch, 24005) == 1 and _n(ch, 29017) == 10,
		"于毒獎勵: 曹操將軍令 + 泉源之石 + 伏魔戒指/項鍊 + 戰國七雄×10")


# ---------- 搶救曹操 (監獄子~丑時門禁) ----------
func t_chengong(data: GameData) -> void:
	var r := _new(data, 103)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var pol0 := int(ch["attrs"]["pol"])
	var pe0 := int(ch.get("polExp", 0))
	_at(sim, 0, 40)
	_talk(sim, id, "chengong")
	check(_n(ch, 56046) == 1, "陳宮: 得縣官令")
	var door := _portal(sim, "xyc_prison")
	_put(sim, id, int(door["x"]), int(door["y"]))
	sim.cmd_travel(id, "xyc_prison")
	check(_map_of(sim, id) == "xiangyang", "午時: 入唔到監獄")
	_at(sim, 1, 4)
	_put(sim, id, int(door["x"]), int(door["y"]))
	sim.cmd_travel(id, "xyc_prison")
	check(_map_of(sim, id) == "xy_prison", "子時: 潛入監獄")
	check(_vis(sim, "prison_clerk"), "獄吏: 任務進行中出現")
	_talk(sim, id, "prison_clerk")
	check(_n(ch, 56047) == 1 and _n(ch, 56046) == 0, "獄吏: 收縣官令、得襄陽通行令")
	check(_vis(sim, "caocao_pr"), "子時: 獄中曹操見到")
	_at(sim, 1, 40)
	check(not _vis(sim, "caocao_pr"), "午時: 獄中曹操唔見 (strictWindow)")
	_talk(sim, id, "caocao_pr")
	check(not _done(ch, "hist_chengong"), "唔見嘅 NPC 傾唔到")
	var out := _portal(sim, "pr_door")
	_put(sim, id, int(out["x"]), int(out["y"]))
	sim.cmd_travel(id, "pr_door")
	check(_map_of(sim, id) == "xiangyang", "監獄出嚟唔使守時辰")
	_at(sim, 2, 12)
	_talk(sim, id, "caocao_pr")
	check(_done(ch, "hist_chengong") and _n(ch, 62094) == 1 and _n(ch, 56047) == 0, "丑時救出曹操: 完成 + 陳宮將軍令")
	var per := int(data.office["polExpPerPoint"])
	check(int(ch["attrs"]["pol"]) * per + int(ch["polExp"]) == pol0 * per + pe0 + 20, "陳宮獎勵: 政治經驗 +20")


# ---------- 袁紹義助王允 (魅力 10+) ----------
# F4: 高階歷史任務門檻 (等級/政治/魅力 各 10+)，未達標唔接、傾偈提示差乜
func t_gate_f4(data: GameData) -> void:
	var q := {}
	for x in data.quests:
		if String(x["id"]) == "hist_longzhong":
			q = x
	check(not q.is_empty(), "F4: hist_longzhong 存在")
	var ch := {"level": 9, "attrs": {"pol": 5, "cha": 5}, "quests": {}, "questDone": {}}
	var h := RulesQuest.gate_hint(q, ch)
	check(h.contains("等級 10") and h.contains("政治 10") and h.contains("魅力 10"), "F4: 提示列出未達等級/政治/魅力 (%s)" % h)
	check(not RulesQuest.pre_ok(data, q, ch), "F4: 未達標 pre 唔過")
	var res := RulesQuest.on_npc_talk(data, ch, q, String(q["giver"]), 1)
	check(bool(res.get("blocked", false)) and String(res["msg"]) == h, "F4: 傾偈被擋並提示")
	check(not (ch["quests"] as Dictionary).has("hist_longzhong"), "F4: 未達標冇接任務")
	ch = {"level": 10, "attrs": {"pol": 10, "cha": 10}, "quests": {}, "questDone": {}}
	check(RulesQuest.gate_hint(q, ch) == "" and RulesQuest.pre_ok(data, q, ch), "F4: 達標 = 無提示可接")
	var zj := {}
	for x in data.quests:
		if String(x["id"]) == "orig_zhangjiao":
			zj = x
	check(int(zj["pre"]["workLv"]["herbalism"]) >= 10, "F4: 討伐張角 有採藥 10 級門檻")
	var cz := {"level": 20, "attrs": {"pol": 10, "cha": 10}, "quests": {}, "questDone": {}}
	check(not RulesQuest.pre_ok(data, zj, cz) and RulesQuest.gate_hint(zj, cz).contains("採藥 10"), "討伐張角: 採藥未 10 級擋住 + 提示")
	cz["workLv"] = {"herbalism": {"lv": 10}}
	check(RulesQuest.pre_ok(data, zj, cz), "討伐張角: 採藥 10 級可接")
	check(int(zj["pre"]["attr"]["pol"]) >= 10 and int(zj["pre"]["attr"]["cha"]) >= 10 and int(zj["pre"]["minLevel"]) >= 10, "F4: 太平要術(討伐張角) 門檻 政治/魅力/等級 ≥10")


func t_yuanshao(data: GameData) -> void:
	var r := _new(data, 104)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	ch["attrs"]["cha"] = 9
	_talk(sim, id, "yuanshao")
	check(_stage(ch, "hist_yuanshao") == -1, "袁紹: 魅力 9 接唔到")
	ch["attrs"]["cha"] = 10
	_talk(sim, id, "yuanshao")
	check(_n(ch, 56056) == 1, "袁紹: 得助兵令")
	_talk(sim, id, "wangyun")
	check(_done(ch, "hist_yuanshao") and _n(ch, 62097) == 1 and _n(ch, 56056) == 0, "王允: 完成 + 袁紹將軍令")


# ---------- 董卓初登場 (魅力 5+、卯~酉時) ----------
func t_dongzhuo(data: GameData) -> void:
	var r := _new(data, 105)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	ch["attrs"]["cha"] = 5
	_at(sim, 0, 40)
	_talk(sim, id, "liru")
	check(_n(ch, 56059) == 1, "李儒: 得保駕密令牌")
	_at(sim, 1, 8)
	check(not _vis(sim, "dongzhuo"), "丑時: 董卓唔喺度")
	_talk(sim, id, "dongzhuo")
	check(not _done(ch, "hist_dongzhuo"), "丑時交唔到")
	_at(sim, 1, 30)
	check(_vis(sim, "dongzhuo"), "卯時: 董卓出現")
	_talk(sim, id, "dongzhuo")
	check(_done(ch, "hist_dongzhuo") and _n(ch, 62073) == 1 and _n(ch, 56059) == 0, "董卓: 完成 + 董卓將軍令")


# ---------- 代呂布斬丁原 (丁府鑰匙門禁 + 安全區 PK) ----------
func t_dingyuan(data: GameData) -> void:
	var r := _new(data, 106, 18)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	ch["attrs"]["cha"] = 10
	var door := _portal(sim, "xc_in_2001")
	_put(sim, id, int(door["x"]), int(door["y"]))
	sim.cmd_travel(id, "xc_in_2001")
	check(_map_of(sim, id) == "xc2000", "冇鑰匙: 入唔到丁刺史府")
	_talk(sim, id, "lisu")
	check(_n(ch, 56017) == 1, "李肅: 得董卓勸降書")
	_talk(sim, id, "lvbu_rn")
	check(_n(ch, 56019) == 1 and _n(ch, 56017) == 0, "呂布: 收勸降書、得投降書")
	_talk(sim, id, "lvbu")
	check(_stage(ch, "hist_dingyuan") == 2, "許昌呂布 (絕招 NPC) 唔會推進歷史任務")
	_talk(sim, id, "lisu")
	check(_n(ch, 56018) == 1 and _n(ch, 56019) == 0 and _stage(ch, "hist_dingyuan") == 3, "李肅: 收投降書、得丁原家鑰匙")
	_put(sim, id, int(door["x"]), int(door["y"]))
	sim.cmd_travel(id, "xc_in_2001")
	check(_map_of(sim, id) == "xc2001", "有鑰匙: 入到丁刺史府")
	check(bool(data.map_by_id["xc2001"]["safe"]), "丁刺史府仍然係安全區")
	# 安全區內打得任務 boss
	_talk(sim, id, "dingyuan")
	var b := _boss(sim, "hist_dingyuan")
	check(not b.is_empty() and sim.map_id_at(int(b["x"]), int(b["y"])) == "xc2001", "丁原 boss 喺府內出現")
	check(sim.is_free(int(b["x"]), int(b["y"])), "boss 出喺行得嘅格")
	var hp0 := int(b["hp"])
	sim.ent(id)["ch"]["hp"] = 99999
	sim.ent(id)["hp"] = 99999
	sim.cmd_attack(id, int(b["id"]))
	for i in 200:
		sim.step()
		if _boss(sim, "hist_dingyuan").is_empty() or int(b["hp"]) < hp0:
			break
	check(_boss(sim, "hist_dingyuan").is_empty() or int(b["hp"]) < hp0, "安全區: 玩家打得 quest boss")
	if not _boss(sim, "hist_dingyuan").is_empty():
		sim._kill_mob(b, sim.ent(id))
	check(_done(ch, "hist_dingyuan") and _n(ch, 62072) == 1 and _n(ch, 32305) >= 1, "斬丁原: 完成 + 丁原將軍令 + 無之石")


# ---------- 武將收集冊 ----------
func t_book(data: GameData) -> void:
	var r := _new(data, 107)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var stones: Array = data.comm["book"]["stones"]
	var book := int(data.comm["book"]["item"])
	for s in stones.slice(0, 5):
		RulesShop.add_item(ch["bag"], int(s), 1)
	_talk(sim, id, "laozhang")
	check(_n(ch, book) == 0, "老丈: 石唔齊換唔到")
	RulesShop.add_item(ch["bag"], int(stones[5]), 1)
	_talk(sim, id, "laozhang")
	check(_n(ch, book) == 1, "老丈: 6 石換到收集冊")
	check(stones.all(func(s): return _n(ch, int(s)) == 0), "6 粒石扣晒")
	check(RulesQuest.is_quest_item(data, book), "收集冊唔賣得")
	RulesShop.add_item(ch["bag"], 62093, 1)
	RulesShop.add_item(ch["bag"], 62092, 2)
	RulesShop.add_item(ch["bag"], 29017, 3)
	var slots0 := (ch["bag"] as Array).filter(func(x): return int(x["n"]) > 0).size()
	sim.cmd_book_put(id)
	check(_n(ch, 62093) == 0 and _n(ch, 62092) == 0 and _n(ch, 29017) == 3, "收入冊: 只收將軍令")
	check(int(ch["orderBook"]["62093"]) == 1 and int(ch["orderBook"]["62092"]) == 2, "冊內數量啱")
	check(sim.view_book().size() == 2 and int(sim.view_book()[0]["item"]) == 62092, "view_book 按 id 排")
	check((ch["bag"] as Array).filter(func(x): return int(x["n"]) > 0).size() == slots0 - 2, "收入冊之後背包少 2 格 (唔佔位)")
	# 登用: 冊入面嘅將軍令都算
	var g: Dictionary = sim._order_general("孫堅")
	check(not g.is_empty(), "孫堅係登用武將")
	check(sim._has_order(ch, g), "冊入面嘅孫堅將軍令: 登用有效")
	check(sim._order_consume(ch, 62093) and not ch["orderBook"].has("62093"), "用將軍令: 由冊扣")
	check(not sim._has_order(ch, g), "用完即消")
	sim.cmd_book_take(id, 62092)
	check(_n(ch, 62092) == 1 and int(ch["orderBook"]["62092"]) == 1, "由冊攞 1 張出嚟")
	# 冇冊唔收得
	var r2 := _new(data, 108)
	RulesShop.add_item(r2[2]["bag"], 62093, 1)
	(r2[0] as Sim).cmd_book_put(r2[1])
	check(_n(r2[2], 62093) == 1 and not r2[2].has("orderBook"), "冇收集冊: 收唔到")
	# 老丈已有冊唔再換
	for s in stones:
		RulesShop.add_item(ch["bag"], int(s), 1)
	_talk(sim, id, "laozhang")
	check(_n(ch, book) == 1 and _n(ch, int(stones[0])) == 1, "已有冊: 唔再換、唔扣石")


# ---------- 委託出單 (純函數) ----------
func t_comm_offer(data: GameData) -> void:
	var givers: Array = data.comm["givers"].keys()
	var kinds := {}
	var diff := 0
	for d in 40:
		for gv in givers:
			var o := RulesCommission.offer(data, gv, d, 777)
			var o2 := RulesCommission.offer(data, gv, d, 777)
			if JSON.stringify(o) != JSON.stringify(o2):
				diff += 1000
			kinds[String(o["kind"])] = true
			var ok: bool = int(o["reward"]["gold"]) > 0 and String(o["giver"]) == gv and int(o["day"]) == d
			match String(o["kind"]):
				"hunt":
					ok = ok and (data.comm["givers"][gv]["hunt"] as Array).map(func(x): return int(x)).has(int(o["mob"])) and int(o["n"]) >= 4 and int(o["n"]) <= 8
				"collect":
					ok = ok and RulesCommission.collect_pool(data, data.comm["givers"][gv]).has(int(o["item"])) and int(o["n"]) >= 3
				"deliver":
					ok = ok and (data.comm["givers"][gv]["deliver"] as Array).has(String(o["to"]))
				"repair":
					ok = ok and String(o["skill"]) != "" and int(o["lv"]) >= 1
			if not ok:
				check(false, "委託內容唔啱: %s" % str(o))
			if JSON.stringify(o) != JSON.stringify(RulesCommission.offer(data, gv, d, 778)):
				diff += 1
	check(diff > 0 and diff < 1000, "同 (日, 人, salt) 出同一單；salt 唔同會變")
	check(kinds.size() == 4, "40 日內 4 種委託都出現 (%s)" % str(kinds.keys()))
	check(RulesCommission.offer(data, "mystery_old", 0, 1).is_empty(), "唔係委託人: 冇單")
	var hunt := {"kind": "hunt", "mob": 1001, "n": 2, "prog": 0}
	RulesCommission.on_kill([hunt], 1002)
	check(int(hunt["prog"]) == 0, "on_kill: 唔啱嘅怪唔計")
	RulesCommission.on_kill([hunt], 1001)
	RulesCommission.on_kill([hunt], 1001)
	RulesCommission.on_kill([hunt], 1001)
	check(int(hunt["prog"]) == 2 and RulesCommission.can_report(hunt, []), "on_kill: 計到 n 就停 + 可覆命")
	check(RulesCommission.expired({"accepted": 3}, 6, 3) and not RulesCommission.expired({"accepted": 3}, 5, 3), "過期: 接咗 3 日")


# 搵某人某種委託嘅日子 (從 from 起)
func _day_for(data: GameData, gv: String, kind: String, salt: int, from: int = 0) -> int:
	for d in range(from, from + 200):
		if String(RulesCommission.offer(data, gv, d, salt)["kind"]) == kind:
			return d
	return -1


# ---------- 打怪 / 收集委託 ----------
func t_comm_hunt_collect(data: GameData) -> void:
	var r := _new(data, 111)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var salt := int(sim._comm(ch)["salt"])
	var gv := "citizen_1"
	var npc: Dictionary = data.quest_npcs[gv]
	var d := _day_for(data, gv, "hunt", salt)
	check(d >= 0, "搵到打怪委託日")
	_at(sim, d, 40)
	var o := sim.comm_offer(ch, gv)
	check(String(o.get("kind", "")) == "hunt", "今日 citizen_1 = 打怪委託")
	_put(sim, id, 1, 1)
	sim.cmd_comm_accept(id, gv)
	check((ch["comm"]["active"] as Array).is_empty(), "唔喺委託人附近接唔到")
	_put(sim, id, int(npc["x"]) + 1, int(npc["y"]))
	sim.cmd_comm_accept(id, gv)
	check((ch["comm"]["active"] as Array).size() == 1, "接咗打怪委託")
	check(sim.comm_offer(ch, gv).is_empty(), "接咗之後今日冇新單")
	sim.cmd_comm_report(id, gv)
	check((ch["comm"]["active"] as Array).size() == 1, "未打夠唔覆命得")
	var mob := int(o["mob"])
	var zone := ""
	for sp in data.spawns:
		if int(sp["monster"]) == mob:
			zone = String(sp["zone"])
			break
	var gold0 := int(ch["gold"])
	var exp0 := int(ch["exp"]) + int(ch["level"]) * 100000
	for i in int(o["n"]):
		var m = sim._spawn_mob(mob, zone)
		if m == null:
			continue
		sim._kill_mob(m, sim.ent(id))
	check(int(ch["comm"]["active"][0]["prog"]) == int(o["n"]), "打夠 %d 隻" % int(o["n"]))
	var view := sim.view_commissions()
	check(view.size() == 1 and bool(view[0]["ready"]) and int(view[0]["left"]) == 3, "記事: 可覆命 + 剩 3 日")
	var gold_before := int(ch["gold"])
	var fame0 := int(ch.get("fame", 0))
	_put(sim, id, int(npc["x"]) + 1, int(npc["y"]))
	sim.cmd_comm_report(id, gv)
	check((ch["comm"]["active"] as Array).is_empty(), "打怪委託覆命完成")
	check(int(ch["gold"]) == gold_before + int(o["reward"]["gold"]) and int(ch["fame"]) == fame0 + 1, "打怪委託: 金 + 名聲")
	check(gold0 >= 0 and exp0 > 0, "(sanity)")
	# 收集
	var gv2 := "xinye_farmer"
	var n2: Dictionary = data.quest_npcs[gv2]
	var d2 := _day_for(data, gv2, "collect", salt, d + 1)
	_at(sim, d2, 40)
	var o2 := sim.comm_offer(ch, gv2)
	_put(sim, id, int(n2["x"]) + 1, int(n2["y"]))
	sim.cmd_comm_accept(id, gv2)
	RulesShop.add_item(ch["bag"], int(o2["item"]), int(o2["n"]) - 1)
	sim.cmd_comm_report(id, gv2)
	check((ch["comm"]["active"] as Array).size() == 1, "收集: 唔夠數唔覆命得")
	RulesShop.add_item(ch["bag"], int(o2["item"]), 1)
	var g1 := int(ch["gold"])
	sim.cmd_comm_report(id, gv2)
	check((ch["comm"]["active"] as Array).is_empty() and _n(ch, int(o2["item"])) == 0, "收集: 交齊完成 + 扣材料")
	check(int(ch["gold"]) == g1 + int(o2["reward"]["gold"]), "收集: 得金")


# ---------- 送信 / 修理委託 ----------
func t_comm_deliver_repair(data: GameData) -> void:
	var r := _new(data, 112)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var salt := int(sim._comm(ch)["salt"])
	var letter := int(data.comm["letterItem"])
	var gv := "citizen_3"
	var npc: Dictionary = data.quest_npcs[gv]
	var d := _day_for(data, gv, "deliver", salt)
	_at(sim, d, 40)
	var o := sim.comm_offer(ch, gv)
	_put(sim, id, int(npc["x"]) + 1, int(npc["y"]))
	sim.cmd_comm_accept(id, gv)
	check(_n(ch, letter) == 1, "送信: 接單得信")
	check(RulesQuest.is_quest_item(data, letter), "信唔賣得")
	var g0 := int(ch["gold"])
	_talk(sim, id, String(o["to"]))
	check((ch["comm"]["active"] as Array).is_empty() and _n(ch, letter) == 0, "送信: 同收信人傾偈即完成")
	check(int(ch["gold"]) == g0 + int(o["reward"]["gold"]), "送信: 得金")
	# 修理
	var gv2 := "runan_smith"
	var n2: Dictionary = data.quest_npcs[gv2]
	var d2 := _day_for(data, gv2, "repair", salt, d + 1)
	check(d2 >= 0, "搵到修理委託日")
	_at(sim, d2, 40)
	var o2 := sim.comm_offer(ch, gv2)
	_put(sim, id, int(n2["x"]) + 1, int(n2["y"]))
	sim.cmd_comm_accept(id, gv2)
	check(not sim.comm_offer(ch, gv2).is_empty(), "修理: 冇技能做唔到 (單仲喺度)")
	var sk := String(o2["skill"])
	sim.cmd_debug_work_lv(id, 99)
	sim.cmd_comm_accept(id, gv2)
	check(not sim.comm_offer(ch, gv2).is_empty(), "修理: 冇工具做唔到")
	ch["tools"][sk] = {"item": int(data.work_adv[sk]["tool"]), "dur": 100}
	var wl := int(sim.work_lv(ch, sk))
	var g1 := int(ch["gold"])
	sim._full_heal(ch)
	sim.cmd_comm_accept(id, gv2)
	check(sim.comm_offer(ch, gv2).is_empty() and (ch["comm"]["active"] as Array).is_empty(), "修理: 即場完成，唔入手上委託")
	check(int(ch["gold"]) == g1 + int(o2["reward"]["gold"]), "修理: 得金")
	check(int(ch["tools"].get(sk, {"dur": 0})["dur"]) < 100, "修理: 用咗工具耐久")
	check(int(sim.work_lv(ch, sk)) >= wl, "修理: 技能經驗 (唔會跌級)")


# ---------- 上限 / 過期 / 放棄 ----------
func t_comm_limits(data: GameData) -> void:
	var r := _new(data, 113)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var salt := int(sim._comm(ch)["salt"])
	var letter := int(data.comm["letterItem"])
	# 揾一日有 ≥ 4 個委託人出非修理單
	var day := -1
	for d in 200:
		var cnt := 0
		for gv in data.comm["givers"]:
			if String(RulesCommission.offer(data, gv, d, salt)["kind"]) != "repair":
				cnt += 1
		if cnt >= 4:
			day = d
			break
	check(day >= 0, "搵到 4 單日")
	_at(sim, day, 40)
	var taken := 0
	for gv in data.comm["givers"]:
		if String(RulesCommission.offer(data, gv, day, salt)["kind"]) == "repair":
			continue
		var n: Dictionary = data.quest_npcs[gv]
		_put(sim, id, int(n["x"]) + 1, int(n["y"]))
		sim.cmd_comm_accept(id, gv)
		taken += 1
		if taken == 4:
			break
	check((ch["comm"]["active"] as Array).size() == 3, "手上委託最多 3 單")
	var letters := _n(ch, letter)
	var has_deliver := (ch["comm"]["active"] as Array).any(func(c): return String(c["kind"]) == "deliver")
	# 放棄: 送信要收返信
	var first: Dictionary = ch["comm"]["active"][0]
	sim.cmd_comm_abandon(id, String(first["giver"]))
	check((ch["comm"]["active"] as Array).size() == 2, "放棄咗 1 單")
	check(sim.comm_offer(ch, String(first["giver"])).is_empty(), "放棄咗今日都唔再出單")
	# 過期
	_at(sim, day + 2, 40)
	check((ch["comm"]["active"] as Array).size() == 2, "第 2 日未過期")
	_at(sim, day + 3, 40)
	check((ch["comm"]["active"] as Array).is_empty(), "第 3 日過期收走")
	check(_n(ch, letter) == 0, "過期: 信收返 (本來 %d, deliver=%s)" % [letters, has_deliver])
	check(not sim.comm_offer(ch, String(first["giver"])).is_empty(), "新一日又有單")


# ---------- 存檔 roundtrip ----------
func t_roundtrip(data: GameData) -> void:
	var r := _new(data, 121)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	_talk(sim, id, "sunjian")
	_talk(sim, id, "huyu")
	var salt := int(sim._comm(ch)["salt"])
	var d := _day_for(data, "citizen_1", "hunt", salt)
	_at(sim, d, 40)
	var n: Dictionary = data.quest_npcs["citizen_1"]
	_put(sim, id, int(n["x"]) + 1, int(n["y"]))
	sim.cmd_comm_accept(id, "citizen_1")
	ch["orderBook"] = {"62092": 2}
	var s1 := sim.save_string()
	var sim2 := Sim.load_string(data, s1)
	check(sim2 != null and sim2.save_string() == s1, "save → load → save 字串一致")
	var ch2: Dictionary = sim2.player_ch()
	check(_stage(ch2, "hist_sunjian") == 1, "載入: 歷史任務進度")
	check(not _boss(sim2, "hist_sunjian").is_empty(), "載入: 胡玉 boss 仲喺度")
	check((ch2["comm"]["active"] as Array).size() == 1 and int(ch2["comm"]["salt"]) == salt, "載入: 委託 + salt")
	check(JSON.stringify(sim2.comm_offer(ch2, "citizen_3")) == JSON.stringify(sim.comm_offer(ch, "citizen_3")), "載入: 出單一樣")
	var id2 := int(sim2.state["player_id"])
	sim2._kill_mob(_boss(sim2, "hist_sunjian"), sim2.ent(id2))
	_talk(sim2, id2, "sunjian")
	check(_done(ch2, "hist_sunjian"), "載入後繼續完成歷史任務")
	check(sim2.order_count(ch2, 62092) == 2, "載入: 收集冊")


# ---------- 決定性 ----------
func _script(data: GameData) -> String:
	var r := _new(data, 131)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	_talk(sim, id, "wanggong")
	_talk(sim, id, "caocao_cl")
	_talk(sim, id, "yudu")
	for i in 30:
		sim.step()
	_at(sim, 2, 40)
	for gv in data.comm["givers"]:
		var n: Dictionary = data.quest_npcs[gv]
		_put(sim, id, int(n["x"]) + 1, int(n["y"]))
		sim.cmd_comm_accept(id, gv)
	for i in 30:
		sim.step()
	return sim.save_string()


func t_determinism(data: GameData) -> void:
	check(_script(data) == _script(data), "同種子同操作 → 存檔一致")
