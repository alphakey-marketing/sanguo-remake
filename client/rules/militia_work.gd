class_name RulesMilitiaWork
extends RefCounted
# 義勇軍工作 22 項純函數 (S08f, spec 08 §8 / 攻略 sy2_8_8)。
# 有城池：內政 10 + 軍事 3 + 軍備 9 = 22；無城池：得監督/商情兩項內政 + 軍事 3 + 軍備 9 = 14。
# 評定會議指派 3 類工作 (捐獻/監督/商情)；績效→功績對照表見 data/camp.json meritTable【原】。


static func works(camp: Dictionary) -> Array:
	return camp.get("works", [])


static func def_of(camp: Dictionary, work_id: String) -> Dictionary:
	for w in works(camp):
		if String((w as Dictionary).get("id", "")) == work_id:
			return w
	return {}


# 呢件工作而家做唔做得（冇城池 → 淨係監督/商情兩項內政）
static func is_available(camp: Dictionary, has_city: bool, work_id: String) -> bool:
	var w := def_of(camp, work_id)
	if w.is_empty():
		return false
	if bool(w.get("needCity", false)) and not has_city:
		return false
	return true


static func available(camp: Dictionary, has_city: bool) -> Array:
	var out: Array = []
	for w in works(camp):
		if is_available(camp, has_city, String(w["id"])):
			out.append(w)
	return out


static func assignment_kinds(camp: Dictionary) -> Array:
	return camp.get("assignmentKinds", ["donate", "supervise", "trade"])


static func max_assignments(camp: Dictionary) -> int:
	return int(camp.get("maxAssignments", 3))


# 一件工作屬邊個指派類別 ("" = 唔屬)
static func assignment_of(camp: Dictionary, work_id: String) -> String:
	var w := def_of(camp, work_id)
	if w.is_empty():
		return ""
	var a := String(w.get("assignment", ""))
	if a != "":
		return a
	var k := String(w.get("kind", ""))
	return k if (assignment_kinds(camp) as Array).has(k) else ""


# 績效 → 功績增減【原】[績效上限, 功績增減]；超出表尾當最後一格
static func merit_delta(camp: Dictionary, performance: int) -> int:
	var perf := maxi(0, performance)
	for row in camp.get("meritTable", []):
		if perf <= int(row[0]):
			return int(row[1])
	return 0


# 一次工作加幾多績效：基本 + 專長 lv × expertPerf + (有指派) assignBonus
static func performance_gain(camp: Dictionary, work_id: String, expert_lv: int, assigned: bool) -> int:
	var w := def_of(camp, work_id)
	if w.is_empty():
		return 0
	var g := int(w.get("perf", 10)) + maxi(0, expert_lv) * int(camp.get("expertPerf", 5))
	if assigned:
		g += int(camp.get("assignBonus", 20))
	return g
