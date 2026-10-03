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


# 屬性頁用: 職業特技名 + 效果說明 (數值同 sim 一致)
const YISHI_FUSION := {"name": "融合", "desc": "將背包屬性石燒入裝備中嘅武器（只能 1 粒），隨時隨地可用。10 級起。"}
const DESCS := {
	"unlock": "開附近鎖住嘅寶箱，三支鑰匙揀啱一支。",
	"chaodu": "救起附近倒下嘅同伴／主公，消耗自己 20% HP + 30% MP。",
	"yinxing": "躲車小遊戲成功後潛行 100 tick：可以攻擊，但主動怪同居民睇唔到你。冷卻 1 日。",
	"qieting": "偷聽附近居民對話，得傳聞線索。冷卻 300 tick。",
	"toushi": "睇 NPC／怪嘅 HP、MP、等級，並進入洞悉狀態（+20%）。冷卻 180 tick。",
}


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