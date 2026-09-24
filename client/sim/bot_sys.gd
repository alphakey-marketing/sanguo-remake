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


# 新居民入場: 派理念 + 開一張記憶表 (供 sim.add_bots 用)
static func init_identity(e: Dictionary, rng: SimRng) -> void:
	e["ch"]["ideology"] = IDEOLOGIES[rng.below(IDEOLOGIES.size())]
	e["mem"] = NpcMemory.init_memory()


static func think(sim) -> void:
	for id in sim.state["bots"]:
		var e: Dictionary = sim.ent(id)
		if e.is_empty() or not e.has("ch"):
			continue
		var ch: Dictionary = e["ch"]
		if sim.rng.next() < 0.002:
			sim.cmd_chat(id, LINES[sim.rng.below(LINES.size())])
		var low: bool = int(e["hp"]) < RulesStats.max_hp(int(ch["level"]), ch["attrs"]) * 0.4
		var inn: Vector2i = sim.inn_pos
		var near_inn := maxi(absi(int(e["x"]) - inn.x), absi(int(e["y"]) - inn.y)) <= 3
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
		var my_map: String = sim.map_id_at(int(e["x"]), int(e["y"]))
		var best := 0
		var best_d := 1 << 30
		for m in sim.ents.values():
			if m["kind"] != "mob" or int(m["level"]) > int(ch["level"]) + 2 or m["mob"].has("arena"):
				continue
			var d := maxi(absi(int(m["x"]) - int(e["x"])), absi(int(m["y"]) - int(e["y"])))
			if d > 14 or d >= best_d or sim.map_id_at(int(m["x"]), int(m["y"])) != my_map:
				continue
			best = int(m["id"])
			best_d = d
		if best != 0:
			sim.cmd_attack(id, best)
			continue
		if sim._route_to_map(e, Sim.DEFAULT_ZONE):    # 唔喺野區: 經門口出城
			continue
		if int(e["x"]) == int(e["tx"]) and int(e["y"]) == int(e["ty"]) and sim.rng.next() < 0.15:    # 冇怪: 喺野區行吓
			var z: Dictionary = sim.zone_by_id(Sim.DEFAULT_ZONE)
			sim.cmd_move(id, int(z["x0"]) + sim.rng.below(int(z["x1"]) - int(z["x0"])), int(z["y0"]) + sim.rng.below(int(z["y1"]) - int(z["y0"])))
