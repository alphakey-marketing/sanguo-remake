extends "res://sim/sim_quest.gd"
# Sim 繼承鏈 第 3 層: 設施 / 升級點數 / 建角欄位 / 移動 / 傳送 / 搭話

# 玩家/機械人 意圖

# 設施互動 (Step 3.2): training=練兵場 school=私塾 temple=寺廟
func cmd_facility(id: int, key: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var f: Dictionary = data.facilities.get(key, {})
	if f.is_empty():
		return
	if not _near(e, int(f["x"]), int(f["y"])):
		return _msg(id, "要行近%s先得" % f["name"])
	var ch: Dictionary = e["ch"]
	match key:
		"training": _fac_training(e, ch, f)
		"trainer": _fac_restsp(e, ch, f)
		"school":
			var qid := _fac_ensure_quest(ch, "school")
			if _fac_attr(e, ch, f, "pol", qid != ""):
				if qid != "":
					_finish_fac_quest(e, ch, qid, "school")
		"temple":
			var qid2 := _fac_ensure_quest(ch, "temple")
			if _fac_attr(e, ch, f, "cha", qid2 != ""):
				if qid2 != "":
					_finish_fac_quest(e, ch, qid2, "temple")


# 練兵場【原】: 2 人對練, 扣 HP+SP, 直接加 EXP (F8: 取代歷練)
func _fac_training(e: Dictionary, ch: Dictionary, f: Dictionary) -> void:
	var lv := int(ch["level"])
	var mhp := RulesStats.max_hp(lv, ch["attrs"])
	var msp := RulesStats.max_sp(lv, ch["attrs"])
	var id := int(e["id"])
	if tick < int(e.get("train_cd", 0)):
		return _msg(id, "啱啱練完，抖陣先")
	if int(ch["hp"]) < mhp * 0.35:
		return _msg(id, "體力唔夠對練 (HP 要 > 35%)")
	# 附近要有拍檔 (玩家或 bot)
	var partner := {}
	for b in ents.values():
		if int(b["id"]) == id or not b.has("ch") or int(b["hp"]) <= 0:
			continue
		if _near(e, int(b["x"]), int(b["y"])):
			partner = b
			break
	if partner.is_empty():
		return _msg(id, "附近冇人可以對練")
	ch["hp"] = maxi(1, int(ch["hp"]) - MathX.js_round(mhp * float(f["costHp"])))
	ch["sp"] = maxi(1, int(ch["sp"]) - MathX.js_round(msp * float(f["costSp"])))
	var pch: Dictionary = partner["ch"]
	pch["hp"] = maxi(1, int(pch["hp"]) - MathX.js_round(RulesStats.max_hp(int(pch["level"]), pch["attrs"]) * float(f["costHp"])))
	partner["hp"] = int(pch["hp"])
	_sync_stats(e)
	var gain := maxi(int(f["expMin"]), MathX.js_round(RulesStats.exp_to_next(lv) * float(f["expPct"])))
	RulesStats.gain_exp(data, ch, gain)
	_sync_stats(e)
	e["train_cd"] = tick + int(f["cooldownTicks"])
	_emit({"k": "train", "src": id, "partner": partner["name"], "exp": gain})


# 練兵場小兵【原】: 免費回滿 SP (S01a, spec 01 §6)
func _fac_restsp(e: Dictionary, ch: Dictionary, f: Dictionary) -> void:
	var id := int(e["id"])
	if tick < int(e.get("restsp_cd", 0)):
		return _msg(id, "小兵啱啱幫你回復完，抖陣先")
	var msp := RulesStats.max_sp(int(ch["level"]), ch["attrs"])
	if int(ch["sp"]) >= msp:
		return _msg(id, "體力已滿")
	ch["sp"] = msp
	e["restsp_cd"] = tick + int(f["cooldownTicks"])
	_sync_stats(e)
	_msg(id, "小兵幫你回復晒體力")


# 私塾/寺廟【原】: 政治/魅力 +1, 扣 SP (+MP) + 金。free=true = 新手修練退款 (spec 06 §2，第一次唔使金)。
# 回傳成功與否 (新手任務只喺成功時推進)
func _fac_attr(e: Dictionary, ch: Dictionary, f: Dictionary, attr: String, free: bool = false) -> bool:
	var id := int(e["id"])
	var lv := int(ch["level"])
	var cost_gold := 0 if free else int(f.get("gold", 0))
	var cost_sp := MathX.js_round(RulesStats.max_sp(lv, ch["attrs"]) * float(f.get("costSp", 0.0)))
	var cost_mp := MathX.js_round(RulesStats.max_mp(lv, ch["attrs"]) * float(f.get("costMp", 0.0)))
	if int(ch["gold"]) < cost_gold:
		_msg(id, "要 %d 金" % cost_gold)
		return false
	if int(ch["sp"]) < cost_sp or int(ch["mp"]) < cost_mp:
		_msg(id, "精神不足 (要 SP%d/MP%d)" % [cost_sp, cost_mp])
		return false
	var v := int(ch["attrs"][attr])
	if v >= int(f["attrCap"]):
		_msg(id, "屬性已到上限 (%d)" % int(f["attrCap"]))
		return false
	ch["gold"] = int(ch["gold"]) - cost_gold
	ch["sp"] = int(ch["sp"]) - cost_sp
	ch["mp"] = int(ch["mp"]) - cost_mp
	ch["attrs"][attr] = v + 1
	_sync_stats(e)
	var an := "政治" if attr == "pol" else "魅力"
	_emit({"k": "train", "src": id, "type": "attr", "attr": an, "val": v + 1})
	return true


# ================= 升級點數 / 建角欄位 (Step 7.5, spec 01 §1/§2/§5) =================

# 升級自由點數: 扣 1 點，str/agi/int/spi +1；政治/魅力唔可以用升級點 (只能私塾/寺廟)
func cmd_raise_attr(id: int, attr: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var code := RulesStats.can_raise(ch, attr)
	match code:
		1: return _msg(id, "冇可分配點數 (升呢俾 %d 點)" % RulesStats.UPGRADE_POINTS)
		2: return _msg(id, "政治/魅力唔可以用升級點，去私塾/寺廟修練")
		3: return _msg(id, "屬性已到上限 99")
	RulesStats.raise_attr(ch, attr)
	_sync_stats(e)
	_emit({"k": "attr_rise", "src": id, "attr": attr, "val": int(ch["attrs"][attr]), "points": int(ch["attrPoints"])})


# 一鍵自動分配【自訂】: 按 classes.json.growth 建議比例派晒所有點
func cmd_auto_assign(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var ch: Dictionary = e["ch"]
	if int(ch.get("attrPoints", 0)) <= 0:
		return _msg(id, "冇可分配點數")
	RulesStats.auto_assign_points(ch, data.classes[ch["classId"]])
	_sync_stats(e)
	_emit({"k": "attr_auto", "src": id, "points": int(ch["attrPoints"])})
	_msg(id, "自動分配合成 (剩 %d 點)" % int(ch["attrPoints"]))


# 新手城建角揀城 (UAT-feedback, spec 12 §1)【自訂】: 未出發(Lv1)先可以揀；揀完搬去嗰城客棧
# 只允許有 city 地圖嘅「新手城」（許昌/襄陽/新野）
const NEWBIE_CITIES := ["xuchang"]    # 新手城只限許昌

func newbie_cities() -> Array:
	var out: Array = []
	if bool(data.world.get("origStart", false)):
		var om: Dictionary = data.map_by_id.get(String(data.world.get("origHome", "")), {})
		return [{"id": "xuchang", "name": String(om.get("name", "許昌")), "spawn": (om.get("spawn", []) as Array)}]
	for c in NEWBIE_CITIES:
		var md := _city_map(c)
		if not md.is_empty():
			out.append({"id": c, "name": String(md.get("name", c)), "spawn": (md.get("spawn", []) as Array)})
	return out


# 揀做新手城: 記低 ch.homeCity + 搬去嗰城（客棧側）
func cmd_set_home(id: int, city_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var ch: Dictionary = e["ch"]
	if int(ch["level"]) != 1:
		return _msg(id, "出發咗就唔可以改新手城")
	var md := _city_map(city_id)
	if md.is_empty() or not (city_id in NEWBIE_CITIES):
		return _msg(id, "揀嘅城未開放")
	# 搬去嗰城客棧側（同 cmd_travel 咁直接改座標）
	var inn := nearest_inn(String(md["id"]))
	var dest := _free_near(int(inn["x"]), int(inn["y"]))
	e["x"] = dest.x
	e["y"] = dest.y
	e["tx"] = dest.x
	e["ty"] = dest.y
	e.erase("path")
	e["atk_target"] = 0
	ch["homeCity"] = city_id
	if e.has("goto"):
		e.erase("goto")
	if e.has("casting"):
		e.erase("casting")
		_emit({"k": "cast_interrupted", "dst": id, "reason": "travel"})
	_msg(id, "新手城揀做「%s」" % String(md.get("name", city_id)))
	_emit({"k": "home", "dst": id, "city": city_id, "x": e["x"], "y": e["y"], "map": map_id_at(int(e["x"]), int(e["y"]))})


# 建角期間轉職業 (Step 9): 未出發 (Lv1) 先可以；重新生成角色
func cmd_select_class(id: int, class_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var ch: Dictionary = e["ch"]
	if int(ch["level"]) != 1:
		return _msg(id, "出發咗就唔可以轉職業")
	var cls: Dictionary = data.classes.get(class_id, {})
	if cls.is_empty() or not bool(cls["enabled"]):
		return _msg(id, "職業未開放")
	var name := str(ch["name"])
	ents.erase(id)
	var ne := _spawn_actor(name, "player", class_id)
	state["player_id"] = int(ne["id"])
	_sync_quest_npcs()
	_emit({"k": "reclass", "id": int(ne["id"]), "class": class_id, "name": name})
	_msg(int(ne["id"]), "轉職做「%s」" % cls["name"])


# 轉職 (S01d, spec 01 §7): 等級 + 對應轉職考試任務完成 → 職階 +1。
# 效果: 職名變化、進階武器解鎖、四招起絶招解鎖、專長上限提升（規則層 RulesClass/RulesExpert）
func cmd_class_promote(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var ok := RulesClass.promote_ok(data, ch)
	if not bool(ok["ok"]):
		return _msg(id, str(ok["why"]))
	var tier := int(ok["tier"])
	ch["tier"] = tier
	var cls: Dictionary = data.classes.get(str(ch["classId"]), {})
	var name := RulesClass.title_of(cls, tier)
	_sync_stats(e)
	_emit({"k": "promote", "src": id, "tier": tier, "title": name, "lv": int(ch["level"])})
	_msg(id, "恭喜！你已經轉職做「%s」！（%s）" % [name, RulesClass.tier_name_of(tier)])
	_msg(id, "進階武器解鎖，四招起絕招解鎖，專長上限提升！")


# 姓名【原】: 1~8 字，決定後（理念測驗一交）唔可以改
func cmd_set_name(id: int, name: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var ch: Dictionary = e["ch"]
	if bool(ch.get("nameLocked", false)):
		return _msg(id, "姓名已經決定咗，唔可以改")
	name = name.strip_edges()
	if name.length() < 1 or name.length() > 8:
		return _msg(id, "姓名要 1~8 字")
	ch["name"] = name
	e["name"] = name
	_msg(id, "姓名改做「%s」" % name)


# 稱號 (F1): 唔可以自由輸入，只可以揀已解鎖 (ch.titles) 嘅；空字串 = 除下稱號
func cmd_set_title(id: int, title: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	title = title.strip_edges()
	if title != "" and not (e["ch"].get("titles", []) as Array).has(title):
		return _msg(id, "未解鎖呢個稱號")
	e["ch"]["title"] = title
	_msg(id, "稱號改做「%s」" % title if title != "" else "已除下稱號")


# 臉譜: 8 部位，款式 1..count (data/face.json)
func cmd_set_face(id: int, part: String, value: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var count: int = int(data.face_parts.get(part, 0))
	if count <= 0 or value < 1 or value > count:
		return _msg(id, "冇呢個部位/款式")
	e["ch"]["face"][part] = value
	_msg(id, "%s 款式設為 %d" % [part, value])


# 理念測驗: 一次過交答卷 (data/quiz.json 12 題，每題 0/1)，決定理念。決定了就唔可以改
func cmd_submit_quiz(id: int, answers: Array) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var ch: Dictionary = e["ch"]
	if not str(ch.get("ideology", "")).is_empty():
		return _msg(id, "理念已經決定咗，唔可以改")
	if not RulesQuiz.valid_answers(data, answers):
		return _msg(id, "答卷唔啱 (要 %d 題)" % (data.quiz as Array).size())
	var res := RulesQuiz.score(data, answers)
	ch["ideology"] = str(res["ideology"])
	ch["nameLocked"] = true
	ch["quizAnswers"] = []
	for a in answers:
		ch["quizAnswers"].append(int(a))
	_emit({"k": "quiz", "src": id, "ideology": str(res["ideology"])})
	_msg(id, "理念測驗完成：你嘅理念係「%s」" % str(res["ideology"]))
# 玩家手動行 (搖桿/撳地) = 取消自動尋路
func cmd_move(id: int, x: int, y: int) -> void:
	var e := ent(id)
	if not e.is_empty() and e.has("goto") and is_free(x, y):
		e.erase("goto")
		if e["kind"] == "player":
			_msg(id, "取消自動尋路")
	_move(id, x, y)


# 行去 (x,y): 直線唔通就 A* (spec 12 §3)；自動尋路/居民路由都用呢個
func _move(id: int, x: int, y: int, cap: int = 0) -> void:
	var e := ent(id)
	if e.is_empty() or not is_free(x, y):
		return
	if bool(e.get("down", false)):        # 倒地期間唔可以郁【自訂新增】
		return
	var ch: Dictionary = e.get("ch", {})
	if not ch.is_empty() and RulesSpell.blocks_move(ch.get("status", {}), tick) and not _friend_effect_active(e, "stun_resist"):  # 中邪定身【原】(戰騎「穩重」友好技免疫, U13)
		if e["kind"] == "player":
			_msg(id, "中邪緊，郁唔到")
		return
	if e.has("casting"):                     # 吟唱期間移動 = 取消【原】
		e.erase("casting")
		if e["kind"] == "player":
			_msg(id, "移動取消咗吟唱")
		_emit({"k": "cast_interrupted", "dst": id, "reason": "move"})
	if cap <= 0:
		cap = mini(PATH_CAP, 200 + 40 * (absi(x - int(e["x"])) + absi(y - int(e["y"]))))   # 近路唔使大搜
	_set_dest(e, x, y, cap)
	e["atk_target"] = 0      # 手動行路取消攻擊


func cmd_attack(id: int, target: int) -> void:
	var e := ent(id)
	var t := ent(target)
	# S03a: 開放居民 (bot) 做攻擊目標（含紅名殺人魔 NPC）；安全區照禁（_think_player 出手前擋）
	if e.has("ch") and int(e["hp"]) > 0 and (t.get("kind", "") == "mob" or t.get("kind", "") == "bot"):
		e["atk_target"] = target      # 安全區入面都可以追過去，行出安全區先真正出手 (見 _think_player)


# 傳送點 (Step 3.2+): 城內/城外之間即時傳送，要行近出發點
func cmd_travel(id: int, point_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var from_p := travel_point_by_id(point_id)
	if from_p.is_empty():
		return
	var in_rect := false
	if from_p.has("rect"):               # 矩形門: 企喺區入面就得，唔使行近
		var rc: Array = from_p["rect"]
		in_rect = int(e["x"]) >= int(rc[0]) and int(e["x"]) <= int(rc[2]) and int(e["y"]) >= int(rc[1]) and int(e["y"]) <= int(rc[3])
	if not in_rect and not _near(e, int(from_p["x"]), int(from_p["y"])):
		return _msg(id, "要行近%s先得" % String(from_p["name"]))
	var to_p := travel_point_by_id(String(from_p["to"]))
	if to_p.is_empty():
		return
	var why := _gate_why(e, from_p.get("gate", {}))
	if why != "":
		return _msg(id, why)
	var land: Array = to_p.get("land", [int(to_p["x"]), int(to_p["y"])])   # 有 land = 落喺門外，唔會即刻彈返轉頭
	e["x"] = int(land[0])
	e["y"] = int(land[1])
	e["tx"] = e["x"]
	e["ty"] = e["y"]
	e.erase("path")
	e["atk_target"] = 0
	if e.has("casting"):                     # 傳送 = 斷吟唱
		e.erase("casting")
		_emit({"k": "cast_interrupted", "dst": id, "reason": "travel"})
	_emit({"k": "travel", "dst": id, "to": String(to_p["name"]), "x": e["x"], "y": e["y"],
		"map": map_id_at(int(e["x"]), int(e["y"]))})


# 門禁 (Step 16 歷史任務): window = 時辰窗口先入得 (襄陽監獄子~丑)；item = 身上要有 (丁原家鑰匙)。"" = 過得
func _gate_why(e: Dictionary, gate: Dictionary) -> String:
	if gate.is_empty():
		return ""
	var w: Dictionary = gate.get("window", {})
	if not w.is_empty() and not RulesQuest.ke_in_window(int(_clock()["ke"]), int(w["startKe"]), int(w["endKe"])):
		return String(gate.get("msg", "而家入唔到"))
	if gate.has("item") and RulesShop.count_item(e["ch"]["bag"], int(gate["item"])) <= 0:
		return String(gate.get("msg", "冇%s入唔到" % data.names.get(int(gate["item"]), "")))
	return ""


# 行咗一格之後 (step() 叫): 踩中 auto 傳送點 = 過圖；玩家行近史蹟地標 = 第一次彈典故 (spec 12 §4~5)
func _on_moved(e: Dictionary) -> void:
	if not e.has("ch"):
		return
	var pid: String = data.portal_at.get(int(e["y"]) * W + int(e["x"]), "")
	if pid != "":
		cmd_travel(int(e["id"]), pid)
		return
	if e["kind"] != "player":
		return
	for lm in data.landmarks:
		if not RulesCombat.in_range(e["x"], e["y"], int(lm["x"]), int(lm["y"]), float(lm.get("r", 3))):
			continue
		var seen: Array = e["ch"].get("landmarks", [])
		if seen.has(String(lm["id"])):
			continue
		seen.append(String(lm["id"]))
		e["ch"]["landmarks"] = seen
		_emit({"k": "landmark", "dst": int(e["id"]), "id": String(lm["id"]), "name": String(lm["name"]), "text": String(lm["text"])})
		_msg(int(e["id"]), "【%s】%s" % [lm["name"], lm["text"]])


# 跨圖路由 (spec 12 §4): 唔喺 map_id 就行去第一跳嘅門口 (地圖圖 BFS)；返 true = 處理緊 (未到)
func _route_to_map(e: Dictionary, map_id: String) -> bool:
	var cur := map_id_at(int(e["x"]), int(e["y"]))
	if cur == map_id or cur == "":
		return false
	var hop := next_portal(cur, map_id)
	if hop.is_empty():
		return false
	var px := int(hop["x"])
	var py := int(hop["y"])
	if int(e["x"]) == px and int(e["y"]) == py:
		cmd_travel(int(e["id"]), String(hop["id"]))
	elif int(e["tx"]) != px or int(e["ty"]) != py:
		_move(int(e["id"]), px, py, PATH_CAP)      # 門口可能好遠 (成張圖)
	return true


# 大地圖撳城 = 自動尋路 (spec 12 §1 B2): 記低目的地圖，_think_player 每 tick 經 _route_to_map 行；
# 手動行 (cmd_move)/死亡 = 取消；打緊怪暫停，打完繼續
func cmd_goto_map(id: int, map_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var md: Dictionary = data.map_by_id.get(map_id, {})
	if md.is_empty():
		return
	var cur := map_id_at(int(e["x"]), int(e["y"]))
	if cur == map_id:
		e.erase("goto")
		return _msg(id, "你已經喺%s" % md["name"])
	if next_portal(cur, map_id).is_empty():
		return _msg(id, "去唔到%s" % md["name"])
	e["goto"] = map_id
	e["atk_target"] = 0
	_msg(id, "自動尋路：前往%s（行一步就取消）" % md["name"])


# 自動尋路每 tick: 到咗 = 清；返 true = 仲喺路上
func _goto_tick(e: Dictionary) -> bool:
	var goal := String(e.get("goto", ""))
	if goal == "":
		return false
	if _route_to_map(e, goal):
		return true
	e.erase("goto")
	if map_id_at(int(e["x"]), int(e["y"])) == goal:
		_emit({"k": "goto_done", "dst": int(e["id"]), "map": goal})
		_msg(int(e["id"]), "已到達%s" % String(data.map_by_id[goal]["name"]))
	return false


# 地圖圖 BFS 結果快取 (傳送點資料固定；唔入存檔)
var _hops_cache := {}
var _portal_cache := {}


# 兩張地圖之間最少過幾次圖 (BFS；-1 = 去唔到)
func map_hops(from_map: String, to_map: String) -> int:
	var key := from_map + ">" + to_map
	if not _hops_cache.has(key):
		_hops_cache[key] = _map_hops_bfs(from_map, to_map)
	return _hops_cache[key]


func _map_hops_bfs(from_map: String, to_map: String) -> int:
	var dist := {from_map: 0}
	var q: Array = [from_map]
	while not q.is_empty():
		var m: String = q.pop_front()
		if m == to_map:
			return int(dist[m])
		for p in data.travel_points:
			if String(p["map"]) != m:
				continue
			var nm := String(travel_point_by_id(String(p["to"])).get("map", ""))
			if nm != "" and not dist.has(nm):
				dist[nm] = int(dist[m]) + 1
				q.append(nm)
	return -1


# 最近嘅客棧 (過圖次數最少；同分 = data.inns 先嗰間，即許昌)
func nearest_inn(map_id: String) -> Dictionary:
	var best: Dictionary = data.inn
	var bd := 1 << 30
	for x in data.inns:
		var d := map_hops(map_id, String(x["map"]))
		if d >= 0 and d < bd:
			bd = d
			best = x
	return best


# 由 from_map 去 to_map 嘅第一個傳送點 (BFS，傳送點次序固定 → 決定性)
func next_portal(from_map: String, to_map: String) -> Dictionary:
	var key := from_map + ">" + to_map
	if not _portal_cache.has(key):
		_portal_cache[key] = _next_portal_bfs(from_map, to_map)
	return _portal_cache[key]


func _next_portal_bfs(from_map: String, to_map: String) -> Dictionary:
	var first := {from_map: {}}
	var q: Array = [from_map]
	while not q.is_empty():
		var m: String = q.pop_front()
		for p in data.travel_points:
			if String(p["map"]) != m:
				continue
			var nm := String(travel_point_by_id(String(p["to"])).get("map", ""))
			if nm == "" or first.has(nm):
				continue
			first[nm] = p if m == from_map else first[m]
			if nm == to_map:
				return first[nm]
			q.append(nm)
	return {}


func cmd_chat(id: int, text: String) -> void:
	var e := ent(id)
	text = text.strip_edges().substr(0, 60)
	if e.is_empty() or text == "":
		return
	_emit({"k": "chat", "id": id, "name": e["name"], "text": text, "x": e["x"], "y": e["y"]})
	if _has_listener(e):
		_sip_thirst(e)          # 同居民搭話扣飲水度 (Step 14)
	_witness_nearby(e, id, "greet", BotSys.W_GREET)
	_npc_react(e, id)


# ================= 飲水度 (Step 14, spec 01 §9)【原=聊天扣；單機 = 同 NPC 搭話扣】=================
const THIRSTY_LINE := "（你口乾到講唔到幾句，對方都係客套兩句——去客棧飲杯茶先啦）"


func thirst_of(ch: Dictionary) -> int:
	return int(ch.get("thirst", int(data.world["thirst"]["max"])))


# 搭話扣飲水度 → true = 傾得 (LLM 模式)；false = 口渴 (0，只講模板)。只計玩家
func _sip_thirst(e: Dictionary) -> bool:
	if String(e.get("kind", "")) != "player":
		return true
	var ch: Dictionary = e["ch"]
	var t := thirst_of(ch)
	if t <= 0:
		_msg(int(e["id"]), "口渴：飲水度 0，去客棧喝茶先")
		return false
	ch["thirst"] = RulesTitle.sip(t, data.world["thirst"])
	return true


# 附近有冇居民聽到 (有記憶表嘅 NPC)
func _has_listener(e: Dictionary) -> bool:
	for w in ents.values():
		if int(w["id"]) != int(e["id"]) and w.has("mem") and RulesCombat.in_range(e["x"], e["y"], w["x"], w["y"], WITNESS_RANGE):
			return true
	return false


# 居民對打招呼嘅反應 (Step 5.4): brain 淨係揀白名單動作 + 生成話語，數值(好感)已經由
# _witness_nearby 結算好，brain 唔改任何數值
func _npc_react(actor_e: Dictionary, actor_id: int) -> void:
	var actor_ch: Dictionary = ent(actor_id).get("ch", {})
	var karma_tier := RulesKarma.tier(int(actor_ch.get("karma", 0))) if not actor_ch.is_empty() else 3
	for w in ents.values():
		if int(w["id"]) == actor_id or not w.has("mem"):
			continue
		if not RulesCombat.in_range(actor_e["x"], actor_e["y"], w["x"], w["y"], WITNESS_RANGE):
			continue
		var ctx := {"actor_name": actor_e.get("name", ""), "affinity": NpcMemory.affinity(w["mem"], actor_id), "karma_tier": karma_tier}
		var wch: Dictionary = w.get("ch", {})
		if bool(wch.get("resident", false)):       # S09: 居民按 role/當前活動分流對白
			ctx["role"] = String(wch.get("role", ""))
			ctx["activity"] = RulesResident.activity_at(data.residents, RulesClock.shichen_of_ke(int(_clock()["ke"])))
		var res := NpcBrain.decide(ctx, rng.below(4))
		if res["action"] == "ignore":
			continue
		# S09d Tier2 居民：偶發接 LLM（tier 政策抽唔中 / 未啟用 = 模板）
		if _llm_talk(w, String(w["name"]), String(w.get("ch", {}).get("ideology", "")), 0, int(w["x"]), int(w["y"]), actor_id):
			continue
		_emit({"k": "npc_say", "id": w["id"], "name": w["name"], "text": res["line"], "action": res["action"], "x": w["x"], "y": w["y"]})


# 首次開面板簡介睇過就記低 (ch.helpSeen)，唔再彈
func cmd_help_seen(id: int, key: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var seen: Array = e["ch"].get("helpSeen", [])
	if not seen.has(key):
		seen.append(key)
	e["ch"]["helpSeen"] = seen
