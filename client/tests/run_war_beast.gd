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
