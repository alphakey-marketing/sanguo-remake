extends SceneTree
# 職業特技逐招效果: 開鎖/超渡/隱形/竊聽/透視 (學咗先用得、效果、冷卻、錯職業)
# 跑: Godot --headless --path client --script tests/run_cskill.gd
var fails := 0
var total := 0
var evs: Array = []


func check(c: bool, m: String) -> void:
	total += 1
	if not c:
		fails += 1
		print("[FAIL] " + m)


func _new(data: GameData, cls: String, skill: String) -> Array:
	var sim := Sim.new(data, 5)
	var id := sim.spawn_player("t", cls)
	var ch: Dictionary = sim.player_ch()
	ch["level"] = 30
	sim._full_heal(ch)
	sim._sync_stats(sim.ent(id))
	if skill != "":
		sim.cmd_debug_learn(id, "skill", skill)
	evs = []
	sim.event_emitted.connect(func(ev): evs.append(ev))
	return [sim, id, ch]


func _has(k: String) -> bool:
	return evs.any(func(ev): return str(ev.get("k", "")) == k)


func _init() -> void:
	var data := GameData.load_all()
	# 未學 / 錯職業
	var a := _new(data, "shinu", "")
	a[0].cmd_use_skill(a[1], "unlock")
	check(not _has("unlock_open"), "未學開鎖唔開")
	var b := _new(data, "yishi", "unlock")
	b[0].cmd_use_skill(b[1], "unlock")
	check(not _has("unlock_open"), "錯職業唔得")
	var lv := _new(data, "shinu", "unlock")
	lv[2]["level"] = 1
	lv[0].cmd_use_skill(lv[1], "unlock")
	check(not _has("unlock_open"), "等級唔夠唔得")

	# 開鎖: 無箱 → 冇；有箱 → 揀錯留箱、揀啱得賞
	var s := _new(data, "shinu", "unlock")
	var sim: Sim = s[0]
	var id: int = s[1]
	sim.cmd_use_skill(id, "unlock")
	check(not _has("unlock_open"), "附近冇寶箱唔開")
	var pe := sim.ent(id)
	var chest := sim._new_ent("寶箱", "chest", Vector2i(int(pe["x"]) + 1, int(pe["y"])))
	chest["hp"] = 1
	chest["locked"] = true
	chest["key"] = 1
	chest["drop"] = {"gold": 50, "items": []}
	sim.cmd_use_skill(id, "unlock")
	check(_has("unlock_open"), "有寶箱開鎖面板")
	var g0 := int(s[2]["gold"])
	sim.cmd_skill_pick(id, int(chest["id"]), 0)
	check(sim.ents.has(int(chest["id"])) and bool(chest["locked"]), "揀錯鑰匙箱仲鎖住")
	sim.cmd_skill_pick(id, int(chest["id"]), 1)
	check(not sim.ents.has(int(chest["id"])) and int(s[2]["gold"]) == g0 + 50, "揀啱得金 50 + 收箱")

	# 超渡 (道士): 倒地同伴 → 起身；自己扣 20% HP 30% MP
	var d := _new(data, "daoshi", "chaodu")
	var ds: Sim = d[0]
	var did: int = d[1]
	var dpe := ds.ent(did)
	ds.cmd_use_skill(did, "chaodu")
	check(not _has("revive"), "冇倒地人唔超渡")
	var ally := ds._new_ent("友", "player", Vector2i(int(dpe["x"]) + 1, int(dpe["y"])))
	ally["ch"] = ds.player_ch().duplicate(true)
	ally["hp"] = 0
	ally["down"] = true
	ally["ch"]["hp"] = 0
	var hp0 := int(d[2]["hp"])
	var mp0 := int(d[2]["mp"])
	ds.cmd_use_skill(did, "chaodu")
	check(_has("revive") and int(ally["hp"]) > 0 and not bool(ally.get("down", false)), "超渡令倒地人起身")
	check(int(d[2]["hp"]) < hp0 and int(d[2]["mp"]) < mp0, "超渡扣自己 HP/MP")

	# 隱形 (舞女): 開行車小遊戲 → 全穿 → stealth 狀態 + CD
	var w := _new(data, "wunu", "yinxing")
	var ws: Sim = w[0]
	var wid: int = w[1]
	ws.cmd_use_skill(wid, "yinxing")
	check(_has("stealth_open"), "隱形開行車面板")
	var pat: Array = w[2]["stealthGame"]["pattern"]
	var st := int(w[2]["stealthGame"]["start"])
	var ok := true
	for i in RulesStealth.GAP_COUNT:
		var t := -1
		for tk in range(ws.tick, ws.tick + 4 * RulesStealth.CART_PERIOD):
			if RulesStealth.cross_pattern(pat, st, i, tk):
				t = tk
				break
		if t < 0:
			ok = false
			break
		ws.state["tick"] = t
		ws.cmd_stealth_cross(wid)
	check(ok and _has("stealth_done"), "隱形穿晒得潛行")
	check(RulesSpell.has(w[2].get("status", {}), "stealth", ws.tick), "隱形狀態生效")
	evs.clear()
	ws.cmd_use_skill(wid, "yinxing")
	check(not _has("stealth_open"), "潛行中/冷卻唔再開")

	# 竊聽 (辯士): 冇居民唔得；有居民 → 傳聞 + CD
	var q := _new(data, "bianshi", "qieting")
	var qs: Sim = q[0]
	var qid: int = q[1]
	var qpe := qs.ent(qid)
	var far := true
	for o in qs.ents.values():
		if str(o.get("kind", "")) == "bot":
			far = false
	if far:
		qs.cmd_use_skill(qid, "qieting")
		check(not _has("qieting"), "附近冇居民唔竊聽")
	var bot := qs._new_ent("居民甲", "bot", Vector2i(int(qpe["x"]) + 1, int(qpe["y"])))
	bot["hp"] = 10
	qs.cmd_use_skill(qid, "qieting")
	check(_has("qieting") and (q[2].get("rumors", []) as Array).size() == 1, "竊聽得 1 條傳聞")
	evs.clear()
	qs.cmd_use_skill(qid, "qieting")
	check(not _has("qieting"), "竊聽冷卻中")
	qs.state["tick"] = qs.tick + RulesQieting.QIETING_CD_TICKS + 1
	qs.cmd_use_skill(qid, "qieting")
	check(_has("qieting") and (q[2]["rumors"] as Array).size() == 2, "冷卻後再聽，傳聞唔重複")

	# 透視 (美女): 附近怪 → 資訊 + 洞悉狀態 + CD
	var m := _new(data, "meinu", "toushi")
	var ms: Sim = m[0]
	var mid: int = m[1]
	ms.cmd_use_skill(mid, "toushi")
	var any_near := _has("toushi")
	if not any_near:
		var mpe := ms.ent(mid)
		var mob := ms._new_ent("水鴨", "mob", Vector2i(int(mpe["x"]) + 2, int(mpe["y"])))
		mob["hp"] = 50
		mob["max_hp"] = 50
		mob["mob"] = {"def": 12022, "lv": 5}
		ms.cmd_use_skill(mid, "toushi")
	var info: Dictionary = {}
	for ev in evs:
		if str(ev.get("k", "")) == "toushi":
			info = ev["info"]
	check(not info.is_empty(), "透視出資訊")
	check(RulesSpell.has(m[2].get("status", {}), "insight", ms.tick), "透視入洞悉狀態")
	evs.clear()
	ms.cmd_use_skill(mid, "toushi")
	check(not _has("toushi"), "透視冷卻中")

	# 融合 (義士): 打鐵鋪 + 屬性石 → 集氣棒 → 早撳失敗唔扣石 / 準時成功嵌石 / 已嵌唔再融合 / 非義士唔得
	var f := _new(data, "yishi", "")
	var fs: Sim = f[0]
	var fid: int = f[1]
	var fch: Dictionary = f[2]
	fs.cmd_fusion_start(fid)
	check((fch.get("fusing", {}) as Dictionary).is_empty(), "唔喺打鐵鋪唔融合")
	var fe := fs.ent(fid)
	fe["x"] = int(data.facilities["forge"]["x"])
	fe["y"] = int(data.facilities["forge"]["y"])
	fs.cmd_fusion_start(fid)
	check((fch.get("fusing", {}) as Dictionary).is_empty(), "冇屬性石唔融合")
	fs.cmd_debug_give(fid, 32001, 2)
	fs.cmd_fusion_start(fid)
	check(not (fch.get("fusing", {}) as Dictionary).is_empty(), "開始融合集氣棒")
	fs.cmd_fusion_hit(fid)
	check(RulesShop.count_item(fch["bag"], 32001) == 2 and (fch.get("fusedJewels", {}) as Dictionary).is_empty(), "撳早失敗唔扣石")
	fs.cmd_fusion_start(fid)
	for i in 15:
		fs.step()
	fs.cmd_fusion_hit(fid)
	check(RulesShop.count_item(fch["bag"], 32001) == 1, "成功扣 1 粒石")
	var wp := int(fch["equip"]["weapon"])
	check((fch["fusedJewels"] as Dictionary).has(wp) and str(fch["fusedJewels"][wp]["elem"]) == "wind", "武器嵌風石")
	check(absf(fs._phys_elem_mult(fch, "earth") - 1.05) < 0.0001, "融合石物理剋地 ×1.05")
	fs.cmd_fusion_start(fid)
	check((fch.get("fusing", {}) as Dictionary).is_empty(), "已嵌武器唔再融合")
	var nf := _new(data, "daoshi", "")
	var nfe: Dictionary = nf[0].ent(nf[1])
	nfe["x"] = int(data.facilities["forge"]["x"])
	nfe["y"] = int(data.facilities["forge"]["y"])
	nf[0].cmd_debug_give(nf[1], 32001, 1)
	nf[0].cmd_fusion_start(nf[1])
	check((nf[2].get("fusing", {}) as Dictionary).is_empty(), "非義士唔得融合")

	# 冇開鎖技能: 狂打寶箱 12 下撬爛得賞
	var pr := _new(data, "yishi", "")
	var ps: Sim = pr[0]
	var pid: int = pr[1]
	var ppe := ps.ent(pid)
	var pc := ps._new_ent("寶箱", "chest", Vector2i(int(ppe["x"]) + 1, int(ppe["y"])))
	pc["hp"] = 1
	pc["locked"] = true
	pc["key"] = 1
	pc["drop"] = {"gold": 40, "items": []}
	var pg0 := int(pr[2]["gold"])
	ps.cmd_attack(pid, int(pc["id"]))
	for i in 40:
		ps.step()
	check(ps.ents.has(int(pc["id"])) and int(pc["pry"]) < 12, "狂打寶箱未爛 (撬緊)")
	for i in 200:
		ps.step()
	check(not ps.ents.has(int(pc["id"])) and int(pr[2]["gold"]) >= pg0 + 40, "冇開鎖技能撬爛寶箱得賞")

	print("[TEST] cskill: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)
