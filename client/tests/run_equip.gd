extends SceneTree
# Step 11.6 測試 (spec 02 §9, spec 03 §4.3): 裝備欄 / 裝卸 / 武器 3 槽 / 戰鬥接入 / 耐久 / 存檔兼容 / 掉落 + 防具店
# 跑: Godot --headless --path client --script tests/run_equip.gd  (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_data(data)
	t_new_char(data)
	t_equip_armor(data)
	t_sell_guard(data)
	t_weapon_slots(data)
	t_combat_def(data)
	t_bonus_caps(data)
	t_durability(data)
	t_death_keeps_equip(data)
	t_save_roundtrip(data)
	t_old_save_compat(data)
	t_drops_and_shop(data)
	print("[TEST] equip scenarios: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


func _put(sim: Sim, id: int, x: int, y: int) -> void:
	var e := sim.ent(id)
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y


func _new(data: GameData, seed: int = 7, cls: String = "yishi") -> Array:
	var sim := Sim.new(data, seed)
	var pid := sim.spawn_player("t", cls)
	return [sim, pid]


# 部位碼對照: 全部 cat 19~31 防具都有部位，部位同 cat 一致
func t_data(data: GameData) -> void:
	var want := {19: "head", 20: "head", 21: "head", 22: "head", 23: "head", 24: "head",
		25: "body", 26: "body", 27: "body", 28: "body", 29: "boots", 30: "ring", 31: "necklace"}
	var bad := 0
	var n := 0
	for id in data.cats:
		var c := int(data.cats[id])
		if want.has(c):
			n += 1
			if str(data.armors.get(id, {}).get("slot", "")) != want[c]:
				bad += 1
	check(n > 1900 and bad <= 1, "部位碼: cat 19~31 共 %d 件，對唔上 %d 件 (容許 1 件原版怪資料)" % [n, bad])
	var a: Dictionary = data.armors[16001]            # 奔狼頭帶 物防2 術防1
	check(int(a["stats"]["def"]) == 2 and int(a["stats"]["sdef"]) == 1 and int(a["max_dur"]) == 50, "奔狼頭帶: 物防 2 術防 1 耐久 50")
	check(int(data.armors[16003]["max_dur"]) == 50 + 5 * 51, "Lv51 防具耐久 = 50 + 5×51")
	check(int(data.armors[23057]["stats"]["resist"].get("hex", 0)) == 10, "驅邪戒指: 迴避中邪 10%")


func t_new_char(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var ch := sim.player_ch()
	var eq: Dictionary = ch["equip"]
	check(RulesShop.count_item(ch["bag"], 10001) == 1 and RulesShop.count_item(ch["bag"], 22001) == 1, "開場: 武器/靴喺背包")
	check(eq["weapons"] == [10001, 0, 0] and int(eq["wslot"]) == 0 and int(eq["weapon"]) == 10001, "開場: 武器槽 1 = 柳葉刀")
	check(int(eq["boots"]) == 22001 and int(eq["head"]) == 0 and int(eq["body"]) == 0, "開場: 著草鞋，其他部位空")
	check(int(eq["dur"]["22001"]) == 50, "開場: 草鞋耐久 50")
	var r2 := _new(data, 7, "daoshi")
	var ch2: Dictionary = (r2[0] as Sim).player_ch()
	check(int(ch2["equip"]["weapon"]) == 14001 and RulesShop.count_item(ch2["bag"], 14001) == 1, "道士開場: 麻布幡喺背包 + 裝備")


func t_equip_armor(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch := sim.player_ch()
	sim.cmd_equip(pid, 16001)
	check(int(ch["equip"]["head"]) == 0, "背包冇就唔裝得")
	sim.cmd_debug_give(pid, 16001, 1)
	sim.cmd_equip(pid, 16001)
	check(int(ch["equip"]["head"]) == 16001 and int(ch["equip"]["dur"]["16001"]) == 50, "裝頭帶: 頭部 + 耐久 50")
	var ab := sim._armor_bonus(ch)
	check(int(ab["def"]) == 3 and int(ab["sdef"]) == 1 and int(ab["evade"]) == 1, "頭帶+草鞋: 物防 3 術防 1 物迴避 1 (got %s)" % ab)
	sim.cmd_debug_give(pid, 17001, 1)
	sim.cmd_equip(pid, 17001)                           # 同部位換: 清心方巾
	check(int(ch["equip"]["head"]) == 17001 and RulesShop.count_item(ch["bag"], 16001) == 1, "同部位換裝: 舊件留喺背包")
	sim.cmd_debug_give(pid, 16003, 1)                   # Lv51 血焰頭帶
	sim.cmd_equip(pid, 16003)
	check(int(ch["equip"]["head"]) == 17001, "等級唔夠唔裝得")
	sim.cmd_equip(pid, 65210)
	check(int(ch["equip"]["head"]) == 17001 and int(ch["equip"]["weapon"]) == 10001, "藥水唔係裝備")
	sim.cmd_unequip(pid, "head")
	check(int(ch["equip"]["head"]) == 0 and RulesShop.count_item(ch["bag"], 17001) == 1, "卸下: 部位清空，件嘢仲喺背包")
	sim.cmd_unequip(pid, "boots")
	check(int(sim._armor_bonus(ch)["def"]) == 0, "全部卸晒: 物防 0")


func t_sell_guard(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch := sim.player_ch()
	ch["storageSub"] = true
	sim.cmd_debug_give(pid, 16001, 1)
	sim.cmd_equip(pid, 16001)
	sim.cmd_storage_sell(pid, 16001, 1)
	check(RulesShop.count_item(ch["bag"], 16001) == 1, "裝備中唔可以代賣")
	sim.cmd_storage_deposit(pid, 16001, 1)
	check(RulesShop.count_item(ch["bag"], 16001) == 1, "裝備中唔可以存倉")
	sim.cmd_debug_give(pid, 16001, 1)
	sim.cmd_storage_sell(pid, 16001, 1)
	check(RulesShop.count_item(ch["bag"], 16001) == 1 and int(ch["equip"]["head"]) == 16001, "有 2 件: 賣走多出嗰件，身上嗰件保留")
	sim.cmd_storage_sell(pid, 10001, 1)
	check(RulesShop.count_item(ch["bag"], 10001) == 1, "裝備中武器唔可以賣")
	sim.cmd_unequip(pid, "head")
	sim.cmd_storage_sell(pid, 16001, 1)
	check(RulesShop.count_item(ch["bag"], 16001) == 0 and not ch["equip"]["dur"].has("16001"), "卸咗先賣得；耐久記錄清走")


func t_weapon_slots(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch := sim.player_ch()
	var eq: Dictionary = ch["equip"]
	sim.cmd_debug_give(pid, 10042, 1)                   # 飛鷹寶戟 (槍矛)
	sim.cmd_equip(pid, 10042, 1)
	check(eq["weapons"] == [10001, 10042, 0] and int(eq["weapon"]) == 10001, "武器槽 2 裝戟，現用仍係刀")
	sim.cmd_switch_weapon(pid, 1)
	check(int(eq["wslot"]) == 1 and int(eq["weapon"]) == 10042, "切去槽 2: 現用 = 戟")
	sim.cmd_equip(pid, 10042, 2)                        # 得 1 件 → 由槽 2 搬去槽 3
	check(eq["weapons"] == [10001, 0, 10042] and int(eq["weapon"]) == 0, "得 1 件: 搬槽，槽 2 變空 (現用空手)")
	sim.cmd_switch_weapon(pid, 2)
	check(int(eq["weapon"]) == 10042, "切去槽 3")
	sim.cmd_unequip(pid, "weapon")
	check(int(eq["weapon"]) == 0 and eq["weapons"] == [10001, 0, 0], "卸現用武器")
	sim.cmd_switch_weapon(pid, 0)
	sim.cmd_equip_weapon(pid, 10042)                    # 舊指令包裝: 入現用槽
	check(eq["weapons"] == [10042, 0, 0] and int(eq["weapon"]) == 10042, "cmd_equip_weapon 包裝: 取代現用槽")
	sim.cmd_debug_give(pid, 14001, 1)
	sim.cmd_equip(pid, 14001)
	check(int(eq["weapon"]) == 10042, "義士用唔到幡 (職業武器類【原】)")
	sim.cmd_debug_give(pid, 10002, 1)                   # 鬼頭刀 Lv10
	sim.cmd_equip(pid, 10002)
	check(int(eq["weapon"]) == 10042, "等級唔夠唔用得武器")
	var r2 := _new(data, 7, "daoshi")
	var s2: Sim = r2[0]
	s2.cmd_debug_give(r2[1], 14013, 1)
	s2.cmd_equip(r2[1], 14013)
	check(int(s2.player_ch()["equip"]["weapon"]) == 14013, "道士用得拂塵")
	s2.cmd_equip(r2[1], 10001)
	check(int(s2.player_ch()["equip"]["weapon"]) == 14013, "道士用唔到刀")


# 同一粒種子: 著咗 物防 17 嘅衣，平均受傷明顯低
func _mob_hits(data: GameData, body: int) -> Array:
	var sim := Sim.new(data, 21)
	var pid := sim.spawn_player("t")
	sim.cmd_unequip(pid, "boots")                        # 排除草鞋迴避，只比物防
	if body > 0:
		sim.cmd_debug_give(pid, body, 1)
		sim.cmd_equip(pid, body)
	var m: Dictionary = sim._spawn_mob(12012, "field_1")   # 野狗 atk 28
	var p := sim.ent(pid)
	_put(sim, m["id"], 60, 60)                           # 野外 (60,60 非安全區): 城內唔准打人，隨機 spawn 可能落安全區
	m["mob"]["home_x"] = 60                              # home 都要跟，否則超出 leash 即脫戰
	m["mob"]["home_y"] = 60
	_put(sim, pid, 61, 60)
	m["mob"]["state"] = "chase"
	m["mob"]["target"] = pid
	var hits: Array = []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if str(ev.get("k", "")) == "hit" and int(ev.get("dst", 0)) == pid:
			hits.append(int(ev["dmg"])))
	for i in 300:
		p["ch"]["hp"] = 9999
		p["hp"] = 9999
		sim.step()
	return hits


func t_combat_def(data: GameData) -> void:
	var bare := _mob_hits(data, 0)
	var worn := _mob_hits(data, 21003)                   # 牡丹蝶衣 物防 17
	var avg := func(a: Array) -> float:
		var s := 0.0
		for x in a:
			s += x
		return s / maxf(1.0, a.size())
	check(bare.size() >= 10 and worn.size() == bare.size(), "戰鬥: 同種子受擊次數一樣 (%d/%d)" % [bare.size(), worn.size()])
	check(avg.call(bare) - avg.call(worn) > 14.0, "戰鬥: 物防 17 → 平均受傷減 >14 (%.1f → %.1f)" % [avg.call(bare), avg.call(worn)])


func t_bonus_caps(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch := sim.player_ch()
	sim.cmd_debug_give(pid, 22072, 1)                   # GM御用頭: 物迴避 100
	sim.cmd_equip(pid, 22072)
	var ab := sim._armor_bonus(ch)
	check(int(ab["evade"]) == 101, "GM 頭 + 草鞋: 物迴避 101%")
	check(absf(RulesEquip.evade_chance(int(ab["evade"]), 0.0, int(data.equip_cfg["caps"]["evadePct"])) - 0.6) < 1e-9, "迴避率夾 60%")
	sim.cmd_debug_give(pid, 22097, 1)                   # GM御用腳環 (靴): 物防 888 受擊 -100%
	sim.cmd_equip(pid, 22097)
	check(int(ch["equip"]["boots"]) == 22097, "GM 腳環入靴位 (取代草鞋)")
	check(RulesEquip.reduce_dmg(300, int(sim._armor_bonus(ch)["dmgRed"]), 50) == 150, "受擊減少夾 50%")
	sim.cmd_debug_give(pid, 24004, 1)                   # 佛珠項鍊: 靈力 +1
	sim.cmd_equip(pid, 24004)
	check(absf(sim._eff_attr(ch, "spi") - float(ch["attrs"]["spi"]) - 1.0) < 1e-9, "項鍊靈力 +1 入有效屬性")


func t_durability(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch := sim.player_ch()
	var p := sim.ent(pid)
	sim.cmd_debug_give(pid, 21003, 1)
	sim.cmd_equip(pid, 21003)
	var mob: Dictionary = sim._spawn_mob(12012, "field_1")
	for i in 9:
		sim.damage(p, 1, mob)
	check(int(ch["equip"]["dur"]["21003"]) == 50 and int(ch["equip"]["dur"]["22001"]) == 50, "受擊 9 下: 未磨損")
	sim.damage(p, 1, mob)
	check(int(ch["equip"]["dur"]["21003"]) == 49 and int(ch["equip"]["dur"]["22001"]) == 49, "受擊第 10 下: 每件 -1")
	sim.damage(p, 0, mob)
	check(int(ch["equip"]["hits"]) == 10, "0 傷害唔計受擊")
	ch["equip"]["dur"]["21003"] = 0
	check(int(sim._armor_bonus(ch)["def"]) == 8 + 1, "耐久 0: 物防 17 → 8 (減半，唔消失)")
	ch["equip"]["dur"]["21003"] = 20
	p["hp"] = 1
	ch["hp"] = 1
	sim.damage(p, 99, mob)                             # 死亡
	check(int(ch["equip"]["dur"]["21003"]) == 15 and int(ch["equip"]["dur"]["22001"]) == 44, "死亡: 每件扣 10%% 上限 (20→15, 49→44)")
	check(int(ch["equip"]["body"]) == 21003, "死亡: 仍然著住")


# 惡人死亡 50% 跌嘢: 身上裝備永遠唔跌
func t_death_keeps_equip(data: GameData) -> void:
	var ok := true
	for seed in range(1, 40):
		var r := _new(data, seed)
		var sim: Sim = r[0]
		var pid: int = r[1]
		var ch := sim.player_ch()
		ch["karma"] = -30000
		ch["bag"] = [{"id": 10001, "n": 1}, {"id": 22001, "n": 1}]
		var p := sim.ent(pid)
		sim.damage(p, 99999, {})
		if RulesShop.count_item(ch["bag"], 10001) != 1 or RulesShop.count_item(ch["bag"], 22001) != 1:
			ok = false
	check(ok, "死亡: 背包只得身上裝備 → 永遠唔跌")


func t_save_roundtrip(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	sim.cmd_debug_give(pid, 16001, 1)
	sim.cmd_equip(pid, 16001)
	sim.cmd_debug_give(pid, 10042, 1)
	sim.cmd_equip(pid, 10042, 2)
	sim.cmd_switch_weapon(pid, 2)
	sim.player_ch()["equip"]["dur"]["16001"] = 33
	var s1 := sim.save_string()
	var loaded := Sim.load_string(data, s1)
	var eq: Dictionary = loaded.player_ch()["equip"]
	check(int(eq["head"]) == 16001 and int(eq["dur"]["16001"]) == 33, "存檔: 頭部 + 耐久 roundtrip")
	check(eq["weapons"] == [10001, 0, 10042] and int(eq["wslot"]) == 2 and int(eq["weapon"]) == 10042, "存檔: 武器 3 槽 roundtrip")
	check(loaded.save_string() == s1, "存檔: save→load→save 一致")
	loaded.cmd_unequip(pid, "head")
	check(int(loaded.player_ch()["equip"]["head"]) == 0, "讀檔後可以卸 (dur key 係 String 都得)")


# 舊存檔: equip 得 weapon/boots，開場武器/靴唔喺背包
func t_old_save_compat(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var d: Dictionary = JSON.parse_string(sim.save_string())
	var ech: Dictionary = d["state"]["ents"][str(pid)]["ch"]
	ech["equip"] = {"weapon": 10001, "boots": 22001, "spellbooks": [0, 0, 0], "jewels": [0, 0]}
	ech["bag"] = [{"id": 65210, "n": 5}]
	var loaded := Sim.load_string(data, JSON.stringify(d))
	var ch := loaded.player_ch()
	var eq: Dictionary = ch["equip"]
	check(eq["weapons"] == [10001, 0, 0] and int(eq["weapon"]) == 10001, "舊存檔: weapon → weapons[0]")
	check(int(eq["boots"]) == 22001 and int(eq["dur"]["22001"]) == 50 and int(eq["head"]) == 0, "舊存檔: boots 保留 + 耐久補滿 + 新部位 0")
	check(RulesShop.count_item(ch["bag"], 10001) == 1 and RulesShop.count_item(ch["bag"], 22001) == 1, "舊存檔: 身上裝備補返入背包")


func t_drops_and_shop(data: GameData) -> void:
	# 1~10 級怪至少有一隻掉防具 (跟原版掉落，唔加保底)
	var found := []
	for id in data.monsters:
		var m: Dictionary = data.monsters[id]
		if int(m["level"]) > 10:
			continue
		for dr in (m["drops"] as Array) + (m.get("rareDrops", []) as Array):
			if data.armors.has(int(dr["item"])) and float(dr["p"]) > 0.0:
				found.append(int(dr["item"]))
	check(found.size() >= 1, "1~10 級怪有防具掉落 (%d 項)" % found.size())
	var shop: Dictionary = {}
	for s in data.shops:
		if str(s["id"]) == "armor":
			shop = s
	check(not shop.is_empty(), "防具店存在")
	var slots := {}
	for it in shop.get("stock", []):
		slots[str(data.armors.get(int(it), {}).get("slot", "?"))] = true
	check(slots.size() == 5 and not slots.has("?"), "防具店: 5 個部位都有貨，全部係防具")
	# 喺防具店買 + 即刻著
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	_put(sim, pid, int(shop["x"]), int(shop["y"]) + 1)
	sim.player_ch()["gold"] = 1000
	sim.cmd_buy(pid, 19001, 1)                          # 奔狼戰袍 250
	sim.cmd_equip(pid, 19001)
	check(int(sim.player_ch()["equip"]["body"]) == 19001, "防具店買戰袍 + 著上")
