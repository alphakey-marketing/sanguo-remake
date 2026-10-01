class_name GameData
extends RefCounted
# 載入 res://data/*.json。數值表喺 data/，規則喺 rules/

const NEWBIE_LEVEL := 5
const WORLD_W := 512              # 全域格仔 (所有地圖拼埋一張，spec 12 §2)
const WORLD_H := 9820             # 640 + 原版許昌 + 室內/道路 + 洞穴 + 各城外圍實例 (shelf 排，import_orig_interiors 報最低值)

var classes: Dictionary = {}     # id(String) -> def
var monsters: Dictionary = {}    # id(int) -> def
var spawns: Array = []
var starter: Dictionary = {}
var weapons: Dictionary = {}     # item id -> {power, hit}  武器強度(effect 99) / 命中率(effect 13)
var heals: Dictionary = {}       # item id -> {hp, mp}  回復生命力(effect 14) / 回復靈力(effect 16)，供 cmd_use_item
var prices: Dictionary = {}      # item id -> price
var item_ids: Dictionary = {}    # item id -> true
var weights: Dictionary = {}     # item id -> weight (負重, 背包滿 S04a / 城際貿易 S05)
var names: Dictionary = {}       # item id -> 名
var cats: Dictionary = {}        # item id -> cat (物品分類, 市場用)
var info: Dictionary = {}        # item id -> {cat_label, req_lv, effects:[{label, value}]}  UI 物品詳情用
var inn: Dictionary = {}          # 新手城 (許昌) 客棧 = 出生/復活預設點
var inns: Array = []              # 所有客棧 (inn + shops.json inns)，死亡返最近嗰間 (Step 11.7)
var shops: Array = []
var world: Dictionary = {}        # clock/cities/market/disasters (data/world.json)
var facilities: Dictionary = {}   # 練兵場/私塾/寺廟 (data/facilities.json)
var cities: Dictionary = {}       # city id -> def (由 world.json)
var zones: Array = []             # 安全區/戰鬥區: 每張地圖一個 (由 data/maps.json 生成, spec 12 §2)
var travel_points: Array = []     # 傳送點 (data/maps.json portals，已轉全域座標)
var maps: Array = []              # 地圖 def (data/maps.json)，載入後加 w/h、座標轉全域
var map_by_id: Dictionary = {}    # map id -> def
var legend: Dictionary = {}       # 地形字元 -> {name, walk}
var tiles := PackedByteArray()    # 全域地形字元 (ASCII)，0 = 虛空 (唔喺任何地圖)
var walk := PackedByteArray()     # 全域行得表 1/0
var portal_at: Dictionary = {}    # cell (y*W+x) -> auto 傳送點 id (踩上去就過圖)
var map_idx := PackedByteArray()  # cell -> maps index + 1 (0 = 虛空)；map_at/zone 查表用 (地圖唔重疊)
var tp_by_id: Dictionary = {}     # 傳送點 id -> def
var zone_by_id: Dictionary = {}   # zone (= 地圖) id -> zone
var landmarks: Array = []         # 史蹟地標 (已轉全域座標)
var world_map: Dictionary = {}    # 大地圖 (天下) 節點/路線 (UI 用)
var work: Dictionary = {}         # 工作技能 (data/work.json.skills, Step 7.1)
var work_meta: Dictionary = {}    # 工作技能雜項 (data/work.json: toolDurability/level/basicRate/craftRate/repair)
var work_adv: Dictionary = {}     # 進階技能 (data/work.json.advanced, Step 12)
var recipes: Dictionary = {}      # 成品 item id -> {id, skill, lv, need:[[id,n]]} (data/recipes.json, Step 12)
var recipes_by_skill: Dictionary = {}  # 進階 skill -> [recipe] (按 lv 排)
var tool_skill: Dictionary = {}   # 工具 item id -> skill (初階 tool/starterTool + 進階 tool)
var tool_tier: Dictionary = {}    # 工具 item id -> "special"/"platinum"/"godgiven" (S05b, 普通/新手 tool 冇 entry)
var mat_skill: Dictionary = {}    # 初階工作材料 item id -> skill (天地商行自動存, Step 13)
var donation: Dictionary = {}     # 捐贈官令設定 (data/donation.json, Step 13)
var donation_rates: Dictionary = {}  # item id -> 捐獻單位【原】
var titles: Array = []            # 頭銜 60 階 (data/titles.json, Step 14)【原】
var office: Dictionary = {}       # 官宅/官令設定 (data/office.json, Step 14)
var camp: Dictionary = {}         # 義勇軍營地建設/工作 (data/camp.json, S08f)
var mounts: Dictionary = {}       # 座騎設定 (data/mounts.json, Step 17a)
var mount_weapons: Dictionary = {}  # 馬戰兵器 + 特技 (data/mount_weapons.json, Step 17b)
var war_beasts: Dictionary = {}   # 戰騎屬性/升級 (data/war_beasts.json, Step 18)
var mall: Dictionary = {}          # 貨金商城 (data/mall.json, S11a): {stock:[id], prices:{id:金}}
var battles: Array = []           # 戰役任務 (data/battles.json, Step 19)
var scenes: Array = []            # 特殊場景 (data/scenes.json, S04d): 怪物/層/日曆窗口
var quiz: Array = []              # 理念測驗題庫 (data/quiz.json, Step 7.5)
var face_parts: Dictionary = {}   # 臉譜 8 部位款式數 (data/face.json, Step 7.5)
var quests: Array = []            # 任務定義 (data/quests.json, Step 8)
var quest_npcs: Dictionary = {}   # quest npc id -> def (data/quest_npcs.json, Step 8)
var quest_npc_list: Array = []    # 同上，array 版 (順序)
var spells: Array = []            # 術書定義 (data/spells.json, Step 9)
var spell_by_item: Dictionary = {}  # item id -> spell def
var spell_by_id: Dictionary = {}  # spell id -> def
var jewels: Dictionary = {}      # 寶石目錄 (data/jewels.json, Step 10): stones/special/support/fusable
var jewel_by_item: Dictionary = {}  # item id -> jewel def (全種類)
var ultimates: Array = []        # 絕招定義 (data/ultimates.json, Step 10, spec 02 §5)
var ult_by_id: Dictionary = {}   # ult id -> def
var class_skills: Dictionary = {}   # 職業特技 (data/class_skills.json, S02c, spec 02 §6): skill id -> def
var rumors: Array = []            # 辯士竊聽傳聞線索池 (data/rumors.json, S02c-辯士, spec 02 §6)
var armors: Dictionary = {}      # item id -> {slot, req_lv, max_dur, stats} 防具 (Step 11.6, spec 02 §9)
var equip_cfg: Dictionary = {}   # data/equip.json (部位碼/耐久/上限)
var generals: Array = []          # 登用武將 (data/generals.json, Step 13.5)
var general_by_id: Dictionary = {}  # id -> def
var generals_t1: Array = []       # Tier1 城內常駐 (已轉全域座標)
var recruit_cfg: Dictionary = {}  # generals.json cfg
var general_skill_names: Dictionary = {}  # skill id(String) -> 名
var quiz_generals: Array = []     # 文官問答題庫 (data/quiz_generals.json) [{q, opts[4], a}]
var _arena_defs: Dictionary = {}  # 擂台臨時怪 def 快取 (mob_def 用)
var gen2_cfg: Dictionary = {}     # 登用 v2 (data/general_skills.json cfg, Step 15)
var gen_skills: Array = []        # 70 項特技
var gen_skill_by_id: Dictionary = {}   # 特技 id -> def
var gen_skill_override: Dictionary = {}  # 武將名 -> 特技 id (名將指定)
var gen_draw_pool: Dictionary = {}     # S07d 抽特技固定池 (type -> [skill id])
var gen_skill_pin: Dictionary = {}     # S07d 個別武將指定 (名 -> 特技 id)
var general_order_item: Dictionary = {}  # 武將名 -> 將軍令 item id
var comm: Dictionary = {}          # 居民委託 + 武將收集冊設定 (data/commissions.json, Step 16)
var experts: Dictionary = {}       # 專長 (data/experts.json, Step S01c, spec 01 §8)
var master: Dictionary = {}        # 大宗師合成術 (data/master_recipes.json, S05c, spec 05 §5)
var residents: Dictionary = {}     # 居民 NPC 設定/角色/日程/名字池 (data/residents.json, S09a, spec 09 §1)
var guards: Dictionary = {}        # 捕快 NPC 設定 (data/guards.json,【自訂】)
var llm: Dictionary = {}           # LLM 層設定 (data/llm.json, S09d, spec 09 §5)；key 唔喺度
var marry: Dictionary = {}         # 結婚系統設定 (data/marry.json, S09e, spec 06 §9 / 09 §6)

static var _cache: GameData


static func _read(path: String) -> Variant:
	var txt := FileAccess.get_file_as_string(path)
	var v: Variant = JSON.parse_string(txt)
	assert(v != null, "JSON 讀取失敗: " + path)
	return v


static func load_all() -> GameData:
	if _cache != null:
		return _cache
	var g := GameData.new()
	var c: Dictionary = _read("res://data/classes.json")
	var m: Dictionary = _read("res://data/monsters.json")
	var sh: Dictionary = _read("res://data/shops.json")
	var items: Array = _read("res://data/items.json")
	g.world = _read("res://data/world.json")
	g.facilities = _read("res://data/facilities.json")
	g._load_maps(_read("res://data/maps.json"))
	var wk: Dictionary = _read("res://data/work.json")
	g.work = wk["skills"]
	g.work_meta = {"toolDurability": wk["toolDurability"], "level": wk["level"], "basicRate": wk["basicRate"],
		"craftRate": wk["craftRate"], "repair": wk["repair"], "tierBonus": wk.get("tierBonus", {}),
		"toolRedeemContrib": wk.get("toolRedeemContrib", {})}
	g.work_adv = wk["advanced"]
	for sk in g.work:
		g.tool_skill[int(g.work[sk]["tool"])] = sk
		g.tool_skill[int(g.work[sk]["starterTool"])] = sk
		for mid in g.work[sk]["materials"]:
			g.mat_skill[int(mid)] = sk
		for tier in g.work[sk].get("tiers", {}):
			var tid := int(g.work[sk]["tiers"][tier])
			g.tool_skill[tid] = sk
			g.tool_tier[tid] = tier
	for sk in g.work_adv:
		g.tool_skill[int(g.work_adv[sk]["tool"])] = sk
		g.recipes_by_skill[sk] = []
		for tier in g.work_adv[sk].get("tiers", {}):
			var tid2 := int(g.work_adv[sk]["tiers"][tier])
			g.tool_skill[tid2] = sk
			g.tool_tier[tid2] = tier
	var rc: Dictionary = _read("res://data/recipes.json")
	for r in rc["recipes"]:
		g.recipes[int(r["id"])] = r
		g.recipes_by_skill[String(r["skill"])].append(r)
	g.donation = _read("res://data/donation.json")
	for cat in g.donation["table"]:
		for row in g.donation["table"][cat]:
			g.donation_rates[int(row["id"])] = int(row["rate"])
	var tt: Dictionary = _read("res://data/titles.json")
	g.titles = tt["titles"]
	g.office = _read("res://data/office.json")
	g.camp = _read("res://data/camp.json")
	g.mounts = _read("res://data/mounts.json")
	g.mount_weapons = _read("res://data/mount_weapons.json")
	g.war_beasts = _read("res://data/war_beasts.json")
	g.battles = (_read("res://data/battles.json") as Dictionary)["battles"]
	g.scenes = (_read("res://data/scenes.json") as Dictionary)["scenes"]
	g.mall = _read("res://data/mall.json")
	for o in g.office["orders"]:
		o["rankName"] = RulesTitle.name_of(g.titles, int(o["rank"]))
	var qz: Dictionary = _read("res://data/quiz.json")
	g.quiz = qz["questions"]
	var fc: Dictionary = _read("res://data/face.json")
	g.face_parts = fc["parts"]
	var qn: Dictionary = _read("res://data/quest_npcs.json")
	for x in qn["npcs"]:
		g.quest_npcs[String(x["id"])] = x
		g.quest_npc_list.append(x)
	var qu: Dictionary = _read("res://data/quests.json")
	g.quests = qu["quests"]
	g.comm = _read("res://data/commissions.json")
	var sp: Dictionary = _read("res://data/spells.json")
	g.spells = sp["spells"]
	for x in g.spells:
		g.spell_by_id[String(x["id"])] = x
		g.spell_by_item[int(x["item"])] = x
	var jw: Dictionary = _read("res://data/jewels.json")
	g.jewels = jw
	for cat in ["stones", "special", "support", "fusable"]:
		for j in jw.get(cat, []):
			j["kind"] = "stone" if cat == "stones" else "special" if cat == "special" else "support" if cat == "support" else "fusable"
			g.jewel_by_item[int(j["id"])] = j
	g.equip_cfg = _read("res://data/equip.json")
	var gn: Dictionary = _read("res://data/generals.json")
	g.recruit_cfg = gn["cfg"]
	g.general_skill_names = gn["skillNames"]
	for x in gn["generals"]:
		x["id"] = int(x["id"])
		g.generals.append(x)
		g.general_by_id[int(x["id"])] = x
		if int(x["tier"]) == 1:
			g.generals_t1.append(x)
	var gs: Dictionary = _read("res://data/general_skills.json")
	g.gen2_cfg = gs["cfg"]
	g.gen_skills = gs["skills"]
	for s in g.gen_skills:
		s["id"] = int(s["id"])
		g.gen_skill_by_id[int(s["id"])] = s
	g.gen_skill_override = gs.get("override", {})
	g.gen_draw_pool = gs["cfg"].get("drawPool", {})
	g.gen_skill_pin = gs["cfg"].get("pin", {})
	var qg: Dictionary = _read("res://data/quiz_generals.json")
	g.quiz_generals = qg["questions"]
	var ul: Dictionary = _read("res://data/ultimates.json")
	g.ultimates = ul["ultimates"]
	for u in g.ultimates:
		g.ult_by_id[String(u["id"])] = u
	var csk: Dictionary = _read("res://data/class_skills.json")
	for s in csk["skills"]:
		g.class_skills[String(s["id"])] = s
	g.rumors = (_read("res://data/rumors.json") as Dictionary).get("rumors", [])
	g.experts = _read("res://data/experts.json")
	g.master = _read("res://data/master_recipes.json")
	g.residents = _read("res://data/residents.json")
	g.guards = _read("res://data/guards.json")
	g.llm = _read("res://data/llm.json")
	g.marry = _read("res://data/marry.json")
	for x in c["classes"]:
		g.classes[String(x["id"])] = x
	for x in m["monsters"]:
		g.monsters[int(x["id"])] = x
	g.spawns = m["spawns"]
	g.starter = c["starter"]
	g.inn = sh["inn"]
	g.inn["id"] = String(g.inn.get("id", "xuchang"))
	g.inn["name"] = String(g.inn.get("name", "客棧"))
	g.inns = [g.inn] + sh.get("inns", [])
	g.shops = sh["shops"]
	for c_ in g.world["cities"]:
		g.cities[c_.id] = c_
	for it in items:
		var id := int(it["id"])
		g.item_ids[id] = true
		g.names[id] = str(it.get("name", id))
		g.prices[id] = float(it.get("price", 0))
		g.weights[id] = int(it.get("weight", 0))
		g.cats[id] = int(it.get("cat", 0))
		var gname := RulesGeneral.order_general_name(g.names[id], String(g.gen2_cfg["orderSuffix"]), g.gen2_cfg.get("orderAlias", {}))
		if gname != "" and not g.general_order_item.has(gname):
			g.general_order_item[gname] = id
		var effs: Array = []
		for e in it.get("effects", []):
			effs.append({"label": str(e.get("label", "")), "value": int(e.get("value", 0)), "type": int(e.get("type", 0))})
		g.info[id] = {"cat_label": str(it.get("cat_label", "")), "req_lv": int(it.get("req_lv", 0)), "effects": effs}
		var p = null
		var h = null
		var heal_hp := 0
		var heal_mp := 0
		var heal_sp := 0
		for e in it.get("effects", []):
			var et := int(e["type"])
			if et == 99 and p == null:
				p = float(e["value"])
			elif et == 13 and h == null:
				h = float(e["value"])
			elif et == 14:
				heal_hp += int(e["value"])
			elif et == 16:
				heal_mp += int(e["value"])
			elif et == 19:              # 回復氣力 (SP)【原=喜餅點心等食物藥水】
				heal_sp += int(e["value"])
			elif et in [73, 74, 75]:    # 【自訂】73/74/75 = 戰騎藥水系 (紅/藍/綠藥水): value × 100 固定回復 (I=300, II=200, III=100)
				var v := int(e["value"]) * 100
				if et == 73:
					heal_hp += v
				elif et == 74:
					heal_mp += v
				else:
					heal_sp += v
		var slot := str(g.equip_cfg["slotCode"].get(str(int((it.get("b54_59", [0, 0, 0]) as Array)[2])), ""))
		if slot != "":
			g.armors[id] = {"slot": slot, "req_lv": int(it.get("req_lv", 0)),
				"max_dur": RulesEquip.max_dur(int(it.get("req_lv", 0)), g.equip_cfg["durability"]),
				"stats": RulesEquip.armor_stats(it.get("effects", []))}
		if p != null:
			g.weapons[id] = {"power": p, "hit": h if h != null else 45.0,
				"max_dur": RulesEquip.max_dur(int(it.get("req_lv", 0)), g.equip_cfg["durability"])}
		if heal_hp > 0 or heal_mp > 0 or heal_sp > 0:
			g.heals[id] = {"hp": heal_hp, "mp": heal_mp, "sp": heal_sp}
	for k in g.gen2_cfg["tonics"]:          # 武將補品價【自訂】(items.json 原價 0)
		g.prices[int(k)] = float(g.gen2_cfg["tonics"][k]["price"])
	g._place_all()
	_cache = g
	return g


# ---- 地圖 (spec 12 §2) ----
# 讀每張 data/maps/<id>.txt 落全域格仔；每張地圖生成一個 zone；傳送點/地標/區域轉全域
func _load_maps(mj: Dictionary) -> void:
	legend = mj["legend"]
	var walk_code := {}
	for k in legend:
		walk_code[String(k).unicode_at(0)] = bool(legend[k]["walk"])
	tiles.resize(WORLD_W * WORLD_H)
	walk.resize(WORLD_W * WORLD_H)
	map_idx.resize(WORLD_W * WORLD_H)
	assert(mj["maps"].size() < 255, "map_idx 用 byte，地圖太多")
	for md in mj["maps"]:
		var id := String(md["id"])
		var rows := FileAccess.get_file_as_string("res://data/maps/%s.txt" % id).replace("\r", "").split("\n", false)
		assert(rows.size() > 0, "地圖檔讀唔到: " + id)
		var ox := int(md["ox"])
		var oy := int(md["oy"])
		md["w"] = rows[0].length()
		md["h"] = rows.size()
		assert(ox + int(md["w"]) <= WORLD_W and oy + int(md["h"]) <= WORLD_H, "地圖出界: " + id)
		for y in rows.size():
			var row: String = rows[y]
			for x in mini(row.length(), int(md["w"])):
				var c := row.unicode_at(x)
				var i := (oy + y) * WORLD_W + ox + x
				tiles[i] = c if c < 128 else 32
				walk[i] = 1 if walk_code.get(c, false) else 0
		if md.has("spawn"):
			var s: Array = md["spawn"]
			md["spawn"] = [int(s[0]) + ox, int(s[1]) + oy, int(s[2]) + ox, int(s[3]) + oy]
		for a in md.get("areas", []):
			for k in ["x0", "x1"]:
				a[k] = int(a[k]) + ox
			for k in ["y0", "y1"]:
				a[k] = int(a[k]) + oy
		maps.append(md)
		map_by_id[id] = md
		for y in int(md["h"]):
			for x in int(md["w"]):
				map_idx[(oy + y) * WORLD_W + ox + x] = maps.size()
		zones.append({"id": id, "name": String(md["name"]), "safe": bool(md["safe"]), "map": id,
			"x0": ox, "y0": oy, "x1": ox + int(md["w"]) - 1, "y1": oy + int(md["h"]) - 1})
		zone_by_id[id] = zones[-1]
	travel_points = mj.get("portals", [])
	for p in travel_points:
		tp_by_id[String(p["id"])] = p
	landmarks = mj.get("landmarks", [])
	world_map = mj.get("world", {})


# 有 "map" 嘅物件: 地圖內座標 → 全域 (保留 lx/ly)
func place(o: Dictionary) -> void:
	if not o.has("map") or o.has("lx"):
		return
	var md: Dictionary = map_by_id.get(String(o["map"]), {})
	assert(not md.is_empty(), "未知地圖: %s" % o["map"])
	o["lx"] = int(o["x"])
	o["ly"] = int(o["y"])
	o["x"] = int(o["x"]) + int(md["ox"])
	o["y"] = int(o["y"]) + int(md["oy"])


func _place_all() -> void:
	for x in inns:
		place(x)
	for s in shops:
		place(s)
	for k in facilities:
		if facilities[k] is Dictionary:
			place(facilities[k])
	for n in quest_npc_list:
		place(n)
	for x in generals_t1:
		place(x)
	for p in travel_points:
		place(p)
		if p.has("rect"):                 # 矩形觸發區 (原版門): rect/land 都係地圖內座標 → 全域
			var md: Dictionary = map_by_id[String(p["map"])]
			var r: Array = p["rect"]
			var ox := int(md["ox"])
			var oy := int(md["oy"])
			p["rect"] = [int(r[0]) + ox, int(r[1]) + oy, int(r[2]) + ox, int(r[3]) + oy]
			if p.has("land"):
				p["land"] = [int(p["land"][0]) + ox, int(p["land"][1]) + oy]
		if bool(p.get("auto", false)):
			if p.has("rect"):
				var rr: Array = p["rect"]
				for cy in range(int(rr[1]), int(rr[3]) + 1):
					for cx in range(int(rr[0]), int(rr[2]) + 1):
						if walk[cy * WORLD_W + cx] == 1 and not portal_at.has(cy * WORLD_W + cx):
							portal_at[cy * WORLD_W + cx] = String(p["id"])
			else:
				portal_at[int(p["y"]) * WORLD_W + int(p["x"])] = String(p["id"])
	for lm in landmarks:
		place(lm)
	for sp in spawns:                     # spawn area = zone 地圖內座標 → 全域
		var md: Dictionary = map_by_id.get(String(sp.get("zone", "")), {})
		if md.is_empty():
			continue
		var a: Array = sp.get("area", [0, 0, int(md["w"]) - 1, int(md["h"]) - 1])
		sp["area"] = [int(a[0]) + int(md["ox"]), int(a[1]) + int(md["oy"]), int(a[2]) + int(md["ox"]), int(a[3]) + int(md["oy"])]


# 怪物 def: monsters.json；擂台臨時怪 (id ≥ ARENA_DEF_BASE) 由武將資料即時生成 (Step 13.5)
func mob_def(def_id: int) -> Dictionary:
	if monsters.has(def_id):
		return monsters[def_id]
	if not _arena_defs.has(def_id):
		var g: Dictionary = general_by_id.get(def_id - RulesRecruit.ARENA_DEF_BASE, {})
		if g.is_empty():
			return {}
		_arena_defs[def_id] = RulesRecruit.arena_def(g, recruit_cfg)
	return _arena_defs[def_id]


# 全域格屬邊張地圖 ({} = 虛空)
# 地圖所屬城池 id: 原版室內/城街用 cityOf (唔係 kind:city，免得居民/捕快重複生成)；舊圖用 city；冇 = ""
static func map_city_of(md: Dictionary) -> String:
	var c := String(md.get("cityOf", ""))
	return c if c != "" else String(md.get("city", ""))


func map_at(x: int, y: int) -> Dictionary:
	var i := map_index(x, y)
	return maps[i] if i >= 0 else {}


# 全域格屬 maps/zones 第幾個 (-1 = 虛空/出界)；zones 同 maps 一一對應同次序
func map_index(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= WORLD_W or y >= WORLD_H:
		return -1
	return map_idx[y * WORLD_W + x] - 1
