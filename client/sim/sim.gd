class_name Sim
extends "res://sim/sim_war_beast.gd"
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


# 城內安全區自動回復 (S01a, spec 01 §4)【自訂】: 每 regen.ticks tick 回 max(hp/mp/sp) × regen.pct；野外唔回
# S07c: 戰騎「聖體」友好技 → 回復倍率 ×2 (_friend_regen_mult)
func _safe_regen_tick() -> void:
	var cfg: Dictionary = data.world["regen"]
	if tick % int(cfg["ticks"]) != 0:
		return
	var base_pct: float = float(cfg["pct"])
	for e in ents.values():
		if not e.has("ch") or int(e["hp"]) <= 0:
			continue
		if not is_safe(int(e["x"]), int(e["y"])):
			continue
		var pct: float = base_pct * _friend_regen_mult(e)
		var ch: Dictionary = e["ch"]
		var lv := int(ch["level"])
		ch["hp"] = mini(RulesStats.max_hp(lv, ch["attrs"]), int(ch["hp"]) + maxi(1, MathX.js_round(RulesStats.max_hp(lv, ch["attrs"]) * pct)))
		ch["mp"] = mini(RulesStats.max_mp(lv, ch["attrs"]), int(ch["mp"]) + maxi(1, MathX.js_round(RulesStats.max_mp(lv, ch["attrs"]) * pct)))
		ch["sp"] = mini(RulesStats.max_sp(lv, ch["attrs"]), int(ch["sp"]) + maxi(1, MathX.js_round(RulesStats.max_sp(lv, ch["attrs"]) * pct)))
		_sync_stats(e)


# S03b 城門衛兵 (spec 03 §5): 殺人魔 (tier 6) 喺城內/安全區 → 衛兵警告「唔准入城」+ 發 guard_warn 事件
# （單機連續地圖，城內冇硬閂；用「城內服務拒絶 + 定期警告」代表「拒入城」，見 status/log。定時節流。）
func _city_guard_check() -> void:
	var pid := int(state["player_id"])
	var p := ent(pid)
	if p.is_empty() or not p.has("ch") or int(p["hp"]) <= 0:
		return
	var karma := int(p["ch"]["karma"])
	if not RulesKarma.city_banned(karma):
		return
	if not is_safe(int(p["x"]), int(p["y"])):
		return
	var ch: Dictionary = p["ch"]
	var last: int = int(ch.get("lastGuardWarn", -99999))
	# S08b：城池「防禦」屬性影響衛兵警告間隔（城牆越好 → 衛兵越密）
	var map_city := String(data.map_by_id.get(map_id_at(int(p["x"]), int(p["y"])), {}).get("city", ""))
	# S08g 法令：冇僱護衛（guard 關）→ 冇衛兵攔路（未佔城 = 照舊）
	if not law_allows(map_city, "guard"):
		return
	var ticks := RulesCity.guard_warn_ticks(city_attrs(map_city), int(data.world["bots"].get("guardWarnTicks", 120)), _city_attr_cfg())
	if tick - last < ticks:
		return
	ch["lastGuardWarn"] = tick
	_emit({"k": "guard_warn", "dst": pid, "name": str(p["name"]), "karma": karma, "text": RulesKarma.guard_warn_text(karma)})


# 每日子時: 天災擲骰 -> 市場日結 -> 通知 UI
func _daily_hook(day: int) -> void:
	var disas: Array = state["disasters"]
	RulesDisaster.expire(disas, day)
	var season := RulesClock.season_of_day(day, int(data.world["clock"]["seasonDays"]))
	var changed: Array = []
	for c in data.world["cities"]:
		var d := RulesDisaster.roll_day(rng_fn, day, season, String(c.id), data.world["disasters"], data.world.get("shopShutdown", {}))
		if not d.is_empty():
			disas.append(d)
			changed.append(d)
	_market_daily(season)
	_storage_daily()
	_ap_daily()
	_salary_daily(day)           # 每月初一俸祿 (Step 14)
	_title_contest_daily(day)    # S08d 每月初一頭銜名額競爭 (spec 08 §2)
	_eval_daily(day)             # S08f 每月初一義勇軍績效 → 功績 (spec 08 §4)
	_morale_daily(day)           # S08g 每月初一民心評比（稅率 → 民心 −4 / 人口流失）
	_militia_quest_reset(day)    # S08f 團體任務每月/每日重複 (清 S06c 延後)
	_recruit_daily(day)          # 同伴到期/忠誠低離開 (Step 13.5)
	_rumor_daily(day)            # S09b 傳聞擴散: 每日反思/鄰居交換 + 跨城延遲 (spec 09 §4)
	_llm_reflect_daily(day)      # S09d LLM 每日反思摘要 (spec 09 §5)
	_comm_daily(day)             # 居民委託過期 (Step 16)
	_mount_daily(day)            # 座騎子時結算 (Step 17a)
	_auction_daily(day)          # S07d NPC 拍賣場換貨 (spec 07 §9)
	_chest_daily(day)            # T-07 隨機寶箱每日子時更新位置 (spec 02 §6)
	# S04d: 特殊場景開門日公告（game 日曆窗口）
	var md := int(data.world["clock"].get("monthDays", 30))
	var mdow := RulesScene.day_of_month(day, md)
	for s in data.scenes:
		if RulesScene.is_open(s, day, md) and int(s.get("lastAnnounceDay", -1)) != mdow:
			s["lastAnnounceDay"] = mdow
			_emit({"k": "scene_open", "name": String(s["name"]), "minLevel": int(s.get("minLevel", 1)),
				"openDays": RulesScene.open_days_text(s)})
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
		var sm := RulesMarket.supply_mods(season, cfg["seasonSupply"], city_dis, _city_with_attrs(c))
		var dm := RulesMarket.demand_mods(season, cfg["seasonDemand"])
		# S08g 民心 → 市場 prod 乘數（未佔城 = morale 100 → ×1.0，零改變）
		var mm := RulesCivic.prod_mult(city_morale(String(c.id)), _civic_cfg())
		if not is_equal_approx(mm, 1.0):
			for k in sm:
				sm[k] = float(sm[k]) * mm
		RulesMarket.daily(_city_with_attrs(c), state["market"][c.id], cfg, sm, dm, _city_attr_cfg())


# 入夜: 補夜怪；天光: 夜怪消失
func _sync_night_spawns() -> void:
	if not bool(_clock()["is_night"]):
		var gone: Array = []
		for e in ents.values():
			if e["kind"] == "mob" and data.mob_def(int(e["mob"]["def"])).get("night", false):
				gone.append(int(e["id"]))
		_remove_ents(gone)
		return
	var have := {}                  # def -> 現有隻數 (數一次，補完再加)
	for e in ents.values():
		if e["kind"] == "mob":
			var k := int(e["mob"]["def"])
			have[k] = int(have.get(k, 0)) + 1
	for sp in data.spawns:
		if not sp.get("night", false):
			continue
		var def_id := int(sp["monster"])
		for i in int(sp["count"]) - int(have.get(def_id, 0)):
			if _spawn_mob(def_id, String(sp.get("zone", DEFAULT_ZONE))) == null:
				break
			have[def_id] = int(have.get(def_id, 0)) + 1


# 每 tick: 時鐘 -> 日結(天災/市場) -> 夜怪 -> 機械人思考 -> 戰鬥/AI -> 重生 -> 移動 (一格)
func step() -> void:
	state["tick"] = tick + 1
	_advance_clock()
	BotSys.think(self)
	_recruit_tick()             # 擂台勝負 (Step 13.5)
	_player_down_tick()         # 玩家倒地逾時未救 → 強制回城復活【自訂新增】
	_office_tick()              # 官令護衛/救援 NPC 死咗 → 自動失敗 (S06a)
	_mount_tick()               # 放牧返嚟 (Step 17a)
	_beast_tick()               # 戰騎出戰實體同步/回復 (S07b)
	_beast_orphans()            # 戰騎無主實體清理 (S07b)
	_tiandi_auto_loot_tick()    # 天地商行訂閱者自動拾取地面掉落物 (U16)
	_safe_regen_tick()          # 城內安全區自動回復 (S01a, spec 01 §4)
	_city_guard_check()         # S03b: 殺人魔喺城內/安全區 → 城門衛兵警告 (拒入城)
	_expire_drops()             # S04a: 過期地面掉落物消失
	for id in ents.keys():
		var e: Dictionary = ents.get(id, {})
		if e.is_empty():
			continue
		if e["kind"] == "mob":
			_think_mob(e)
		elif e["kind"] == "beast":
			_think_beast(e)         # 戰騎: 跟主人/自動攻擊/戰鬥特技 (S07b)
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
		if e.has("ch"):
			mv = _ride_steps(e)       # 騎馬: 移速 ×1.5~2 (Step 17a, spec 07 §7)
		if e["kind"] == "bot" and (bool(e.get("fleePk", false)) or bool(e.get("huntedByGuard", false))) and tick % 2 == 1:
			mv = 0                    # 打人模式/S03a 逃跑 + 捕快追緊嘅紅名: 行慢啲 (2 tick 行 1 格)，等玩家/捕快追得返 (spec 03 §3 + 自訂)
		mv = _walk_scale(e, mv)      # 全體步行速度 ×walkStepRate (預設 0.5 = 慢一半)，小數累積喺 e.mvAcc
		var moved := false
		var moved_n := 0
		for _k in mv:
			if _k > 0 and data.portal_at.has(int(e["y"]) * W + int(e["x"])):
				break                  # 一 tick 行多格 (騎馬) 踩中傳送點就停，唔好跨過咗
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
					moved_n += 1
					continue
				e.erase("path")
			var n := _greedy_step(int(e["x"]), int(e["y"]), int(e["tx"]), int(e["ty"]))
			if n.x != int(e["x"]) or n.y != int(e["y"]):
				e["x"] = n.x
				e["y"] = n.y
				moved = true
				moved_n += 1
		if moved:
			_ride_moved(e, moved_n)
			_on_moved(e)


# 天文專長 lv≥1 + 帶渾天儀(26029): 各城池現時天氣/天災情報 (S01c, spec 01 §8)
const WEATHER_ITEM := 26029

func view_weather() -> Array:
	var ch := player_ch()
	if ch.is_empty() or not RulesExpert.weather_unlocked(expert_lv(ch, "tianwen")) or not RulesShop.has_item(ch.get("bag", []), WEATHER_ITEM, 1):
		return []
	var season := RulesClock.season_of_day(int(_clock()["day"]), int(data.world["clock"]["seasonDays"]))
	var out: Array = []
	for c in data.world["cities"]:
		var d := {}
		for x in state["disasters"]:
			if String(x["city"]) == String(c.id):
				d = x
				break
		out.append({"city": String(c.id), "name": String(c.get("name", c.id)), "season": season, "disaster": (String(d.get("name", "")) if not d.is_empty() else "")})
	return out


# 城際價差 (spec 05 §6【自訂】): 幾件代表物資喺各城依家市價，俾地圖面板「市價」頁顯示
const MARKET_REP_ITEMS := [25064, 25053, 25001, 29021, 29043]   # 蕃薯/木頭/石頭/宮保雞丁/回血草

func view_market_prices() -> Array:
	var out: Array = []
	for c in data.world["cities"]:
		var row := {"city": String(c.id), "name": String(c.get("name", c.id)), "items": []}
		for iid in MARKET_REP_ITEMS:
			var cat := str(int(data.cats.get(iid, 0)))
			var g := market_city(String(c.id), cat)
			var pf := float(g.get("pf", 1.0)) if not g.is_empty() else 1.0
			var price := int(round(float(data.prices.get(iid, 0.0)) * pf))
			(row["items"] as Array).append({"id": iid, "name": String(data.names.get(iid, str(iid))), "price": price})
		out.append(row)
	return out


# 地理專長 lv≥1: 小地圖顯示全部設施 (唔止傳送點)；UI 讀呢個 gate 小地圖畫法 (spec 01 §8)
func geo_unlocked() -> bool:
	var ch := player_ch()
	return not ch.is_empty() and RulesExpert.geo_unlocked(expert_lv(ch, "dili"))


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
		# S04b 吟唱線索: 透出術法怪/boss 吟唱中嘅彈道落點 + 術（UI 畫紅圈）
		var csx := 0
		var csy := 0
		var csp := ""
		var cprog := 0.0
		if e.has("casting"):
			var cs: Dictionary = e["casting"]
			csp = str(cs.get("spell", ""))
			cprog = clampf(float(tick - int(cs.get("start", tick))) / maxf(1.0, float(int(cs.get("done_at", tick)) - int(cs.get("start", tick)))), 0.0, 1.0)
			csx = int(cs.get("x", int(e["x"])))
			csy = int(cs.get("y", int(e["y"])))
		var o: Dictionary = {"id": e["id"], "name": e["name"], "x": e["x"], "y": e["y"], "face": e["face"],
			"bot": e["kind"] == "bot", "gen": e["kind"] == "gen", "hp": e["hp"], "maxHp": e["max_hp"], "level": e["level"], "mob": e["kind"] == "mob",
			"criminal": bool(e.get("ch", {}).get("criminal", false)),
			"atkTarget": int(e.get("atk_target", 0)),   # 打人模式: 居民鎖定緊邊個玩家 (bot_sys._crime_find_player)
			"resident": bool(e.get("ch", {}).get("resident", false)),
			"role": String(e.get("ch", {}).get("role", "")),
			"statuses": st_vis, "casting": e.has("casting"), "castX": csx, "castY": csy, "castSpell": csp, "castProg": cprog,
			"aggro": int(e["mob"]["target"]) if e["kind"] == "mob" and e["mob"]["state"] == "chase" else 0}   # 怪追緊邊個
		if e["kind"] == "dropped":
			o["dropped"] = true
			o["dropItems"] = e["drop"]["items"]
		out.append(o)
	return out


func save_string() -> String:
	return JSON.stringify(_canonical({"state": state, "rng": rng.s}))


# S09a 居民 read-model: role/性格/理念/homeCity/homeZone/當前時辰活動。非居民 = {}
func resident_view(id: int) -> Dictionary:
	var e := ent(id)
	var ch: Dictionary = e.get("ch", {})
	if not bool(ch.get("resident", false)):
		return {}
	var shi := RulesClock.shichen_of_ke(int(_clock()["ke"]))
	var role := String(ch.get("role", ""))
	return {"role": role, "roleName": RulesResident.role_name(data.residents, role),
		"personality": ch.get("personality", {}), "ideology": String(ch.get("ideology", "")),
		"align": String(ch.get("align", "good")), "homeCity": String(ch.get("homeCity", "")),
		"homeZone": String(ch.get("homeZone", "")), "shichen": shi,
		"activity": RulesResident.activity_at(data.residents, shi)}


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
			for k in ["birthMonth", "birthDay", "lilian"]:   # F2/F8: 生日、歷練欄位已取消，舊檔清走
				e["ch"].erase(k)
			var oc: Dictionary = e["ch"]                     # F1: 舊檔自訂稱號當已解鎖
			if not oc.has("titles") and String(oc.get("title", "")) != "":
				oc["titles"] = [String(oc["title"])]
	sim._ensure_city_attrs()                # 舊存檔城池屬性兼容 (S08b)
	sim._ensure_rumors()                    # 舊存檔傳聞欄兼容 (S09b)
	sim._ensure_llm()                       # 舊存檔 LLM 狀態欄兼容 (S09d)
	sim._ensure_marry()                     # 舊存檔結婚狀態欄兼容 (S09e)
	sim._fix_positions()
	return sim


# 舊存檔 (地圖改版前, spec 12) 單位可能企喺牆/樹/虛空: 人搬返客棧、怪喺自己 spawn 範圍重揀位
func _fix_positions() -> void:
	for e in ents.values():
		if e["kind"] == "dropped":
			continue                        # 地面掉落物唔搬位 (跌出位本身行得)
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


# 步行速度縮放 (UAT 用家 confirm: 玩家/NPC/同伴/怪物全體慢一半)；騎乘倍數喺 mv 內已計，呢度統一乘 rate。
# 小數步數累積入 e.mvAcc (決定性，冇 RNG)。walkStepRate=1 = 唔縮放。
func _walk_scale(e: Dictionary, mv: int) -> int:
	var rate := float(data.world.get("walkStepRate", 1.0))
	if rate >= 1.0 or mv <= 0:
		return mv
	var acc := float(e.get("mvAcc", 0.0)) + float(mv) * rate
	var n := int(floor(acc + 0.0001))
	e["mvAcc"] = acc - float(n)
	return n
