extends SceneTree
# 角色成長場景測試 (spec 01, S01)。跑: Godot --headless --path client --script tests/run_char.gd
# S01a: 安全區自動回復、練兵場小兵免費回 SP、5 級前免費補 HP、HUD 鍵數跟等級

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_safe_regen(data)
	t_wild_no_regen(data)
	t_trainer_restsp(data)
	t_hud_skill_cap()
	t_expert_rules(data)
	t_expert_trade(data)
	t_expert_weather_geo(data)
	t_class_rules(data)
	t_promote_flow(data)
	t_ult_req_tier(data)
	t_weapon_req_tier(data)
	t_expert_tier_boost(data)
	print("[TEST] char: %d, fail %d" % [total, fails])
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


func t_safe_regen(data: GameData) -> void:
	var sim := Sim.new(data, 1)
	var id := sim.spawn_player("t")
	var ch := sim.player_ch()
	_put(sim, id, sim.inn_pos.x, sim.inn_pos.y)     # 客棧一帶 = 安全區
	check(sim.is_safe(int(ch_ent(sim, id)["x"]), int(ch_ent(sim, id)["y"])), "客棧係安全區")
	var mhp := RulesStats.max_hp(int(ch["level"]), ch["attrs"])
	ch["hp"] = 1
	var ticks := int(data.world["regen"]["ticks"])
	for i in ticks:
		sim.step()
	check(int(ch["hp"]) > 1, "安全區: 每 %d tick 回 HP" % ticks)
	ch["hp"] = mhp
	for i in ticks:
		sim.step()
	check(int(ch["hp"]) == mhp, "安全區: 回復封頂喺 max_hp")


func t_wild_no_regen(data: GameData) -> void:
	var sim := Sim.new(data, 2)
	var id := sim.spawn_player("t")
	var ch := sim.player_ch()
	_put(sim, id, 60, 60)                           # 野外 (非安全區)
	check(not sim.is_safe(60, 60), "60,60 係野外")
	ch["hp"] = 1
	var ticks := int(data.world["regen"]["ticks"])
	for i in ticks * 2:
		sim.step()
	check(int(ch["hp"]) == 1, "野外: 唔會自動回復")


func ch_ent(sim: Sim, id: int) -> Dictionary:
	return sim.ent(id)


func t_trainer_restsp(data: GameData) -> void:
	var sim := Sim.new(data, 3)
	var id := sim.spawn_player("t")
	var ch := sim.player_ch()
	var f: Dictionary = data.facilities["trainer"]
	_put(sim, id, int(f["x"]), int(f["y"]))
	var msp := RulesStats.max_sp(int(ch["level"]), ch["attrs"])
	ch["sp"] = 1
	sim.cmd_facility(id, "trainer")
	check(int(ch["sp"]) == msp, "練兵場小兵: 免費回滿 SP")
	ch["sp"] = 1
	sim.cmd_facility(id, "trainer")
	check(int(ch["sp"]) == 1, "練兵場小兵: 冷卻中唔可以再用")


func t_hud_skill_cap() -> void:
	check(HudLayout.skill_cap(1) == 4, "5 級前 4 鍵")
	check(HudLayout.skill_cap(4) == 4, "5 級前 4 鍵 (4 級)")
	check(HudLayout.skill_cap(5) == 6, "5 級後 6 鍵")
	check(HudLayout.skill_cap(50) == 6, "5 級後 6 鍵 (高級)")


# ================= S01c 專長 (spec 01 §8) =================
func t_expert_rules(data: GameData) -> void:
	check(RulesExpert.cap_of(data.experts, "yishi", "kaiken") == 4, "義士開墾上限 4")
	check(RulesExpert.cap_of(data.experts, "yishi", "zhaolai") == 2, "義士招徠上限 2")
	check(RulesExpert.cap_of(data.experts, "yishi", "zhentan") == 0, "偵查表冇 = 未解鎖 (0)")
	var le: Array = data.experts["levelExp"]
	check(RulesExpert.level_of_exp(0, le) == 0, "0 exp = 0 級")
	check(RulesExpert.level_of_exp(9, le) == 0, "未夠門檻 = 0 級")
	check(RulesExpert.level_of_exp(10, le) == 1, "夠 10 = 1 級")
	check(RulesExpert.level_of_exp(100, le) == 4, "夠 100 = 頂級 4")
	check(RulesExpert.eff_level(data.experts, "yishi", "zhaolai", 100) == 2, "生效等級封頂喺職業上限 (100exp 本身 4 級但上限 2)")
	check(RulesExpert.eff_level(data.experts, "yishi", "kaiken", 30) == 2, "生效等級: 30exp = 2 級 (上限 4 夠用)")


func t_expert_trade(data: GameData) -> void:
	var sim := Sim.new(data, 11)
	var id := sim.spawn_player("t")
	var ch := sim.player_ch()
	ch["gold"] = 100000
	var item := 0
	for k in data.prices:
		if float(data.prices[k]) > 0:
			item = int(k)
			break
	check(item != 0, "搵到有價道具做測試")
	check(sim.expert_lv(ch, "jiaoyi") == 0, "未學交易 = 0 級")
	var cost0 := RulesShop.buy_price(data.prices[item], float(ch["attrs"]["cha"]), 0, sim.expert_lv(ch, "jiaoyi"))
	RulesExpert.add_exp(ch, data.experts, "jiaoyi", 100)
	check(sim.expert_lv(ch, "jiaoyi") == RulesExpert.cap_of(data.experts, String(ch["classId"]), "jiaoyi"), "加滿 exp = 封頂喺職業上限")
	var cost1 := RulesShop.buy_price(data.prices[item], float(ch["attrs"]["cha"]), 0, sim.expert_lv(ch, "jiaoyi"))
	check(cost1 <= cost0, "交易專長: 買入價唔會貴過未學")
	if sim.expert_lv(ch, "jiaoyi") > 0:
		check(cost1 < cost0, "交易專長: 有級數就買平啲")
	var sell0 := RulesShop.sell_price(data.prices[item], 0)
	var sell1 := RulesShop.sell_price(data.prices[item], sim.expert_lv(ch, "jiaoyi"))
	check(sell1 >= sell0, "交易專長: 賣出價唔會平過未學")


func t_expert_weather_geo(data: GameData) -> void:
	var sim := Sim.new(data, 12)
	var id := sim.spawn_player("t")
	var ch := sim.player_ch()
	check(sim.view_weather().is_empty(), "未學天文 + 冇渾天儀 = 睇唔到天氣")
	check(not sim.geo_unlocked(), "未學地理 = 未解鎖")
	RulesExpert.add_exp(ch, data.experts, "tianwen", 100)
	check(sim.view_weather().is_empty(), "有天文冇渾天儀 = 都係睇唔到")
	RulesShop.add_item(ch["bag"], sim.WEATHER_ITEM, 1)
	var w := sim.view_weather()
	check(not w.is_empty(), "天文 lv≥1 + 帶渾天儀 = 睇到各城天氣")
	check(w.size() == data.world["cities"].size(), "天氣情報涵蓋全部城池")
	RulesExpert.add_exp(ch, data.experts, "dili", 100)
	check(sim.geo_unlocked(), "學咗地理 = 解鎖")


# ================= S01d 二轉/三轉 (spec 01 §7) =================
func t_class_rules(data: GameData) -> void:
	check(RulesClass.tier_of({}) == 0, "tier_of: 舊存檔冇 tier 欄 = 0")
	check(RulesClass.tier_of({"tier": 2}) == 2, "tier_of: 讀 ch.tier")
	var cls: Dictionary = data.classes["yishi"]
	check(RulesClass.title_of(cls, 0) == "義士", "職名: 初階 = 職業名")
	check(RulesClass.title_of(cls, 1) == "武士", "職名: 二轉 = tier2")
	check(RulesClass.title_of(cls, 2) == "猛將", "職名: 三轉 = tier3")
	check(RulesClass.tier_name_of(1) == "二轉", "階級名")
	check(RulesClass.tier_name_of(-3) == "初階", "階級名 clamp 下限")
	check(RulesClass.weapon_tier_required(50) == 0, "武器職階: req_lv 50 = 初階武器")
	check(RulesClass.weapon_tier_required(51) == 1, "武器職階: req_lv 51 = 要二轉")
	check(RulesClass.weapon_tier_required(99) == 1, "武器職階: req_lv 99 = 要二轉")
	check(RulesClass.weapon_tier_required(100) == 2, "武器職階: req_lv 100 = 要三轉")
	check(RulesClass.expert_cap_bonus(0) == 0 and RulesClass.expert_cap_bonus(1) == 1 and RulesClass.expert_cap_bonus(2) == 2, "專長上限提升: +tier")
	# 絕招資格
	var ult1: Dictionary = data.ult_by_id["fengyi"]     # 四招: reqTier 1
	check(RulesClass.ultimate_usable({"tier": 0, "level": 60}, ult1)["ok"] == false, "四招: 未二轉用唔到")
	check(RulesClass.ultimate_usable({"tier": 1, "level": 60}, ult1)["ok"] == true, "四招: 二轉後用到")
	var ult6: Dictionary = data.ult_by_id["xuanbing"]   # 六招: reqTier 2 + reqLevel 100
	check(RulesClass.ultimate_usable({"tier": 1, "level": 100}, ult6)["ok"] == false, "六招: 要三轉")
	check(RulesClass.ultimate_usable({"tier": 2, "level": 99}, ult6)["ok"] == false, "六招: Lv 唔夠")
	check(RulesClass.ultimate_usable({"tier": 2, "level": 100}, ult6)["ok"] == true, "六招: 三轉 + Lv100 用到")
	# 轉職資格
	var ch := {"tier": 0, "level": 49, "questDone": {}}
	check(RulesClass.promote_ok(data, ch)["ok"] == false, "Lv49 唔可以轉職")
	ch["level"] = 50
	check(RulesClass.promote_ok(data, ch)["ok"] == false, "Lv50 未考考試唔可以轉職")
	ch["questDone"] = {"promote_test": true}
	check(bool(RulesClass.promote_ok(data, ch)["ok"]) and int(RulesClass.promote_ok(data, ch)["tier"]) == 1, "Lv50 + 考試完成 = 可以二轉")
	ch["tier"] = 1
	check(RulesClass.promote_ok(data, ch)["ok"] == false, "二轉後 Lv50 唔可以跳三轉")
	ch["level"] = 100
	check(RulesClass.promote_ok(data, ch)["ok"] == false, "Lv100 無三轉任務 (S04d 接) = 唔可以轉")
	var fake := {"id": "promote_test2", "name": "三轉考驗", "type": "general", "stages": []}
	data.quests.append(fake)
	var ch2 := {"tier": 1, "level": 100, "questDone": {"promote_test2": true}}
	check(bool(RulesClass.promote_ok(data, ch2)["ok"]) and int(RulesClass.promote_ok(data, ch2)["tier"]) == 2, "三轉框架: 有任務完成就 ok")
	data.quests.remove_at(data.quests.size() - 1)
	var ch3 := {"tier": 2, "level": 100, "questDone": {}}
	check(RulesClass.promote_ok(data, ch3)["ok"] == false, "已三轉: 冇得再轉")


func t_promote_flow(data: GameData) -> void:
	var sim := Sim.new(data, 21)
	var id := sim.spawn_player("t")
	var ch: Dictionary = sim.player_ch()
	ch["level"] = 50
	sim._sync_stats(sim.ent(id))
	# 未完成考試 → 轉職拒絕
	sim.cmd_class_promote(id)
	check(bool(ch.get("tier", 0)) == false, "冇考試任務: 轉職拒絕")
	# 接任務 (導師 NPC minLevel 50)
	var npc: Dictionary = data.quest_npcs["promote_master"]
	sim._sync_quest_npcs()           # 導師 minLevel 50，spawn 嗰陣唔 visible，升 50 後要 re-sync
	_put(sim, id, int(npc["x"]) + 1, int(npc["y"]))
	sim.cmd_quest_talk(id, "promote_master")
	check((ch.get("quests", {}) as Dictionary).has("promote_test"), "同導師傾偈 = 接咗轉職考試")
	# 收集 5 塊試煉之證 → 交
	RulesShop.add_item(ch["bag"], 51100, 5)
	_put(sim, id, int(npc["x"]) + 1, int(npc["y"]))
	sim.cmd_quest_turnin(id, "promote_test")
	check(int((ch.get("quests", {}) as Dictionary).get("promote_test", {}).get("stage", -1)) == 2, "交齊證 = 推進到回報階段")
	# 最後回報導師先 done
	_put(sim, id, int(npc["x"]) + 1, int(npc["y"]))
	sim.cmd_quest_talk(id, "promote_master")
	check(bool(ch.get("questDone", {}).get("promote_test", false)), "交齊證 + 回報 = 考試任務完成")
	check(int(ch.get("fame", 0)) == 10, "考試任務獎勵名聲 10")
	# 轉職
	var cls: Dictionary = data.classes["yishi"]
	check(RulesClass.title_of(cls, 0) == "義士", "轉職前職名")
	sim.cmd_class_promote(id)
	check(int(ch["tier"]) == 1, "完成考試 + Lv50 = 轉職成功")
	check(RulesClass.title_of(cls, 1) == "武士", "二轉職名")
	# 三轉框架: 唔存在任務 → 拒絕
	ch["level"] = 100
	sim.cmd_class_promote(id)
	check(int(ch["tier"]) == 1, "冇三轉任務: 三轉拒絕 (S04d 接)")



func _spawn_one(sim: Sim, def_id: int, except_id: int = 0) -> int:
	sim._spawn_mob(def_id)
	var best := 0
	for e in sim.ents.values():
		if e["kind"] == "mob" and int(e["mob"]["def"]) == def_id and int(e["id"]) != except_id:
			if int(e["id"]) > best:
				best = int(e["id"])
	return best


# 絶招職階: 四招要二轉 / 五·六招要三轉 (S01d) + 六招凍結特效
func t_ult_req_tier(data: GameData) -> void:
	var sim := Sim.new(data, 22)
	var id := sim.spawn_player("t")
	var ch: Dictionary = sim.player_ch()
	ch["level"] = 60
	sim._sync_stats(sim.ent(id))
	ch["ultimates"] = ["fengyi", "xuanbing"]
	sim.cmd_debug_give(id, 10042, 1)          # 矛 (cat 3)
	sim.cmd_equip_weapon(id, 10042)
	_put(sim, id, 60, 60)                     # 野外
	var m := _spawn_one(sim, 1001)
	_put(sim, m, 60, 59)
	ch["mp"] = RulesStats.max_mp(60, ch["attrs"])
	ch["sp"] = RulesStats.max_sp(60, ch["attrs"])
	# 未二轉 → 四招用唔到
	sim.cmd_use_ultimate(id, "fengyi")
	check(int(ch["mp"]) == RulesStats.max_mp(60, ch["attrs"]), "四招: 未二轉唔扣 MP")
	# 二轉 → 用得
	ch["tier"] = 1
	sim.cmd_use_ultimate(id, "fengyi")
	check(int(ch["mp"]) < RulesStats.max_mp(60, ch["attrs"]), "四招: 二轉後成功扣 MP")
	# 未三轉 → 六招用唔到
	var mp1 := int(ch["mp"])
	sim.cmd_use_ultimate(id, "xuanbing")
	check(int(ch["mp"]) == mp1, "六招: 未三轉唔扣 MP")
	# 三轉 + Lv100 + 特效凍結
	ch["tier"] = 2
	ch["level"] = 100
	sim._sync_stats(sim.ent(id))
	ch["mp"] = RulesStats.max_mp(100, ch["attrs"])
	ch["sp"] = RulesStats.max_sp(100, ch["attrs"])
	var m2 := _spawn_one(sim, 1001)
	var m2e := sim.ent(m2)
	m2e["hp"] = 100000
	m2e["max_hp"] = 100000
	_put(sim, m2, 60, 59)
	sim.cmd_use_ultimate(id, "xuanbing")
	check(int(m2e["hp"]) < 100000, "六招: 三轉後用到 (打到隻怪)")
	check(RulesSpell.has(m2e.get("status", {}), "freeze", sim.tick), "六招: 特效凍結")


# 進階武器: req_lv 51+ 要二轉 (S01d)
func t_weapon_req_tier(data: GameData) -> void:
	var sim := Sim.new(data, 23)
	var id := sim.spawn_player("t")
	var ch: Dictionary = sim.player_ch()
	ch["level"] = 60
	sim._sync_stats(sim.ent(id))
	var wid := 0
	for k in data.weapons:
		if int(data.cats.get(int(k), 0)) == 1 and int(data.info.get(int(k), {}).get("req_lv", 0)) >= 51:
			wid = int(k)
			break
	check(wid != 0, "搵到 req_lv≥51 嘅刀做測試")
	sim.cmd_debug_give(id, wid, 1)
	sim.cmd_equip_weapon(id, wid)
	check(int(ch["equip"].get("weapon", 0)) != wid, "進階武器: 未二轉裝唔到")
	ch["tier"] = 1
	sim.cmd_equip_weapon(id, wid)
	check(int(ch["equip"].get("weapon", 0)) == wid, "進階武器: 二轉後裝到（解鎖）")


# 專長上限: 二轉 +1 / 三轉 +2 (S01d)
func t_expert_tier_boost(data: GameData) -> void:
	check(RulesExpert.cap_of(data.experts, "yishi", "kaiken", 0) == 4, "初階: 開墾上限 4")
	check(RulesExpert.cap_of(data.experts, "yishi", "kaiken", 1) == 5, "二轉: 開墾上限 5")
	check(RulesExpert.cap_of(data.experts, "yishi", "kaiken", 2) == 6, "三轉: 開墾上限 6")
	check(RulesExpert.cap_of(data.experts, "yishi", "zhentan", 2) == 0, "表冇嘅專長: 轉職都唔解鎖")
	check(RulesExpert.eff_level(data.experts, "yishi", "kaiken", 100, 0) == 4, "4 級 exp 初階封頂 4")
	check(RulesExpert.eff_level(data.experts, "yishi", "kaiken", 150, 1) == 5, "150 exp + 二轉 = 5 級")
	# 交易效果上限: lv6 都封頂 10%【自訂】
	check(RulesExpert.trade_buy_discount(6) == RulesExpert.trade_buy_discount(5), "交易折扣封頂 10% (lv5+ 一樣)")
