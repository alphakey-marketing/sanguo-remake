class_name RulesQuest
extends RefCounted
# 任務系統純函數 (spec 06 §1): quests.json 驗證、pre 條件、stage 推進、獎勵結算、
# NPC 時辰窗口可見性。所有函數無狀態（ch/quests dict 都係參數傳入，直接 mutate 如 RulesShop 一樣）。
# 數值/對話全部喺 data/quests.json + data/quest_npcs.json，呢度只做邏輯。

const QUEST_TYPES := ["newbie", "general", "official", "history", "ultimate", "group", "battle", "expert", "marry", "service"]
const STAGE_TYPES := ["talk", "talk_n", "repeat", "collect", "ask", "facility", "fight"]
const QUEST_ITEM_CATS := [44, 52]          # 任務雜物 / 任務物品 (spec 06 §1.2: 61501 田鼠碎骨等)
const HINT_VARS := ["%v", "%n"]            # hint 內 %v=目前進度 %n=需要數量
const ATTR_KEYS := ["str", "agi", "int", "spi", "pol", "cha"]


# ================= schema 驗證 (data load 後跑，回傳錯誤 String 列表) =================
static func validate(data: GameData) -> Array:
	var errs: Array = []
	var qids := {}
	for q in data.quests:
		var id := String(q.get("id", ""))
		if id == "":
			errs.append("quest 冇 id")
			continue
		if qids.has(id):
			errs.append("quest id 重複: %s" % id)
			continue
		qids[id] = true
		if not QUEST_TYPES.has(String(q.get("type", ""))):
			errs.append("%s: type 唔啱 (%s)" % [id, q.get("type", "")])
		var stages: Array = q.get("stages", [])
		if stages.is_empty() and String(q.get("type", "")) != "service":
			errs.append("%s: 冇 stages" % id)
		for si in stages.size():
			var st: Dictionary = stages[si]
			var t := String(st.get("type", ""))
			if not STAGE_TYPES.has(t):
				errs.append("%s.s%d: stage type 唔啱 (%s)" % [id, si, t])
				continue
			if t == "talk" or t == "repeat" or t == "fight":
				if not data.quest_npcs.has(String(st.get("npc", ""))):
					errs.append("%s.s%d: npc 唔存在 (%s)" % [id, si, st.get("npc", "")])
			if t == "talk_n":
				var npcs: Array = st.get("npcs", [])
				if npcs.size() < int(st.get("n", 0)):
					errs.append("%s.s%d: talk_n npcs 少過 n" % [id, si])
				for nid in npcs:
					if not data.quest_npcs.has(String(nid)):
						errs.append("%s.s%d: talk_n npc 唔存在 (%s)" % [id, si, nid])
			for ti in st.get("takeItems", []):
				if not data.item_ids.has(int(ti[0])):
					errs.append("%s.s%d: takeItems 道具唔存在 (%s)" % [id, si, ti[0]])
			if t == "fight" and not data.monsters.has(int(st.get("monster", 0))):
				errs.append("%s.s%d: fight monster 唔存在 (%s)" % [id, si, st.get("monster", "")])
			if t == "collect":
				var it: Dictionary = st.get("item", {})
				if it.is_empty() or not data.item_ids.has(int(it.get("id", -1))):
					errs.append("%s.s%d: collect item 唔存在" % [id, si])
			if t == "facility":
				if not data.facilities.has(String(st.get("fac", ""))):
					errs.append("%s.s%d: facility 唔存在 (%s)" % [id, si, st.get("fac", "")])
			var gi: Dictionary = st.get("getItem", {})
			if not gi.is_empty() and not data.item_ids.has(int(gi.get("id", -1))):
				errs.append("%s.s%d: getItem 唔存在" % [id, si])
			for gii in st.get("getItems", []):   # 一次派多件 (S06e 地理圖×4)
				if not data.item_ids.has(int(gii[0])):
					errs.append("%s.s%d: getItems 道具唔存在 (%s)" % [id, si, gii[0]])
			if si > 0 and not bool(st.get("done", false)) and stages[si - 1].get("done", false):
				errs.append("%s: stage %d 之後仲有 stage，但 %d 已 done" % [id, si - 1, si - 1])
		var rw: Dictionary = q.get("reward", {})
		if not rw.is_empty():
			for it in rw.get("items", []):
				if not data.item_ids.has(int(it[0])):
					errs.append("%s: reward item 唔存在 (%s)" % [id, it[0]])
			if rw.has("ultimate") and not data.ult_by_id.has(String(rw["ultimate"])):
				errs.append("%s: reward ultimate 唔存在 (%s)" % [id, rw["ultimate"]])
			if rw.has("skill") and not (data.class_skills as Dictionary).has(String(rw["skill"])):
				errs.append("%s: reward skill 唔存在 (%s)" % [id, rw["skill"]])
			if rw.has("expert"):            # 專長認證 (S06e): {skill, level}
				var ex: Dictionary = rw["expert"]
				if not (data.experts.get("skills", {}) as Dictionary).has(String(ex.get("skill", ""))):
					errs.append("%s: reward.expert skill 唔啱 (%s)" % [id, ex.get("skill", "")])
				var ex_lv := int(ex.get("level", 0))
				if ex_lv < 1 or ex_lv > (data.experts.get("levelExp", []) as Array).size():
					errs.append("%s: reward.expert level 唔啱 (%d)" % [id, ex_lv])
		for k in q.get("pre", {}).get("attr", {}):
			if not ATTR_KEYS.has(String(k)):
				errs.append("%s: pre.attr 屬性唔啱 (%s)" % [id, k])
		var pre_v: Dictionary = q.get("pre", {})
		for cid in pre_v.get("classAny", []):       # 允好多個職業之一 (S06e 專長任務)
			if not data.classes.has(String(cid)):
				errs.append("%s: pre.classAny 職業唔啱 (%s)" % [id, cid])
		for k in pre_v.get("expert", {}):           # 專長等級門檻 (S06e)
			if not (data.experts.get("skills", {}) as Dictionary).has(String(k)):
				errs.append("%s: pre.expert 專長唔啱 (%s)" % [id, k])
		for k in pre_v.get("expertAny", {}):        # 任一專長達標 (S06e)
			if not (data.experts.get("skills", {}) as Dictionary).has(String(k)):
				errs.append("%s: pre.expertAny 專長唔啱 (%s)" % [id, k])
		for it in pre_v.get("hasItemAny", []):       # 任一物品都可以觸發 (S06e)
			if not data.item_ids.has(int(it.get("id", -1))):
				errs.append("%s: pre.hasItemAny 道具唔存在 (%s)" % [id, it.get("id", -1)])
		var gv := String(q.get("giver", ""))
		if gv != "" and not data.quest_npcs.has(gv):
			errs.append("%s: giver npc 唔存在 (%s)" % [id, gv])
	var nids := {}
	for n in data.quest_npc_list:
		var nid := String(n.get("id", ""))
		if nid == "":
			errs.append("quest_npc 冇 id")
			continue
		if nids.has(nid):
			errs.append("quest_npc id 重複: %s" % nid)
		nids[nid] = true
		var w: Dictionary = n.get("window", {})
		if not w.is_empty():
			var s := int(w.get("startKe", -1))
			var e := int(w.get("endKe", -1))
			if s < 0 or s > 95 or e < 0 or e > 96:
				errs.append("%s: window 範圍唔啱 (%d~%d)" % [nid, s, e])
		var dw: Dictionary = n.get("dayWindow", {})
		if not dw.is_empty():
			var ds := int(dw.get("startDay", -1))
			var de := int(dw.get("endDay", -1))
			if ds < 1 or de > 30 or ds > de:
				errs.append("%s: dayWindow 範圍唔啱 (%d~%d)" % [nid, ds, de])
	return errs


# ================= NPC 可見性 (時辰窗口 + 等級 + 任務進行中) =================
# ke = 0..95 (0 = 子時 1 刻)；window [startKe, endKe)，endKe <= startKe = 跨日
static func ke_in_window(ke: int, start_ke: int, end_ke: int) -> bool:
	if start_ke < end_ke:
		return ke >= start_ke and ke < end_ke
	return ke >= start_ke or ke < end_ke


# dayWindow = 每月第幾日到第幾日出現 (含頭尾)；day < 0 = 唔檢查
static func day_in_window(day: int, start_day: int, end_day: int) -> bool:
	return day >= start_day and day <= end_day


static func npc_visible(npc: Dictionary, ch: Dictionary, ke: int, day: int = -1) -> bool:
	if ch.is_empty() or bool(npc.get("questOnly", false)):
		return false
	if npc.has("maxLevel") and int(ch["level"]) > int(npc["maxLevel"]):
		return false
	if npc.has("minLevel") and int(ch["level"]) < int(npc["minLevel"]):
		return false
	var w: Dictionary = npc.get("window", {})
	if not w.is_empty() and not ke_in_window(ke, int(w["startKe"]), int(w["endKe"])):
		return false
	var dw: Dictionary = npc.get("dayWindow", {})
	if day >= 0 and not dw.is_empty() and not day_in_window(day, int(dw["startDay"]), int(dw["endDay"])):
		return false
	return true


# 最終顯示: 平時規則 或 任務強制常駐；strictWindow = 任務進行中都要守時辰 (Step 16 董卓卯~酉/獄中曹操子~丑)
static func npc_shown(npc: Dictionary, ch: Dictionary, ke: int, quests: Array, day: int = -1) -> bool:
	if npc_visible(npc, ch, ke, day):
		return true
	if ch.is_empty() or not quest_locks_npc(ch, String(npc.get("id", "")), quests):
		return false
	var w: Dictionary = npc.get("window", {})
	if bool(npc.get("strictWindow", false)) and not w.is_empty():
		return ke_in_window(ke, int(w["startKe"]), int(w["endKe"]))
	var dw: Dictionary = npc.get("dayWindow", {})
	if day >= 0 and not dw.is_empty() and not day_in_window(day, int(dw["startDay"]), int(dw["endDay"])):
		return false
	return true


# 有冇進行中 quest 需要呢個 npc 常駐: giver 或 current stage 目標（talk / talk_n / repeat / fight）
static func quest_locks_npc(ch: Dictionary, npc_id: String, quests: Array) -> bool:
	for q in quests:
		var st: Dictionary = ch.get("quests", {}).get(String(q["id"]), {})
		if st.is_empty() or bool(st.get("done", false)):
			continue
		if String(q.get("giver", "")) == npc_id:
			return true
		var stage := _stage(q, int(st.get("stage", 0)))
		if stage.is_empty():
			continue
		if String(stage.get("npc", "")) == npc_id:
			return true
		if (stage.get("npcs", []) as Array).has(npc_id):
			return true
	return false


# ================= pre 條件 (spec 06 §1.1: 全部要符合先觸發) =================
# 支持: maxLevel/minLevel/level/classId/karmaMin/karmaMax/ideology/attr {k: 最低}/hasItem/questDone
static func pre_ok(data: GameData, q: Dictionary, ch: Dictionary) -> bool:
	var pre: Dictionary = q.get("pre", {})
	if pre.is_empty():
		return true
	var lv := int(ch["level"])
	if pre.has("maxLevel") and lv > int(pre["maxLevel"]):
		return false
	if pre.has("minLevel") and lv < int(pre["minLevel"]):
		return false
	if pre.has("level") and lv < int(pre["level"]):
		return false
	if pre.has("classId") and String(ch.get("classId", "")) != String(pre["classId"]):
		return false
	if pre.has("karmaMin") and int(ch.get("karma", 0)) < int(pre["karmaMin"]):
		return false
	if pre.has("karmaMax") and int(ch.get("karma", 0)) > int(pre["karmaMax"]):
		return false
	if pre.has("ideology") and String(ch.get("ideology", "")) != String(pre["ideology"]):
		return false
	if pre.has("gender"):            # 男/女限定 (S09e 御賜函任務): 由職業表 gender 讀
		var gc: Dictionary = data.classes.get(String(ch.get("classId", "")), {})
		if String(gc.get("gender", "")) != String(pre["gender"]):
			return false
	for k in pre.get("attr", {}):   # 屬性門檻 (Step 16 歷史任務: 魅力 10+)
		if int(ch["attrs"].get(k, 0)) < int(pre["attr"][k]):
			return false
	if pre.has("hasItem"):          # 身上要有道具先觸發 (Step 10 絕招三: 呂代槍文集)
		var need: Dictionary = pre["hasItem"]
		if not RulesShop.has_item(ch["bag"], int(need.get("id", 0)), int(need.get("n", 1))):
			return false
	if pre.has("hasItemAny"):       # 列出多件道具，有其中一件就觸發 (S06e 天文/地理一級)
		var any_item := false
		for it in pre["hasItemAny"]:
			if RulesShop.has_item(ch["bag"], int(it.get("id", 0)), int(it.get("n", 1))):
				any_item = true
				break
		if not any_item:
			return false
	if pre.has("classAny"):         # 職業屬其中一款先觸發 (S06e 天文/地理三四級)
		if not (pre["classAny"] as Array).has(String(ch.get("classId", ""))):
			return false
	var tier := RulesClass.tier_of(ch)
	if pre.has("expert"):           # 專長等級門檻 (S06e 二/三/四級)
		for k in pre["expert"]:
			var elv := RulesExpert.eff_level(data.experts, String(ch.get("classId", "")), String(k), int(ch.get("expert", {}).get(k, 0)), tier)
			if elv < int(pre["expert"][k]):
				return false
	if pre.has("expertAny"):        # 任一專長達標 (S06e 二級)
		var any_ok := false
		for k in pre["expertAny"]:
			var elv2 := RulesExpert.eff_level(data.experts, String(ch.get("classId", "")), String(k), int(ch.get("expert", {}).get(k, 0)), tier)
			if elv2 >= int(pre["expertAny"][k]):
				any_ok = true
				break
		if not any_ok:
			return false
	for qid in pre.get("questDone", []):
		if not bool(ch.get("questDone", {}).get(String(qid), false)):
			return false
	if pre.has("militia"):       # 團體任務 (spec 06 §6): 要「所屬義勇軍」先接得 (S06c)
		if not bool(ch.get("militia", {}).get("founded", false)):
			return false
	return true


# ================= 進度讀取 =================
static func stage_of(ch: Dictionary, q: Dictionary) -> Dictionary:
	var st: Dictionary = ch.get("quests", {}).get(String(q["id"]), {})
	if st.is_empty() or bool(st.get("done", false)):
		return {}
	return _stage(q, int(st.get("stage", 0)))


# 記事 UI 提示: 進行中 = stage hint；未開始 = pre 提示
static func hint(q: Dictionary, ch: Dictionary) -> String:
	var st: Dictionary = ch.get("quests", {}).get(String(q["id"]), {})
	if st.is_empty():
		return String(q.get("preHint", ""))
	if bool(st.get("done", false)):
		return "已完成"
	var stage := _stage(q, int(st.get("stage", 0)))
	if stage.is_empty():
		return ""
	var h := String(stage.get("hint", ""))
	if h.contains("%v"):
		var done := 0
		var need := 0
		if String(stage.get("type", "")) == "talk_n":
			done = (st.get("flags", {}).get("visited", []) as Array).size()
			need = int(stage.get("n", 1))
		elif String(stage.get("type", "")) == "repeat":
			done = int(st.get("flags", {}).get("count", 0))
			need = int(stage.get("n", 1))
		elif String(stage.get("type", "")) == "collect":   # UAT: collect stage 顯示背包已收集/需要
			var item: Dictionary = stage.get("item", {})
			need = int(item.get("n", 0))
			done = RulesShop.count_item(ch.get("bag", {}), int(item.get("id", -1))) if need > 0 else 0
		h = h.replace("%v", str(done)).replace("%n", str(need))
	return h


# ================= stage 推進 =================
# 對話指定 npc：回傳 {"changed": bool, "done": bool, "msg": String, "reward": Dictionary, "dialog": Array}
static func on_npc_talk(data: GameData, ch: Dictionary, q: Dictionary, npc_id: String, day: int) -> Dictionary:
	var out := {"changed": false, "done": false, "msg": "", "reward": {}, "dialog": []}
	var st: Dictionary = ch.get("quests", {}).get(String(q["id"]), {})
	if st.is_empty() or bool(st.get("done", false)):
		if bool(ch.get("questDone", {}).get(String(q["id"]), false)):
			return out                                   # 已完成，唔會重接
		if String(q.get("giver", "")) != npc_id:
			return out                                   # 只有 quest giver 先可以觸發
		if not pre_ok(data, q, ch):
			return out
		if not ch.has("quests"):
			ch["quests"] = {}
		ch["quests"][String(q["id"])] = {"stage": 0, "startDay": day, "flags": {}}
		st = ch["quests"][String(q["id"])]
		out["changed"] = true
		out["started"] = true
	var stage := _stage(q, int(st.get("stage", 0)))
	if stage.is_empty():
		return out
	var t := String(stage.get("type", ""))
	var hit := String(stage.get("npc", "")) == npc_id or (stage.get("npcs", []) as Array).has(npc_id)
	if not hit:
		return out
	match t:
		"talk", "fight":
			if t == "fight":
				return out                            # PK 由 cmd_quest_battle 處理 (Step 10+)，talk 唔推進
			var take: Array = stage.get("takeItems", [])
			for ti in take:                           # 交信物 (Step 16): 要帶齊先推進，推進先扣
				if not RulesShop.has_item(ch["bag"], int(ti[0]), int(ti[1])):
					out["msg"] = "要帶齊%s" % data.names.get(int(ti[0]), str(ti[0]))
					out["blocked"] = true                 # 冇推進但要話畀玩家知 (唔好變閒談)
					return out
			for ti in take:
				RulesShop.remove_item(ch["bag"], int(ti[0]), int(ti[1]))
			out["dialog"] = stage.get("dialog", [])
			return _advance(data, ch, q, st, stage, out)
		"talk_n":
			var flags: Dictionary = st.get("flags", {})
			var vis: Array = flags.get("visited", [])
			if not vis.has(npc_id):
				vis.append(npc_id)
			flags["visited"] = vis
			st["flags"] = flags
			out["changed"] = true
			if vis.size() >= int(stage.get("n", 1)):
				return _advance(data, ch, q, st, stage, out)
			out["msg"] = hint(q, ch)
			return out
		"repeat":
			var flags: Dictionary = st.get("flags", {})
			if bool(stage.get("perDay", false)) and int(flags.get("lastDay", -1)) == day:
				out["msg"] = String(stage.get("dayMsg", "今晚已經跟蹤過喇，聽晚再嚟"))
				out["blocked"] = true
				return out
			flags["count"] = int(flags.get("count", 0)) + 1
			flags["lastDay"] = day
			st["flags"] = flags
			out["changed"] = true
			var dls: Array = stage.get("dialogs", [])     # 第 n 次嘅對白 (B3 三顧茅廬)
			if int(flags["count"]) <= dls.size():
				out["dialog"] = [dls[int(flags["count"]) - 1]]
			if int(flags["count"]) >= int(stage.get("n", 1)):
				return _advance(data, ch, q, st, stage, out)
			out["msg"] = hint(q, ch)
			return out
		"collect":
			out["msg"] = "要交道具: %s" % str(stage.get("item", {}).get("id", ""))
			return out
		"ask":
			out["msg"] = "佢似係等你答問題"
			return out
	return out


# 設施使用 (newbie_temple/school 由 cmd_facility 推進；未開始 + pre ok 都會自動觸發)
static func on_facility(data: GameData, ch: Dictionary, q: Dictionary, key: String, day: int = 0) -> Dictionary:
	var out := {"changed": false, "done": false, "msg": "", "reward": {}, "dialog": []}
	var st: Dictionary = ch.get("quests", {}).get(String(q["id"]), {})
	if st.is_empty() or bool(st.get("done", false)):
		if bool(ch.get("questDone", {}).get(String(q["id"]), false)):
			return out
		if not pre_ok(data, q, ch):
			return out
		if not ch.has("quests"):
			ch["quests"] = {}
		ch["quests"][String(q["id"])] = {"stage": 0, "startDay": day, "flags": {}}
		st = ch["quests"][String(q["id"])]
		out["changed"] = true
	var stage := _stage(q, int(st.get("stage", 0)))
	if stage.is_empty() or String(stage.get("type", "")) != "facility" or String(stage.get("fac", "")) != key:
		return out
	return _advance(data, ch, q, st, stage, out)


# PK 戰勝 boss (cmd_quest_battle 召喚嘅 quest boss 死時由 sim 調用, Step 10, spec 06 §5):
static func on_fight_win(data: GameData, ch: Dictionary, q: Dictionary) -> Dictionary:
	var out := {"changed": false, "done": false, "msg": "", "reward": {}, "dialog": []}
	var st: Dictionary = ch.get("quests", {}).get(String(q["id"]), {})
	if st.is_empty() or bool(st.get("done", false)):
		return out
	var stage := _stage(q, int(st.get("stage", 0)))
	if stage.is_empty() or String(stage.get("type", "")) != "fight":
		return out
	for ti in stage.get("takeItems", []):      # 出兵令之類: 打贏先收 (召喚時已 check 過有)
		RulesShop.remove_item(ch["bag"], int(ti[0]), int(ti[1]))
	return _advance(data, ch, q, st, stage, out)


# 繳交收集道具 (cmd_quest_turnin)：扣背包道具
static func on_turnin(data: GameData, ch: Dictionary, q: Dictionary) -> Dictionary:
	var out := {"changed": false, "done": false, "msg": "", "reward": {}, "dialog": []}
	var st: Dictionary = ch.get("quests", {}).get(String(q["id"]), {})
	if st.is_empty() or bool(st.get("done", false)):
		return out
	var stage := _stage(q, int(st.get("stage", 0)))
	if stage.is_empty() or String(stage.get("type", "")) != "collect":
		return out
	var need: Dictionary = stage.get("item", {})
	if not RulesShop.remove_item(ch["bag"], int(need["id"]), int(need["n"])):
		out["msg"] = "道具唔夠: %s x%d" % [data.names.get(int(need["id"]), str(need["id"])), int(need["n"])]
		return out
	return _advance(data, ch, q, st, stage, out)


# 答題 (cmd_quest_answer)：答案啱先推進
static func on_answer(data: GameData, ch: Dictionary, q: Dictionary, answer_idx: int) -> Dictionary:
	var out := {"changed": false, "done": false, "msg": "", "reward": {}, "dialog": []}
	var st: Dictionary = ch.get("quests", {}).get(String(q["id"]), {})
	if st.is_empty() or bool(st.get("done", false)):
		return out
	var stage := _stage(q, int(st.get("stage", 0)))
	if stage.is_empty() or String(stage.get("type", "")) != "ask":
		return out
	if int(stage.get("answer", -1)) != answer_idx:
		out["msg"] = "答錯喇，再唸一唸…"
		var wr: Array = stage.get("wrong", [])
		if not wr.is_empty():        # UAT: 答錯 → NPC 回應對話（唔推進），唔淨係信息欄一句
			out["dialog"] = wr
		return out
	var rp: Array = stage.get("response", [])   # UAT: 答啱 → NPC 回應對話先至繼續
	if not rp.is_empty():
		out["dialog"] = rp
	return _advance(data, ch, q, st, stage, out)


# 跨 stage / 完成：getItem 派道具；done → 獎勵 + 記入 questDone
static func _advance(data: GameData, ch: Dictionary, q: Dictionary, st: Dictionary, stage: Dictionary, out: Dictionary) -> Dictionary:
	out["changed"] = true
	var gi: Dictionary = stage.get("getItem", {})
	if not gi.is_empty():
		RulesShop.add_item(ch["bag"], int(gi["id"]), int(gi["n"]))
		out["getItem"] = gi
	var gis: Array = stage.get("getItems", [])
	if not gis.is_empty():          # 一次派多件 (S06e 地理圖×4)
		for g in gis:
			RulesShop.add_item(ch["bag"], int(g[0]), int(g[1]))
		out["getItems"] = gis
	if bool(stage.get("done", false)):
		ch["quests"].erase(String(q["id"]))
		if not ch.has("questDone"):
			ch["questDone"] = {}
		ch["questDone"][String(q["id"])] = true
		out["done"] = true
		out["reward"] = apply_reward(data, ch, q.get("reward", {}))
		out["msg"] = "任務完成！"
	else:
		st["stage"] = int(st.get("stage", 0)) + 1
		out["stage"] = int(st["stage"])
		out["msg"] = hint(q, ch)
	return out


# ================= 獎勵結算 =================
# reward keys: exp/gold/fame/lilian/items [[id,n]...]/attr {k:+1}/polExp/ultimate/spell/expert
# 回傳 payload（事件/訊息用）；未支援嘅 key 忽略
static func apply_reward(data: GameData, ch: Dictionary, reward: Dictionary) -> Dictionary:
	var payload := {}
	if reward.is_empty():
		return payload
	if reward.has("exp"):
		var exp := int(reward["exp"])
		payload["exp"] = exp
		ch["exp"] = int(ch.get("exp", 0)) + exp
	if reward.has("gold"):
		var gold := int(reward["gold"])
		payload["gold"] = gold
		ch["gold"] = int(ch.get("gold", 0)) + gold
	if reward.has("fame"):
		var fame := int(reward["fame"])
		payload["fame"] = fame
		ch["fame"] = int(ch.get("fame", 0)) + fame
	if reward.has("lilian"):
		var lil := int(reward["lilian"])
		payload["lilian"] = lil
		ch["lilian"] = int(ch.get("lilian", 0)) + lil
	if reward.has("items"):
		var items: Array = []
		for it in reward["items"]:
			var id := int(it[0])
			RulesShop.add_item(ch["bag"], id, int(it[1]))
			items.append({"id": id, "n": int(it[1])})
		payload["items"] = items
	if reward.has("attr"):
		var attrs := {}
		for k in reward["attr"]:
			ch["attrs"][k] = int(ch["attrs"].get(k, 0)) + int(reward["attr"][k])
			attrs[k] = int(reward["attr"][k])
		payload["attr"] = attrs
	if reward.has("polExp"):            # 政治經驗 (Step 16 歷史任務): 同官令一樣換算政治點
		var pe := int(reward["polExp"])
		var r := RulesTiandi.cha_gain(int(ch["attrs"]["pol"]), int(ch.get("polExp", 0)), pe,
			{"chaExpPerPoint": data.office["polExpPerPoint"], "chaCap": data.office["polCap"]})
		ch["attrs"]["pol"] = int(r["cha"])
		ch["polExp"] = int(r["exp"])
		payload["polExp"] = pe
	if reward.has("ultimate"):          # 絕招 (Step 10, spec 02 §5): 學識 -> ch.ultimates 列表
		var uid := String(reward["ultimate"])
		var ults: Array = ch.get("ultimates", [])
		if not ults.has(uid):
			ults.append(uid)
		ch["ultimates"] = ults
		payload["ultimate"] = uid
	if reward.has("skill"):             # 職業特技 (S02c, spec 02 §6): 學識 -> ch.classSkill (單一格)
		ch["classSkill"] = String(reward["skill"])
		payload["skill"] = String(reward["skill"])
	if reward.has("spell"):             # 學術書 (spec 02 §6): 識得某術法
		ch["spell"] = String(reward["spell"])
		payload["spell"] = String(reward["spell"])
	if reward.has("expert"):            # 專長認證 (S06e, spec 06 §8): {skill, level} 直接升到嗰級
		var ex: Dictionary = reward["expert"]
		var before := int((ch.get("expert", {}) as Dictionary).get(String(ex.get("skill", "")), 0))
		var after := RulesExpert.certify(ch, data.experts, String(ex.get("skill", "")), int(ex.get("level", 0)), RulesClass.tier_of(ch))
		payload["expert"] = {"skill": String(ex.get("skill", "")), "level": int(ex.get("level", 0)), "exp": after}
		if after == before:
			payload["expert"]["noop"] = true
	return payload


# 任務道具 (cat 44 任務雜物 / cat 52 任務物品) 唔賣得 (spec 06 §1.2)
# 武將收集冊 (Step 16) 一樣唔賣得
static func is_quest_item(data: GameData, item_id: int) -> bool:
	if item_id == int(data.comm.get("book", {}).get("item", 0)):
		return true
	return QUEST_ITEM_CATS.has(int(data.cats.get(item_id, 0)))


static func _stage(q: Dictionary, idx: int) -> Dictionary:
	var stages: Array = q.get("stages", [])
	if idx < 0 or idx >= stages.size():
		return {}
	return stages[idx]