class_name RulesSpell
extends RefCounted
# 術法系統純函數 (spec 02 §3/§7)。數值【自訂】；術書等級/職業/大範圍/需寶石表 = data/spells.json
# 由 legacy TS 版 (legacy/server/src/rules/spell.ts) 導出向量對拍


# 【原】地剋水、水剋火、火剋風、風剋地
const BEATS := {"earth": "water", "water": "fire", "fire": "wind", "wind": "earth"}
const COUNTER_X := 1.5            # 克制乘數【自訂】基數


static func element_factor(att: String, def: String) -> float:
	if String(BEATS.get(att, "")) == def:
		return COUNTER_X
	if String(BEATS.get(def, "")) == att:
		return 1.0 / COUNTER_X
	return 1.0


# 術攻 = 術書威力 × (1 + 0.06×對應屬性(智力/靈力))【原 sy2_1_4】
static func spell_attack(power: float, attr: float) -> float:
	return power * (1.0 + 0.06 * attr)


# 術法傷害 = max(1, round(術攻 × rand(0.9~1.1) × (100/(100+術防)) × 相剋 × (1+寶石加成)))
static func calc_spell_damage(power: float, attr: float, spell_def: float, att_elem: String, def_elem: String,
		jewel_pct: float, rng: Callable = Callable()) -> int:
	var atk := spell_attack(power, attr)
	return maxi(1, MathX.js_round(atk * (0.9 + MathX.roll(rng) * 0.2) * (100.0 / (100.0 + spell_def))
		* element_factor(att_elem, def_elem) * (1.0 + jewel_pct)))


# ================= 術法熟練度 (P5, 用家 2026-10-02 approve)【自訂】 =================
# 每本術書記施放次數 ch.spellUse[item]；熟練等級 0~10，每級威力 +3%（上限 +30%），只加傷害術/恢復術威力
const PROF_NEED := [10, 25, 45, 70, 100, 135, 175, 220, 270, 330]   # 累計施放次數 → 升 1~10 級
const PROF_PCT := 0.03


static func prof_level(uses: int) -> int:
	var lv := 0
	for n in PROF_NEED:
		if uses >= int(n):
			lv += 1
	return lv


static func prof_mult(uses: int) -> float:
	return 1.0 + PROF_PCT * float(prof_level(uses))


# ================= 狀態 (spec 02 §7) =================
# 持續(tick): 封咒 600 / 中邪 300 / buff 全部 900
const STATUS_TICKS := {"sealed": 600, "hex": 300, "freeze": 300,
	"armor1": 900, "armor2": 900, "armor3": 900,
	"mirror1": 900, "mirror2": 900, "mirror3": 900,
	"power1": 900, "power2": 900, "power3": 900,
	"insight": 150}

# 美女特技「透視」洞悉狀態：對已透視目標 +20% 攻擊力（RulesToushi 用）【自訂】
const INSIGHT_ATK_MULT := 0.2


static func status_ticks(id: String) -> int:
	return int(STATUS_TICKS.get(id, 0))


# status = {狀態id: until_tick}
static func has(status: Dictionary, id: String, tick: int) -> bool:
	return int(status.get(id, 0)) > tick


static func add_status(status: Dictionary, id: String, ticks: int, tick: int) -> void:
	status[id] = tick + ticks


static func clear_status(status: Dictionary, id: String) -> void:
	status.erase(id)


# 封咒: 唔可以施術法
static func blocks_cast(status: Dictionary, tick: int) -> bool:
	return has(status, "sealed", tick)


# 中邪/冰凍: 定身郁唔到 (S01d 六招特效凍結【自訂】)
static func blocks_move(status: Dictionary, tick: int) -> bool:
	return has(status, "hex", tick) or has(status, "freeze", tick)


# buff 倍率 (無狀態 = 1.0): 聚力/強力/神力 = 物攻 +15%/30%/50%；透視釋領洞悉 = +20%【自訂】
static func atk_mult(status: Dictionary, tick: int) -> float:
	var m := 1.0
	if has(status, "insight", tick):
		m *= 1.0 + INSIGHT_ATK_MULT
	if has(status, "power3", tick):
		m *= 1.5
	elif has(status, "power2", tick):
		m *= 1.3
	elif has(status, "power1", tick):
		m *= 1.15
	return m


# 護甲/金甲/聖鎧 = 物防 +20%/40%/60%
static func def_mult(status: Dictionary, tick: int) -> float:
	if has(status, "armor3", tick):
		return 1.6
	if has(status, "armor2", tick):
		return 1.4
	if has(status, "armor1", tick):
		return 1.2
	return 1.0


# 護鏡/光鏡/仙鏡 = 術防 +20%/40%/60%
static func spell_def_mult(status: Dictionary, tick: int) -> float:
	if has(status, "mirror3", tick):
		return 1.6
	if has(status, "mirror2", tick):
		return 1.4
	if has(status, "mirror1", tick):
		return 1.2
	return 1.0