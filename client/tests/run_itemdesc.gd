extends SceneTree
# 物品說明生成: 全部物品唔 crash；寶石/特殊道具/座騎飼料/武將寶物 有說明
var fails := 0


func check(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("[FAIL] ", m)


func _init() -> void:
	var d := GameData.load_all()
	var n_jewel_empty := 0
	var n_all := 0
	for id in d.names.keys():
		var ls := RulesItemDesc.lines(int(id), d)
		n_all += 1
		if d.jewel_by_item.has(int(id)) and ls.is_empty():
			n_jewel_empty += 1
	check(n_all > 5000, "掃晒全部物品 (%d)" % n_all)
	check(n_jewel_empty == 0, "每粒寶石都有說明 (空 %d)" % n_jewel_empty)
	var t := func(id: int) -> String: return " | ".join(RulesItemDesc.lines(id, d))
	check(str(t.call(32001)).contains("風系術法傷害 +10%"), "屬性石: " + str(t.call(32001)))
	check(str(t.call(32301)).contains("解鎖"), "元素術石: " + str(t.call(32301)))
	check(str(t.call(32041)).contains("MP 耗損 -10%"), "輔助石 63: " + str(t.call(32041)))
	check(str(t.call(32050)).contains("SP 耗損 -10%"), "輔助石 65: " + str(t.call(32050)))
	check(str(t.call(32056)).contains("吸血"), "輔助石 64: " + str(t.call(32056)))
	check(str(t.call(25075)).contains("融合") and str(t.call(25075)).contains("武器強度 +25"), "融合材料: " + str(t.call(25075)))
	check(str(t.call(65002)).contains("+100"), "百寶袋")
	check(str(t.call(30055)).contains("開鎖"), "開鎖丹")
	check(str(t.call(54807)).contains("武將寶物"), "武將寶物: " + str(t.call(54807)))
	check(str(t.call(31001)).contains("座騎道具"), "座騎飼料: " + str(t.call(31001)))
	check(not str(t.call(28004)).contains("未實裝"), "解咒粉已實裝: " + str(t.call(28004)))
	check(str(t.call(10001)).contains("武器強度"), "武器照舊顯示強度/命中")
	for id in [32001, 32301, 32041, 25075, 54807, 31001, 28004, 10001, 65338, 28061]:
		print("  ", id, d.names.get(id, "?"), " → ", t.call(id))
	print("[TEST] itemdesc: fails ", fails)
	quit()
