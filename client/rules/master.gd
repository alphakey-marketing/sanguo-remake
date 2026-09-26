class_name RulesMaster
extends RefCounted
# 大宗師合成術（S05c, spec 05 §5）【原=系統框架；細節數值/產出地自訂】

# 合成寶石解鎖條件【原】：任一初階 100 級 + 同系列進階 20 級
static func gem_ready(basic_lv: int, adv_lv: int, cfg: Dictionary) -> bool:
	return basic_lv >= int(cfg.get("basicLv", 100)) and adv_lv >= int(cfg.get("advLv", 20))


static func has_need(bag_count: Dictionary, need: Array) -> bool:
	for m in need:
		if int(bag_count.get(int(m[0]), 0)) < int(m[1]):
			return false
	return true


static func gem_count_ok(n: int, cfg: Dictionary) -> bool:
	return n >= int(cfg.get("minGems", 2)) and n <= int(cfg.get("maxGems", 5))


# 進階大宗師合成術：成功率跟進階技能等級【自訂公式】= base + perLv × lv，clamp 0~0.95
static func synth_chance(adv_lv: int, cfg: Dictionary) -> float:
	return clampf(float(cfg.get("base", 0.15)) + float(cfg.get("perLv", 0.01)) * float(adv_lv), 0.0, 0.95)


static func pick_treasure(pool: Array, rng: Callable) -> int:
	return int(pool[int(floor(MathX.roll(rng) * pool.size()))])
