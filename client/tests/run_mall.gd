extends SceneTree
# 貨金商城 + 商城道具單機化 (S11a/S11b, spec 11 §11): 精選 cat 250 道具以金買 + 各道具功能。
# 跑: Godot --headless --path client --script tests/run_mall.gd

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_mall_view_buy(data)
	t_action_pill(data)
	t_lilian_elixir(data)
	t_skill_elixir(data)
	t_promote_token(data)
	t_class_pill(data)
	print("[TEST] mall: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


func _put(sim: Sim, id: int, x: int, y: int) -> void:
	var e := sim.ent(id)
	if e.is_empty():
		return
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y
	e.erase("path")


func _bag_n(ch: Dictionary, id: int) -> int:
	for b in ch.get("bag", []) as Array:
		if int(b["id"]) == id:
			return int(b["n"])
	return 0


func t_mall_view_buy(data: GameData) -> void:
	var sim := Sim.new(data, 11)
	var id := sim.spawn_player("m")
	sim.player_ch()["gold"] = 100000
	sim.cmd_use_item(id, 30012)          # 歷練神丹（試用一件）
	var v: Dictionary = sim.mall_view(id)
	check(v.has("stock") and (v["stock"] as Array).size() > 0, "mall_view 有貨單")
	check(int(v.get("gold", 0)) > 0, "mall_view 顯示金錢")
	var before := int(sim.player_ch()["gold"])
	sim.cmd_mall_buy(id, 65003, 1)            # 行動丸
	var after := int(sim.player_ch()["gold"])
	check(after < before, "買行動丸扣金")
	check(_bag_n(sim.player_ch(), 65003) >= 1, "買咗行動丸入背包")
	sim.cmd_mall_buy(id, 999, 1)              # 唔喺貨單
	var gold_after_bad := int(sim.player_ch()["gold"])
	check(gold_after_bad == after, "唔喺貨單唔會扣錢")


func t_action_pill(data: GameData) -> void:
	var sim := Sim.new(data, 12)
	var id := sim.spawn_player("a")
	var ch := sim.player_ch()
	sim.cmd_debug_give(id, 65003, 1)
	ch["ap"] = 0
	sim.cmd_use_item(id, 65003)
	check(int(ch["ap"]) >= sim.ap_max(ch), "行動丸回滿行動力")
	check(_bag_n(ch, 65003) == 0, "行動丸消耗咗")


func t_lilian_elixir(data: GameData) -> void:
	var sim := Sim.new(data, 13)
	var id := sim.spawn_player("l")
	var ch := sim.player_ch()
	var exp0 := int(ch["exp"])
	sim.cmd_debug_give(id, 30012, 1)
	sim.cmd_use_item(id, 30012)
	check(int(ch["exp"]) > exp0 or int(ch["level"]) > 1, "歷練神丹 加 EXP")
	check(_bag_n(ch, 30012) == 0, "歷練神丹消耗")


func t_skill_elixir(data: GameData) -> void:
	var sim := Sim.new(data, 14)
	var id := sim.spawn_player("s")
	var ch := sim.player_ch()
	ch["expert"] = {"tianwen": 0, "dili": 0}
	sim.cmd_debug_give(id, 30013, 1)
	sim.cmd_use_item(id, 30013)
	check(int(ch["expert"].get("tianwen", 0)) > 0, "技能神丹加咗專長 exp")
	check(_bag_n(ch, 30013) == 0, "技能神丹消耗")


func t_promote_token(data: GameData) -> void:
	var sim := Sim.new(data, 15)
	var id := sim.spawn_player("p")
	var ch := sim.player_ch()
	var cur := int(ch.get("titleRank", 0))
	sim.cmd_debug_give(id, 30016, 1)
	sim.cmd_use_item(id, 30016)
	check(int(ch["titleRank"]) == cur + 1, "升官令牌頭銜 +1 (%d→%d)" % [cur, int(ch["titleRank"])])
	check(_bag_n(ch, 30016) == 0, "升官令牌消耗")


func t_class_pill(data: GameData) -> void:
	var sim := Sim.new(data, 16)
	var id := sim.spawn_player("c")
	var ch := sim.player_ch()
	ch["classId"] = "yishi"                  # 義士：食唔到仕女丹（開鎖）
	ch["classSkill"] = "unlock"               # 就當學過
	sim.cmd_debug_give(id, 30055, 1)          # 開鎖丹
	sim.cmd_use_item(id, 30055)
	check(_bag_n(ch, 30055) == 1, "非對應職業食職業丹唔會消耗 (義士唔食仕女丹)")
	# 冇對應職業嘅丹（武匠都唔係 5 職）
	sim.cmd_debug_give(id, 30056, 1)
	sim.cmd_use_item(id, 30056)
	check(_bag_n(ch, 30056) == 1, "非竊聽職 (辯士) 唔消耗竊聽丹")