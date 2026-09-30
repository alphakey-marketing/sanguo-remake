extends SceneTree
# S08f 測試 (spec 08 §7/§8 / 攻略 sy2_8_5、sy2_8_6、sy2_8_8):
#   營地建設 10 設施（升級材料 = 基本×級數、監督完成度）、義勇軍工作 22 項（有/無城池）、
#   評定會議（指派 3 種、績效 0~900+ → 功績 −30~+100）、團體任務接軌（每月/每日重複、日窗口、績效）。
# 跑: Godot --headless --path client --script tests/run_camp.gd  (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_data(data)
	t_rules(data)
	t_work_rules(data)
	t_camp_upgrade(data)
	t_works(data)
	t_work_expert(data)
	t_eval(data)
	t_eval_daily(data)
	t_group_hook(data)
	t_repeat(data)
	t_daywindow(data)
	t_adv(data)
	t_save(data)
	t_determinism(data)
	print("[TEST] camp (S08f: camp/work/eval): %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


func _new(data: GameData, seed: int = 42) -> Array:
	var sim := Sim.new(data, seed)
	var pid := sim.spawn_player("t", "yishi")
	var ch := sim.player_ch()
	ch["level"] = 20
	ch["ap"] = 100000
	ch["gold"] = 3000000
	var msgs: Array = []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "msg":
			msgs.append(String(ev["text"])))
	return [sim, pid, ch, msgs]


func _last(msgs: Array) -> String:
	return String(msgs[-1]) if not msgs.is_empty() else ""


func _mil(sim: Sim, ch: Dictionary, city: String = "xuchang") -> Dictionary:
	ch["militia"] = {"founded": true, "name": "義軍", "city": city, "grade": 1, "supporters": [], "role": "banner", "hasCity": true}
	return ch["militia"]


func _put(sim: Sim, id: int, x: int, y: int) -> void:
	var e := sim.ent(id)
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y


func _put_map(sim: Sim, id: int, data: GameData, map_id: String) -> void:
	var z: Dictionary = data.zone_by_id[map_id]
	_put(sim, id, int(z["x0"]) + 1, int(z["y0"]) + 1)


# ================= 資料 =================
func t_data(data: GameData) -> void:
	var camp: Dictionary = data.camp
	var facs: Array = camp["facilities"]
	check(facs.size() == 10, "營地 10 個設施")
	var ids := []
	var init := {}
	for f in facs:
		ids.append(String(f["id"]))
		init[String(f["id"])] = int(f["initial"])
	check(ids.has("camp") and ids.has("treasury") and ids.has("granary") and ids.has("vault"), "設施 id 齊")
	check(int(init["camp"]) == 1 and int(init["treasury"]) == 1 and int(init["granary"]) == 0 and int(init["barracks"]) == 0, "初始級: 營地/金庫 1、糧倉/兵營 0")
	check(int(camp["maxLevel"]) == 10 and int((camp["supervise"] as Dictionary)["target"]) == 100, "10 級上限 + 完成度目標 100")
	check(int((camp["workCapByLevel"] as Dictionary)["1"]) == 50 and int((camp["workCapByLevel"] as Dictionary)["5"]) == 100, "指派份數 50→100")
	check((camp["gradeLimitByLevel"] as Dictionary)["1"][0] == 5 and (camp["gradeLimitByLevel"] as Dictionary)["5"][7] == 45, "階級人數上限表")
	var camp_fac := RulesCamp.def_of(camp, "camp")
	check(int((camp_fac["base"] as Dictionary)["gold"]) == 200000, "營地基本 20 萬")
	var works: Array = camp["works"]
	check(works.size() == 22, "義勇軍工作 22 項")
	var series := {"internal": 0, "military": 0, "armament": 0}
	var need_city := 0
	for w in works:
		series[String(w["series"])] += 1
		if bool(w.get("needCity", false)):
			need_city += 1
	check(int(series["internal"]) == 10 and int(series["military"]) == 3 and int(series["armament"]) == 9, "內政 10 + 軍事 3 + 軍備 9")
	check(need_city == 8, "8 項內政要城池 (監督/商情兩項無城池都做得到)")
	check((camp["assignmentKinds"] as Array).size() == 3 and int(camp["maxAssignments"]) == 3, "評定指派 3 種")
	var mt: Array = camp["meritTable"]
	check(mt.size() == 14 and int(mt[0][0]) == 20 and int(mt[0][1]) == -30 and int(mt[13][1]) == 100, "功績對照表 14 段")


# ================= 純函數 =================
func t_rules(data: GameData) -> void:
	var camp: Dictionary = data.camp
	check(RulesCamp.cfg(camp).size() > 0 and RulesCamp.def_of(camp, "camp").size() > 0, "cfg/def_of")
	check(RulesCamp.initial_level(camp, "camp") == 1 and RulesCamp.initial_level(camp, "granary") == 0, "initial_level")
	check(RulesCamp.max_level(camp) == 10, "max_level")
	var c2 := RulesCamp.upgrade_cost(camp, "camp", 2)
	check(int(c2["gold"]) == 400000, "升級 2 級 = 200000×2")
	check(int(c2["materials"][25001]) == 10000 and int(c2["materials"][25010]) == 400, "材料 = 基本×級數 (石頭 10000/星隕 400)")
	var c1 := RulesCamp.upgrade_cost(camp, "camp", 1)
	check(int(c1["gold"]) == 200000 and int(c1["materials"][25001]) == 5000, "升級 1 級 = 基本")
	# 監督完成度 = 0.5 + 政治×0.01 + 木匠×0.02 + 身份加成
	check(absf(RulesCamp.supervise_points(camp, 50, 0, "banner") - 1.3) < 1e-6, "監督: 政治 50 + 頭目 = 1.3")
	check(absf(RulesCamp.supervise_points(camp, 0, 0, "member") - 0.5) < 1e-6, "監督: 白身部將 = 0.5")
	check(absf(RulesCamp.supervise_points(camp, 100, 10, "canjun") - (0.5 + 1.0 + 0.2 + 0.2)) < 1e-6, "監督: 政治 100 + 木匠 10 + 參軍")
	check(RulesCamp.supervise_target(camp) == 100, "監督目標 100")
	check(RulesCamp.work_cap(camp, 1) == 50 and RulesCamp.work_cap(camp, 5) == 100 and RulesCamp.work_cap(camp, 9) == 100, "work_cap 50/100")
	check(RulesCamp.grade_limit(camp, 1, 1) == 5 and RulesCamp.grade_limit(camp, 1, 8) == 35, "grade_limit 1 級")
	check(RulesCamp.grade_limit(camp, 5, 1) == 15 and RulesCamp.grade_limit(camp, 5, 8) == 45, "grade_limit 5 級")
	check(RulesCamp.facility_cap(camp, "treasury", 1, "gold") == 50000000, "金庫 1 級 = 5000 萬")
	check(RulesCamp.facility_cap(camp, "treasury", 10, "gold") == 200000000, "金庫 10 級 = 2 億")
	check(RulesCamp.facility_cap(camp, "barracks", 1, "soldiers") == 600000 and RulesCamp.facility_cap(camp, "camp", 1, "gold") == -1, "兵營 60 萬 / 營地冇 store cap")
	check((RulesCamp.positions_at(camp, 4) as Array).has("diannong") and (RulesCamp.positions_at(camp, 5) as Array).has("sinong"), "4 級典農/靈台、5 級司農")
	check(RulesCamp.can_upgrade_role(camp, "banner") and RulesCamp.can_upgrade_role(camp, "canjun") and not RulesCamp.can_upgrade_role(camp, "member"), "得頭目/參軍指定升級")
	check(absf(RulesCamp.role_bonus(camp, "banner") - 0.3) < 1e-6 and absf(RulesCamp.role_bonus(camp, "member")) < 1e-6, "身份加成")


func t_work_rules(data: GameData) -> void:
	var camp: Dictionary = data.camp
	check(RulesMilitiaWork.works(camp).size() == 22, "works 22")
	check(RulesMilitiaWork.available(camp, false).size() == 14, "無城池: 14 項 (得監督/商情)")
	check(RulesMilitiaWork.available(camp, true).size() == 22, "有城池: 22 項")
	check(not RulesMilitiaWork.is_available(camp, false, "kaiken") and RulesMilitiaWork.is_available(camp, false, "jiandu"), "無城池: 開墾唔得、監督得")
	check(RulesMilitiaWork.assignment_of(camp, "jiandu") == "supervise", "jiandu → supervise")
	check(RulesMilitiaWork.assignment_of(camp, "shangqing") == "trade", "shangqing → trade")
	check(RulesMilitiaWork.assignment_of(camp, "juanqian") == "donate", "juanqian → donate")
	check(RulesMilitiaWork.assignment_of(camp, "kaiken") == "", "kaiken 唔屬指派類")
	# 績效→功績表【原】
	check(RulesMilitiaWork.merit_delta(camp, 0) == -30 and RulesMilitiaWork.merit_delta(camp, 20) == -30, "0~20 → -30")
	check(RulesMilitiaWork.merit_delta(camp, 21) == -20 and RulesMilitiaWork.merit_delta(camp, 40) == -20, "21~40 → -20")
	check(RulesMilitiaWork.merit_delta(camp, 61) == 0 and RulesMilitiaWork.merit_delta(camp, 80) == 0, "61~80 → 0")
	check(RulesMilitiaWork.merit_delta(camp, 81) == 10 and RulesMilitiaWork.merit_delta(camp, 101) == 20, "81~100 → 10")
	check(RulesMilitiaWork.merit_delta(camp, 121) == 30 and RulesMilitiaWork.merit_delta(camp, 151) == 40, "121~150 → 30")
	check(RulesMilitiaWork.merit_delta(camp, 201) == 50 and RulesMilitiaWork.merit_delta(camp, 301) == 60, "201~300 → 50")
	check(RulesMilitiaWork.merit_delta(camp, 401) == 70 and RulesMilitiaWork.merit_delta(camp, 501) == 80, "401~500 → 70")
	check(RulesMilitiaWork.merit_delta(camp, 701) == 90 and RulesMilitiaWork.merit_delta(camp, 901) == 100 and RulesMilitiaWork.merit_delta(camp, 99999) == 100, "701~900 → 90、901+ → 100")
	# 績效 gain: 基本 + 專長×5 + 指派 +20
	check(RulesMilitiaWork.performance_gain(camp, "kaiken", 0, false) == 10, "kaiken perf 10")
	check(RulesMilitiaWork.performance_gain(camp, "kaiken", 2, false) == 20, "kaiken 專長 2 級 = 10+10")
	check(RulesMilitiaWork.performance_gain(camp, "kaiken", 0, true) == 30, "kaiken 有指派 = 10+20")
	check(RulesMilitiaWork.performance_gain(camp, "juanqian", 1, true) == 15 + 5 + 20, "juanqian 專長 1 級 + 指派")


# ================= 營地升級/監督 =================
func t_camp_upgrade(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	# 未成立
	sim.cmd_camp_upgrade(pid, "treasury")
	check(_last(msgs).contains("未成立"), "未成立起唔到營地")
	_mil(sim, ch, "xuchang")
	# 唔喺根據地 (搬去新野)
	_put_map(sim, pid, data, "xinye")
	sim.cmd_camp_upgrade(pid, "treasury")
	check(_last(msgs).contains("根據地"), "唔喺根據地指定唔到升級")
	# 回根據地許昌
	_put_map(sim, pid, data, "xuchang")
	check(sim.city_at(sim.ent(pid)) == "xuchang", "玩家喺許昌城內")
	# 軍資不足
	ch["gold"] = 1
	sim.cmd_camp_upgrade(pid, "treasury")
	check(_last(msgs).contains("軍資唔夠"), "軍資不足")
	ch["gold"] = 3000000
	# 材料不足
	sim.cmd_camp_upgrade(pid, "treasury")
	check(_last(msgs).contains("材料唔夠"), "材料不足")
	# 備齊材料
	RulesShop.add_item(ch["bag"], 25001, 20000)
	RulesShop.add_item(ch["bag"], 25053, 20000)
	RulesShop.add_item(ch["bag"], 25002, 5000)
	RulesShop.add_item(ch["bag"], 25054, 10000)
	RulesShop.add_item(ch["bag"], 25006, 5000)
	ch["workLv"] = {"carpentry": {"lv": 50, "exp": 0}}
	ch["attrs"]["pol"] = 50
	var v := sim.camp_view(pid)
	check(bool(v["founded"]) and bool(v["atHome"]) and int(v["level"]) == 1, "camp_view: 成立/根據地/1 級")
	check(int(v["workCap"]) == 50 and (v["facilities"] as Array).size() == 10, "camp_view: 指派份數 50")
	sim.cmd_camp_upgrade(pid, "treasury")
	var c: Dictionary = ch["militia"]["camp"]
	check(String((c["build"] as Dictionary)["fac"]) == "treasury" and int((c["build"] as Dictionary)["target"]) == 2, "開咗建設 treasury → 2 級")
	check(int(ch["gold"]) == 3000000 - 100000, "扣升級軍資 10 萬 (2 級)")
	check(RulesShop.count_item(ch["bag"], 25001) == 20000 - 4000, "扣石頭 4000")
	check(_last(msgs).contains("監督"), "建設中提示監督")
	sim.cmd_camp_upgrade(pid, "camp")
	check(_last(msgs).contains("仲有建設緊"), "建設中唔可以再開")
	# 監督一次
	var ap0 := int(ch["ap"])
	sim.cmd_camp_supervise(pid, "treasury")
	check(absf(float((c["build"] as Dictionary)["progress"]) - 2.3) < 1e-6, "監督一次: 政治 50 + 木匠 50 + 頭目 = 2.3")
	check(int(ch["ap"]) == ap0 - 10, "監督扣行動力 10")
	check(int(ch["militia"]["performance"]) > 0, "監督加績效")
	# 監督到完成
	for i in 100:
		sim.cmd_camp_supervise(pid, "treasury")
	check(int(c["facilities"]["treasury"]) == 2 and (c["build"] as Dictionary).is_empty(), "監督滿 → 金庫升到 2 級")
	check(_any(msgs, "升到 2 級"), "升級完成訊息")
	# 封頂測試
	c["facilities"]["camp"] = 10
	sim.cmd_camp_upgrade(pid, "camp")
	check(_last(msgs).contains("封頂"), "封頂唔可以再升")


func _any(msgs: Array, sub: String) -> bool:
	for m in msgs:
		if String(m).contains(sub):
			return true
	return false


# ================= 義勇軍工作 =================
func t_works(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	_mil(sim, ch, "xuchang")
	ch["militia"]["hasCity"] = false
	sim.cmd_militia_work(pid, "kaiken")
	check(_last(msgs).contains("冇呢種工作"), "無城池做唔到開墾")
	ch["militia"]["hasCity"] = true
	# 內政: 開墾
	sim.cmd_militia_work(pid, "kaiken")
	check(int(sim.city_attrs("xuchang")["kaiken"]) == 52, "開墾: 城池開墾 +2")
	check(int(ch["ap"]) == 100000 - 10, "工作扣行動力 10")
	check(int(ch["militia"]["performance"]) == 10, "開墾績效 +10")
	var wv := sim.militia_work_view(pid)
	var rows: Array = wv["works"]
	check(rows.size() == 22 and int(wv["allWorks"]) == 22, "militia_work_view 22 項")
	# 商情
	sim.cmd_militia_work(pid, "shangqing")
	check(int(ch["militia"]["camp"]["trade"]["xuchang"]) == 5, "商情情報值 +5")
	# 訓練
	sim.cmd_militia_work(pid, "xunlian")
	check(int(ch["militia"]["camp"]["train"]) > 0, "訓練度上升")
	# 徵兵
	sim.cmd_militia_work(pid, "zhengbing")
	check(int(ch["militia"]["camp"]["stores"]["soldiers"]) == 10000, "徵兵 +10000 (兵營 0 級無上限)")
	# 軍馬
	var gold0 := int(ch["gold"])
	sim.cmd_militia_work(pid, "junma")
	check(int(ch["militia"]["camp"]["stores"]["horses"]) == 10000, "軍馬 +10000")
	check(int(ch["gold"]) == gold0 - 1000000, "軍馬扣 100 萬")
	# 捐錢
	var gold1 := int(ch["gold"])
	sim.cmd_militia_work(pid, "juanqian")
	check(int(ch["militia"]["camp"]["stores"]["gold"]) == 10000, "捐錢 → 軍資 +10000")
	check(int(ch["gold"]) == gold1 - 10000, "捐錢扣 10000")
	# 捐糧 (物資)
	RulesShop.add_item(ch["bag"], 25003, 100)
	sim.cmd_militia_work(pid, "juanliang")
	check(int(ch["militia"]["camp"]["stores"]["grain"]) == 10000 and RulesShop.count_item(ch["bag"], 25003) == 0, "捐糧 → 糧秣 +10000、扣物資")
	# 冇材料做唔到
	sim.cmd_militia_work(pid, "juanliang")
	check(_last(msgs).contains("物資唔夠"), "冇物資做唔到")
	# 行動力不足
	ch["ap"] = 5
	sim.cmd_militia_work(pid, "kaiken")
	check(_last(msgs).contains("行動力不足"), "行動力不足做唔到")
	ch["ap"] = 100000
	# 義勇軍庫存唔夠 (軍糧: 要 grain)
	ch["militia"]["camp"]["stores"]["grain"] = 0
	sim.cmd_militia_work(pid, "junliang")
	check(_last(msgs).contains("庫存唔夠"), "義勇軍庫存唔夠做唔到軍糧")


func t_work_expert(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_mil(sim, ch, "xuchang")
	ch["expert"]["kaiken"] = 30      # 2 級 → domestic_mult 1.5
	check(sim.expert_lv(ch, "kaiken") == 2, "開墾專長 2 級")
	sim.cmd_militia_work(pid, "kaiken")
	check(int(sim.city_attrs("xuchang")["kaiken"]) == 53, "專長 2 級: 開墾 +3")
	check(int(ch["militia"]["performance"]) == 10 + 2 * 5, "專長 2 級: 績效 10+10")
	# 指派加成
	sim.cmd_eval_assign(pid, ["donate"])
	sim.cmd_militia_work(pid, "juanqian")
	check(int(ch["militia"]["performance"]) == 20 + 15 + 20, "有指派: 捐錢績效 15+20 (累加)")


# ================= 評定會議 =================
func t_eval(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	_mil(sim, ch, "xuchang")
	sim.cmd_eval_assign(pid, ["nope"])
	check(_last(msgs).contains("唔可以指派"), "唔可以指派未知類別")
	sim.cmd_eval_assign(pid, ["donate", "supervise", "trade", "donate"])
	check(_last(msgs).contains("最多指派 3 種") or _last(msgs).contains("指派本月工作"), "重複/超額處理")
	ch["militia"]["eval"] = {}
	sim.cmd_eval_assign(pid, ["donate", "supervise", "trade"])
	check((ch["militia"]["eval"]["kinds"] as Array).size() == 3, "指派 3 種工作")
	# 會議: 績效 110 → 功績 +20，歸零
	ch["militia"]["performance"] = 110
	ch["militia"]["merit"] = 0
	sim.cmd_eval_meeting(pid, ["supervise"])
	check(int(ch["militia"]["merit"]) == 20, "開會: 績效 110 → 功績 +20")
	check(int(ch["militia"]["performance"]) == 0, "開會: 績效歸 0")
	check(ch["militia"]["eval"]["kinds"] == ["supervise"], "開會: 重新指派")
	check(int(ch["militia"]["eval"]["lastMerit"]) == 20, "開會: lastMerit 記錄")
	var ev := sim.eval_view(pid)
	check(bool(ev["founded"]) and int(ev["merit"]) == 20 and int(ev["nextDelta"]) == -30, "eval_view read-model")
	# 唔係頭目唔可以召開
	ch["militia"]["role"] = "member"
	sim.cmd_eval_meeting(pid, [])
	check(_last(msgs).contains("頭目"), "唔係頭目開唔到會")
	ch["militia"]["role"] = "banner"
	# 未成立
	ch["militia"]["founded"] = false
	sim.cmd_eval_meeting(pid, [])
	check(_last(msgs).contains("未成立"), "未成立開唔到會")


func t_eval_daily(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_mil(sim, ch, "xuchang")
	ch["militia"]["performance"] = 350    # 301~400 → +60
	ch["militia"]["merit"] = 0
	sim._eval_daily(30)
	check(int(ch["militia"]["merit"]) == 60, "每月初一自動結算: 績效 350 → 功績 +60")
	check(int(ch["militia"]["performance"]) == 350, "月初結算唔清績效 (等開會先清)")
	sim._eval_daily(30)
	check(int(ch["militia"]["merit"]) == 60, "同一期唔會重複結算")
	ch["militia"]["performance"] = 20
	sim._eval_daily(60)
	check(int(ch["militia"]["merit"]) == 30, "下一期: 20 → -30 (60-30)")
	sim._eval_daily(31)
	check(int(ch["militia"]["merit"]) == 30, "月中唔結算")


# ================= 團體任務接軌 =================
func t_group_hook(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_mil(sim, ch, "xuchang")
	# 完成 group_recruit_soldier (2 個 talk) → 績效 +30
	var npc: Dictionary = data.quest_npcs["recruit_officer"]
	_put(sim, pid, int(npc["x"]) + 1, int(npc["y"]))
	sim.cmd_quest_talk(pid, "recruit_officer")
	sim.cmd_quest_talk(pid, "recruit_officer")
	check(bool(ch["questDone"].get("group_recruit_soldier", false)), "團體任務完成")
	check(int(ch["militia"]["performance"]) == int(data.camp["questPerf"]), "團體任務完成 → 義勇軍績效 +30")
	# 非團體任務唔加績效
	var p0 := int(ch["militia"]["performance"])
	ch["questDone"]["some_other"] = true
	sim._on_militia_quest_done({"type": "newbie", "id": "some_other"})
	check(int(ch["militia"]["performance"]) == p0, "非團體任務唔加績效")


func t_repeat(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_mil(sim, ch, "xuchang")
	ch["questDone"] = {"group_recruit_soldier": true, "group_zixu": true, "newbie_mystery": true}
	# 每日重複 (紫虛上人)
	sim._militia_quest_reset(5)
	check(not bool(ch["questDone"].get("group_zixu", false)), "每日重複: 一日後清旗標")
	check(bool(ch["questDone"].get("group_recruit_soldier", false)), "月中: 每月任務唔清")
	check(bool(ch["questDone"].get("newbie_mystery", false)), "非重複任務唔清")
	# 每月重複
	sim._militia_quest_reset(30)
	check(not bool(ch["questDone"].get("group_recruit_soldier", false)), "每月初一: 每月任務清旗標")
	check(bool(ch["questDone"].get("newbie_mystery", false)), "非重複任務唔清 (月)")
	var q: Dictionary = {}
	for x in data.quests:
		if String(x["id"]) == "group_recruit_soldier":
			q = x
	check(String(q.get("repeat", "")) == "monthly" and bool(q["pre"]["militia"]), "group_recruit_soldier = monthly + militia")
	# 完成後可以重接
	ch["questDone"].erase("group_recruit_soldier")
	check(RulesQuest.pre_ok(data, q, ch), "清咗旗標可以重接")


func t_daywindow(data: GameData) -> void:
	var r := _new(data)
	var ch: Dictionary = r[2]
	var sj: Dictionary = data.quest_npcs["shenjing_lao"]
	var lp: Dictionary = data.quest_npcs["luopo_lao"]
	check(not RulesQuest.npc_visible(sj, ch, 40, 10), "神經老人: 第 10 日唔見")
	check(RulesQuest.npc_visible(sj, ch, 40, 16) and RulesQuest.npc_visible(sj, ch, 40, 21), "神經老人: 16~21 日見")
	check(not RulesQuest.npc_visible(sj, ch, 40, 22), "神經老人: 第 22 日唔見")
	check(RulesQuest.npc_visible(lp, ch, 40, 10) and RulesQuest.npc_visible(lp, ch, 40, 15), "落魄老人: 10~15 日見")
	check(not RulesQuest.npc_visible(lp, ch, 40, 9) and not RulesQuest.npc_visible(lp, ch, 40, 16), "落魄老人: 窗口外唔見")
	check(RulesQuest.npc_visible(sj, ch, 40), "唔傳 day: 唔檢查日窗口 (兼容舊 call)")
	check(RulesQuest.day_in_window(12, 10, 15) and not RulesQuest.day_in_window(9, 10, 15), "day_in_window")


# ================= 存檔 =================
func t_save(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_mil(sim, ch, "xuchang")
	RulesShop.add_item(ch["bag"], 25001, 20000)
	RulesShop.add_item(ch["bag"], 25053, 20000)
	RulesShop.add_item(ch["bag"], 25002, 5000)
	RulesShop.add_item(ch["bag"], 25054, 10000)
	RulesShop.add_item(ch["bag"], 25006, 5000)
	ch["workLv"] = {"carpentry": {"lv": 50, "exp": 0}}
	ch["attrs"]["pol"] = 50
	sim.cmd_camp_upgrade(pid, "treasury")
	sim.cmd_militia_work(pid, "kaiken")
	sim.cmd_militia_work(pid, "juanqian")
	sim.cmd_eval_assign(pid, ["donate"])
	ch["militia"]["performance"] = 350
	sim._eval_daily(30)
	var s1 := sim.save_string()
	var loaded := Sim.load_string(data, s1)
	var lch := loaded.player_ch()
	var lc: Dictionary = lch["militia"]["camp"]
	check(int(lc["facilities"]["treasury"]) == 1 and not (lc["build"] as Dictionary).is_empty(), "存檔: 設施級 + 建設進度保留")
	check(int((lc["stores"] as Dictionary)["gold"]) == 10000, "存檔: 軍資保留")
	check(int(lch["militia"]["merit"]) == 60 and int(lch["militia"]["performance"]) == 350, "存檔: 功績/績效保留")
	check(lch["militia"]["eval"]["kinds"] == ["donate"], "存檔: 指派保留")
	check(loaded.save_string() == s1, "存檔: save→load→save 一致")
	# 舊存檔: 冇 camp/merit/performance/eval/role/hasCity
	var d: Dictionary = JSON.parse_string(s1)
	for e in d["state"]["ents"].values():
		if e.has("ch") and (e["ch"].get("militia", {}) is Dictionary):
			for k in ["camp", "merit", "performance", "eval", "role", "hasCity"]:
				e["ch"]["militia"].erase(k)
	var old := Sim.load_string(data, JSON.stringify(d))
	var opid := int(old.state["player_id"])
	var och := old.player_ch()
	check(String(old.militia_role(och)) == "banner" and not old.militia_has_city(och), "舊存檔: 補 role/hasCity 預設")
	var oev := old.eval_view(opid)
	check(int(oev["merit"]) == 0 and int(oev["performance"]) == 0, "舊存檔: 補功績/績效 0")
	var ov := old.camp_view(opid)
	check(ov["facilities"].size() == 10 and int(ov["level"]) == 1, "舊存檔: camp 設施補初值")
	och["ap"] = 100000
	och["militia"]["hasCity"] = true
	old.cmd_militia_work(opid, "kaiken")
	check(int((och["militia"]["camp"] as Dictionary)["facilities"]["camp"]) == 1, "舊存檔: 補完 camp 照做到工作")
	check(int(och["militia"]["performance"]) == 10, "舊存檔: 工作照加績效")


func _seq(data: GameData) -> String:
	var r := _new(data, 7)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_mil(sim, ch, "xuchang")
	sim.cmd_militia_work(pid, "kaiken")
	sim.cmd_militia_work(pid, "shangqing")
	sim.cmd_eval_assign(pid, ["trade"])
	sim.cmd_militia_work(pid, "juanqian")
	ch["militia"]["performance"] = 500
	sim._eval_daily(30)
	for i in 200:
		sim.step()
	return sim.save_string()


func t_determinism(data: GameData) -> void:
	check(_seq(data) == _seq(data), "決定性: 同種子同操作 → 同存檔")


# ---- 營地進階【自訂】: 召喚部將 / 材料轉入轉出 / 兵營情報 ----
func t_adv(data: GameData) -> void:
	var r := _new(data, 71)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	var m := _mil(sim, ch, "xuchang")
	var md: Dictionary = sim._city_map("xuchang")
	var ap: Vector2i = sim._city_anchor(md)
	_put(sim, pid, ap.x, ap.y)
	# 兵營情報
	var iv := sim.camp_intel_view(pid)
	check(not bool(iv["ok"]), "情報: 未起兵營 → 睇唔到")
	var c := sim._camp_of(ch)
	c["facilities"]["barracks"] = 1
	iv = sim.camp_intel_view(pid)
	check(bool(iv["ok"]) and not (iv["generals"] as Array).is_empty(), "情報: 兵營 1 級 → 有根據地武將名單")
	var gid := int(iv["generals"][0]["id"])
	check(String(iv["generals"][0]["status"]) == "喺城", "情報: 預設喺城")
	# 召喚部將
	sim.cmd_camp_call_back(pid, gid)
	check(_last(msgs).find("5 級") >= 0, "召喚: 營地未夠 5 級拒絕 (%s)" % _last(msgs))
	c["facilities"]["camp"] = 5
	sim.cmd_camp_call_back(pid, gid)
	check(_last(msgs).find("唔使召喚") >= 0, "召喚: 喺城嘅唔使召喚")
	for i in 7:
		sim._gen_state(gid)["awayMonth"] = sim._month()
		sim.cmd_camp_call_back(pid, gid)
	check(int(sim._gen_state(gid).get("awayMonth", -1)) == sim._month(), "召喚: 每月 6 次用晒 → 第 7 次拒絕")
	check(int((c["callBack"] as Dictionary)["n"]) == 6, "召喚: 計數 6")
	sim.state["clock"]["day"] = int(sim.state["clock"]["day"]) + 40
	sim._gen_state(gid)["awayMonth"] = sim._month()
	sim.cmd_camp_call_back(pid, gid)
	check(int(sim._gen_state(gid)["awayMonth"]) == -1, "召喚: 下個月重新計，召得返")
	_put(sim, pid, 5, 5)
	sim._gen_state(gid)["awayMonth"] = sim._month()
	sim.cmd_camp_call_back(pid, gid)
	check(_last(msgs).find("根據地") >= 0, "召喚: 唔喺根據地拒絕")
	_put(sim, pid, ap.x, ap.y)
	# 材料轉入轉出
	var item := 25001
	RulesShop.add_item(ch["bag"], item, 50)
	sim.cmd_camp_mat(pid, item, 10, "in")
	check(_last(msgs).find("9 級") >= 0, "材料: 材料庫未 9 級唔可以轉入")
	c["facilities"]["matstore"] = 9
	sim.cmd_camp_mat(pid, item, 10, "in")
	check(int(c["matItems"][str(item)]) == 10 and RulesShop.count_item(ch["bag"], item) == 40, "材料: 轉入 10")
	sim.cmd_camp_mat(pid, item, 5, "out")
	check(int(c["matItems"][str(item)]) == 10, "材料: 9 級唔可以轉出")
	sim.cmd_camp_mat(pid, 1001, 1, "in")
	check(_last(msgs).find("只收材料") >= 0, "材料: 非材料拒絕")
	c["facilities"]["matstore"] = 10
	sim.cmd_camp_mat(pid, item, 4, "out")
	check(int(c["matItems"][str(item)]) == 6 and RulesShop.count_item(ch["bag"], item) == 44, "材料: 10 級轉出 4")
	sim.cmd_camp_mat(pid, item, 99, "out")
	check(int(c["matItems"][str(item)]) == 6, "材料: 轉出超量拒絕")
	sim.cmd_camp_mat(pid, item, 6, "out")
	check(not (c["matItems"] as Dictionary).has(str(item)), "材料: 清空移除鍵")
	var cap := RulesCamp.facility_cap(data.camp, "matstore", 10, "stack")
	RulesShop.add_item(ch["bag"], item, cap + 100)
	sim.cmd_camp_mat(pid, item, cap + 100, "in")
	check(int(c["matItems"][str(item)]) == cap, "材料: 堆疊上限 %d" % cap)
	var v := sim.camp_view(pid)
	check((v["matItems"] as Dictionary).has(str(item)) and int(v["callBackLeft"]) <= 6, "view: 有 matItems / callBackLeft")
