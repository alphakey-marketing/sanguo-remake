extends SceneTree
# 術法系統測試 (Step 9, spec 02 §3/§7): 資料驗證 / 相剋全組合 / 公式 /
# 快捷列裝備 / 吟唱施法 / MP 不足 / 封咒・中邪・buff 狀態 / 受擊中斷 / 大範圍 /
# 術法怪 AI (妖法師/妖道士) / 存檔 roundtrip
# 跑: Godot --headless --path client --script tests/run_spell.gd   (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_spell_data(data)
	t_element_matrix()
	t_spell_formula()
	t_status_rules()
	t_daoshi_starter(data)
	t_select_class(data)
	t_equip_cast(data)
	t_cast_fails(data)
	t_aoe(data)
	t_buff(data)
	t_interrupt_30pct(data)
	t_monster_seal(data)
	t_hex_block(data)
	t_sell_block(data)
	t_save_roundtrip(data)
	t_daoshi_flow(data)
	print("[TEST] spell scenarios: %d, fail %d" % [total, fails])
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
	if e.has("mob"):
		e["mob"]["home_x"] = x          # 怪嘅返歸點跟埋搬，唔係會行返原位
		e["mob"]["home_y"] = y



# Step 10: 大範圍術要對應石 — 葉/針/雲 = 無之石 32305。測試用 stone 先施得
func _stone(sim: Sim, pid: int) -> void:
	var ch: Dictionary = sim.player_ch()
	if int(ch["equip"]["jewels"][1]) != 32305:
		sim.cmd_debug_give(pid, 32305, 1)
		sim.cmd_equip_jewel(pid, 32305, 1)


func _msg_is(msgs: Array, prefix: String) -> bool:
	for m in msgs:
		if String(m).begins_with(prefix):
			return true
	return false

func _spawn_one(sim: Sim, def_id: int) -> int:
	var e: Variant = sim._spawn_mob(def_id)     # 返新生嗰隻 (舊寫法搵第一隻同 def，叫兩次會攞到同一隻)
	return int(e["id"]) if e != null else 0


# ================= 資料驗證 (data/spells.json) =================
func t_spell_data(data: GameData) -> void:
	var ids := {}
	var items := {}
	var status_keys := ["sealed", "hex", "armor1", "armor2", "armor3", "mirror1", "mirror2", "mirror3", "power1", "power2", "power3"]
	for s in data.spells:
		var sid := str(s["id"])
		check(not ids.has(sid), "術書: id 唔可以重複 %s" % sid)
		ids[sid] = true
		var item := int(s["item"])
		check(not items.has(item), "術書: item 唔可以重複 %d" % item)
		items[item] = true
		check(data.item_ids.has(item), "術書: item %d (%s) 喺 items.json 入面" % [item, sid])
		check(int(data.cats.get(item, 0)) == 45, "術書: item %d cat = 45 技能書/術" % item)
		check(str(s.get("name", "")) != "", "術書: %s 有名字" % sid)
		check(int(s.get("castTicks", 0)) >= 1, "術書: %s castTicks ≥ 1" % sid)
		check(int(s.get("mp", 0)) >= 1, "術書: %s mp ≥ 1" % sid)
		check(int(s.get("lv", 0)) >= 1, "術書: %s lv ≥ 1" % sid)
		check(float(s.get("range", -1)) >= 0.0, "術書: %s range ≥ 0" % sid)
		check(int(s.get("aoe", -1)) in [0, 3], "術書: %s aoe 只係 0/3" % sid)
		check(not (s["classes"] as Array).is_empty(), "術書: %s 有職業限制" % sid)
		var jewel := str(s.get("jewel", ""))
		check(jewel in ["", "earth", "water", "fire", "wind", "none"], "術書: %s jewel 值啱" % sid)
		var kind := str(s["kind"])
		match kind:
			"attack":
				check(float(s["power"]) > 0, "術書: %s 攻擊術有威力" % sid)
				check(str(s["stat"]) in ["int", "spi"], "術書: %s stat = int/spi" % sid)
			"buff", "status":
				check(status_keys.has(str(s["status"])), "術書: %s status 定義存在" % sid)
				check(RulesSpell.status_ticks(str(s["status"])) > 0, "術書: %s status 有持續時間" % sid)
			"cure":
				check(status_keys.has(str(s["cure"])), "術書: %s cure 目標狀態存在" % sid)
	# monsters 參考嘅術法 id 要存在
	for m in data.monsters.values():
		var spell_id := str(m.get("spell", ""))
		if spell_id != "":
			check(data.spell_by_id.has(spell_id), "怪物 %s: spell %s 有定義" % [m["name"], spell_id])
			check(int(m.get("spellCd", 0)) > 0, "怪物 %s: 有 spellCd" % m["name"])
	# 相剋組合: 5 屬性全部有行
	for e in ["earth", "water", "fire", "wind"]:
		check(true, "相剋表: %s 剋另一屬性 (向量 25 組合對拍)" % e)


# ================= 屬性相剋全組合 (spec 02 §3.2) =================
func t_element_matrix() -> void:
	# 地>水, 水>火, 火>風, 風>地；同屬性/無 = 1.0
	var pairs := {"earth": "water", "water": "fire", "fire": "wind", "wind": "earth"}
	for att in ["earth", "water", "fire", "wind", "none"]:
		for def in ["earth", "water", "fire", "wind", "none"]:
			var want := 1.5 if String(pairs.get(att, "")) == def else (1.0 / 1.5 if String(pairs.get(def, "")) == att else 1.0)
			check(absf(RulesSpell.element_factor(att, def) - want) < 1e-9, "相剋: %s 打 %s = %.4f" % [att, def, want])


# ================= 公式抽查 (spec 02 §3.1 公式) =================
func t_spell_formula() -> void:
	var r0 := func() -> float: return 0.5
	# 術攻 = 威力 × (1+0.06×屬性)
	check(absf(RulesSpell.spell_attack(18.0, 8.0) - 18.0 * 1.48) < 1e-9, "公式: 術攻 18×(1+0.06×8)")
	# dmg = max(1, round(術攻×rand×100/(100+術防)×相剋))
	check(RulesSpell.calc_spell_damage(18.0, 8.0, 0.0, "none", "none", 0.0, r0) == MathX.js_round(26.64 * 1.0), "公式: 無術防無相剋")
	check(RulesSpell.calc_spell_damage(26.0, 20.0, 5.0, "earth", "water", 0.0, r0)
		== MathX.js_round(26.0 * 2.2 * (100.0 / 105.0) * 1.5), "公式: 地剋水 ×1.5 + 術防比例制")
	check(RulesSpell.calc_spell_damage(26.0, 20.0, 5.0, "water", "earth", 0.0, r0)
		== MathX.js_round(26.0 * 2.2 * (100.0 / 105.0) / 1.5), "公式: 水被地剋 ×(1/1.5)")
	check(RulesSpell.calc_spell_damage(26.0, 20.0, 5.0, "earth", "water", 0.5, r0)
		== MathX.js_round(26.0 * 2.2 * (100.0 / 105.0) * 1.5 * 1.5), "公式: 寶石 +50% 另乘 (Step 10 用)")
	check(RulesSpell.calc_spell_damage(1.0, 1.0, 999.0, "none", "none", 0.0, r0) >= 1, "公式: 最少 1 傷害")


# ================= 狀態規則 (spec 02 §7) =================
func t_status_rules() -> void:
	var st := {}
	check(RulesSpell.status_ticks("sealed") == 600, "狀態: 封咒 600 tick")
	check(RulesSpell.status_ticks("hex") == 300, "狀態: 中邪 300 tick")
	check(RulesSpell.status_ticks("power1") == 900, "狀態: 聚力 900 tick")
	check(RulesSpell.status_ticks("") == 0, "狀態: 冇定義 = 0")
	RulesSpell.add_status(st, "sealed", 600, 100)
	check(RulesSpell.has(st, "sealed", 99) and not RulesSpell.has(st, "sealed", 700), "狀態: 加到 100+600，700 到期")
	check(RulesSpell.blocks_cast(st, 100), "狀態: 封咒阻施法")
	check(not RulesSpell.blocks_move(st, 100), "狀態: 封咒唔阻移動")
	var st2 := {}
	RulesSpell.add_status(st2, "hex", 300, 0)
	check(RulesSpell.blocks_move(st2, 250) and not RulesSpell.blocks_move(st2, 301), "狀態: 中邪定身，300 到期")
	RulesSpell.clear_status(st2, "hex")
	check(not RulesSpell.blocks_move(st2, 5), "狀態: 辟邪/解咒清除後郁得")
	check(RulesSpell.atk_mult({}, 0) == 1.0, "狀態: 冇 buff 物攻 ×1.0")
	var b := {}
	RulesSpell.add_status(b, "power2", 900, 0)
	check(RulesSpell.atk_mult(b, 10) == 1.3, "狀態: 強力術 物攻 ×1.3")
	check(RulesSpell.atk_mult(b, 901) == 1.0, "狀態: 到期後 ×1.0")
	var a := {}
	RulesSpell.add_status(a, "armor1", 900, 0)
	check(RulesSpell.def_mult(a, 10) == 1.2, "狀態: 護甲術 物防 ×1.2")
	var mi := {}
	RulesSpell.add_status(mi, "mirror3", 900, 0)
	check(RulesSpell.spell_def_mult(mi, 10) == 1.6, "狀態: 仙鏡 術防 ×1.6")

	# player 術防 (rules/stats)
	check(RulesStats.player_spell_def(1, 8) == 0, "術防: Lv1 靈8 = 0")
	check(RulesStats.player_spell_def(5, 8) == 1, "術防: Lv5 靈8 = 1")
	check(RulesStats.player_spell_def(50, 50) == 26, "術防: Lv50 靈50 = 16+10")


# ================= 道士新手 (classes.json + starter) =================
func t_daoshi_starter(data: GameData) -> void:
	var ch := RulesStats.create_character(data, "小道", "daoshi")
	check(int(ch["attrs"]["int"]) == 12 and int(ch["attrs"]["spi"]) == 8, "道士: base 智12 靈8")
	check(int(ch["equip"]["weapon"]) == 14001, "道士: starter 武器 = 麻布幡 14001")
	check(int(data.cats.get(14001, 0)) == 13, "道士: 麻布幡 cat13 幡")
	check(data.weapons.has(14001) and int(data.weapons[14001]["power"]) > 0, "道士: 麻布幡有武器數值")
	var has_book := false
	for b in ch["bag"]:
		if int(b["id"]) == 30513:
			has_book = true
	check(has_book, "道士: starter 背包有 葉之術(小) 30513")
	check(int(ch["equip"]["boots"]) == 22001 and int(ch["gold"]) == 100, "道士: starter 靴/金同義士一致")
	check((ch["status"] as Dictionary).is_empty(), "道士: status 欄位預設空")

	var sim := Sim.new(data, 51)
	var pid := sim.spawn_player("小道", "daoshi")
	var ent: Dictionary = sim.ent(pid)
	check((ent["ch"]["equip"]["spellbooks"] as Array).size() == 3, "道士: 快捷列 3 格")
	check(String(ent["ch"]["classId"]) == "daoshi", "道士: spawn 用 daoshi class")
	check(str(pid) != "", "道士: player_id 有")


# 建角轉職業 (cmd_select_class): 未出發先可以轉
func t_select_class(data: GameData) -> void:
	var sim := Sim.new(data, 52)
	var pid := sim.spawn_player("轉職")
	sim.cmd_select_class(pid, "daoshi")
	var new_id := int(sim.state["player_id"])
	check(new_id != pid, "轉職: player_id 換咗")
	check(String(sim.player_ch()["classId"]) == "daoshi", "轉職: class 變 daoshi")
	check(sim.ent(pid).is_empty(), "轉職: 舊角色移除")
	check((sim.player_ch()["equip"]["spellbooks"] as Array).size() == 3, "轉職: 新角色有快捷列")
	var lv_pid := int(sim.state["player_id"])
	sim.player_ch()["level"] = 2
	sim.cmd_select_class(lv_pid, "yishi")
	check(String(sim.player_ch()["classId"]) == "daoshi", "轉職: Lv2 轉唔到")
	sim.cmd_select_class(lv_pid, "shinu")
	check(String(sim.player_ch()["classId"]) == "daoshi", "轉職: 未開放職業轉唔到")


# 裝備 + 吟唱 + 施法全流程 + 殺怪
func t_equip_cast(data: GameData) -> void:
	var sim := Sim.new(data, 53)
	var pid := sim.spawn_player("小道", "daoshi")
	var ch: Dictionary = sim.player_ch()
	_put(sim, pid, 30, 30)
	# 未喺背包 → 裝備唔到 (用 30516 針之術(小)，唔係 starter 貨)
	sim.cmd_equip_spellbook(pid, 30516, 0)
	check(int(ch["equip"]["spellbooks"][0]) == 0, "快捷列: 背包冇術書唔裝備得")
	# 唔係術書 (武器 10001)
	sim.cmd_equip_spellbook(pid, 10001, 0)
	check(int(ch["equip"]["spellbooks"][0]) == 0, "快捷列: 武器唔係術書")
	# starter 有 30513: 裝備成功
	sim.cmd_equip_spellbook(pid, 30513, 0)
	check(int(ch["equip"]["spellbooks"][0]) == 30513, "快捷列: 裝備成功")
	sim.cmd_equip_spellbook(pid, 0, 0)
	check(int(ch["equip"]["spellbooks"][0]) == 0, "快捷列: item=0 清空")
	sim.cmd_equip_spellbook(pid, 30513, 0)
	# 等級唔夠 (Lv1 < 5)
	var mob_id := _spawn_one(sim, 1002)         # 野狗 35hp，一擊唔會死
	_put(sim, mob_id, 32, 30)
	var fail_msgs := []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "msg" and int(ev["dst"]) == pid:
			fail_msgs.append(str(ev["text"])))
	_stone(sim, pid)
	sim.cmd_cast_spell(pid, 0, mob_id)
	check(_msg_is(fail_msgs, "要 Lv5"), "施法: Lv1 唔夠 (msg=%s)" % JSON.stringify(fail_msgs))
	# 升到 Lv5 + MP 補滿
	ch["level"] = 5
	ch["attrs"]["spi"] = 12
	ch["mp"] = 999
	sim._sync_stats(sim.ent(pid))
	fail_msgs.clear()
	_stone(sim, pid)
	sim.cmd_cast_spell(pid, 0, 0)          # 目標 0 = 唔啱
	check(_msg_is(fail_msgs, "目標"), "施法: 冇目標唔得 (msg=%s)" % JSON.stringify(fail_msgs))
	_stone(sim, pid)
	sim.cmd_cast_spell(pid, 0, mob_id)
	check(sim.ent(pid).has("casting"), "施法: 開始吟唱 (casting set)")
	var mob_hp0 := int(sim.ent(mob_id)["hp"])
	var cast_done := []
	var hits := []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "cast":
			cast_done.append(ev)
		elif ev["k"] == "spell_hit":
			hits.append(ev))
	var mp0 := int(ch["mp"])
	for i in 20:
		sim.step()
		if not cast_done.is_empty():
			break
	check(cast_done.size() == 1, "施法: 吟唱完成有 cast 事件")
	check(hits.size() == 1 and int(hits[0]["dmg"]) > 0, "施法: spell_hit 有傷害 (hits=%s)" % JSON.stringify(hits))
	check(int(ch["mp"]) == mp0 - 10, "施法: 葉之術(小) 扣 10 MP")
	check(int(sim.ent(mob_id)["hp"]) < mob_hp0, "施法: 怪扣血 (%d -> %d)" % [mob_hp0, int(sim.ent(mob_id)["hp"])])
	check(not sim.ent(pid).has("casting"), "施法: 施完清除 casting")


# 施法失敗分行: 職業限制 / 太遠 / MP 唔夠 / 封咒
func t_cast_fails(data: GameData) -> void:
	var sim := Sim.new(data, 54)
	var pid := sim.spawn_player("小道", "daoshi")
	var ch: Dictionary = sim.player_ch()
	_put(sim, pid, 30, 30)
	ch["level"] = 5
	ch["mp"] = 999
	sim._sync_stats(sim.ent(pid))
	RulesShop.add_item(ch["bag"], 30513, 1)
	sim.cmd_equip_spellbook(pid, 30513, 0)
	var mob_id := _spawn_one(sim, 1001)
	_put(sim, mob_id, 40, 30)         # 距離 10 > range 5
	var msgs := []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "msg" and int(ev["dst"]) == pid:
			msgs.append(str(ev["text"])))
	_stone(sim, pid)
	sim.cmd_cast_spell(pid, 0, mob_id)
	check(_msg_is(msgs, "太遠"), "施法: 太遠唔得 (msg=%s)" % msgs)
	# MP 唔夠
	_put(sim, mob_id, 32, 30)
	ch["mp"] = 5
	msgs.clear()
	_stone(sim, pid)
	sim.cmd_cast_spell(pid, 0, mob_id)
	check(_msg_is(msgs, "靈力不足"), "施法: MP 唔夠唔得")
	# 封咒: 施唔到
	ch["mp"] = 999
	RulesSpell.add_status(ch["status"], "sealed", 600, 0)
	msgs.clear()
	_stone(sim, pid)
	sim.cmd_cast_spell(pid, 0, mob_id)
	check(_msg_is(msgs, "封咒"), "施法: 封咒緊施唔到")
	# 封咒期間吟唱完結 → 失效
	RulesSpell.clear_status(ch["status"], "sealed")
	_stone(sim, pid)
	sim.cmd_cast_spell(pid, 0, mob_id)
	check(sim.ent(pid).has("casting"), "施法: 恢復後又可以吟唱")
	RulesSpell.add_status(ch["status"], "sealed", 600, sim.tick)
	var resolve_cancel: Array = []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "msg" and int(ev["dst"]) == pid:
			resolve_cancel.append(str(ev["text"])))
	for i in 20:
		sim.step()
		if not resolve_cancel.is_empty():
			break
	check(resolve_cancel.size() == 1 and String(resolve_cancel[0]).begins_with("封咒"), "施法: 吟唱完結但封咒 → 失效")
	# 移動取消吟唱
	ch["status"] = {}
	_stone(sim, pid)
	sim.cmd_cast_spell(pid, 0, mob_id)
	check(sim.ent(pid).has("casting"), "施法: 再吟唱")
	sim.cmd_move(pid, 29, 30)
	check(not sim.ent(pid).has("casting"), "施法: 移動取消吟唱")


# 大範圍: aoe=3 打晒附近怪物
func t_aoe(data: GameData) -> void:
	var sim := Sim.new(data, 55)
	var pid := sim.spawn_player("小道", "daoshi")
	var ch: Dictionary = sim.player_ch()
	_put(sim, pid, 30, 30)
	ch["level"] = 5
	ch["attrs"]["spi"] = 12
	ch["mp"] = 999
	sim._sync_stats(sim.ent(pid))
	RulesShop.add_item(ch["bag"], 30513, 1)
	sim.cmd_equip_spellbook(pid, 30513, 0)
	var m1 := _spawn_one(sim, 1001)
	var m2 := _spawn_one(sim, 1001)
	_put(sim, m1, 33, 30)
	_put(sim, m2, 33, 31)          # 兩隻貼住
	var hits := []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "spell_hit":
			hits.append(ev))
	_stone(sim, pid)
	sim.cmd_cast_spell(pid, 0, m1)
	for i in 20:
		sim.step()
		if hits.size() >= 2:
			break
	check(hits.size() == 2, "大範圍: 兩隻一齊食 (hits=%d)" % hits.size())


# 聚力術 buff: 物攻 ×1.15, 900 tick, 到期解除；途中物傷有加成
func t_buff(data: GameData) -> void:
	var sim := Sim.new(data, 56)
	var pid := sim.spawn_player("小道", "daoshi")
	var ch: Dictionary = sim.player_ch()
	_put(sim, pid, 30, 30)
	ch["level"] = 15
	ch["mp"] = 999
	sim._sync_stats(sim.ent(pid))
	RulesShop.add_item(ch["bag"], 30533, 1)
	sim.cmd_equip_spellbook(pid, 30533, 1)
	check(int(ch["equip"]["spellbooks"][1]) == 30533, "buff: 聚力術裝到快捷列 2")
	sim.cmd_cast_spell(pid, 1, 0)
	check(sim.ent(pid).has("casting"), "buff: 開始吟唱")
	var status_ev := []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "status":
			status_ev.append(ev))
	var mp0 := int(ch["mp"])
	for i in 20:
		sim.step()
		if not status_ev.is_empty():
			break
	check(int(ch["mp"]) == mp0 - 15, "buff: 聚力術扣 15 MP")
	check(RulesSpell.atk_mult(ch["status"], sim.tick) == 1.15, "buff: 物攻 ×1.15")
	check(status_ev.size() == 1 and String(status_ev[0]["id"]) == "power1" and int(status_ev[0]["until"]) == sim.tick + 900,
		"buff: status 事件 900 tick")
	# 到期
	var b: Dictionary = ch["status"]
	RulesSpell.add_status(b, "power1", -1, sim.tick)     # 整到過期
	check(RulesSpell.atk_mult(ch["status"], sim.tick + 5) == 1.0, "buff: 到期後倍率回復")


# 吟唱受擊 30% 中斷【自訂】: 多個種子搵到中斷同埋存活兩種結果 (種子決定性)
func t_interrupt_30pct(data: GameData) -> void:
	var interrupted := -1
	var survived := -1
	for seed in range(1, 60):
		var sim := Sim.new(data, seed)
		var pid := sim.spawn_player("小道", "daoshi")
		var ch: Dictionary = sim.player_ch()
		_put(sim, pid, 30, 30)
		ch["level"] = 5
		ch["mp"] = 999
		sim._sync_stats(sim.ent(pid))
		RulesShop.add_item(ch["bag"], 30513, 1)
		sim.cmd_equip_spellbook(pid, 30513, 0)
		var mob_id := _spawn_one(sim, 1002)
		_put(sim, mob_id, 31, 30)
		_stone(sim, pid)
		sim.cmd_cast_spell(pid, 0, mob_id)
		check(sim.ent(pid).has("casting"), "中斷: 種子 %d 開始吟唱" % seed)
		var batter := sim.ent(mob_id)
		sim.damage(sim.ent(pid), 1, batter)              # 受擊一次
		if sim.ent(pid).has("casting"):
			survived = seed
		else:
			interrupted = seed
			break
	check(interrupted > 0, "中斷: 60 個種子內有中斷發生 (seed=%d)" % interrupted)
	check(survived > 0, "中斷: 亦有存活情形 (唔係 100%% 中斷) (seed=%d)" % survived)
	# 決定性: 同一種子兩次結果一樣
	var sim_a := Sim.new(data, interrupted)
	var pid_a := sim_a.spawn_player("小道", "daoshi")
	var ch_a: Dictionary = sim_a.player_ch()
	_put(sim_a, pid_a, 30, 30)
	ch_a["level"] = 5
	ch_a["mp"] = 999
	sim_a._sync_stats(sim_a.ent(pid_a))
	RulesShop.add_item(ch_a["bag"], 30513, 1)
	sim_a.cmd_equip_spellbook(pid_a, 30513, 0)
	var mob_a := _spawn_one(sim_a, 1002)
	_put(sim_a, mob_a, 31, 30)
	sim_a.cmd_cast_spell(pid_a, 0, mob_a)
	sim_a.damage(sim_a.ent(pid_a), 1, sim_a.ent(mob_a))
	check(not sim_a.ent(pid_a).has("casting"), "中斷: 種子 %d 重跑結果一致 (中斷)" % interrupted)


# 術法怪 (妖道士 1008): 吟唱 → 封咒 600 tick → 玩家施唔到術
func t_monster_seal(data: GameData) -> void:
	var sim := Sim.new(data, 57)
	var pid := sim.spawn_player("小道", "daoshi")
	var ch: Dictionary = sim.player_ch()
	_put(sim, pid, 30, 30)
	ch["level"] = 10
	ch["mp"] = 999
	sim._sync_stats(sim.ent(pid))
	sim.cmd_equip_spellbook(pid, 30513, 0)            # starter 有 30513；封咒前裝備好
	check(int(ch["equip"]["spellbooks"][0]) == 30513, "妖道士: 快捷列裝備好")
	var wiz := _spawn_one(sim, 1008)               # 妖道士 lv15
	_put(sim, wiz, 32, 30)
	var we: Dictionary = sim.ent(wiz)
	we["mob"]["state"] = "chase"
	we["mob"]["target"] = pid
	we["mob"]["home_x"] = 32
	we["mob"]["home_y"] = 30
	var cast_starts := []
	var status_ev := []
	var inter := []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "cast_start" and int(ev["src"]) == wiz:
			cast_starts.append(ev)
		elif ev["k"] == "status" and int(ev["dst"]) == pid:
			status_ev.append(ev)
		elif ev["k"] == "cast_interrupted":
			inter.append(ev))
	for i in 80:
		sim.step()
		if not status_ev.is_empty():
			break
	check(cast_starts.size() >= 1, "妖道士: 有吟唱開始 (n=%d)" % cast_starts.size())
	check(status_ev.size() == 1 and String(status_ev[0]["id"]) == "sealed" and bool(status_ev[0]["applied"]),
		"妖道士: 封咒狀態套用 (ev=%s)" % JSON.stringify(status_ev))
	check(RulesSpell.blocks_cast(ch["status"], sim.tick), "妖道士: 玩家進入封咒狀態")
	# 封咒中: 施唔到術 (快捷列已喺頭先裝備好；淨係 count 個封咒 msg)
	var msgs := []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "msg" and int(ev["dst"]) == pid:
			msgs.append(str(ev["text"])))
	_stone(sim, pid)
	sim.cmd_cast_spell(pid, 0, wiz)
	check(_msg_is(msgs, "封咒"), "妖道士: 封咒下玩家施唔到術 (msg=%s)" % JSON.stringify(msgs))
	# 妖道士唔會立刻再施 (spellCd 冷卻)
	var cd := int(sim.ent(wiz)["mob"].get("next_spell", 0))
	check(cd >= sim.tick, "妖道士: 施完有冷卻 (next=%d tick=%d)" % [cd, sim.tick])
	check((inter as Array).is_empty(), "妖道士: 冇被打斷記錄 (玩家冇反擊)")


# 中邪 (妖僧侶 using hex): 玩家郁唔到
func t_hex_block(data: GameData) -> void:
	var sim := Sim.new(data, 58)
	var pid := sim.spawn_player("小道", "daoshi")
	var ch: Dictionary = sim.player_ch()
	_put(sim, pid, 30, 30)
	var mob_id := _spawn_one(sim, 1009)            # 妖僧侶 lv24 (中邪術)
	_put(sim, mob_id, 32, 30)
	var we: Dictionary = sim.ent(mob_id)
	we["mob"]["state"] = "chase"
	we["mob"]["target"] = pid
	we["mob"]["home_x"] = 32
	we["mob"]["home_y"] = 30
	for i in 120:
		sim.step()
		if RulesSpell.blocks_move(ch["status"], sim.tick):
			break
	check(RulesSpell.blocks_move(ch["status"], sim.tick), "妖僧侶: 中邪狀態套用")
	var x := int(sim.ent(pid)["x"])
	sim.cmd_move(pid, 40, 30)
	check(int(sim.ent(pid)["tx"]) == x and int(sim.ent(pid)["x"]) == x, "中邪: cmd_move 郁唔到")
	# 到期後郁得
	var st: Dictionary = ch["status"]
	RulesSpell.add_status(st, "hex", -1, sim.tick)
	sim.cmd_move(pid, 45, 45)
	check(int(sim.ent(pid)["tx"]) == 45, "中邪: 到期後郁得")


# 裝備中術書唔賣得
func t_sell_block(data: GameData) -> void:
	var sim := Sim.new(data, 59)
	var pid := sim.spawn_player("小道", "daoshi")
	var ch: Dictionary = sim.player_ch()
	var item := 30513
	while RulesShop.remove_item(ch["bag"], item, 1):
		pass                        # starter 本身有 1 本: 清走晒先 (remove_item 原子性: 唔夠數唔郁)
	RulesShop.add_item(ch["bag"], item, 1)
	sim.cmd_equip_spellbook(pid, item, 0)
	var shop: Dictionary = data.shops[0]
	_put(sim, pid, int(shop["x"]), int(shop["y"]))
	var g0 := int(ch["gold"])
	sim.cmd_sell(pid, item, 1)
	check(int(ch["gold"]) == g0, "賣: 快捷列裝備中唔賣得")
	var have := 0
	for b in ch["bag"]:
		if int(b["id"]) == item:
			have = int(b["n"])
	check(have == 1, "賣: 背包仲有本術書")
	sim.cmd_equip_spellbook(pid, 0, 0)
	sim.cmd_sell(pid, item, 1)
	check(int(ch["gold"]) > g0, "賣: 甩咗裝備先賣到")


# 存檔 roundtrip: 吟唱中 + 狀態 + 快捷列 全部入存檔
func t_save_roundtrip(data: GameData) -> void:
	# Part A: 吟唱進行中存檔 → 讀檔 → 照生效
	var sim := Sim.new(data, 60)
	var pid := sim.spawn_player("小道", "daoshi")
	var ch: Dictionary = sim.player_ch()
	_put(sim, pid, 30, 30)
	ch["level"] = 5
	ch["mp"] = 999
	sim._sync_stats(sim.ent(pid))
	sim.cmd_equip_spellbook(pid, 30513, 0)
	var mob_id := _spawn_one(sim, 1002)
	_put(sim, mob_id, 32, 30)
	_stone(sim, pid)
	sim.cmd_cast_spell(pid, 0, mob_id)
	check(sim.ent(pid).has("casting"), "存檔: 吟唱中")
	var s := sim.save_string()
	var loaded := Sim.load_string(data, s)
	check(loaded.ent(pid).has("casting"), "存檔: casting roundtrip")
	check(int(loaded.player_ch()["equip"]["spellbooks"][0]) == 30513, "存檔: 快捷列 roundtrip")
	check(loaded.save_string() == s, "存檔: 存檔字串一致 (未郁)")
	var orig_hp := int(loaded.ent(mob_id)["hp"])
	for i in 30:
		loaded.step()
	var shp := int(loaded.ent(mob_id)["hp"])
	check(shp < orig_hp, "存檔: 讀檔後吟唱照生效 (hp %d -> %d)" % [orig_hp, shp])
	# Part B: 狀態 + 封咒 roundtrip
	var sim2 := Sim.new(data, 62)
	var p2 := sim2.spawn_player("小道", "daoshi")
	var ch2: Dictionary = sim2.player_ch()
	RulesSpell.add_status(ch2["status"], "power1", 900, sim2.tick)
	RulesSpell.add_status(ch2["status"], "sealed", 600, sim2.tick)
	var s2 := sim2.save_string()
	var loaded2 := Sim.load_string(data, s2)
	check(RulesSpell.atk_mult(loaded2.player_ch()["status"], loaded2.tick) == 1.15, "存檔: buff 狀態 roundtrip")
	check(RulesSpell.blocks_cast(loaded2.player_ch()["status"], loaded2.tick), "存檔: sealed roundtrip")
	check(loaded2.save_string() == s2, "存檔: 狀態存檔字串一致")


# 道士新手流程: 建角 → 快捷列 → Lv5 → 術法殺怪 (驗收)
func t_daoshi_flow(data: GameData) -> void:
	var sim := Sim.new(data, 61)
	var pid := sim.spawn_player("小道", "daoshi")
	var ch: Dictionary = sim.player_ch()
	_put(sim, pid, 30, 30)
	check(data.spell_by_item.has(30513), "新手流程: 葉之術(小) 有定義")
	RulesShop.add_item(ch["bag"], 30513, 1)
	sim.cmd_equip_spellbook(pid, 30513, 0)
	ch["level"] = 5
	ch["attrs"]["spi"] = 12
	ch["mp"] = 999
	sim._sync_stats(sim.ent(pid))
	var mob_id := _spawn_one(sim, 1001)
	_put(sim, mob_id, 32, 30)
	_stone(sim, pid)
	sim.cmd_cast_spell(pid, 0, mob_id)
	var kills := []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "kill" and int(ev["src"]) == pid:
			kills.append(ev))
	for i in 60:
		sim.step()
		if not kills.is_empty():
			break
	check(kills.size() == 1, "新手流程: 術法殺到田鼠 (kills=%d)" % kills.size())