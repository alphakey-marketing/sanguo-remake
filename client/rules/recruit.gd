class_name RulesRecruit
extends RefCounted
# 登用武將 (Step 13.5, spec 09 §3)。純函數；設定喺 data/generals.json cfg
# 【原】理念相合 5×3 表 + 出仕人人可登用；唔可以登用高自己 10 級以上；調查每日 1 次、成功嗰個月封鎖；
#       武將 = PK 擂台、文官 = 三國問答；登用 30 日，到期子時離開
# 【自訂】擂台/同伴/忠誠數值、候選排序、問答 8/10 過關

const IDEOLOGIES := ["義理", "霸權", "權謀", "隱遁", "治國"]
const FREE_IDEO := "出仕"
# 【原】sy1_1_2 / spec 09 §3.1: 玩家理念 → 可登用嘅武將理念
const IDEO_OK := {
	"義理": ["義理", "霸權", "治國"],
	"霸權": ["霸權", "義理", "權謀"],
	"權謀": ["權謀", "霸權", "隱遁"],
	"隱遁": ["隱遁", "權謀", "治國"],
	"治國": ["治國", "隱遁", "義理"],
}
const ARENA_DEF_BASE := 900000          # 擂台臨時怪 def id = BASE + 武將 id (唔入 monsters.json)
# 戰鬥指令 4 種【原】: 主動/協助/停止/遠距跟隨。招式用唔用 (U16 拆做獨立開關 skillMode) 由 SKILL_MODES 控制，兩者正交組合。
const ORDERS := ["active", "assist", "stop", "follow"]
const ORDER_NAMES := {"active": "主動攻擊", "assist": "協助攻擊", "stop": "停止攻擊", "follow": "遠距跟隨"}
const SKILL_MODES := ["off", "on"]
const SKILL_MODE_NAMES := {"off": "唔用招式", "on": "用絕招/術法"}


# 理念相合: 出仕人人得；玩家未定理念 = 只可以登用出仕
static func ideology_ok(player_ideo: String, gen_ideo: String) -> bool:
	if gen_ideo == FREE_IDEO:
		return true
	return (IDEO_OK.get(player_ideo, []) as Array).has(gen_ideo)


# 等級: 武將戰等唔可以高過玩家 gap 級以上 (gap = 10 → 玩家 5 級最多登 15 級)
static func level_ok(gen_lv: int, player_lv: int, gap: int) -> bool:
	return gen_lv <= player_lv + gap


# 頭銜【原】: 50 級以上人才，玩家頭銜唔可以低過人才 5 階以上 (Step 14；人才頭銜 = RulesTitle.general_rank)
static func title_ok(g: Dictionary, ch: Dictionary, cfg: Dictionary) -> bool:
	return RulesTitle.recruit_ok(int(g["lv"]), int(ch.get("titleRank", 0)), cfg)


# ---- F5 文官登用: 魅力/政治/等級/頭銜/親密度 加權 ----
# 【自訂】分數 = 魅力 + 政治 + 等級 + 頭銜階 + 親密度；門檻 = 人才戰等 (+ 50 級以上人才嘅頭銜階)。
# 超過/唔夠門檻每 CIVIL_STEP 分，問答過關題數 -1 / +1 (封頂 CIVIL_MIN_PASS ~ quizN)。魅力另有最低要求 = 戰等 / CIVIL_CHA_DIV。
const CIVIL_STEP := 10
const CIVIL_MIN_PASS := 5
const CIVIL_CHA_DIV := 8
const AFF_CAP := 20


static func civil_score(ch: Dictionary, aff: int) -> int:
	var a: Dictionary = ch.get("attrs", {})
	return int(a.get("cha", 0)) + int(a.get("pol", 0)) + int(ch.get("level", 1)) + int(ch.get("titleRank", 0)) + clampi(aff, 0, AFF_CAP)


static func civil_need(g: Dictionary, cfg: Dictionary) -> int:
	return int(g["lv"]) + RulesTitle.general_rank(int(g["lv"]), cfg)


static func civil_min_cha(g: Dictionary) -> int:
	return int(g["lv"]) / CIVIL_CHA_DIV


# 問答要答啱幾多題先過 (base = cfg.quizPass)
static func civil_pass_need(ch: Dictionary, g: Dictionary, aff: int, cfg: Dictionary) -> int:
	var diff := civil_score(ch, aff) - civil_need(g, cfg)
	var step := diff / CIVIL_STEP if diff >= 0 else -((-diff + CIVIL_STEP - 1) / CIVIL_STEP)
	return clampi(int(cfg["quizPass"]) - step, CIVIL_MIN_PASS, int(cfg["quizN"]))


# 可唔可以登用呢個人 → "" = 得；否則 = 原因
static func check(g: Dictionary, ch: Dictionary, cfg: Dictionary) -> String:
	if not ideology_ok(String(ch.get("ideology", "")), String(g["ideo"])):
		return "理念唔合"
	if String(g.get("type", "")) == "wen" and int(ch.get("attrs", {}).get("cha", 99)) < civil_min_cha(g):
		return "魅力唔夠（要 %d）" % civil_min_cha(g)
	if not level_ok(int(g["lv"]), int(ch["level"]), int(cfg["levelGap"])):
		return "等級差太遠"
	if not title_ok(g, ch, cfg):
		return "頭銜唔夠"
	return ""


# game 月 (monthDays 日一個月)
static func month_of(day: int, month_days: int) -> int:
	return day / maxi(1, month_days)


# 調查封鎖原因 → "" = 可以調查。rec = ch.recruit
# recruitLockUntil = 登用成功嗰日 + recruitLockDays (U16: 由曆月鎖改做滾動日數鎖，同 serveDays 一齊減半)
static func survey_block(rec: Dictionary, day: int, _month: int) -> String:
	var until := int(rec.get("recruitLockUntil", -1))
	if until >= 0 and day < until:
		return "登用鎖緊，%d 日後先可以再調查" % (until - day)
	if int(rec.get("surveyDay", -1)) == day:
		return "今日已經調查過，聽日再嚟"
	return ""


# 候選排序 key: 每日唔同 (同一日調查結果一樣，可重現)
static func _order_key(gid: int, day: int) -> int:
	var h := ((gid * 73856093) ^ (day * 19349663)) & 0x7FFFFFFF
	return (h * 2654435761) & 0x7FFFFFFF       # 再乘一次: 日子差 1 都會洗牌 (h < 2^31 → 唔會溢位)


# 調查候選 (spec 09 §3.2)
# kind = "wu"/"wen"；visible_t1 = 而家城內見到嘅 Tier1 id (Dictionary id->true)；gone = 呢個月走咗/跟緊人嘅 id
# Tier1: 要喺城內見到；登用池 (tier 0): 戰等喺 [玩家 -poolBelow, 玩家 +levelGap]，同名只列一個
# free = 御賜金牌 (Step 15): 無視理念/等級/頭銜 (池仍然要 ≥ 玩家 -poolBelow)
static func candidates(gens: Array, ch: Dictionary, kind: String, day: int, visible_t1: Dictionary,
		gone: Dictionary, cfg: Dictionary, free: bool = false) -> Array:
	var t1: Array = []
	var pool: Array = []
	var plv := int(ch["level"])
	for g in gens:
		var gid := int(g["id"])
		if String(g["type"]) != kind or gone.has(gid) or (not free and not check(g, ch, cfg).is_empty()):
			continue
		var tier := int(g["tier"])
		if tier == 1:
			if visible_t1.has(gid):
				t1.append(g)
		elif tier == 0 and int(g["lv"]) >= plv - int(cfg["poolBelow"]):
			pool.append(g)
	pool.sort_custom(func(a, b): return _order_key(int(a["id"]), day) < _order_key(int(b["id"]), day))
	var out: Array = t1.duplicate()
	var names := {}
	for g in t1:
		names[String(g["name"])] = true
	for g in pool:
		if out.size() >= int(cfg["surveyMax"]):
			break
		if names.has(String(g["name"])):
			continue
		names[String(g["name"])] = true
		out.append(g)
	return out


# 擂台臨時怪 def (spec 09 §3.2 設計: HP = 戰等×20，打到 0 = 制服)
static func arena_def(g: Dictionary, cfg: Dictionary) -> Dictionary:
	var a: Dictionary = cfg["arena"]
	var lv := int(g["lv"])
	return {"id": ARENA_DEF_BASE + int(g["id"]), "name": String(g["name"]), "level": lv,
		"hp": lv * int(a["hpPerLv"]), "atk": MathX.js_round(float(a["atkBase"]) + lv * float(a["atkPerLv"])),
		"def": int(floor(lv * float(a["defPerLv"]))), "atkInterval": int(a["atkInterval"]),
		"aggroRange": 0, "leash": int(a["leash"]), "flee": false, "groups": false, "boss": false,
		"drops": [], "gold": [0, 0], "exp": 0, "alignment": 0, "element": "none"}


# 問答過關
static func quiz_pass(ok: int, cfg: Dictionary, need: int = -1) -> bool:
	return ok >= (int(cfg["quizPass"]) if need < 0 else need)


# 登用到期日: 第 start+serveDays 日子時 0 刻離開
static func until_day(start_day: int, cfg: Dictionary) -> int:
	return start_day + int(cfg["serveDays"])


# 初始忠誠: 基本 + 同理念加成
static func loyalty_init(player_ideo: String, gen_ideo: String, cfg: Dictionary) -> int:
	var l: Dictionary = cfg["loyalty"]
	return clampi(int(l["init"]) + (int(l["sameIdeo"]) if player_ideo == gen_ideo else 0), 0, 100)


static func loyalty_add(loy: int, delta: int) -> int:
	return clampi(loy + delta, 0, 100)


# 殺善 (alignment > 0 = 善怪，殺咗善惡值跌) → 義理/治國武將忠誠跌 (spec 09 §4)
static func loyalty_kill_delta(gen_ideo: String, alignment: float, cfg: Dictionary) -> int:
	var l: Dictionary = cfg["loyalty"]
	if alignment > 0 and (l["badKillIdeo"] as Array).has(gen_ideo):
		return int(l["badKill"])
	return 0


# 忠誠結算: "stay" / "leave_now" (=0 即刻走) / "leave_daily" (<leave 子時走)
static func loyalty_verdict(loy: int, cfg: Dictionary) -> String:
	if loy <= 0:
		return "leave_now"
	if loy < int(cfg["loyalty"]["leave"]):
		return "leave_daily"
	return "stay"


# 同伴屬性: 義士成長表按戰等 → 武將武力 ×strMulWu；文官武力 ×strMulWen、智力 + 戰等×intAddWen
static func companion_attrs(cls: Dictionary, g: Dictionary, cfg: Dictionary) -> Dictionary:
	var c: Dictionary = cfg["companion"]
	var a := RulesStats.attrs_at(cls, int(g["lv"]))
	if String(g["type"]) == "wu":
		a["str"] = MathX.js_round(int(a["str"]) * float(c["strMulWu"]))
	else:
		a["str"] = MathX.js_round(int(a["str"]) * float(c["strMulWen"]))
		a["int"] = int(a["int"]) + MathX.js_round(int(g["lv"]) * float(c["intAddWen"]))
	return a


static func type_name(t: String) -> String:
	return "武將" if t == "wu" else "文官"
