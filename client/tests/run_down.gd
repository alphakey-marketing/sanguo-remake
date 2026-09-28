extends SceneTree
# 倒地/就地復活測試【自訂新增】(玩家死亡由「即死即傳客棧」改做「倒地」狀態):
# 死亡即刻扣經驗/掉物/耐久(不變) → 倒地(原地, hp=0) → 強制 5 秒 → 5~300 秒可回城/復活丹/同伴超渡 → 300 秒逾時強制回城。
# 覆蓋: 「復活丹」item id 存在 + 5 城雜貨店有賣、cmd_revive_pill 就地回滿血、cmd_companion_revive_owner 同伴超渡、逾時兜底、read-model。
# 跑: Godot --headless --path client --script tests/run_down.gd

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_item_and_shops(data)
	t_revive_pill(data)
	t_companion_revive(data)
	t_timeout_bailout(data)
	t_down_view(data)
	print("[TEST] down/onsite-revive: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


func _put(sim: Sim, id: int, x: int, y: int) -> void:
	var e := sim.ent(id)
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y


func _mk(data: GameData, seed: int) -> Array:
	var sim := Sim.new(data, seed)
	var pid := sim.spawn_player("t", "yishi")
	_put(sim, pid, 60, 60)                    # 野外, 唔受安全區
	sim._sync_stats(sim.ent(pid))
	return [sim, pid]


# ===== 「復活丹」item id 存在 + 5 城雜貨店有賣 =====
func t_item_and_shops(data: GameData) -> void:
	check(RulesCombat.ONSITE_REVIVE_PILL == 65338, "復活丹 item id = 65338")
	check(data.item_ids.has(65338), "復活丹喺 items.json 存在")
	var groceries := ["grocery", "grocery_xy", "grocery_rn", "grocery_wc", "grocery_xyc"]
	for sid in groceries:
		var shop := {}
		for s in data.shops:
			if String(s.get("id", "")) == sid:
				shop = s
				break
		check(not shop.is_empty(), "雜貨店 %s 存在" % sid)
		check((shop.get("stock", []) as Array).has(65338), "雜貨店 %s 有賣復活丹" % sid)


# ===== 復活丹: 倒地期間隨時 (唔使等 5 秒) 就地回滿血，消耗 1 =====
func t_revive_pill(data: GameData) -> void:
	var r := _mk(data, 91)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = sim.player_ch()
	sim.cmd_debug_give(pid, 65338, 2)
	var p: Dictionary = sim.ent(pid)
	var dx := int(p["x"])
	var dy := int(p["y"])
	sim.damage(p, 99999, {})
	check(bool(p.get("down", false)), "死: 入倒地")
	# 未夠 5 秒都可以即刻用復活丹 (唔受 5 秒限制)
	sim.cmd_revive_pill(pid)
	check(not bool(p.get("down", false)), "復活丹: 就地復活成功")
	check(int(p["x"]) == dx and int(p["y"]) == dy, "復活丹: 原地企 (冇傳送)")
	check(int(ch["hp"]) == int(p["max_hp"]), "復活丹: 回滿血")
	check(RulesShop.count_item(ch["bag"], 65338) == 1, "復活丹: 消耗 1 (2->1)")
	# 冇復活丹時: 擋
	var r2 := _mk(data, 92)
	var sim2: Sim = r2[0]
	var pid2: int = r2[1]
	var p2: Dictionary = sim2.ent(pid2)
	sim2.damage(p2, 99999, {})
	sim2.cmd_revive_pill(pid2)
	check(bool(p2.get("down", false)), "冇復活丹: cmd_revive_pill 冇反應")


# ===== 同伴道士超渡: 就救返倒地緊嘅主公 (原地回滿血) =====
func t_companion_revive(data: GameData) -> void:
	var sim := Sim.new(data, 93)
	var pid := sim.spawn_player("t", "yishi")
	var pe: Dictionary = sim.ent(pid)
	var ch: Dictionary = sim.player_ch()
	ch["level"] = 10
	var g: Dictionary = data.generals[0]
	var c0: Dictionary = sim._spawn_companion(pe, g)
	var cid := int(c0["id"])
	ch["recruit"] = {"comp": cid}         # _companion_of() 要靠呢個先搵到同伴
	var cch: Dictionary = c0["ch"]
	cch["classSkill"] = "chaodu"
	cch["level"] = 10
	_put(sim, pid, 60, 60)
	var q := sim._free_near(60, 60)
	_put(sim, cid, q.x, q.y)
	sim._sync_stats(pe)
	var c: Dictionary = sim.ent(cid)
	sim._sync_stats(c)
	cch["hp"] = int(c["max_hp"])
	cch["mp"] = 1000
	sim._sync_stats(c)
	var dx := int(pe["x"])
	var dy := int(pe["y"])
	sim.damage(pe, 99999, {})
	check(bool(pe.get("down", false)), "主公死: 入倒地")
	var got_revive: Array = [false]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "revive" and int(ev.get("dst", 0)) == pid:
			got_revive[0] = true)
	sim.cmd_companion_revive_owner(pid)
	check(not bool(pe.get("down", false)), "同伴超渡: 主公就地復活")
	check(int(pe["x"]) == dx and int(pe["y"]) == dy, "同伴超渡: 原地企 (冇傳送)")
	check(int(ch["hp"]) == int(pe["max_hp"]), "同伴超渡: 主公回滿血")
	check(int(cch["hp"]) < int(c["max_hp"]), "同伴超渡: 同伴扣咗 HP")
	check(bool(got_revive[0]), "同伴超渡: 發出 revive 事件 (dst=主公)")


# ===== 逾時未救: 300 秒 (3000 tick) 到強制回城 =====
func t_timeout_bailout(data: GameData) -> void:
	var r := _mk(data, 94)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = sim.player_ch()
	var p: Dictionary = sim.ent(pid)
	sim.damage(p, 99999, {})
	check(bool(p.get("down", false)), "死: 入倒地")
	var max_ticks := int(data.world["combat"]["playerDownMaxTicks"])
	check(max_ticks == 3000, "playerDownMaxTicks = 3000 (300 秒)")
	for _i in max_ticks - 1:
		sim.step()
	check(bool(p.get("down", false)), "未夠 3000 tick: 仍倒地")
	sim.step()
	check(not bool(p.get("down", false)), "3000 tick 到: 強制回城復活")
	check(int(p["x"]) == sim.inn_pos.x and int(p["y"]) == sim.inn_pos.y, "逾時兜底: 傳返客棧")
	check(int(ch["hp"]) == maxi(1, MathX.js_round(sim._eff_max_hp(ch) / 2.0)), "逾時兜底: HP 回一半")


# ===== read-model: player_down_view() =====
func t_down_view(data: GameData) -> void:
	var r := _mk(data, 95)
	var sim: Sim = r[0]
	var pid: int = r[1]
	check(sim.player_down_view().is_empty(), "未死: player_down_view 空")
	var p: Dictionary = sim.ent(pid)
	sim.damage(p, 99999, {})
	var dv := sim.player_down_view()
	check(bool(dv.get("down", false)), "倒地: down=true")
	check(not bool(dv.get("canSelf", true)), "倒地: 未夠 5 秒 canSelf=false")
	check(not bool(dv.get("hasPill", true)), "倒地: 冇復活丹 hasPill=false")
	check(not bool(dv.get("hasChaoduComp", true)), "倒地: 冇同伴 hasChaoduComp=false")
	for _i in int(data.world["combat"]["playerDownSelfTicks"]):
		sim.step()
	check(bool(sim.player_down_view().get("canSelf", false)), "倒地: 夠 5 秒後 canSelf=true")
