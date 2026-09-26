class_name RulesMerit
extends RefCounted
# 義舉證明 + 城池進貢 純函數 (S08a, spec 08 §1)
# 義舉證明: 四類 20 項物品，繳畀朝廷官員 (限許昌【原】)；每項固定名聲值【自訂】。
#   機密情報/古董軍備/特殊收藏品三類有頭銜需求【原 sy2_8_3】；為民除害類冇。
# 城池進貢: 進貢物資 (捐獻單位) → 名聲 + 該城好感【自訂 ×0.01，spec 08 §1】；唔扣行動力。
# cfg = data.office["merit"] / data.office["tribute"]；titles = data.titles


# 義舉證明物品定義；{} = 唔係義舉證明物品
static func item_def(cfg: Dictionary, item_id: int) -> Dictionary:
	for it in cfg["items"]:
		if int(it["id"]) == item_id:
			return it
	return {}


# 繳交前檢查 → "" = 得；titles 用嚟砌頭銜名
static func block(cfg: Dictionary, item_id: int, title_rank: int, titles: Array) -> String:
	var d := item_def(cfg, item_id)
	if d.is_empty():
		return "呢件唔係義舉證明物品"
	var req := int(d.get("reqRank", 0))
	if title_rank < req:
		return "要%s以上頭銜先收得（%s）" % [RulesTitle.name_of(titles, req), String(d["name"])]
	return ""


# 物品固定名聲值 (0 = 唔係義舉證明物品)
static func fame_of(cfg: Dictionary, item_id: int) -> int:
	return int(item_def(cfg, item_id).get("fame", 0))


# 城池好感【自訂】= 捐獻單位 × 0.01 (spec 08 §1「物資價值×0.01」, 以捐獻單位做價值)
static func favor_gain(units: int, cfg: Dictionary) -> int:
	return units / maxi(1, int(cfg["unitsPerFavor"]))


# 進貢名聲【自訂】= 捐獻單位 × 0.01
static func tribute_fame(units: int, cfg: Dictionary) -> int:
	return units / maxi(1, int(cfg["unitsPerFame"]))


# 好感封頂 (cfg.favorCap)
static func favor_cap(favor: int, cfg: Dictionary) -> int:
	return mini(int(cfg["favorCap"]), favor)