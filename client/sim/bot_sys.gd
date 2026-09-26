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


# 新居民入場: 派理念 + 開一張記憶表 (供 sim.add_bots 用)
static func init_identity(e: Dictionary, rng: SimRng) -> void:
	e["ch"]["ideology"] = IDEOLOGIES[rng.below(IDEOLOGIES.size())]
	e["mem"] = NpcMemory.init_memory()


static func think(sim) -> void:
	var bc: Dictionary = sim.data.world["bots"]
	var mobs_by_map := {}              # 地圖 index -> [mob]，每 tick 分組一次 (次序 = ents 插入次序)
	for m in sim.ents.values():
		if m["kind"] == "mob":
			var k: int = sim.data.map_index(int(m["x"]), int(m["y"]))
			if not mobs_by_map.has(k):
				mobs_by_map[k] = []
			mobs_by_map[k].append(m)
	var dead: Array = []
	for id in sim.state["bots"]:
		var e: Dictionary = sim.ent(id)
		if e.is_empty() or not e.has("ch"):
			continue
		var ch: Dictionary = e["ch"]
		if bool(ch.get("fleePk", false)):          # S03a: 被襲逃跑叫衛兵
			_pk_flee(sim, id, e, dead)
			continue
		if bool(ch.get("criminal", false)) and _crime_find_player(sim, e):   # S03a: 紅名(殺人魔)主動襲擊玩家
			continue                                  # (atk_target 已鎖定, 下方 _think_player 出手)
		if sim.rng.next() < float(bc["chatChance"]):
			sim.cmd_chat(id, LINES[sim.rng.below(LINES.size())])
		var low: bool = int(e["hp"]) < RulesStats.max_hp(int(ch["level"]), ch["attrs"]) * float(bc["lowHpPct"])
		var inn: Vector2i = sim.inn_pos
		var near_inn := maxi(absi(int(e["x"]) - inn.x), absi(int(e["y"]) - inn.y)) <= Sim.NEAR
		if low:                                        # 血低: 撤退返客棧休息 (跨圖就經門口行, spec 12 §4)
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
		if sim._route_to_map(e, Sim.DEFAULT_ZONE):    # 唔喺野區: 經門口出城
			continue
		if int(e["x"]) == int(e["tx"]) and int(e["y"]) == int(e["ty"]) and sim.rng.next() < float(bc["wanderChance"]):    # 冇怪: 喺野區行吓
			var z: Dictionary = sim.zone_by_id(Sim.DEFAULT_ZONE)
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
