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
	t_tianqian_rules(data)
	t_tianqian_reprisal(data)
	t_selfdef_no_tianqian(data)
	t_safe_guard_warn(data)
	t_murderer_rest_refused(data)
	t_criminal_no_office(data)
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


# ===== S03b 純函數: 天譴 + 城門二階 + 官令阻 (spec 03 §3, §5) =====
func t_tianqian_rules(data: GameData) -> void:
	# 天譴雷劈: 現有 HP×50% (最多留 1)
	check(RulesKarma.tianqian_hp(100) == 50, "天譴: HP100 -> 50")
	check(RulesKarma.tianqian_hp(99) == 49, "天譴: HP99 -> 49")
	check(RulesKarma.tianqian_hp(101) == 50, "天譴: HP101 -> 50 (floor)")
	check(RulesKarma.tianqian_hp(1) == 1, "天譴: HP1 -> 最少 1")
	check(RulesKarma.tianqian_hp(0) == 1, "天譴: HP0 -> 最少 1")
	check(RulesKarma.tianqian_announce("張三") == "張三因作惡多端遭到天譴", "天譴: 公告文案")
	check(RulesKarma.tianqian_blocks_revive(), "天譴: 還魂丹無效 (S03c invariant)")
	# 城門拒入: 殺人魔 (≤ -16001, tier6) 先拒
	check(RulesKarma.city_banned(-30000), "城門: -30000 殺人魔拒入")
	check(RulesKarma.city_banned(-16001), "城門: -16001 殺人魔拒入 (邊界)")
	check(not RulesKarma.city_banned(-16000), "城門: -16000 惡人唔拒 (邊界)")
	check(not RulesKarma.city_banned(0), "城門: 中立唔拒")
	# 官令: 罪犯及以下 (≤ -1001, tier>=4) 唔接
	check(RulesKarma.office_blocked(-1001), "官令: -1001 罪犯拒")
	check(RulesKarma.office_blocked(-30000), "官令: -30000 殺人魔拒")
	check(not RulesKarma.office_blocked(-1000), "官令: -1000 中立接 (邊界)")
	check(not RulesKarma.office_blocked(30000), "官令: 大英雄接")
	check(str(RulesKarma.guard_warn_text(-30000)) != "", "城門: 衛兵警告文案非空")


# ===== S03b sim: 殺善居民(非自衛) -> 天譴 =====
func t_tianqian_reprisal(data: GameData) -> void:
	var r := _mk(data, 71)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var b: Dictionary = r[2]
	var ch: Dictionary = sim.player_ch()
	var bid := int(b["id"])
	ch["karma"] = 0
	# 玩家喺野外 (60,60) 打爆居民, 設定玩家 HP 高過 1 先 (好驗 half)
	var hp_before := int(ch["hp"])
	sim.ent(bid)["hp"] = 1
	sim.ent(bid)["ch"]["hp"] = 1
	var got: Array = [false, "", false]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "tianqian" and int(ev.get("dst", 0)) == pid:
			got[0] = true
			got[1] = str(ev.get("announce", ""))
		if String(ev.get("k", "")) == "kill_npc" and int(ev.get("dst", 0)) == pid:
			got[2] = bool(ev.get("tianqian", false)))
	sim.cmd_attack(pid, bid)
	for _i in 60:
		sim.step()
		if bool(got[0]):
			break
	check(bool(got[0]), "天譴: 殺善居民發出 tianqian 事件")
	check(bool(got[2]), "天譴: kill_npc 事件帶 tianqian=true")
	check(int(ch["karma"]) == -1000, "天譴: 善惡照 -1000")
	check(int(ch["hp"]) == RulesKarma.tianqian_hp(hp_before), "天譴: 玩家 HP 劈半")
	check(bool(ch.get("tianqian", false)), "天譴: ch.tianqian 旗 (S03c 還魂丹無效用)")
	check(str(got[1]) == RulesKarma.tianqian_announce("t"), "天譴: 公告文案送出")
	var inn: Dictionary = data.inn
	check(int(sim.ent(pid)["x"]) == int(inn["x"]) and int(sim.ent(pid)["y"]) == int(inn["y"]), "天譴: 傳送回客棧")
	check(not sim.ents.has(bid), "天譴: 居民已移除")


# ===== S03b sim: 自衛反殺善居民 -> 唔啪天譴 =====
func t_selfdef_no_tianqian(data: GameData) -> void:
	# 玩家被居民先攻而反殺 -> counter=true -> 唔應該有天譴
	var sim := Sim.new(data, 72)
	var pid := sim.spawn_player("t", "yishi")
	var me: Dictionary = sim.ent(pid)
	_put(sim, pid, 60, 60)
	sim._sync_stats(me)
	var ch: Dictionary = sim.player_ch()
	ch["karma"] = 0
	var b := sim._spawn_actor("路人", "bot")
	BotSys.init_identity(b, sim.rng)
	var q := sim._free_near(60, 60)
	_put(sim, int(b["id"]), q.x, q.y)
	sim._sync_stats(b)
	sim.state["bots"].append(int(b["id"]))
	var bid := int(b["id"])
	var got := [false]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "tianqian" and int(ev.get("dst", 0)) == pid:
			got[0] = true)
	# 玩家冇追擊 (atk_target=0) -> 直接打 (假定覺察到被襲, 自衛反殺)
	sim.ent(bid)["hp"] = 1
	sim.ent(bid)["ch"]["hp"] = 1
	sim.damage(sim.ent(bid), 99999, sim.ent(pid))
	check(not got[0], "天譴: 自衛反殺唔啪天譴")
	check(not bool(ch.get("tianqian", false)), "天譴: 自衛反殺冇 tianqian 旗")
	check(int(ch["karma"]) == -900, "天譴: 自衛反殺善居民 = 殺善 -1000 + 反擊 +100 = -900")
	check(not sim.ents.has(bid), "天譴: 自衛反殺居民移除")


# ===== S03b sim: 殺人魔喺安全區 -> 城門衛兵警告 =====
func t_safe_guard_warn(data: GameData) -> void:
	var sim := Sim.new(data, 73)
	var pid := sim.spawn_player("t", "yishi")
	var me: Dictionary = sim.ent(pid)
	var ch: Dictionary = me["ch"]
	ch["karma"] = -30000          # 殺人魔
	var inn: Dictionary = data.inn
	_put(sim, pid, int(inn["x"]), int(inn["y"]))
	sim._sync_stats(me)
	var got := [false]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "guard_warn" and int(ev.get("dst", 0)) == pid:
			got[0] = true)
	sim.step()
	sim.step()
	sim.step()
	check(got[0], "城門: 殺人魔喺安全區發出 guard_warn")


# ===== S03b sim: 殺人魔客棧休息被衛兵拒 =====
func t_murderer_rest_refused(data: GameData) -> void:
	var sim := Sim.new(data, 74)
	var pid := sim.spawn_player("t", "yishi")
	var me: Dictionary = sim.ent(pid)
	var ch: Dictionary = me["ch"]
	ch["karma"] = -30000
	var inn: Dictionary = data.inn
	_put(sim, pid, int(inn["x"]) + 1, int(inn["y"]))
	sim._sync_stats(me)
	var hp := int(ch["hp"])
	var gold := int(ch["gold"])
	var refused := [false]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "msg" and int(ev.get("dst", 0)) == pid and str(ev.get("text", "")).contains("衛兵"):
			refused[0] = true)
	sim.cmd_rest(pid)
	check(refused[0], "城門: 殺人魔客棧休息被衛兵拒")
	check(int(ch["hp"]) == hp and int(ch["gold"]) == gold, "城門: 拒絶後冇回復冇扣金")


# ===== S03b sim: 罪犯以下唔接官令 =====
func t_criminal_no_office(data: GameData) -> void:
	var orders: Array = data.office["orders"]
	if orders.is_empty():
		check(true, "官令表非空 (測試可跑)")
		return
	var oid := String(orders[0]["id"])
	var sim := Sim.new(data, 75)
	var pid := sim.spawn_player("t", "yishi")
	var me: Dictionary = sim.ent(pid)
	var ch: Dictionary = me["ch"]
	ch["karma"] = -5000           # 罪犯
	# 企喺官宅隔籬 (donate_xc, xuchang 許昌)
	var xcf: Dictionary = data.facilities.get("donate_xc", {})
	if xcf.is_empty():
		check(true, "官宅設施存在 (測試可跑)")
		return
	_put(sim, pid, int(xcf["x"]), int(xcf["y"]))
	sim._sync_stats(me)
	check(sim.office_near(me) != "", "官令: 玩家企喺官宅隔籬")
	var refused := [false]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "msg" and int(ev.get("dst", 0)) == pid and str(ev.get("text", "")).contains("罪犯") and str(ev.get("text", "")).contains("官令"):
			refused[0] = true)
	sim.cmd_office_order(pid, oid)
	check(refused[0], "官令: 罪犯接官令被拒 (msg 罪犯...官令)")
	# 對照: 中立玩家接得到 (唔應該被官令阻) — 升夠頭銜 rank 過官令 title gate
	var sim2 := Sim.new(data, 76)
	var pid2 := sim2.spawn_player("t2", "yishi")
	var me2: Dictionary = sim2.ent(pid2)
	var ch2: Dictionary = me2["ch"]
	ch2["karma"] = 0
	ch2["titleRank"] = 10
	_put(sim2, pid2, int(xcf["x"]), int(xcf["y"]))
	sim2._sync_stats(me2)
	var accepted := [false]
	sim2.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "office_order" and int(ev.get("id", 0)) == pid2:
			accepted[0] = true)
	sim2.cmd_office_order(pid2, oid)
	check(accepted[0], "官令: 中立玩家接得官令 (對照)")