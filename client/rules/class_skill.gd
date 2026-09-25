class_name RulesClassSkill
extends RefCounted
# 職業特技 (S02c, spec 02 §6)【自訂】單機化: 每職一招，學到 = ch.classSkill = skill id（單一格）。
# 義士「融合」係 Step 10 內建（打鐵鋪 QTE），唔經呢度；呢度管理其餘五職。
# 純函數，無狀態；data = GameData.class_skills (id -> def, data/class_skills.json)。


# skill def（行唔到就 {}）
static func def_of(data: GameData, skill_id: String) -> Dictionary:
	return (data.class_skills as Dictionary).get(skill_id, {})


static func learned(ch: Dictionary, skill_id: String) -> bool:
	return String(ch.get("classSkill", "")) == skill_id


# 使用資格（唔包目標檢查 — 目標由 sim 嗰層做，例如開鎖要有寶箱喺附近）
static func can_use(data: GameData, ch: Dictionary, skill_id: String) -> Dictionary:
	var out := {"ok": true, "why": ""}
	var def: Dictionary = (data.class_skills as Dictionary).get(skill_id, {})
	if def.is_empty():
		out["ok"] = false
		out["why"] = "呢招特技唔存在"
		return out
	if String(ch.get("classId", "")) != String(def.get("class", "")):
		out["ok"] = false
		out["why"] = "你嘅職業用唔到「%s」" % String(def.get("name", skill_id))
		return out
	if not learned(ch, skill_id):
		out["ok"] = false
		out["why"] = "未學「%s」（搵導師領）" % String(def.get("name", skill_id))
		return out
	if int(ch["level"]) < int(def.get("lv", 1)):
		out["ok"] = false
		out["why"] = "要 Lv%d 先用得「%s」" % [int(def["lv"]), String(def.get("name", skill_id))]
		return out
	return out