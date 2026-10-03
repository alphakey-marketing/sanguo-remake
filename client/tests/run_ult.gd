extends SceneTree
# 其他職絕招任務鏈 (S06d, spec 06 §5.4【原】sy3_6_1~3):
# 仕女/道士/巫女/辯士/美女 各一~三招共 15 條，端到端驅動 (ask/talk/collect/fight)。
# 驗: 職業門檻 / 招數鏈 questDone 前置 / 學識 ultimate / 武器獎勵 / 存檔 roundtrip / 決定性。
# 跑: Godot --headless --path client --script tests/run_ult.gd   (失敗 exit 1)

var fails := 0
var total := 0

# [classId, ultId, questId, giver, level]
const QUESTS := [
	["shinu", "huxiao", "ult_shinu_huxiao", "shinu_master", 20],
	["shinu", "jinhu", "ult_shinu_jinhu", "shinu_master", 33],
	["shinu", "jinghua", "ult_shinu_jinghua", "shinu_master", 43],
	["daoshi", "xuwu", "ult_daoshi_xuwu", "daoshi_master", 20],
	["daoshi", "ruhuan", "ult_daoshi_ruhuan", "daoshi_master", 30],
	["daoshi", "shenyou", "ult_daoshi_shenyou", "daoshi_master", 45],
	["wunu", "candeng", "ult_wunu_candeng", "wunu_master", 20],
	["wunu", "danchan", "ult_wunu_danchan", "wunu_master", 30],
	["wunu", "guiku", "ult_wunu_guiku", "wunu_master", 42],
	["bianshi", "tiandao", "ult_bianshi_tiandao", "bianshi_master", 20],
	["bianshi", "tuohuo", "ult_bianshi_tuohuo", "bianshi_master", 31],
	["bianshi", "sanfen", "ult_bianshi_sanfen", "bianshi_master", 45],
	["meinu", "xiaobo", "ult_meinu_xiaobo", "meinu_master", 20],
	["meinu", "songzhu", "ult_meinu_songzhu", "meinu_master", 30],
	["meinu", "feihua", "ult_meinu_feihua", "meinu_master", 44],
	["shinu", "tianhuo", "ult_shinu_tianhuo", "shinu_master", 50],
	["shinu", "liehuo", "ult_shinu_liehuo", "shinu_master", 60],
	["shinu", "hengsao", "ult_shinu_hengsao", "shinu_master", 70],
	["daoshi", "wolong", "ult_daoshi_wolong", "daoshi_master", 50],
	["daoshi", "leizhen", "ult_daoshi_leizhen", "daoshi_master", 60],
	["daoshi", "qimen", "ult_daoshi_qimen", "daoshi_master", 70],
	["wunu", "shehun", "ult_wunu_shehun", "wunu_master", 50],
	["wunu", "suohun", "ult_wunu_suohun", "wunu_master", 60],
	["wunu", "qunmo", "ult_wunu_qunmo", "wunu_master", 70],
	["bianshi", "wanjian", "ult_bianshi_wanjian", "bianshi_master", 50],
	["bianshi", "zhuiyun", "ult_bianshi_zhuiyun", "bianshi_master", 60],
	["meinu", "huangying", "ult_meinu_huangying", "meinu_master", 50],
	["meinu", "luoshen", "ult_meinu_luoshen", "meinu_master", 60],
]


func _init() -> void:
	var data := GameData.load_all()
	t_data(data)
	t_all_chains(data)
	t_class_gate(data)
	t_chain_gate(data)
	t_roundtrip(data)
	t_determinism(data)
	print("[TEST] ultimate quest chains (S06d): %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


# ---------- helpers ----------
func _new(data: GameData, class_id: String, seed: int, level: int) -> Array:
	var sim := Sim.new(data, seed)
	var id := sim.spawn_player("t", class_id)
	var ch: Dictionary = sim.player_ch()
	ch["level"] = level
	sim._full_heal(ch)
	sim._sync_stats(sim.ent(id))
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
	_put(sim, id, int(n["x"]), int(n["y"]))
	sim.cmd_quest_talk(id, npc_id)


func _vis(sim: Sim, npc: String) -> bool:
	return bool(sim.state["quest_npcs"].get(npc, {}).get("visible", false))


func _done(ch: Dictionary, qid: String) -> bool:
	return bool(ch.get("questDone", {}).get(qid, false))


func _stage(sim: Sim, id: int, qid: String) -> Dictionary:
	return RulesQuest.stage_of(sim.ent(id)["ch"], sim._quest_by_id(qid))


# 通用驅動: 由觸發開始，逐步根據 stage type 發指令，直到完成
func _drive(sim: Sim, id: int, qid: String, giver: String) -> void:
	var ch: Dictionary = sim.ent(id)["ch"]
	_talk(sim, id, giver)                       # 觸發 (talk-first 會即場推進 stage0)
	for _i in 20:
		if _done(ch, qid):
			return
		var st := _stage(sim, id, qid)
		if st.is_empty():
			return
		match String(st.get("type", "")):
			"talk":
				_talk(sim, id, String(st.get("npc", giver)))
			"ask":
				sim.cmd_quest_answer(id, qid, int(st.get("answer", 0)))
			"collect":
				var it: Dictionary = st.get("item", {})
				sim.cmd_debug_give(id, int(it["id"]), int(it["n"]))
				_talk(sim, id, giver)
				sim.cmd_quest_turnin(id, qid)
			"fight":
				_talk(sim, id, String(st.get("npc", "")))
				sim.cmd_quest_battle(id, qid)
				_kill_quest_boss(sim, id, qid)
			_:
				return
	check(_done(ch, qid), "%s: 完成" % qid)


func _kill_quest_boss(sim: Sim, id: int, qid: String) -> void:
	var boss := 0
	for e in sim.ents.values():
		if str(e.get("mob", {}).get("quest_boss", "")) == qid:
			boss = int(e["id"])
	if boss == 0:
		return
	sim.ent(boss)["hp"] = 1
	sim.cmd_attack(id, boss)
	for _i in 120:
		sim.step()
		if sim.ent(boss).is_empty():
			return


func _bag_n(sim: Sim, id: int, item: int) -> int:
	return RulesShop.count_item(sim.ent(id)["ch"]["bag"], item)


# ---------- 資料完整性 ----------
func t_data(data: GameData) -> void:
	var errs := RulesQuest.validate(data)
	check(errs.is_empty(), "quests/quest_npcs schema 驗證 (errors: %s)" % str(errs))
	for row in QUESTS:
		var qid := String(row[2])
		var ult := String(row[1])
		var q: Dictionary = {}
		for x in data.quests:
			if String(x["id"]) == qid:
				q = x
		check(not q.is_empty(), "%s 存在" % qid)
		if q.is_empty():
			continue
		check(String(q.get("type", "")) == "ultimate", "%s type=ultimate" % qid)
		check(String(q["reward"].get("ultimate", "")) == ult, "%s reward.ultimate=%s" % [qid, ult])
		check(data.quest_npcs.has(String(q.get("giver", ""))), "%s giver 存在" % qid)
		check(String(data.ult_by_id[ult].get("quest", "")) == qid, "%s ultimate.quest 反指" % ult)
	# 15 條齊全
	var ids := {}
	for row in QUESTS:
		ids[String(row[2])] = true
	var n := 0
	for x in data.quests:
		if ids.has(String(x["id"])):
			n += 1
	check(n == 28, "S06d 絕招任務 28 條齊 (而家 %d)" % n)


# ---------- 15 條端到端 ----------
func t_all_chains(data: GameData) -> void:
	# 每職一個 sim, 逐招 (tier 由 1 遞進, pre 有 questDone 鏈)
	var order := ["shinu", "daoshi", "wunu", "bianshi", "meinu"]
	for ci in order.size():
		var cls: String = order[ci]
		var rows: Array = []
		for row in QUESTS:
			if String(row[0]) == cls:
				rows.append(row)
		var r := _new(data, cls, 200 + ci, 20)
		var sim: Sim = r[0]
		var id: int = r[1]
		var ch: Dictionary = r[2]
		for row in rows:
			var ult := String(row[1])
			var qid := String(row[2])
			var giver := String(row[3])
			ch["level"] = int(row[4])
			sim._full_heal(ch)
			sim._sync_stats(sim.ent(id))
			sim._sync_quest_npcs()
			_drive(sim, id, qid, giver)
			check((ch.get("ultimates", []) as Array).has(ult), "%s 學識 %s" % [qid, ult])
			check(_done(ch, qid), "%s 完成" % qid)
		check((ch.get("ultimates", []) as Array).size() == rows.size(), "%s 三招齊 (%d)" % [cls, rows.size()])


func t_class_gate(data: GameData) -> void:
	# 錯職業唔可以觸發 (義士去搵仕女師傅 = 唔會開仕女招)
	var r := _new(data, "yishi", 7, 30)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	_talk(sim, id, "shinu_master")
	check(not (ch.get("quests", {}) as Dictionary).has("ult_shinu_huxiao"), "職業唔啱: 唔觸發仕女一招")
	# 對職業 20 級以下唔觸發
	var r2 := _new(data, "shinu", 8, 19)
	var sim2: Sim = r2[0]
	var id2: int = r2[1]
	var ch2: Dictionary = r2[2]
	_talk(sim2, id2, "shinu_master")
	check(not (ch2.get("quests", {}) as Dictionary).has("ult_shinu_huxiao"), "等級唔夠: 唔觸發")


func t_chain_gate(data: GameData) -> void:
	# 未學一招唔可以接二招
	var r := _new(data, "wunu", 11, 35)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	_talk(sim, id, "wunu_master")
	check((ch.get("quests", {}) as Dictionary).has("ult_wunu_candeng"), "巫女一招觸發")
	check(not (ch.get("quests", {}) as Dictionary).has("ult_wunu_danchan"), "未學一招: 二招唔觸發")
	# 完成一招後, 二招先觸發
	_drive(sim, id, "ult_wunu_candeng", "wunu_master")
	ch["level"] = 30
	sim._sync_quest_npcs()
	_talk(sim, id, "wunu_master")
	check((ch.get("quests", {}) as Dictionary).has("ult_wunu_danchan"), "學完一招: 二招觸發")


func t_roundtrip(data: GameData) -> void:
	var r := _new(data, "daoshi", 21, 30)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	# 完成一招 + 進行中二招 (talk 已推進到 collect)
	_drive(sim, id, "ult_daoshi_xuwu", "daoshi_master")
	_talk(sim, id, "daoshi_master")            # 觸發並推進二招到 collect (文成親筆信到)
	check((ch.get("quests", {}) as Dictionary).has("ult_daoshi_ruhuan"), "二招進行中")
	check(int(ch["quests"]["ult_daoshi_ruhuan"]["stage"]) == 1, "二招 stage=1 (collect)")
	sim.cmd_debug_give(id, 25009, 12)          # 部分收集
	var s := sim.save_string()
	var sim2 := Sim.load_string(data, s)
	var ch2: Dictionary = sim2.player_ch()
	check((ch2.get("ultimates", []) as Array).has("xuwu"), "存檔: 已學一招保留")
	check(int(ch2["quests"]["ult_daoshi_ruhuan"]["stage"]) == 1, "存檔: 進行中 stage 保留")
	check(RulesShop.count_item(ch2["bag"], 25009) == 12, "存檔: 收集進度保留")
	# 載入後可以繼續完成
	sim2._full_heal(ch2)
	sim2._sync_stats(sim2.ent(int(sim2.state["player_id"])))
	_drive(sim2, int(sim2.state["player_id"]), "ult_daoshi_ruhuan", "daoshi_master")
	check((ch2.get("ultimates", []) as Array).has("ruhuan"), "存檔後續玩: 學識二招")


func t_determinism(data: GameData) -> void:
	var a := _new(data, "meinu", 33, 20)
	var b := _new(data, "meinu", 33, 20)
	_drive(a[0], a[1], "ult_meinu_xiaobo", "meinu_master")
	_drive(b[0], b[1], "ult_meinu_xiaobo", "meinu_master")
	check(a[2]["questDone"] == b[2]["questDone"], "決定性: 同種子 questDone 一致")
	check((a[2]["ultimates"] as Array) == (b[2]["ultimates"] as Array), "決定性: 同種子 ultimates 一致")
