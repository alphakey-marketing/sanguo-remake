class_name BotSys
extends RefCounted
# 居民 NPC (Step 5.1 升級自機械人): 有角色、理念、記憶表，會去野區打怪、血低返客棧休息、間中講嘢。
# Tier3(路人) 用純規則行動；理念/記憶為 Step 6 LLM 層鋪路，今步只由規則寫入/讀出。

const NAMES := ["黃權", "張繡", "趙雲", "關平", "周倉", "徐庶", "龐統", "法正", "馬岱", "王平", "姜維", "魏延"]
const LINES := ["有冇人組隊?", "呢度啲怪好肥", "小心野豬", "我去練功", "升級喇!", "客棧休息好抵", "有刀賣未?", "三國萬歲"]
const IDEOLOGIES := ["義理", "霸權", "權謀", "隱遁", "治國"]         # 【原】五角理念關係，Step 8 登用會用到

# 目擊/交流權重【自訂】: 幾件初步事件先，Step 5.3 先接善惡反應
const W_GREET := 2            # 玩家打招呼 (chat 喺附近)
const W_SEE_KILL := 1         # 目擊玩家打怪 (中性偏正面，佩服)
const W_SEE_DIE := 2          # 目擊玩家陣亡 (善 NPC 同情好感 +2, spec 03 §4.3)
const W_KILL_NPC := -4        # 目擊玩家殺善居民 (大惡: NpcMemory 好感大跌, Spec 09/S03b 用)
const W_KILL_RED := 2         # 目擊玩家殺紅名(殺人魔): 除害 (正面)


# 新居民入場: 派理念 + 開一張記憶表 (供 sim.add_bots / 測試用)
static func init_identity(e: Dictionary, rng: SimRng) -> void:
	e["ch"]["ideology"] = IDEOLOGIES[rng.below(IDEOLOGIES.size())]
	e["mem"] = NpcMemory.init_memory()


# S09a: bot → 居民。派身份 (性格/理念/role/善惡/homeCity/homeZone) + 記憶表。
# city_id/home_zone 由 sim.add_residents 用 residents.json 傳入；legacy add_bots 唔會叫呢個。
static func init_resident(e: Dictionary, rng: SimRng, residents: Dictionary, city_id: String, home_zone: String) -> void:
	var ch: Dictionary = e["ch"]
	ch["ideology"] = RulesResident.ideology_at(residents, rng.below(maxi(1, RulesResident.ideologies(residents).size())))
	ch["resident"] = true
	var role := RulesResident.pick_role(residents, rng.below(RulesResident.role_total(residents)))
	ch["role"] = String(role.get("id", "villager"))
	ch["align"] = String(role.get("align", "good"))
	ch["homeCity"] = city_id
	ch["homeZone"] = home_zone
	var dims := RulesResident.personality_dims(residents)
	var maxv := int(RulesResident.cfg(residents).get("personalityMax", 10))
	var rolls: Array = []
	for _i in dims.size():
		rolls.append(rng.below(maxv + 1))
	ch["personality"] = RulesResident.personality(dims, rolls, maxv)
	e["mem"] = NpcMemory.init_memory()


# 捕快入場【自訂】: 派 role/homeCity/企定位 + 開一張記憶表。等級/屬性由 sim._bump_level 另設。
static func init_guard(e: Dictionary, city_id: String, stand: Vector2i, home_zone: String = "") -> void:
	var ch: Dictionary = e["ch"]
	ch["role"] = "constable"
	ch["align"] = "good"
	ch["homeCity"] = city_id
	ch["homeZone"] = home_zone if home_zone != "" else Sim.DEFAULT_ZONE    # 巡邏野區 (同居民一樣: 自己城最近野區)
	ch["standPos"] = {"x": stand.x, "y": stand.y}
	ch["patrolStep"] = 0
	e["mem"] = NpcMemory.init_memory()


# 捕快行為【自訂】: 見紅名(罪犯居民/殺人魔玩家)喺 aggroRange 內 -> 鎖定 atk_target (由 _think_player 追擊出手)；
# 冇紅名: 巡邏時辰內喺企定位附近循環巡邏，其餘時辰返企定位企定 (唔郁)。
# bots_by_map: think() 每 tick 分好嘅 {map_index: [bot id]}，避免逐個捕快逐 tick 掃成個 sim.state["bots"]（效能）。
static func _constable_tick(sim, id: int, e: Dictionary, bots_by_map: Dictionary) -> void:
	var ch: Dictionary = e["ch"]
	if int(e["atk_target"]) != 0:
		var t: Dictionary = sim.ent(int(e["atk_target"]))
		if not t.is_empty() and t.has("ch") and int(t["hp"]) > 0 and String(t.get("kind", "")) == "bot":
			t["huntedByGuard"] = true    # 持續標記俾追緊嘅紅名 NPC 行慢啲 (等捕快追得到, 自訂)
		return                                       # 追緊 -> 交返 _think_player 出手
	var g: Dictionary = RulesGuard.cfg(sim.data.guards)
	var map_k: int = sim.data.map_index(int(e["x"]), int(e["y"]))
	var pid := int(sim.state["player_id"])
	var pe: Dictionary = sim.ent(pid)
	if not pe.is_empty() and pe.has("ch") and int(pe["hp"]) > 0 \
			and sim.data.map_index(int(pe["x"]), int(pe["y"])) == map_k \
			and RulesGuard.is_red_target(pe["ch"], true) \
			and not sim.is_safe(int(pe["x"]), int(pe["y"])) and not sim.is_safe(int(e["x"]), int(e["y"])) \
			and RulesGuard.in_aggro_range(int(e["x"]), int(e["y"]), int(pe["x"]), int(pe["y"]), g):
		e["atk_target"] = pid
		return
	for bid in bots_by_map.get(map_k, []):
		if int(bid) == id:
			continue
		var be: Dictionary = sim.ent(int(bid))
		if be.is_empty() or not be.has("ch") or int(be["hp"]) <= 0:
			continue
		if not RulesGuard.is_red_target(be["ch"], false):
			continue
		if sim.is_safe(int(be["x"]), int(be["y"])) or sim.is_safe(int(e["x"]), int(e["y"])):
			continue                                     # 城內唔打人: 紅名喺城入面唔追，等佢出野外
		if RulesGuard.in_aggro_range(int(e["x"]), int(e["y"]), int(be["x"]), int(be["y"]), g):
			e["atk_target"] = int(bid)
			be["huntedByGuard"] = true
			return
	var sp: Dictionary = ch.get("standPos", {})
	var stand := Vector2i(int(sp.get("x", int(e["x"]))), int(sp.get("y", int(e["y"]))))
	var shi := RulesClock.shichen_of_ke(int(sim._clock()["ke"]))
	if RulesGuard.is_patrol_time(g, shi):
		# 巡邏喺城外野區: 唔喺野區就經門口出城；到咗野區循環行 4 個方向點 (紅名喺野外先打，城內唔郁手)
		var zone_id := String(ch.get("homeZone", Sim.DEFAULT_ZONE))
		var z: Dictionary = sim.zone_by_id(zone_id)
		if z.is_empty():
			return
		if sim._route_to_map(e, zone_id):
			return
		if int(e["x"]) == int(e["tx"]) and int(e["y"]) == int(e["ty"]):
			var centre := Vector2i((int(z["x0"]) + int(z["x1"])) / 2, (int(z["y0"]) + int(z["y1"])) / 2)
			var step := int(ch.get("patrolStep", 0))
			var pt := RulesGuard.patrol_point(centre, int(g.get("patrolRadius", 6)), step)
			pt.x = clampi(pt.x, int(z["x0"]), int(z["x1"]) - 1)
			pt.y = clampi(pt.y, int(z["y0"]), int(z["y1"]) - 1)
			ch["patrolStep"] = step + 1
			sim.cmd_move(id, pt.x, pt.y)
	else:
		var cmap: String = sim.resident_city_map_id(String(ch.get("homeCity", "")))
		if cmap != "" and sim.map_id_at(int(e["x"]), int(e["y"])) != cmap:
			sim._route_to_map(e, cmap)                   # 非巡邏時辰: 返城
		elif int(e["x"]) != stand.x or int(e["y"]) != stand.y:
			sim.cmd_move(id, stand.x, stand.y)


static func think(sim) -> void:
	var bc: Dictionary = sim.data.world["bots"]
	var mobs_by_map := {}              # 地圖 index -> [mob]，每 tick 分組一次 (次序 = ents 插入次序)
	for m in sim.ents.values():
		if m["kind"] == "mob":
			var k: int = sim.data.map_index(int(m["x"]), int(m["y"]))
			if not mobs_by_map.has(k):
				mobs_by_map[k] = []
			mobs_by_map[k].append(m)
	var bots_by_map := {}              # 地圖 index -> [bot id]，每 tick 分組一次，畀捕快揾紅名用 (自訂，避免逐 tick 掃全部 bots)
	for bid in sim.state["bots"]:
		var be: Dictionary = sim.ent(int(bid))
		if be.is_empty():
			continue
		var bk: int = sim.data.map_index(int(be["x"]), int(be["y"]))
		if not bots_by_map.has(bk):
			bots_by_map[bk] = []
		bots_by_map[bk].append(int(bid))
	var dead: Array = []
	for id in sim.state["bots"]:
		var e: Dictionary = sim.ent(id)
		if e.is_empty() or not e.has("ch"):
			continue
		var ch: Dictionary = e["ch"]
		if bool(ch.get("fleePk", false)):          # S03a: 被襲逃跑叫衛兵
			_pk_flee(sim, id, e, dead)
			continue
		if String(ch.get("role", "")) == "constable":   # 捕快: 見紅名主動打, 否則巡邏/企定位
			_constable_tick(sim, id, e, bots_by_map)
			continue
		if bool(ch.get("criminal", false)) and _crime_find_player(sim, e):   # S03a: 紅名(殺人魔)主動襲擊玩家
			continue                                  # (atk_target 已鎖定, 下方 _think_player 出手)
		if sim.rng.next() < float(bc["chatChance"]):
			sim.cmd_chat(id, LINES[sim.rng.below(LINES.size())])
		var low: bool = int(e["hp"]) < RulesStats.max_hp(int(ch["level"]), ch["attrs"], ch) * float(bc["lowHpPct"])
		var zone_id := String(ch.get("homeZone", Sim.DEFAULT_ZONE))    # S09a: 居民屬自己城最近野區；legacy = 預設
		var inn: Vector2i = sim.resident_inn_pos(e)      # S09a: 居民返自己城客棧 (冇 = 唔撤退)
		if low and inn.x >= 0:                          # 血低: 撤退返客棧休息 (跨圖就經門口行, spec 12 §4)
			var near_inn := maxi(absi(int(e["x"]) - inn.x), absi(int(e["y"]) - inn.y)) <= Sim.NEAR
			e["atk_target"] = 0
			if sim._route_to_map(e, sim.map_id_at(inn.x, inn.y)):
				continue
			if near_inn:
				var cost := int(sim.data.inn["restCost"])
				if int(ch["gold"]) < cost:
					ch["gold"] = int(ch["gold"]) + cost      # 窮機械人有免費住宿
				sim.cmd_rest(id)
			else:
				sim.cmd_move(id, inn.x, inn.y)
			continue
		if int(e["atk_target"]) != 0:                  # 戰鬥中
			continue
		# 居民日程 (S09a, spec 09 §1): in-town 活動 (cfg.inTownActivities: eat/home/sleep) → 留城內行街/休息，唔出野區；
		# work → 落下方野外練功邏輯。血低返客棧 (上方) 任何時辰都優先。
		if RulesResident.stays_in_town(sim.data.residents, String(ch.get("role", "")), RulesResident.activity_at(sim.data.residents, RulesClock.shichen_of_ke(int(sim._clock()["ke"])))):
			var cmap: String = sim.resident_city_map_id(String(ch.get("homeCity", "")))
			if cmap != "" and sim.map_id_at(int(e["x"]), int(e["y"])) != cmap:
				sim._route_to_map(e, cmap)          # 唔喺自己城: 返城
			elif cmap != "" and int(e["x"]) == int(e["tx"]) and int(e["y"]) == int(e["ty"]) and sim.rng.next() < float(bc["wanderChance"]):
				var rz: Dictionary = sim.zone_by_id(cmap)      # 城內行街: 去城內隨機安全點
				if not rz.is_empty():
					var rxc := int(rz.get("x0", 0))
					var ryc := int(rz.get("y0", 0))
					var rw := maxi(1, int(rz.get("x1", 0)) - rxc)
					var rh := maxi(1, int(rz.get("y1", 0)) - ryc)
					for _t in 8:
						var nx: int = rxc + int(sim.rng.below(rw))
						var ny: int = ryc + int(sim.rng.below(rh))
						if sim.is_free(nx, ny) and sim.is_safe(nx, ny):
							sim.cmd_move(id, nx, ny)
							break
			continue
		# 揀附近最近嘅怪 (等級唔好高過自己太多；只揀同一張地圖)
		var best := 0
		var best_d := 1 << 30
		for m in mobs_by_map.get(sim.data.map_index(int(e["x"]), int(e["y"])), []):
			if int(m["level"]) > int(ch["level"]) + int(bc["maxLvAbove"]) or m["mob"].has("arena"):
				continue
			var d := maxi(absi(int(m["x"]) - int(e["x"])), absi(int(m["y"]) - int(e["y"])))
			if d > int(bc["seekRange"]) or d >= best_d:
				continue
			best = int(m["id"])
			best_d = d
		if best != 0:
			sim.cmd_attack(id, best)
			continue
		if sim._route_to_map(e, zone_id):    # 唔喺野區: 經門口出城 (居民去自己城最近嘅野區)
			continue
		if int(e["x"]) == int(e["tx"]) and int(e["y"]) == int(e["ty"]) and sim.rng.next() < float(bc["wanderChance"]):    # 冇怪: 喺野區行吓
			var z: Dictionary = sim.zone_by_id(zone_id)
			if z.is_empty():
				continue
			sim.cmd_move(id, int(z["x0"]) + sim.rng.below(int(z["x1"]) - int(z["x0"])), int(z["y0"]) + sim.rng.below(int(z["y1"]) - int(z["y0"])))
	for did in dead:                                  # 打完循環先清已經走去叫衛兵嘅居民 (避免中途改行緊嘅 list)
		sim.state["bots"].erase(int(did))


# S03a: 紅名(殺人魔)居民主動襲擊附近玩家 -> 鎖定 atk_target (畀玩家自衛反殺 = 反擊 +100 / 除害 +300)。
# 潛行玩家唔會被發現 (同主動怪一致)。
static func _crime_find_player(sim, e: Dictionary) -> bool:
	var pid := int(sim.state["player_id"])
	var pe: Dictionary = sim.ent(pid)
	if pe.is_empty() or not pe.has("ch") or int(pe["hp"]) <= 0:
		return false
	# 安全區 PK 禁令 (spec 03 §3): 衛兵/城內冇得打交 —— 紅名(殺人魔)喺城入面都唔可以襲擊玩家；
	# 要出到野外先會主動鎖定玩家 (玩家喺安全區 = 居民主動襲擊都禁，叫你入城避難)。
	if sim.is_safe(int(e["x"]), int(e["y"])) or sim.is_safe(int(pe["x"]), int(pe["y"])):
		return false
	if RulesSpell.has(pe["ch"].get("status", {}), "stealth", sim.tick):
		return false
	var d := maxi(absi(int(e["x"]) - int(pe["x"])), absi(int(e["y"]) - int(pe["y"])))
	if d <= int(sim.data.world["bots"]["crimeAggro"]):
		e["atk_target"] = pid
		return true
	return false


# S03a: 被襲選擇逃跑嘅居民 -> 走去客棧/安全區叫衛兵，到埗就消失 + 發 guard_alert (S03b 城門衛兵拒入接)。
# dead: 要喺 think 循環完先由 sim.state["bots"] 移除嘅 id 集合。
static func _pk_flee(sim, id: int, e: Dictionary, dead: Array) -> void:
	var inn: Vector2i = sim.inn_pos
	var near_inn := maxi(absi(int(e["x"]) - inn.x), absi(int(e["y"]) - inn.y)) <= Sim.NEAR
	if near_inn or sim.is_safe(int(e["x"]), int(e["y"])):
		var agg := int(e.get("aggressor", 0))
		if agg != 0:
			var pe: Dictionary = sim.ent(agg)
			if not pe.is_empty() and pe.has("ch"):
				sim._msg(agg, "%s跑去叫衛兵！" % str(e["name"]))
				sim.event_emitted.emit({"k": "guard_alert", "src": int(e["id"]), "dst": agg, "name": str(e["name"])})
		sim._remove_ent(id)
		dead.append(id)
		return
	if sim._route_to_map(e, sim.map_id_at(inn.x, inn.y)):
		return
	sim.cmd_move(id, inn.x, inn.y)
