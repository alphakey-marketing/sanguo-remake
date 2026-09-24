class_name RulesTitle
extends RefCounted
# 名聲 / 頭銜 / 官宅 / 飲水度 (Step 14, spec 08 §1~3, spec 01 §9~10)。純函數
# 【原】頭銜 60 階表 (data/titles.json)：名聲 + 資金討取、行動力上限、每月初一俸祿；官令每日 1 次扣行動力 10、頭銜解鎖；
#       喝茶回飲水度 50 + MP
# 【自訂】討取可以跳階 (名聲夠邊階都得，扣嗰階資金)；人才頭銜 = 戰等 - titleMinLv；官宅貢獻換行動丹


# 第 rank 階定義 (0 / 超出 = {})
static func def_of(titles: Array, rank: int) -> Dictionary:
	if rank < 1 or rank > titles.size():
		return {}
	return titles[rank - 1]


static func name_of(titles: Array, rank: int) -> String:
	return String(def_of(titles, rank).get("name", "白身"))


# 行動力上限【原】: 頭銜表 ap 欄；冇頭銜 = base
static func ap_max(titles: Array, rank: int, base: int) -> int:
	return int(def_of(titles, rank).get("ap", base))


# 俸祿【原】: 每月初一
static func salary(titles: Array, rank: int) -> int:
	return int(def_of(titles, rank).get("salary", 0))


# 名聲夠得上嘅最高階 (唔理資金)；0 = 一階都唔夠
static func fame_rank(titles: Array, fame: int) -> int:
	var r := 0
	for t in titles:
		if fame >= int(t["fame"]):
			r = int(t["rank"])
	return r


# 討取第 rank 階 → "" = 得；否則原因
static func claim_check(titles: Array, rank: int, cur_rank: int, fame: int, gold: int) -> String:
	var t := def_of(titles, rank)
	if t.is_empty():
		return "冇呢個頭銜"
	if rank <= cur_rank:
		return "你已經係%s" % name_of(titles, cur_rank)
	if fame < int(t["fame"]):
		return "名聲不足 (要 %d)" % int(t["fame"])
	if gold < int(t["gold"]):
		return "資金不足 (要 %d 金)" % int(t["gold"])
	return ""


# 每月初一 (day 0 唔計: 開局唔派)
static func is_month_start(day: int, month_days: int) -> bool:
	return day > 0 and day % maxi(1, month_days) == 0


# 人才頭銜【自訂】: 戰等 titleMinLv 以下 = 0 (唔設限)；以上每級一階，封頂 60
static func general_rank(gen_lv: int, cfg: Dictionary) -> int:
	return clampi(gen_lv - int(cfg["titleMinLv"]), 0, 60)


# 登用頭銜條件【原】: 50 級以上人才，玩家頭銜唔可以低過人才 titleGap 階以上
static func recruit_ok(gen_lv: int, player_rank: int, cfg: Dictionary) -> bool:
	if gen_lv < int(cfg["titleMinLv"]):
		return true
	return player_rank >= general_rank(gen_lv, cfg) - int(cfg["titleGap"])


# 接官令 → "" = 得。off = ch.office {orderDay, order}
static func order_block(order: Dictionary, rank: int, ap: int, day: int, off: Dictionary, ap_cost: int) -> String:
	if rank < int(order["rank"]):
		return "要%s以上頭銜" % String(order.get("rankName", "第 %d 階" % int(order["rank"])))
	if not (off.get("order", {}) as Dictionary).is_empty():
		return "手上仲有未完成嘅官令"
	if int(off.get("orderDay", -1)) == day:
		return "今日已經接過官令，聽日再嚟"
	if ap < ap_cost:
		return "行動力不足 (要 %d)" % ap_cost
	return ""


# 飲水度: 喝茶【原】回 tea，封頂 max
static func drink(thirst: int, cfg: Dictionary) -> int:
	return mini(int(cfg["max"]), thirst + int(cfg["tea"]))


# 搭話扣飲水度 (最低 0)
static func sip(thirst: int, cfg: Dictionary) -> int:
	return maxi(0, thirst - int(cfg["chat"]))
