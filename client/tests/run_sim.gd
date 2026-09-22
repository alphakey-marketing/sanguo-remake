extends SceneTree
# sim 場景測試 (headless): 跑 Godot --headless --path client --script tests/run_sim.gd   (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_walk(data)
	t_blocked(data)
	t_kill_mob(data)
	t_death(data)
	t_facilities(data)
	t_determinism(data)
	t_save_roundtrip(data)
	t_bots_live(data)
	t_karma_tiers()
	t_npc_memory()
	t_npc_witness(data)
	t_karma_price()
	t_npc_brain()
	t_npc_react_integration(data)
	t_work_rules()
	t_work_sim(data)
	t_market_wired_to_shop(data)
	t_storage(data)
	t_use_item(data)
	print("[TEST] sim scenarios: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


func t_karma_tiers() -> void:
	var cases := [[30000, "大英雄"], [16001, "大英雄"], [16000, "善人"], [8001, "善人"], [8000, "好人"], [1001, "好人"],
		[1000, "中立"], [0, "中立"], [-1000, "中立"], [-1001, "罪犯"], [-8000, "罪犯"], [-8001, "惡人"],
		[-16000, "惡人"], [-16001, "殺人魔"], [-30000, "殺人魔"]]
	for c in cases:
		check(RulesKarma.tier_name(int(c[0])) == c[1], "善惡階 %d → %s" % [c[0], c[1]])


func _put(sim: Sim, id: int, x: int, y: int) -> void:
	var e := sim.ent(id)
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y


func t_walk(data: GameData) -> void:
	var sim := Sim.new(data, 1)
	var id := sim.spawn_player("t")
	_put(sim, id, 5, 5)
	sim.cmd_move(id, 8, 5)
	sim.step()
	check(int(sim.ent(id)["x"]) == 6, "走路: 一 tick 一格")
	sim.step()
	sim.step()
	check(int(sim.ent(id)["x"]) == 8, "走路: 三 tick 到 8")


func t_blocked(data: GameData) -> void:
	var sim := Sim.new(data, 1)
	var id := sim.spawn_player("t")
	check(not sim.is_free(15, 20), "阻擋格 (15,20)")
	sim.cmd_move(id, 15, 20)
	var e := sim.ent(id)
	check(not (int(e["tx"]) == 15 and int(e["ty"]) == 20), "阻擋格唔可以做目標")


func t_kill_mob(data: GameData) -> void:
	var sim := Sim.new(data, 7)
	var id := sim.spawn_player("t")
	_put(sim, id, 30, 30)
	sim._spawn_mob(1001)       # 田鼠
	var mob_id := 0
	for e in sim.ents.values():
		if e["kind"] == "mob":
			mob_id = int(e["id"])
	_put(sim, mob_id, 31, 30)
	sim.ent(mob_id)["mob"]["home_x"] = 31
	sim.ent(mob_id)["mob"]["home_y"] = 30
	var kills := []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "kill":
			kills.append(ev))
	sim.cmd_attack(id, mob_id)
	for i in 300:
		sim.step()
		if not kills.is_empty():
			break
	var ch := sim.player_ch()
	check(kills.size() == 1, "殺怪: 收到 kill 事件")
	check(int(ch["exp"]) > 0 or int(ch["level"]) > 1, "殺怪: 經驗增加")
	check(not sim.ents.has(mob_id), "殺怪: 怪已移除")
	check(sim.state["respawns"].size() == 1, "殺怪: 排入重生")


func t_death(data: GameData) -> void:
	var sim := Sim.new(data, 3)
	var id := sim.spawn_player("t")
	_put(sim, id, 30, 30)
	var ch := sim.player_ch()
	ch["hp"] = 1
	sim._sync_stats(sim.ent(id))
	sim._spawn_mob(1005)       # 最強嗰隻
	var mob_id := 0
	for e in sim.ents.values():
		if e["kind"] == "mob":
			mob_id = int(e["id"])
	_put(sim, mob_id, 31, 30)
	sim.ent(mob_id)["mob"]["state"] = "chase"
	sim.ent(mob_id)["mob"]["target"] = id
	var died := []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "die":
			died.append(ev))
	for i in 100:
		sim.step()
		if not died.is_empty():
			break
	var e := sim.ent(id)
	check(died.size() == 1, "死亡: 收到 die 事件")
	check(int(e["x"]) == sim.inn_pos.x and int(e["y"]) == sim.inn_pos.y, "死亡: 返客棧")
	check(int(e["hp"]) == int(e["max_hp"]), "死亡: 回滿血")


func t_facilities(data: GameData) -> void:
	var sim := Sim.new(data, 5)
	var id := sim.spawn_player("t")
	var ch := sim.player_ch()
	_put(sim, id, 30, 30)
	ch["gold"] = 100
	sim.cmd_rest(id)
	check(int(ch["gold"]) == 100, "休息: 遠離客棧唔扣錢")
	_put(sim, id, sim.inn_pos.x, sim.inn_pos.y)
	ch["hp"] = 1
	sim.cmd_rest(id)
	check(int(ch["gold"]) == 100 - int(data.inn["restCost"]), "休息: 扣住宿費")
	check(int(ch["hp"]) == RulesStats.max_hp(int(ch["level"]), ch["attrs"]), "休息: 回滿 HP")
	var shop: Dictionary = data.shops[0]
	_put(sim, id, int(shop["x"]), int(shop["y"]))
	var item := int(shop["stock"][1])
	ch["gold"] = 100000
	var gold0 := int(ch["gold"])
	var cost := RulesShop.buy_price(data.prices[item], ch["attrs"]["cha"])
	sim.cmd_buy(id, item, 1)
	check(int(ch["gold"]) == gold0 - cost, "買: 扣錢 (魅力折扣價)")
	var have := 0
	for b in ch["bag"]:
		if int(b["id"]) == item:
			have = int(b["n"])
	check(have >= 1, "買: 背包有貨")
	sim.cmd_sell(id, item, 1)
	check(int(ch["gold"]) == gold0 - cost + RulesShop.sell_price(data.prices[item]), "賣: 收 50% 價")


func _run_scripted(data: GameData, seed_value: int, ticks: int) -> Sim:
	var sim := Sim.new(data, seed_value)
	sim.init_mobs()
	sim.add_bots(10)
	var id := sim.spawn_player("玩家")
	sim.cmd_move(id, 35, 35)
	for i in ticks:
		if i % 50 == 0:
			for e in sim.ents.values():
				if e["kind"] == "mob":
					sim.cmd_attack(id, int(e["id"]))
					break
		sim.step()
	return sim


func t_determinism(data: GameData) -> void:
	var a := _run_scripted(data, 42, 600)
	var b := _run_scripted(data, 42, 600)
	var c := _run_scripted(data, 43, 600)
	check(a.save_string() == b.save_string(), "同種子 600 tick 狀態一致")
	check(a.save_string() != c.save_string(), "唔同種子狀態唔同")


func t_save_roundtrip(data: GameData) -> void:
	var a := _run_scripted(data, 9, 300)
	var s := a.save_string()
	var b := Sim.load_string(data, s)
	check(b != null and b.save_string() == s, "存檔 → 讀檔 → 再存檔一致")
	for i in 200:
		a.step()
		b.step()
	check(a.save_string() == b.save_string(), "讀檔後續跑 200 tick 同原本一致")


func t_bots_live(data: GameData) -> void:
	var sim := Sim.new(data, 11)
	sim.init_mobs()
	sim.add_bots(10)
	var kills := [0]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "kill":
			kills[0] += 1)
	for i in 3000:
		sim.step()
	check(kills[0] > 0, "機械人 3000 tick 內有殺怪 (kills=%d)" % kills[0])


func t_npc_memory() -> void:
	var mem := NpcMemory.init_memory()
	check(NpcMemory.affinity(mem, 99) == 0, "記憶表: 未接觸過好感=0")
	NpcMemory.witness(mem, 5, "greet", 10, 2)
	check(NpcMemory.affinity(mem, 5) == 2, "記憶表: 打招呼好感+2")
	NpcMemory.witness(mem, 5, "greet", 20, 2)
	check(NpcMemory.affinity(mem, 5) == 4, "記憶表: 好感累加")
	check(mem["events"].size() == 2, "記憶表: 事件有記低")
	for i in 20:
		NpcMemory.witness(mem, 5, "greet", i, 1)
	check(mem["events"].size() == NpcMemory.CAP, "記憶表: 事件上限 %d，舊事件擠走" % NpcMemory.CAP)
	NpcMemory.witness(mem, 6, "see_kill", 1, 1000)
	check(NpcMemory.affinity(mem, 6) == NpcMemory.AFFINITY_MAX, "記憶表: 好感 clamp 上限")


func t_npc_witness(data: GameData) -> void:
	var sim := Sim.new(data, 4)
	var pid := sim.spawn_player("t")
	_put(sim, pid, 30, 30)
	sim.add_bots(1)
	var bot_id: int = int(sim.state["bots"][0])
	_put(sim, bot_id, 32, 30)                              # 附近 (WITNESS_RANGE 內)
	var ch: Dictionary = sim.ent(bot_id)["ch"]
	check(ch.get("ideology", "") in BotSys.IDEOLOGIES, "居民: 有派理念")
	check(sim.ent(bot_id).has("mem"), "居民: 有記憶表")
	sim.cmd_chat(pid, "你好")
	check(NpcMemory.affinity(sim.ent(bot_id)["mem"], pid) == BotSys.W_GREET, "居民: 附近打招呼觸發目擊+好感")
	_put(sim, bot_id, 60, 60)                               # 移出目擊範圍
	sim._spawn_mob(1001)
	var mob_id := 0
	for e in sim.ents.values():
		if e["kind"] == "mob":
			mob_id = int(e["id"])
	_put(sim, mob_id, 31, 30)
	sim.cmd_attack(pid, mob_id)
	for i in 300:
		sim.step()
		if not sim.ents.has(mob_id):
			break
	check(NpcMemory.affinity(sim.ent(bot_id)["mem"], pid) == BotSys.W_GREET, "居民: 出咗範圍唔會目擊到殺怪")
	var s := sim.save_string()
	var loaded := Sim.load_string(data, s)
	check(NpcMemory.affinity(loaded.ent(bot_id)["mem"], pid) == BotSys.W_GREET, "居民: 記憶表存讀檔一致")


func t_karma_price() -> void:
	var base := 100.0
	check(RulesShop.buy_price(base, 0, 0) == 100, "善惡買價: 中立冇加成")
	check(RulesShop.buy_price(base, 0, -1000) == 100, "善惡買價: 中立下限都冇加成")
	check(RulesShop.buy_price(base, 0, -1001) == 110, "善惡買價: 罪犯 +10%")
	check(RulesShop.buy_price(base, 0, -8001) == 120, "善惡買價: 惡人 +20%")
	check(RulesShop.buy_price(base, 0, -16001) == 130, "善惡買價: 殺人魔 +30%")


func t_npc_brain() -> void:
	var neutral := NpcBrain.decide({"actor_name": "阿明", "affinity": 0, "karma_tier": 3})
	check(neutral["action"] == "greet", "brain: 中立好感 → 打招呼")
	var warm := NpcBrain.decide({"actor_name": "阿明", "affinity": 15, "karma_tier": 3})
	check(warm["action"] == "greet" and warm["line"].contains("阿明"), "brain: 高好感 → 熱情打招呼")
	var cold := NpcBrain.decide({"actor_name": "阿明", "affinity": -25, "karma_tier": 3})
	check(cold["action"] == "warn", "brain: 低好感 → 警戒")
	var villain := NpcBrain.decide({"actor_name": "阿明", "affinity": 0, "karma_tier": 6})
	check(villain["action"] == "warn", "brain: 殺人魔階級 → 警戒 (蓋過好感)")
	for a in [neutral, warm, cold, villain]:
		check(NpcBrain.ACTIONS.has(a["action"]), "brain: 輸出動作喺白名單入面")


func t_npc_react_integration(data: GameData) -> void:
	var sim := Sim.new(data, 2)
	var pid := sim.spawn_player("t")
	_put(sim, pid, 30, 30)
	sim.add_bots(1)
	var bot_id: int = int(sim.state["bots"][0])
	_put(sim, bot_id, 31, 30)
	var says := []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "npc_say":
			says.append(ev))
	sim.cmd_chat(pid, "你好")
	check(says.size() == 1, "居民: 打招呼後有 NPC 回應事件")
	check(NpcBrain.ACTIONS.has(says[0]["action"]), "居民: 回應動作喺白名單入面")
	var ch: Dictionary = sim.player_ch()
	ch["karma"] = -20000                                    # 殺人魔
	says.clear()
	sim.cmd_chat(pid, "你好")
	check(says.size() == 1 and says[0]["action"] == "warn", "居民: 殺人魔玩家打招呼 → 居民警戒")


func t_work_rules() -> void:
	check(RulesWork.unlocked_tiers(1, [1, 3, 6, 10]) == 1, "工作: Lv1 解鎖第 1 tier")
	check(RulesWork.unlocked_tiers(5, [1, 3, 6, 10]) == 2, "工作: Lv5 解鎖到第 2 tier")
	check(RulesWork.unlocked_tiers(999, [1, 3, 6, 10]) == 4, "工作: 高等級解鎖晒")
	var seq := _rng_seq([0.0, 0.99])
	check(RulesWork.roll_tier(3, seq) == 0, "工作: rng=0 揀最低 tier")
	var seq2 := _rng_seq([0.99])
	var t := RulesWork.roll_tier(3, seq2)
	check(t >= 0 and t < 3, "工作: roll_tier 結果喺範圍內")
	check(RulesWork.durability_after_use(1) == 0, "工作: 耐久用到 0")
	check(RulesWork.durability_after_use(0) == 0, "工作: 耐久唔會負數")
	check(RulesWork.sp_cost(100) == 10, "工作: SP 消耗 = 10% max_sp")


func _rng_seq(vals: Array) -> Callable:
	var idx := [0]
	return func() -> float:
		var v: float = float(vals[idx[0] % vals.size()])
		idx[0] += 1
		return v


func t_work_sim(data: GameData) -> void:
	var sim := Sim.new(data, 6)
	var pid := sim.spawn_player("t")
	_put(sim, pid, 30, 30)                                  # field_1 (unsafe)
	var ch: Dictionary = sim.player_ch()
	var sk: Dictionary = data.work["mining"]
	var bag0: int = ch["bag"].size()
	sim.cmd_work(pid, "mining")
	check(ch["bag"].size() == bag0, "工作: 未夠等級唔可以做")
	ch["level"] = 10
	sim.cmd_work(pid, "mining")
	check(ch["bag"].size() == bag0, "工作: 冇工具唔可以做")
	RulesShop.add_item(ch["bag"], int(sk["starterTool"]), 1)
	sim.cmd_equip_tool(pid, "mining", int(sk["starterTool"]))
	check(int(ch["tools"]["mining"]["dur"]) == int(data.work_meta["toolDurability"]["starter"]), "工作: 裝備新手工具耐久啱")
	var sp0 := int(ch["sp"])
	sim.cmd_work(pid, "mining")
	var mat_ids: Array = []
	for m in sk["materials"]:
		mat_ids.append(int(m))
	var got := false
	for b in ch["bag"]:
		if mat_ids.has(int(b["id"])):
			got = true
	check(got, "工作: 採到礦材")
	check(int(ch["sp"]) < sp0, "工作: 扣咗 SP")
	check(int(ch["tools"]["mining"]["dur"]) == int(data.work_meta["toolDurability"]["starter"]) - 1, "工作: 工具耐久 -1")
	_put(sim, pid, 10, 10)                                   # town (safe)
	var bag_before: int = ch["bag"].size()
	sim.cmd_work(pid, "mining")
	check(ch["bag"].size() == bag_before, "工作: 城內唔可以工作")
	_put(sim, pid, 30, 30)
	var dur := int(ch["tools"]["mining"]["dur"])
	for i in dur:
		ch["sp"] = 999999                                    # 測試唔理 SP 限制，淨係試耐久
		sim.cmd_work(pid, "mining")
	check(not ch["tools"].has("mining"), "工作: 耐久用晒工具爛咗要重裝")
	var s := sim.save_string()
	var loaded := Sim.load_string(data, s)
	check(loaded.player_ch()["bag"].size() == ch["bag"].size(), "工作: 存讀檔背包一致")


# 補 Step 4.5 缺口: 商店買賣原先冇真正乘市場價因子 (pf 一直冇讀)，而家接返
func t_market_wired_to_shop(data: GameData) -> void:
	var sim := Sim.new(data, 8)
	var id := sim.spawn_player("t")
	var shop: Dictionary = data.shops[0]
	_put(sim, id, int(shop["x"]), int(shop["y"]))
	var item := int(shop["stock"][1])
	var cat := str(int(data.cats.get(item, 0)))
	check(data.world["market"]["cats"].has(cat), "市場: 測試貨品要喺已定義 cat 入面")
	var ch: Dictionary = sim.player_ch()
	ch["gold"] = 1000000
	var home := str(data.world["homeCity"])
	check(absf(sim.market_factor(item) - 1.0) < 0.0001, "市場: 未跑日仔 pf=1.0")
	var g0 := int(ch["gold"])
	sim.cmd_buy(id, item, 1)
	var cost_normal := g0 - int(ch["gold"])
	sim.state["market"][home][cat]["pf"] = 2.0
	g0 = int(ch["gold"])
	sim.cmd_buy(id, item, 1)
	var cost_high := g0 - int(ch["gold"])
	check(cost_high > cost_normal * 1.8, "市場: pf=2.0 買價貴近一倍 (接返 market_factor)")
	sim.state["market"][home][cat]["pf"] = 0.5
	RulesShop.add_item(ch["bag"], item, 1)
	var g1 := int(ch["gold"])
	sim.cmd_sell(id, item, 1)
	var gain_low := int(ch["gold"]) - g1
	sim.state["market"][home][cat]["pf"] = 1.0
	RulesShop.add_item(ch["bag"], item, 1)
	g1 = int(ch["gold"])
	sim.cmd_sell(id, item, 1)
	var gain_normal := int(ch["gold"]) - g1
	check(gain_low < gain_normal, "市場: pf=0.5 賣價平過正常 (接返 market_factor)")


func t_storage(data: GameData) -> void:
	var sim := Sim.new(data, 9)
	var id := sim.spawn_player("t")
	_put(sim, id, 30, 30)                                     # 野區，唔近商店
	var ch: Dictionary = sim.player_ch()
	var item := 25007                                          # 玄鐵礦石 (礦石材料，price 30，賣出價 > 0)
	RulesShop.add_item(ch["bag"], item, 5)
	sim.cmd_storage_deposit(id, item, 2)
	check(int(ch["bag"][0]["n"]) == 5, "天地商行: 未訂閱唔可以存")
	sim.cmd_storage_sub(id, true)
	check(bool(ch["storageSub"]), "天地商行: 訂閱成功")
	sim.cmd_storage_deposit(id, item, 2)
	var bag_n := 0
	for b in ch["bag"]:
		if int(b["id"]) == item: bag_n = int(b["n"])
	check(bag_n == 3, "天地商行: 存咗 2 件，背包剩 3")
	var store_n := 0
	for b in ch["storage"]:
		if int(b["id"]) == item: store_n = int(b["n"])
	check(store_n == 2, "天地商行: 倉庫有 2 件")
	sim.cmd_storage_withdraw(id, item, 1)
	store_n = 0
	for b in ch["storage"]:
		if int(b["id"]) == item: store_n = int(b["n"])
	check(store_n == 1, "天地商行: 攞返 1 件後倉庫剩 1")
	var g0 := int(ch["gold"])
	sim.cmd_storage_sell(id, item, 1)                          # 唔使喺商店附近都賣得
	check(int(ch["gold"]) > g0, "天地商行: 代賣隨時隨地都得")
	ch["gold"] = 500
	sim._daily_hook(1)
	check(int(ch["gold"]) == 500 - int(data.world["storageFee"]), "天地商行: 子時扣日費")
	ch["gold"] = 10
	sim._daily_hook(2)
	check(not bool(ch["storageSub"]), "天地商行: 唔夠錢自動退訂")
	var s := sim.save_string()
	var loaded := Sim.load_string(data, s)
	check(loaded.player_ch()["storage"].size() == ch["storage"].size(), "天地商行: 存讀檔倉庫一致")


func t_use_item(data: GameData) -> void:
	var sim := Sim.new(data, 10)
	var id := sim.spawn_player("t")
	_put(sim, id, 30, 30)
	var ch: Dictionary = sim.player_ch()
	var weapon := int(ch["equip"].get("weapon", 10001))
	RulesShop.add_item(ch["bag"], weapon, 1)
	sim.cmd_use_item(id, weapon)
	var bag_n := 0
	for b in ch["bag"]:
		if int(b["id"]) == weapon: bag_n = int(b["n"])
	check(bag_n >= 1, "食用: 唔食得嘅物品 (武器) 唔會扣背包")
	var food := 29054                                          # 燻魚, heal_hp=80
	RulesShop.add_item(ch["bag"], food, 1)
	ch["hp"] = 1
	sim.cmd_use_item(id, food)
	check(int(ch["hp"]) == 81, "食用: 食物回 80 HP")
	var bag_food := 0
	for b in ch["bag"]:
		if int(b["id"]) == food: bag_food = int(b["n"])
	check(bag_food == 0, "食用: 扣咗背包果件")
	var mhp := RulesStats.max_hp(int(ch["level"]), ch["attrs"])
	ch["hp"] = mhp - 5
	RulesShop.add_item(ch["bag"], food, 1)
	sim.cmd_use_item(id, food)
	check(int(ch["hp"]) == mhp, "食用: 回血封頂喺 max_hp")
	var potion := 28001                                        # 通靈藥, heal_mp=5
	RulesShop.add_item(ch["bag"], potion, 1)
	ch["mp"] = 0
	sim.cmd_use_item(id, potion)
	check(int(ch["mp"]) == 5, "食用: 藥丸回 5 MP")
	var s := sim.save_string()
	var loaded := Sim.load_string(data, s)
	check(loaded.player_ch()["hp"] == ch["hp"], "食用: 存讀檔一致")
