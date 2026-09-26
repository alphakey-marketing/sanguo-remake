extends SceneTree
# 團體任務 16 項 (S06c, spec 06 §6): 任務資料 + 義勇軍門檻 (pre.militia) + 非義勇軍版 (紫虛上人)。
# 義勇軍任務靠 ch.militia.founded 開關 (S08e 先正式 set，呢度注入測試)；每月/每日重複 + NPC 日窗口 → S08f。
# 跑: Godot --headless --path client --script tests/run_group.gd   (失敗 exit 1)

var fails := 0
var total := 0

const NON_MILITIA := ["group_zixu"]


func _init() -> void:
	var data := GameData.load_all()
	t_data(data)
	t_militia_gate(data)
	t_zixu(data)
	t_exterminate(data)
	t_court_rat(data)
	t_ghost(data)
	t_imperial_tool(data)
	t_roundtrip(data)
	t_determinism(data)
	print("[TEST] group: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


# ---------- helpers ----------
func _new(data: GameData, seed: int, militia: bool = false) -> Array:
	var sim := Sim.new(data, seed)
	var id := sim.spawn_player("t")
	var ch: Dictionary = sim.player_ch()
	ch["level"] = 30
	if militia:
		ch["militia"] = {"founded": true}
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


func _fight(sim: Sim, id: int, npc: String, qid: String) -> bool:
	_talk(sim, id, npc)
	var b := _boss(sim, qid)
	if b.is_empty():
		return false
	sim._kill_mob(b, sim.ent(id))
	return true


# ---------- 資料驗證 ----------
func t_data(data: GameData) -> void:
	var errs := RulesQuest.validate(data)
	check(errs.is_empty(), "quests/quest_npcs 驗證 (errors: %s)" % str(errs))
	var groups := data.quests.filter(func(q): return String(q["type"]) == "group")
	check(groups.size() == 17, "團體任務 17 條 (spec 06 §6 字面記 16 項，攻略 sy3_4 有 18 ★，居民除害 Part1/2 合併；而家 %d)" % groups.size())
	var militia_q := 0
	for q in groups:
		check(data.quest_npcs.has(String(q["giver"])), "%s giver 存在" % q["id"])
		check(not (q["stages"] as Array).is_empty(), "%s 有 stages" % q["id"])
		if bool((q.get("pre", {}) as Dictionary).get("militia", false)):
			militia_q += 1
		else:
			check(NON_MILITIA.has(String(q["id"])), "%s 係非義勇軍版（唔使 militia）" % q["id"])
	check(militia_q == 16, "16 條要義勇軍 (%d)" % militia_q)
	# fight boss 全員存在 + 冇掉落
	for mid in [1093, 1094, 1095, 1096, 1097, 1098, 1099]:
		var m: Dictionary = data.monsters.get(mid, {})
		check(not m.is_empty() and (m.get("drops", []) as Array).is_empty(), "boss %d 存在 + 冇掉落" % mid)
	# 新道具存在 + 唔賣得
	for iid in [56503, 56504]:
		check(data.item_ids.has(iid), "任務道具 %d 存在" % iid)
		check(RulesQuest.is_quest_item(data, iid), "任務道具 %d 唔賣得" % iid)


# ---------- militia 門檻 (純函數) ----------
func t_militia_gate(data: GameData) -> void:
	var ch := RulesStats.create_character(data, "t", "yishi")
	var q := {"id": "x", "type": "group", "pre": {"militia": true}}
	check(not RulesQuest.pre_ok(data, q, ch), "冇義勇軍: pre.militia 唔得")
	ch["militia"] = {"founded": true}
	check(RulesQuest.pre_ok(data, q, ch), "有義勇軍: pre.militia 得")
	# 非義勇軍版唔受影響
	var zx: Dictionary = _quest_by_id(data, "group_zixu")
	check(RulesQuest.pre_ok(data, zx, ch), "紫虛上人: 唔使 militia 都可以")
	ch.erase("militia")
	check(RulesQuest.pre_ok(data, zx, ch), "紫虛上人: 冇 militia 都得")


func _quest_by_id(data: GameData, qid: String) -> Dictionary:
	for q in data.quests:
		if String(q["id"]) == qid:
			return q
	return {}


# ---------- 紫虛上人 (非義勇軍版，全線) ----------
func t_zixu(data: GameData) -> void:
	var r := _new(data, 201)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var fame0 := int(ch.get("fame", 0))
	check(not ch.has("militia"), "紫虛上人: 冇義勇軍都可以接")
	_talk(sim, id, "zixu")
	check(_stage(ch, "group_zixu") == 1, "紫虛上人: 接任務 (collect stage)")
	_talk(sim, id, "zixu")
	check(_stage(ch, "group_zixu") == 1, "紫虛上人: 材料唔齊唔推進")
	RulesShop.add_item(ch["bag"], 25097, 5)
	_talk(sim, id, "zixu")              # collect turnin → 推進到最後 talk stage
	check(_stage(ch, "group_zixu") == 2, "紫虛上人: 交材料推進到覆命 stage")
	_talk(sim, id, "zixu")
	check(_done(ch, "group_zixu"), "紫虛上人: 交材料完成")
	check(_n(ch, 61319) == 1 and _n(ch, 25097) == 0, "紫虛上人: 得藏寶圖 + 扣材料")
	check(int(ch.get("fame", 0)) >= fame0, "紫虛上人: 名聲冇跌")


# ---------- 居民除害（猛獸王）— 義勇軍 fight 全線 ----------
func t_exterminate(data: GameData) -> void:
	var r := _new(data, 202)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	_talk(sim, id, "wu_lao")
	check(_stage(ch, "group_exterminate") == -1, "除害: 冇義勇軍接唔到")
	check(not _vis(sim, "beast_king"), "除害: 未接唔見猛獸王")
	ch["militia"] = {"founded": true}
	_talk(sim, id, "wu_lao")
	check(_stage(ch, "group_exterminate") == 1, "除害: 有義勇軍接到任務")
	check(_vis(sim, "beast_king"), "除害: 任務進行中猛獸王出現")
	check(_fight(sim, id, "beast_king", "group_exterminate"), "除害: 對話召喚猛獸王 boss")
	check(_boss(sim, "group_exterminate").is_empty(), "除害: boss 死咗唔重生")
	_talk(sim, id, "wu_lao")
	check(_done(ch, "group_exterminate"), "除害: 回報完成")
	var fame0 := int(ch.get("fame", 0))
	check(fame0 >= 0, "(sanity fame)")


# ---------- 朝廷滅鼠 — 義勇軍 collect 全線 ----------
func t_court_rat(data: GameData) -> void:
	var r := _new(data, 203, true)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	_talk(sim, id, "court_rat")
	check(_stage(ch, "group_court_rat") == 1, "滅鼠: 接到任務 (collect)")
	var gold0 := int(ch["gold"])
	RulesShop.add_item(ch["bag"], 61501, 5)
	_talk(sim, id, "court_rat")
	check(_stage(ch, "group_court_rat") == 1, "滅鼠: 唔夠 30 唔推進")
	check(_n(ch, 61501) == 5, "滅鼠: 唔夠唔扣")
	RulesShop.add_item(ch["bag"], 61501, 25)
	_talk(sim, id, "court_rat")              # collect turnin
	_talk(sim, id, "court_rat")              # 覆命
	check(_done(ch, "group_court_rat"), "滅鼠: 交齊 30 完成")
	check(_n(ch, 61501) == 0, "滅鼠: 田鼠碎骨扣晒")
	var q: Dictionary = _quest_by_id(data, "group_court_rat")
	check(int(ch["gold"]) == gold0 + int(q["reward"]["gold"]), "滅鼠: 得賞金")


# ---------- 鬼域迷陣 — 洞窟內 fight (questOnly 戰boss) ----------
func t_ghost(data: GameData) -> void:
	var r := _new(data, 204, true)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	sim.state["clock"]["day"] = 18      # S08f: 神經老人 16~21 日先現身
	sim._sync_quest_npcs()
	_talk(sim, id, "shenjing_lao")
	check(_stage(ch, "group_ghost") == 1, "鬼域: 神經老人觸發任務")
	check(_vis(sim, "ghost_guard"), "鬼域: 巨魎出現 (洞窟三層)")
	check(_fight(sim, id, "ghost_guard", "group_ghost"), "鬼域: 打巨魎 boss")
	_talk(sim, id, "shenjing_lao")
	check(_done(ch, "group_ghost") and _n(ch, 25002) >= 20, "鬼域: 完成 + 得礦石×20")


# ---------- 初階御賜工具 (collect → 御賜工具) ----------
func t_imperial_tool(data: GameData) -> void:
	var r := _new(data, 205, true)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	_talk(sim, id, "court_official_tool")
	check(_stage(ch, "group_imperial_tool") == 1, "御賜工具: 接到任務")
	RulesShop.add_item(ch["bag"], 25105, 10)
	_talk(sim, id, "court_official_tool")     # collect turnin
	_talk(sim, id, "court_official_tool")     # 覆命
	check(_done(ch, "group_imperial_tool") and _n(ch, 26053) == 1, "御賜工具: 交雕刻木換御賜鋤頭")


# ---------- 存檔 roundtrip + militia 旗 ----------
func t_roundtrip(data: GameData) -> void:
	var r := _new(data, 121, true)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	_talk(sim, id, "zixu")
	_talk(sim, id, "wu_lao")
	_talk(sim, id, "beast_king")             # 召喚猛獸王 boss
	check(_stage(ch, "group_exterminate") == 1, "存檔前: 除害進行中")
	check(not _boss(sim, "group_exterminate").is_empty(), "存檔前: 猛獸王 boss 喺度")
	check(bool(ch.get("militia", {}).get("founded", false)), "存檔前: militia 旗")
	var s := sim.save_string()
	var sim2 := Sim.load_string(data, s)
	check(sim2 != null and sim2.save_string() == s, "save → load → save 一致")
	var ch2: Dictionary = sim2.player_ch()
	check(_stage(ch2, "group_zixu") == 1, "載入: 紫虛上人進度")
	check(_stage(ch2, "group_exterminate") == 1, "載入: 除害進度")
	check(bool(ch2.get("militia", {}).get("founded", false)), "載入: militia 旗")
	check(not _boss(sim2, "group_exterminate").is_empty(), "載入: 猛獸王 boss 仲喺度")


# ---------- 決定性 ----------
func _script(data: GameData) -> String:
	var r := _new(data, 131, true)
	var sim: Sim = r[0]
	var id: int = r[1]
	_talk(sim, id, "zixu")
	_talk(sim, id, "wu_lao")
	_talk(sim, id, "beast_king")
	for i in 30:
		sim.step()
	return sim.save_string()


func t_determinism(data: GameData) -> void:
	check(_script(data) == _script(data), "同種子同操作 → 存檔一致")