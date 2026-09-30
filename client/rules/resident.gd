class_name RulesResident
extends RefCounted
# 居民 NPC 規則層 (S09a, spec 09 §1): 性格/理念/role/日程/city count/名字生成。
# 純函數 + 數據驅動；唔碰 sim 狀態。所有隨機由外面 sim 用 SimRng 抽 index 傳入。


static func cfg(residents: Dictionary) -> Dictionary:
	var c = residents.get("cfg", {})
	return c if c is Dictionary else {}


static func roles(residents: Dictionary) -> Array:
	var r = residents.get("roles", [])
	return r if r is Array else []


static func role_ids(residents: Dictionary) -> Array:
	var out: Array = []
	for r in roles(residents):
		out.append(String(r.get("id", "")))
	return out


static func role_def(residents: Dictionary, role_id: String) -> Dictionary:
	for r in roles(residents):
		if String(r.get("id", "")) == role_id:
			return r
	return {}


static func role_name(residents: Dictionary, role_id: String) -> String:
	return String(role_def(residents, role_id).get("name", role_id))


static func role_total(residents: Dictionary) -> int:
	var t := 0
	for r in roles(residents):
		t += maxi(1, int(r.get("weight", 1)))
	return maxi(1, t)


# roll 係 [0, role_total) 嘅整數 (sim 用 SimRng.below 抽)；揀一個 role
static func pick_role(residents: Dictionary, roll: int) -> Dictionary:
	var rs := roles(residents)
	if rs.is_empty():
		return {}
	var t := role_total(residents)
	var k := ((roll % t) + t) % t
	for r in rs:
		k -= maxi(1, int(r.get("weight", 1)))
		if k < 0:
			return r
	return rs[rs.size() - 1]


static func is_positive(role: Dictionary) -> bool:
	return String(role.get("align", "good")) == "good"


static func personality_dims(residents: Dictionary) -> Array:
	var d = cfg(residents).get("personalityDims", [])
	return d if d is Array else []


# values = 5 個 0~maxv 整數 → 5 維 0.0~1.0 (夾好)
static func personality(dims: Array, values: Array, maxv: int = 10) -> Dictionary:
	var m := maxi(1, maxv)
	var out := {}
	for i in dims.size():
		var v := float(values[i]) if i < values.size() else 0.0
		out[String(dims[i])] = clampf(v / float(m), 0.0, 1.0)
	return out


# 每城居民數: 12~20，大城 (人口高) 多
static func city_count(city: Dictionary, residents: Dictionary) -> int:
	var c := cfg(residents)
	var lo := int(c.get("minPerCity", 12))
	var hi := int(c.get("maxPerCity", 20))
	var per := maxi(1, int(c.get("popPerResident", 30)))
	var pop := int(city.get("pop", int(c.get("borderPop", 350))))
	return clampi(int(round(float(pop) / float(per))), lo, maxi(lo, hi))


static func schedule(residents: Dictionary) -> Array:
	var s = cfg(residents).get("schedule", [])
	return s if s is Array else []


# 時辰 0(子)..11(亥) → 活動 (sleep/work/eat/home)；越界 wrap
static func activity_at(residents: Dictionary, shichen: int) -> String:
	var s := schedule(residents)
	if s.is_empty():
		return "home"
	return String(s[((shichen % s.size()) + s.size()) % s.size()])


# 居民日程驅動 (spec 09 §1): 某啲活動 (cfg.inTownActivities，如 eat/home/sleep) → 留城內行街/休息，唔出野外；
# 其餘 (work) → 去 homeZone 野外練功。非 in-town 活動一律回 false (照舊野外)。
# role 分流: 只有 work=field 嘅居民 (村民) 工作時辰出野區；商販/衛兵/馬夫/官員 (shop/gate/stable/office) 上班留城
static func stays_in_town(residents: Dictionary, role_id: String, activity: String) -> bool:
	if is_city_activity(residents, activity):
		return true
	var w := String(role_def(residents, role_id).get("work", "field"))
	return activity == "work" and w != "field"


static func is_city_activity(residents: Dictionary, activity: String) -> bool:
	var in_town = cfg(residents).get("inTownActivities", [])
	return in_town is Array and (in_town as Array).has(activity)


static func home_zone(residents: Dictionary, city_id: String) -> String:
	var cs = residents.get("cities", {})
	if not (cs is Dictionary):
		return ""
	var d = cs.get(city_id, {})
	return String((d as Dictionary).get("homeZone", "")) if d is Dictionary else ""


static func ideologies(residents: Dictionary) -> Array:
	var i = cfg(residents).get("ideologies", [])
	return i if i is Array else []


static func ideology_at(residents: Dictionary, idx: int) -> String:
	var ids := ideologies(residents)
	if ids.is_empty():
		return "義理"
	return String(ids[((idx % ids.size()) + ids.size()) % ids.size()])


static func surname_pool(residents: Dictionary) -> Array:
	var n = residents.get("names", {})
	return n.get("surnames", []) if n is Dictionary else []


static func given_pool(residents: Dictionary) -> Array:
	var n = residents.get("names", {})
	return n.get("given", []) if n is Dictionary else []


# 決定性名字: si/gi 由 sim 用 SimRng 抽；越界 wrap；池空回 "居民"
static func make_name(residents: Dictionary, si: int, gi: int) -> String:
	var sn := surname_pool(residents)
	var gn := given_pool(residents)
	if sn.is_empty():
		return "居民"
	var s := String(sn[((si % sn.size()) + sn.size()) % sn.size()])
	if gn.is_empty():
		return s
	var g := String(gn[((gi % gn.size()) + gn.size()) % gn.size()])
	return s + g
