extends "res://sim/sim_char.gd"
# Sim 繼承鏈 第 4 層: 客棧 / 商店 / 消耗品 / 天地商行 / 工作技能 / 武器寶石裝備

func cmd_rest(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var inn := _inn_near(e)
	if inn.is_empty():
		return _msg(id, "要喺客棧附近先可以休息")
	var cost := int(inn["restCost"])
	var ch: Dictionary = e["ch"]
	if int(ch["gold"]) < cost:
		return _msg(id, "住宿要 %d 金" % cost)
	ch["gold"] = int(ch["gold"]) - cost
	_full_heal(ch)
	_sync_stats(e)
	_msg(id, "休息完畢，花 %d 金" % cost)


func _inn_near(e: Dictionary) -> Dictionary:
	for x in data.inns:
		if _near(e, int(x["x"]), int(x["y"])):
			return x
	return {}


func _shop_for(e: Dictionary) -> Dictionary:
	for s in data.shops:
		if _near(e, int(s["x"]), int(s["y"])):
			return s
	return {}


func cmd_buy(id: int, item: int, n: int = 1) -> void:
	var e := ent(id)
	n = mini(99, n)
	if e.is_empty() or not e.has("ch") or n < 1:
		return
	var shop := _shop_for(e)
	if shop.is_empty():
		return _msg(id, "附近冇商店")
	var stock: Array = shop["stock"]
	if not stock.has(item) and not stock.has(float(item)):
		return _msg(id, "呢間店唔賣呢件")
	var ch: Dictionary = e["ch"]
	var cost := RulesShop.buy_price(data.prices.get(item, 0.0) * market_factor(item), ch["attrs"]["cha"], int(ch["karma"])) * n
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
	var gain := RulesShop.sell_price(data.prices.get(item, 0.0) * market_factor(item)) * n
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
	if not bool(ch.get("storageSub", false)):
		return _msg(id, "要先訂閱天地商行")
	if _locked_by_equip(ch, item, n):
		return _msg(id, "裝備中，唔可以存 (先卸下)")
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
	if not bool(ch.get("storageSub", false)):
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
	var gain := RulesShop.sell_price(data.prices.get(item, 0.0) * market_factor(item)) * n
	ch["gold"] = int(ch["gold"]) + gain
	_cleanup_dur(ch)
	_msg(id, "天地商行代賣 %d 件，得 %d 金" % [n, gain])


# ================= 工作技能 (Step 7.1) =================
const WORK_MIN_LEVEL := 10                                # 【原】10 級可做初階工作技能

# 裝備工具: 背包要有呢件工具，裝上即扣 1 件、開耐久 (starterTool 或 tool 都得)
func cmd_equip_tool(id: int, skill: String, item: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var sk: Dictionary = data.work.get(skill, {})
	if sk.is_empty() or (int(sk["tool"]) != item and int(sk["starterTool"]) != item):
		return _msg(id, "呢件唔係%s工具" % sk.get("name", skill))
	var ch: Dictionary = e["ch"]
	if not RulesShop.remove_item(ch["bag"], item, 1):
		return _msg(id, "背包冇呢件工具")
	var dur: int = int(data.work_meta.get("toolDurability", {}).get("starter" if int(sk["starterTool"]) == item else "normal", 50))
	ch["tools"][skill] = {"item": item, "dur": dur}
	_msg(id, "裝備咗%s（耐久 %d）" % [data.names.get(item, str(item)), dur])


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
	var materials: Array = sk["materials"]
	var unlocked := RulesWork.unlocked_tiers(int(ch["level"]), sk["unlockLv"])
	var tier := RulesWork.roll_tier(unlocked, rng_fn)
	var item := int(materials[tier])
	RulesShop.add_item(ch["bag"], item, 1)
	tool["dur"] = RulesWork.durability_after_use(int(tool["dur"]))
	var broke := int(tool["dur"]) <= 0
	if broke:
		ch["tools"].erase(skill)
	_emit({"k": "work", "id": id, "skill": skill, "item": item, "spCost": cost, "toolBroke": broke})
	_msg(id, "%s: 得到 %s%s" % [sk["name"], data.names.get(item, str(item)), "（工具用爛咗）" if broke else ""])


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
