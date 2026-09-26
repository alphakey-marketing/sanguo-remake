class_name RulesLlm
extends RefCounted
# LLM 層規則 (S09d, spec 09 §5): 動作白名單 / OpenRouter 請求建立 / 回應解析 / 規則層效果 /
# 每日反思摘要（純函數）。LLM 只可以揀白名單動作 + 生成句；解析會扔掉所有數值欄，
# 任何數值改動都只可以由 `effect_of()` 決定（測試斷言 LLM 唔改數值）。
# 冇 key / 失敗 / 預算完 → `NpcBrainLlm.decide()` 模板後備（離線照玩）。


static func cfg(data) -> Dictionary:
	var c = data.llm if data != null else {}
	return c if c is Dictionary else {}


static func actions(c: Dictionary) -> Array:
	var a = c.get("actions", ["greet", "warn", "ignore"])
	return a if a is Array and not (a as Array).is_empty() else ["greet", "warn", "ignore"]


static func has_action(c: Dictionary, action: String) -> bool:
	return actions(c).has(action)


# ================= Tier / 冷卻 / 預算 =================

# tier 政策: 1 = 一定 LLM、2 = 偶發（機率)、3 = 純模板。roll = 外面 SimRng 抽 0..999 傳入。
static func tier_mode(c: Dictionary, tier: int) -> String:
	var t = (c.get("tiers", {}) as Dictionary).get(str(tier), {})
	return String((t as Dictionary).get("mode", "template")) if t is Dictionary else "template"


static func tier_chance(c: Dictionary, tier: int) -> float:
	var t = (c.get("tiers", {}) as Dictionary).get(str(tier), {})
	return float((t as Dictionary).get("chance", 0.0)) if t is Dictionary else 0.0


# uses = 呢個 tier 呢次要唔要用 LLM（roll = 0..999，決定性）
static func tier_uses_llm(c: Dictionary, tier: int, roll: int) -> bool:
	match tier_mode(c, tier):
		"llm":
			return true
		"mixed":
			return roll < int(round(tier_chance(c, tier) * 1000.0))
		_:
			return false


static func cooldown_ticks(c: Dictionary) -> int:
	return maxi(0, int(c.get("cooldownTicks", 0)))


static func cooldown_ok(c: Dictionary, last_tick: int, tick: int) -> bool:
	return tick - last_tick >= cooldown_ticks(c)


# used = {"day": int, "calls": int, "reflect": int}；跨日自動重設
static func roll_day(used: Dictionary, day: int) -> Dictionary:
	if int(used.get("day", -1)) != day:
		return {"day": day, "calls": 0, "reflect": 0}
	return {"day": day, "calls": int(used.get("calls", 0)), "reflect": int(used.get("reflect", 0))}


static func per_day(c: Dictionary) -> int:
	return maxi(0, int((c.get("budget", {}) as Dictionary).get("perDay", 0)))


static func reflect_per_day(c: Dictionary) -> int:
	return maxi(0, int((c.get("budget", {}) as Dictionary).get("reflectPerDay", 0)))


static func budget_ok(c: Dictionary, used: Dictionary, kind: String) -> bool:
	if kind == "reflect":
		return int(used.get("reflect", 0)) < reflect_per_day(c)
	return int(used.get("calls", 0)) < per_day(c)


static func reflect_interval(c: Dictionary) -> int:
	return maxi(1, int((c.get("reflect", {}) as Dictionary).get("intervalDays", 1)))


# 呢日要唔要為呢張記憶表出摘要
static func reflect_due(c: Dictionary, mem: Dictionary, day: int) -> bool:
	return day - int(mem.get("summaryDay", -1)) >= reflect_interval(c)


# ================= 請求建立 (OpenAI 相容) =================

static func _headers(c: Dictionary, key: String) -> Dictionary:
	var h := {"Content-Type": "application/json"}
	if key != "":
		h["Authorization"] = "Bearer " + key
	h["X-Title"] = "sanguo-remake"
	return h


static func auth_headers(c: Dictionary, key: String) -> Dictionary:
	return _headers(c, key)


# ctx = {actor_name, npc_name, tier, ideology, affinity, karma_tier, rumor_kind, quest_hint, known_rumors:[...]}
static func prompt_messages(c: Dictionary, ctx: Dictionary) -> Array:
	var style: Dictionary = c.get("ideologyStyle", {})
	var ideo := String(ctx.get("ideology", ""))
	var msgs: Array = [{"role": "system", "content": String((c.get("prompt", {}) as Dictionary).get("system", ""))}]
	var facts := "你係%s。對方係%s。你嘅理念係%s（%s）。對方對你嘅好感 %d（-100~100）。對方善惡等級 %d（0 大英雄..6 殺人魔）。" % [
		String(ctx.get("npc_name", "")), String(ctx.get("actor_name", "")), ideo,
		String(style.get(ideo, "")), int(ctx.get("affinity", 0)), int(ctx.get("karma_tier", 3))]
	var rk := String(ctx.get("rumor_kind", ""))
	if rk != "":
		facts += "你聽過關於對方嘅傳聞：%s。" % rk
	var qh := String(ctx.get("quest_hint", ""))
	if qh != "":
		facts += "對方好似想拜託你：%s。" % qh
	msgs.append({"role": "user", "content": facts})
	return msgs


static func request_body(c: Dictionary, model: String, messages: Array) -> Dictionary:
	return {
		"model": model if model != "" else String(c.get("model", "")),
		"messages": messages,
		"temperature": float(c.get("temperature", 0.7)),
		"max_tokens": int(c.get("maxTokens", 120)),
		"response_format": c.get("responseFormat", {})
	}


# 完整 OpenRouter 請求 = {url, headers, body}；key 只放 header，唔會入存檔/事件
static func build_request(c: Dictionary, model: String, ctx: Dictionary, key: String) -> Dictionary:
	return {"url": String(c.get("endpoint", "")), "headers": _headers(c, key),
		"body": request_body(c, model, prompt_messages(c, ctx))}


# 反思摘要請求（純文字輸出，唔用 schema）
static func build_reflect_request(c: Dictionary, model: String, ctx: Dictionary, key: String) -> Dictionary:
	var sys := String((c.get("prompt", {}) as Dictionary).get("reflectSystem", ""))
	var user := "NPC 記憶：%s。已知傳聞：%s。請用一句話摘要佢而家嘅處境同目標。" % [
		String(ctx.get("mem_digest", "")), String(ctx.get("rumor_digest", ""))]
	var body := request_body(c, model, [{"role": "system", "content": sys}, {"role": "user", "content": user}])
	body.erase("response_format")
	return {"url": String(c.get("endpoint", "")), "headers": _headers(c, key), "body": body}


# ================= 回應解析 =================

# 扔掉 code fence / 前後雜訊，抽出第一個 JSON object 字串
static func _extract_json(text: String) -> String:
	var s := text.strip_edges()
	var a := s.find("{")
	var b := s.rfind("}")
	if a >= 0 and b > a:
		return s.substr(a, b - a + 1)
	return ""


# 解析 LLM 回應 → {"action": 白名單內, "line": String}。任何數值欄/未知欄一律丟棄。
# 解析唔到 → {}（呼叫方 fallback 模板）。
static func parse_response(c: Dictionary, text: String) -> Dictionary:
	var js := _extract_json(text)
	if js == "":
		return {}
	var v: Variant = JSON.parse_string(js)
	if not (v is Dictionary):
		return {}
	var action := String((v as Dictionary).get("action", ""))
	var line := String((v as Dictionary).get("line", "")).strip_edges()
	if action == "":
		return {}
	if not has_action(c, action):
		action = "ignore"                       # 非法動作 → 安全 fallback
	if line == "":
		line = "……"
	return {"action": action, "line": line.substr(0, int(c.get("maxTokens", 120)) * 4)}


# 摘要解析: 只取純文字，剝 JSON/引號，限制長度
static func parse_summary(c: Dictionary, text: String) -> String:
	var s := text.strip_edges()
	if s == "":
		return ""
	if s.begins_with("{"):
		var v: Variant = JSON.parse_string(s)
		if v is Dictionary:
			s = String((v as Dictionary).get("summary", (v as Dictionary).get("line", "")))
	s = s.replace("\n", " ").strip_edges()
	var maxc := int((c.get("reflect", {}) as Dictionary).get("maxChars", 80))
	return s.substr(0, maxc)


# ================= 規則層效果（LLM 唯一可以間接引致嘅數值改動）=================
# 回傳 {"affinity": int, "accept": bool, "hint": bool, "refuse": bool, "rumor": bool, "warn": bool, "ignore": bool}
static func effect_of(action: String) -> Dictionary:
	var e := {"affinity": 0, "accept": false, "hint": false, "refuse": false, "rumor": false, "warn": false, "ignore": false}
	match action:
		"greet":
			e["affinity"] = 1                   # 打招呼好感 +1（同規矩層一致）
		"acceptQuest":
			e["accept"] = true
		"hint":
			e["hint"] = true
		"rumor":
			e["rumor"] = true
		"refuse":
			e["refuse"] = true
		"warn":
			e["warn"] = true
		_:
			e["ignore"] = true
	return e


static func affinity_delta(action: String) -> int:
	return int(effect_of(action).get("affinity", 0))


# ================= 每日反思摘要（純函數、離線後備）=================

# 記憶表 → 一句摘要。只用記憶表內容，唔用 rng、唔改任何數值。
static func template_summary(c: Dictionary, mem: Dictionary) -> String:
	var events: Array = mem.get("events", [])
	var kinds := {}
	for ev in events:
		var k := String((ev as Dictionary).get("kind", ""))
		kinds[k] = int(kinds.get(k, 0)) + 1
	var aff: Dictionary = mem.get("affinity", {})
	var lo := 0
	var hi := 0
	var first := true
	for k in aff:
		var v := int(aff[k])
		if first:
			lo = v
			hi = v
			first = false
		else:
			lo = mini(lo, v)
			hi = maxi(hi, v)
	var rs: Dictionary = mem.get("rumors", {})
	var rks := {}
	for k in rs:
		var rk := String((rs[k] as Dictionary).get("kind", ""))
		rks[rk] = int(rks.get(rk, 0)) + 1
	var s := "記得 %d 件事" % events.size()
	if not kinds.is_empty():
		s += "（%s）" % _pair_str(kinds)
	if not aff.is_empty():
		s += "，好感 %d~%d" % [lo, hi]
	if not rks.is_empty():
		s += "；聽過 %d 單傳聞（%s）" % [rs.size(), _pair_str(rks)]
	return s.substr(0, int((c.get("reflect", {}) as Dictionary).get("maxChars", 80)))


static func _pair_str(d: Dictionary) -> String:
	var keys: Array = d.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s×%d" % [String(k), int(d[k])])
	return "、".join(parts)


# 由記憶表推「目標」（純規則，唔用 LLM）
static func goal_of(mem: Dictionary) -> String:
	var aff: Dictionary = mem.get("affinity", {})
	var hi := -999
	var lo := 999
	for k in aff:
		var v := int(aff[k])
		hi = maxi(hi, v)
		lo = mini(lo, v)
	var rks := {}
	for k in (mem.get("rumors", {}) as Dictionary):
		var rk := String((mem["rumors"][k] as Dictionary).get("kind", ""))
		rks[rk] = true
	if rks.has("killer") or lo <= -30:
		return "提防你"
	if rks.has("bounty") or hi >= 20:
		return "敬重你"
	if hi >= 5:
		return "同你相熟"
	return "平淡相處"