class_name RulesCommission
extends RefCounted
# 居民委託 (Step 16, spec 06 §4 一般任務模板)【自訂】純函數。設定 = data/commissions.json (GameData.comm)。
# 委託單 = 純 Dictionary: {giver, day, kind, mob/item/to, n, reward:{gold, exp, fame}}；
# 接咗 = 加 accepted(日) + prog(打怪進度)，放入 ch.comm.active。
# 出單唔食 sim RNG: 由 (日, 委託人, salt) 砌種子，同一存檔同一日出同一單 (可重現)。

const KINDS := ["hunt", "collect", "deliver", "repair"]


# ================= 驗證 (data load 後跑) =================
static func validate(data: GameData) -> Array:
	var errs: Array = []
	var cfg: Dictionary = data.comm
	for k in KINDS:
		if not cfg.has(k) or not cfg["kindWeights"].has(k):
			errs.append("commissions: 冇 %s 設定" % k)
	if not data.item_ids.has(int(cfg.get("letterItem", 0))):
		errs.append("commissions: letterItem 唔存在")
	for gid in cfg.get("givers", {}):
		var g: Dictionary = cfg["givers"][gid]
		var npc: Dictionary = data.quest_npcs.get(String(gid), {})
		if npc.is_empty():
			errs.append("commissions: 委託人唔存在 (%s)" % gid)
		elif not bool(npc.get("commission", false)):
			errs.append("commissions: %s 冇 commission=true" % gid)
		for m in g.get("hunt", []):
			if not data.monsters.has(int(m)):
				errs.append("commissions: %s hunt 怪唔存在 (%s)" % [gid, m])
		for t in g.get("deliver", []):
			if String(t) == String(gid) or not data.quest_npcs.has(String(t)):
				errs.append("commissions: %s deliver 目標唔啱 (%s)" % [gid, t])
		for it in g.get("repair", []):
			if repair_skill(data, int(it)) == "":
				errs.append("commissions: %s repair 件嘢修唔到 (%s)" % [gid, it])
		if collect_pool(data, g).is_empty():
			errs.append("commissions: %s 冇 collect 材料 (hunt 怪冇掉落)" % gid)
	for n in data.quest_npc_list:
		if bool(n.get("commission", false)) and not cfg.get("givers", {}).has(String(n["id"])):
			errs.append("commissions: %s commission=true 但冇 givers 設定" % n["id"])
	var bk: Dictionary = cfg.get("book", {})
	if not data.item_ids.has(int(bk.get("item", 0))) or not data.quest_npcs.has(String(bk.get("npc", ""))):
		errs.append("commissions: book item/npc 唔存在")
	for s in bk.get("stones", []):
		if not data.item_ids.has(int(s)):
			errs.append("commissions: book 石唔存在 (%s)" % s)
	return errs


# 邊種進階技能修得呢件 (同 sim_econ.repair_skill 一致)；"" = 修唔到
static func repair_skill(data: GameData, item: int) -> String:
	var part := "weapon" if data.weapons.has(item) else String(data.armors.get(item, {}).get("slot", ""))
	if part == "":
		return ""
	for sk in data.work_adv:
		if (data.work_adv[sk].get("repairs", []) as Array).has(part):
			return sk
	return ""


# collect 材料池 = 打怪池啲怪 p ≥ collectMinP 嘅掉落 (唔包任務道具)，按 id 排 (穩定)
static func collect_pool(data: GameData, g: Dictionary) -> Array:
	var min_p := float(data.comm["collect"]["collectMinP"])
	var seen := {}
	for m in g.get("hunt", []):
		for d in data.monsters.get(int(m), {}).get("drops", []):
			var it := int(d["item"])
			if float(d["p"]) >= min_p and data.item_ids.has(it) and not RulesQuest.is_quest_item(data, it):
				seen[it] = true
	var out: Array = seen.keys()
	out.sort()
	return out


# ================= 出單 =================
static func seed_of(day: int, giver: String, salt: int) -> int:
	return ("%d:%s:%d" % [day, giver, salt]).hash()


# 今日呢位委託人出嘅單；委託人冇設定 = {}
static func offer(data: GameData, giver: String, day: int, salt: int) -> Dictionary:
	var cfg: Dictionary = data.comm
	var g: Dictionary = cfg.get("givers", {}).get(giver, {})
	if g.is_empty():
		return {}
	var r := SimRng.new(seed_of(day, giver, salt))
	var pools := {"hunt": g.get("hunt", []), "collect": collect_pool(data, g), "deliver": g.get("deliver", []), "repair": g.get("repair", [])}
	var total := 0
	for k in KINDS:
		if not (pools[k] as Array).is_empty():
			total += int(cfg["kindWeights"][k])
	if total <= 0:
		return {}
	var roll := r.below(total)
	var kind := ""
	for k in KINDS:
		if (pools[k] as Array).is_empty():
			continue
		roll -= int(cfg["kindWeights"][k])
		if roll < 0:
			kind = k
			break
	var pool: Array = pools[kind]
	var pick: Variant = pool[r.below(pool.size())]
	var o := {"giver": giver, "day": day, "kind": kind}
	var fame := int(cfg.get("fame", 0))
	match kind:
		"hunt":
			var kc: Dictionary = cfg["hunt"]
			var md: Dictionary = data.monsters[int(pick)]
			var n := _range(r, kc["n"])
			o["mob"] = int(pick)
			o["n"] = n
			o["reward"] = {"gold": n * int(md["level"]) * int(kc["goldPerLvN"]),
				"exp": int(n * int(md["exp"]) * float(kc["expMul"])), "fame": fame}
		"collect":
			var kc: Dictionary = cfg["collect"]
			var n := _range(r, kc["n"])
			o["item"] = int(pick)
			o["n"] = n
			o["reward"] = {"gold": maxi(int(kc["minGold"]), int(float(data.prices.get(int(pick), 0.0)) * n * float(kc["priceMul"]))),
				"exp": n * int(kc["expPerN"]), "fame": fame}
		"deliver":
			var kc: Dictionary = cfg["deliver"]
			o["to"] = String(pick)
			o["reward"] = {"gold": int(kc["gold"]), "exp": int(kc["exp"]), "fame": fame}
		"repair":
			var kc: Dictionary = cfg["repair"]
			o["item"] = int(pick)
			o["skill"] = repair_skill(data, int(pick))
			o["lv"] = int(data.recipes.get(int(pick), {}).get("lv", 1))
			o["reward"] = {"gold": maxi(int(kc["minGold"]), int(float(data.prices.get(int(pick), 0.0)) * float(kc["priceMul"]))),
				"fame": fame}
	return o


static func _range(r: SimRng, lohi: Array) -> int:
	return int(lohi[0]) + r.below(int(lohi[1]) - int(lohi[0]) + 1)


# ================= 進度 =================
# 打死 def_id 一隻: 所有未夠數嘅 hunt 單 +1；回傳有變嘅單
static func on_kill(active: Array, def_id: int) -> Array:
	var out: Array = []
	for c in active:
		if String(c["kind"]) == "hunt" and int(c["mob"]) == def_id and int(c.get("prog", 0)) < int(c["n"]):
			c["prog"] = int(c.get("prog", 0)) + 1
			out.append(c)
	return out


# 返委託人覆命得唔得 (hunt 夠數 / collect 背包夠)；deliver/repair 唔喺委託人度完成
static func can_report(c: Dictionary, bag: Array) -> bool:
	match String(c["kind"]):
		"hunt":
			return int(c.get("prog", 0)) >= int(c["n"])
		"collect":
			return RulesShop.has_item(bag, int(c["item"]), int(c["n"]))
	return false


# 過期: 接咗 expireDays 日 (含) 之後
static func expired(c: Dictionary, day: int, expire_days: int) -> bool:
	return day - int(c.get("accepted", day)) >= expire_days


# 委託內容一句 (UI/訊息用)
static func describe(data: GameData, c: Dictionary) -> String:
	match String(c["kind"]):
		"hunt":
			return "打 %d 隻%s（%d/%d）" % [int(c["n"]), data.monsters[int(c["mob"])]["name"], int(c.get("prog", 0)), int(c["n"])]
		"collect":
			return "收集 %d 件%s" % [int(c["n"]), data.names.get(int(c["item"]), str(c["item"]))]
		"deliver":
			return "送信畀%s" % data.quest_npcs[String(c["to"])]["name"]
		"repair":
			return "修理%s（%s %d 級）" % [data.names.get(int(c["item"]), str(c["item"])),
				data.work_adv[String(c["skill"])]["name"], int(c["lv"])]
	return "?"


static func reward_text(r: Dictionary) -> String:
	var parts: Array = []
	if int(r.get("gold", 0)) > 0:
		parts.append("%d 金" % int(r["gold"]))
	if int(r.get("exp", 0)) > 0:
		parts.append("經驗 %d" % int(r["exp"]))
	if int(r.get("fame", 0)) > 0:
		parts.append("名聲 %d" % int(r["fame"]))
	return "、".join(parts)
