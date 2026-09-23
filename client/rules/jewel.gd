class_name RulesJewel
extends RefCounted
# 寶石系統純函數 (Step 10, spec 02 §4)。data/jewels.json 由 items.json 生成 (tools/gen_jewels.py)。
# - 屬性石: element_mult() 相剋加成表【自訂】: pct 縮放倍率 (100% = 原版 1.5 / (1/1.5))
# - 特殊石: 元素術大範圍施放 (sim 攔: 施法要裝備對應特殊石)
# - 輔助石: support_bonus() 著裝即生效 (HP/MP/SP 上限、攻防%、命中%、耗損減免)
# - 融合: 義士特技 (spec 02 §6): QTE 集氣棒，fusion_hit() 判定

const ELEM_BY_EFFECT := {41: "wind", 42: "earth", 43: "water", 44: "fire"}
const SPECIAL_BY_EFFECT := {46: "wind", 47: "earth", 48: "water", 49: "fire", 50: "none", 51: "life"}
const FUSION_SECONDS := 3.0          # 集氣棒行 3 秒到 100% 【自訂】
const FUSION_TARGET := 0.5           # 目標位: 50%
const FUSION_WINDOW := 0.2           # 成功範圍: ±20%

# 相剋加成表【原】地剋水、水剋火、火剋風、風剋地【自訂】: 加成按石 pct 縮放。
# pct = 0.1..1.0 (10%~100%)。pct=1 → 1.5 / (1/1.5) = RulesSpell.element_factor 全倍率
static func element_mult(att_elem: String, pct: float, def_elem: String) -> float:
	var boost := (RulesSpell.COUNTER_X - 1.0) * clampf(pct, 0.0, 1.0)
	if String(RulesSpell.BEATS.get(att_elem, "")) == def_elem:
		return 1.0 + boost
	if String(RulesSpell.BEATS.get(def_elem, "")) == att_elem:
		return 1.0 / (1.0 + boost)
	return 1.0


# 術法寶石加成 (spec 02 §3.2: ×(1+寶石加成)): 裝備屬性石 element 同術法 element 一模先有 (自訂),
# 石 pct 直接係加成 (50% 石 = ×1.5)
static func spell_jewel_bonus(stone_elem: String, spell_elem: String, pct: float) -> float:
	if stone_elem == "" or stone_elem != spell_elem:
		return 1.0
	return 1.0 + clampf(pct, 0.0, 1.0)


# ================= 輔助石 (著裝即生效, spec 02 §4) =================
# items.json effects 類型 → bonus 欄位。回傳 dict，全部有預設 (冇嘅效果 = 0/1.0)
static func support_bonus(effects: Array) -> Dictionary:
	var b := {"hpPct": 0.0, "mpPct": 0.0, "spFlat": 0, "atkPct": 0.0, "spellAtkPct": 0.0,
		"defPct": 0.0, "spellDefPct": 0.0, "defFlat": 0, "spellDefFlat": 0,
		"evadePct": 0.0, "spellEvadePct": 0.0, "hitPct": 0.0, "spellHitPct": 0.0,
		"strFlat": 0, "agiFlat": 0, "spiFlat": 0, "intFlat": 0,
		"mpCostMul": 1.0, "spCostMul": 1.0}
	for e in effects:
		var t := int(e["type"])
		var v := int(e.get("value", 0))
		var p := float(v) / 100.0
		match t:
			15: b["hpPct"] = float(b["hpPct"]) + p       # HP 上限 %
			17: b["mpPct"] = float(b["mpPct"]) + p       # MP 上限 %
			20: b["spFlat"] = int(b["spFlat"]) + v       # SP 上限點
			7: b["atkPct"] = float(b["atkPct"]) + p      # 物理攻擊 %
			8: b["spellAtkPct"] = float(b["spellAtkPct"]) + p  # 術法攻擊 %
			52: b["defPct"] = float(b["defPct"]) + p     # 物理防禦 %
			53: b["spellDefPct"] = float(b["spellDefPct"]) + p  # 術法防禦 %
			9: b["defFlat"] = int(b["defFlat"]) + v      # 物理防禦力
			11: b["spellDefFlat"] = int(b["spellDefFlat"]) + v  # 術法防禦力
			10: b["evadePct"] = float(b["evadePct"]) + p # 物理迴避 %
			12: b["spellEvadePct"] = float(b["spellEvadePct"]) + p
			13: b["hitPct"] = float(b["hitPct"]) + p     # 武器命中率 %
			21: b["spellHitPct"] = float(b["spellHitPct"]) + p
			1: b["strFlat"] = int(b["strFlat"]) + v
			2: b["agiFlat"] = int(b["agiFlat"]) + v
			4: b["spiFlat"] = int(b["spiFlat"]) + v
			5: b["intFlat"] = int(b["intFlat"]) + v
			63: b["mpCostMul"] = float(b["mpCostMul"]) * (1.0 - p)  # MP 耗損 -%
			65: b["spCostMul"] = float(b["spCostMul"]) * (1.0 - p)  # SP 耗損 -%
	return b


# 合併一粒寶石嘅 bonus (jewels.json 內記錄，參考 items effects)
static func jewel_bonus(jewel: Dictionary) -> Dictionary:
	return support_bonus(jewel.get("effects", []))


# 加總多粒 (裝備 2 格): hpPct 等相加；耗損乘算用 (1 - 每粒減免) 累乘
static func sum_bonus(bonus_list: Array) -> Dictionary:
	var out := {"hpPct": 0.0, "mpPct": 0.0, "spFlat": 0, "atkPct": 0.0, "spellAtkPct": 0.0,
		"defPct": 0.0, "spellDefPct": 0.0, "defFlat": 0, "spellDefFlat": 0,
		"evadePct": 0.0, "spellEvadePct": 0.0, "hitPct": 0.0, "spellHitPct": 0.0,
		"strFlat": 0, "agiFlat": 0, "spiFlat": 0, "intFlat": 0,
		"mpCostMul": 1.0, "spCostMul": 1.0}
	for b in bonus_list:
		out["hpPct"] = float(out["hpPct"]) + float(b.get("hpPct", 0.0))
		out["mpPct"] = float(out["mpPct"]) + float(b.get("mpPct", 0.0))
		out["spFlat"] = int(out["spFlat"]) + int(b.get("spFlat", 0))
		out["atkPct"] = float(out["atkPct"]) + float(b.get("atkPct", 0.0))
		out["spellAtkPct"] = float(out["spellAtkPct"]) + float(b.get("spellAtkPct", 0.0))
		out["defPct"] = float(out["defPct"]) + float(b.get("defPct", 0.0))
		out["spellDefPct"] = float(out["spellDefPct"]) + float(b.get("spellDefPct", 0.0))
		out["defFlat"] = int(out["defFlat"]) + int(b.get("defFlat", 0))
		out["spellDefFlat"] = int(out["spellDefFlat"]) + int(b.get("spellDefFlat", 0))
		out["evadePct"] = float(out["evadePct"]) + float(b.get("evadePct", 0.0))
		out["spellEvadePct"] = float(out["spellEvadePct"]) + float(b.get("spellEvadePct", 0.0))
		out["hitPct"] = float(out["hitPct"]) + float(b.get("hitPct", 0.0))
		out["spellHitPct"] = float(out["spellHitPct"]) + float(b.get("spellHitPct", 0.0))
		out["strFlat"] = int(out["strFlat"]) + int(b.get("strFlat", 0))
		out["agiFlat"] = int(out["agiFlat"]) + int(b.get("agiFlat", 0))
		out["spiFlat"] = int(out["spiFlat"]) + int(b.get("spiFlat", 0))
		out["intFlat"] = int(out["intFlat"]) + int(b.get("intFlat", 0))
		out["mpCostMul"] = float(out["mpCostMul"]) * float(b.get("mpCostMul", 1.0))
		out["spCostMul"] = float(out["spCostMul"]) * float(b.get("spCostMul", 1.0))
	return out


# ================= 融合 (義士特技, spec 02 §6) =================
# QTE 簡化【自訂】: 集氣棒 3 秒由 0 → 100%，玩家喺 50%±20% 時撳實 = 成功。
# 一 pass (唔會回落)；過咗位拎到 100% 就走咗 (fail)。全部 deterministic (由 tick 計)
static func fusion_pos(elapsed_ticks: int, hz: int = 10) -> float:
	return minf(1.0, float(elapsed_ticks) / (FUSION_SECONDS * float(hz)))


static func fusion_hit(elapsed_ticks: int, hz: int = 10) -> bool:
	var p := fusion_pos(elapsed_ticks, hz)
	return p > 0.0 and p < 1.0 and absf(p - FUSION_TARGET) <= FUSION_WINDOW