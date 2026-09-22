class_name RulesShop
extends RefCounted
# 商店/客棧純函數。買價受魅力影響【原】，折扣幅度【自訂】: 每點魅力 0.5%，上限 20%；賣價 = 原價 50%
# bag = [{id, n}]


static func buy_price(base: float, cha: float) -> int:
	return maxi(1, MathX.js_round(base * (1.0 - minf(0.2, cha * 0.005))))


static func sell_price(base: float) -> int:
	return int(floor(base * 0.5))


static func add_item(bag: Array, id: int, n: int) -> void:
	for s in bag:
		if int(s["id"]) == id:
			s["n"] = int(s["n"]) + n
			return
	bag.append({"id": id, "n": n})


static func remove_item(bag: Array, id: int, n: int) -> bool:
	for i in bag.size():
		var s: Dictionary = bag[i]
		if int(s["id"]) == id:
			if int(s["n"]) < n:
				return false
			s["n"] = int(s["n"]) - n
			if int(s["n"]) <= 0:
				bag.remove_at(i)
			return true
	return false
