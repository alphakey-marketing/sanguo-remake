extends "res://sim/sim_char.gd"
# Sim 繼承鏈 第 4 層: 客棧 / 商店 / 消耗品 / 天地商行 / 工作技能 / 武器寶石裝備

func cmd_rest(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var inn := _inn_near(e)
	if inn.is_empty():
		return _msg(id, "要喺客棧附近先可以休息")
	var ch: Dictionary = e["ch"]
	if RulesKarma.city_banned(int(ch["karma"])):     # S03b: 殺人魔城門衛兵拒入城 → 唔俾留宿 (spec 03 §5)
		return _msg(id, RulesKarma.guard_warn_text(int(ch["karma"])) + "（衛兵唔俾你留宿！）")
	var cost := 0 if int(ch["level"]) < GameData.NEWBIE_LEVEL else int(inn["restCost"])   # 5 級前店小二免費補 HP (S01a, spec 01 §5)
	if int(ch["gold"]) < cost:
		return _msg(id, "住宿要 %d 金" % cost)
	ch["gold"] = int(ch["gold"]) - cost
	_full_heal(ch)
	_sync_stats(e)
	_msg(id, "休息完畢，花 %d 金" % cost)


# 客棧喝茶【原】: 回飲水度 50 + 回 MP (Step 14, spec 01 §9)
func cmd_tea(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	if _inn_near(e).is_empty():
		return _msg(id, "要喺客棧先有茶飲")
	var cfg: Dictionary = data.world["thirst"]
	var ch: Dictionary = e["ch"]
	var cost := int(cfg["teaCost"])
	if int(ch["gold"]) < cost:
		return _msg(id, "飲茶要 %d 金" % cost)
	ch["gold"] = int(ch["gold"]) - cost
	var before := thirst_of(ch)
	ch["thirst"] = RulesTitle.drink(before, cfg)
	var mmp := _eff_max_mp(ch)
	var mp := mini(mmp, int(ch["mp"]) + int(round(mmp * float(cfg["teaMp"]))))
	var gained := mp - int(ch["mp"])
	ch["mp"] = mp
	_sync_stats(e)
	_msg(id, "飲咗杯茶（%d 金）：飲水度 +%d，MP +%d" % [cost, int(ch["thirst"]) - before, maxi(0, gained)])


func _inn_near(e: Dictionary) -> Dictionary:
	for x in data.inns:
		if _near(e, int(x["x"]), int(x["y"])):
			return x
	return {}


func _shop_for(e: Dictionary) -> Dictionary:
	for s in data.shops:
		if _near(e, int(s["x"]), int(s["y"])):
			return s
	var k := _fac_near(e, "stable")        # 馬廄賣馬用品 (Step 17a)
	if k != "":
		return {"id": k, "name": data.facilities[k]["name"], "stock": data.mounts["stableStock"]}
	return {}


# S08b：城池「鑄造」屬性影響商店貨單（attr ≥ min → 多啲貨）。呢件貨商店賣唔賣
func shop_sells(shop: Dictionary, item: int) -> bool:
	var stock: Array = shop.get("stock", [])
	if stock.has(item) or stock.has(float(item)):
		return true
	var city := String(shop.get("map", ""))
	if city == "":
		return false
	return RulesCity.shop_extra_items(city_attrs(city), _city_attr_cfg()).has(item)


# 天災大/中停進貨 (spec 05 §6【自訂】): 商店所屬城市有生效中天災、且天災 supply cat 蓋到呢件貨嘅 cat → 缺貨
func _shop_shutdown_reason(shop: Dictionary, item: int) -> String:
	var city_id := String(shop.get("map", ""))
	if city_id == "":
		return ""
	var cat := int(data.cats.get(item, -1))
	var day := int(_clock()["day"])
	for d in state["disasters"]:
		if str(d.get("city", "")) != city_id:
			continue
		if day >= int(d.get("shutdownEnd", -1)):
			continue
		var cats: Array = d.get("shutdownCats", [])
		if cats.has(str(cat)) or cats.has(cat):
			return "%s：%s 停止進貨中，暫時缺貨" % [String(d.get("name", "天災")), shop.get("name", "商店")]
	return ""


func cmd_buy(id: int, item: int, n: int = 1) -> void:
	var e := ent(id)
	n = mini(99, n)
	if e.is_empty() or not e.has("ch") or n < 1:
		return
	var shop := _shop_for(e)
	if shop.is_empty():
		return _msg(id, "附近冇商店")
	var stock: Array = shop["stock"]
	if not shop_sells(shop, item):
		return _msg(id, "呢間店唔賣呢件")
	var shut := _shop_shutdown_reason(shop, item)
	if shut != "":
		return _msg(id, shut)
	var ch: Dictionary = e["ch"]
	var cost := RulesShop.buy_price(data.prices.get(item, 0.0) * market_factor(item), ch["attrs"]["cha"], int(ch["karma"]), expert_lv(ch, "jiaoyi")) * n
	if int(ch["gold"]) < cost:
		return _msg(id, "金錢不足，要 %d" % cost)
	ch["gold"] = int(ch["gold"]) - cost
	RulesShop.add_item(ch["bag"], item, n)
	_msg(id, "買咗 %d 件，花 %d 金" % [n, cost])


func cmd_sell(id: int, item: int, n: int = 1) -> void:
	var e := ent(id)
	n = mini(99, n)
	if e.is_empty() or not e.has("ch") or n < 1:
		return
	if _shop_for(e).is_empty():
		return _msg(id, "附近冇商店")
	if RulesQuest.is_quest_item(data, item):
		return _msg(id, "任務道具唔可以賣 (會擋任務)")
	var ch: Dictionary = e["ch"]
	var have := 0
	for b in ch["bag"]:
		if int(b["id"]) == item:
			have = int(b["n"])
	if _locked_by_equip(ch, item, n):
		return _msg(id, "裝備中，唔可以賣 (先卸下)")
	var eq_books: Array = ch["equip"].get("spellbooks", [0, 0, 0])
	if (eq_books as Array).has(item) and have <= n:
		return _msg(id, "快捷列裝備中，唔可以賣")
	if not RulesShop.remove_item(ch["bag"], item, n):
		return _msg(id, "背包冇咁多")
	var gain := RulesShop.sell_price(data.prices.get(item, 0.0) * market_factor(item), expert_lv(ch, "jiaoyi")) * n
	ch["gold"] = int(ch["gold"]) + gain
	_cleanup_dur(ch)
	_cleanup_fused(ch)                    # 賣晒融合武器 → 清嵌石記錄
	_msg(id, "賣出 %d 件，得 %d 金" % [n, gain])


# debug 用: 直接派物品落背包 (未有商店/任務可以攞到嘅嘢，方便手機冇鍵盤都測到成條流程；成品前移除)
func cmd_debug_give(id: int, item: int, n: int = 1) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	RulesShop.add_item(e["ch"]["bag"], item, n)


# 食用/飲用消耗品【原=食物藥水回 HP、藥丸散回 MP；自訂=冇食用次數限制，用完即扣背包一件】
func cmd_use_item(id: int, item: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	if item == int(data.office["pillItem"]):
		return _use_ap_pill(e, item)
	var heal: Dictionary = data.heals.get(item, {})
	if heal.is_empty():
		return _msg(id, "呢件唔可以食用")
	var ch: Dictionary = e["ch"]
	if not RulesShop.remove_item(ch["bag"], item, 1):
		return _msg(id, "背包冇呢件")
	var mhp := _eff_max_hp(ch)
	var mmp := _eff_max_mp(ch)
	var msp := _eff_max_sp(ch)
	var gained_hp := mini(int(heal.get("hp", 0)), mhp - int(ch["hp"]))
	var gained_mp := mini(int(heal.get("mp", 0)), mmp - int(ch["mp"]))
	var gained_sp := mini(int(heal.get("sp", 0)), msp - int(ch["sp"]))
	ch["hp"] = int(ch["hp"]) + maxi(0, gained_hp)
	ch["mp"] = int(ch["mp"]) + maxi(0, gained_mp)
	ch["sp"] = int(ch["sp"]) + maxi(0, gained_sp)
	_sync_stats(e)
	_msg(id, "用咗 %s，回 %d HP %d MP %d SP" % [data.names.get(item, str(item)), maxi(0, gained_hp), maxi(0, gained_mp), maxi(0, gained_sp)])


# ================= 天地商行 (Step 7.2)【原=功能：代買賣/存材料/買賣工具/休息；自訂=費用扣法已在 4.5 有嘅市場價/日費】=================
# 依家做「代買賣 + 存材料」；休息/買賣工具已有 cmd_rest/cmd_buy 頂替，唔使再重做一套

func cmd_storage_sub(id: int, on: bool) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	e["ch"]["storageSub"] = on
	_msg(id, "訂閱天地商行" if on else "退訂天地商行")


func cmd_storage_deposit(id: int, item: int, n: int = 1) -> void:
	var e := ent(id)
	n = mini(99, n)
	if e.is_empty() or not e.has("ch") or n < 1:
		return
	var ch: Dictionary = e["ch"]
	if not bool(ch.get("storageSub", false)) and not _friend_effect_active(e, "bank"):
		return _msg(id, "要先訂閱天地商行")
	if _locked_by_equip(ch, item, n):
		return _msg(id, "裝備中，唔可以存 (先卸下)")
	var cap := int(data.world["tiandi"]["storageCap"])
	if RulesTiandi.stack_total(ch["storage"]) + n > cap:
		return _msg(id, "倉庫滿咗 (上限 %d 件)" % cap)
	if not RulesShop.remove_item(ch["bag"], item, n):
		return _msg(id, "背包冇咁多")
	RulesShop.add_item(ch["storage"], item, n)
	_msg(id, "存咗 %d 件入天地商行" % n)


func cmd_storage_withdraw(id: int, item: int, n: int = 1) -> void:
	var e := ent(id)
	n = mini(99, n)
	if e.is_empty() or not e.has("ch") or n < 1:
		return
	var ch: Dictionary = e["ch"]
	if not bool(ch.get("storageSub", false)) and not _friend_effect_active(e, "bank"):
		return _msg(id, "要先訂閱天地商行")
	if not RulesShop.remove_item(ch["storage"], item, n):
		return _msg(id, "倉庫冇咁多")
	RulesShop.add_item(ch["bag"], item, n)
	_msg(id, "由天地商行攞返 %d 件" % n)


# 代買賣: 隨時隨地都可以賣 (唔使喺商店附近)，用市場價
func cmd_storage_sell(id: int, item: int, n: int = 1) -> void:
	var e := ent(id)
	n = mini(99, n)
	if e.is_empty() or not e.has("ch") or n < 1:
		return
	var ch: Dictionary = e["ch"]
	if not bool(ch.get("storageSub", false)):
		return _msg(id, "要先訂閱天地商行")
	if RulesQuest.is_quest_item(data, item):
		return _msg(id, "任務道具唔可以賣 (會擋任務)")
	if _locked_by_equip(ch, item, n):
		return _msg(id, "裝備中，唔可以賣 (先卸下)")
	if not RulesShop.remove_item(ch["bag"], item, n):
		return _msg(id, "背包冇咁多")
	var gain := RulesShop.sell_price(data.prices.get(item, 0.0) * market_factor(item), expert_lv(ch, "jiaoyi")) * n
	ch["gold"] = int(ch["gold"]) + gain
	_cleanup_dur(ch)
	_msg(id, "天地商行代賣 %d 件，得 %d 金" % [n, gain])


# ================= 天地商行自動化 (Step 13, spec 05 §3) =================
# 【原】功能: 負重滿自動存/賣材料、自動買賣工具、工作區小屋休息；【自訂】負重 = 背包工作材料件數 (world.json tiandi)

# 設定: key = "deposit:<skill>" / "buyTool" / "sellTool"
func cmd_tiandi_set(id: int, key: String, on: bool) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var td := tiandi_cfg(e["ch"])
	if key.begins_with("deposit:"):
		var sk := key.substr(8)
		if not data.work.has(sk):
			return
		var dep: Array = td["deposit"]
		if on and not dep.has(sk):
			dep.append(sk)
		elif not on:
			dep.erase(sk)
	elif key == "buyTool" or key == "sellTool":
		td[key] = on
	else:
		return
	_emit({"k": "tiandi_set", "id": id, "key": key, "on": on})


# 天地商行設定 (舊存檔冇 → 補)
func tiandi_cfg(ch: Dictionary) -> Dictionary:
	if not ch.has("tiandi"):
		ch["tiandi"] = {"deposit": [], "buyTool": false, "sellTool": false}
	return ch["tiandi"]


# 工作區小屋休息【原】: 訂閱咗 + 喺城外 (工作區)，收費回滿 HP/MP/SP
func cmd_storage_rest(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	if not bool(ch.get("storageSub", false)):
		return _msg(id, "要先訂閱天地商行")
	if is_safe(int(e["x"]), int(e["y"])):
		return _msg(id, "小屋喺城外工作區，城內去客棧啦")
	var cost := int(data.world["tiandi"]["restCost"])
	if int(ch["gold"]) < cost:
		return _msg(id, "小屋休息要 %d 金" % cost)
	ch["gold"] = int(ch["gold"]) - cost
	_full_heal(ch)
	_sync_stats(e)
	_msg(id, "喺工作區小屋休息完畢，花 %d 金" % cost)


# 工具耐久上限 (新手/普通/特製/白金/御賜, S05b spec 05 §2)
func _tool_max_dur(skill: String, item: int) -> int:
	var tier := String(data.tool_tier.get(item, ""))
	if tier != "":
		return RulesWork.tool_tier_dur(tier, data.work_meta["tierBonus"])
	var sk := _skill_def(skill)
	var td: Dictionary = data.work_meta.get("toolDurability", {})
	return int(td.get("starter" if int(sk.get("starterTool", -1)) == item else "normal", 50))


# 3 等工具成功率加成 (S05b)：普通/新手 = 0
func _tool_bonus(item: int) -> float:
	return RulesWork.tool_tier_bonus(String(data.tool_tier.get(item, "")), data.work_meta["tierBonus"])


# 做完一次工作: 耐久剩 toolSellAt 自動賣【原】；冇工具 (爛咗/賣咗) + 勾咗買工具 → 自動買返同一件【原】
func _tiandi_tools(id: int, ch: Dictionary, skill: String, item: int) -> void:
	if not bool(ch.get("storageSub", false)):
		return
	var td := tiandi_cfg(ch)
	var cur: Dictionary = ch["tools"].get(skill, {})
	if bool(td.get("sellTool", false)) and not cur.is_empty() and int(cur["dur"]) <= int(data.world["tiandi"]["toolSellAt"]):
		var gain := RulesTiandi.tool_resale(int(data.prices.get(item, 0.0)), int(cur["dur"]), _tool_max_dur(skill, item))
		ch["tools"].erase(skill)
		ch["gold"] = int(ch["gold"]) + gain
		_emit({"k": "tiandi_tool", "id": id, "skill": skill, "act": "sell", "item": item, "gold": gain})
		_msg(id, "天地商行: 代賣%s，得 %d 金" % [data.names.get(item, str(item)), gain])
	if not bool(td.get("buyTool", false)) or ch["tools"].has(skill):
		return
	var cost := RulesShop.buy_price(data.prices.get(item, 0.0) * market_factor(item), ch["attrs"]["cha"], int(ch["karma"]), expert_lv(ch, "jiaoyi"))
	if int(ch["gold"]) < cost:
		return _msg(id, "天地商行: 買新%s要 %d 金，唔夠錢" % [data.names.get(item, str(item)), cost])
	ch["gold"] = int(ch["gold"]) - cost
	ch["tools"][skill] = {"item": item, "dur": _tool_max_dur(skill, item)}
	_emit({"k": "tiandi_tool", "id": id, "skill": skill, "act": "buy", "item": item, "gold": cost})
	_msg(id, "天地商行: 代買新%s，花 %d 金" % [data.names.get(item, str(item)), cost])


# 負重滿【自訂=材料件數 > bagMatCap】→ 腳伕搬晒材料: 勾咗嘅入倉 (到倉滿)，其餘賣市集【原】。任務道具唔郁
func _tiandi_haul(id: int, ch: Dictionary) -> void:
	if not bool(ch.get("storageSub", false)):
		return
	var cfg: Dictionary = data.world["tiandi"]
	var view: Array = []
	for s in ch["bag"]:
		if not RulesQuest.is_quest_item(data, int(s["id"])):
			view.append(s)
	if RulesTiandi.mat_load(view, data.mat_skill) <= int(cfg["bagMatCap"]):
		return
	var plan := RulesTiandi.plan_haul(view, data.mat_skill, tiandi_cfg(ch)["deposit"],
		RulesTiandi.stack_total(ch["storage"]), int(cfg["storageCap"]))
	var dep_n := 0
	var sell_n := 0
	var gold := 0
	for d in plan["deposit"]:
		RulesShop.remove_item(ch["bag"], int(d[0]), int(d[1]))
		RulesShop.add_item(ch["storage"], int(d[0]), int(d[1]))
		dep_n += int(d[1])
	for d in plan["sell"]:
		RulesShop.remove_item(ch["bag"], int(d[0]), int(d[1]))
		gold += RulesShop.sell_price(data.prices.get(int(d[0]), 0.0) * market_factor(int(d[0])), expert_lv(ch, "jiaoyi")) * int(d[1])
		sell_n += int(d[1])
	ch["gold"] = int(ch["gold"]) + gold
	_emit({"k": "tiandi_haul", "id": id, "deposit": dep_n, "sell": sell_n, "gold": gold})
	_msg(id, "天地商行腳伕: 存 %d 件入倉，賣 %d 件得 %d 金" % [dep_n, sell_n, gold])


# ================= 捐贈官令 + 行動力 (Step 13, spec 05 §7 / spec 08 §1) =================

# 行動力上限【原】= 頭銜表 ap 欄 (Step 14)；白身 = world.ap.max
func ap_max(ch: Dictionary) -> int:
	return RulesTitle.ap_max(data.titles, int(ch.get("titleRank", 0)), int(data.world["ap"]["max"]))


func ap_of(ch: Dictionary) -> int:
	return int(ch.get("ap", ap_max(ch)))


# 行動丹【原=回滿行動力】(Step 14)
func _use_ap_pill(e: Dictionary, item: int) -> void:
	var id := int(e["id"])
	var ch: Dictionary = e["ch"]
	if ap_of(ch) >= ap_max(ch):
		return _msg(id, "行動力已經滿")
	if not RulesShop.remove_item(ch["bag"], item, 1):
		return _msg(id, "背包冇呢件")
	ch["ap"] = ap_max(ch)
	_msg(id, "食咗行動丹，行動力回滿 (%d)" % int(ch["ap"]))


func _near_donation(e: Dictionary) -> bool:
	return _fac_near(e, "donation") != ""


# 捐金錢【原】3000~50000
func cmd_donate_gold(id: int, amount: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var cfg: Dictionary = data.donation
	var ch: Dictionary = e["ch"]
	if not _near_donation(e):
		return _msg(id, "要去官府捐獻處先得")
	if not RulesTiandi.gold_ok(amount, cfg):
		return _msg(id, "捐獻金額要 %d~%d 金" % [int(cfg["goldMin"]), int(cfg["goldMax"])])
	if int(ch["gold"]) < amount:
		return _msg(id, "金錢不足")
	if ap_of(ch) < int(cfg["apCost"]):
		return _msg(id, "行動力不足 (要 %d)" % int(cfg["apCost"]))
	ch["gold"] = int(ch["gold"]) - amount
	_donate_reward(e, ch, RulesTiandi.donation_fame("gold", amount, cfg), "%d 金" % amount)


# 捐物資【原】: items = [[item id, n], ...]，只收轉換表入面嘅物資；合共 ≥ 100 單位
func cmd_donate_items(id: int, items: Array) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var cfg: Dictionary = data.donation
	var ch: Dictionary = e["ch"]
	if not _near_donation(e):
		return _msg(id, "要去官府捐獻處先得")
	var counts := {}
	for it in items:
		var iid := int(it[0])
		var n := int(it[1])
		if n <= 0 or not data.donation_rates.has(iid) or RulesQuest.is_quest_item(data, iid):
			continue
		counts[iid] = int(counts.get(iid, 0)) + n
	for iid in counts:
		if RulesShop.count_item(ch["bag"], iid) < int(counts[iid]):
			return _msg(id, "背包冇咁多%s" % data.names.get(iid, str(iid)))
	var units := RulesTiandi.donation_units(counts, data.donation_rates)
	if units < int(cfg["unitsMin"]):
		return _msg(id, "物資要 %d 單位以上 (而家 %d)" % [int(cfg["unitsMin"]), units])
	if ap_of(ch) < int(cfg["apCost"]):
		return _msg(id, "行動力不足 (要 %d)" % int(cfg["apCost"]))
	for iid in counts:
		RulesShop.remove_item(ch["bag"], iid, int(counts[iid]))
	_donate_reward(e, ch, RulesTiandi.donation_fame("units", units, cfg), "物資 %d 單位" % units)


# 背包入面可以捐嘅物資 [[id, n]] (UI「捐晒物資」用；任務道具唔計)
func donatable_items(ch: Dictionary) -> Array:
	var out: Array = []
	for s in ch.get("bag", []):
		var iid := int(s["id"])
		if data.donation_rates.has(iid) and not RulesQuest.is_quest_item(data, iid):
			out.append([iid, int(s["n"])])
	return out


# 捐獻成功: 扣行動力 + 名聲 + 魅力經驗【原=三樣都有；數值自訂】
func _donate_reward(e: Dictionary, ch: Dictionary, fame: int, what: String) -> void:
	var id := int(e["id"])
	var cfg: Dictionary = data.donation
	ch["ap"] = ap_of(ch) - int(cfg["apCost"])
	ch["fame"] = int(ch.get("fame", 0)) + fame
	var r := RulesTiandi.cha_gain(int(ch["attrs"]["cha"]), int(ch.get("chaExp", 0)), fame * int(cfg["chaExpPerFame"]), cfg)
	ch["attrs"]["cha"] = int(r["cha"])
	ch["chaExp"] = int(r["exp"])
	_sync_stats(e)
	_emit({"k": "donate", "id": id, "what": what, "fame": fame, "chaUps": int(r["ups"])})
	var tail := "，魅力 +%d" % int(r["ups"]) if int(r["ups"]) > 0 else ""
	_msg(id, "捐獻 %s：名聲 +%d%s" % [what, fame, tail])


# ================= 工作技能 (Step 7.1) =================
const WORK_MIN_LEVEL := 10                                # 【原】10 級可做初階工作技能

# 裝備工具: 背包要有呢件工具，裝上即扣 1 件、開耐久。初階 = starterTool/tool；進階 = tool (Step 12)
func cmd_equip_tool(id: int, skill: String, item: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var sk: Dictionary = _skill_def(skill)
	if sk.is_empty() or String(data.tool_skill.get(item, "")) != skill:
		return _msg(id, "呢件唔係%s工具" % sk.get("name", skill))
	var ch: Dictionary = e["ch"]
	if not RulesShop.remove_item(ch["bag"], item, 1):
		return _msg(id, "背包冇呢件工具")
	var dur := _tool_max_dur(skill, item)
	ch["tools"][skill] = {"item": item, "dur": dur}
	var bonus := _tool_bonus(item)
	var tail := "，成功率 +%d%%" % int(round(bonus * 100)) if bonus > 0.0 else ""
	_msg(id, "裝備咗%s（耐久 %d%s）" % [data.names.get(item, str(item)), dur, tail])


# 初階/進階技能定義 ({} = 冇)
func _skill_def(skill: String) -> Dictionary:
	if data.work.has(skill):
		return data.work[skill]
	return data.work_adv.get(skill, {})


# 專長生效等級 (S01c, spec 01 §8)
func expert_lv(ch: Dictionary, skill_id: String) -> int:
	return RulesExpert.eff_level(data.experts, String(ch.get("classId", "")), skill_id, int(ch.get("expert", {}).get(skill_id, 0)), RulesClass.tier_of(ch))


# 生產技能等級 (未做過: 初階 = 1；進階 = 已解鎖 1 / 未解鎖 0)
func work_lv(ch: Dictionary, skill: String) -> int:
	var w: Dictionary = ch.get("workLv", {}).get(skill, {})
	if w.is_empty():
		return 1 if data.work.has(skill) or adv_unlocked(ch, skill) else 0
	return int(w["lv"])


# 進階技能解鎖咗未【原】: 對應初階 50 級
func adv_unlocked(ch: Dictionary, skill: String) -> bool:
	var ad: Dictionary = data.work_adv.get(skill, {})
	if ad.is_empty():
		return false
	var lvs := {}
	for s in ad["from"]:
		lvs[s] = work_lv(ch, s)
	return RulesWork.adv_unlocked(lvs, ad["from"], int(ad["unlockLv"]))


# 加技能經驗 + 升級訊息；初階升到解鎖級 → 進階技能開 1 級
func _work_gain(id: int, ch: Dictionary, skill: String, amount: int) -> void:
	if not ch.has("workLv"):
		ch["workLv"] = {}
	var w: Dictionary = ch["workLv"].get(skill, {"lv": maxi(1, work_lv(ch, skill)), "exp": 0})
	var r := RulesWork.gain_exp(int(w["lv"]), int(w["exp"]), amount, data.work_meta["level"])
	ch["workLv"][skill] = {"lv": int(r["lv"]), "exp": int(r["exp"])}
	if int(r["ups"]) <= 0:
		return
	_emit({"k": "work_lv", "id": id, "skill": skill, "lv": int(r["lv"])})
	_msg(id, "%s 升到 %d 級！" % [_skill_def(skill).get("name", skill), int(r["lv"])])
	_sync_adv_unlock(id, ch)


# 啱啱夠級解鎖嘅進階技能 → 開 1 級
func _sync_adv_unlock(id: int, ch: Dictionary) -> void:
	for adk in data.work_adv:
		if not ch["workLv"].has(adk) and adv_unlocked(ch, adk):
			ch["workLv"][adk] = {"lv": 1, "exp": 0}
			_msg(id, "解鎖進階技能「%s」！去城內%s做" % [data.work_adv[adk]["name"], _craft_fac_name(adk)])


func _craft_fac_name(skill: String) -> String:
	for k in data.facilities:
		var f = data.facilities[k]
		if f is Dictionary and (f.get("crafts", []) as Array).has(skill):
			return str(f["name"])
	return "工作區"


func cmd_work(id: int, skill: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var sk: Dictionary = data.work.get(skill, {})
	if sk.is_empty():
		return _msg(id, "冇呢種工作")
	var ch: Dictionary = e["ch"]
	if int(ch["level"]) < WORK_MIN_LEVEL:
		return _msg(id, "要 %d 級先做得工作技能" % WORK_MIN_LEVEL)
	if is_safe(int(e["x"]), int(e["y"])):
		return _msg(id, "城內冇得工作，要出城")
	var tool: Dictionary = ch["tools"].get(skill, {})
	if tool.is_empty() or int(tool["dur"]) <= 0:
		return _msg(id, "要裝備%s工具先" % sk["name"])
	var msp := RulesStats.max_sp(int(ch["level"]), ch["attrs"])
	var cost := RulesWork.sp_cost(msp)
	if int(ch["sp"]) < cost:
		return _msg(id, "體力不足 (要 %d SP)" % cost)
	ch["sp"] = int(ch["sp"]) - cost
	var lv := work_lv(ch, skill)
	var cfg: Dictionary = data.work_meta["basicRate"]
	var ok := MathX.roll(rng_fn) < clampf(RulesWork.basic_success(lv, cfg) + _tool_bonus(int(tool["item"])), 0.0, 1.0)
	var item := 0
	var n := 0
	if ok:
		# 材料 tier 按技能等級解鎖 (Step 12；之前用角色等級)
		var materials: Array = sk["materials"]
		var tier := RulesWork.roll_tier(RulesWork.unlocked_tiers(lv, sk["unlockLv"]), rng_fn)
		item = int(materials[tier])
		n = 2 if MathX.roll(rng_fn) < float(cfg["big"]) else 1       # 大成功雙倍
		if n == 1 and sk.has("doubleChance") and MathX.roll(rng_fn) < float(sk["doubleChance"]):
			n = 2       # 農耕/伐木/採礦：額外機率多收 1 件（spec 05 §2「1~2件」）
		RulesShop.add_item(ch["bag"], item, n)
		_master_gather_bonus(id, ch, skill, int(tool["item"]))
	var tool_item := int(tool["item"])
	tool["dur"] = RulesWork.durability_after_use(int(tool["dur"]))
	var broke := int(tool["dur"]) <= 0
	if broke:
		ch["tools"].erase(skill)
	_emit({"k": "work", "id": id, "skill": skill, "item": item, "n": n, "ok": ok, "spCost": cost, "toolBroke": broke})
	var tail := "（工具用爛咗）" if broke else ""
	if ok:
		_msg(id, "%s: 得到 %s%s%s" % [sk["name"], data.names.get(item, str(item)), " x2 大成功！" if n == 2 else "", tail])
	else:
		_msg(id, "%s: 失手，咩都冇%s" % [sk["name"], tail])
	_work_gain(id, ch, skill, int(data.work_meta["level"]["gainOk" if ok else "gainFail"]))
	_tiandi_tools(id, ch, skill, tool_item)
	_tiandi_haul(id, ch)


# ================= 進階生產 + 修理 (Step 12, spec 05 §4) =================

# 附近有冇做呢個進階技能嘅設施
func _near_craft(e: Dictionary, skill: String) -> bool:
	for k in data.facilities:
		var f = data.facilities[k]
		if f is Dictionary and (f.get("crafts", []) as Array).has(skill) and _near(e, int(f["x"]), int(f["y"])):
			return true
	return false


# 附近有冇修理服務設施 (打鐵鋪)
func _near_repair_service(e: Dictionary) -> bool:
	return _fac_near(e, "repair") != ""


func _bag_counts(bag: Array) -> Dictionary:
	var out := {}
	for b in bag:
		out[int(b["id"])] = int(out.get(int(b["id"]), 0)) + int(b["n"])
	return out


# 進階技能共通檢查 (設施/解鎖/等級/工具/SP)；回傳 "" = OK，否則錯誤訊息
func adv_check(e: Dictionary, skill: String, need_lv: int) -> String:
	var ch: Dictionary = e["ch"]
	var ad: Dictionary = data.work_adv.get(skill, {})
	if ad.is_empty():
		return "冇呢種技能"
	if not _near_craft(e, skill):
		return "要喺%s先做得%s" % [_craft_fac_name(skill), ad["name"]]
	if not adv_unlocked(ch, skill):
		var names: Array = []
		for s in ad["from"]:
			names.append(data.work[s]["name"])
		return "%s未解鎖（要%s %d 級）" % [ad["name"], "/".join(names), int(ad["unlockLv"])]
	if work_lv(ch, skill) < need_lv:
		return "%s要 %d 級（而家 %d）" % [ad["name"], need_lv, work_lv(ch, skill)]
	var tool: Dictionary = ch["tools"].get(skill, {})
	if tool.is_empty() or int(tool["dur"]) <= 0:
		return "要裝備%s先" % data.names.get(int(ad["tool"]), "工具")
	if int(ch["sp"]) < RulesWork.sp_cost(RulesStats.max_sp(int(ch["level"]), ch["attrs"])):
		return "體力不足"
	return ""


# 用一次進階工具: 扣 SP + 工具耐久；回傳工具爛咗未
func _adv_use(ch: Dictionary, skill: String) -> bool:
	ch["sp"] = int(ch["sp"]) - RulesWork.sp_cost(RulesStats.max_sp(int(ch["level"]), ch["attrs"]))
	var tool: Dictionary = ch["tools"][skill]
	tool["dur"] = RulesWork.durability_after_use(int(tool["dur"]))
	if int(tool["dur"]) <= 0:
		ch["tools"].erase(skill)
		return true
	return false


# 製作【原=配方/技能；自訂=成功率/失敗扣料】: 成功扣全部材料得成品；失敗 failLoseMat 機會扣材料
func cmd_craft(id: int, item: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var r: Dictionary = data.recipes.get(item, {})
	if r.is_empty():
		return _msg(id, "冇呢個配方")
	var skill := String(r["skill"])
	var err := adv_check(e, skill, int(r["lv"]))
	if err != "":
		return _msg(id, err)
	var ch: Dictionary = e["ch"]
	if not RulesWork.has_materials(_bag_counts(ch["bag"]), r["need"]):
		return _msg(id, "材料唔夠")
	var cfg: Dictionary = data.work_meta["craftRate"]
	var tool_bonus := _tool_bonus(int(ch["tools"][skill]["item"]))
	var ok := MathX.roll(rng_fn) < clampf(RulesWork.craft_chance(work_lv(ch, skill), int(r["lv"]), cfg) + tool_bonus, 0.0, 1.0)
	var lose := ok or MathX.roll(rng_fn) < float(cfg["failLoseMat"])
	if lose:
		for m in r["need"]:
			RulesShop.remove_item(ch["bag"], int(m[0]), int(m[1]))
	if ok:
		RulesShop.add_item(ch["bag"], item, 1)
		_master_gather_bonus(id, ch, skill, int(ch["tools"][skill]["item"]))
	var broke := _adv_use(ch, skill)
	_emit({"k": "craft", "id": id, "skill": skill, "item": item, "ok": ok, "lost": lose, "toolBroke": broke})
	var sn: String = data.work_adv[skill]["name"]
	var tail := "（工具用爛咗）" if broke else ""
	if ok:
		_msg(id, "%s成功：得到「%s」%s" % [sn, data.names.get(item, str(item)), tail])
	else:
		_msg(id, "%s失敗%s%s" % [sn, "，材料冇咗" if lose else "，材料保住", tail])
	_work_gain(id, ch, skill, int(data.work_meta["level"]["gainOk" if ok else "gainFail"]))


# ================= 大宗師合成術 (S05c, spec 05 §5) =================

# 用御賜工具工作/製作時，額外機會夾埋一件大宗師材料（唔加額外 SP/耐久/exp 消耗）
func _master_gather_bonus(id: int, ch: Dictionary, skill: String, tool_item: int) -> void:
	if String(data.tool_tier.get(tool_item, "")) != "godgiven":
		return
	var mat := int(data.master["materials"].get(skill, 0))
	if mat == 0:
		return
	if MathX.roll(rng_fn) < float(data.master["gatherChance"]):
		RulesShop.add_item(ch["bag"], mat, 1)
		_msg(id, "御賜工具顯靈：多得一件「%s」！" % data.names.get(mat, str(mat)))


# 合成一粒大宗師寶石：條件 100/20 + 材料齊
func cmd_master_gem(id: int, skill: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var gc: Dictionary = data.master["gems"].get(skill, {})
	if gc.is_empty():
		return _msg(id, "冇呢種大宗師寶石")
	var ch: Dictionary = e["ch"]
	var basic_lv := work_lv(ch, String(gc["basicFrom"]))
	var adv_lv := work_lv(ch, skill)
	if not RulesMaster.gem_ready(basic_lv, adv_lv, data.master["condition"]):
		return _msg(id, "要 %s 100 級 + %s 20 級先合得（而家 %d / %d）" %
			[data.work[String(gc["basicFrom"])]["name"], data.work_adv[skill]["name"], basic_lv, adv_lv])
	var need: Array = gc["need"]
	if not RulesMaster.has_need(_bag_counts(ch["bag"]), need):
		return _msg(id, "材料唔夠")
	for m in need:
		RulesShop.remove_item(ch["bag"], int(m[0]), int(m[1]))
	var gem := int(gc["item"])
	RulesShop.add_item(ch["bag"], gem, 1)
	_emit({"k": "master_gem", "id": id, "skill": skill, "item": gem})
	_msg(id, "合成成功：得到「%s」" % data.names.get(gem, str(gem)))


# 進階大宗師合成術：2~5 粒寶石（至少 1 粒對應技能）→ 隨機虛擬寶物；成功率跟進階技能等級
func cmd_master_treasure(id: int, skill: String, gems: Array) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	if not data.work_adv.has(skill):
		return _msg(id, "冇呢種技能")
	var cfg: Dictionary = data.master["synth"]
	if not RulesMaster.gem_count_ok(gems.size(), cfg):
		return _msg(id, "要用 %d~%d 粒寶石" % [int(cfg["minGems"]), int(cfg["maxGems"])])
	var my_gem := int(data.master["gems"].get(skill, {}).get("item", -1))
	if not gems.has(my_gem):
		return _msg(id, "至少要 1 粒「%s」對應嘅寶石" % data.work_adv[skill]["name"])
	var ch: Dictionary = e["ch"]
	var counts := {}
	for g in gems:
		counts[int(g)] = int(counts.get(int(g), 0)) + 1
	if not RulesWork.has_materials(_bag_counts(ch["bag"]), counts.keys().map(func(k): return [k, counts[k]])):
		return _msg(id, "寶石唔夠")
	for g in counts:
		RulesShop.remove_item(ch["bag"], int(g), int(counts[g]))
	var ok := MathX.roll(rng_fn) < RulesMaster.synth_chance(work_lv(ch, skill), cfg)
	if ok:
		var treasure := RulesMaster.pick_treasure(data.master["treasures"], rng_fn)
		RulesShop.add_item(ch["bag"], treasure, 1)
		_emit({"k": "master_treasure", "id": id, "skill": skill, "ok": true, "item": treasure})
		_msg(id, "大宗師合成成功：煉出「%s」！" % data.names.get(treasure, str(treasure)))
	else:
		_emit({"k": "master_treasure", "id": id, "skill": skill, "ok": false})
		_msg(id, "大宗師合成失敗，寶石冇咗")


# 兌換白晝之珠（過渡來源，等神秘洞窟場景接正式掉落，見 PLAN §4）
func cmd_master_redeem_baizhu(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var cost := int(data.master["baizhuRedeemContrib"])
	if int(ch.get("contrib", 0)) < cost:
		return _msg(id, "官宅貢獻不足 (要 %d，而家 %d)" % [cost, int(ch.get("contrib", 0))])
	ch["contrib"] = int(ch["contrib"]) - cost
	var item := int(data.master["baizhu"])
	RulesShop.add_item(ch["bag"], item, 1)
	_emit({"k": "master_redeem_baizhu", "id": id, "item": item, "contrib": cost})
	_msg(id, "兌換咗「%s」，扣官宅貢獻 %d" % [data.names.get(item, str(item)), cost])


# read-model：大宗師頁面用（工房 UI）
func view_master(id: int) -> Dictionary:
	var e := ent(id)
	var out := {"gems": [], "treasures": data.master["treasures"], "baizhuCost": int(data.master["baizhuRedeemContrib"])}
	if e.is_empty() or not e.has("ch"):
		return out
	var ch: Dictionary = e["ch"]
	for skill in data.master["gems"]:
		var gc: Dictionary = data.master["gems"][skill]
		var basic_lv := work_lv(ch, String(gc["basicFrom"]))
		var adv_lv := work_lv(ch, skill)
		out["gems"].append({"skill": skill, "name": data.work_adv[skill]["name"], "item": int(gc["item"]),
			"ready": RulesMaster.gem_ready(basic_lv, adv_lv, data.master["condition"]),
			"basicLv": basic_lv, "advLv": adv_lv, "need": gc["need"]})
	return out


# 呢件裝備歸邊個技能修【原】(武器 = 冶鐵、頭/身/靴 = 修繕、戒指/項鍊 = 木匠)；"" = 唔修得
func repair_skill(item: int) -> String:
	var part := "weapon" if data.weapons.has(item) else String(data.armors.get(item, {}).get("slot", ""))
	if part == "":
		return ""
	for sk in data.work_adv:
		if (data.work_adv[sk].get("repairs", []) as Array).has(part):
			return sk
	return ""


# 自己修理要求等級【自訂】: 有配方 = 配方等級 (識整先識修)，冇 = 1
func repair_need_lv(item: int) -> int:
	return int(data.recipes.get(item, {}).get("lv", 1))


func _repair_target(ch: Dictionary, item: int) -> String:
	if RulesShop.count_item(ch["bag"], item) <= 0:
		return "背包冇呢件"
	var mx := _max_dur(item)
	if mx <= 0:
		return "呢件唔使修"
	if int(ch["equip"].get("dur", {}).get(str(item), mx)) >= mx:
		return "「%s」耐久已滿" % data.names.get(item, str(item))
	return ""


# 自己修理【原】: 喺工房用對應進階技能，扣 SP + 工具耐久，回滿耐久
func cmd_repair(id: int, item: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var err := _repair_target(ch, item)
	if err != "":
		return _msg(id, err)
	var skill := repair_skill(item)
	err = adv_check(e, skill, repair_need_lv(item))
	if err != "":
		return _msg(id, err)
	ch["equip"]["dur"][str(item)] = _max_dur(item)
	var broke := _adv_use(ch, skill)
	_emit({"k": "repair", "id": id, "item": item, "skill": skill, "gold": 0, "toolBroke": broke})
	_msg(id, "用%s修好「%s」%s" % [data.work_adv[skill]["name"], data.names.get(item, str(item)), "（工具用爛咗）" if broke else ""])
	_work_gain(id, ch, skill, int(data.work_meta["level"]["gainOk"]))


# 修理服務費 (打鐵鋪)
func repair_service_cost(ch: Dictionary, item: int) -> int:
	var mx := _max_dur(item)
	return RulesWork.repair_cost(float(data.prices.get(item, 0.0)), int(ch["equip"].get("dur", {}).get(str(item), mx)), mx,
		float(data.work_meta["repair"]["serviceRate"]))


# 修理服務【原】: 打鐵鋪俾錢修 (費用【自訂】)
func cmd_repair_service(id: int, item: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	if not _near_repair_service(e):
		return _msg(id, "要喺打鐵鋪先修得")
	var ch: Dictionary = e["ch"]
	var err := _repair_target(ch, item)
	if err != "":
		return _msg(id, err)
	var cost := repair_service_cost(ch, item)
	if int(ch["gold"]) < cost:
		return _msg(id, "唔夠錢（要 %d 金）" % cost)
	ch["gold"] = int(ch["gold"]) - cost
	ch["equip"]["dur"][str(item)] = _max_dur(item)
	_emit({"k": "repair", "id": id, "item": item, "skill": "", "gold": cost})
	_msg(id, "打鐵鋪修好「%s」，收 %d 金" % [data.names.get(item, str(item)), cost])


# debug 用: 所有初階生產技能 +add 級 (夠 50 就解鎖進階；已解鎖進階都 +add)；成品前移除
func cmd_debug_work_lv(id: int, add: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var ch: Dictionary = e["ch"]
	if not ch.has("workLv"):
		ch["workLv"] = {}
	var mx := int(data.work_meta["level"]["max"])
	for sk in data.work_adv:
		if ch["workLv"].has(sk):
			ch["workLv"][sk] = {"lv": clampi(work_lv(ch, sk) + add, 1, mx), "exp": 0}
	for sk in data.work:
		ch["workLv"][sk] = {"lv": clampi(work_lv(ch, sk) + add, 1, mx), "exp": 0}
	_msg(id, "（測試）生產技能 +%d 級" % add)
	_sync_adv_unlock(id, ch)


# ================= 裝備: 武器 3 槽 + 5 部位防具 (Step 10/11.6, spec 02 §9) =================
# 裝備 = 背包參照 (件嘢留喺背包)；身上已裝嘅件數唔可以賣/存/死亡跌

func _locked_by_equip(ch: Dictionary, item: int, n: int) -> bool:
	return _equipped_n(ch, item) > 0 and RulesShop.count_item(ch["bag"], item) - n < _equipped_n(ch, item)


# 武器可唔可以用: 職業武器類【原】(classes.json weapons = items cat_label)
func _weapon_ok(ch: Dictionary, item: int) -> bool:
	var cls: Dictionary = data.classes.get(str(ch.get("classId", "")), {})
	return (cls.get("weapons", []) as Array).has(str(data.info.get(item, {}).get("cat_label", "")))


# 通用裝備: 武器 → 武器槽 wslot (-1 = 現用槽)；防具 → 按部位 (b54_59 部位碼)。背包要有、等級夠
func cmd_equip(id: int, item: int, wslot: int = -1) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var eq: Dictionary = ch["equip"]
	var need_lv := int(data.info.get(item, {}).get("req_lv", 0))
	var nm: String = data.names.get(item, str(item))
	if data.armors.has(item):
		var slot: String = data.armors[item]["slot"]
		if int(eq[slot]) == item:
			return _msg(id, "已經著緊「%s」" % nm)
		if not RulesShop.has_item(ch["bag"], item, 1):
			return _msg(id, "背包冇呢件裝備")
		if int(ch["level"]) < need_lv:
			return _msg(id, "要 Lv%d 先著得「%s」" % [need_lv, nm])
		eq[slot] = item
		if not eq["dur"].has(str(item)):
			eq["dur"][str(item)] = int(data.armors[item]["max_dur"])
		_emit({"k": "equip", "src": id, "slot": slot, "item": item})
		return _msg(id, "著上「%s」" % nm)
	if not data.weapons.has(item):
		return _msg(id, "呢件唔係武器或防具")
	if not RulesShop.has_item(ch["bag"], item, 1):
		return _msg(id, "背包冇呢件武器")
	if not _weapon_ok(ch, item):
		return _msg(id, "%s用唔到「%s」" % [data.classes.get(str(ch["classId"]), {}).get("name", "呢個職業"), nm])
	if int(ch["level"]) < need_lv:
		return _msg(id, "要 Lv%d 先用得「%s」" % [need_lv, nm])
	# S01d 進階武器解鎖【自訂】(spec 01 §7): req_lv 51+ 武器要二轉、100+ 要三轉；承繼 = 初階武器照用
	var treq := RulesClass.weapon_tier_required(need_lv)
	if RulesClass.tier_of(ch) < treq:
		return _msg(id, "要%s先用得進階武器「%s」" % [RulesClass.tier_name_of(treq), nm])
	var ws := int(eq["wslot"]) if wslot < 0 else wslot
	if ws < 0 or ws >= RulesEquip.WEAPON_SLOTS:
		return _msg(id, "武器槽得 %d 格" % RulesEquip.WEAPON_SLOTS)
	# 同一件武器背包得 1 件 → 由其他槽搬過嚟
	if RulesShop.count_item(ch["bag"], item) <= _equipped_n(ch, item) - (1 if int(eq["weapons"][ws]) == item else 0):
		for i in RulesEquip.WEAPON_SLOTS:
			if i != ws and int(eq["weapons"][i]) == item:
				eq["weapons"][i] = 0
				break
	eq["weapons"][ws] = item
	eq["weapon"] = int(eq["weapons"][int(eq["wslot"])])
	if not eq["dur"].has(str(item)):
		eq["dur"][str(item)] = _max_dur(item)          # 武器耐久 (Step 12)
	_emit({"k": "equip", "src": id, "slot": "weapon", "wslot": ws, "item": item})
	_msg(id, "裝備咗「%s」%s" % [nm, "" if ws == int(eq["wslot"]) else "（武器槽 %d）" % (ws + 1)])


# 卸下: part = head/body/boots/ring/necklace 或 "weapon" (wslot -1 = 現用槽)
func cmd_unequip(id: int, part: String, wslot: int = -1) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var eq: Dictionary = e["ch"]["equip"]
	var item := 0
	if part == "weapon":
		var ws := int(eq["wslot"]) if wslot < 0 else wslot
		if ws < 0 or ws >= RulesEquip.WEAPON_SLOTS:
			return
		item = int(eq["weapons"][ws])
		eq["weapons"][ws] = 0
		eq["weapon"] = int(eq["weapons"][int(eq["wslot"])])
	elif RulesEquip.SLOTS.has(part):
		item = int(eq[part])
		eq[part] = 0
	if item == 0:
		return
	_emit({"k": "equip", "src": id, "slot": part, "item": 0})
	_msg(id, "卸下「%s」" % data.names.get(item, str(item)))


# 切換武器槽【原】(Alt+A/S/D)；空槽都切得 (= 空手)
func cmd_switch_weapon(id: int, wslot: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or wslot < 0 or wslot >= RulesEquip.WEAPON_SLOTS:
		return
	var eq: Dictionary = e["ch"]["equip"]
	eq["wslot"] = wslot
	eq["weapon"] = int(eq["weapons"][wslot])
	e["ch"].erase("fusing")
	_emit({"k": "equip", "src": id, "slot": "weapon", "wslot": wslot, "item": int(eq["weapon"])})
	_msg(id, "切換武器槽 %d：%s" % [wslot + 1, data.names.get(int(eq["weapon"]), "空手")])


# 舊指令保留做包裝 (Step 10)
func cmd_equip_weapon(id: int, item: int) -> void:
	cmd_equip(id, item, -1)


# 寶石欄裝卸 (2 格): 背包要有，裝備唔消耗。item=0 = 清空。slot 0 = 攻擊用屬性石
func cmd_equip_jewel(id: int, item: int, slot: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	if slot < 0 or slot > 1:
		return _msg(id, "寶石欄得 2 格")
	var ch: Dictionary = e["ch"]
	if item == 0:
		var old := int(ch["equip"]["jewels"][slot])
		if old != 0:
			_unequip_jewel_sync(ch, old)
		ch["equip"]["jewels"][slot] = 0
		_emit({"k": "jewel", "src": id, "slot": slot, "item": 0})
		return _msg(id, "寶石欄 %d 已清空" % (slot + 1))
	var jd: Dictionary = data.jewel_by_item.get(item, {})
	if jd.is_empty():
		return _msg(id, "呢件唔係寶石")
	if not RulesShop.has_item(ch["bag"], item, 1):
		return _msg(id, "背包冇呢粒寶石")
	var dup := int(ch["equip"]["jewels"][0]) == item or int(ch["equip"]["jewels"][1]) == item
	if dup:
		return _msg(id, "已經裝緊呢粒寶石")
	var full := (int(ch["equip"]["jewels"][0]) != 0 and slot == 0) or (int(ch["equip"]["jewels"][1]) != 0 and slot == 1)
	if full:
		_unequip_jewel_sync(ch, int(ch["equip"]["jewels"][slot]))
	ch["equip"]["jewels"][slot] = item
	_emit({"k": "jewel", "src": id, "slot": slot, "item": item})
	_msg(id, "裝咗「%s」落寶石欄 %d" % [jd["name"], slot + 1])


# 裝/卸石後: clamp 血/氣到有效上限 (輔助石 HP/MP/SP 加成)
func _unequip_jewel_sync(ch: Dictionary, item: int) -> void:
	var lv := int(ch["level"])
	var bonus_before := RulesJewel.support_bonus(data.jewel_by_item.get(item, {}).get("effects", []))
	var extra_hp := MathX.js_round(RulesStats.max_hp(lv, ch["attrs"]) * float(bonus_before.get("hpPct", 0.0)))
	var extra_mp := MathX.js_round(RulesStats.max_mp(lv, ch["attrs"]) * float(bonus_before.get("mpPct", 0.0)))
	var extra_sp := int(bonus_before.get("spFlat", 0))
	ch["hp"] = maxi(1, int(ch["hp"]) - extra_hp)
	ch["mp"] = maxi(0, int(ch["mp"]) - extra_mp)
	ch["sp"] = maxi(0, int(ch["sp"]) - extra_sp)
