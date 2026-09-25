class_name RulesMountBattle
extends RefCounted
# 馬戰 (Step 17b, spec 07 §7 / spec 02 §10): 馬戰兵器 + 特技，純函數。數值喺 data/mount_weapons.json (cfg)


static func weapon_def(cfg: Dictionary, wtype: String, wid: String) -> Dictionary:
	for w in (cfg["weapons"] as Dictionary).get(wtype, []):
		if String(w["id"]) == wid:
			return w
	return {}


static func weapon_type_of(cfg: Dictionary, wid: String) -> String:
	for t in cfg["weapons"]:
		for w in cfg["weapons"][t]:
			if String(w["id"]) == wid:
				return String(t)
	return ""


static func weapon_buy_why(cfg: Dictionary, level: int, wtype: String, wid: String) -> String:
	var w := weapon_def(cfg, wtype, wid)
	if w.is_empty():
		return "冇呢件馬戰兵器"
	if level < int(w["lv"]):
		return "要 Lv%d 先買得" % int(w["lv"])
	return ""


static func skill_def(cfg: Dictionary, skill_id: String) -> Dictionary:
	for s in cfg["skills"]:
		if String(s["id"]) == skill_id:
			return s
	return {}


static func skills_of(cfg: Dictionary, wtype: String) -> Array:
	var out: Array = []
	for s in cfg["skills"]:
		if String(s["weapon"]) == wtype:
			out.append(s)
	return out


# 學特技: 最多 maxSkills 招、要有對應種類兵器【原】
static func learn_why(cfg: Dictionary, learned: Array, wtype_owned: String, skill_id: String) -> String:
	var s := skill_def(cfg, skill_id)
	if s.is_empty():
		return "冇呢招特技"
	if learned.has(skill_id):
		return "已經學咗"
	if learned.size() >= int(cfg["maxSkills"]):
		return "最多學 %d 招馬戰特技" % int(cfg["maxSkills"])
	if String(s["weapon"]) != wtype_owned:
		return "要有對應嘅馬戰兵器先學得"
	return ""


# 用特技: 要騎緊 + 裝備對應兵器 + 學過 + 唔喺冷卻 + SP 夠
static func use_why(cfg: Dictionary, learned: Array, riding: bool, wtype_owned: String, skill_id: String,
		cd_until: int, tick: int, sp: int) -> String:
	var s := skill_def(cfg, skill_id)
	if s.is_empty() or not (learned as Array).has(skill_id):
		return "未學呢招"
	if not riding:
		return "要騎緊馬先用得馬戰特技"
	if String(s["weapon"]) != wtype_owned:
		return "冇裝備對應嘅馬戰兵器"
	if tick < cd_until:
		return "冷卻中 (%d tick)" % (cd_until - tick)
	if sp < int(s.get("sp", 0)):
		return "體力不足"
	return ""
