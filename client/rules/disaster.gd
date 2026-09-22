class_name RulesDisaster
extends RefCounted
# 天災生成純函數 (Step 4)【自訂】: 每日每城擲骰，受季節限制。防災度喺 supply_mods 度處理。
# 回傳 active disaster dict: {id, name, city, size, startDay, endDay, supply:{cat: f}} (from def)

const SIZE_W := [0.25, 0.6, 1.0]     # 大/中/細 累積機率


# 每日每城: 掟 rng 睇有冇天災發生。回傳 disaster dict 或 {}
static func roll_day(rng: Callable, day: int, season: int, city_id: String, defs: Array) -> Dictionary:
	for d in defs:
		var ok := false
		for s in d["seasons"]:
			if int(s) == season:
				ok = true
		if not ok:
			continue
		if MathX.roll(rng) >= float(d["chancePerDay"]):
			continue
		var r := MathX.roll(rng)
		var idx := 0
		if r >= SIZE_W[0]:
			idx = 1 if r < SIZE_W[1] else 2
		var sz: Dictionary = d["sizes"][idx]
		return {
			"id": d["id"], "name": d["name"], "city": city_id, "size": sz["size"],
			"startDay": day, "endDay": day + int(sz["days"]),
			"supply": sz["supply"],
		}
	return {}


# 過期天災移除 (原地)
static func expire(disasters: Array, day: int) -> void:
	for i in range(disasters.size() - 1, -1, -1):
		if day >= int(disasters[i]["endDay"]):
			disasters.remove_at(i)