extends SceneTree
# 戰騎測試 (Step 18a, spec 07 §8.1~8.2): 10 種戰騎屬性表【原】/ 升級經驗曲線 / 3 種點數表 / 屬性點分配
# 跑: Godot --headless --path client --script tests/run_war_beast.gd   (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	var cfg: Dictionary = data.war_beasts
	t_breeds(cfg)
	t_new_beast(cfg)
	t_exp_curve(cfg)
	t_level_points(cfg)
	t_gain_exp(cfg)
	t_spend_point(cfg)
	t_battle_skills(cfg)
	t_friend_skills(cfg)
	t_loyalty_trade(cfg)
	t_stats(data)
	t_sim_adopt(data)
	t_sim_combat(data)
	t_sim_skill(data)
	t_sim_death(data)
	t_sim_roundtrip(data)
	t_sim_determinism(data)
	t_friend_effects_rules(cfg)
	t_sim_friend_loot(data)
	t_sim_friend_bag(data)
	t_sim_friend_bank(data)
	t_sim_friend_station(data)
	t_sim_friend_death(data)
	t_sim_friend_regen(data)
	t_sim_friend_passives(data)
	t_sim_skill_buff_debuff(data)
	t_sim_friend_view(data)
	t_auction(data)
	t_friend_rest_rules(cfg)
	t_friend_rest_sim(data)
	print("[TEST] war_beast: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


func t_breeds(cfg: Dictionary) -> void:
	var bs: Array = cfg["breeds"]
	check(bs.size() == 10, "十種戰騎【原】(8 已開放 + 2 後期)")
	check(RulesWarBeast.breeds_enabled(cfg).size() == 8, "8 種已開放戰騎【原】")
	for b in bs:
		var a: Dictionary = b["attrs"]
		var sum: int = int(a["pow"]) + int(a["body"]) + int(a["spirit"]) + int(a["agi"])
		check(sum == 19, "%s 四維總和 19【原】(實際 %d)" % [b["name"], sum])
	var niu := RulesWarBeast.breed_def(cfg, "niujiao")
	check(String(niu["bonusAttr"]) == "body", "巨角牛隱藏加成獸體【原】")
	var bao := RulesWarBeast.breed_def(cfg, "canying")
	check(int(bao["attrs"]["agi"]) == 9, "殘影豹獸敏 9【原】")


func t_new_beast(cfg: Dictionary) -> void:
	var wb := RulesWarBeast.new_beast(cfg, "jifeng", 1)
	check(int(wb["level"]) == 1 and int(wb["exp"]) == 0, "新戰騎 1 級 0 經驗")
	check(int(wb["attrs"]["spirit"]) == 7, "疾風狼初始獸靈 = 品種表【原】")
	check(int(wb["attrPts"]) == 0 and int(wb["battlePts"]) == 0 and int(wb["friendPts"]) == 0, "新戰騎冇未分點數")
	check(RulesWarBeast.display_name(cfg, wb) == "疾風狼", "冇改名 = 顯示品種名")
	wb["nick"] = "阿風"
	check(RulesWarBeast.display_name(cfg, wb) == "阿風", "改名後顯示暱稱")


func t_exp_curve(cfg: Dictionary) -> void:
	var e1 := RulesWarBeast.exp_to_next(cfg, 1)
	var e2 := RulesWarBeast.exp_to_next(cfg, 2)
	var e50 := RulesWarBeast.exp_to_next(cfg, 50)
	check(e1 > 0 and e2 > e1, "經驗需求隨級數遞增")
	check(e50 > e2, "高級數需求明顯更高")


func t_level_points(cfg: Dictionary) -> void:
	var r1 := RulesWarBeast.points_for_level(cfg, 1)
	check(int(r1["attrPts"]) == 2 and int(r1["battlePts"]) == 1 and int(r1["friendPts"]) == 2, "1~25 級點數表【原】")
	var r30 := RulesWarBeast.points_for_level(cfg, 30)
	check(int(r30["attrPts"]) == 3 and int(r30["friendPts"]) == 3, "26~50 級點數表【原】")
	var r60 := RulesWarBeast.points_for_level(cfg, 60)
	check(int(r60["attrPts"]) == 6 and int(r60["friendPts"]) == 6, "51~75 級點數表【原】")
	var r90 := RulesWarBeast.points_for_level(cfg, 90)
	check(int(r90["attrPts"]) == 9 and int(r90["friendPts"]) == 9, "76~100 級點數表【原】")


func t_gain_exp(cfg: Dictionary) -> void:
	var wb := RulesWarBeast.new_beast(cfg, "bawang", 1)
	var need := RulesWarBeast.exp_to_next(cfg, 1)
	var ups := RulesWarBeast.gain_exp(cfg, wb, need)
	check(ups == 1 and int(wb["level"]) == 2, "剛好夠經驗 = 升一級")
	check(int(wb["attrPts"]) == 2 and int(wb["battlePts"]) == 1 and int(wb["friendPts"]) == 2, "升級發返 1~25 級點數")
	# 連升多級
	var wb2 := RulesWarBeast.new_beast(cfg, "bawang", 2)
	var big := RulesWarBeast.exp_to_next(cfg, 1) + RulesWarBeast.exp_to_next(cfg, 2) + RulesWarBeast.exp_to_next(cfg, 3) + 5
	var ups2 := RulesWarBeast.gain_exp(cfg, wb2, big)
	check(ups2 == 3 and int(wb2["level"]) == 4, "連升 3 級")
	check(int(wb2["exp"]) == 5, "剩返嘅經驗carry落去")
	check(int(wb2["attrPts"]) == 6, "3 級都喺 1~25 級表，攞 2×3=6 點屬性")
	# 頂級冇經驗溢出
	var wb3 := RulesWarBeast.new_beast(cfg, "yanya", 3)
	wb3["level"] = int(cfg["maxLevel"])
	RulesWarBeast.gain_exp(cfg, wb3, 999999)
	check(int(wb3["exp"]) == 0, "頂級唔再儲經驗")


func t_spend_point(cfg: Dictionary) -> void:
	var wb := RulesWarBeast.new_beast(cfg, "shixue", 1)
	check(RulesWarBeast.point_why(cfg, wb, "pow") == "冇點數可以分配", "冇點分唔到")
	wb["attrPts"] = 2
	var pow0 := int(wb["attrs"]["pow"])
	check(RulesWarBeast.spend_point(cfg, wb, "pow"), "有點分得到")
	check(int(wb["attrs"]["pow"]) == pow0 + 1 and int(wb["attrPts"]) == 1, "分咗一點 pow +1")
	check(RulesWarBeast.point_why(cfg, wb, "unknown") == "冇呢個屬性", "未知屬性拒絕")
	wb["attrPts"] = 999
	wb["attrs"]["pow"] = int(cfg["attrCap"])
	check(RulesWarBeast.point_why(cfg, wb, "pow") != "", "到頂唔畀再分")
	check(not RulesWarBeast.spend_point(cfg, wb, "pow"), "到頂分唔到")


func t_battle_skills(cfg: Dictionary) -> void:
	for b in RulesWarBeast.breeds_enabled(cfg):
		var breed := String(b["id"])
		var list := RulesWarBeast.battle_skills_of(cfg, breed)
		check(list.size() == 6, "%s 有 6 招戰鬥特技【原】" % b["name"])
	var wb := RulesWarBeast.new_beast(cfg, "jifeng", 1)
	check(RulesWarBeast.battle_train_why(cfg, wb, "jifeng_langzhao") == "冇戰鬥技點數", "冇點練唔到")
	wb["battlePts"] = 20
	check(RulesWarBeast.battle_train_why(cfg, wb, "jifeng_fengren") != "", "*招未夠前置級數學唔到")
	for i in range(5):
		check(RulesWarBeast.battle_train(cfg, wb, "jifeng_langzhao"), "狼爪練到 %d 級" % (i + 1))
	check(RulesWarBeast.battle_skill_level(wb, "jifeng_langzhao") == 5, "狼爪已練到 5 級")
	check(RulesWarBeast.battle_train_why(cfg, wb, "jifeng_fengren") == "", "前置夠 5 級可以學風刃")
	check(RulesWarBeast.battle_train(cfg, wb, "jifeng_fengren"), "學到風刃 1 級")
	check(RulesWarBeast.battle_skill_level(wb, "jifeng_fengren") == 1, "風刃 1 級")
	for i in range(4):
		RulesWarBeast.battle_train(cfg, wb, "jifeng_fengren")
	check(RulesWarBeast.battle_skill_level(wb, "jifeng_fengren") == 5, "風刃練到同狼爪一樣 5 級")
	check(RulesWarBeast.battle_train_why(cfg, wb, "jifeng_fengren") != "", "風刃唔可以高過狼爪等級")
	check(not RulesWarBeast.battle_train(cfg, wb, "jifeng_fengren"), "頂住前置等級，練唔到")
	RulesWarBeast.battle_train(cfg, wb, "jifeng_langzhao")
	check(RulesWarBeast.battle_skill_level(wb, "jifeng_langzhao") == 6, "狼爪再練到 6 級")
	check(RulesWarBeast.battle_train(cfg, wb, "jifeng_fengren"), "狼爪夠 6 級，風刃可以追到 6")
	var s := RulesWarBeast.battle_skill_def(cfg, "jifeng", "jifeng_langzhao")
	check(is_equal_approx(RulesWarBeast.skill_value(s, 1), float(s["val"])), "1 級數值 = val")
	check(is_equal_approx(RulesWarBeast.skill_value(s, 3), float(s["val"]) + float(s["valStep"]) * 2.0), "3 級數值 = val + 2×valStep")
	var maxed := {"breed": "jifeng", "battlePts": 999, "battleSkills": {"jifeng_langzhao": int(cfg["battleMaxLv"])}}
	check(RulesWarBeast.battle_train_why(cfg, maxed, "jifeng_langzhao") == "已經頂級", "頂級練唔到")


func t_friend_skills(cfg: Dictionary) -> void:
	for b in RulesWarBeast.breeds_enabled(cfg):
		var breed := String(b["id"])
		var list := RulesWarBeast.friend_skills_of(cfg, breed)
		check(list.size() == 4, "%s 有 4 階友好特技【原】" % b["name"])
		check(int(list[3]["tier"]) == 4, "第四階獨家【原】")
	var wb := RulesWarBeast.new_beast(cfg, "niujiao", 1)
	wb["friendPts"] = 100
	check(RulesWarBeast.friend_train_why(cfg, wb, "niujiao", "niujiao_tianyan") == "要學咗上一階先學得", "唔可以跳階")
	check(RulesWarBeast.friend_cost(cfg, wb, "niujiao", "niujiao_daohang") == 3, "本身品種一階成本 3【原】")
	check(RulesWarBeast.friend_cost(cfg, wb, "niujiao", "niujiao_dundi") == 12, "本身品種三階成本 12【原】")
	check(RulesWarBeast.friend_cost(cfg, wb, "jifeng", "jifeng_tuochu") == 3 * int(cfg["friendCrossMult"]), "跨品種一階成本 ×3【原】")
	check(RulesWarBeast.friend_train(cfg, wb, "niujiao", "niujiao_daohang"), "學到初階導航")
	check(int(wb["friendPts"]) == 97, "扣咗 3 點")
	check(RulesWarBeast.friend_train_why(cfg, wb, "niujiao", "niujiao_daohang") == "已經學咗", "學咗嘅唔可以再學")
	check(RulesWarBeast.friend_train(cfg, wb, "niujiao", "niujiao_tianyan"), "學到咗上一階，二階學得")
	# 忠誠門檻：霸王熊四階忠誠
	var bear := RulesWarBeast.new_beast(cfg, "bawang", 2)
	bear["friendPts"] = 100
	RulesWarBeast.friend_train(cfg, bear, "bawang", "bawang_beifu")
	RulesWarBeast.friend_train(cfg, bear, "bawang", "bawang_shenqi")
	RulesWarBeast.friend_train(cfg, bear, "bawang", "bawang_xuanmiao")
	bear["loyalty"] = 20
	check(RulesWarBeast.friend_train_why(cfg, bear, "bawang", "bawang_zhongcheng") != "", "忠誠唔夠 50 學唔到忠誠特技")
	bear["loyalty"] = 50
	check(RulesWarBeast.friend_train(cfg, bear, "bawang", "bawang_zhongcheng"), "忠誠夠 50 學得到")


func t_loyalty_trade(cfg: Dictionary) -> void:
	var wb := RulesWarBeast.new_beast(cfg, "canying", 1)
	check(int(wb["loyalty"]) == 100, "新戰騎忠誠 100【自訂】")
	for i in range(94):
		RulesWarBeast.on_death(cfg, wb)
	check(int(wb["loyalty"]) == 6, "死亡 94 次跌到 6")
	check(not RulesWarBeast.on_death(cfg, wb), "跌到 5 未到走佬門檻")
	check(int(wb["loyalty"]) == 5, "忠誠 5")
	check(RulesWarBeast.sell_why(cfg, wb, 10) == "", "忠誠剛好 5 = 夠交易")
	for i in range(5):
		RulesWarBeast.on_death(cfg, wb)
	check(int(wb["loyalty"]) == 0, "跌到 0")
	check(RulesWarBeast.sell_why(cfg, wb, 10) != "", "忠誠 <5 唔可以交易【原】")
	var wb2 := RulesWarBeast.new_beast(cfg, "canying", 2)
	check(RulesWarBeast.sell_why(cfg, wb2, 5) != "", "玩家 <10 級唔可以交易【原】")
	check(RulesWarBeast.sell_why(cfg, wb2, 10) == "", "玩家 10 級 + 忠誠夠 = 可以交易")
	wb2["level"] = 10
	check(RulesWarBeast.sell_price(cfg, wb2) == int(cfg["sellBase"]) + 10 * int(cfg["sellPerLevel"]), "賣價跟等級")
# ================= 實戰數值 (S07b) =================
func t_stats(data: GameData) -> void:
	var cfg: Dictionary = data.war_beasts
	var niu := RulesWarBeast.new_beast(cfg, "niujiao", 1)
	var sn := RulesWarBeast.stats_for(cfg, niu)
	var bao := RulesWarBeast.new_beast(cfg, "canying", 2)
	var sb := RulesWarBeast.stats_for(cfg, bao)
	check(int(sn["hpMax"]) > int(sb["hpMax"]), "獸體高 (巨角牛 9) HP 多過 殘影豹 3")
	check(float(sn["atk"]) > float(sb["atk"]), "獸力高攻擊高")
	check(int(sb["spMax"]) > int(sn["spMax"]), "獸靈高 SP 多")
	check(int(sn["interval"]) >= 6, "攻速間隔有下限")
	var lv := RulesWarBeast.new_beast(cfg, "niujiao", 3)
	lv["level"] = 50
	var s50 := RulesWarBeast.stats_for(cfg, lv)
	check(int(s50["hpMax"]) > int(sn["hpMax"]), "等級高 HP 高")
	var p := RulesWarBeast.new_beast(cfg, "bawang", 4)
	var base_atk := float(RulesWarBeast.stats_for(cfg, p)["atk"])
	p["battleSkills"] = {"bawang_juli": 5}
	var boosted := float(RulesWarBeast.stats_for(cfg, p)["atk"])
	check(boosted > base_atk, "passive 巨力加成攻擊")
	check(RulesWarBeast.exp_share(cfg, 100) == int(round(100.0 * float(cfg["beastExpShare"]))), "exp 分享按比例")
	var wb := RulesWarBeast.new_beast(cfg, "jifeng", 5)
	check(RulesWarBeast.pick_skill(cfg, wb, 0, {}, 999, 1.0).is_empty(), "冇學招 = 普通攻擊")
	wb["battleSkills"] = {"jifeng_langzhao": 1}
	check(not RulesWarBeast.pick_skill(cfg, wb, 0, {}, 999, 1.0).is_empty(), "學咗狼爪 → 揀嚟用")
	check(RulesWarBeast.pick_skill(cfg, wb, 0, {}, 0, 1.0).is_empty(), "SP 唔夠唔出招")
	check(RulesWarBeast.pick_skill(cfg, wb, 100, {"jifeng_langzhao": 200}, 999, 1.0).is_empty(), "冷卻中唔出招")
	var fox := RulesWarBeast.new_beast(cfg, "jifeng", 6)
	fox["battleSkills"] = {"jifeng_langzhao": 1, "jifeng_liaoshang": 1}
	var pick := RulesWarBeast.pick_skill(cfg, fox, 0, {}, 999, 0.3)
	check(not pick.is_empty() and String(pick["skill"]["kind"]) == "heal", "血少優先揀療傷")


# ================= sim (S07b) =================
func _new(data: GameData, seed: int) -> Array:
	var sim := Sim.new(data, seed)
	var id := sim.spawn_player("t")
	var ch: Dictionary = sim.player_ch()
	ch["level"] = 30
	ch["gold"] = 500000
	var msgs: Array = []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "msg" and int(ev.get("dst", -1)) == id:
			msgs.append(str(ev["text"])))
	return [sim, id, ch, msgs]


func _put(sim: Sim, id: int, x: int, y: int) -> void:
	var e := sim.ent(id)
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y
	e.erase("path")


func _at_fac(sim: Sim, id: int, key: String) -> void:
	var f: Dictionary = sim.data.facilities[key]
	var p := sim._free_near(int(f["x"]), int(f["y"]))
	_put(sim, id, p.x, p.y)


func _last(msgs: Array) -> String:
	return str(msgs[-1]) if not msgs.is_empty() else ""


func t_sim_adopt(data: GameData) -> void:
	var r := _new(data, 21)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	sim.cmd_beast_adopt(id, "jifeng")
	check(sim._beasts(ch).is_empty() and _last(msgs).contains("馬廄"), "唔喺馬廄馴唔到戰騎")
	_at_fac(sim, id, "stable_xc")
	sim.cmd_beast_adopt(id, "jifeng")
	var list: Array = sim._beasts(ch)
	check(list.size() == 1 and String(list[0]["where"]) == "with", "馴養 → 出戰跟身")
	check(int(ch["gold"]) == 500000 - 15000, "扣 15000 金")
	check(not sim.beast_ent(id).is_empty(), "出戰戰騎有實體")
	sim.cmd_beast_adopt(id, "niujiao")
	check(list.size() == 2 and String(list[1]["where"]) == "stable", "第 2 隻有出戰 → 寄馬廄")
	sim.cmd_beast_adopt(id, "bawang")
	check(list.size() == 3, "養到 3 隻")
	sim.cmd_beast_adopt(id, "canying")
	check(list.size() == 3 and _last(msgs).contains("3"), "最多 3 隻【原】")
	sim.cmd_beast_adopt(id, "shenglin")
	check(list.size() == 3, "未開放品種馴唔到")
	var uid := int(list[0]["uid"])
	sim.cmd_beast_rename(id, uid, "  小風  ")
	check(String(list[0]["nick"]) == "小風", "改名 trim")
	check(String(sim.beast_ent(id)["name"]) == "小風", "改名更新實體名")
	list[0]["attrPts"] = 2
	var pow0 := int(list[0]["attrs"]["pow"])
	sim.cmd_beast_point(id, uid, "pow")
	check(int(list[0]["attrs"]["pow"]) == pow0 + 1 and int(list[0]["attrPts"]) == 1, "屬性點分配")
	var uid2 := int(list[1]["uid"])
	sim.cmd_beast_deploy(id, uid2, true)
	check(String(list[0]["where"]) == "stable" and String(list[1]["where"]) == "with", "出戰切換")
	check(int(sim.beast_ent(id)["uid"]) == uid2, "換咗實體")
	sim.cmd_beast_deploy(id, uid2, false)
	check(String(list[1]["where"]) == "stable" and sim.beast_ent(id).is_empty(), "收回馬廄 → 冇實體")
	list[0]["battlePts"] = 3
	sim.cmd_beast_train(id, uid, "jifeng_fengren")
	check(RulesWarBeast.battle_skill_level(list[0], "jifeng_fengren") == 0, "*招要前置先學到")
	sim.cmd_beast_train(id, uid, "jifeng_langzhao")
	check(RulesWarBeast.battle_skill_level(list[0], "jifeng_langzhao") == 1, "練到狼爪 1 級")
	list[0]["friendPts"] = 5
	sim.cmd_beast_friend_train(id, uid, "jifeng", "jifeng_tuochu")
	check(RulesWarBeast.friend_learned(list[0], "jifeng_tuochu"), "學到友好特技脫出")
	var gold0 := int(ch["gold"])
	sim.cmd_beast_sell(id, uid)
	check(sim._beasts(ch).size() == 2 and int(ch["gold"]) > gold0, "賣戰騎換金")


func t_sim_combat(data: GameData) -> void:
	var r := _new(data, 22)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	sim.init_mobs()
	_at_fac(sim, id, "stable_xc")
	sim.cmd_beast_adopt(id, "bawang")
	var wb: Dictionary = sim._beasts(ch)[0]
	var be_id := int(sim.beast_ent(id)["id"])
	var hits: Array = []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "hit" and int(ev.get("src", -1)) == be_id and int(ev["dmg"]) > 0:
			hits.append(ev))
	_put(sim, id, 30, 30)
	sim._spawn_mob(1001)
	var mob_id := 0
	for e in sim.ents.values():
		if e["kind"] == "mob":
			mob_id = int(e["id"])
			break
	_put(sim, mob_id, 31, 30)
	sim.ent(mob_id)["mob"]["home_x"] = 31
	sim.ent(mob_id)["mob"]["home_y"] = 30
	_put(sim, be_id, 29, 30)
	var exp0 := int(wb["exp"])
	for i in 400:
		sim.step()
		if not sim.ents.has(mob_id):
			break
	check(not hits.is_empty(), "戰騎自動攻擊打中怪")
	check(not sim.ents.has(mob_id), "戰騎幫手殺到怪")
	check(int(wb["exp"]) > exp0 or int(wb["level"]) > 1, "戰騎殺怪吸 exp")


func t_sim_skill(data: GameData) -> void:
	var r := _new(data, 23)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	sim.init_mobs()
	_at_fac(sim, id, "stable_xc")
	sim.cmd_beast_adopt(id, "jifeng")
	var wb: Dictionary = sim._beasts(ch)[0]
	wb["battleSkills"] = {"jifeng_langzhao": 1}
	wb["sp"] = 999
	var used: Array = []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "beast_skill":
			used.append(str(ev["skill"])))
	_put(sim, id, 30, 30)
	sim._spawn_mob(1001)
	var mob_id := 0
	for e in sim.ents.values():
		if e["kind"] == "mob":
			mob_id = int(e["id"])
			break
	_put(sim, mob_id, 31, 30)
	sim.ent(mob_id)["mob"]["home_x"] = 31
	sim.ent(mob_id)["mob"]["home_y"] = 30
	_put(sim, int(sim.beast_ent(id)["id"]), 29, 30)
	for i in 120:
		sim.step()
		if not used.is_empty():
			break
	check(used.has("jifeng_langzhao"), "戰騎出戰鬥特技 (狼爪)")


func t_sim_death(data: GameData) -> void:
	var r := _new(data, 24)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	_at_fac(sim, id, "stable_xc")
	sim.cmd_beast_adopt(id, "niujiao")
	var wb: Dictionary = sim._beasts(ch)[0]
	wb["loyalty"] = 50
	var before := int(wb["loyalty"])
	var be := sim.beast_ent(id)
	sim.damage(be, 999999, sim.ent(id))
	check(sim._beasts(ch).size() == 1, "倒下唔走佬 → 仲喺清單")
	check(int(wb["loyalty"]) == before - 1, "戰鬥死亡忠誠 −1【原】")
	check(String(wb["where"]) == "stable", "倒下送返馬廄")
	check(sim.beast_ent(id).is_empty(), "倒下 → 移除實體")
	var r2 := _new(data, 25)
	var sim2: Sim = r2[0]
	var id2: int = r2[1]
	var ch2: Dictionary = r2[2]
	_at_fac(sim2, id2, "stable_xc")
	sim2.cmd_beast_adopt(id2, "niujiao")
	var wb2: Dictionary = sim2._beasts(ch2)[0]
	wb2["loyalty"] = 1
	sim2.damage(sim2.beast_ent(id2), 999999, sim2.ent(id2))
	check(sim2._beasts(ch2).is_empty(), "忠誠 0 → 走佬消失")


func t_sim_roundtrip(data: GameData) -> void:
	var r := _new(data, 26)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	_at_fac(sim, id, "stable_xc")
	sim.cmd_beast_adopt(id, "jifeng")
	sim.cmd_beast_adopt(id, "bawang")
	sim._beasts(ch)[0]["battleSkills"] = {"jifeng_langzhao": 3}
	var s1 := sim.save_string()
	var sim2 := Sim.load_string(data, s1)
	check(sim2 != null and sim2.save_string() == s1, "戰騎存檔 roundtrip 字串一致")
	var ch2: Dictionary = sim2.player_ch()
	var id2 := int(sim2.state["player_id"])
	check(sim2._beasts(ch2).size() == 2, "載入 2 隻戰騎")
	check(not sim2.beast_ent(id2).is_empty(), "載入後出戰實體重建")
	check(RulesWarBeast.battle_skill_level(sim2._beasts(ch2)[0], "jifeng_langzhao") == 3, "載入後招式等級保留")
	check(not (sim2.beast_view(id2)["list"] as Array).is_empty(), "beast_view 讀到清單")


func t_sim_determinism(data: GameData) -> void:
	check(_script(data) == _script(data), "同種子同操作 → 存檔一致")


func _script(data: GameData) -> String:
	var r := _new(data, 138)
	var sim: Sim = r[0]
	var id: int = r[1]
	sim.init_mobs()
	_at_fac(sim, id, "stable_xc")
	sim.cmd_beast_adopt(id, "bawang")
	_put(sim, id, 30, 30)
	sim._spawn_mob(1001)
	var mob_id := 0
	for e in sim.ents.values():
		if e["kind"] == "mob":
			mob_id = int(e["id"])
			break
	_put(sim, mob_id, 31, 30)
	sim.ent(mob_id)["mob"]["home_x"] = 31
	sim.ent(mob_id)["mob"]["home_y"] = 30
	_put(sim, int(sim.beast_ent(id)["id"]), 29, 30)
	for i in 200:
		sim.step()
	return sim.save_string()

# ================= S07c 友好特技效果接系統 =================
func t_friend_effects_rules(cfg: Dictionary) -> void:
	var wb := RulesWarBeast.new_beast(cfg, "niujiao", 1)
	wb["friendSkills"] = {"niujiao_daohang": true}
	check(RulesWarBeast.has_effect(cfg, wb, "map_city"), "導航 → map_city 效果")
	check(not RulesWarBeast.has_effect(cfg, wb, "auto_loot"), "未學撿寶 → 冇 auto_loot")
	check(is_equal_approx(RulesWarBeast.bag_cap_mult(cfg, wb), 1.0), "冇背負 → 負重倍率 1.0")
	# 跨品種學：殘影豹一階撿寶
	var wb2 := RulesWarBeast.new_beast(cfg, "niujiao", 2)
	wb2["friendSkills"] = {"canying_jianbao": true}
	check(RulesWarBeast.has_effect(cfg, wb2, "auto_loot"), "跨品種學撿寶 → auto_loot")
	# 背負 / 聖體 數值
	var bear := RulesWarBeast.new_beast(cfg, "bawang", 3)
	bear["friendSkills"] = {"bawang_beifu": true}
	check(is_equal_approx(RulesWarBeast.bag_cap_mult(cfg, bear), 1.5), "背負 → 負重上限 ×1.5")
	var fox := RulesWarBeast.new_beast(cfg, "jiuwei", 4)
	fox["friendSkills"] = {"jiuwei_shengti": true}
	check(is_equal_approx(RulesWarBeast.regen_mult(cfg, fox), 2.0), "聖體 → 回復 ×2")
	# 效果集
	var fx := RulesWarBeast.active_effects(cfg, bear)
	check(bool(fx.get("bag_capacity", false)) and not bool(fx.get("bank", false)), "效果集只含已學")


func _learn(sim: Sim, id: int, uid: int, breed: String, skill_id: String) -> void:
	sim._beasts(sim.player_ch())[0]["friendPts"] = 999
	sim.cmd_beast_friend_train(id, uid, breed, skill_id)


func _adopt(data: GameData, seed: int, breed: String) -> Array:
	var r := _new(data, seed)
	var sim: Sim = r[0]
	var id: int = r[1]
	_at_fac(sim, id, "stable_xc")
	sim.cmd_beast_adopt(id, breed)
	return r


func t_sim_friend_loot(data: GameData) -> void:
	var r := _adopt(data, 31, "canying")
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var uid := int(sim._beasts(ch)[0]["uid"])
	_learn(sim, id, uid, "canying", "canying_jianbao")
	_put(sim, id, 30, 30)
	var d := sim._drop_items(31, 30, [{"id": 65008, "n": 2}])
	check(not d.is_empty(), "跌咗件嘢落地")
	var looted: Array = []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "beast_loot":
			looted.append(ev))
	sim.step()
	check(not looted.is_empty(), "戰騎自動執咗地下寶物")
	check(RulesShop.count_item(ch["bag"], 65008) == 2, "執到嘅嘢入咗玩家背包")
	check(sim.ents.get(int(d["id"]), {}).is_empty(), "執晒 → 掉落物消失")


func t_sim_friend_bag(data: GameData) -> void:
	var r := _adopt(data, 32, "bawang")
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var base := int(sim.data.world["dropped"]["capBagWeight"])
	check(sim._bag_cap(ch) == base, "冇背負 → 負重上限 = 底值")
	var uid := int(sim._beasts(ch)[0]["uid"])
	_learn(sim, id, uid, "bawang", "bawang_beifu")
	check(sim._bag_cap(ch) == int(round(float(base) * 1.5)), "背負 → 負重上限 ×1.5")


func t_sim_friend_bank(data: GameData) -> void:
	var r := _adopt(data, 33, "bawang")
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	RulesShop.add_item(ch["bag"], 65016, 2)
	sim.cmd_storage_deposit(id, 65016, 1)
	check(RulesShop.count_item(ch["storage"], 65016) == 0, "冇神奇 + 冇訂閱 → 存唔到")
	var uid := int(sim._beasts(ch)[0]["uid"])
	_learn(sim, id, uid, "bawang", "bawang_beifu")
	_learn(sim, id, uid, "bawang", "bawang_shenqi")
	sim.cmd_storage_deposit(id, 65016, 1)
	check(RulesShop.count_item(ch["storage"], 65016) == 1, "學咗神奇 → 免訂閱存得")
	sim.cmd_storage_withdraw(id, 65016, 1)
	check(RulesShop.count_item(ch["storage"], 65016) == 0, "學咗神奇 → 免訂閱攞返")


func t_sim_friend_station(data: GameData) -> void:
	var r := _adopt(data, 34, "bawang")
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var e := sim.ent(id)
	check(sim.station_near(e) == "", "企喺非驛站位置")
	sim.cmd_station(id, "station_xy")
	check(sim.map_id_at(int(e["x"]), int(e["y"])) != String(sim.data.facilities["station_xy"]["map"]) \
		or sim.station_near(e) != "station_xy", "冇玄妙 → 去唔到 (仍喺原地)")
	var uid := int(sim._beasts(ch)[0]["uid"])
	_learn(sim, id, uid, "bawang", "bawang_beifu")
	_learn(sim, id, uid, "bawang", "bawang_shenqi")
	_learn(sim, id, uid, "bawang", "bawang_xuanmiao")
	var gold0 := int(ch["gold"])
	check(sim.station_view(id).get("remote", false), "station_view 標示 remote")
	sim.cmd_station(id, "station_xy")
	check(sim.station_near(e) == "station_xy", "學咗玄妙 → 喺任何地方去得到驛站")
	check(int(ch["gold"]) < gold0, "遠程驛站照收車費")


func t_sim_friend_death(data: GameData) -> void:
	var r := _adopt(data, 35, "canying")
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var uid := int(sim._beasts(ch)[0]["uid"])
	_learn(sim, id, uid, "canying", "canying_jianbao")
	_learn(sim, id, uid, "canying", "canying_xingyun")
	_learn(sim, id, uid, "canying", "canying_hushen")
	_learn(sim, id, uid, "canying", "canying_huanhun")
	RulesShop.add_item(ch["bag"], 65008, 3)
	ch["exp"] = 100000
	var dies: Array = []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "die":
			dies.append(ev))
	sim._kill_player(sim.ent(id))
	check(dies.size() == 1, "死咗一次")
	var ev: Dictionary = dies[0]
	check(bool(ev["lucky"]), "幸運 → 死亡唔跌物品")
	check(bool(ev["huhushen"]), "護身 → 經驗損失減半")
	check(bool(ev["revived"]), "還魂 → 復活效果")
	check((ev["dropped"] as Array).is_empty(), "冇跌任何嘢")
	check(RulesShop.count_item(ch["bag"], 65008) == 3, "友好技唔消耗道具")


func t_sim_friend_regen(data: GameData) -> void:
	var r := _adopt(data, 36, "jiuwei")
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	check(is_equal_approx(sim._friend_regen_mult(sim.ent(id)), 1.0), "冇聖體 → 回復倍率 1.0")
	var uid := int(sim._beasts(ch)[0]["uid"])
	_learn(sim, id, uid, "jiuwei", "jiuwei_jingang")
	_learn(sim, id, uid, "jiuwei", "jiuwei_shouhu")
	_learn(sim, id, uid, "jiuwei", "jiuwei_shengti")
	check(is_equal_approx(sim._friend_regen_mult(sim.ent(id)), 2.0), "聖體 → 回復倍率 2.0")


func t_sim_friend_passives(data: GameData) -> void:
	var r := _adopt(data, 37, "jiuwei")
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var uid := int(sim._beasts(ch)[0]["uid"])
	_learn(sim, id, uid, "jiuwei", "jiuwei_jingang")
	_learn(sim, id, uid, "jiuwei", "jiuwei_shouhu")
	sim.step()
	var status: Dictionary = ch["status"]
	check(RulesSpell.has(status, "armor1", sim.tick + 1), "金剛 → 護甲術 (armor1) 常駐")
	check(RulesSpell.has(status, "mirror1", sim.tick + 1), "守護 → 護鏡術 (mirror1) 常駐")


func t_sim_skill_buff_debuff(data: GameData) -> void:
	var r := _adopt(data, 38, "jifeng")
	var sim: Sim = r[0]
	var id: int = r[1]
	var be := sim.beast_ent(id)
	sim._beast_add_buff(be, "lifesteal", 0.2, 300)
	sim._beast_add_buff(be, "spellAtk", 0.15, 300)
	check(is_equal_approx(sim._beast_buff_sum(be, "lifesteal"), 0.2), "聖血 → lifesteal buff 生效")
	check(is_equal_approx(sim._beast_buff_sum(be, "spellAtk"), 0.15), "狐仙 → spellAtk buff 生效")
	sim._beast_add_buff(be, "mpRegen", 0.3, 300)
	check(is_equal_approx(sim._beast_buff_sum(be, "mpRegen"), 0.3), "凝神 → mpRegen buff 生效")
	# 過期
	be["beastBuff"]["lifesteal"]["until"] = sim.tick - 1
	check(is_equal_approx(sim._beast_buff_sum(be, "lifesteal"), 0.0), "buff 過期 → 0")
	# debuff 對目標
	var mob := {"kind": "mob", "mob": {"def": 1009}, "level": 5}
	var base := float(data.mob_def(1009)["def"])
	check(base > 0.0, "測試怪有物防")
	sim._apply_beast_debuff(mob, "def", -0.2, 300)
	check(sim._beast_target_def(mob) < base, "破擊/狂吼 → 降敵物防")
	check(is_equal_approx(RulesCombat.debuffed(100.0, {"atk": {"val": -0.2, "until": sim.tick + 10}}, "atk", sim.tick), 80.0),
		"降敵物攻公式 ×0.8")


func t_sim_friend_view(data: GameData) -> void:
	var r := _adopt(data, 39, "bawang")
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var uid := int(sim._beasts(ch)[0]["uid"])
	_learn(sim, id, uid, "bawang", "bawang_beifu")
	var v := sim.beast_view(id)
	check(bool((v["effects"] as Dictionary).get("bag_capacity", false)), "beast_view 透出友好效果")
	check(bool(((v["list"] as Array)[0]["effects"] as Dictionary).get("bag_capacity", false)), "每個戰騎有 effects 欄")


func t_auction(data: GameData) -> void:
	# 生成 + 決定性 + 唔影響主 rng 流
	var a := _new(data, 41)
	var sim: Sim = a[0]
	var id: int = a[1]
	var ch: Dictionary = a[2]
	var msgs: Array = a[3]
	var rng_before := sim.rng.s
	sim._auction_daily(3)
	check(sim.rng.s == rng_before, "拍賣場用獨立 rng：唔影響主 rng 流")
	var b := _new(data, 41)
	var sim2: Sim = b[0]
	sim2._auction_daily(3)
	check(JSON.stringify(sim._auction()["lots"]) == JSON.stringify(sim2._auction()["lots"]), "同種子同 game 日 → 拍賣貨一樣")
	var v := sim.auction_view(id)
	check((v["lots"] as Array).size() == int(sim._aucfg()["slots"]), "拍賣場 slot 數")
	var kinds := {}
	for l in v["lots"]:
		kinds[String(l["kind"])] = true
		check(int(l["price"]) > 0 and String(l["breed"]) != "", "每件貨價格 > 0 + 有品種")
	check(not kinds.is_empty(), "拍賣場有貨")
	var sim3 := Sim.new(data, 41)
	sim3.spawn_player("t")
	sim3._auction_daily(4)
	check(JSON.stringify(sim._auction()["lots"]) != JSON.stringify(sim3._auction()["lots"]), "第 2 日換貨")
	# 唔喺馬廄買唔到
	var lot := {"id": 501, "kind": "beast", "breed": "canying", "name": "殘影豹", "price": 5000, "sex": "", "tamed": false, "level": 5}
	sim._auction()["day"] = int(sim._clock()["day"])
	sim._auction()["lots"] = [lot.duplicate()]
	sim.cmd_auction_buy(id, 501)
	check(_last(msgs).contains("馬廄") and sim._beasts(ch).is_empty(), "唔喺馬廄買唔到拍賣品")
	# 買戰騎 (標等級)
	_at_fac(sim, id, "stable_xc")
	ch["gold"] = 500000
	sim._auction()["lots"] = [lot.duplicate()]
	sim.cmd_auction_buy(id, 501)
	var blist: Array = sim._beasts(ch)
	check(blist.size() == 1 and int(blist[0]["level"]) == 5, "買到 5 級戰騎")
	check(int(ch["gold"]) == 495000, "扣 5000 金")
	check((sim._auction()["lots"] as Array).is_empty(), "賣出後落架")
	check(not sim.beast_ent(id).is_empty(), "第 1 隻即出戰")
	# 已有出戰 → 新戰騎寄馬廄
	sim._auction()["lots"] = [{"id": 502, "kind": "beast", "breed": "jifeng", "name": "疾風狼", "price": 3000, "sex": "", "tamed": false, "level": 1}]
	sim.cmd_auction_buy(id, 502)
	check(sim._beasts(ch).size() == 2 and String(sim._beasts(ch)[1]["where"]) == "stable", "已有出戰 → 新戰騎寄馬廄")
	# 買座騎
	sim._auction()["lots"] = [{"id": 503, "kind": "mount", "breed": "dawan", "name": "火焰紅馬", "price": 6000, "sex": "m", "tamed": true, "level": 0}]
	sim.cmd_auction_buy(id, 503)
	var mlist: Array = sim._mounts(ch)
	check(mlist.size() == 1 and String(mlist[0]["sex"]) == "m" and int(mlist[0]["intimacy"]) == 60, "買到成年公馬 (親密 60)")
	# 唔夠錢 / 滿額
	ch["gold"] = 1
	sim._auction()["lots"] = [lot.duplicate()]
	sim.cmd_auction_buy(id, 501)
	check(_last(msgs).contains("金"), "唔夠錢買唔到")
	ch["gold"] = 500000
	sim._beasts(ch).clear()
	for i in int(sim._wbcfg()["maxOwned"]):
		sim._beasts(ch).append(sim._wrap_wb(sim._wbcfg(), "canying", i + 100))
	sim._auction()["lots"] = [lot.duplicate()]
	sim.cmd_auction_buy(id, 501)
	check(sim._beasts(ch).size() == int(sim._wbcfg()["maxOwned"]), "戰騎滿 3 隻買唔到")
	# 存檔 roundtrip + 舊存檔兼容
	var s := sim.save_string()
	var sim4 := Sim.load_string(data, s)
	check(int(sim4._auction()["day"]) == int(sim._auction()["day"]), "存檔保留拍賣場")
	sim4.state.erase("auction")
	check((sim4.auction_view(int(sim4.state["player_id"]))["lots"] as Array).size() > 0, "舊存檔冇 auction → 即時生成")


# ---- 友好技補齊 (飛影/狂力/開光/野性/巨力/火焰/奇門/脫出/召喚/神行/回城) ----
func _learn_chain(sim: Sim, id: int, breed: String, upto: int) -> void:
	var uid := int(sim._beasts(sim.player_ch())[0]["uid"])
	var list: Array = sim.data.war_beasts["friendSkills"][breed]
	for i in upto:
		_learn(sim, id, uid, breed, String(list[i]["id"]))


func t_friend_rest_rules(cfg: Dictionary) -> void:
	var wb := RulesWarBeast.new_beast(cfg, "yanya", 1)
	wb["friendPts"] = 999
	for sk in ["yanya_huoyan", "yanya_feiying", "yanya_kuangli", "yanya_kaiguang"]:
		RulesWarBeast.friend_train(cfg, wb, "yanya", sk)
	check(RulesWarBeast.attr_plus(cfg, wb, "agi") == 3, "飛影 → 敏 +3")
	check(RulesWarBeast.attr_plus(cfg, wb, "str") == 3, "狂力 → 武力 +3")
	check(RulesWarBeast.attr_plus(cfg, wb, "int") == 3 and RulesWarBeast.attr_plus(cfg, wb, "spi") == 3, "開光 → 智 +3 靈 +3")
	check(RulesWarBeast.attr_plus(cfg, wb, "pol") == 0, "政治唔受影響")
	check(RulesWarBeast.attr_plus(cfg, {}, "agi") == 0, "冇戰騎 → 0")
	var w2 := RulesWarBeast.new_beast(cfg, "shixue", 1)
	check(RulesWarBeast.atk_interval_mult(cfg, w2) == 1.0, "未學野性 → 攻速 ×1")
	w2["friendPts"] = 999
	RulesWarBeast.friend_train(cfg, w2, "shixue", "shixue_xiuxue")
	RulesWarBeast.friend_train(cfg, w2, "shixue", "shixue_yesheng")
	check(is_equal_approx(RulesWarBeast.atk_interval_mult(cfg, w2), 0.8), "野性 → 攻擊間隔 ×0.8")
	var w3 := RulesWarBeast.new_beast(cfg, "changya", 1)
	w3["friendPts"] = 999
	RulesWarBeast.friend_train(cfg, w3, "changya", "changya_juli")
	check(is_equal_approx(RulesWarBeast.bag_cap_mult(cfg, w3), 1.3), "巨力 → 負重 ×1.3")
	for e in ["stealth_noncombat", "maze_escape", "summon_friend", "haste_scroll", "return_scroll"]:
		check(not RulesWarBeast.active_def(cfg, e).is_empty(), "主動友好技有參數: " + e)


func t_friend_rest_sim(data: GameData) -> void:
	# 飛影/狂力/開光: _eff_attr 經戰騎加成
	var r := _adopt(data, 51, "yanya")
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var agi0 := sim._eff_attr(ch, "agi")
	var str0 := sim._eff_attr(ch, "str")
	var int0 := sim._eff_attr(ch, "int")
	_learn_chain(sim, id, "yanya", 4)
	check(sim._eff_attr(ch, "agi") == agi0 + 3 and sim._eff_attr(ch, "str") == str0 + 3 and sim._eff_attr(ch, "int") == int0 + 3,
		"sim: 飛影/狂力/開光 令主人屬性 +3")
	check(bool(sim.beast_effects_view(id).get("light", false)), "火焰: view 透出 light (夜景照明)")
	# 野性: 攻擊間隔
	var r2 := _adopt(data, 52, "shixue")
	var sim2: Sim = r2[0]
	check(sim2._atk_interval_scale(sim2.ent(r2[1]), 20) == 20, "sim: 未學野性 → 間隔不變")
	_learn_chain(sim2, r2[1], "shixue", 2)
	check(sim2._atk_interval_scale(sim2.ent(r2[1]), 20) == 16, "sim: 野性 → 間隔 20 → 16")
	check(sim2._atk_interval_scale(sim2.ent(r2[1]), 6) == 6, "sim: 野性 → 最快仍 6")
	# 巨力
	var r3 := _adopt(data, 53, "changya")
	var sim3: Sim = r3[0]
	var base := int(sim3.data.world["dropped"]["capBagWeight"])
	_learn_chain(sim3, r3[1], "changya", 1)
	check(sim3._bag_cap(r3[2]) == int(round(float(base) * 1.3)), "sim: 巨力 → 負重上限 ×1.3")
	# 奇門
	var r4 := _adopt(data, 54, "niujiao")
	var sim4: Sim = r4[0]
	var id4: int = r4[1]
	var ch4: Dictionary = r4[2]
	sim4.cmd_beast_act(id4, "stealth_noncombat")
	check(not RulesSpell.has(ch4["status"], "qimen", sim4.tick), "未學奇門 → 用唔到")
	_learn_chain(sim4, id4, "niujiao", 4)
	ch4["sp"] = 999
	sim4.cmd_beast_act(id4, "stealth_noncombat")
	check(RulesSpell.has(ch4["status"], "stealth", sim4.tick) and RulesSpell.has(ch4["status"], "qimen", sim4.tick), "奇門 → 隱身狀態")
	check(int(ch4["sp"]) < 999, "奇門消耗 SP")
	var sp_after := int(ch4["sp"])
	sim4.cmd_beast_act(id4, "stealth_noncombat")
	check(int(ch4["sp"]) == sp_after, "奇門冷卻中 → 唔再扣 SP")
	sim4.init_mobs()
	sim4._spawn_mob(1001)
	var mob_id := 0
	for e in sim4.ents.values():
		if e["kind"] == "mob":
			mob_id = int(e["id"])
			break
	sim4.cmd_attack(id4, mob_id)
	check(int(sim4.ent(id4).get("atk_target", 0)) == 0, "奇門隱身中 → 唔可以攻擊")
	sim4.state["tick"] = sim4.tick + 400
	sim4.cmd_attack(id4, mob_id)
	check(int(sim4.ent(id4).get("atk_target", 0)) == mob_id, "奇門過期 → 可以攻擊")
	# 疾風狼四招: 脫出/召喚/神行/回城
	var r5 := _adopt(data, 55, "jifeng")
	var sim5: Sim = r5[0]
	var id5: int = r5[1]
	var ch5: Dictionary = r5[2]
	_learn_chain(sim5, id5, "jifeng", 4)
	ch5["sp"] = 999
	sim5.cmd_beast_act(id5, "maze_escape")
	check(int(ch5["sp"]) == 999, "脫出: 唔喺迷宮/戰役 → 拒絕且唔扣 SP")
	sim5.cmd_beast_act(id5, "summon_friend")
	check(int(ch5["sp"]) == 999, "召喚: 冇同伴 → 拒絕且唔扣 SP")
	var pe := sim5.ent(id5)
	var c: Dictionary = sim5._spawn_companion(pe, data.generals[0])
	ch5["recruit"] = {"comp": int(c["id"])}
	_put(sim5, int(c["id"]), int(pe["x"]) + 12, int(pe["y"]))
	sim5.cmd_beast_act(id5, "summon_friend")
	var cd := maxi(absi(int(c["x"]) - int(pe["x"])), absi(int(c["y"]) - int(pe["y"])))
	check(cd <= 2 and int(ch5["sp"]) < 999, "召喚: 同伴即時趕到身邊 + 扣 SP")
	sim5.cmd_beast_act(id5, "haste_scroll")
	check(RulesSpell.has(ch5["status"], "beast_haste", sim5.tick), "神行 → 加速狀態")
	var steps := 0
	for t in 10:
		sim5.state["tick"] = sim5.tick + 1
		steps += sim5._ride_steps(pe)
	check(steps == 15, "神行 ×1.5 → 10 tick 行 15 格 (實際 %d)" % steps)
	_put(sim5, id5, 30, 30)
	var expect_md: Dictionary = sim5._nearest_city_map(sim5.map_id_at(30, 30))
	sim5.cmd_beast_act(id5, "return_scroll")
	if expect_md.is_empty():
		check(true, "回城: 附近冇城池 (跳過位置檢查)")
	else:
		var ap: Vector2i = sim5._city_anchor(expect_md)
		check(int(pe["x"]) == ap.x and int(pe["y"]) == ap.y, "回城 → 傳返最近城池中心")
