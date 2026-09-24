class_name Sim
extends "res://sim/sim_office.gd"
# 單機世界模擬: 格子地圖 + 單位 + 即時戰鬥 + 怪物 AI + 設施。
# - state 全部係純資料 (Dictionary/Array/int/String)，可直接存檔；RNG 由種子驅動 → 可重現
# - UI 只透過 cmd_* 發意圖、透過 event_emitted 收事件、透過 view_ents()/player_ch() 讀狀態
# 由 server/src/world.ts 重寫 (去 AOI/ws)；規則喺 rules/*.gd
# 實作分層見 sim_core.gd 頂註解；呢層 = 世界時鐘 / 日結 / step() / UI 讀取 / 存檔

# ---- 世界時鐘 / 天災 / 市場 (Step 4) ----
func _advance_clock() -> void:
	var clk: Dictionary = _clock()
	var min_per_tick := int(data.world["clock"]["gameMinPerTick"])
	var ke := RulesClock.ke_of_tick(tick, min_per_tick)
	var day := RulesClock.day_of_tick(tick, min_per_tick)
	var new_day := day != int(clk["day"])
	clk["day"] = day
	clk["ke"] = ke
	clk["is_night"] = RulesClock.is_night(ke, int(data.world["night"]["startKe"]), int(data.world["night"]["endKe"]))
	var shi := RulesClock.shichen_of_ke(ke)
	if new_day:
		_daily_hook(day)
	if shi != int(clk.get("lastShichen", -1)):
		clk["lastShichen"] = shi
		_sync_night_spawns()
	if ke != int(clk.get("lastKe", -1)):
		clk["lastKe"] = ke
		_sync_quest_npcs()          # 時辰窗口 NPC (Step 8): 每刻 check 一次


# 每日子時: 天災擲骰 -> 市場日結 -> 通知 UI
func _daily_hook(day: int) -> void:
	var disas: Array = state["disasters"]
	RulesDisaster.expire(disas, day)
	var season := RulesClock.season_of_day(day, int(data.world["clock"]["seasonDays"]))
	var changed: Array = []
	for c in data.world["cities"]:
		var d := RulesDisaster.roll_day(rng_fn, day, season, String(c.id), data.world["disasters"])
		if not d.is_empty():
			disas.append(d)
			changed.append(d)
	_market_daily(season)
	_storage_daily()
	_ap_daily()
	_salary_daily(day)           # 每月初一俸祿 (Step 14)
	_recruit_daily(day)          # 同伴到期/忠誠低離開 (Step 13.5)
	_emit({"k": "day", "day": day, "season": season})
	for d in changed:
		_emit({"k": "disaster", "name": d["name"], "city": d["city"], "size": d["size"]})


# 天地商行【原】: 子時扣 200/日；唔夠錢自動退訂
func _storage_daily() -> void:
	var cost := int(data.world.get("storageFee", 200))
	for e in ents.values():
		if not e.has("ch"):
			continue
		var ch: Dictionary = e["ch"]
		if not bool(ch.get("storageSub", false)):
			continue
		if int(ch["gold"]) < cost:
			ch["storageSub"] = false
			_msg(int(e["id"]), "天地商行費唔夠錢，自動退訂")
			continue
		ch["gold"] = int(ch["gold"]) - cost
		_msg(int(e["id"]), "天地商行扣 %d 金" % cost)


# 行動力【自訂】: 子時回滿 (Step 13)
func _ap_daily() -> void:
	for e in ents.values():
		if e.has("ch"):
			e["ch"]["ap"] = ap_max(e["ch"])


func _market_daily(season: int) -> void:
	var cfg: Dictionary = data.world["market"]
	for c in data.world["cities"]:
		var city_dis := []
		for d in state["disasters"]:
			if str(d["city"]) == str(c.id):
				city_dis.append(d)
		var sm := RulesMarket.supply_mods(season, cfg["seasonSupply"], city_dis, c)
		var dm := RulesMarket.demand_mods(season, cfg["seasonDemand"])
		RulesMarket.daily(c, state["market"][c.id], cfg, sm, dm)


# 入夜: 補夜怪；天光: 夜怪消失
func _sync_night_spawns() -> void:
	var night := bool(_clock()["is_night"])
	for sp in data.spawns:
		if not sp.get("night", false):
			continue
		if night:
			var have := 0
			for e in ents.values():
				if e["kind"] == "mob" and int(e["mob"]["def"]) == int(sp["monster"]):
					have += 1
			for i in int(sp["count"]) - have:
				if _spawn_mob(int(sp["monster"]), String(sp.get("zone", DEFAULT_ZONE))) == null:
					break
		else:
			for id0 in ents.keys():
				var e: Dictionary = ents.get(id0, {})
				if not e.is_empty() and e["kind"] == "mob" and data.mob_def(int(e["mob"]["def"])).get("night", false):
					ents.erase(id0)
					for e2 in ents.values():
						if int(e2["atk_target"]) == int(id0):
							e2["atk_target"] = 0


# 每 tick: 時鐘 -> 日結(天災/市場) -> 夜怪 -> 機械人思考 -> 戰鬥/AI -> 重生 -> 移動 (一格)
func step() -> void:
	state["tick"] = tick + 1
	_advance_clock()
	BotSys.think(self)
	_recruit_tick()             # 擂台勝負 (Step 13.5)
	for id in ents.keys():
		var e: Dictionary = ents.get(id, {})
		if e.is_empty():
			continue
		if e["kind"] == "mob":
			_think_mob(e)
		elif e.has("ch"):
			if e["kind"] == "gen":
				_think_companion(e)     # 登用同伴: 揀目標/跟隨 (Step 13.5)
			_think_player(e)
	var rs: Array = state["respawns"]
	for i in range(rs.size() - 1, -1, -1):
		if tick >= int(rs[i]["at"]):
			_spawn_mob(int(rs[i]["def"]), String(rs[i].get("zone", DEFAULT_ZONE)))     # 夜怪喺白天唔重生，天黑由 _sync_night_spawns 補
			rs.remove_at(i)
	for e in ents.values():
		# 逃跑怪 sprint: tick%2=0 嗰陣郁兩格 → 平均 1.5× 移速 (spec 04 §3)
		var mv := 2 if (e["kind"] == "mob" and (e.get("mob", {}) as Dictionary).get("state", "") == "flee" and tick % 2 == 0) else 1
		var moved := false
		for _k in mv:
			# A* 路徑 (spec 12 §3): 終點 = 目的地 + 下一格相鄰先有效，否則作廢行直線
			var path: Array = e.get("path", [])
			if not path.is_empty():
				var nxt := int(path[0])
				var cur := int(e["y"]) * W + int(e["x"])
				if int(path[-1]) == int(e["ty"]) * W + int(e["tx"]) and (absi(nxt - cur) == 1 or absi(nxt - cur) == W) and data.walk[nxt] == 1:
					e["x"] = nxt % W
					e["y"] = nxt / W
					path.pop_front()
					if path.is_empty():
						e.erase("path")
					moved = true
					continue
				e.erase("path")
			var n := _greedy_step(int(e["x"]), int(e["y"]), int(e["tx"]), int(e["ty"]))
			if n.x != int(e["x"]) or n.y != int(e["y"]):
				e["x"] = n.x
				e["y"] = n.y
				moved = true
		if moved:
			_on_moved(e)


# ================= UI 讀取 / 存檔 =================
# UI 用嘅單位視圖 (camelCase，同舊 server snapshot 一致)
func view_ents() -> Array:
	var out: Array = []
	for e in ents.values():
		var st_vis: Array = []
		var st_all: Dictionary = e.get("status", {}) if e["kind"] == "mob" else e.get("ch", {}).get("status", {})
		for k in st_all:
			if int(st_all[k]) > tick:
				st_vis.append(str(k))
		out.append({"id": e["id"], "name": e["name"], "x": e["x"], "y": e["y"], "face": e["face"],
			"bot": e["kind"] == "bot", "gen": e["kind"] == "gen", "hp": e["hp"], "maxHp": e["max_hp"], "level": e["level"], "mob": e["kind"] == "mob",
			"statuses": st_vis, "casting": e.has("casting"),
			"aggro": int(e["mob"]["target"]) if e["kind"] == "mob" and e["mob"]["state"] == "chase" else 0})   # 怪追緊邊個
	return out


func save_string() -> String:
	return JSON.stringify(_canonical({"state": state, "rng": rng.s}))


# 規範化: 整數 float → int、其他 float → 6 位小數。保證 save→load→save 字串一致
static func _canonical(v: Variant) -> Variant:
	if v is Dictionary:
		var o := {}
		for k in v:
			o[k] = _canonical(v[k])
		return o
	if v is Array:
		var a := []
		for x in v:
			a.append(_canonical(x))
		return a
	if v is float:
		var f: float = v
		return int(f) if f == floor(f) else float(round(f * 1000000.0)) / 1000000.0
	return v


static func load_string(game_data: GameData, s: String) -> Sim:
	var d = JSON.parse_string(s)
	if not d is Dictionary:
		return null
	var sim := Sim.new(game_data, int(d["rng"]))
	var st: Dictionary = _intify(d["state"])
	var es := {}
	for k in st["ents"]:
		es[int(k)] = st["ents"][k]
	st["ents"] = es
	sim.state = st
	for e in es.values():
		if e.has("ch"):
			sim._ensure_equip(e["ch"])      # 舊存檔裝備欄兼容 (Step 11.6)
	sim._fix_positions()
	return sim


# 舊存檔 (地圖改版前, spec 12) 單位可能企喺牆/樹/虛空: 人搬返客棧、怪喺自己 spawn 範圍重揀位
func _fix_positions() -> void:
	for e in ents.values():
		if is_free(int(e["x"]), int(e["y"])):
			continue
		var p := inn_pos
		if e["kind"] == "mob":
			var zone := String(e["mob"].get("zone", DEFAULT_ZONE))
			var r: Array = []
			for sp in data.spawns:
				if int(sp["monster"]) == int(e["mob"]["def"]) and String(sp["zone"]) == zone:
					r = sp["area"]
			if r.is_empty():
				var z := zone_by_id(zone)
				r = [int(z["x0"]), int(z["y0"]), int(z["x1"]), int(z["y1"])]
			p = _pick_free(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
			e["mob"]["home_x"] = p.x
			e["mob"]["home_y"] = p.y
		e["x"] = p.x
		e["y"] = p.y
		e["tx"] = p.x
		e["ty"] = p.y
		e.erase("path")


# JSON 讀返嚟數字全部係 float；整數值轉返 int
static func _intify(v: Variant) -> Variant:
	if v is float:
		return int(v) if v == floor(v) else v
	if v is Dictionary:
		var o := {}
		for k in v:
			o[k] = _intify(v[k])
		return o
	if v is Array:
		var a := []
		for x in v:
			a.append(_intify(x))
		return a
	return v
