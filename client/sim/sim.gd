class_name Sim
extends "res://sim/sim_ai.gd"
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
				if not e.is_empty() and e["kind"] == "mob" and data.monsters[int(e["mob"]["def"])].get("night", false):
					ents.erase(id0)
					for e2 in ents.values():
						if int(e2["atk_target"]) == int(id0):
							e2["atk_target"] = 0


# 每 tick: 時鐘 -> 日結(天災/市場) -> 夜怪 -> 機械人思考 -> 戰鬥/AI -> 重生 -> 移動 (一格)
func step() -> void:
	state["tick"] = tick + 1
	_advance_clock()
	BotSys.think(self)
	for id in ents.keys():
		var e: Dictionary = ents.get(id, {})
		if e.is_empty():
			continue
		if e["kind"] == "mob":
			_think_mob(e)
		elif e.has("ch"):
			_think_player(e)
	var rs: Array = state["respawns"]
	for i in range(rs.size() - 1, -1, -1):
		if tick >= int(rs[i]["at"]):
			_spawn_mob(int(rs[i]["def"]), String(rs[i].get("zone", DEFAULT_ZONE)))     # 夜怪喺白天唔重生，天黑由 _sync_night_spawns 補
			rs.remove_at(i)
	for e in ents.values():
		# 逃跑怪 sprint: tick%2=0 嗰陣郁兩格 → 平均 1.5× 移速 (spec 04 §3)
		var mv := 2 if (e["kind"] == "mob" and (e.get("mob", {}) as Dictionary).get("state", "") == "flee" and tick % 2 == 0) else 1
		for _k in mv:
			var dx := signi(int(e["tx"]) - int(e["x"]))
			var dy := signi(int(e["ty"]) - int(e["y"]))
			if dx != 0 and is_free(int(e["x"]) + dx, int(e["y"])):
				e["x"] = int(e["x"]) + dx
			elif dy != 0 and is_free(int(e["x"]), int(e["y"]) + dy):
				e["y"] = int(e["y"]) + dy


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
			"bot": e["kind"] == "bot", "hp": e["hp"], "maxHp": e["max_hp"], "level": e["level"], "mob": e["kind"] == "mob",
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
	return sim


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
