extends SceneTree
# S03a 可攻擊 NPC 測試 (spec 03 §2, §3, §4): 居民/紅名 NPC 攻擊 + 反擊/逃跑叫衛兵/善惡。
# 覆蓋: 純函數善惡 (殺善 -1000 / 紅殺紅 +300 / 反擊 +100)、cmd_attack 開放 bot、
#       安全區照禁、殺居民 murder / 殺紅名 bounty 事件、紅名自衛反殺、逃跑叫衛兵、view_ents 紅名。
# 跑: Godot --headless --path client --script tests/run_pk.gd

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_karma_rules(data)
	t_npc_attack_good(data)
	t_npc_safe_zone(data)
	t_npc_red_kill(data)
	t_npc_self_defense(data)
	t_npc_flee_guards(data)
	t_npc_view(data)
	print("[TEST] pk: %d, fail %d" % [total, fails])
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


# 喺野外 (60,60 附近非安全) 砌一個玩家 + 一隻居民 (bot)，玩家黐住佢
func _mk(data: GameData, seed: int) -> Array:
	var sim := Sim.new(data, seed)
	var pid := sim.spawn_player("t", "yishi")
	var me: Dictionary = sim.ent(pid)
	_put(sim, pid, 60, 60)
	sim._sync_stats(me)
	var b := sim._spawn_actor("路人", "bot")
	BotSys.init_identity(b, sim.rng)
	var q := sim._free_near(60, 60)
	_put(sim, int(b["id"]), q.x, q.y)
	sim._sync_stats(b)
	return [sim, pid, b]


# ===== 純函數: 殺善 -1000 / 紅殺紅 +300 / 反擊 +100 (spec 03 §2) =====
func t_karma_rules(data: GameData) -> void:
	# 殺善居民 (自己非惡): 直接 -1000
	check(RulesKarma.karma_after_kill_npc(0, {"good": true, "red": false}) == -1000, "中立殺善: 直接 -1000")
	check(RulesKarma.karma_after_kill_npc(5000, {"good": true, "red": false}) == -1000, "正/善殺善: 直接 -1000")
	check(RulesKarma.karma_after_kill_npc(1000, {"good": true, "red": false}) == -1000, "好人殺善: 直接 -1000")
	# 惡人殺善: 累積 -1000
	check(RulesKarma.karma_after_kill_npc(-5000, {"good": true, "red": false}) == -6000, "罪犯殺善: 累積 -1000")
	check(RulesKarma.karma_after_kill_npc(-20000, {"good": true, "red": false}) == -21000, "殺人魔殺善: 累積 -1000")
	# 殺紅名 (殺人魔) NPC: +300 (善/中立一致)
	check(RulesKarma.karma_after_kill_npc(0, {"good": false, "red": true}) == 300, "中立殺紅名: +300")
	check(RulesKarma.karma_after_kill_npc(5000, {"good": false, "red": true}) == 5300, "善殺紅名: +300")
	# 紅殺紅 +300（一樣）
	check(RulesKarma.karma_after_kill_npc(-20000, {"good": false, "red": true}) == -19700, "紅殺紅: +300")
	# 反擊成功 +100 (疊加喺基礎之上)
	check(RulesKarma.counter_kill(-1000) == -900, "反擊: 基礎 +100")
	check(RulesKarma.counter_kill(-19700) == -19600, "反擊: 疊加喺紅殺之後 = 前面 +300 再 +100")
	# clamp ±30000
	check(RulesKarma.karma_after_kill_npc(29900, {"good": false, "red": true}) == 30000, "紅名 clamp 頂")
	check(RulesKarma.karma_after_kill_npc(-29900, {"good": true, "red": false}) == -30000, "殺善 clamp 底 (惡人 -1000 到底)")


# ===== cmd_attack 開放居民 + 殺善居民 -> karma -1000 + murder 事件 + 移除 =====
func t_npc_attack_good(data: GameData) -> void:
	var r := _mk(data, 61)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var b: Dictionary = r[2]
	var ch: Dictionary = sim.player_ch()
	var bid := int(b["id"])
	# 未開放前 bot 唔係攻擊目標? 依家開咗 -> cmd_attack 接受
	sim.cmd_attack(pid, bid)
	check(int(sim.ent(pid)["atk_target"]) == bid, "cmd_attack: 接受居民做目標")
	# 居民血 1: 一打即死
	sim.ent(bid)["hp"] = 1
	sim.ent(bid)["ch"]["hp"] = 1
	var got_murder: Array = [false, 0]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "kill_npc" and int(ev.get("dst", 0)) == pid:
			got_murder[0] = true
			got_murder[1] = int(ev.get("karma", 0)))
	var before := 0
	for _i in 60:
		sim.step()
		if int(ch.get("karma", 0)) < before:
			break
	check(int(ch["karma"]) == -1000, "殺善居民: 善惡一次過 -1000")
	check(bool(got_murder[0]), "殺居民: 發出 kill_npc (murder) 事件")
	check(String(sim.ent(bid).get("kind", "")) != "bot" or not sim.ents.has(bid), "殺居民: 居民被移除")
	check(int(sim.ent(pid).id) == pid, "玩家仲喺度")


# ===== 安全區照禁: 城內攻擊居民無效 =====
func t_npc_safe_zone(data: GameData) -> void:
	var sim := Sim.new(data, 62)
	var pid := sim.spawn_player("t", "yishi")
	var me: Dictionary = sim.ent(pid)
	var inn: Dictionary = data.inn
	_put(sim, pid, int(inn["x"]), int(inn["y"]) + 2)
	sim._sync_stats(me)
	var b := sim._spawn_actor("路人", "bot")
	BotSys.init_identity(b, sim.rng)
	_put(sim, int(b["id"]), int(inn["x"]), int(inn["y"]) + 3)
	sim._sync_stats(b)
	check(sim.is_safe(int(sim.ent(pid)["x"]), int(sim.ent(pid)["y"])), "玩家喺安全區")
	check(sim.is_safe(int(sim.ent(int(b["id"]))["x"]), int(sim.ent(int(b["id"]))["y"])), "居民喺安全區")
	sim.ent(int(b["id"]))["hp"] = 1
	sim.ent(int(b["id"]))["ch"]["hp"] = 1
	var ch: Dictionary = sim.player_ch()
	sim.cmd_attack(pid, int(b["id"]))
	var k0 := int(ch["karma"])
	for _i in 40:
		sim.step()
		if int(ch["karma"]) != k0:
			break
	check(int(ch["karma"]) == k0, "安全區: 攻擊居民唔會改變善惡")
	# 安全區會自動回血 (regen)，唔可以用 hp==1 證明；證明 = 居民仲喺度 + 冇死 + 善惡冇變
	check(sim.ents.has(int(b["id"])) and int(sim.ent(int(b["id"]))["hp"]) > 0, "安全區: 居民冇死 (出手被禁)")


# ===== 殺紅名(殺人魔) NPC -> +300 + bounty 事件 =====
func t_npc_red_kill(data: GameData) -> void:
	var r := _mk(data, 63)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var b: Dictionary = r[2]
	b["ch"]["criminal"] = true
	var ch: Dictionary = sim.player_ch()
	ch["karma"] = 0
	var bid := int(b["id"])
	var got_bounty: Array = [false, false]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "kill_npc" and int(ev.get("dst", 0)) == pid:
			got_bounty[0] = true
			got_bounty[1] = bool(ev.get("red", false)))
	sim.ent(bid)["hp"] = 1
	sim.ent(bid)["ch"]["hp"] = 1
	sim.cmd_attack(pid, bid)
	for _i in 60:
		sim.step()
		if int(ch["karma"]) > 0:
			break
	check(int(ch["karma"]) == 300, "殺紅名 NPC: +300")
	check(bool(got_bounty[0]) and bool(got_bounty[1]), "殺紅名: kill_npc 事件 red=true")


# ===== 紅名(殺人魔)主動襲擊玩家 -> 玩家自衛反殺 = 反擊 +100 疊加喺 +300 上面 =====
func t_npc_self_defense(data: GameData) -> void:
	var sim := Sim.new(data, 64)
	var pid := sim.spawn_player("t", "yishi")
	var me: Dictionary = sim.ent(pid)
	_put(sim, pid, 60, 60)
	sim._sync_stats(me)
	var b := sim._spawn_actor("殺人魔", "bot")
	BotSys.init_identity(b, sim.rng)
	b["ch"]["criminal"] = true
	var q := sim._free_near(60, 60)
	_put(sim, int(b["id"]), q.x, q.y)
	sim._sync_stats(b)
	sim.state["bots"].append(int(b["id"]))
	var ch: Dictionary = sim.player_ch()
	ch["karma"] = 0
	var bid := int(b["id"])
	# 玩家冇追擊佢 (atk_target=0)；紅名居民喺 BotSys.think 會主動鎖定玩家 (crimeAggro)
	var locked := false
	for _i in 30:
		sim.step()
		if String(sim.ent(int(me["id"])).get("kind", "")) == "":
			break
		if int(sim.ent(bid).get("atk_target", 0)) == pid:
			locked = true
			break
	check(locked, "紅名居民: 主動襲擊玩家 (atk_target=玩家)")
	# 玩家反殺 (player 冇 atk_target 指向佢 = 自衛) -> 紅殺 +300 + 反擊 +100 = +400
	sim.ent(bid)["hp"] = 1
	sim.ent(bid)["ch"]["hp"] = 1
	sim.damage(sim.ent(bid), 99999, sim.ent(pid))
	check(int(ch["karma"]) == 400, "自衛反殺紅名: 紅殺 +300 + 反擊 +100 = +400")
	check(not sim.ents.has(bid), "自衛反殺: 紅名被移除")


# ===== 逃跑叫衛兵: 被襲居民 (fleePk) 到安全區/客棧 -> guard_alert + 消失 =====
func t_npc_flee_guards(data: GameData) -> void:
	var sim := Sim.new(data, 65)
	var pid := sim.spawn_player("t", "yishi")
	_put(sim, pid, 60, 60)
	sim._sync_stats(sim.ent(pid))
	var b := sim._spawn_actor("路人", "bot")
	BotSys.init_identity(b, sim.rng)
	sim.state["bots"].append(int(b["id"]))
	var bid := int(b["id"])
	# 玩家襲擊, 居民揀咗逃跑: 手動設定 fleePk + aggressor
	sim.ent(bid)["ch"]["fleePk"] = true
	sim.ent(bid)["aggressor"] = pid
	# 放喺客棧隔籬 (安全) -> 下一步 BotSys.think 走去叫衛兵
	var innx := int(data.inn["x"])
	var inny := int(data.inn["y"])
	_put(sim, bid, innx, inny + 2)
	var got_alert: Array = [false, ""]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "guard_alert" and int(ev.get("dst", 0)) == pid:
			got_alert[0] = true
			got_alert[1] = str(ev.get("name", "")))
	for _i in 30:
		sim.step()
		if bool(got_alert[0]):
			break
	check(bool(got_alert[0]), "逃跑居民: 到安全區發出 guard_alert (叫衛兵)")
	check(not sim.ents.has(bid), "逃跑居民: 走去叫衛兵後消失")
	check(not (sim.state["bots"] as Array).has(bid), "逃跑居民: 由居民清單移除")


# ===== view_ents 紅名表示 (UI 紅名顯示用) =====
func t_npc_view(data: GameData) -> void:
	var sim := Sim.new(data, 66)
	var pid := sim.spawn_player("t", "yishi")
	_put(sim, pid, 60, 60)
	var good := sim._spawn_actor("路人", "bot")
	_put(sim, int(good["id"]), 61, 60)
	var red := sim._spawn_actor("殺人魔", "bot")
	red["ch"]["criminal"] = true
	_put(sim, int(red["id"]), 62, 60)
	var found_good := false
	var found_red := false
	for e in sim.view_ents():
		if int(e["id"]) == int(good["id"]):
			found_good = not bool(e.get("criminal", false))
		if int(e["id"]) == int(red["id"]):
			found_red = bool(e.get("criminal", false))
	check(found_good, "view_ents: 普通居民 criminal=false (白名)")
	check(found_red, "view_ents: 紅名居民 criminal=true (紅名顯示)")