extends SceneTree
# 工作區 (原版許昌道路 xc1922 農漁獵 / xc1923 木礦藥): 區內+有工具先做得
# 跑: Godot --headless --path client --script tests/run_workzone.gd
var fails := 0
var total := 0


func check(c: bool, m: String) -> void:
	total += 1
	if not c:
		fails += 1
		print("[FAIL] " + m)


func _init() -> void:
	var data := GameData.load_all()
	var sim := Sim.new(data, 5)
	var id := sim.spawn_player("t", "yishi")
	var ch: Dictionary = sim.player_ch()
	ch["level"] = 30
	sim._full_heal(ch)
	var e := sim.ent(id)
	var mp: Dictionary = {}
	for md in data.maps:
		if str(md.id) == "xc1922":
			mp = md
	check(not mp.is_empty(), "有 xc1922")
	var x := int(mp.ox) + 100
	var y := int(mp.oy) + 7
	check(sim.work_area_skills(x, y).has("farming"), "xc1922 可農耕")
	check(sim.work_ok_here("fishing", x, y) and sim.work_ok_here("hunting", x, y), "xc1922 可釣魚/狩獵")
	check(not sim.work_ok_here("mining", x, y), "xc1922 唔可採礦")
	check(sim.work_area_skills(int(e.x), int(e.y)).is_empty(), "出生點 (街上) 唔係工作區")
	e["x"] = x
	e["y"] = y
	var got: Array = []
	sim.event_emitted.connect(func(ev): got.append(ev))
	sim.cmd_work(id, "farming")
	check(not got.any(func(ev): return str(ev.get("k", "")) == "work"), "冇工具唔做得")
	var w: Dictionary = data.work["farming"]
	RulesShop.add_item(ch["bag"], int(w["starterTool"]), 1)
	sim.cmd_equip_tool(id, "farming", int(w["starterTool"]))
	sim.cmd_work(id, "farming")
	check(got.any(func(ev): return str(ev.get("k", "")) == "work"), "有工具 + 工作區做得")
	# 新手一次性提示
	var tips: Array = []
	sim.event_emitted.connect(func(ev): if str(ev.get("k", "")) == "tip": tips.append(ev))
	sim.tip_once(id, "hud_auto")
	sim.tip_once(id, "hud_auto")
	check(tips.size() == 1, "提示只彈一次")
	check(bool(ch.get("tipsSeen", {}).get("hud_auto", false)), "提示記喺 tipsSeen")
	ch["attrPoints"] = 3
	sim.tick = 40
	sim._tips_tick()
	check(tips.any(func(ev): return str(ev.key) == "attr"), "有屬性點 → attr 提示")
	check(tips.any(func(ev): return str(ev.key) == "work_zone"), "工作區 → work_zone 提示")
	# 任務追蹤
	check(sim.quest_track_view().is_empty(), "冇進行中任務 = 冇追蹤")
	ch["quests"]["newbie_work"] = {"stage": 0, "flags": {}}
	var tv := sim.quest_track_view()
	check(str(tv.get("name", "")) == "新手工作：第一次採集" and tv.has("tx"), "追蹤: 任務名 + 目標座標")
	print("[TEST] workzone: %d, fail %d" % [total, fails])
	quit()
