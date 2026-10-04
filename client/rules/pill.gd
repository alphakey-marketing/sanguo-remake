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


# 無「持續」欄嘅丸/光【自訂】: 丸 30 分鐘；光 = 數值分鐘
# 金剛丸 60 物防+20% / 守護丸 61 術防+20% / 大力丸 62 物攻+20% (精煉 68~70 = +40%)；神速丸 71 = 移速+50%
# 快跑/急速/神速丹 76 值 1/2/3 = 移速 +25/50/75%；光 59 = 夜間照明
const SPEED_TYPE := 100
const LIGHT_TYPE := 101
const PILL_MINUTES := 30


static func fixed_pill(info: Dictionary) -> Dictionary:
	var effs: Array = []
	var mins := PILL_MINUTES
	for ef in info.get("effects", []):
		var t := int(ef.get("type", -1))
		var v := int(ef.get("value", 0))
		match t:
			60: effs.append({"type": 8, "value": 20})
			61: effs.append({"type": 9, "value": 20})
			62: effs.append({"type": 6, "value": 20})
			68: effs.append({"type": 8, "value": 40})
			69: effs.append({"type": 9, "value": 40})
			70: effs.append({"type": 6, "value": 40})
			71: effs.append({"type": SPEED_TYPE, "value": 50})
			76: effs.append({"type": SPEED_TYPE, "value": 25 * clampi(v, 1, 3)})
			59:
				effs.append({"type": LIGHT_TYPE, "value": v})
				mins = maxi(10, v)
	if effs.is_empty():
		return {}
	return {"minutes": mins, "effects": effs}


# 飲水度 (effect 18)
static func thirst_gain(info: Dictionary) -> int:
	var n := 0
	for ef in info.get("effects", []):
		if int(ef.get("type", -1)) == 18:
			n += int(ef.get("value", 0))
	return n


static func speed_mult(ch: Dictionary, tick: int) -> float:
	var p: Dictionary = active(ch, tick).get(str(SPEED_TYPE), {})
	return 1.0 + float(int(p.get("v", 0))) / 100.0


static func light_on(ch: Dictionary, tick: int) -> bool:
	return active(ch, tick).has(str(LIGHT_TYPE))


static func pill_effect(info: Dictionary) -> Dictionary:
	# 回傳 {"minutes":, "effects":[{type,value}]}；唔係限時丹 = {}
	var fx := fixed_pill(info)
	if not fx.is_empty():
		return fx
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


# 背包「使用」掣：限時丹 / 解狀態藥 / 飲品 / 光
static func usable(info: Dictionary) -> bool:
	if not pill_effect(info).is_empty() or thirst_gain(info) > 0:
		return true
	for ef in info.get("effects", []):
		if int(ef.get("type", -1)) in [28, 29, 30, 31, 32, 33]:
			return true
	return false
