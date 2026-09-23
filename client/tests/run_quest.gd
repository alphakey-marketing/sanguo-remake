extends SceneTree
# 任務系統測試 (Step 8, spec 06 §1~2): schema 驗證 / 時辰窗口 NPC / pre 條件 /
# 新手任務鏈端到端 / 密醫服務 / 任務道具唔賣得 / 存檔 roundtrip / turnin/answer。
# 跑: Godot --headless --path client --script tests/run_quest.gd   (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_validate(data)
	t_npc_visible_pure(data)
	t_window_pure()
	t_quest_item(data)
	t_newbie_chain(data)
	t_windows_in_sim(data)
	t_miyi_service(data)
	t_quest_item_sell_blocked(data)
	t_reward_use(data)
	t_turnin_answer(data)
	t_roundtrip(data)
	print("[TEST] quest: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


func _put(sim: Sim, id: int, x: int, y: int) -> void:
	var e := sim.ent(id)
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y


func _talk(sim: Sim, id: int, npc_id: String) -> void:
	var n: Dictionary = sim.data.quest_npcs[npc_id]
	_put(sim, id, int(n["x"]) + 1, int(n["y"]))
	sim.cmd_quest_talk(id, npc_id)


func _bag_n(sim: Sim, id: int, item: int) -> int:
	var ch: Dictionary = sim.ent(id)["ch"]
	for b in ch["bag"]:
		if int(b["id"]) == item:
			return int(b["n"])
	return 0


func _npc_visible(sim: Sim, npc_id: String) -> bool:
	return bool(sim.state["quest_npcs"].get(npc_id, {}).get("visible", false))


# ---------- schema 驗證 ----------
func t_validate(data: GameData) -> void:
	var errs := RulesQuest.validate(data)
	check(errs.is_empty(), "quests.json + quest_npcs.json schema 驗證通過 (errors: %s)" % str(errs))
	# 壞數據要報錯
	var bad := GameData.new()
	bad.quests = [{"id": "q1", "type": "nonsense", "stages": [{"type": "talk", "npc": "nobody", "done": true}], "reward": {"items": [[999999, 1]]}}]
	bad.quest_npc_list = []
	var e2 := RulesQuest.validate(bad)
	check(e2.size() >= 3, "壞 quest 報錯 (type/npc/item): %s" % str(e2))
	bad.quest_npc_list = [{"id": "x", "window": {"startKe": 99, "endKe": 5}}]
	check(RulesQuest.validate(bad).size() >= 4, "壞 window 報錯")


# ---------- NPC 可見性 (純函數) ----------
func t_npc_visible_pure(data: GameData) -> void:
	var ch := RulesStats.create_character(data, "t", "yishi")
	var old: Dictionary = data.quest_npcs["mystery_old"]
	check(RulesQuest.npc_visible(old, ch, 30), "神秘老人: 1 級 + 任意時辰可見")
	ch["level"] = 5
	check(not RulesQuest.npc_visible(old, ch, 30), "神秘老人: 5 級唔可見 (<5 級【原】)")
	var dog: Dictionary = data.quest_npcs["stray_dog"]
	ch["level"] = 5
	check(not RulesQuest.npc_visible(dog, ch, 0), "流浪狗: 5 級但 ko 0 (子時 1 刻) 唔見")
	check(RulesQuest.npc_visible(dog, ch, 2), "流浪狗: ke 2 (子時 3 刻) 見")
	check(not RulesQuest.npc_visible(dog, ch, 5), "流浪狗: ke 5 (子時 6 刻) 唔見 (窗口 2~5 刻)")


# ---------- 時辰窗口純函數 ----------
func t_window_pure() -> void:
	check(RulesQuest.ke_in_window(2, 1, 5) and RulesQuest.ke_in_window(4, 1, 5), "窗口含頭尾")
	check(not RulesQuest.ke_in_window(0, 1, 5) and not RulesQuest.ke_in_window(5, 1, 5), "窗口外唔算")
	check(RulesQuest.ke_in_window(95, 90, 5) and RulesQuest.ke_in_window(3, 90, 5), "跨日窗口 (亥→丑)")


# ---------- 任務道具 ----------
func t_quest_item(data: GameData) -> void:
	check(RulesQuest.is_quest_item(data, 61501), "61501 田鼠碎骨 = 任務道具")
	check(RulesQuest.is_quest_item(data, 58025), "58025 暴虎獸皮 (cat 44) = 任務道具")
	check(not RulesQuest.is_quest_item(data, 10001), "10001 柳葉刀唔係任務道具")
	check(not RulesQuest.is_quest_item(data, 65210), "65210 紅藥水I 唔係任務道具")


# ---------- 新手任務鏈端到端 ----------
func t_newbie_chain(data: GameData) -> void:
	var sim := Sim.new(data, 5)
	var id := sim.spawn_player("t")
	var ch: Dictionary = sim.player_ch()
	var old_gold := int(ch["gold"])
	check(_npc_visible(sim, "mystery_old"), "開場: 神秘老人可見 (1 級)")
	check(not _npc_visible(sim, "stray_dog"), "開場: 流浪狗唔可見 (未 5 級)")
	# --- 神秘老人: 開始 ---
	_talk(sim, id, "mystery_old")
	check((ch["quests"] as Dictionary).has("newbie_mystery"), "神秘老人: 任務觸發")
	check(int(ch["quests"]["newbie_mystery"]["stage"]) == 1, "神秘老人: stage 1 (搵街坊)")
	# --- 3 個街坊 ---
	_talk(sim, id, "citizen_1")
	_talk(sim, id, "citizen_2")
	check(int(ch["quests"]["newbie_mystery"]["stage"]) == 1, "街坊 2/3: 未推進")
	_talk(sim, id, "citizen_3")
	check(int(ch["quests"]["newbie_mystery"]["stage"]) == 2, "街坊 3/3: stage 2 (報告)")
	# 進行中升上 5 級: giver 都要常駐（唔係報告唔到）
	ch["level"] = 5
	sim._sync_stats(sim.ent(id))
	sim._sync_quest_npcs()
	check(_npc_visible(sim, "mystery_old"), "任務進行中: 神秘老人唔會消失 (即使已 5 級)")
	# --- 報告 (5 級都 report 到) ---
	_talk(sim, id, "mystery_old")
	check(bool(ch["questDone"].get("newbie_mystery", false)), "神秘老人: 完成記錄")
	check(not (ch["quests"] as Dictionary).has("newbie_mystery"), "神秘老人: 進行中列表清走")
	check(int(ch["gold"]) == old_gold + 50, "神秘老人: +50 金")
	check(_bag_n(sim, id, 65210) == 10, "神秘老人: 新手藥品 +5 (開場 5 + 獎勵 5)")
	check(not (ch["quests"] as Dictionary).has("newbie_mystery"), "神秘老人: 進行中列表清走")
	check(int(ch["gold"]) == old_gold + 50, "神秘老人: +50 金")
	check(_bag_n(sim, id, 65210) == 10, "神秘老人: 新手藥品 +5 (開場 5 + 獎勵 5)")
	# --- 練兵場 ---
	_talk(sim, id, "training_recruit")
	check(bool(ch["questDone"].get("newbie_training", false)), "練兵場: 完成")
	check(int(ch.get("lilian", 0)) == 10, "練兵場: 歷練 +10")
	check(_bag_n(sim, id, 10002) == 1, "練兵場: 新手武器 (鬼頭刀)")
	# --- 寺廟/私塾退款 ---
	_put(sim, id, 22, 16)
	var gold0 := int(ch["gold"])
	sim.cmd_facility(id, "temple")
	check(bool(ch["questDone"].get("newbie_temple", false)), "寺廟: 新手任務完成")
	check(int(ch["gold"]) == gold0, "寺廟: 退款 (免費)")
	check(int(ch["attrs"]["cha"]) == int(data.classes["yishi"]["base"]["cha"]) + 1, "寺廟: 魅力 +1")
	_put(sim, id, 14, 14)
	gold0 = int(ch["gold"])
	sim.cmd_facility(id, "school")
	check(bool(ch["questDone"].get("newbie_school", false)), "私塾: 新手任務完成")
	check(int(ch["gold"]) == gold0, "私塾: 退款 (免費)")
	check(int(ch["attrs"]["pol"]) == int(data.classes["yishi"]["base"]["pol"]) + 1, "私塾: 政治 +1")
	# 再修練要收錢
	_put(sim, id, 22, 16)
	sim.cmd_facility(id, "temple")
	check(int(ch["gold"]) == gold0 - 8, "寺廟: 第二次收返 8 金")
	# --- 流浪狗 (5 級 + 子時窗口) ---
	ch["level"] = 5
	sim._sync_stats(sim.ent(id))
	sim._sync_quest_npcs()
	check(not _npc_visible(sim, "stray_dog"), "5 級但 ke 0: 狗唔見 (窗口外)")
	# 行到子時 3 刻 (ke 2 = tick 16)
	for i in 16:
		sim.step()
	check(_npc_visible(sim, "stray_dog"), "ke 2: 狗出現 (子時 3 刻)")
	_talk(sim, id, "stray_dog")
	check((ch["quests"] as Dictionary).has("newbie_dog"), "流浪狗: 任務觸發")
	_talk(sim, id, "stray_dog")
	check(int(ch["quests"]["newbie_dog"]["flags"]["count"]) == 1, "流浪狗: 跟蹤第 1 晚 (perDay 同一日唔重計)")
	_talk(sim, id, "stray_dog")
	check(int(ch["quests"]["newbie_dog"]["flags"]["count"]) == 1, "流浪狗: 同晚重複唔計")
	# 第二晚
	for i in 720:
		sim.step()
	_talk(sim, id, "stray_dog")
	check(int(ch["quests"]["newbie_dog"]["flags"]["count"]) == 2, "流浪狗: 第 2 晚")
	# 第三晚 → 完成
	for i in 720:
		sim.step()
	_talk(sim, id, "stray_dog")
	check(bool(ch["questDone"].get("newbie_dog", false)), "流浪狗: 第 3 晚完成")
	check(_bag_n(sim, id, 65002) == 1, "流浪狗: 狗仔袋 (百寶袋)")
	check(int(ch["lilian"]) == 10 and int(ch["exp"]) >= 100, "流浪狗: +100 exp")


# ---------- sim 時辰窗口 ----------
func t_windows_in_sim(data: GameData) -> void:
	var sim := Sim.new(data, 3)
	var id := sim.spawn_player("t")
	# ke 由 tick 推: 8 tick = ke 1, 16 tick = ke 2 (gameMinPerTick=2, 每 ke = 8 tick)
	var seen := {"v": false}
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev.get("k", "") == "quest_npcs":
			seen["v"] = true)
	for i in 17:
		sim.step()
	check(_npc_visible(sim, "stray_dog") == false, "1 級玩家: 狗永遠唔出現 (等級條件)")
	sim.player_ch()["level"] = 5
	sim._sync_quest_npcs()
	check(_npc_visible(sim, "stray_dog"), "5 級 + ke 2: 狗出現")
	for i in 100:
		sim.step()          # ke 推過窗口 (ke 5+)
	check(not _npc_visible(sim, "stray_dog"), "ke 過咗窗口: 狗消失")
	check(seen["v"], "quest_npcs 事件有 emit")


# ---------- 密醫服務 ----------
func t_miyi_service(data: GameData) -> void:
	var sim := Sim.new(data, 4)
	var id := sim.spawn_player("t")
	var ch: Dictionary = sim.player_ch()
	var mhp := RulesStats.max_hp(int(ch["level"]), ch["attrs"])
	ch["hp"] = mhp - 50
	sim.ent(id)["hp"] = ch["hp"]
	_talk(sim, id, "miyi")
	check(int(ch["hp"]) == mhp, "密醫: 回 100 HP (cap)")
	check(int(ch["quests"]["service_miyi"]["used"]) == 1, "密醫: 用咗 1 次")
	ch["hp"] = mhp - 50
	sim.ent(id)["hp"] = ch["hp"]
	_talk(sim, id, "miyi")
	ch["hp"] = mhp - 50
	sim.ent(id)["hp"] = ch["hp"]
	_talk(sim, id, "miyi")
	check(int(ch["quests"]["service_miyi"]["used"]) == 3, "密醫: 一日 3 次上限")
	ch["hp"] = mhp - 50
	sim.ent(id)["hp"] = ch["hp"]
	_talk(sim, id, "miyi")
	check(int(ch["quests"]["service_miyi"]["used"]) == 3, "密醫: 第 4 次被拒")
	check(int(ch["hp"]) == mhp - 50, "密醫: 第 4 次冇再回血")
	# 第二日 reset
	for i in 720:
		sim.step()
	_talk(sim, id, "miyi")
	check(int(ch["quests"]["service_miyi"]["used"]) == 1, "密醫: 第二日重置")


# ---------- 任務道具唔賣得 ----------
func t_quest_item_sell_blocked(data: GameData) -> void:
	var sim := Sim.new(data, 6)
	var id := sim.spawn_player("t")
	var ch: Dictionary = sim.player_ch()
	sim.cmd_debug_give(id, 61501, 3)
	sim.cmd_debug_give(id, 58025, 1)
	# 行去武器店
	var shop: Dictionary = sim.data.shops[0]
	_put(sim, id, int(shop["x"]), int(shop["y"]))
	var gold0 := int(ch["gold"])
	sim.cmd_sell(id, 61501, 3)
	sim.cmd_sell(id, 58025, 1)
	check(int(ch["gold"]) == gold0, "賣任務道具被擋 (金冇變)")
	check(_bag_n(sim, id, 61501) == 3 and _bag_n(sim, id, 58025) == 1, "任務道具仲喺袋")
	sim.cmd_debug_give(id, 10002, 1)
	sim.cmd_sell(id, 10002, 1)
	check(int(ch["gold"]) > gold0, "非任務道具照賣到")
	# 天地商行代賣都擋
	sim.cmd_storage_sub(id, true)
	ch["storageSub"] = true
	sim.cmd_storage_sell(id, 61501, 1)
	check(_bag_n(sim, id, 61501) == 3, "天地商行代賣都擋任務道具")


# ---------- 獎勵道具可食 (effect 73 藥水修復) ----------
func t_reward_use(data: GameData) -> void:
	var heal: Dictionary = data.heals.get(65210, {})
	check(heal.size() > 0, "65210 紅藥水I 入咗 heals (effect 73)")
	check(int(heal.get("hp", 0)) == 300, "紅藥水I 回 300 HP (73 = value×100 自訂)")
	var sim := Sim.new(data, 8)
	var id := sim.spawn_player("t")
	var ch: Dictionary = sim.player_ch()
	var mhp := RulesStats.max_hp(int(ch["level"]), ch["attrs"])
	ch["hp"] = mhp - 50
	sim.ent(id)["hp"] = ch["hp"]
	sim.cmd_use_item(id, 65210)
	check(int(ch["hp"]) == mhp, "食紅藥水I: 回 300 HP (cap)")
	check(_bag_n(sim, id, 65210) == 4, "用咗扣一件")
	# SP 藥水 (effect 75)
	var sp_heal: Dictionary = data.heals.get(65158, {})
	check(int(sp_heal.get("sp", 0)) == 100, "綠色藥丸回 100 SP")
	var msp := RulesStats.max_sp(int(ch["level"]), ch["attrs"])
	ch["hp"] = mhp
	ch["sp"] = 1
	sim.ent(id)["hp"] = ch["hp"]
	sim.cmd_debug_give(id, 65158, 1)
	sim.cmd_use_item(id, 65158)
	check(int(ch["sp"]) == mini(msp, 101), "食綠色藥丸: 回 SP")


# ---------- turnin / answer (框架, spec §1.2) ----------
func t_turnin_answer(data: GameData) -> void:
	var ch := RulesStats.create_character(data, "t", "yishi")
	var qc := {"id": "t_collect", "type": "general", "stages": [{"type": "collect", "item": {"id": 61501, "n": 2}, "done": true}], "reward": {"exp": 10}}
	ch["quests"]["t_collect"] = {"stage": 0, "flags": {}}
	RulesShop.add_item(ch["bag"], 61501, 2)
	var r1 := RulesQuest.on_turnin(data, ch, qc)
	check(bool(r1["done"]) and bool(ch["questDone"].get("t_collect", false)), "turnin: 交齊道具完成")
	check(_bag(ch, 61501) == 0, "turnin: 扣咗道具")
	check(int(ch["exp"]) == 10, "turnin: 獎勵 exp")
	var qa := {"id": "t_ask", "type": "general", "stages": [{"type": "ask", "answer": 1, "done": true}]}
	ch["quests"]["t_ask"] = {"stage": 0, "flags": {}}
	var r2 := RulesQuest.on_answer(data, ch, qa, 0)
	check(not bool(r2["changed"]), "answer: 答錯唔推進")
	var r3 := RulesQuest.on_answer(data, ch, qa, 1)
	check(bool(r3["done"]) and bool(ch["questDone"].get("t_ask", false)), "answer: 答啱完成")
	# pre 唔過唔觸發
	var qp := {"id": "t_pre", "type": "newbie", "pre": {"minLevel": 10}, "stages": [{"type": "talk", "npc": "mystery_old", "done": true}]}
	var r4 := RulesQuest.on_npc_talk(data, ch, qp, "mystery_old", 0)
	check(not bool(r4["changed"]) and not (ch["quests"] as Dictionary).has("t_pre"), "pre minLevel 唔過唔觸發")


# ---------- 存檔 roundtrip ----------
func t_roundtrip(data: GameData) -> void:
	var sim := Sim.new(data, 9)
	var id := sim.spawn_player("t")
	_talk(sim, id, "mystery_old")
	_talk(sim, id, "citizen_1")
	check(int(sim.player_ch()["quests"]["newbie_mystery"]["stage"]) == 1, "roundtrip 前: stage 1")
	var s1 := sim.save_string()
	var sim2 := Sim.load_string(data, s1)
	check(sim2 != null, "quest 進度存檔可載入")
	var ch2: Dictionary = sim2.player_ch()
	check((ch2["quests"] as Dictionary).has("newbie_mystery"), "載入後: quest 進度仲喺度")
	check(int(ch2["quests"]["newbie_mystery"]["stage"]) == 1, "載入後: stage 1")
	check(_npc_visible(sim2, "mystery_old"), "載入後: 任務進行中 NPC 常駐")
	var id2 := int(sim2.state["player_id"])
	_talk(sim2, id2, "citizen_2")
	_talk(sim2, id2, "citizen_3")
	check(int(ch2["quests"]["newbie_mystery"]["stage"]) == 2, "載入後可以繼續推進")
	var s2 := sim2.save_string()
	var sim3 := Sim.load_string(data, s2)
	_talk(sim3, int(sim3.state["player_id"]), "mystery_old")
	check(bool(sim3.player_ch()["questDone"].get("newbie_mystery", false)), "載入後完成任務都冇問題")


func _bag(ch: Dictionary, id: int) -> int:
	for b in ch["bag"]:
		if int(b["id"]) == id:
			return int(b["n"])
	return 0