class_name RulesShop
extends RefCounted
# 商店/客棧純函數。買價受魅力影響【原】，折扣幅度【自訂】: 每點魅力 0.5%，上限 20%；賣價 = 原價 50%
# bag = [{id, n}]


static func buy_price(base: float, cha: float, karma: int = 0, trade_lv: int = 0) -> int:
	return maxi(1, MathX.js_round(base * (1.0 - minf(0.2, cha * 0.005)) * (1.0 - RulesExpert.trade_buy_discount(trade_lv)) * RulesKarma.price_factor(karma)))


static func sell_price(base: float, trade_lv: int = 0) -> int:
	return int(floor(base * 0.5 * (1.0 + RulesExpert.trade_sell_bonus(trade_lv))))


static func add_item(bag: Array, id: int, n: int) -> void:
	for s in bag:
		if int(s["id"]) == id:
			s["n"] = int(s["n"]) + n
			return
	bag.append({"id": id, "n": n})


# 背包有幾多件 (Step 10: pre hasItem 檢查用)
static func has_item(bag: Array, id: int, n: int) -> bool:
	for s in bag:
		if int(s["id"]) == id and int(s["n"]) >= n:
			return true
	return false


# 背包內一種道具總件數 (融合後清理 fusedJewels 用)
static func count_item(bag: Array, id: int) -> int:
	var t := 0
	for s in bag:
		if int(s["id"]) == id:
			t += int(s["n"])
	return t


# 背包總重量 (S04a, spec 04 §6): 逐件 item id 叫 weight_fn(id)->int，乘件數加埋。
static func bag_weight(bag: Array, weight_fn: Callable) -> int:
	var t := 0
	for s in bag:
		t += int(s["n"]) * int(weight_fn.call(int(s["id"])))
	return t


# 背包加唔加得落 (拾取時背包滿檢查, S04a): 而家總重 + 新件重量 ≤ cap。
# weight_fn(id)->int 由 caller 傳 (要 items.json weight，rules 唔直接讀 data)。
static func bag_fits(bag: Array, item_id: int, n: int, weight_fn: Callable, cap: int) -> bool:
	return bag_weight(bag, weight_fn) + int(weight_fn.call(item_id)) * n <= cap


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
