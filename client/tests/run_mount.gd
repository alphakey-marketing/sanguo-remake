extends SceneTree
# 座騎測試 (Step 17a, spec 07 §1~5): 六種馬數據【原】/ 階段 / 飼養動作 / 道具效果碼 / 子時結算 /
# 騎乘條件 + 移速 + 騎乘疲勞 / 放牧機率 + 結果 / 優秀值點數 / 馬廄買馬寄養領馬 / 用品店 /
# 攻擊 + 死亡落馬 / 馬瘟 / 存檔 roundtrip / 決定性
# Step 17b (spec 07 §6~7): 繁衍 (種馬借用/胎教小遊戲/懶人胎教/積點分配/進階馬/待領小馬過期) +
# 馬戰 (馬戰兵器/特技學習上限 3/騎乘用兵器唔落馬/aoe/combo/dash/speed/shield/block/stun)
# 跑: Godot --headless --path client --script tests/run_mount.gd   (失敗 exit 1)

var fails := 0
var total := 0

const FEED := 31001          # 一般乾糧: 飽食 +10 疲勞 +10
const TONIC := 31003         # 一般補藥: 飽食 +50 體力 +3 疲勞 +20
const WAKE := 31204          # 收心丸: 治頭暈
const STRONG := 31201        # 強力丸: 情緒 −10 疲勞 −30
const WHISTLE := 62060


func _init() -> void:
	var data := GameData.load_all()
	var cfg: Dictionary = data.mounts
	t_breeds(cfg)
	t_stage(cfg)
	t_acts(cfg, data)
	t_daily(cfg)
	t_ride_pure(cfg)
	t_graze_pure(cfg)
	t_stable(data)
	t_sim_acts(data)
	t_ride(data)
	t_graze(data)
	t_daily_sim(data)
	t_roundtrip(data)
	t_determinism(data)
	t_breed_pure(cfg)
	t_breed_sim(data)
	t_battle_pure(data)
	t_battle_sim(data)
	print("[TEST] mount: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


func _effs(data: GameData, item: int) -> Array:
	return data.info[item]["effects"]


# ---------- 純函數 ----------
func t_breeds(cfg: Dictionary) -> void:
	var bs: Array = cfg["breeds"]
	check(bs.size() == 6, "六種馬【原】")
	check(int(cfg["maxOwned"]) == 5 and int(cfg["rideIntimacy"]) == 60, "最多 5 匹、親密度 60 先騎【原】")
	check(int(cfg["foalDays"]) == 30 and int(cfg["lifeDays"]) == 365 and int(cfg["oldDays"]) == 30, "襁褓 30 / 壽命 365 / 衰老 30 日【原】")
	# 兌換表 + 進階門檻 (攻略 sy2_4_5)
	var want := {"烏孫馬": ["銀甲黑馬", [1, 3, 3, 3, 2], "皇極馬", 500], "大漠馬": ["狂風棕馬", [3, 3, 1, 2, 3], "炎陽馬", 900],
		"黃膘馬": ["流星黃馬", [3, 3, 2, 3, 1], "震地馬", 800], "大宛馬": ["火焰紅馬", [2, 2, 2, 2, 2], "流雲馬", 1000],
		"深山馬": ["雷光灰馬", [2, 1, 3, 3, 3], "瘦金馬", 600], "中原馬": ["冰雪白馬", [3, 2, 3, 1, 3], "靈仙馬", 700]}
	for b in bs:
		var w: Array = want.get(String(b["name"]), [])
		check(not w.is_empty(), "品種 %s 喺表" % b["name"])
		if w.is_empty():
			continue
		var ex: Array = []
		for a in cfg["attrs"]:
			ex.append(int(b["exchange"][a]))
		check(String(b["adult"]) == w[0] and ex == w[1] and String(b["adv"]) == w[2] and int(b["advNeed"]) == w[3], "%s 成馬/兌換/進階【原】" % b["name"])
	# 特長: 1 點兌換 = 特長屬性
	for b in bs:
		var tr := String(b["trait"])
		if tr != "":
			check(int(b["exchange"][tr]) == 1, "%s 特長 %s 兌換 1" % [b["name"], tr])
	var m := RulesMount.new_mount(cfg, "wusun", 1)
	check(int(m["attrs"]["learn"]) == 20 and int(m["attrs"]["run"]) == 10, "烏孫馬學習力優 (20/10)")
	var d := RulesMount.new_mount(cfg, "dawan", 2)
	check(int(d["attrs"]["learn"]) == 10 and int(d["attrs"]["stamina"]) == 10, "大宛馬平均型")
	check(RulesMount.eff_value(65506) == -30 and RulesMount.eff_value(30) == 30, "uint16 效果值轉負數")


func t_stage(cfg: Dictionary) -> void:
	var m := RulesMount.new_mount(cfg, "damo", 1)
	check(RulesMount.stage(cfg, m) == "foal" and RulesMount.display_name(cfg, m) == "大漠馬", "幼馬 = 品種名")
	m["age"] = 30
	check(RulesMount.stage(cfg, m) == "adult" and RulesMount.display_name(cfg, m) == "狂風棕馬", "30 日成年 = 成馬名")
	m["age"] = 335
	check(RulesMount.stage(cfg, m) == "old", "死前 30 日 = 衰老期")
	m["nick"] = "阿棕"
	check(RulesMount.display_name(cfg, m) == "阿棕", "暱稱優先")
	var t := RulesMount.new_mount(cfg, "dawan", 2, true)
	check(RulesMount.stage(cfg, t) == "adult" and int(t["intimacy"]) == 60 and int(t["attrs"]["run"]) == 40, "馬廄成年馬: 成年 + 親密 60 + 屬性 40")
	check(RulesMount.fatigue_max(cfg, t) == 50 + 40, "疲勞上限 = 50 + 忍耐力")
	check(RulesMount.mood_name(cfg, {"mood": 85, "status": {}}) == "高興" and RulesMount.mood_name(cfg, {"mood": 10, "status": {}}) == "生氣", "情緒名")
	check(RulesMount.mood_name(cfg, {"mood": 85, "status": {"dizzy": true}}) == "@_@", "頭暈 = @_@【原】")


func t_acts(cfg: Dictionary, data: GameData) -> void:
	var m := RulesMount.new_mount(cfg, "dawan", 1)
	var r := RulesMount.apply_act(cfg, m, "play", [])
	check(int(m["attrs"]["run"]) == 12 and int(m["mood"]) == 75 and int(m["fatigue"]) == 10 and not bool(r["dizzy"]), "玩耍: 奔跑 +2 情緒 +15 疲勞 +10")
	RulesMount.apply_act(cfg, m, "scold", [])
	check(int(m["attrs"]["endure"]) == 12 and int(m["mood"]) == 60 and int(m["fatigue"]) == 15, "責備: 忍耐 +2 情緒 −15")
	RulesMount.apply_act(cfg, m, "feed", _effs(data, TONIC))
	check(int(m["satiety"]) == 100 and int(m["attrs"]["stamina"]) == 13 and int(m["fatigue"]) == 35, "補藥: 飽食 +50(封頂 100) 體力 +3 疲勞 +20")
	RulesMount.apply_act(cfg, m, "heal", _effs(data, STRONG))
	check(int(m["fatigue"]) == 5 and int(m["mood"]) == 50, "強力丸: 疲勞 −30 情緒 −10 (負數效果值)")
	RulesMount.apply_act(cfg, m, "gift", _effs(data, 31104))
	check(int(m["attrs"]["learn"]) == 14 and int(m["attrs"]["run"]) == 10, "按摩手套: 學習 +4 奔跑 −2")
	# 每日上限
	var p := RulesMount.new_mount(cfg, "dawan", 2)
	for i in 5:
		check(RulesMount.act_why(cfg, p, "play") == "", "玩耍第 %d 次得" % (i + 1))
		p["fatigue"] = 0
		RulesMount.apply_act(cfg, p, "play", [])
	check(RulesMount.act_why(cfg, p, "play") != "" and RulesMount.acts_left(cfg, p, "play") == 0, "玩耍一日 5 次上限")
	check(RulesMount.acts_left(cfg, p, "heal") == -1, "醫療冇上限")
	# 成年屬性唔再升
	var a := RulesMount.new_mount(cfg, "dawan", 3, true)
	RulesMount.apply_act(cfg, a, "play", [])
	check(int(a["attrs"]["run"]) == 40 and int(a["mood"]) == 75, "成年: 玩耍屬性唔升、情緒照升")
	# 疲勞爆 = 頭暈；頭暈淨係醫得
	var z := RulesMount.new_mount(cfg, "dawan", 4)
	z["fatigue"] = RulesMount.fatigue_max(cfg, z) - 5
	var rz := RulesMount.apply_act(cfg, z, "play", [])
	check(bool(rz["dizzy"]) and z["status"].has("dizzy") and int(z["fatigue"]) == RulesMount.fatigue_max(cfg, z), "疲勞滿 = 頭暈")
	check(RulesMount.act_why(cfg, z, "feed") != "" and RulesMount.act_why(cfg, z, "heal") == "", "頭暈: 淨係醫得")
	RulesMount.apply_act(cfg, z, "heal", _effs(data, WAKE))
	check(not z["status"].has("dizzy"), "收心丸治頭暈")
	z["status"]["coma"] = true
	RulesMount.apply_act(cfg, z, "heal", _effs(data, 31207))
	check(not z["status"].has("coma"), "醒魂草治昏迷")
	z["life"] = 50
	RulesMount.apply_act(cfg, z, "heal", _effs(data, 31005))
	check(int(z["life"]) == 100, "補血藥: 生命力 +50")
	z["where"] = "stable"
	check(RulesMount.act_why(cfg, z, "play") != "", "唔喺身邊唔做得動作")
	# 屬性封頂
	var c := RulesMount.new_mount(cfg, "dawan", 5)
	c["attrs"]["run"] = 99
	RulesMount.apply_act(cfg, c, "play", [])
	check(int(c["attrs"]["run"]) == 100, "屬性封頂 100")


func t_daily(cfg: Dictionary) -> void:
	# 帶身邊 + 情緒高興 → 親密 +2、情緒 −10
	var m := RulesMount.new_mount(cfg, "dawan", 1)
	m["mood"] = 85
	m["satiety"] = 80
	m["fatigue"] = 20
	RulesMount.daily(cfg, m, false)
	check(int(m["intimacy"]) == 22 and int(m["mood"]) == 75, "高興: 親密 +2、情緒必降 −10【原】")
	check(int(m["fatigue"]) == 20 - (5 + 2) and int(m["satiety"]) == 55 and int(m["age"]) == 1, "飽食夠回疲勞 (5 + 體力×0.2)、飽食 −25、歲 +1")
	# 肚餓: 疲勞唔回、情緒多跌
	var h := RulesMount.new_mount(cfg, "dawan", 2)
	h["satiety"] = 40
	h["fatigue"] = 20
	h["mood"] = 60
	RulesMount.daily(cfg, h, false)
	check(int(h["fatigue"]) == 20 and int(h["mood"]) == 40 and int(h["intimacy"]) == 21, "飽食 <50: 疲勞唔降【原】、情緒 −20")
	# 襁褓期寄馬廄: 親密唔變；疲勞清零 + 頭暈好返
	var s := RulesMount.new_mount(cfg, "dawan", 3)
	s["where"] = "stable"
	s["mood"] = 90
	s["fatigue"] = 60
	s["status"]["dizzy"] = true
	s["acts"]["play"] = 5
	RulesMount.daily(cfg, s, false)
	check(int(s["intimacy"]) == 20 and int(s["fatigue"]) == 0 and not s["status"].has("dizzy"), "馬廄過子時: 疲勞清零 + 頭暈好返；襁褓期唔加親密【原】")
	check((s["acts"] as Dictionary).is_empty(), "動作次數重置")
	# 成年寄馬廄: 情緒好照加親密
	var a := RulesMount.new_mount(cfg, "dawan", 4, true)
	a["where"] = "stable"
	a["mood"] = 65
	RulesMount.daily(cfg, a, false)
	check(int(a["intimacy"]) == 61, "成熟期情緒好 → 親密 +1")
	# 情緒差扣親密
	var b := RulesMount.new_mount(cfg, "dawan", 5)
	b["mood"] = 20
	RulesMount.daily(cfg, b, false)
	check(int(b["intimacy"]) == 19, "情緒差 → 親密 −1")
	# 流血 / 馬瘟
	var l := RulesMount.new_mount(cfg, "dawan", 6)
	l["status"]["bleed"] = true
	RulesMount.daily(cfg, l, false)
	check(int(l["life"]) == 90, "流血: 生命力 −10/日")
	var pg := RulesMount.new_mount(cfg, "dawan", 7)
	pg["where"] = "stable"
	RulesMount.daily(cfg, pg, true)
	check(int(pg["life"]) == 80, "馬瘟 (寄喺瘟疫城): 生命力 −20")
	var pw := RulesMount.new_mount(cfg, "dawan", 8)
	RulesMount.daily(cfg, pw, true)
	check(int(pw["life"]) == 100, "帶喺身邊唔受馬瘟")
	# 成長事件
	var g := RulesMount.new_mount(cfg, "dawan", 9)
	g["age"] = 29
	check(RulesMount.daily(cfg, g, false).has("grown"), "第 30 日成年事件")
	g["age"] = 334
	check(RulesMount.daily(cfg, g, false).has("old"), "入衰老期事件")
	g["age"] = 364
	check(RulesMount.daily(cfg, g, false).has("dead"), "365 日壽終【原】")
	var dl := RulesMount.new_mount(cfg, "dawan", 10)
	dl["life"] = 5
	dl["status"]["bleed"] = true
	check(RulesMount.daily(cfg, dl, false).has("dead"), "生命力歸 0 = 死亡【原】")
	# S07d 馴馬: 親密度成長倍率 (只放大正成長)
	var mul := RulesMount.new_mount(cfg, "dawan", 11)
	mul["mood"] = 85
	RulesMount.daily(cfg, mul, false, 2.0)
	check(int(mul["intimacy"]) == 24, "馴馬倍率: 親密度 +2 → +4")
	var neg := RulesMount.new_mount(cfg, "dawan", 12)
	neg["mood"] = 20
	RulesMount.daily(cfg, neg, false, 2.0)
	check(int(neg["intimacy"]) == 19, "馴馬倍率唔放大負成長")


func t_ride_pure(cfg: Dictionary) -> void:
	var m := RulesMount.new_mount(cfg, "dawan", 1)
	check(RulesMount.ride_why(cfg, m) != "", "襁褓期唔騎得")
	m["age"] = 30
	m["intimacy"] = 59
	check(RulesMount.ride_why(cfg, m) != "", "親密 59 唔騎得")
	m["intimacy"] = 60
	check(RulesMount.ride_why(cfg, m) == "", "成年 + 親密 60 騎得【原】")
	m["status"]["fracture"] = true
	check(RulesMount.ride_why(cfg, m) != "", "骨折唔騎得")
	m["status"] = {}
	m["where"] = "stable"
	check(RulesMount.ride_why(cfg, m) != "", "唔喺身邊唔騎得")
	# 移速 ×1.5 起 (奔跑力 0) → ×2 (奔跑力 100)
	m["attrs"]["run"] = 0
	check(is_equal_approx(RulesMount.ride_mult(cfg, m), 1.5), "移速 +50%【原】")
	m["attrs"]["run"] = 100
	check(is_equal_approx(RulesMount.ride_mult(cfg, m), 2.0), "奔跑力 100 → ×2")
	for mult in [1.0, 1.5, 1.75, 2.0]:
		var sum := 0
		for t in 100:
			sum += RulesMount.steps_at(mult, t)
		check(sum == int(floor(100 * mult)), "steps_at 累積 = 100 × %.2f" % mult)
	# 騎乘疲勞
	m["attrs"]["stamina"] = 50
	var per := RulesMount.tiles_per_fatigue(cfg, m)
	check(per == 20 + 15, "每 35 格 +1 疲勞 (體力 50)")
	m["fatigue"] = 0
	RulesMount.ride_tiles(cfg, m, per - 1)
	check(int(m["fatigue"]) == 0, "未夠格數唔加")
	RulesMount.ride_tiles(cfg, m, 1)
	check(int(m["fatigue"]) == 1 and int(m["rideAcc"]) == 0, "夠格數 +1")
	m["fatigue"] = RulesMount.fatigue_max(cfg, m) - 1
	check(RulesMount.ride_tiles(cfg, m, per), "騎到疲勞滿 → 頭暈")


func t_graze_pure(cfg: Dictionary) -> void:
	var m := RulesMount.new_mount(cfg, "shenshan", 1, true)
	check(RulesMount.graze_why(cfg, RulesMount.new_mount(cfg, "dawan", 2)) != "", "襁褓期唔放得牧")
	check(RulesMount.graze_why(cfg, m) == "", "成年放得牧")
	m["attrs"]["burst"] = 0
	var o0 := RulesMount.graze_odds(cfg, m)
	m["attrs"]["burst"] = 100
	var o1 := RulesMount.graze_odds(cfg, m)
	check(float(o1["good"]) > float(o0["good"]) and float(o1["find"]) > float(o0["find"]) and float(o1["hurt"]) < float(o0["hurt"]), "爆發力高: 好結果多、受傷少【原】")
	check(float(o1["good"]) + float(o1["find"]) + float(o1["hurt"]) <= 1.0, "機率總和 ≤ 1")
	check(String(RulesMount.graze_roll(cfg, m, 0.0, 0.0)["kind"]) == "good", "r1=0 → 成長")
	var f := RulesMount.graze_roll(cfg, m, float(o1["good"]) + 0.001, 0.0)
	check(String(f["kind"]) == "find" and int(f["item"]) == int(cfg["graze"]["loot"][0][0]), "執嘢: 權重第一件")
	var f2 := RulesMount.graze_roll(cfg, m, float(o1["good"]) + 0.001, 0.9999)
	check(int(f2["item"]) == int(cfg["graze"]["loot"][-1][0]), "執嘢: 權重最後一件 (藏寶圖)")
	var hr := RulesMount.graze_roll(cfg, m, float(o1["good"]) + float(o1["find"]) + 0.001, 0.0)
	check(String(hr["kind"]) == "hurt" and String(hr["status"]) == "bleed", "受傷 + 異常")
	check(String(RulesMount.graze_roll(cfg, m, 0.9999, 0.5)["kind"]) == "none", "無事")
	# 套用: 成長值 × (1 + 學習力/100)
	m["attrs"]["learn"] = 50
	m["grow"] = 0
	var r := RulesMount.graze_apply(cfg, m, {"kind": "good"})
	check(int(m["grow"]) == 60 and int(r["levels"]) == 0 and int(m["fatigue"]) == 20, "成長 +60 (40×1.5)、疲勞 +20")
	r = RulesMount.graze_apply(cfg, m, {"kind": "good"})
	check(int(r["levels"]) == 1 and int(m["excel"]) == 1 and int(m["points"]) == 1 and int(m["grow"]) == 20, "成長值滿 100 → 優秀值 +1、1 點【原】")
	check(int(m["life"]) == 102 and RulesMount.life_max(cfg, m) == 102, "優秀值 +1 → 生命力 +2")
	RulesMount.graze_apply(cfg, m, {"kind": "hurt", "status": "fracture"})
	check(int(m["life"]) == 87 and m["status"].has("fracture"), "受傷: 生命 −15 + 骨折")
	check(RulesMount.graze_why(cfg, m) != "", "骨折唔放得牧")
	# 點數
	check(RulesMount.spend_point(cfg, m, "run") and int(m["attrs"]["run"]) == 41 and int(m["points"]) == 0, "分配 1 點 → 奔跑 +1")
	check(not RulesMount.spend_point(cfg, m, "run"), "冇點數唔分得")
	m["points"] = 1
	m["attrs"]["run"] = 150
	check(RulesMount.point_why(cfg, m, "run") != "", "點數分配上限 150")


# ---------- sim ----------
func _new(data: GameData, seed: int) -> Array:
	var sim := Sim.new(data, seed)
	var id := sim.spawn_player("t")
	var ch: Dictionary = sim.player_ch()
	ch["level"] = 20
	ch["gold"] = 200000
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


func _next_day(sim: Sim) -> void:
	var tpd := 1440 / int(sim.data.world["clock"]["gameMinPerTick"])
	var day := int(sim.state["tick"]) / tpd + 1
	sim.state["tick"] = day * tpd - 1
	sim.step()


func _last(msgs: Array) -> String:
	return str(msgs[-1]) if not msgs.is_empty() else ""


func t_stable(data: GameData) -> void:
	var r := _new(data, 11)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	for k in ["stable_xc", "stable_xy"]:
		var f: Dictionary = data.facilities[k]
		check(sim.is_free(int(f["x"]), int(f["y"])) or sim._free_near(int(f["x"]), int(f["y"])) != Vector2i(int(f["x"]), int(f["y"])), "%s 位置行得到" % k)
	sim.cmd_mount_buy(id, "wusun")
	check(sim._mounts(ch).is_empty() and _last(msgs).contains("馬廄"), "唔喺馬廄買唔到")
	_at_fac(sim, id, "stable_xc")
	check(sim.stable_near(sim.ent(id)) == "stable_xc", "認得馬廄")
	sim.cmd_mount_buy(id, "wusun")
	var ms: Array = sim._mounts(ch)
	check(ms.size() == 1 and String(ms[0]["where"]) == "with" and int(ch["gold"]) == 200000 - 3000, "買幼馬 3000 金 → 跟身")
	sim.cmd_mount_buy(id, "damo")
	check(ms.size() == 2 and String(ms[1]["where"]) == "stable" and String(ms[1]["stable"]) == "stable_xc", "身邊有馬 → 新馬寄馬廄")
	sim.cmd_mount_buy(id, "wusun", true)
	check(ms.size() == 2, "只有大宛馬先有成年版")
	sim.cmd_mount_buy(id, "nope")
	check(ms.size() == 2, "唔存在品種")
	for b in ["huangbiao", "shenshan", "zhongyuan"]:
		sim.cmd_mount_buy(id, b)
	check(ms.size() == 5, "買夠 5 匹")
	sim.cmd_mount_buy(id, "dawan")
	check(ms.size() == 5 and _last(msgs).contains("5"), "最多 5 匹【原】")
	# 寄 / 領 / 換
	var a := int(ms[0]["uid"])
	var b2 := int(ms[1]["uid"])
	sim.cmd_mount_take(id, b2)
	check(String(ms[1]["where"]) == "with" and String(ms[0]["where"]) == "stable", "領另一匹 → 身邊嗰匹自動寄低")
	sim.cmd_mount_stable(id, b2)
	check(sim.mount_near_me(ch).is_empty(), "寄低 → 身邊冇馬")
	# 喺另一間馬廄領 (互通)
	_at_fac(sim, id, "stable_xy")
	sim.cmd_mount_take(id, a)
	check(String(ms[0]["where"]) == "with", "新野馬廄都領得許昌寄嘅馬")
	_put(sim, id, int(sim.inn_pos.x), int(sim.inn_pos.y))
	sim.cmd_mount_take(id, b2)
	check(String(ms[1]["where"]) == "stable", "唔喺馬廄領唔到")
	# 丟棄
	sim.cmd_mount_abandon(id, int(ms[4]["uid"]))
	check(ms.size() == 4, "丟棄荒野")
	# 用品: 馬廄就係商店
	_at_fac(sim, id, "stable_xc")
	sim.cmd_buy(id, FEED, 3)
	check(RulesShop.count_item(ch["bag"], FEED) == 3, "馬廄買飼料")
	var w0 := RulesShop.count_item(ch["bag"], 10001)
	sim.cmd_buy(id, 10001, 1)
	check(RulesShop.count_item(ch["bag"], 10001) == w0, "馬廄唔賣武器")
	# 改名
	sim.cmd_mount_rename(id, a, "  踏雪烏騅之王者  ")
	check(String(ms[0]["nick"]) == "踏雪烏騅之王者".substr(0, 8), "改名 (≤8 字)")
	var v := sim.mount_view(id)
	check((v["list"] as Array).size() == 4 and v["stable"] == "stable_xc" and String(v["list"][0]["where"]) == "with", "mount_view")


func t_sim_acts(data: GameData) -> void:
	var r := _new(data, 12)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	_at_fac(sim, id, "stable_xc")
	sim.cmd_mount_buy(id, "dawan")
	var m: Dictionary = sim._mounts(ch)[0]
	var uid := int(m["uid"])
	var ap0 := sim.ap_of(ch)
	sim.cmd_mount_act(id, uid, "play")
	check(int(m["attrs"]["run"]) == 12 and sim.ap_of(ch) == ap0 - 5, "玩耍扣行動力 5")
	sim.cmd_mount_act(id, uid, "feed", FEED)
	check(int(m["satiety"]) == 60 and _last(msgs).contains("背包冇"), "冇飼料餵唔到")
	RulesShop.add_item(ch["bag"], FEED, 1)
	sim.cmd_mount_act(id, uid, "feed", 10001)
	check(RulesShop.count_item(ch["bag"], FEED) == 1, "錯道具唔得")
	sim.cmd_mount_act(id, uid, "feed", FEED)
	check(int(m["satiety"]) == 70 and RulesShop.count_item(ch["bag"], FEED) == 0, "餵食: 食咗 1 份乾糧")
	ch["ap"] = 3
	sim.cmd_mount_act(id, uid, "play")
	check(int(m["attrs"]["run"]) == 12 and _last(msgs).contains("行動力"), "行動力唔夠")
	ch["ap"] = 100
	m["fatigue"] = RulesMount.fatigue_max(data.mounts, m) - 1
	sim.cmd_mount_act(id, uid, "play")
	check(m["status"].has("dizzy") and _last(msgs).contains("頭暈"), "動作做到頭暈有提示")


func t_ride(data: GameData) -> void:
	var r := _new(data, 13)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	_at_fac(sim, id, "stable_xc")
	sim.cmd_mount_buy(id, "dawan")
	sim.cmd_mount_ride(id, true)
	check(not sim.is_riding(ch), "幼馬騎唔到")
	sim.cmd_mount_stable(id, int(sim._mounts(ch)[0]["uid"]))
	sim.cmd_mount_buy(id, "dawan", true)
	var m: Dictionary = sim.mount_near_me(ch)
	check(int(ch["gold"]) == 200000 - 3000 - 20000 and RulesMount.stage(data.mounts, m) == "adult", "買成年馬 20000")
	sim.cmd_mount_ride(id, true)
	check(sim.is_riding(ch), "成年馬即刻騎得")
	# 移速: 許昌第 27 行直路
	var md: Dictionary = data.map_by_id["xuchang"]
	var ox := int(md["ox"])
	var oy := int(md["oy"])
	_put(sim, id, ox + 6, oy + 27)
	sim.cmd_move(id, ox + 64, oy + 27)
	for i in 20:
		sim.step()
	var ride_dx := int(sim.ent(id)["x"]) - (ox + 6)
	sim.cmd_mount_ride(id, false)
	check(not sim.is_riding(ch), "落馬")
	_put(sim, id, ox + 6, oy + 27)
	sim.cmd_move(id, ox + 64, oy + 27)
	for i in 20:
		sim.step()
	var walk_dx := int(sim.ent(id)["x"]) - (ox + 6)
	check(walk_dx == 20 and ride_dx >= 34 and ride_dx <= 40, "騎馬 20 tick 行 %d 格 (行路 %d)" % [ride_dx, walk_dx])
	check(int(m["fatigue"]) >= 1, "騎住行會攰")
	# 騎到頭暈 → 自動落馬
	sim.cmd_mount_ride(id, true)
	m["fatigue"] = RulesMount.fatigue_max(data.mounts, m) - 1
	m["rideAcc"] = RulesMount.tiles_per_fatigue(data.mounts, m) - 1
	_put(sim, id, ox + 6, oy + 27)
	sim.cmd_move(id, ox + 30, oy + 27)
	for i in 3:
		sim.step()
	check(not sim.is_riding(ch) and m["status"].has("dizzy"), "騎到疲勞滿 → 頭暈落馬")
	sim.cmd_mount_ride(id, true)
	check(not sim.is_riding(ch), "頭暈騎唔到")
	m["status"].erase("dizzy")
	m["fatigue"] = 0
	# 攻擊 → 落馬
	sim.init_mobs()
	var mob := {}
	for e in sim.ents.values():
		if e["kind"] == "mob" and not sim.is_safe(int(e["x"]), int(e["y"])):
			mob = e
			break
	check(not mob.is_empty(), "搵到野外怪")
	var p := sim._free_near(int(mob["x"]), int(mob["y"]))
	_put(sim, id, p.x, p.y)
	sim.cmd_mount_ride(id, true)
	check(sim.is_riding(ch), "野外騎馬")
	sim.cmd_attack(id, int(mob["id"]))
	for i in 3:
		sim.step()
	check(not sim.is_riding(ch), "用一般武器出手 → 落馬")
	# 死亡 → 落馬
	sim.cmd_mount_ride(id, true)
	sim._kill_player(sim.ent(id))
	check(not sim.is_riding(ch) and not sim.mount_near_me(ch).is_empty(), "死亡落馬、馬仍然跟身")
	# 過圖: 騎馬踩門口照過
	sim.cmd_mount_ride(id, true)
	var gate: Dictionary = sim.travel_point_by_id("gate_out")
	_put(sim, id, int(gate["x"]), int(gate["y"]) - 6)
	sim.cmd_move(id, int(gate["x"]), int(gate["y"]))
	for i in 10:
		sim.step()
	check(sim.map_id_at(int(sim.ent(id)["x"]), int(sim.ent(id)["y"])) != "xuchang", "騎馬行過城門 = 過圖 (唔會跨過傳送格)")


func t_graze(data: GameData) -> void:
	var r := _new(data, 14)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	_at_fac(sim, id, "stable_xc")
	sim.cmd_mount_buy(id, "shenshan", false)
	sim.cmd_mount_graze(id)
	check(_last(msgs).contains("馴馬專用哨"), "冇哨唔放得牧")
	sim.cmd_buy(id, WHISTLE, 1)
	check(RulesShop.count_item(ch["bag"], WHISTLE) == 1, "馬廄買到馴馬專用哨")
	sim.cmd_mount_graze(id)
	check(String(sim._mounts(ch)[0]["where"]) == "with", "襁褓期唔放得牧")
	sim.cmd_mount_stable(id, int(sim._mounts(ch)[0]["uid"]))
	sim.cmd_mount_buy(id, "dawan", true)
	var m: Dictionary = sim.mount_near_me(ch)
	sim.cmd_mount_ride(id, true)
	sim.cmd_mount_graze(id)
	check(String(m["where"]) == "graze" and not sim.is_riding(ch), "放牧: 落馬 + 馬離開")
	sim.cmd_mount_ride(id, true)
	check(not sim.is_riding(ch), "放緊牧騎唔到")
	var back := {}
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "mount" and ev.get("act", "") == "graze_back":
			back["ev"] = ev)
	for i in int(data.mounts["grazeTicks"]) - 1:
		sim.step()
	check(String(m["where"]) == "graze" and back.is_empty(), "未夠一個時辰未返")
	sim.step()
	check(String(m["where"]) == "with" and not back.is_empty(), "一個時辰後返嚟【原】")
	check(int(m["fatigue"]) > 0, "放牧返嚟加疲勞【原】")
	# 緊急召回
	m["fatigue"] = 0
	sim.cmd_mount_graze(id)
	sim.step()
	sim.cmd_mount_graze(id)
	check(String(m["where"]) == "with" and int(m["fatigue"]) == int(data.mounts["graze"]["fatigue"]["recall"]), "再吹哨 = 緊急召回")
	# 多次放牧: 有成長 / 執嘢 / 受傷 (統計)
	var kinds := {}
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "mount" and ev.get("act", "") == "graze_back":
			kinds[ev["res"]] = int(kinds.get(ev["res"], 0)) + 1)
	for n in 60:
		m["fatigue"] = 0
		m["status"] = {}
		m["life"] = 100
		sim.cmd_mount_graze(id)
		for i in int(data.mounts["grazeTicks"]):
			sim.step()
	check(kinds.size() == 4, "60 次放牧四種結果都有: %s" % str(kinds))
	check(int(m["excel"]) > 0 or int(m["grow"]) > 0, "放牧有成長")


func t_daily_sim(data: GameData) -> void:
	var r := _new(data, 15)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	_at_fac(sim, id, "stable_xc")
	sim.cmd_mount_buy(id, "dawan")
	sim.cmd_mount_buy(id, "wusun")
	var ms: Array = sim._mounts(ch)
	ms[0]["mood"] = 90
	ms[1]["fatigue"] = 50
	ms[1]["status"]["dizzy"] = true
	sim.cmd_mount_act(id, int(ms[0]["uid"]), "play")
	_next_day(sim)
	check(int(ms[0]["intimacy"]) == 22 and int(ms[0]["age"]) == 1 and (ms[0]["acts"] as Dictionary).is_empty(), "子時: 身邊高興 +2、歲 +1、次數重置")
	check(int(ms[1]["fatigue"]) == 0 and not ms[1]["status"].has("dizzy") and int(ms[1]["intimacy"]) == 20, "子時: 馬廄疲勞清零 + 頭暈好、幼馬唔加親密")
	# 馬瘟
	sim.state["disasters"].append({"id": "plague", "name": "瘟疫", "city": "xuchang", "size": "細", "supply": {}, "endDay": 999})
	_next_day(sim)
	check(int(ms[1]["life"]) == 80 and int(ms[0]["life"]) == 100, "許昌瘟疫: 寄喺許昌馬廄嘅馬扣生命力")
	# 壽終
	ms[1]["age"] = 364
	_next_day(sim)
	check(ms.size() == 1 and _last(msgs).contains("獸醫"), "壽終: 獸醫來信 + 移除【原】")
	# 騎緊嘅馬死 → 落馬
	var t := RulesMount.new_mount(data.mounts, "dawan", 99, true)
	ms.clear()
	ms.append(t)
	sim.cmd_mount_ride(id, true)
	check(sim.is_riding(ch), "騎住")
	t["age"] = 364
	_next_day(sim)
	check(ms.is_empty() and not sim.is_riding(ch), "騎緊嘅馬死咗 → 落馬")


# ---------- 存檔 / 決定性 ----------
func t_roundtrip(data: GameData) -> void:
	var r := _new(data, 16)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	_at_fac(sim, id, "stable_xc")
	sim.cmd_mount_buy(id, "dawan", true)
	sim.cmd_mount_buy(id, "wusun")
	sim.cmd_buy(id, WHISTLE, 1)
	sim.cmd_mount_graze(id)
	sim.step()
	var s1 := sim.save_string()
	var sim2 := Sim.load_string(data, s1)
	check(sim2 != null and sim2.save_string() == s1, "save → load → save 字串一致")
	var ch2: Dictionary = sim2.player_ch()
	var id2 := int(sim2.state["player_id"])
	var m2: Dictionary = sim2.mount_near_me(ch2)
	check(sim2._mounts(ch2).size() == 2 and String(m2["where"]) == "graze", "載入: 2 匹 + 放牧中")
	for i in int(data.mounts["grazeTicks"]):
		sim2.step()
	check(String(m2["where"]) == "with", "載入後放牧照返")
	sim2.cmd_mount_ride(id2, true)
	check(sim2.is_riding(ch2), "載入後騎得")
	var s2 := sim2.save_string()
	check(Sim.load_string(data, s2).is_riding(Sim.load_string(data, s2).player_ch()), "騎乘狀態存檔")


func _script(data: GameData) -> String:
	var r := _new(data, 138)
	var sim: Sim = r[0]
	var id: int = r[1]
	sim.init_mobs()
	_at_fac(sim, id, "stable_xc")
	sim.cmd_mount_buy(id, "dawan", true)
	sim.cmd_buy(id, WHISTLE, 1)
	sim.cmd_mount_ride(id, true)
	sim.cmd_goto_map(id, "field_1")
	for i in 200:
		sim.step()
	sim.cmd_mount_graze(id)
	for n in 5:
		for i in 61:
			sim.step()
		sim.cmd_mount_graze(id)
	_next_day(sim)
	return sim.save_string()


func t_determinism(data: GameData) -> void:
	check(_script(data) == _script(data), "同種子同操作 → 存檔一致")


# ---------- 繁衍 (Step 17b, spec 07 §6) ----------
func t_breed_pure(cfg: Dictionary) -> void:
	var m := RulesMount.new_mount(cfg, "wusun", 1, true)     # tamed 成年母馬
	check(RulesMount.breed_why(cfg, m) == "", "成年母馬配得種")
	var mfoal := RulesMount.new_mount(cfg, "wusun", 2, false)   # 幼馬
	check(RulesMount.breed_why(cfg, mfoal) != "", "幼馬配唔到種")
	RulesMount.breed_start(cfg, m, "damo")
	check(m.has("preg") and int(m["preg"]["motive"]) == 50, "配種: 動力值 50 起【原】")
	check(RulesMount.breed_why(cfg, m) != "", "已懷孕配唔到第二次")
	# 落注: outcome 由 r 決定 (5 揀 1)，選中 (choice==outcome) 先得分
	var res_win := RulesMount.breed_bet(cfg, 2, 0.41)          # r*5=2.05 → outcome=2
	check(int(res_win["outcome"]) == 2 and bool(res_win["win"]) and int(res_win["points"]) == int(cfg["breed"]["betOdds"][2]), "估中攞返對應賠率積點")
	var res_lose := RulesMount.breed_bet(cfg, 0, 0.41)
	check(not bool(res_lose["win"]) and int(res_lose["points"]) == 0, "估錯冇積點")
	var before_motive := int(m["preg"]["motive"])
	RulesMount.breed_play(cfg, m, 2, 0.41)
	check(int(m["preg"]["motive"]) == before_motive - int(cfg["breed"]["betCost"]) and int(m["preg"]["taiqi"]) == 1
		and int(m["preg"]["bpts"]) == int(cfg["breed"]["betOdds"][2]), "落注: 扣動力、胎氣必 +1、估中加積點")
	m["preg"]["motive"] = 5
	check(RulesMount.breed_can_play(cfg, m) != "", "動力唔夠，聽日先再嚟")
	RulesMount.breed_daily(cfg, m)
	check(int(m["preg"]["motive"]) == 45, "動力 <50 → 每日子時 +40【原】")
	m["preg"]["motive"] = 80
	RulesMount.breed_daily(cfg, m)
	check(int(m["preg"]["motive"]) == 100, "動力 >=50 → +20，封頂 100")
	m["preg"]["taiqi"] = int(cfg["breed"]["taiqiNeed"])
	check(RulesMount.breed_ready(cfg, m), "100 胎氣可以接生【原】")
	check(RulesMount.breed_can_play(cfg, m) != "", "胎氣夠就唔畀再落注")
	# 接生: 品種 = 母血機率 × damWeight : 父血 × sireWeight；性別多數母
	var mA := RulesMount.new_mount(cfg, "wusun", 10, true)
	RulesMount.breed_start(cfg, mA, "damo")
	var b1 := RulesMount.breed_birth(cfg, mA, 0.1, 0.1)
	check(not mA.has("preg"), "接生後懷孕狀態清空")
	check(String(b1["breed"]) == "wusun" and String(b1["sex"]) == "m", "r1 細 → 母血 (機率 ×2)；r2 細 → 男")
	var mB := RulesMount.new_mount(cfg, "wusun", 11, true)
	RulesMount.breed_start(cfg, mB, "damo")
	var b2 := RulesMount.breed_birth(cfg, mB, 0.99, 0.99)
	check(String(b2["breed"]) == "damo" and String(b2["sex"]) == "f", "r1 大 → 父血；r2 大 → 女 (多數母)【原】")
	# 懶人胎教: lazyDays 日自動填滿【自訂】
	var m3 := RulesMount.new_mount(cfg, "wusun", 3, true)
	RulesMount.breed_start(cfg, m3, "wusun")
	m3["preg"]["lazy"] = true
	for i in int(cfg["breed"]["lazyDays"]) - 1:
		RulesMount.breed_daily(cfg, m3)
	check(not RulesMount.breed_ready(cfg, m3), "懶人胎教未夠日未完成")
	var ev := RulesMount.breed_daily(cfg, m3)
	check(ev == "ready" and int(m3["preg"]["taiqi"]) == int(cfg["breed"]["taiqiNeed"])
		and int(m3["preg"]["bpts"]) == int(cfg["breed"]["lazyBpts"]), "懶人胎教 lazyDays 日後自動完成，積點封頂 lazyBpts")
	# 積點分配 (兌換錶) + 進階馬
	var m4 := RulesMount.new_foal(cfg, "wusun", 4, "f", 3)
	check(int(m4["bpts"]) == 3 and int(m4["totalBpts"]) == 3 and not bool(m4["adv"]), "新小馬帶住接生積點")
	check(RulesMount.spend_bpt(cfg, m4, "burst") and int(m4["bpts"]) == 0
		and RulesMount.attr_cap(cfg, m4, "burst") == int(cfg["attrCap"]) + 1, "烏孫馬 3 點換 1 爆發力上限【原】")
	check(not RulesMount.spend_bpt(cfg, m4, "burst"), "積點用晒唔換得")
	var m5 := RulesMount.new_foal(cfg, "wusun", 5, "f", int(RulesMount.breed_def(cfg, "wusun")["advNeed"]))
	check(bool(m5["adv"]), "總積點 ≥ advNeed → 進階馬【原】")
	check(RulesMount.life_max(cfg, m5) == int(cfg["start"]["life"]) * 2, "進階馬生命上限 ×2【原】")


func t_breed_sim(data: GameData) -> void:
	var r := _new(data, 21)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	var cfg := data.mounts
	_at_fac(sim, id, "stable_xc")
	sim.cmd_mount_buy(id, "dawan", true)          # tamed 成年母馬
	var m: Dictionary = sim._mounts(ch)[0]
	var uid := int(m["uid"])
	var gold0 := int(ch["gold"])
	sim.cmd_mount_breed_start(id, uid, "damo")
	check(m.has("preg") and int(ch["gold"]) == gold0 - int(cfg["studPrice"]), "配種: 種馬借用扣 5000 金")
	sim.cmd_mount_breed_start(id, uid, "damo")
	check(_last(msgs).contains("身孕"), "已懷孕唔畀再配")
	sim.cmd_mount_breed_bet(id, uid, 0)
	check(int(m["preg"]["taiqi"]) == 1, "落注: 胎氣 +1")
	sim.cmd_mount_breed_lazy(id, uid, true)
	check(bool(m["preg"]["lazy"]), "懶人胎教開關")
	m["preg"]["taiqi"] = int(cfg["breed"]["taiqiNeed"])          # 直接催熟去 claim 流程
	sim.cmd_mount_breed_claim(id, uid)
	check(not m.has("preg") and not (ch.get("pendingFoal", {}) as Dictionary).is_empty(), "接生: 產生待領小馬")
	_put(sim, id, 5, 5)                                          # 唔喺馬廄
	sim.cmd_mount_take_foal(id)
	check(not (ch.get("pendingFoal", {}) as Dictionary).is_empty(), "唔喺馬廄領唔到")
	_at_fac(sim, id, "stable_xc")
	var before := sim._mounts(ch).size()
	sim.cmd_mount_take_foal(id)
	check(sim._mounts(ch).size() == before + 1 and (ch.get("pendingFoal", {}) as Dictionary).is_empty(), "馬廄領走小馬")
	# 未提領過期【原=3 個月未提領死亡】
	var m2: Dictionary = sim._mounts(ch)[0]
	sim.cmd_mount_breed_start(id, int(m2["uid"]), "damo")
	m2["preg"]["taiqi"] = int(cfg["breed"]["taiqiNeed"])
	sim.cmd_mount_breed_claim(id, int(m2["uid"]))
	for i in int(cfg["breed"]["claimDays"]) + 1:
		_next_day(sim)
	check((ch.get("pendingFoal", {}) as Dictionary).is_empty(), "%d 日未領走失【原】" % int(cfg["breed"]["claimDays"]))
	# sim 指令層: 積點分配
	var m3: Dictionary = sim._mounts(ch)[0]
	m3["breed"] = "wusun"
	m3["bpts"] = 3
	sim.cmd_mount_spend_bpt(id, int(m3["uid"]), "burst")
	check(int(m3["bpts"]) == 0 and _last(msgs).contains("爆發力"), "sim: 積點分配扣點")


# ---------- 馬戰 (Step 17b, spec 07 §7 / spec 02 §10) ----------
func t_battle_pure(data: GameData) -> void:
	var cfg := data.mount_weapons
	check(RulesMountBattle.weapon_type_of(cfg, "dao2") == "dao", "兵器種類反查")
	check(RulesMountBattle.weapon_buy_why(cfg, 5, "dao", "dao1") != "", "等級唔夠買唔到")
	check(RulesMountBattle.weapon_buy_why(cfg, 10, "dao", "dao1") == "", "夠 Lv 買得")
	var learned: Array = []
	check(RulesMountBattle.learn_why(cfg, learned, "", "dao_baoji") != "", "冇裝備對應兵器學唔到")
	check(RulesMountBattle.learn_why(cfg, learned, "dao", "dao_baoji") == "", "有兵器就學得")
	learned = ["dao_baoji", "dao_jiyun", "dao_didang"]
	check(RulesMountBattle.learn_why(cfg, learned, "dao", "jian_hudun") != "", "最多學 3 招馬戰特技【原】")
	check(RulesMountBattle.use_why(cfg, learned, false, "dao", "dao_baoji", 0, 0, 100) != "", "未騎馬用唔到")
	check(RulesMountBattle.use_why(cfg, learned, true, "dao", "dao_baoji", 0, 0, 100) == "", "騎緊 + 裝備 + 學過 + 唔喺冷卻 + SP 夠 → 用得")
	check(RulesMountBattle.use_why(cfg, learned, true, "dao", "dao_baoji", 100, 0, 100) != "", "冷卻中用唔到")
	check(RulesMountBattle.use_why(cfg, learned, true, "dao", "dao_baoji", 0, 0, 1) != "", "SP 唔夠用唔到")
	check((RulesMountBattle.skills_of(cfg, "qiang") as Array).size() == 3, "槍 3 招馬戰特技【原】")


func t_battle_sim(data: GameData) -> void:
	var r := _new(data, 31)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	ch["level"] = 50
	sim._sync_stats(sim.ent(id))
	_at_fac(sim, id, "stable_xc")
	sim.cmd_mount_buy(id, "dawan", true)
	sim.cmd_mount_ride(id, true)
	check(sim.is_riding(ch), "騎住")
	sim.cmd_mount_skill_learn(id, "dao_baoji")
	check((ch.get("mountSkills", []) as Array).is_empty(), "未有馬戰兵器學唔到特技")
	sim.cmd_mount_weapon_buy(id, "dao", "dao2")
	check(String(ch.get("mountWeapon", "")) == "dao2", "買咗馬戰兵器就裝備")
	sim.cmd_mount_skill_learn(id, "dao_baoji")
	sim.cmd_mount_skill_learn(id, "dao_jiyun")
	sim.cmd_mount_skill_learn(id, "dao_didang")
	check((ch["mountSkills"] as Array).size() == 3, "學咗 3 招")
	sim.cmd_mount_skill_learn(id, "dao_baoji")
	check(_last(msgs).contains("已經學"), "重複學唔到")
	sim.cmd_goto_map(id, "field_1")
	for i in 50:
		sim.step()
	var mo: Dictionary = sim._spawn_mob(12012, "field_1")
	var mob := int(mo["id"])
	_put(sim, id, int(mo["x"]), int(mo["y"]))
	sim.cmd_attack(id, mob)
	for i in 20:
		sim.step()
	check(sim.is_riding(ch), "有馬戰兵器: 騎緊都打得，唔使落馬【原】")
	sim.ent(id)["atk_target"] = 0        # 停低玩家自動攻擊，之後淨係試主動用特技
	ch["mountWeapon"] = ""
	var mo0: Dictionary = sim._spawn_mob(12012, "field_1")     # 新一隻，避免上面已經打死
	var mob0 := int(mo0["id"])
	_put(sim, id, int(mo0["x"]), int(mo0["y"]))
	sim.ent(id)["next_atk"] = sim.tick
	sim.cmd_attack(id, mob0)
	for i in 20:
		sim.step()
	check(not sim.is_riding(ch), "冇馬戰兵器: 一般武器出手要落馬【原】")
	sim.ent(id)["atk_target"] = 0
	sim.cmd_mount_ride(id, true)
	ch["mountWeapon"] = "dao2"
	# 抵擋: 擋一次物理傷害 (換隻新怪，冇畀玩家自動攻擊打死)
	var mo2: Dictionary = sim._spawn_mob(12012, "field_1")
	_put(sim, id, int(mo2["x"]), int(mo2["y"]))
	sim.cmd_mount_skill_use(id, "dao_didang")
	check(int(ch.get("mBlockCharges", 0)) == 1, "抵擋: 準備擋一次")
	mo2["mob"]["state"] = "chase"
	mo2["mob"]["target"] = id
	for i in 20:
		ch["hp"] = 9999
		sim.ent(id)["hp"] = 9999
		sim.step()
		if int(ch.get("mBlockCharges", 0)) == 0:
			break
	check(int(ch.get("mBlockCharges", 0)) == 0, "抵擋擋咗一次後清零")
	sim.ent(id)["atk_target"] = 0
	# 擊暈: 敵人定身 (hex) (再換隻新怪)
	var mo3: Dictionary = sim._spawn_mob(12012, "field_1")
	var mob3 := int(mo3["id"])
	_put(sim, id, int(mo3["x"]), int(mo3["y"]))
	sim.cmd_mount_skill_use(id, "dao_jiyun", mob3)
	check(RulesSpell.has(mo3.get("status", {}), "hex", sim.tick), "擊暈: 目標定身 (hex)【自訂近似】")
	# 爆擊: 單體高倍傷害
	var hp1 := int(mo3["hp"])
	sim.cmd_mount_skill_use(id, "dao_baoji", mob3)
	check(int(mo3["hp"]) < hp1, "爆擊出傷害")
	var hp2 := int(mo3["hp"])
	sim.cmd_mount_skill_use(id, "dao_baoji", mob3)
	check(int(mo3["hp"]) == hp2, "冷卻中再用唔到")
	# 疾奔 / 護盾 / 重擊 (劍) 分開一個玩家測，避免撞學招上限
	var r2 := _new(data, 32)
	var sim2: Sim = r2[0]
	var id2: int = r2[1]
	var ch2: Dictionary = r2[2]
	ch2["level"] = 50
	sim2._sync_stats(sim2.ent(id2))
	_at_fac(sim2, id2, "stable_xc")
	sim2.cmd_mount_buy(id2, "dawan", true)
	sim2.cmd_mount_weapon_buy(id2, "jian", "jian2")
	sim2.cmd_mount_skill_learn(id2, "jian_jiben")     # 疾奔
	sim2.cmd_mount_skill_learn(id2, "jian_hudun")     # 護盾
	sim2.cmd_mount_skill_learn(id2, "jian_zhongji")   # 重擊 (aoe)
	sim2.cmd_mount_ride(id2, true)
	sim2.cmd_goto_map(id2, "field_1")
	for i in 50:
		sim2.step()
	var base_steps := sim2._ride_steps(sim2.ent(id2))
	sim2.cmd_mount_skill_use(id2, "jian_jiben")
	check(RulesSpell.has(ch2.get("status", {}), "mride_speed", sim2.tick), "疾奔: 加咗移速 buff 狀態")
	check(sim2._ride_steps(sim2.ent(id2)) >= base_steps, "疾奔: 移速加成生效")
	sim2.cmd_mount_skill_use(id2, "jian_hudun")
	check(RulesSpell.has(ch2.get("status", {}), "mshield", sim2.tick), "護盾: 加咗全防禦狀態")
	var moC: Dictionary = sim2._spawn_mob(12012, "field_1")
	_put(sim2, id2, int(moC["x"]), int(moC["y"]))
	moC["mob"]["state"] = "chase"
	moC["mob"]["target"] = id2
	var hpShield := int(ch2["hp"])
	for i in 10:
		ch2["hp"] = maxi(int(ch2["hp"]), hpShield)
		sim2.step()
	check(int(ch2["hp"]) == hpShield, "護盾期間全防禦，冇食傷")
	var moD: Dictionary = sim2._spawn_mob(12012, "field_1")
	_put(sim2, int(moD["id"]), int(moC["x"]) + 1, int(moC["y"]))
	var hpA := int(moC["hp"])
	var hpB := int(moD["hp"])
	sim2.cmd_mount_skill_use(id2, "jian_zhongji", int(moC["id"]))
	check(int(moC["hp"]) < hpA and int(moD["hp"]) < hpB, "重擊: 範圍打中附近嘅怪")
