class_name BotSys
extends RefCounted
# 機械人: 有角色，會去野區打怪、血低返客棧休息、間中講嘢。供新手練兵場頂替組隊。
# (Step 5 會升級成 NPC agent)

const NAMES := ["黃權", "張繡", "趙雲", "關平", "周倉", "徐庶", "龐統", "法正", "馬岱", "王平", "姜維", "魏延"]
const LINES := ["有冇人組隊?", "呢度啲怪好肥", "小心野豬", "我去練功", "升級喇!", "客棧休息好抵", "有刀賣未?", "三國萬歲"]


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
		if low:                                        # 血低: 撤退返客棧休息
			e["atk_target"] = 0
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
		# 揀附近最近嘅怪 (等級唔好高過自己太多)
		var best := 0
		var best_d := 1 << 30
		for m in sim.ents.values():
			if m["kind"] != "mob" or int(m["level"]) > int(ch["level"]) + 2:
				continue
			var d := maxi(absi(int(m["x"]) - int(e["x"])), absi(int(m["y"]) - int(e["y"])))
			if d <= 14 and d < best_d:
				best = int(m["id"])
				best_d = d
		if best != 0:
			sim.cmd_attack(id, best)
			continue
		if int(e["x"]) == int(e["tx"]) and int(e["y"]) == int(e["ty"]) and sim.rng.next() < 0.15:    # 冇怪: 行入野區
			var z: Dictionary = sim.zone_by_id(Sim.DEFAULT_ZONE)
			sim.cmd_move(id, int(z["x0"]) + sim.rng.below(int(z["x1"]) - int(z["x0"])), int(z["y0"]) + sim.rng.below(int(z["y1"]) - int(z["y0"])))
