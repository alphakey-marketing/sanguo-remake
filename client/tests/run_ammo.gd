extends SceneTree
# 箭種定義/威力測試 (S11c, spec 11 §11「箭矢種類定義」): RulesAmmo
#   - arrow 表覆蓋 items.json cat 49 全部真箭 (排除 56402/62150)
#   - def_of / best_arrow / attack_bonus 行為
# 跑: Godot --headless --path client --script tests/run_ammo.gd

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_table_covers_real_arrows(data)
	t_def_of()
	t_best_arrow(data)
	t_attack_bonus(data)
	t_consume(data)
	print("[TEST] ammo: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


# items.json 全部 cat 49 嘅真箭都喺 RulesAmmo.ARROWS（56402/62150 係材料，唔算弩箭，例外允許）
func t_table_covers_real_arrows(data: GameData) -> void:
	for id in data.item_ids:
		var iid := int(id)
		if int(data.cats.get(iid, -1)) != RulesAmmo.ARROW_CAT:
			continue
		if iid in [56402, 62150]:
			continue
		if RulesAmmo.def_of(iid).is_empty():
			check(false, "箭 %d %s 唔喺 RulesAmmo.ARROWS" % [iid, str(data.names.get(iid, ""))])
		else:
			check(true, "箭 %d 有定義" % iid)


func t_def_of() -> void:
	check(RulesAmmo.def_of(12105).get("atk_pct", 0) > 0, "穿心箭(12105) 有特效傷害加成")
	check(RulesAmmo.def_of(12101).get("power", 0) > 0, "羽箭(12101) 有威力")
	check(float(RulesAmmo.def_of(12220).get("power", 0)) > float(RulesAmmo.def_of(12201).get("power", 0)), "一等箭勁過木箭")
	check(RulesAmmo.def_of(56402).is_empty(), "56402 唔算箭")
	check(RulesAmmo.def_of(99999).is_empty(), "唔存在 id → {}")


func t_best_arrow(data: GameData) -> void:
	var bag: Array = [{"id": 12101, "n": 3}, {"id": 12220, "n": 1}]
	var ch := {"bag": bag}
	check(RulesAmmo.best_arrow(data, ch) == 12220, "身上最高等箭優先 (12220)")
	var ch2 := {"bag": [{"id": 65001, "n": 1}]}
	check(RulesAmmo.best_arrow(data, ch2) == 0, "冇箭 → 0")
	var ch3 := {"bag": [{"id": 56402, "n": 5}]}
	check(RulesAmmo.best_arrow(data, ch3) == 0, "56402 唔算箭")


func t_attack_bonus(data: GameData) -> void:
	var none := RulesAmmo.attack_bonus(data, {"bag": [{"id": 65001, "n": 1}]})
	check(float(none.get("power", -1)) == 0.0 and float(none.get("atk_pct", -1)) == 0.0, "冇箭 → 加成 0")
	var chap := {"bag": [{"id": 12101, "n": 5}]}
	var ap := RulesAmmo.attack_bonus(data, chap)
	check(float(ap.get("power", 0)) > 0, "有箭有威力加成")
	var chh := {"bag": [{"id": 12105, "n": 1}]}
	var ah := RulesAmmo.attack_bonus(data, chh)
	check(float(ah.get("atk_pct", 0)) > 0, "穿心箭有傷害%加成")


func t_consume(data: GameData) -> void:
	var bag: Array = [{"id": 12101, "n": 2}, {"id": 12105, "n": 1}]
	var ch := {"bag": bag}
	check(RulesAmmo.has_arrow(data, ch), "有箭")
	check(RulesAmmo.consume_arrow(data, ch, 1), "扣一支 ok")
	check(RulesAmmo.consume_arrow(data, ch, 2), "再扣兩支 ok (跨堆)" )
	check(not RulesAmmo.has_arrow(data, ch), "扣晒冇箭")
	check(not RulesAmmo.consume_arrow(data, ch, 1), "冇箭扣唔到")