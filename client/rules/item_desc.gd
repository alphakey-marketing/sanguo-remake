class_name RulesItemDesc
extends RefCounted
# 物品說明生成 (純函數)：items.json 冇文字描述，全靠呢度按「實際邏輯」寫返人話
# 規則：講到嘅效果一定同 code 一致；單機版冇接嘅效果標「未實裝」，唔好講到好似有咁

# 用 id 判斷嘅特殊道具 (sim_econ cmd_use_item / sim_skill / combat 死亡道具 / 武將補品)
const SPECIAL := {
	65001: "使用：顯示最近城池方位（消耗 1）",
	65002: "使用：背包負重上限永久 +100（消耗 1）",
	65024: "使用：背包負重上限永久 +200（消耗 1）",
	65005: "使用：限時打工經驗 +50%（消耗 1）",
	65020: "使用：傳送去戰役入口（消耗 1）",
	65040: "使用：即時傳送返最近城池（消耗 1）",
	65003: "使用：行動力回滿（消耗 1）",
	30016: "使用：頭銜升 1 階，封頂最高頭銜（消耗 1）",
	30012: "使用：直接加經驗，約當級升級所需 10%（最少 10）",
	30013: "使用：所有已學專長經驗 +50",
	30014: "使用：出戰中戰騎經驗 +200（冇出戰戰騎就浪費）",
	30055: "使用：施展「開鎖」職業特技（要仕女職業）",
	30056: "使用：施展「竊聽」職業特技（要辯士職業）",
	30057: "使用：施展「潛行」職業特技（要巫女職業）",
	30058: "使用：施展「超渡」職業特技（要道士職業）",
	30059: "使用：施展「透視」職業特技（要美女職業）",
	65016: "持有：死亡唔會掉物品（死亡時自動消耗 1）",
	65029: "持有：死亡經驗損失減半（死亡時自動消耗 1）",
	65030: "持有：死亡即喺客棧復活，物品同經驗照掉；天譴無效（消耗 1）",
	65338: "使用：倒地期間就地復活，回滿血（消耗 1）",
	30015: "武將補品：餵武將回復 30% HP、50% SP",
}

const ELEM := {"wind": "風", "earth": "地", "water": "水", "fire": "火", "life": "生", "none": "無屬性"}

# 輔助石 / 融合材料 effect type → [名, 單位, 正負]；單位 "%" = 百分比、"" = 點數；sign -1 = 減免
const SUPPORT := {
	15: ["HP 上限", "%"], 17: ["MP 上限", "%"], 20: ["SP 上限", ""],
	7: ["物理攻擊", "%"], 8: ["術法攻擊", "%"], 52: ["物理受擊", "%", -1], 53: ["術法受擊", "%", -1],
	9: ["物理防禦", ""], 11: ["術法防禦", ""], 10: ["物理迴避", "%"], 12: ["術法迴避", "%"],
	13: ["武器命中", "%"], 21: ["術法命中", "%"],
	1: ["武力", ""], 2: ["敏捷", ""], 4: ["靈力", ""], 5: ["智力", ""],
	63: ["MP 耗損", "%", -1], 65: ["SP 耗損", "%", -1], 64: ["普攻吸血", "%"],
	34: ["迴避中邪", "%"], 35: ["迴避封咒", "%"], 36: ["迴避媚惑", "%"], 37: ["迴避蠱毒", "%"], 38: ["迴避遲緩", "%"],
}

# 單機版真係有接嘅 effect type (其餘有 label 嘅照原標籤，無 label 嘅標未實裝)
const IMPL_TYPES := [0, 1, 22, 18, 59, 60, 61, 62, 68, 69, 70, 71, 72, 76, 28, 29, 30, 31, 32, 33, 2, 4, 5, 9, 10, 11, 12, 13, 14, 16, 19, 34, 35, 36, 37, 38, 39, 52, 53, 73, 74, 75, 99]
const UNIMPL_LABELLED := [2, 3]     # 技能/戰騎經驗倍率丹 (限時版) 未接     # 「解除…」類單機版食藥唔會解狀態


static func _fmt(name: String, unit: String, v: int, sign: int = 1) -> String:
	return "%s %s%d%s" % [name, "+" if sign > 0 else "-", absi(v), unit]


# 回傳說明行 (唔包類別/等級/回復/術法行，嗰幾行喺 game_panel.item_desc)
static func lines(id: int, data: GameData) -> Array:
	if SPECIAL.has(id):
		return [SPECIAL[id]]
	var inf: Dictionary = data.info.get(id, {})
	var effs: Array = inf.get("effects", [])
	var jd: Dictionary = data.jewel_by_item.get(id, {})
	if not jd.is_empty():
		return _jewel_lines(jd)
	var cat := int(data.cats.get(id, 0))
	if cat == int(data.gen2_cfg.get("treasureCat", -1)):
		var t := RulesGeneral.treasure_of(cat, effs, data.gen2_cfg)
		if not t.is_empty():
			var tn := str(data.gen2_cfg["treasure"][str(t["type"])].get("name", "?"))
			return ["武將寶物：交畀武將帶 (最多 2 格)，加「%s」%d" % [tn, int(t["value"])]]
	var mount := _mount_lines(effs, data)
	if not mount.is_empty():
		return mount
	return _generic_lines(effs)


static func _jewel_lines(jd: Dictionary) -> Array:
	var kind := str(jd.get("kind", ""))
	var effs: Array = jd.get("effects", [])
	var out: Array = []
	match kind:
		"stone":
			var el := ELEM.get(str(jd.get("elem", "")), "?") as String
			var pct := int(jd.get("pct", 0))
			out.append("屬性石：裝上寶石欄，%s系術法傷害 +%d%%；剋制嗰個屬性時更痛" % [el, pct])
		"special":
			var el2 := ELEM.get(str(jd.get("elem", "")), "?") as String
			out.append("元素術石：裝上寶石欄，解鎖「%s」術大範圍施放" % el2)
		"support":
			var parts: Array = []
			for e in effs:
				var t: Array = SUPPORT.get(int(e["type"]), [])
				if t.is_empty():
					continue
				parts.append(_fmt(str(t[0]), str(t[1]), int(e["value"]), int(t[2]) if t.size() > 2 else 1))
			out.append("輔助石：裝上寶石欄即生效：" + "、".join(parts) if not parts.is_empty() else "輔助石：（效果未實裝）")
		_:
			var fp: Array = []
			for e in effs:
				var t2: Array = SUPPORT.get(int(e["type"]), [])
				if not t2.is_empty():
					fp.append(_fmt(str(t2[0]), str(t2[1]), int(e["value"]), int(t2[2]) if t2.size() > 2 else 1))
				elif int(e["type"]) == 99:
					fp.append("武器強度 +%d" % int(e["value"]))
			out.append("融合材料：義士融合鑲落武器" + ("，附加：" + "、".join(fp) if not fp.is_empty() else ""))
	return out


# 座騎飼料 / 藥 (mounts.json effectKeys)：有任何一個 key 命中就當座騎道具
static func _mount_lines(effs: Array, data: GameData) -> Array:
	var cfg: Dictionary = data.mounts
	var keys: Dictionary = cfg.get("effectKeys", {})
	var an: Dictionary = cfg.get("attrNames", {})
	var parts: Array = []
	for e in effs:
		var k := str(keys.get(str(int(e["type"])), ""))
		if k == "":
			continue
		var v := RulesMount.eff_value(int(e["value"]))
		if k.begins_with("cure:"):
			parts.append("治%s" % str(cfg["statuses"][k.substr(5)]["name"]))
		elif k == "satiety":
			parts.append("飽食度 %+d" % v)
		elif k == "life":
			parts.append("生命力 %+d" % v)
		elif k == "fatigue":
			parts.append("疲勞 %+d" % v)
		elif k == "mood":
			parts.append("心情 %+d" % v)
		else:
			parts.append("%s %+d" % [str(an.get(k, k)), v])
	if parts.is_empty():
		return []
	return ["座騎道具：馬廄餵飼用 —— " + "、".join(parts)]


static func _generic_lines(effs: Array) -> Array:
	var out: Array = []
	var unimpl := false
	var pill := RulesPill.pill_effect({"effects": effs})
	if not pill.is_empty():
		out.append("限時丹：持續 %d 分鐘（1 分鐘 = 現實 60 秒）" % int(pill["minutes"]))
	for e in effs:
		var t := int(e["type"])
		var lab := str(e["label"])
		if t in [14, 16]:
			continue                         # 回復行由 game_panel 顯示
		var val := int(e["value"])
		if t == 18 and not pill.is_empty():
			continue
		if t in [18, 59, 60, 61, 62, 68, 69, 70, 71, 72, 76] and lab == "":
			out.append(_custom_line(t, val))
			continue
		if t in [56, 57, 58]:
			out.append("煉化素材（單機版暫無用途）")
			continue
		if t in UNIMPL_LABELLED:
			out.append("%s（單機版未實裝）" % lab)
		elif lab == "":
			if not (t in IMPL_TYPES):
				unimpl = true
		else:
			out.append(lab if val == 0 else "%s %d" % [lab, val])
	if unimpl:
		out.append("（原版特殊效果，單機版未實裝）")
	return out


static func _custom_line(t: int, v: int) -> String:
	match t:
		18: return "飲用：飲水度 +%d" % v
		59: return "點燈：夜間照明 %d 分鐘" % v
		60: return "物防 +20%（限時 30 分鐘）"
		61: return "術防 +20%（限時 30 分鐘）"
		62: return "物攻 +20%（限時 30 分鐘）"
		68: return "物防 +40%（限時 30 分鐘）"
		69: return "術防 +40%（限時 30 分鐘）"
		70: return "物攻 +40%（限時 30 分鐘）"
		71: return "移動速度 +50%（限時 30 分鐘）"
		76: return "移動速度 +%d%%（限時 30 分鐘）" % (25 * clampi(v, 1, 3))
		72: return "著住：行動力上限 +%d" % v
	return ""
