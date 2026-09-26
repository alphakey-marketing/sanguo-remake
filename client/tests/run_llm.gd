extends SceneTree
# S09d LLM 層測試 (spec 09 §5): 動作白名單 / OpenRouter 請求 / 回應解析 / 規則層效果 /
# 每日反思摘要 / Tier 分配 / 冷卻 / 預算 / 後備。全部用 mock 文字，**唔碰網絡**。
# 核心斷言: LLM 唔准直接改數值（只可以揀動作，數值只由 RulesLlm.effect_of 決定）。
# 跑: Godot --headless --path client --script tests/run_llm.gd  (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_data(data)
	t_rules_parse(data)
	t_rules_effect()
	t_rules_tier(data)
	t_rules_budget(data)
	t_brain(data)
	t_summary(data)
	t_request(data)
	t_client(data)
	t_sim_config(data)
	t_sim_general_talk(data)
	t_sim_reply(data)
	t_sim_reflection(data)
	t_sim_budget(data)
	t_roundtrip(data)
	t_old_save(data)
	t_determinism(data)
	print("[TEST] llm scenarios: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


func _new(data: GameData, seed: int = 77) -> Array:
	var sim := Sim.new(data, seed)
	var pid := sim.spawn_player("t", "yishi")
	var ch := sim.player_ch()
	var msgs: Array = []
	var evs: Array = []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		evs.append(ev)
		if String(ev.get("k", "")) == "msg":
			msgs.append(String(ev["text"])))
	return [sim, pid, ch, msgs, evs]


func _last(msgs: Array) -> String:
	return String(msgs[-1]) if not msgs.is_empty() else ""


func _put(sim: Sim, id: int, x: int, y: int) -> void:
	var e := sim.ent(id)
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y
	e.erase("path")


func _gen(data: GameData, gname: String) -> Dictionary:
	for g in data.generals_t1:
		if String(g["name"]) == gname:
			return g
	return {}


func _at(sim: Sim, day: int, ke: int) -> void:
	var tpd := 1440 / int(sim.data.world["clock"]["gameMinPerTick"])
	sim.state["tick"] = day * tpd + int(ceil(ke * 15.0 / float(sim.data.world["clock"]["gameMinPerTick"]))) - 1
	sim.step()


func _last_req(evs: Array) -> Dictionary:
	for i in range(evs.size() - 1, -1, -1):
		if String(evs[i].get("k", "")) == "llm_request":
			return evs[i]
	return {}


func _has_say(evs: Array, action: String) -> bool:
	for ev in evs:
		if String(ev.get("k", "")) == "npc_say" and bool(ev.get("llm", false)) and String(ev.get("action", "")) == action:
			return true
	return false


# Tier2 居民偶發 LLM: 測試要必定命中 → 暫時改 cache 機率（單獨 process，無副作用）
func _force_tier2(data: GameData, chance: float) -> void:
	(data.llm["tiers"]["2"] as Dictionary)["chance"] = chance


# ================= 資料 =================

func t_data(data: GameData) -> void:
	var c := RulesLlm.cfg(data)
	check(not c.is_empty(), "資料: data/llm.json 載入")
	check(RulesLlm.actions(c).size() == 7, "資料: 7 個動作白名單")
	for a in ["greet", "warn", "ignore", "acceptQuest", "hint", "rumor", "refuse"]:
		check(RulesLlm.has_action(c, a), "資料: 白名單有 " + a)
	check(RulesLlm.tier_mode(c, 1) == "llm", "資料: Tier1 = llm")
	check(RulesLlm.tier_mode(c, 3) == "template", "資料: Tier3 = template")
	check(RulesLlm.per_day(c) > 0 and RulesLlm.reflect_per_day(c) > 0, "資料: 預算 > 0")
	check(String(c.get("endpoint", "")).contains("openrouter"), "資料: endpoint OpenRouter")
	check(String(c.get("prompt", {}).get("system", "")) != "", "資料: system prompt")


# ================= 純函數: 解析 =================

func t_rules_parse(data: GameData) -> void:
	var c := RulesLlm.cfg(data)
	var ok := RulesLlm.parse_response(c, '{"action":"hint","line":"東邊有寶"}')
	check(String(ok.get("action", "")) == "hint" and String(ok.get("line", "")) == "東邊有寶", "解析: 正常 JSON")
	# 數值欄一律丟棄 (LLM 唔准改數值)
	var evil := RulesLlm.parse_response(c, '{"action":"greet","line":"喂","affinity":9999,"karma":-100,"hp":0,"gold":999999}')
	check(evil.size() == 2 and not evil.has("affinity") and not evil.has("karma") and not evil.has("hp") and not evil.has("gold"),
		"解析: 扔掉所有數值欄 (只剩 action/line)")
	check(String(evil["action"]) == "greet", "解析: 動作保留")
	# code fence / 前後雜訊
	var fence := RulesLlm.parse_response(c, "```json\n{\"action\":\"rumor\",\"line\":\"聽講...\"}\n```")
	check(String(fence.get("action", "")) == "rumor", "解析: 剝 code fence")
	# 未知動作 → ignore
	var bad := RulesLlm.parse_response(c, '{"action":"delete_player","line":"x"}')
	check(String(bad.get("action", "")) == "ignore", "解析: 非白名單動作 → ignore")
	# 解析唔到 → {}
	check(RulesLlm.parse_response(c, "對唔住我唔識").is_empty(), "解析: 非 JSON → 空")
	check(RulesLlm.parse_response(c, '{"line":"冇動作"}').is_empty(), "解析: 冇 action → 空")
	# 空 line 補值
	var empty := RulesLlm.parse_response(c, '{"action":"warn"}')
	check(String(empty.get("line", "")) != "", "解析: 空 line 補預設")
	# 摘要解析
	check(RulesLlm.parse_summary(c, "  NPC 最近避開你\n") == "NPC 最近避開你", "解析: 摘要去空白/換行")
	check(RulesLlm.parse_summary(c, '{"summary":"怕你"}' ) == "怕你", "解析: 摘要可食 JSON")
	check(RulesLlm.parse_summary(c, "").is_empty(), "解析: 空摘要")


# ================= 純函數: 效果 =================

func t_rules_effect() -> void:
	check(RulesLlm.affinity_delta("greet") == 1, "效果: greet 好感 +1")
	for a in ["warn", "ignore", "acceptQuest", "hint", "rumor", "refuse"]:
		check(RulesLlm.affinity_delta(a) == 0, "效果: " + a + " 唔改好感")
	check(bool(RulesLlm.effect_of("acceptQuest")["accept"]), "效果: acceptQuest 標記 accept")
	check(bool(RulesLlm.effect_of("refuse")["refuse"]), "效果: refuse 標記 refuse")
	check(bool(RulesLlm.effect_of("rumor")["rumor"]), "效果: rumor 標記 rumor")
	check(bool(RulesLlm.effect_of("唔存在")["ignore"]), "效果: 未知 → ignore")


# ================= 純函數: Tier / 預算 / 冷卻 =================

func t_rules_tier(data: GameData) -> void:
	var c := RulesLlm.cfg(data)
	check(RulesLlm.tier_uses_llm(c, 1, 999), "Tier1: 永遠用 LLM")
	check(not RulesLlm.tier_uses_llm(c, 3, 0), "Tier3: 唔用 LLM")
	var ch: Dictionary = c["tiers"]["2"]
	var prev := float(ch.get("chance", 0.0))
	ch["chance"] = 0.5
	check(RulesLlm.tier_uses_llm(c, 2, 499) and not RulesLlm.tier_uses_llm(c, 2, 500), "Tier2: 機率門檻")
	ch["chance"] = prev


func t_rules_budget(data: GameData) -> void:
	var c := RulesLlm.cfg(data)
	var u := RulesLlm.roll_day({"day": -1, "calls": 5, "reflect": 2}, 7)
	check(int(u["day"]) == 7 and int(u["calls"]) == 0 and int(u["reflect"]) == 0, "預算: 跨日重設")
	var u2 := RulesLlm.roll_day({"day": 7, "calls": 3, "reflect": 1}, 7)
	check(int(u2["calls"]) == 3, "預算: 同日保留")
	check(RulesLlm.budget_ok(c, {"calls": RulesLlm.per_day(c)}, "talk") == false, "預算: 用完唔開")
	check(RulesLlm.budget_ok(c, {"reflect": RulesLlm.reflect_per_day(c)}, "reflect") == false, "預算: 反思用完唔開")
	check(RulesLlm.cooldown_ok(c, 0, RulesLlm.cooldown_ticks(c)), "冷卻: 夠鐘可再開")
	check(not RulesLlm.cooldown_ok(c, 0, RulesLlm.cooldown_ticks(c) - 1), "冷卻: 未夠鐘唔開")


# ================= brain =================

func t_brain(data: GameData) -> void:
	var c := RulesLlm.cfg(data)
	var d := NpcBrainLlm.decide({"actor_name": "阿明", "affinity": 0, "karma_tier": 3})
	check(NpcBrainLlm.ACTIONS.has(String(d["action"])), "brain: 模板動作喺白名單")
	var villain := NpcBrainLlm.decide({"actor_name": "阿明", "affinity": 0, "karma_tier": 6})
	check(String(villain["action"]) == "warn", "brain: 殺人魔 → warn")
	var hate := NpcBrainLlm.decide({"actor_name": "阿明", "affinity": -50, "karma_tier": 3})
	check(String(hate["action"]) == "refuse", "brain: 好感 -50 → refuse")
	var friend := NpcBrainLlm.decide({"actor_name": "阿明", "affinity": 50, "karma_tier": 3, "rumor_kind": "killer"})
	check(String(friend["action"]) == "rumor", "brain: 熟 + 有傳聞 → rumor")
	# decide_with: 有 LLM 文字用 LLM；亂碼 fallback
	var llm := NpcBrainLlm.decide_with(c, {"actor_name": "阿明", "affinity": 0, "karma_tier": 3}, 0, '{"action":"hint","line":"去東邊"}')
	check(String(llm["action"]) == "hint" and String(llm["line"]) == "去東邊", "brain: decide_with 用 LLM 結果")
	var fb := NpcBrainLlm.decide_with(c, {"actor_name": "阿明", "affinity": 0, "karma_tier": 3}, 0, "亂碼")
	check(NpcBrainLlm.ACTIONS.has(String(fb["action"])), "brain: decide_with 解析唔到 → 模板")
	var evil := NpcBrainLlm.decide_with(c, {"actor_name": "阿明", "affinity": 0, "karma_tier": 3}, 0, '{"action":"greet","affinity":500}')
	check(evil.size() == 2, "brain: decide_with 只回 action/line")


# ================= 摘要 =================

func t_summary(data: GameData) -> void:
	var c := RulesLlm.cfg(data)
	var mem := NpcMemory.init_memory()
	NpcMemory.witness(mem, 5, "greet", 10, 2)
	NpcMemory.witness(mem, 5, "murder", 20, -4)
	NpcMemory.add_rumor(mem, "5:killer", {"actor": 5, "kind": "killer", "weight": -4, "origin": "xuchang", "day": 3})
	var s1 := RulesLlm.template_summary(c, mem)
	var s2 := RulesLlm.template_summary(c, mem)
	check(s1 == s2 and s1 != "", "摘要: 決定性 + 非空")
	check(s1.contains("2") and s1.contains("greet"), "摘要: 有事件統計")
	check(RulesLlm.goal_of(mem) == "提防你", "目標: 有 killer 傳聞 → 提防")
	var good := NpcMemory.init_memory()
	NpcMemory.witness(good, 5, "greet", 1, 25)
	check(RulesLlm.goal_of(good) == "敬重你", "目標: 高好感 → 敬重")
	check(RulesLlm.goal_of(NpcMemory.init_memory()) == "平淡相處", "目標: 空白 → 平淡")
	check(RulesLlm.reflect_due(c, {"summaryDay": -1}, 0), "摘要: 從未做 → 到期")
	var m2 := NpcMemory.init_memory()
	NpcMemory.set_summary(m2, "x", "y", 5)
	check(not RulesLlm.reflect_due(c, m2, 5), "摘要: 同日唔重複")


# ================= 請求 =================

func t_request(data: GameData) -> void:
	var c := RulesLlm.cfg(data)
	var ctx := {"actor_name": "玩家", "npc_name": "典韋", "ideology": "義理", "affinity": 5, "karma_tier": 1}
	var msgs := RulesLlm.prompt_messages(c, ctx)
	check(msgs.size() == 2 and String(msgs[0]["role"]) == "system", "請求: system + user")
	var body := RulesLlm.request_body(c, "m1", msgs)
	check(String(body["model"]) == "m1" and body.has("response_format"), "請求: model + response_format")
	check((body["messages"] as Array).size() == 2, "請求: messages")
	var req := RulesLlm.build_request(c, "m1", ctx, "sk-SECRET")
	check(String(req["headers"].get("Authorization", "")) == "Bearer sk-SECRET", "請求: key 只落 header")
	var nokey := RulesLlm.build_request(c, "m1", ctx, "")
	check(not nokey["headers"].has("Authorization"), "請求: 冇 key 冇 Authorization")
	check(String(req["url"]).contains("openrouter"), "請求: url openrouter")
	var rreq := RulesLlm.build_reflect_request(c, "m1", {"mem_digest": "記得 1 件事", "rumor_digest": "killer"}, "")
	check(not rreq["body"].has("response_format"), "請求: 反思唔用 schema")
	check(String(rreq["body"]["messages"][0]["content"]) != "", "請求: 反思 system prompt")


# ================= LlmClient (mock transport) =================

func t_client(data: GameData) -> void:
	var p := "user://llm_test.cfg"
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var cl := LlmClient.new(p)
	cl.load_cfg()
	check(not cl.has_key() and not cl.enabled(), "client: 未填 key = 停用")
	cl.save_cfg("sk-test-123", "model-x", "http://localhost/x")
	var cl2 := LlmClient.new(p)
	cl2.load_cfg()
	check(String(cl2.cfg["key"]) == "sk-test-123" and cl2.model() == "model-x", "client: key/model roundtrip")
	# 冇 transport → fail
	var got := [""]
	cl2.send(data.llm, "model-x", {"npc_name": "x"}, func(t: String, e: String) -> void: got[0] = e)
	check(got[0] == "no_transport", "client: 冇 transport → fail")
	# mock transport
	var box := {}
	cl2.transport = func(req: Dictionary, on_done: Callable) -> void:
		box["req"] = req
		on_done.call('{"action":"refuse","line":"唔得閒"}', "")
	cl2.send(data.llm, "model-x", {"actor_name": "p", "npc_name": "n", "ideology": "霸權"}, func(_t: String, _e: String) -> void: pass)
	var captured: Dictionary = box.get("req", {})
	check(String(captured.get("url", "")).contains("openrouter"), "client: 送出去嘅 request url")
	check(String((captured.get("headers", {}) as Dictionary).get("Authorization", "")) == "Bearer sk-test-123", "client: header 帶 key")
	var parsed := RulesLlm.parse_response(data.llm, '{"action":"refuse","line":"唔得閒"}')
	check(String(parsed["action"]) == "refuse", "client: mock 回應解析")
	# 清 key → 唔再 enabled
	cl2.clear_key()
	var cl3 := LlmClient.new(p)
	cl3.load_cfg()
	check(not cl3.has_key(), "client: clear_key 清走")
	# 冇 key 真 send → no_key
	var got2 := [""]
	cl3.transport = func(_req: Dictionary, on_done: Callable) -> void: on_done.call("", "")
	cl3.send(data.llm, "m", {}, func(_t: String, e: String) -> void: got2[0] = e)
	check(got2[0] == "no_key", "client: 冇 key → no_key")


# ================= sim: 設定 =================

func t_sim_config(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	check(not sim.llm_enabled(), "sim: 預設停用")
	var v := sim.llm_view()
	check(not bool(v["enabled"]) and v["actions"].size() == 7, "sim: llm_view 讀-model")
	sim.cmd_llm_config(true, "my-model")
	check(sim.llm_enabled() and sim.llm_model() == "my-model", "sim: cmd_llm_config 生效")
	sim.cmd_llm_config(false, "")
	check(not sim.llm_enabled() and sim.llm_model() == String(data.llm["model"]), "sim: 停用後用預設模型")


# ================= sim: Tier1 武將對話 =================

func t_sim_general_talk(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var evs: Array = r[4]
	var gd := _gen(data, "典韋")
	_put(sim, pid, int(gd["x"]) + 1, int(gd["y"]))
	# 未啟用 → 模板，冇 llm_request
	sim.cmd_general_talk(pid, int(gd["id"]))
	check(_last_req(evs).is_empty(), "Tier1: 未啟用 → 唔發 llm_request")
	# 啟用 → 發 llm_request
	sim.cmd_llm_config(true, "m")
	sim.cmd_general_talk(pid, int(gd["id"]))
	var req := _last_req(evs)
	check(not req.is_empty() and String(req["kind"]) == "talk" and int(req["tier"]) == 1, "Tier1: 發 llm_request (talk)")
	check((req["body"] as Dictionary).has("messages") and String(req["url"]).contains("openrouter"), "Tier1: request 內容")
	check(not (req["headers"] as Dictionary).has("Authorization"), "Tier1: sim 事件唔帶 key")
	check(int(req["npcId"]) == 0 and int(req["gid"]) == int(gd["id"]), "Tier1: 請求指紋")
	# 冷卻: 即刻再傾唔再發 llm_request（退回模板句 + _msg）
	var nreq0 := 0
	for ev in evs:
		if String(ev.get("k", "")) == "llm_request":
			nreq0 += 1
	sim.cmd_general_talk(pid, int(gd["id"]))
	var nreq1 := 0
	for ev in evs:
		if String(ev.get("k", "")) == "llm_request":
			nreq1 += 1
	check(nreq1 == nreq0, "Tier1: 冷卻中唔再發 llm_request")


# ================= sim: 回填 / 數值唔准改 =================

func t_sim_reply(data: GameData) -> void:
	_force_tier2(data, 1.0)
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var evs: Array = r[4]
	sim.add_bots(1)
	var bot_id := int(sim.state["bots"][0])
	var bot := sim.ent(bot_id)
	_put(sim, pid, int(bot["x"]) + 1, int(bot["y"]))
	sim.cmd_llm_config(true, "m")
	var aff0 := NpcMemory.affinity(bot["mem"], pid)
	var karma0 := int(ch["karma"])
	var gold0 := int(ch["gold"])
	var hp0 := int(ch["hp"])
	var ev0 := (bot["mem"]["events"] as Array).size()
	var queued := sim._llm_talk(bot, String(bot["name"]), String(bot["ch"].get("ideology", "")), 0, int(bot["x"]), int(bot["y"]), pid)
	check(queued, "回填: 居民 Tier2 排到隊")
	var req := _last_req(evs)
	var rid := int(req["reqId"])
	# 惡意回應: 大量數值欄
	var ok := sim.cmd_llm_reply(rid, '{"action":"greet","line":"喂","affinity":9999,"karma":-100,"hp":0,"gold":999999}')
	check(ok, "回填: cmd_llm_reply 成功")
	check(_has_say(evs, "greet"), "回填: 出 llm npc_say")
	check(NpcMemory.affinity(bot["mem"], pid) == aff0 + 1, "回填: 好感只按規則 +1")
	check(int(ch["karma"]) == karma0 and int(ch["gold"]) == gold0 and int(ch["hp"]) == hp0, "回填: LLM 改唔到善惡/錢/血")
	check((bot["mem"]["events"] as Array).size() == ev0 + 1, "回填: 只加一件規則事件")
	# 同一 req 重複回填 → 唔再有效
	check(not sim.cmd_llm_reply(rid, '{"action":"greet","line":"x"}'), "回填: 重複 req 唔再算")
	# 解析唔到 → 模板後備仍然出句
	_force_tier2(data, 1.0)
	sim.state["tick"] = int(sim.state["tick"]) + RulesLlm.cooldown_ticks(data.llm)   # 過冷卻
	var q2 := sim._llm_talk(bot, String(bot["name"]), "", 0, int(bot["x"]), int(bot["y"]), pid)
	check(q2, "回填: 第二次排隊")
	var rid2 := int(_last_req(evs)["reqId"])
	check(sim.cmd_llm_reply(rid2, "完全唔係 JSON"), "回填: 亂碼 → fallback 都成功")
	# 唔存在嘅 req
	check(not sim.cmd_llm_reply(99999, "{}"), "回填: 未知 req → false")


# ================= sim: 每日反思 =================

func t_sim_reflection(data: GameData) -> void:
	_force_tier2(data, 0.0)
	var r := _new(data, 88)
	var sim: Sim = r[0]
	sim.add_bots(2)
	# 未啟用: 子時反思只出規則模板摘要（決定性、離線照玩）
	_at(sim, 1, 0)
	var with_summary := 0
	for id in sim.state["bots"]:
		var mem: Dictionary = sim.ent(int(id)).get("mem", {})
		if NpcMemory.summary(mem) != "" and NpcMemory.goal(mem) != "":
			with_summary += 1
	check(with_summary == sim.state["bots"].size(), "反思: 停用時都出模板摘要")
	var s1 := NpcMemory.summary(sim.ent(int(sim.state["bots"][0]))["mem"])
	check(not s1.is_empty(), "反思: 摘要非空")
	# 同日唔重複
	_at(sim, 1, 4)
	check(NpcMemory.summary(sim.ent(int(sim.state["bots"][0]))["mem"]) == s1, "反思: 同日唔變")
	# 啟用 + 強制 Tier2 → 出 llm_request (kind reflect)
	_force_tier2(data, 1.0)
	sim.cmd_llm_config(true, "m")
	_at(sim, 2, 0)
	var rreq := {}
	for ev in r[4]:
		if String(ev.get("k", "")) == "llm_request" and String(ev.get("kind", "")) == "reflect":
			rreq = ev
	check(not rreq.is_empty(), "反思: 啟用後出 reflect 請求")
	if not rreq.is_empty():
		var nid := int(rreq["npcId"])
		var before := NpcMemory.summary(sim.ent(nid)["mem"])
		check(sim.cmd_llm_summary(int(rreq["reqId"]), "佢而家好提防你"), "反思: cmd_llm_summary 成功")
		var after := NpcMemory.summary(sim.ent(nid)["mem"])
		check(after == "佢而家好提防你" and after != before, "反思: 摘要被 LLM 覆蓋")
		check(not sim.cmd_llm_summary(int(rreq["reqId"]), "x"), "反思: 重複回填無效")


# ================= sim: 預算 =================

func t_sim_budget(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var evs: Array = r[4]
	var gd := _gen(data, "典韋")
	_put(sim, pid, int(gd["x"]) + 1, int(gd["y"]))
	sim.cmd_llm_config(true, "m")
	var c := data.llm
	var pd := RulesLlm.per_day(c)
	sim.state["llm"]["used"] = {"day": int(sim._clock()["day"]), "calls": pd, "reflect": 0}
	var n0 := 0
	for ev in evs:
		if String(ev.get("k", "")) == "llm_request":
			n0 += 1
	sim.cmd_general_talk(pid, int(gd["id"]))
	var n1 := 0
	for ev in evs:
		if String(ev.get("k", "")) == "llm_request":
			n1 += 1
	check(n1 == n0, "預算: 用完唔發 llm_request")
	check(String(sim.llm_view()["lastError"]) == "budget", "預算: lastError = budget")


# ================= 存檔 =================

func t_roundtrip(data: GameData) -> void:
	_force_tier2(data, 0.0)
	var r := _new(data, 55)
	var sim: Sim = r[0]
	sim.add_bots(1)
	sim.cmd_llm_config(true, "save-model")
	_at(sim, 1, 0)
	var s := sim.save_string()
	check(not s.contains("sk-"), "存檔: 冇 key 字串")
	check(s.contains("save-model"), "存檔: 有 model (非機密)")
	var l := Sim.load_string(data, s)
	check(l != null and l.llm_enabled() and l.llm_model() == "save-model", "存檔: enabled/model 保留")
	check(l.save_string() == s, "存檔: save→load→save 一致")
	var mem: Dictionary = l.ent(int(l.state["bots"][0]))["mem"]
	check(NpcMemory.summary(mem) != "" and int(mem.get("summaryDay", -1)) == 1, "存檔: 反思摘要保留")


func t_old_save(data: GameData) -> void:
	var r := _new(data, 56)
	var sim: Sim = r[0]
	var d: Dictionary = JSON.parse_string(sim.save_string())
	(d["state"] as Dictionary).erase("llm")
	var l := Sim.load_string(data, JSON.stringify(d))
	check(l != null and not l.llm_enabled(), "舊存檔: 冇 llm 欄 → 預設停用")
	var v := l.llm_view()
	check(String(v["model"]) == String(data.llm["model"]), "舊存檔: 補返預設模型")


func t_determinism(data: GameData) -> void:
	var a := _new(data, 91)
	var b := _new(data, 91)
	(a[0] as Sim).add_bots(2)
	(b[0] as Sim).add_bots(2)
	_at(a[0], 2, 20)
	_at(b[0], 2, 20)
	check((a[0] as Sim).save_string() == (b[0] as Sim).save_string(), "決定性: 同種子同動作一致 (停用 LLM)")
	var c: Dictionary = data.llm
	check(RulesLlm.template_summary(c, NpcMemory.init_memory()) == RulesLlm.template_summary(c, NpcMemory.init_memory()),
		"決定性: 摘要純函數")