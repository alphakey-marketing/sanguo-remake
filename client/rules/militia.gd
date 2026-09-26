class_name RulesMilitia
extends RefCounted
# 義勇軍成立 / 帶兵量 (S08e, spec 08 §4~§5 / 攻略 sy2_8_2、sy2_9_19)。純函數
# 【原】成立 4 條件: 頭銜南中郎將、25 人擁護 (每人 Lv5 + 名聲 100)、經費 20 萬、定居非新手城。
# 【自訂】單機化: 擁護者門檻改用 10 人 + 居民好感 ≥50 (spec §4 註「隨想簡化: 10 個都得」)。
# 【原】帶兵量 = 7000 (5 級+入會) + 階級帶兵 8000~1000 + 頭銜帶兵; 51~60 階固定 28000。


# office.militia 設定
static func cfg(office: Dictionary) -> Dictionary:
	return office.get("militia", {})


# 義勇軍階級帶兵量【原】(grade 1~8 → 一品 8000 … 八品 1000)
static func grade_soldiers(cfg: Dictionary, grade: int) -> int:
	var grades: Array = cfg.get("grades", [])
	if grade < 1 or grade > grades.size():
		return 0
	return int((grades[grade - 1] as Dictionary).get("soldiers", 0))


static func grade_name(cfg: Dictionary, grade: int) -> String:
	var grades: Array = cfg.get("grades", [])
	if grade < 1 or grade > grades.size():
		return ""
	return String((grades[grade - 1] as Dictionary).get("name", ""))


# 頭銜增加帶兵量 (titles.json soldiers 欄；0 = 白身)
static func title_soldiers(titles: Array, rank: int) -> int:
	if rank < 1 or rank > titles.size():
		return 0
	return int((titles[rank - 1] as Dictionary).get("soldiers", 0))


# 最大帶兵量【原】: 未成立 / 未夠 5 級 = 0；51 階起固定 capSoldiers
static func max_soldiers(titles: Array, cfg: Dictionary, rank: int, grade: int, level: int, founded: bool) -> int:
	if not founded:
		return 0
	if level < int(cfg.get("minLv", 5)):
		return 0
	if rank >= int(cfg.get("capRank", 51)):
		return int(cfg.get("capSoldiers", 28000))
	return int(cfg.get("baseSoldiers", 7000)) + grade_soldiers(cfg, grade) + title_soldiers(titles, rank)


# 新手城【原 sy2_8_2】: 許昌/襄陽/新野 (原 許昌/襄陽/洛陽 → 換新野) 唔可以成立義勇軍
static func is_newbie(cfg: Dictionary, city: String) -> bool:
	return (cfg.get("newbieCities", []) as Array).has(city)


# 定居檢查: city "" = 唔喺城池；同現居一樣 = 多餘
static func settle_block(_cfg: Dictionary, city: String, current: String) -> String:
	if city == "":
		return "呢度唔係城池，定居唔到"
	if city == current:
		return "你已經定居喺呢度"
	return ""


# 遊說擁護者檢查【自訂】: 居民 Lv ≥ supporterLv + 好感 ≥ supporterFavor
static func invite_block(cfg: Dictionary, lv: int, favor: int, already: bool, founded: bool) -> String:
	if founded:
		return "義勇軍已經成立，唔使再拉人"
	if already:
		return "佢已經擁護咗你"
	if lv < int(cfg.get("supporterLv", 5)):
		return "佢等級不足 (要 Lv %d)" % int(cfg.get("supporterLv", 5))
	if favor < int(cfg.get("supporterFavor", 50)):
		return "佢對你嘅好感不足 (要 %d，而家 %d)" % [int(cfg.get("supporterFavor", 50)), favor]
	return ""


# 名號檢查 (唯一無從驗證: 單機冇其他玩家，只驗非空 + 長度)
static func name_block(cfg: Dictionary, nm: String) -> String:
	var s := nm.strip_edges()
	if s == "":
		return "要輸入義勇軍名號"
	if s.length() > int(cfg.get("nameMaxLen", 12)):
		return "名號太長 (最多 %d 字)" % int(cfg.get("nameMaxLen", 12))
	return ""


# 成立檢查【原 sy2_8_2】。ch = 玩家角色，supporters = 擁護人數，home = ch.homeCity
static func found_block(titles: Array, cfg: Dictionary, ch: Dictionary, supporters: int, home: String) -> String:
	if bool((ch.get("militia", {}) as Dictionary).get("founded", false)):
		return "你已經成立咗義勇軍"
	var min_rank := int(cfg.get("minTitleRank", 6))
	if int(ch.get("titleRank", 0)) < min_rank:
		return "要「%s」以上頭銜 (而家 %s)" % [_title_name(titles, min_rank), _title_name(titles, int(ch.get("titleRank", 0)))]
	if int(ch.get("fame", 0)) < int(cfg.get("minFame", 3000)):
		return "名聲不足 (要 %d)" % int(cfg.get("minFame", 3000))
	var need := int(cfg.get("supporterNeed", 10))
	if supporters < need:
		return "擁護者不足 (%d/%d)" % [supporters, need]
	if int(ch.get("gold", 0)) < int(cfg.get("fund", 200000)):
		return "經費不足 (要 %d 兩)" % int(cfg.get("fund", 200000))
	if home == "":
		return "未定居，去目標城池定居先"
	if is_newbie(cfg, home):
		return "唔可以喺新手城成立 (要定居非新手城)"
	return ""


static func _title_name(titles: Array, rank: int) -> String:
	if rank < 1 or rank > titles.size():
		return "白身"
	return String((titles[rank - 1] as Dictionary).get("name", "白身"))
