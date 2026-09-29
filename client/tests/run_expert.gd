extends SceneTree
# 專長任務 (S06e, spec 06 §8【原】sy3_9_1/2):
# 天文/地理認證 1~4 級 (甘德→喬玄/地理圖守護者→南華老仙→左慈/于吉)。
# 驗: 資料/schema、端到端鏈、職業/專長/道具門檻、認證升級、存檔 roundtrip、決定性。
# 跑: Godot --headless --path client --script tests/run_expert.gd   (失敗 exit 1)

var fails := 0
var total := 0

const QUESTS := [
	["expert_tianwen_1", "gande", "tianwen", 1],
	["expert_dili_1", "gande", "dili", 1],
	["expert_tianwen_2", "nanhua_immortal", "tianwen", 2],
	["expert_dili_2", "nanhua_immortal", "dili", 2],
	["expert_tianwen_3", "zuoci", "tianwen", 3],
	["expert_tianwen_4", "zuoci", "tianwen", 4],
	["expert_dili_3", "yuji", "dili", 3],
	["expert_dili_4", "yuji", "dili", 4],
]

# 每級認證要交嘅屬性石 (10%~100% 各一 + 生之石 32306)
const WATER := [32021, 32022, 32023, 32024, 32025, 32026, 32027, 32028, 32029, 32030]
const WIND := [32001, 32002, 32003, 32004, 32005, 32006, 32007, 32008, 32009, 32010]
const FIRE := [32031, 32032, 32033, 32034, 32035, 32036, 32037, 32038, 32039, 32040]
const EARTH := [32011, 32012, 32013, 32014, 32015, 32016, 32017, 32018, 32019, 32020]


func _init() -> void:
	var data := GameData.load_all()
	t_data(data)
	t_tianwen_chain(data)
	t_dili_chain(data)
	t_gates(data)
	t_intro_quests(data)
	t_class_gate(data)
	t_roundtrip(data)
	t_determinism(data)
	print("[TEST] expert quests (S06e): %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


# ---------- helpers ----------
func _new(data: GameData, class_id: String, seed: int) -> Array:
	var sim := Sim.new(data, seed)
	var id := sim.spawn_player("t", class_id)
	var ch: Dictionary = sim.player_ch()
	ch["level"] = 60
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


func _done(ch: Dictionary, qid: String) -> bool:
	return bool(ch.get("questDone", {}).get(qid, false))


func _stage(sim: Sim, id: int, qid: String) -> Dictionary:
	return RulesQuest.stage_of(sim.ent(id)["ch"], sim._quest_by_id(qid))


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


func _drive(sim: Sim, id: int, qid: String, giver: String) -> void:
	var ch: Dictionary = sim.ent(id)["ch"]
	_talk(sim, id, giver)
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
				sim.cmd_quest_turnin(id, qid)
			"fight":
				_talk(sim, id, String(st.get("npc", "")))
				sim.cmd_quest_battle(id, qid)
				_kill_quest_boss(sim, id, qid)
			_:
				return
	check(_done(ch, qid), "%s: 完成" % qid)


# 畀齊某級認證要嘅屬性石 + 生之石 + 前置書/任務
func _give_stones(sim: Sim, id: int, stones: Array) -> void:
	for it in stones:
		sim.cmd_debug_give(id, int(it), 1)
	sim.cmd_debug_give(id, 32306, 1)


# ---------- 資料完整性 ----------
func t_data(data: GameData) -> void:
	var errs := RulesQuest.validate(data)
	check(errs.is_empty(), "quests/quest_npcs schema 驗證 (errors: %s)" % str(errs))
	for row in QUESTS:
		var qid := String(row[0])
		var q: Dictionary = {}
		for x in data.quests:
			if String(x["id"]) == qid:
				q = x
		check(not q.is_empty(), "%s 存在" % qid)
		if q.is_empty():
			continue
		check(String(q.get("type", "")) == "expert", "%s type=expert" % qid)
		check(String(q.get("giver", "")) == String(row[1]), "%s giver=%s" % [qid, row[1]])
		check(data.quest_npcs.has(String(q.get("giver", ""))), "%s giver NPC 存在" % qid)
		var ex: Dictionary = q.get("reward", {}).get("expert", {})
		check(String(ex.get("skill", "")) == String(row[2]), "%s reward.expert.skill=%s" % [qid, row[2]])
		check(int(ex.get("level", 0)) == int(row[3]), "%s reward.expert.level=%d" % [qid, row[3]])
		check(bool(q.has("preHint")) and String(q["preHint"]) != "", "%s 有 preHint" % qid)
	var ids := {}
	for row in QUESTS:
		ids[String(row[0])] = true
	var n := 0
	for x in data.quests:
		if ids.has(String(x["id"])):
			n += 1
	check(n == 8, "S06e 專長任務 8 條齊 (而家 %d)" % n)


# ---------- 天文 4 級端到端 ----------
func t_tianwen_chain(data: GameData) -> void:
	var r := _new(data, "daoshi", 101)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	# 一級前置: 討伐張角 + 太平天文書
	ch["questDone"]["hist_zhangjiao"] = true
	sim.cmd_debug_give(id, 56027, 1)
	_drive(sim, id, "expert_tianwen_1", "gande")
	check(sim.expert_lv(ch, "tianwen") == 1, "天文一級: 認證到 Lv1")
	check(RulesShop.count_item(ch["bag"], 56027) == 1, "太平天文書唔會扣")
	# 二級: 彩虹鑽石
	sim.cmd_debug_give(id, 25011, 1)
	_drive(sim, id, "expert_tianwen_2", "nanhua_immortal")
	check(sim.expert_lv(ch, "tianwen") == 2, "天文二級: 認證到 Lv2")
	# 三級: 水石 x10 + 生之石
	_give_stones(sim, id, WATER)
	_drive(sim, id, "expert_tianwen_3", "zuoci")
	check(sim.expert_lv(ch, "tianwen") == 3, "天文三級: 認證到 Lv3")
	# 四級: 風石 x10 + 生之石
	_give_stones(sim, id, WIND)
	_drive(sim, id, "expert_tianwen_4", "zuoci")
	check(sim.expert_lv(ch, "tianwen") == 4, "天文四級: 認證到 Lv4")


# ---------- 地理 4 級端到端 (一級要打 boss) ----------
func t_dili_chain(data: GameData) -> void:
	var r := _new(data, "bianshi", 102)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	ch["questDone"]["hist_zhangjiao"] = true
	sim.cmd_debug_give(id, 56027, 1)
	_drive(sim, id, "expert_dili_1", "gande")
	check(sim.expert_lv(ch, "dili") == 1, "地理一級: 認證到 Lv1")
	sim.cmd_debug_give(id, 25011, 1)
	_drive(sim, id, "expert_dili_2", "nanhua_immortal")
	check(sim.expert_lv(ch, "dili") == 2, "地理二級: 認證到 Lv2")
	_give_stones(sim, id, FIRE)
	_drive(sim, id, "expert_dili_3", "yuji")
	check(sim.expert_lv(ch, "dili") == 3, "地理三級: 認證到 Lv3")
	_give_stones(sim, id, EARTH)
	_drive(sim, id, "expert_dili_4", "yuji")
	check(sim.expert_lv(ch, "dili") == 4, "地理四級: 認證到 Lv4")


# ---------- F7: 其餘 10 個專長 1 級入門任務 + 成功使用 ----------
const INTRO := [
	["kaiken", "xinye_farmer"], ["zhaolai", "xinye_clerk"], ["siyu", "baoma_zhai"], ["tankuang", "miner_boss"],
	["xiuzhu", "craft_boss"], ["gongyi", "runan_smith"], ["jiuzai", "town_head"], ["jiaoyi", "merchant_guild"],
	["xunlian", "recruit_officer"], ["jingjie", "hefu_guard"],
]
const DOMESTIC_JOB := {"kaiken": "kaiken", "zhaolai": "shangye", "siyu": "xumu", "tankuang": "kuangchan", "xiuzhu": "fangyu", "gongyi": "duanzao"}


func t_intro_quests(data: GameData) -> void:
	for row in INTRO:
		var sk := String(row[0])
		var qid := "expert_%s_1" % sk
		var q := {}
		for x in data.quests:
			if String(x["id"]) == qid:
				q = x
		check(not q.is_empty() and String(q["type"]) == "expert", "F7: %s 有入門任務" % sk)
		if q.is_empty():
			continue
		var r := _new(data, "yishi", 300 + INTRO.find(row))
		var sim: Sim = r[0]
		var id: int = r[1]
		var ch: Dictionary = r[2]
		check(sim.expert_lv(ch, sk) == 0, "F7: %s 未學 = 0 級" % sk)
		# 答錯唔畀過
		var npc: Dictionary = data.quest_npcs[String(row[1])]
		sim._sync_quest_npcs()
		_put(sim, id, int(npc["x"]) + 1, int(npc["y"]))
		sim.cmd_quest_talk(id, String(row[1]))
		sim.cmd_quest_answer(id, qid, (int(q["stages"][0]["answer"]) + 1) % 3)
		check(not _done(ch, qid) and sim.expert_lv(ch, sk) == 0, "F7: %s 答錯唔通過" % sk)
		_drive(sim, id, qid, String(row[1]))
		check(_done(ch, qid), "F7: %s 入門任務完成" % sk)
		check(sim.expert_lv(ch, sk) == 1, "F7: %s 認證到 Lv1" % sk)
	# 成功使用專長: 認證後做內政，專長 exp 增加、封頂唔超職業上限
	var r2 := _new(data, "yishi", 400)
	var sim2: Sim = r2[0]
	var id2: int = r2[1]
	var ch2: Dictionary = r2[2]
	ch2["titleRank"] = 1
	ch2["ap"] = 100
	var fac: Dictionary = data.facilities["donate_xc"] if data.facilities.has("donate_xc") else {}
	if not fac.is_empty():
		_put(sim2, id2, int(fac["x"]), int(fac["y"]))
		RulesExpert.certify(ch2, data.experts, "kaiken", 1, 0)
		var e0 := int((ch2["expert"] as Dictionary).get("kaiken", 0))
		sim2.cmd_domestic(id2, "kaiken")
		check(int((ch2["expert"] as Dictionary).get("kaiken", 0)) > e0, "F7: 成功使用專長 (內政開墾) → 專長 exp 增加")


# ---------- 前置門檻 ----------
func t_gates(data: GameData) -> void:
	# 冇完成討伐張角 → 一級唔觸發
	var r := _new(data, "daoshi", 103)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	sim.cmd_debug_give(id, 56027, 1)
	_talk(sim, id, "gande")
	check(not (ch.get("quests", {}) as Dictionary).has("expert_tianwen_1"), "未討伐張角: 一級唔觸發")
	# 完成任務但冇天書 → 唔觸發
	ch["questDone"]["hist_zhangjiao"] = true
	RulesShop.remove_item(ch["bag"], 56027, 1)
	_talk(sim, id, "gande")
	check(not (ch.get("quests", {}) as Dictionary).has("expert_tianwen_1"), "冇天書: 一級唔觸發")
	# 冇天文一級 → 二級唔觸發
	var r2 := _new(data, "daoshi", 104)
	var sim2: Sim = r2[0]
	var id2: int = r2[1]
	var ch2: Dictionary = r2[2]
	sim2.cmd_debug_give(id2, 25011, 1)
	_talk(sim2, id2, "nanhua_immortal")
	check(not (ch2.get("quests", {}) as Dictionary).has("expert_tianwen_2"), "冇天文一級: 二級唔觸發")
	# 冇天文二級 → 三級唔觸發
	_talk(sim2, id2, "zuoci")
	check(not (ch2.get("quests", {}) as Dictionary).has("expert_tianwen_3"), "冇天文二級: 三級唔觸發")


# ---------- 職業門檻 ----------
func t_class_gate(data: GameData) -> void:
	# 義士冇得認證天文三級 (classAny 唔包)
	var r := _new(data, "yishi", 105)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	ch["expert"]["tianwen"] = 30    # 已達二級
	ch["questDone"]["expert_tianwen_2"] = true
	_give_stones(sim, id, WATER)
	_talk(sim, id, "zuoci")
	check(not (ch.get("quests", {}) as Dictionary).has("expert_tianwen_3"), "義士: 唔可以接天文三級")
	# 辯士可以接天文三級，但唔可以接四級 (cap 3 / classAny)
	var r2 := _new(data, "bianshi", 106)
	var sim2: Sim = r2[0]
	var id2: int = r2[1]
	var ch2: Dictionary = r2[2]
	ch2["expert"]["tianwen"] = 60    # 三級
	ch2["questDone"]["expert_tianwen_2"] = true
	ch2["questDone"]["expert_tianwen_3"] = true
	_give_stones(sim2, id2, WIND)
	_talk(sim2, id2, "zuoci")
	check(not (ch2.get("quests", {}) as Dictionary).has("expert_tianwen_4"), "辯士: 唔可以接天文四級")


# ---------- 存檔 roundtrip ----------
func t_roundtrip(data: GameData) -> void:
	var r := _new(data, "daoshi", 107)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	ch["questDone"]["hist_zhangjiao"] = true
	sim.cmd_debug_give(id, 56027, 1)
	_drive(sim, id, "expert_tianwen_1", "gande")
	# 地理一級做到 fight 階段 (stage=1)
	_talk(sim, id, "gande")
	check(int(ch["quests"]["expert_dili_1"]["stage"]) == 1, "地理一級 stage=1 (fight)")
	var s := sim.save_string()
	var sim2 := Sim.load_string(data, s)
	var ch2: Dictionary = sim2.player_ch()
	check(int(ch2.get("expert", {}).get("tianwen", 0)) == 10, "存檔: 天文認證 exp 保留")
	check(int(ch2["quests"]["expert_dili_1"]["stage"]) == 1, "存檔: 進行中 stage 保留")
	var id2 := int(sim2.state["player_id"])
	sim2._full_heal(ch2)
	sim2._sync_stats(sim2.ent(id2))
	_drive(sim2, id2, "expert_dili_1", "gande")
	check(sim2.expert_lv(ch2, "dili") == 1, "存檔後續玩: 地理一級認證")


# ---------- 決定性 ----------
func t_determinism(data: GameData) -> void:
	var a := _new(data, "daoshi", 108)
	var b := _new(data, "daoshi", 108)
	for r in [a, b]:
		var sim: Sim = r[0]
		var id: int = r[1]
		var ch: Dictionary = r[2]
		ch["questDone"]["hist_zhangjiao"] = true
		sim.cmd_debug_give(id, 56027, 1)
		_drive(sim, id, "expert_tianwen_1", "gande")
		sim.cmd_debug_give(id, 25011, 1)
		_drive(sim, id, "expert_tianwen_2", "nanhua_immortal")
	check(a[2]["questDone"] == b[2]["questDone"], "決定性: 同種子 questDone 一致")
	check((a[2]["expert"] as Dictionary) == (b[2]["expert"] as Dictionary), "決定性: 同種子 expert 一致")