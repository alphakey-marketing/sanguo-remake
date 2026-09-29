class_name RulesClass
extends RefCounted
# 職階 (spec 01 §7): 二轉 50 級 / 三轉 100 級【原】；轉職考試任務 + 效果【自訂】。
# ch.tier = 0 初階 / 1 二轉 / 2 三轉（create_character 起 0；舊存檔缺欄 = 0）
# 轉職效果: 職名變化、進階武器解鎖、四招起絶招解鎖、專長等級上限提升。

const PROMOTE_LEVEL := [50, 100]                          # 【原】50 二轉、100 三轉
const PROMOTE_QUEST_T3 := "promote_test2"  # 三轉考試任務（S04d 接，暫未有）


# F6 轉職考試任務 id: 二轉 = 每職一份 promote_test_<classId>；三轉 = promote_test2
static func promote_quest_id(class_id: String, tier: int) -> String:
	return "promote_test_%s" % class_id if tier == 0 else PROMOTE_QUEST_T3
const TIER_NAMES := ["初階", "二轉", "三轉"]


static func tier_of(ch: Dictionary) -> int:
	return int(ch.get("tier", 0))


# 職名: 初階 = classes.name；二轉 = tier2.name；三轉 = tier3.name (classes.json)
static func title_of(cls: Dictionary, tier: int) -> String:
	if tier >= 2:
		var t3: Dictionary = cls.get("tier3", {})
		if not t3.is_empty() and t3.has("name"):
			return str(t3["name"])
	if tier >= 1:
		var t2: Dictionary = cls.get("tier2", {})
		if not t2.is_empty() and t2.has("name"):
			return str(t2["name"])
	return str(cls.get("name", ""))


static func tier_name_of(tier: int) -> String:
	return String(TIER_NAMES[clampi(tier, 0, TIER_NAMES.size() - 1)])


# 進階武器解鎖【自訂】(spec 01 §7): 武器職階要求 = req_lv 分帯 — req_lv 51~99 要二轉、100+ 要三轉。
# 二轉後仍可用初階武器（承繼，冇向上限制）；唔轉職就永遠卡喺 req_lv ≤50 武器帯。
static func weapon_tier_required(req_lv: int) -> int:
	if req_lv >= 100:
		return 2
	if req_lv >= 51:
		return 1
	return 0


# 絕招使用資格 (ultimates.json reqTier/reqLevel): 四招起二轉先用得【原】；五/六招三轉【原】
static func ultimate_usable(ch: Dictionary, ult: Dictionary) -> Dictionary:
	var out := {"ok": true, "why": ""}
	var tr := int(ult.get("reqTier", 0))
	if tier_of(ch) < tr:
		out["ok"] = false
		out["why"] = "要二轉之後先用得「%s」" % ult.get("name", "")
		if tr >= 2:
			out["why"] = "要三轉之後先用得「%s」" % ult.get("name", "")
		return out
	if int(ch["level"]) < int(ult.get("reqLevel", 0)):
		out["ok"] = false
		out["why"] = "要 Lv%d 先用得「%s」" % [int(ult["reqLevel"]), ult.get("name", "")]
		return out
	return out


# 專長等級上限提升【自訂】(spec 01 §7): 二轉 +1 / 三轉 +2（喺 experts.json caps 表基礎上）
static func expert_cap_bonus(tier: int) -> int:
	return tier


# 轉職資格: 等級 + 對應轉職考試任務完成。回 {"ok": bool, "why": String, "tier": int(目標階)}
static func promote_ok(data: GameData, ch: Dictionary) -> Dictionary:
	var tier := tier_of(ch)
	var out := {"ok": false, "why": "", "tier": tier + 1}
	if tier >= 2:
		out["why"] = "經已係最高階（三轉），冇得再轉"
		return out
	var lv_need := int(PROMOTE_LEVEL[tier])
	if int(ch["level"]) < lv_need:
		out["why"] = "要 Lv%d 先可以轉職（%s）" % [lv_need, tier_name_of(tier + 1)]
		return out
	var qid := promote_quest_id(String(ch.get("classId", "")), tier)
	var quest := {}
	for q in data.quests:
		if String(q["id"]) == qid:
			quest = q
			break
	if quest.is_empty():
		out["why"] = "「%s」任務未開放（%s考驗）" % [qid, tier_name_of(tier + 1)]
		return out
	if not bool(ch.get("questDone", {}).get(qid, false)):
		out["why"] = "要完成「%s」任務先可以轉職" % quest.get("name", qid)
		return out
	out["ok"] = true
	return out