class_name RulesCamp
extends RefCounted
# 義勇軍營地建設純函數 (S08f, spec 08 §7 / 攻略 sy2_8_6)。
# 10 個設施；升級材料 = 每級基本 × 目標級數 (升 2 級 = 基本×2、3 級 = ×3)。
# 監督完成度 = Σ(監督次數 × (0.5 + 政治×0.01 + 木匠 lv×0.02 + 身份加成))【公式自訂】。
# 規模每級提升工作指派份數 (50/60/70/85/100) 同階級人數上限。


static func cfg(camp: Dictionary) -> Dictionary:
	return camp


static func facilities(camp: Dictionary) -> Array:
	return camp.get("facilities", [])


static func def_of(camp: Dictionary, fac_id: String) -> Dictionary:
	for f in facilities(camp):
		if String((f as Dictionary).get("id", "")) == fac_id:
			return f
	return {}


static func initial_level(camp: Dictionary, fac_id: String) -> int:
	var f := def_of(camp, fac_id)
	return int(f.get("initial", 0)) if not f.is_empty() else 0


static func max_level(camp: Dictionary) -> int:
	return int(camp.get("maxLevel", 10))


static func upgrade_roles(camp: Dictionary) -> Array:
	return camp.get("upgradeRoles", ["banner", "canjun"])


static func role_def(camp: Dictionary, role: String) -> Dictionary:
	for r in camp.get("roles", []):
		if String((r as Dictionary).get("id", "")) == role:
			return r
	return {}


static func role_name(camp: Dictionary, role: String) -> String:
	var r := role_def(camp, role)
	return String(r.get("name", role)) if not r.is_empty() else role


static func role_bonus(camp: Dictionary, role: String) -> float:
	var r := role_def(camp, role)
	return float(r.get("bonus", 0.0)) if not r.is_empty() else 0.0


static func can_upgrade_role(camp: Dictionary, role: String) -> bool:
	return (upgrade_roles(camp) as Array).has(role)


# 升級到 target_level 需要嘅材料：{gold, materials: {item_id: n}}（基本 × target_level，同 id 相加）
static func upgrade_cost(camp: Dictionary, fac_id: String, target_level: int) -> Dictionary:
	var f := def_of(camp, fac_id)
	if f.is_empty():
		return {"gold": 0, "materials": {}}
	var base: Dictionary = f.get("base", {})
	var gold := int(base.get("gold", 0)) * target_level
	var mats := {}
	for m in base.get("materials", []):
		var iid := int(m[0])
		mats[iid] = int(mats.get(iid, 0)) + int(m[1]) * target_level
	return {"gold": gold, "materials": mats}


# 監督一次加幾多完成度點
static func supervise_points(camp: Dictionary, pol: int, carpenter_lv: int, role: String) -> float:
	var cfg: Dictionary = camp.get("supervise", {})
	return float(cfg.get("base", 0.5)) + float(pol) * float(cfg.get("pol", 0.01)) \
		+ float(carpenter_lv) * float(cfg.get("carpenter", 0.02)) + role_bonus(camp, role)


static func supervise_target(camp: Dictionary) -> int:
	return int((camp.get("supervise", {}) as Dictionary).get("target", 100))


# 營地規模 (camp 設施級) → 工作指派份數上限
static func work_cap(camp: Dictionary, camp_level: int) -> int:
	var t: Dictionary = camp.get("workCapByLevel", {})
	return int(t.get(str(clampi(camp_level, 1, 5)), 50))


# 營地規模 → 某階級人數上限 (grade 1~8)
static func grade_limit(camp: Dictionary, camp_level: int, grade: int) -> int:
	var t: Dictionary = camp.get("gradeLimitByLevel", {})
	var row: Array = t.get(str(clampi(camp_level, 1, 5)), [])
	if grade < 1 or grade > row.size():
		return 0
	return int(row[grade - 1])


# 設施某 store 喺某級嘅上限；-1 = 冇上限資料
static func facility_cap(camp: Dictionary, fac_id: String, level: int, store_key: String) -> int:
	var f := def_of(camp, fac_id)
	if f.is_empty():
		return -1
	var sc: Dictionary = (f.get("storeCaps", {}) as Dictionary).get(store_key, {})
	if sc.is_empty():
		return -1
	var vals: Array = sc.get("vals", [])
	if level < 1 or level > vals.size():
		return -1
	return int(vals[level - 1]) * int(sc.get("unit", 1))


# 某級開放嘅職位
static func positions_at(camp: Dictionary, level: int) -> Array:
	var t: Dictionary = camp.get("positionsByLevel", {})
	return t.get(str(level), [])
