class_name RulesEquip
extends RefCounted
# 裝備/防具純函數 (Step 11.6, spec 02 §9)。部位【原】；數值換算/耐久/上限全部【自訂】(data/equip.json)
# armor stats = {def, evade, sdef, sevade, str, agi, int, spi, dmgRed, sdmgRed, resist:{status id -> %}}

const SLOTS := ["head", "body", "boots", "ring", "necklace"]
const WEAPON_SLOTS := 3                  # 【原】武器 3 槽 Alt+A/S/D 切換
const ATTR_EFFECT := {1: "str", 2: "agi", 4: "spi", 5: "int"}     # effect type -> attrs key
# 迴避異常狀態 34~37 -> status id (中邪/封咒 = RulesSpell；媚惑/蠱毒未有術法，先記住)
const RESIST_EFFECT := {34: "hex", 35: "sealed", 36: "charm", 37: "poison"}
const RESIST_ALL := 39                   # 迴避異常狀態 (全部)


# items.json effects → 防具數值 (冇嘅 = 0)
static func armor_stats(effects: Array) -> Dictionary:
	var s := {"def": 0, "evade": 0, "sdef": 0, "sevade": 0, "str": 0, "agi": 0, "int": 0, "spi": 0,
		"dmgRed": 0, "sdmgRed": 0, "resist": {}}
	for e in effects:
		var t := int(e["type"])
		var v := int(e["value"])
		match t:
			9: s["def"] += v
			10: s["evade"] += v
			11: s["sdef"] += v
			12: s["sevade"] += v
			52: s["dmgRed"] += v
			53: s["sdmgRed"] += v
			RESIST_ALL:
				for k in RESIST_EFFECT.values():
					s["resist"][k] = int(s["resist"].get(k, 0)) + v
			_:
				if ATTR_EFFECT.has(t):
					s[ATTR_EFFECT[t]] += v
				elif RESIST_EFFECT.has(t):
					var k2: String = RESIST_EFFECT[t]
					s["resist"][k2] = int(s["resist"].get(k2, 0)) + v
	return s


# 耐久上限【自訂】= base + perLv × 裝備等級
static func max_dur(req_lv: int, cfg: Dictionary) -> int:
	return int(cfg.get("base", 50)) + int(cfg.get("perLv", 5)) * maxi(0, req_lv)


# 加總身上防具。worn = [{stats, dur}]；耐久 0 = 效果減半 (向下取整，唔消失)【自訂】
static func sum_worn(worn: Array) -> Dictionary:
	var out := armor_stats([])
	for w in worn:
		var s: Dictionary = w["stats"]
		var half := int(w["dur"]) <= 0
		for k in s:
			if k == "resist":
				for r in s["resist"]:
					var rv := int(s["resist"][r])
					out["resist"][r] = int(out["resist"].get(r, 0)) + (rv / 2 if half else rv)
			else:
				out[k] = int(out[k]) + (int(s[k]) / 2 if half else int(s[k]))
	return out


# 迴避率 (0~1): 防具 % + 其他來源 (寶石 evadePct 已係小數)，夾上限
static func evade_chance(armor_pct: int, extra: float, cap_pct: int) -> float:
	return clampf(armor_pct / 100.0 + extra, 0.0, cap_pct / 100.0)


# 受擊減少 %【自訂】: 傷害 × (1 - pct/100)，最少 1；pct 夾上限
static func reduce_dmg(dmg: int, pct: int, cap_pct: int) -> int:
	if dmg <= 0:
		return dmg
	return maxi(1, MathX.js_round(dmg * (1.0 - clampi(pct, 0, cap_pct) / 100.0)))


# 受擊磨損【自訂】: 每受 hitsPerWear 下 (有傷害) 身上每件 -1。hits = 累計受擊數 (已加今次)
static func hit_wears(hits: int, every: int) -> bool:
	return every > 0 and hits > 0 and hits % every == 0


# 死亡耐久損失【原+自訂】(spec 03 §4.3): 每件扣上限 × pct (向上取整)，最少 0
static func dur_after_death(cur: int, max_d: int, pct: float) -> int:
	return maxi(0, cur - int(ceil(max_d * pct)))
