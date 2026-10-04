class_name RulesPill
# 限時 buff 丹 (items.json effect type 0 = 持續分鐘)【自訂】: 1 分鐘 = 600 tick (10 tick/秒)
# ch.pills = {型號key: {"until": tick, "v": 數值}}；同型號重食 = 覆蓋 (取較大者續時)
const TICKS_PER_MIN := 600
# effect type → 加成 (套用喺寶石輔助石欄位，見 jewel.gd support_bonus)
const BONUS_TYPES := {6: [7], 7: [8], 8: [52], 9: [53], 10: [9], 11: [11], 13: [10]}
const EXP_TYPES := [1, 4, 22]          # 擊殺經驗倍率 (技能/戰騎經驗倍率 2/3 未接)
const REGEN_TYPE := 12                  # 回復丹: 安全區自動回復 +%
const HP_FLAT_TYPE := 5                 # 元氣丹: HP 上限 +點
const BUFF_TYPES := [5, 6, 7, 8, 9, 10, 11, 12, 13, 15, 16, 17, 18, 1, 4, 22]


static func pill_effect(info: Dictionary) -> Dictionary:
	# 回傳 {"minutes":, "effects":[{type,value}]}；唔係限時丹 = {}
	var mins := 0
	var effs: Array = []
	for ef in info.get("effects", []):
		var t := int(ef.get("type", -1))
		if t == 0:
			mins = int(ef.get("value", 0))
		elif t in BUFF_TYPES:
			effs.append({"type": t, "value": int(ef.get("value", 0))})
	if mins <= 0 or effs.is_empty():
		return {}
	return {"minutes": mins, "effects": effs}


# 加持丹 15~18 展開成基本效果
static func expand(effs: Array) -> Array:
	var out: Array = []
	for ef in effs:
		var t := int(ef["type"])
		var v := int(ef["value"])
		match t:
			15: out.append_array([{"type": 6, "value": 10}, {"type": 7, "value": 10}])
			16: out.append_array([{"type": 8, "value": 10}, {"type": 9, "value": 10}])
			17: out.append_array([{"type": 10, "value": 1}, {"type": 11, "value": 1}])
			18: out.append_array([{"type": 5, "value": 1000}, {"type": 12, "value": 10}])
			_: out.append({"type": t, "value": v})
	return out


static func active(ch: Dictionary, tick: int) -> Dictionary:
	var out := {}
	var pills: Dictionary = ch.get("pills", {})
	for k in pills.keys():
		var p: Dictionary = pills[k]
		if int(p.get("until", 0)) > tick:
			out[k] = p
	return out


# 食丹: 每個 effect type 一格
static func apply(ch: Dictionary, effs: Array, minutes: int, tick: int) -> void:
	var pills: Dictionary = ch.get("pills", {})
	for ef in expand(effs):
		pills[str(int(ef["type"]))] = {"until": tick + minutes * TICKS_PER_MIN, "v": int(ef["value"])}
	ch["pills"] = pills


# 當前有效丹 → 輔助石格式 bonus (+ hpFlat)
static func bonus(ch: Dictionary, tick: int) -> Dictionary:
	var effects: Array = []
	var hp_flat := 0
	for k in active(ch, tick).keys():
		var t := int(k)
		var v := int((ch["pills"][k] as Dictionary).get("v", 0))
		if BONUS_TYPES.has(t):
			for jt in BONUS_TYPES[t]:
				effects.append({"type": jt, "value": v})
		elif t == HP_FLAT_TYPE:
			hp_flat += v
	var b := RulesJewel.support_bonus(effects)
	b["hpFlat"] = hp_flat
	return b


static func exp_mult(ch: Dictionary, tick: int) -> float:
	var m := 1.0
	for k in active(ch, tick).keys():
		if int(k) in EXP_TYPES:
			m = maxf(m, float((ch["pills"][k] as Dictionary).get("v", 1)))
	return m


static func regen_mult(ch: Dictionary, tick: int) -> float:
	var p: Dictionary = active(ch, tick).get(str(REGEN_TYPE), {})
	return 1.0 + float(int(p.get("v", 0))) / 100.0
