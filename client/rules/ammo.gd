class_name RulesAmmo
extends RefCounted
# 弩箭消耗 (S02c-辯士, spec 02 §6【原】) + 箭種威力 (Spec 11 S11c【自訂】):
#   - 辯士用弩射箭，箭 = items.json cat「箭矢」(49) 類。
#   - 弩攻擊每發扣 1 箭（命中先扣；miss 唔燒箭）；冇箭 → 弩出手唔到。
#   - S11c: 箭分「名箭」(12101~12120) 同「等箭」(12201~12220) 兩系，各按等級有
#     唔同「威力(武器強度加成)」同「特效(傷害加成%)」。玩家用身上最高等嘅箭 (best_arrow)。
# 純函數，無狀態；箭矢偵測靠 data.cats (item id -> cat)。

const NU_WEAPON_CAT := 9              # 弩武器 (辯士主力遠距兵器，items.json cat 9)
const ARROW_CAT := 49                # items.json「箭矢」類

# 箭矢等級表【自訂】(S11c): id -> {lv, power(武器強度加成), atk_pct(傷害加成%)}
# power 大致跟 items.json price 由低到高；atk_pct 反映「特效名」(穿心/斷魂/奔雷…)。
# cat 49 全部箭 (56402 火紅布料 / 62150 雪精靈魄 唔係箭，唔入表)。
const ARROWS := {
	# 名箭系 (121xx)
	12101: {"lv": 1,  "power": 2,   "atk_pct": 0.0},   # 羽箭
	12102: {"lv": 1,  "power": 4,   "atk_pct": 0.0},   # 鐵箭
	12103: {"lv": 1,  "power": 6,   "atk_pct": 0.0},   # 鋼箭
	12104: {"lv": 1,  "power": 9,   "atk_pct": 1.0},   # 獸骨箭
	12105: {"lv": 1,  "power": 12,  "atk_pct": 3.0},   # 穿心箭
	12106: {"lv": 1,  "power": 15,  "atk_pct": 4.0},   # 奪命箭
	12107: {"lv": 1,  "power": 19,  "atk_pct": 5.0},   # 烈風箭
	12108: {"lv": 1,  "power": 23,  "atk_pct": 6.0},   # 赤殺箭
	12109: {"lv": 1,  "power": 28,  "atk_pct": 7.0},   # 斷魂箭
	12110: {"lv": 1,  "power": 31,  "atk_pct": 8.0},   # 獵殺箭
	12111: {"lv": 1,  "power": 35,  "atk_pct": 9.0},   # 奪魂箭
	12112: {"lv": 1,  "power": 40,  "atk_pct": 10.0},  # 破滅箭
	12115: {"lv": 2,  "power": 46,  "atk_pct": 12.0},  # 暗影箭
	12117: {"lv": 2,  "power": 52,  "atk_pct": 15.0},  # 閃光箭
	12119: {"lv": 2,  "power": 60,  "atk_pct": 18.0},  # 流星箭
	12120: {"lv": 3,  "power": 66,  "atk_pct": 20.0},  # 落影箭
	# 等箭系 (122xx)
	12201: {"lv": 1,  "power": 3,   "atk_pct": 0.0},   # 木箭
	12202: {"lv": 1,  "power": 5,   "atk_pct": 0.0},   # 十等箭
	12203: {"lv": 1,  "power": 8,   "atk_pct": 1.0},   # 飛翔箭
	12204: {"lv": 1,  "power": 10,  "atk_pct": 1.0},   # 九等箭
	12205: {"lv": 1,  "power": 13,  "atk_pct": 2.0},   # 寂音箭
	12206: {"lv": 1,  "power": 16,  "atk_pct": 2.0},   # 八等箭
	12207: {"lv": 1,  "power": 20,  "atk_pct": 3.0},   # 無名箭
	12208: {"lv": 1,  "power": 24,  "atk_pct": 3.0},   # 七等箭
	12209: {"lv": 1,  "power": 29,  "atk_pct": 4.0},   # 透骨箭
	12210: {"lv": 1,  "power": 33,  "atk_pct": 4.0},   # 六等箭
	12211: {"lv": 1,  "power": 38,  "atk_pct": 5.0},   # 穿揚箭
	12212: {"lv": 1,  "power": 41,  "atk_pct": 5.0},   # 五等箭
	12213: {"lv": 1,  "power": 45,  "atk_pct": 6.0},   # 翻雲箭
	12214: {"lv": 1,  "power": 48,  "atk_pct": 6.0},   # 四等箭
	12215: {"lv": 1,  "power": 54,  "atk_pct": 7.0},   # 破空箭
	12216: {"lv": 1,  "power": 58,  "atk_pct": 7.0},   # 三等箭
	12217: {"lv": 2,  "power": 64,  "atk_pct": 9.0},   # 疾電箭
	12218: {"lv": 2,  "power": 68,  "atk_pct": 9.0},   # 二等箭
	12219: {"lv": 2,  "power": 74,  "atk_pct": 11.0},  # 奔雷箭
	12220: {"lv": 3,  "power": 82,  "atk_pct": 14.0},  # 一等箭
}


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


# 扣 n 支箭（逐堆扣，跨多種箭）。唔足 n 支 → 唔扣 (保持不變)，返 false。
static func consume_arrow(data: GameData, ch: Dictionary, n: int = 1) -> bool:
	var need := n
	for b in ch.get("bag", []) as Array:
		if int(data.cats.get(int(b["id"]), 0)) == ARROW_CAT and int(b["n"]) > 0:
			var take := mini(need, int(b["n"]))
			b["n"] = int(b["n"]) - take
			need -= take
			if need <= 0:
				return true
	return need <= 0


# 箭矢定義 (S11c): 唔係箭 (56402/62150) 或 id 唔喺表 → 回 {} (冇威力加成)
static func def_of(id: int) -> Dictionary:
	return (ARROWS as Dictionary).get(int(id), {})


# 身上最高等嘅箭 (S11c): 玩家用身上最勁嗰支箭。冇箭 → 0。
static func best_arrow(data: GameData, ch: Dictionary) -> int:
	var best := 0
	var best_power := -1.0
	for b in ch.get("bag", []) as Array:
		var id := int(b["id"])
		if int(data.cats.get(id, 0)) != ARROW_CAT:
			continue
		var a := def_of(id)
		if a.is_empty():
			continue
		var pw := float(a.get("power", 0.0))
		if pw > best_power or (pw == best_power and id > best):
			best_power = pw
			best = id
	return best


# 弩出手用箭嘅總加成 (S11c): {power: 武器強度加成, atk_pct: 傷害加成%}
# 有弩先叫 (caller 查)；冇箭 → {0, 0}。
static func attack_bonus(data: GameData, ch: Dictionary) -> Dictionary:
	var a := def_of(best_arrow(data, ch))
	if a.is_empty():
		return {"power": 0.0, "atk_pct": 0.0}
	return {"power": float(a.get("power", 0.0)), "atk_pct": float(a.get("atk_pct", 0.0))}