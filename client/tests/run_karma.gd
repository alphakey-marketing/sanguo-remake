extends SceneTree
# S03c 死亡道具測試 (spec 03 §4 + §6): 死亡流程 6 步 / 幸運符 / 護身符 / 還魂丹(天譴無效) / 掉物品表.
# 覆蓋: 純函數 (死經驗兩檔 + 護身符減半 + 掉物品表全檔 + roll_death_drop_items) +
#       sim 死亡流程 ((扣經驗/掉物/回一半/目擊/耐久) + 三件道具消耗 + 還魂丹天譴無效).
# 跑: Godot --headless --path client --script tests/run_karma.gd

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_rules(data)
	t_death_flow(data)
	t_lucky(data)
	t_huhushen(data)
	t_huhun(data)
	t_huhun_tianqian(data)
	print("[TEST] karma/death items: %d, fail %d" % [total, fails])
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


# 野外 (60,60 非安全) 砌玩家; 可選加一個黐身居民做目擊
func _mk(data: GameData, seed: int) -> Array:
	var sim := Sim.new(data, seed)
	var pid := sim.spawn_player("t", "yishi")
	var me: Dictionary = sim.ent(pid)
	_put(sim, pid, 60, 60)
	sim._sync_stats(me)
	var b := sim._spawn_actor("路人", "bot")
	BotSys.init_identity(b, sim.rng)
	_put(sim, int(b["id"]), 59, 60)
	sim._sync_stats(b)
	return [sim, pid, b]


# 次序式 RNG (純函數用)
func _rng(seq: Array) -> Callable:
	var idx := [0]
	return func() -> float:
		var x: float = float(seq[idx[0] % seq.size()])
		idx[0] += 1
		return x


# ===== 純函數 (spec 03 §4.1/§4.2) =====
func t_rules(data: GameData) -> void:
	# 死經驗兩檔【原】: ≥-1000 10% / <-1000 20%
	check(RulesCombat.death_exp_loss(0, 100) == 10, "死經驗: 中性 10%")
	check(RulesCombat.death_exp_loss(-1000, 100) == 10, "死經驗: -1000 邊界 10%")
	check(RulesCombat.death_exp_loss(-1001, 100) == 20, "死經驗: -1001 起 20%")
	# 護身符: 經驗損失減半
	check(RulesCombat.death_exp_loss_protected(-1001, 100, false) == 20, "護身符: 冇帶 = 原數")
	check(RulesCombat.death_exp_loss_protected(-1001, 100, true) == 10, "護身符: 帶咗減半")
	check(RulesCombat.death_exp_loss_protected(0, 99, true) == 5, "護身符: 99*10%=9.9->10, 半=5 (js_round)")
	# 死亡道具 id (items.json cat 250)
	check(RulesCombat.LUCKY_CHARM == 65016 and RulesCombat.PROTECTION_CHARM == 65029 and RulesCombat.REVIVE_PILL == 65030, "死亡道具 item id")
	check(data.item_ids.has(65016) and data.item_ids.has(65029) and data.item_ids.has(65030), "死亡道具喺 items 存在")
	# 掉物品表【原】§4.1 全檔
	var tb: Array = [RulesCombat.death_drop_table(-30000), RulesCombat.death_drop_table(-9000), RulesCombat.death_drop_table(-2000),
		RulesCombat.death_drop_table(0), RulesCombat.death_drop_table(5000), RulesCombat.death_drop_table(12000), RulesCombat.death_drop_table(20000)]
	check(tb[0] == {"max": 7, "p": 0.8}, "掉物表: 殺人魔 7件 0.8")
	check(tb[1] == {"max": 6, "p": 0.8}, "掉物表: 惡人 6件 0.8")
	check(tb[2] == {"max": 3, "p": 0.6}, "掉物表: 罪犯 3件 0.6")
	check(tb[3] == {"max": 1, "p": 0.4}, "掉物表: 中立 1件 0.4")
	check(tb[4] == {"max": 1, "p": 0.3}, "掉物表: 好人 1件 0.3")
	check(tb[5] == {"max": 1, "p": 0.25}, "掉物表: 善人 1件 0.25")
	check(tb[6] == {"max": 1, "p": 0.2}, "掉物表: 大英雄 1件 0.2")
	# roll_death_drop_items: 逐件獨立擲骰 + 上限
	check(RulesCombat.roll_death_drop_items(0, [], _rng([0])) == [], "掉物: 空袋唔跌")
	var drop1 := RulesCombat.roll_death_drop_items(0, [{"id": 5, "n": 1}], _rng([0.0]))
	check(drop1.size() == 1 and drop1[0] == {"id": 5, "n": 1}, "掉物: 中立 roll<0.4 跌 1 件")
	check(RulesCombat.roll_death_drop_items(0, [{"id": 5, "n": 1}], _rng([0.5])) == [], "掉物: 中立 roll≥0.4 唔跌")
	var cap := RulesCombat.roll_death_drop_items(-9000, [{"id": 1, "n": 9}], _rng([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
	check(cap.size() == 6, "掉物: 惡人最多 6 件 (全中但斬 cap)")


# ===== sim 死亡流程 (spec 03 §4.3): 扣經驗 → 掉物 → 倒地【自訂新增】→ 目擊 → 耐久 =====
func t_death_flow(data: GameData) -> void:
	var r := _mk(data, 81)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var b: Dictionary = r[2]
	var ch: Dictionary = sim.player_ch()
	ch["karma"] = 0
	ch["level"] = 10                                     # 高啲級令經驗損失有意義
	ch["exp"] = 500
	var exp_to_next := RulesStats.exp_to_next(int(ch["level"]))
	var exp_before := int(ch["exp"])
	# 攞個 bot 記憶表對照目擊
	var mem: Dictionary = b["mem"]
	# 死亡事件收集 (Array container: GDScript lambda 改唔到外層 var)
	var last_die: Array = [{}]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "die" and int(ev.get("dst", 0)) == pid:
			last_die[0] = ev)
	var p: Dictionary = sim.ent(pid)
	var dx := int(p["x"])
	var dy := int(p["y"])
	var dur_before := int(ch["equip"]["dur"][str(ch["equip"]["weapons"][0])])
	sim.damage(p, 99999, {})                             # 死亡 (無戰鬥, 正常掉物/經驗)
	# 1. 扣經驗 (10%) —— 即時
	check(int(ch["exp"]) == maxi(0, exp_before - RulesCombat.death_exp_loss(0, exp_to_next)), "死: 扣 10%% 經驗 (got %d)" % int(ch["exp"]))
	# 3. 倒地【自訂新增】: 原地(死位) hp=0，未傳送、未回血
	check(bool(p.get("down", false)), "死: 冇復活道具 → 入倒地狀態")
	check(int(p["x"]) == dx and int(p["y"]) == dy, "死: 倒地原地企，未傳送")
	check(int(ch["hp"]) == 0, "死: 倒地 hp=0")
	# 4. 目擊死亡: 附近 bot 好感 +2 (同情)
	check(NpcMemory.affinity(mem, pid) == BotSys.W_SEE_DIE, "死: 附近 NPC 目擊死亡好感 +2")
	# 5. 耐久 -10%【自訂】—— 即時
	check(int(ch["equip"]["dur"][str(ch["equip"]["weapons"][0])]) < dur_before, "死: 武器耐久扣低過之前")
	# 死亡事件帶齊結算欄位
	var die: Dictionary = last_die[0]
	check(die.has("exp_lost") and die.has("dropped") and die.has("revived") and die.has("lucky") and die.has("huhushen") and die.has("down"), "死: die 事件帶結算欄位")
	check(int(die.get("exp_lost", 0)) == RulesCombat.death_exp_loss(0, exp_to_next), "死: die 事件 exp_lost 正確")
	check(bool(die.get("down", false)) == true, "死: die 事件 down=true")
	# 倒地期間唔可以郁
	sim.cmd_move(pid, dx + 1, dy)
	check(int(p["x"]) == dx and int(p["y"]) == dy, "死: 倒地期間唔可以移動")
	# 5 秒 (50 tick) 前撳回城掣冇反應
	sim.cmd_self_revive(pid)
	check(bool(p.get("down", false)), "死: 未夠 5 秒撳回城復活冇反應")
	for _i in 50:
		sim.step()
	sim.cmd_self_revive(pid)
	check(not bool(p.get("down", false)), "死: 5 秒後撳回城復活 → 成功")
	check(int(p["x"]) == sim.inn_pos.x and int(p["y"]) == sim.inn_pos.y, "死: 回城復活傳返客棧")
	check(int(ch["hp"]) == maxi(1, MathX.js_round(sim._eff_max_hp(ch) / 2.0)), "死: 回城復活 HP 回一半")
	check(int(ch["mp"]) == maxi(0, MathX.js_round(sim._eff_max_mp(ch) / 2.0)), "死: 回城復活 MP 回一半")


# ===== 幸運符: 死亡唔掉物品, 消耗 1 =====
func t_lucky(data: GameData) -> void:
	var r := _mk(data, 82)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = sim.player_ch()
	ch["karma"] = -30000                                  # 高跌物機會
	sim.cmd_debug_give(pid, 65210, 3)                     # 燻魚 x3 (未裝上身)
	sim.cmd_debug_give(pid, 65016, 1)                     # 幸運符
	var fish_before := RulesShop.count_item(ch["bag"], 65210)   # 開場已有 5 件 → 用 before 對照
	var last_die: Array = [{}]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "die" and int(ev.get("dst", 0)) == pid:
			last_die[0] = ev)
	sim.damage(sim.ent(pid), 99999, {})
	check(RulesShop.count_item(ch["bag"], 65210) == fish_before, "幸運符: 燻魚冇跌")
	check(RulesShop.count_item(ch["bag"], 65016) == 0, "幸運符: 消耗 1")
	var die0: Dictionary = last_die[0]
	check(bool(die0.get("lucky", false)), "幸運符: die 事件 lucky=true")
	check((die0.get("dropped", []) as Array).is_empty(), "幸運符: dropped 空")


# ===== 護身符: 經驗損失減半, 消耗 1 =====
func t_huhushen(data: GameData) -> void:
	var r := _mk(data, 83)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = sim.player_ch()
	ch["karma"] = -1001                                   # 20% 經驗檔
	ch["level"] = 10
	sim.cmd_debug_give(pid, 65029, 1)                     # 護身符
	var exp_before := int(ch["exp"])
	var last_die: Array = [{}]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "die" and int(ev.get("dst", 0)) == pid:
			last_die[0] = ev)
	sim.damage(sim.ent(pid), 99999, {})
	var expect := RulesCombat.death_exp_loss_protected(-1001, RulesStats.exp_to_next(10), true)
	check(int(ch["exp"]) == maxi(0, exp_before - expect), "護身符: 經驗損失減半 (扣 %d)" % expect)
	check(RulesShop.count_item(ch["bag"], 65029) == 0, "護身符: 消耗 1")
	check(bool((last_die[0] as Dictionary).get("huhushen", false)), "護身符: die 事件 huhushen=true")


# ===== 還魂丹: 死亡即客棧復活 (物品/經驗照掉), 消耗 1 =====
func t_huhun(data: GameData) -> void:
	var r := _mk(data, 84)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = sim.player_ch()
	ch["exp"] = 300                                    # 有經驗先測到「照掉」
	sim.cmd_debug_give(pid, 65030, 2)                     # 還魂丹 x2
	var exp_before := int(ch["exp"])
	var last_die: Array = [{}]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "die" and int(ev.get("dst", 0)) == pid:
			last_die[0] = ev)
	sim.damage(sim.ent(pid), 99999, {})
	check(RulesShop.count_item(ch["bag"], 65030) == 1, "還魂丹: 死一次消耗 1 (2->1)")
	check(bool((last_die[0] as Dictionary).get("revived", false)), "還魂丹: die 事件 revived=true")
	check(int(ch["exp"]) < exp_before, "還魂丹: 經驗照掉 (復活唔保經)")
	check(int(sim.ent(pid)["x"]) == sim.inn_pos.x, "還魂丹: 復活喺客棧")


# ===== 還魂丹對天譴無效: 殺善居民遭天譴 -> 唔會消耗還魂丹 =====
func t_huhun_tianqian(data: GameData) -> void:
	var r := _mk(data, 85)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var b: Dictionary = r[2]
	var ch: Dictionary = sim.player_ch()
	ch["karma"] = 0
	sim.cmd_debug_give(pid, 65030, 1)                     # 帶還魂丹
	var bid := int(b["id"])
	sim.ent(bid)["hp"] = 1
	sim.ent(bid)["ch"]["hp"] = 1
	var got_tianqian: Array = [false]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "tianqian" and int(ev.get("dst", 0)) == pid:
			got_tianqian[0] = true)
	sim.cmd_attack(pid, bid)
	for _i in 60:
		sim.step()
		if bool(got_tianqian[0]):
			break
	check(bool(got_tianqian[0]), "天譴: 殺善居民觸發天譴")
	check(RulesShop.count_item(ch["bag"], 65030) == 1, "天譴: 還魂丹冇消耗 (對天譴無效)")
	check(bool(ch.get("tianqian", false)), "天譴: tianqian 旗已設")
