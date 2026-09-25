class_name RulesAmmo
extends RefCounted
# 弩箭消耗 (S02c-辯士, spec 02 §6【原】):
#   - 辯士用弩射箭，箭 = items.json cat「箭矢」(49) 類。
#   - 弩攻擊每發扣 1 箭（命中先扣；miss 唔燒箭）。
#   - 冇箭 → 弩出手唔到（去商店買箭 / 木匠製箭 = S05，見 PLAN §4）。
# 純函數，無狀態；箭矢偵測靠 data.cats (item id -> cat)。

const NU_WEAPON_CAT := 9              # 弩武器 (辯士主力遠距兵器，items.json cat 9)
const ARROW_CAT := 49                # items.json「箭矢」類


# 身上箭矢總數（背包 cat 49 道具數量加埋）
static func arrow_count(data: GameData, ch: Dictionary) -> int:
	var n := 0
	for b in ch.get("bag", []) as Array:
		if int(data.cats.get(int(b["id"]), 0)) == ARROW_CAT:
			n += int(b["n"])
	return n


# 有冇箭用 (配合弩出手檢查)
static func has_arrow(data: GameData, ch: Dictionary) -> bool:
	return arrow_count(data, ch) > 0


# 扣 n 支箭（由第一件箭矢堆扣起）。啱先扣得到呑 false。
static func consume_arrow(data: GameData, ch: Dictionary, n: int = 1) -> bool:
	for b in ch.get("bag", []) as Array:
		if int(data.cats.get(int(b["id"]), 0)) == ARROW_CAT and int(b["n"]) > 0:
			b["n"] = maxi(0, int(b["n"]) - n)
			return true
	return false