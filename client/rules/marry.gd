class_name RulesMarry
extends RefCounted
# 結婚系統純函數 (S09e, spec 06 §9 / 09 §6): 御賜函/喜餅/婚戒/好感鎖/離婚設定讀取 + 條件檢查。
# 全部無狀態（data/ch 由參數傳入）。數值/名單喺 data/marry.json。

static func cfg(m: Dictionary) -> Dictionary:
	return m.get("cfg", {})


static func affinity_lock(m: Dictionary) -> int:
	return int(cfg(m).get("affinityLock", 90))


static func summon_sp(m: Dictionary) -> int:
	return int(cfg(m).get("summonSp", 50))


static func divorce_gold(m: Dictionary) -> int:
	return int(cfg(m).get("divorceGold", 500000))


static func ring_item(m: Dictionary) -> int:
	return int(cfg(m).get("ringItem", 0))


static func message_max_len(m: Dictionary) -> int:
	return int(cfg(m).get("messageMaxLen", 40))


static func festive_days(m: Dictionary) -> int:
	return int(cfg(m).get("festiveDays", 1))


static func share_affinity(m: Dictionary) -> int:
	return int(cfg(m).get("shareAffinity", 10))


# 男女御賜函 (M/F) → item id
static func letters(m: Dictionary) -> Dictionary:
	return cfg(m).get("letters", {})


static func letter_for(m: Dictionary, gender: String) -> int:
	return int(letters(m).get(gender, 0))


# 玩家性別由職業表讀 (classes.json gender M/F)
static func gender_of(data: GameData, ch: Dictionary) -> String:
	var c: Dictionary = data.classes.get(String(ch.get("classId", "")), {})
	return String(c.get("gender", ""))


static func has_letter(bag: Array, m: Dictionary, gender: String) -> bool:
	var it := letter_for(m, gender)
	return it != 0 and RulesShop.has_item(bag, it, 1)


# 婚戒 = 結婚戒指 item (無限召喚伴侶)
static func has_ring(bag: Array, m: Dictionary) -> bool:
	var it := ring_item(m)
	return it != 0 and RulesShop.has_item(bag, it, 1)


# ================= 喜餅 (spec 06 §9 步驟 2) =================
static func cakes(m: Dictionary) -> Array:
	return cfg(m).get("cakes", [])


static func cake_tiers(m: Dictionary) -> Array:
	var out: Array = []
	for c in cakes(m):
		out.append(int(c["tier"]))
	return out


static func cake_by_buy(m: Dictionary, buy_item: int) -> Dictionary:
	for c in cakes(m):
		if int(c["buy"]) == buy_item:
			return c
	return {}


static func cake_by_tier(m: Dictionary, tier: int) -> Dictionary:
	for c in cakes(m):
		if int(c["tier"]) == tier:
			return c
	return {}


# 開餅盒: 喜餅 → 對應喜餅 (雙雙對對餅等)
static func open_result(m: Dictionary, buy_item: int) -> int:
	var c := cake_by_buy(m, buy_item)
	return int(c.get("open", 0))


# 喜餅內容物 [[點心 id, n], ...]
static func contents(m: Dictionary, open_item: int) -> Array:
	for c in cakes(m):
		if int(c["open"]) == open_item:
			return c.get("contents", [])
	return []


# ================= 條件檢查 (回 "" = 可以) =================
# 求婚: 未結婚/未訂親 + 有御賜函 + 同伴好感 (忠誠) ≥ affinityLock
static func propose_block(m: Dictionary, ch: Dictionary, comp: Dictionary, gender: String) -> String:
	var ms: Dictionary = ch.get("marry", {})
	if not (ms.get("spouse", {}) as Dictionary).is_empty():
		return "你已經有配偶"
	if not (ms.get("engaged", {}) as Dictionary).is_empty():
		return "你已經訂咗親"
	if comp.is_empty() or not comp.has("gen"):
		return "要先登用一位武將同伴"
	if not has_letter(ch.get("bag", []), m, gender):
		return "要帶住御賜函（去結婚村搵朝廷官員拎）"
	var loy := int(comp["gen"].get("loyalty", 0))
	if loy < affinity_lock(m):
		return "同伴好感未夠 %d（而家 %d）" % [affinity_lock(m), loy]
	return ""


static func book_block(m: Dictionary, ch: Dictionary) -> String:
	var ms: Dictionary = ch.get("marry", {})
	if (ms.get("engaged", {}) as Dictionary).is_empty():
		return "要先向同伴求婚"
	if not (ms.get("booked", {}) as Dictionary).is_empty():
		return "婚禮已經預約咗"
	return ""


static func hold_block(m: Dictionary, ch: Dictionary) -> String:
	var ms: Dictionary = ch.get("marry", {})
	if (ms.get("engaged", {}) as Dictionary).is_empty():
		return "要先向同伴求婚"
	if (ms.get("booked", {}) as Dictionary).is_empty():
		return "要先預約禮堂"
	return ""


# 離婚: 有配偶 + 帶住婚戒
static func divorce_block(m: Dictionary, ch: Dictionary) -> String:
	var ms: Dictionary = ch.get("marry", {})
	if (ms.get("spouse", {}) as Dictionary).is_empty():
		return "你根本冇配偶"
	return ""


# 召喚: 有配偶 + (身上或配偶身上) 有婚戒
static func summon_block(m: Dictionary, ch: Dictionary, comp_present: bool) -> String:
	var ms: Dictionary = ch.get("marry", {})
	if (ms.get("spouse", {}) as Dictionary).is_empty():
		return "你未結婚"
	if not comp_present and not has_ring(ch.get("bag", []), m):
		return "要帶住婚戒先召喚得到"
	return ""