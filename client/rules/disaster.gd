class_name RulesDisaster
extends RefCounted
# 天災生成純函數 (Step 4)【自訂】: 每日每城擲骰，受季節限制。防災度喺 supply_mods 度處理。
# 回傳 active disaster dict: {id, name, city, size, startDay, endDay, supply:{cat: f}} (from def)

const SIZE_W := [0.25, 0.6, 1.0]     # 大/中/細 累積機率


# 每日每城: 掟 rng 睇有冇天災發生。回傳 disaster dict 或 {}
# shutdown_cfg (spec 05 §6【自訂】): {min,max} 大/中規模天災停對應 cat 商店進貨 1~3 日
static func roll_day(rng: Callable, day: int, season: int, city_id: String, defs: Array, shutdown_cfg: Dictionary = {}) -> Dictionary:
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
		var out := {
			"id": d["id"], "name": d["name"], "city": city_id, "size": sz["size"],
			"startDay": day, "endDay": day + int(sz["days"]),
			"supply": sz["supply"],
		}
		if idx < 2 and not shutdown_cfg.is_empty():          # 大(0)/中(1) 先停進貨；細(2) 唔停
			var lo := int(shutdown_cfg.get("min", 1))
			var hi := int(shutdown_cfg.get("max", 3))
			var sd := lo + int(floor(MathX.roll(rng) * float(hi - lo + 1)))
			sd = mini(sd, int(sz["days"]))
			out["shutdownEnd"] = day + maxi(1, sd)
			out["shutdownCats"] = (sz["supply"] as Dictionary).keys()
		return out
	return {}


# 過期天災移除 (原地)
static func expire(disasters: Array, day: int) -> void:
	for i in range(disasters.size() - 1, -1, -1):
		if day >= int(disasters[i]["endDay"]):
			disasters.remove_at(i)