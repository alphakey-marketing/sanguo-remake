extends SceneTree
# 寶石/絕招/融合/絕招任務鏈測試 (Step 10, spec 02 §4~5, spec 06 §5):
# RulesJewel 公式 / 寶石欄裝卸 + HP 加成 / 元素術需要特殊石 / 武器裝備 /
# 絕招框架 (學識/武器檢查/MP/SP/冷卻/範圍/安全區) / 融合 QTE + 嵌石 /
# 義士三招絕招任務鏈端到端 / 存檔 roundtrip
# 跑: Godot --headless --path client --script tests/run_jewel_ult.gd   (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_rules_jewel()
	t_support_bonus()
	t_fusion_rules()
	t_jewel_eq(data)
	t_equip_weapon(data)
	t_cast_need_jewel(data)
	t_ultimate_framework(data)
	t_fusion_sim(data)
	t_ult_quest_chain(data)
	t_save_roundtrip(data)
	print("[TEST] jewel/ultimate scenarios: %d, fail %d" % [total, fails])
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


func _bag_n(sim: Sim, id: int, item: int) -> int:
	for b in sim.ent(id)["ch"]["bag"]:
		if int(b["id"]) == item:
			return int(b["n"])
	return 0


func _talk(sim: Sim, id: int, npc: String) -> void:
	var n: Dictionary = sim.data.quest_npcs.get(npc, {})
	if not n.is_empty():
		_put(sim, id, int(n["x"]), int(n["y"]))
	sim.cmd_quest_talk(id, npc)


func _vis(sim: Sim, npc: String) -> bool:
	return bool(sim.state["quest_npcs"].get(npc, {}).get("visible", false))


func _mob_pos(sim: Sim) -> Array:
	var out: Array = []
	for e in sim.ents.values():
		if e["kind"] == "mob":
			out.append("%d@(%d,%d)%s" % [int(e["id"]), int(e["x"]), int(e["y"]), "D" if int(e["hp"]) <= 0 else ""])
	return out


func _mob_count(sim: Sim) -> int:
	var n := 0
	for e in sim.ents.values():
		if e["kind"] == "mob" and int(e["hp"]) > 0:
			n += 1
	return n


func _bag_stones(sim: Sim, id: int) -> Array:
	var out: Array = []
	for b in sim.ent(id)["ch"]["bag"]:
		var jd: Dictionary = sim.data.jewel_by_item.get(int(b["id"]), {})
		if not jd.is_empty() and str(jd.get("kind", "")) == "stone":
			out.append(int(b["id"]))
	return out


# spawn 一隻怪攞返 id (except_id = 唔好用返前一隻)
func _spawn_one(sim: Sim, def_id: int, except_id: int = 0) -> int:
	sim._spawn_mob(def_id)
	var best := 0
	for e in sim.ents.values():
		if e["kind"] == "mob" and int(e["mob"]["def"]) == def_id and int(e["id"]) != except_id:
			if int(e["id"]) > best:
				best = int(e["id"])
	return best


# ---------- RulesJewel: 相剋加成表 + 術法加成 ----------
func t_rules_jewel() -> void:
	check(absf(RulesJewel.element_mult("earth", 1.0, "water") - 1.5) < 0.0001, "地剋水: 100% 石 = ×1.5")
	check(absf(RulesJewel.element_mult("water", 1.0, "earth") - (1.0 / 1.5)) < 0.0001, "水被地剋: 100% 石 = ÷1.5")
	check(absf(RulesJewel.element_mult("wind", 0.5, "earth") - 1.25) < 0.0001, "風剋地: 50% 石 = ×1.25")
	check(absf(RulesJewel.element_mult("wind", 0.1, "earth") - 1.05) < 0.0001, "風剋地: 10% 石 = ×1.05")
	check(absf(RulesJewel.element_mult("water", 0.5, "fire") - 1.25) < 0.0001, "水剋火: 50% 石 = ×1.25")
	check(absf(RulesJewel.element_mult("fire", 0.5, "water") - 0.8) < 0.0001, "被剋側: 50% 石 = ÷1.25")
	check(absf(RulesJewel.element_mult("wind", 0.0, "earth") - 1.0) < 0.0001, "0% 石 = 無加成")
	check(RulesJewel.element_mult("fire", 1.0, "fire") == 1.0, "同屬性無相剋")
	check(RulesJewel.element_mult("fire", 1.0, "none") == 1.0, "無屬性目標無相剋")
	# 100% 石 = RulesSpell.element_factor 全倍率一致
	check(absf(RulesJewel.element_mult("wind", 1.0, "earth") - RulesSpell.element_factor("wind", "earth")) < 0.0001, "同 element_factor 全倍率一致")
	# 術法加成 (1+寶石加成)
	check(absf(RulesJewel.spell_jewel_bonus("fire", "fire", 0.5) - 1.5) < 0.0001, "火石+火術: ×1.5")
	check(RulesJewel.spell_jewel_bonus("fire", "water", 0.5) == 1.0, "異屬性術法無加成")
	check(RulesJewel.spell_jewel_bonus("", "fire", 0.5) == 1.0, "冇石無加成")


# ---------- RulesJewel: 輔助效果 → bonus 表 ----------
func t_support_bonus() -> void:
	var b := RulesJewel.support_bonus([{"type": 15, "value": 10}, {"type": 17, "value": 5},
		{"type": 20, "value": 15}, {"type": 7, "value": 50}, {"type": 8, "value": 25},
		{"type": 52, "value": 20}, {"type": 53, "value": 10}, {"type": 9, "value": 3},
		{"type": 11, "value": 2}, {"type": 13, "value": 5}, {"type": 21, "value": 4},
		{"type": 1, "value": 2}, {"type": 63, "value": 20}])
	check(absf(float(b["hpPct"]) - 0.10) < 0.0001, "15=HP上限 10%")
	check(absf(float(b["mpPct"]) - 0.05) < 0.0001, "17=MP上限 5%")
	check(int(b["spFlat"]) == 15, "20=SP+15")
	check(absf(float(b["atkPct"]) - 0.50) < 0.0001, "7=物攻 +50%")
	check(absf(float(b["spellAtkPct"]) - 0.25) < 0.0001, "8=術攻 +25%")
	check(absf(float(b["defPct"]) - 0.20) < 0.0001, "52=物防 +20%")
	check(absf(float(b["spellDefPct"]) - 0.10) < 0.0001, "53=術防 +10%")
	check(int(b["defFlat"]) == 3 and int(b["spellDefFlat"]) == 2, "9/11=防禦力直加")
	check(absf(float(b["hitPct"]) - 0.05) < 0.0001, "13=命中 +5%")
	check(absf(float(b["spellHitPct"]) - 0.04) < 0.0001, "21=術命中 +4%")
	check(int(b["strFlat"]) == 2, "1=武力 +2")
	check(absf(float(b["mpCostMul"]) - 0.8) < 0.0001, "63=MP 耗損 -20%")
	var both := RulesJewel.support_bonus([{"type": 63, "value": 20}, {"type": 63, "value": 10}])
	check(absf(float(both["mpCostMul"]) - 0.72) < 0.0001, "兩粒 MP 減免累乘 (0.8×0.9)")
	check(absf(float(RulesJewel.support_bonus([]).get("atkPct", 9.9)) - 0.0) < 0.0001, "冇效果 = 0")


# ---------- RulesJewel: 融合 QTE ----------
func t_fusion_rules() -> void:
	check(RulesJewel.fusion_pos(0) == 0.0, "開始 = 0%")
	check(RulesJewel.fusion_pos(15, 10) == 0.5, "1.5 秒 = 50%")
	check(RulesJewel.fusion_pos(30, 10) == 1.0, "3 秒 = 100%")
	check(RulesJewel.fusion_pos(999, 10) == 1.0, "過咗時間停留 100%")
	check(RulesJewel.fusion_hit(15, 10), "15 tick (50%): 成功")
	check(RulesJewel.fusion_hit(21, 10), "21 tick (70%): 邊界內成功")
	check(not RulesJewel.fusion_hit(22, 10), "22 tick: 過咗窗口失敗")
	check(not RulesJewel.fusion_hit(8, 10), "8 tick (27%): 未到窗口失敗")
	check(not RulesJewel.fusion_hit(0, 10), "0 tick: 未開始失敗")
	check(not RulesJewel.fusion_hit(30, 10), "100% 走晒失敗")


# ---------- 寶石欄裝卸 + HP 加成 ----------
func t_jewel_eq(data: GameData) -> void:
	var sim := Sim.new(data, 7)
	var id := sim.spawn_player("t")
	var ch: Dictionary = sim.player_ch()
	var e := sim.ent(id)
	# 冇裝石: 有效上限 = 基礎
	check(sim._eff_max_hp(ch) == RulesStats.max_hp(1, ch["attrs"]), "冇石: HP = 基礎")
	# 裝 32102 生命之石 (HP+4%) → 上限 ×1.04
	sim.cmd_debug_give(id, 32102, 1)
	sim.cmd_equip_jewel(id, 32102, 1)
	var hp_base := RulesStats.max_hp(1, ch["attrs"])
	check(sim._eff_max_hp(ch) == MathX.js_round(hp_base * 1.04), "生命之石: HP ×1.04")
	check(int(ch["equip"]["jewels"][1]) == 32102, "寶石欄 1 已裝")
	# 裝第 2 粒: 32201 強化之石 (物攻5%) 取代 slot1 嘅 HP 石
	sim.cmd_debug_give(id, 32201, 1)
	sim.cmd_equip_jewel(id, 32201, 1)
	check(int(ch["equip"]["jewels"][1]) == 32201, "slot1 取代成功")
	check(sim._eff_max_hp(ch) == hp_base, "冇HP石 -> 上限回復基礎")
	# 卸載後 HP clamp
	sim.cmd_equip_jewel(id, 0, 1)
	check(sim._eff_max_hp(ch) == hp_base, "卸石: 上限回復")
	check(int(ch["hp"]) <= hp_base, "卸石: HP clamp 唔會超上限")
	# 唔係寶石 (10001 武器) 拒絕
	sim.cmd_equip_jewel(id, 10001, 0)
	check(int(ch["equip"]["jewels"][0]) == 0, "非寶石拒絕")
	# slot 0 裝屬性石 (attack use)
	sim.cmd_debug_give(id, 32035, 1)     # 烈焰之石 (火 50%)
	sim.cmd_equip_jewel(id, 32035, 0)
	check(int(ch["equip"]["jewels"][0]) == 32035, "屬性石入 slot 0")
	var st := sim._equip_stone(ch)
	check(str(st.get("elem", "")) == "fire" and absf(float(st.get("pct", 0.0)) - 0.5) < 0.0001, "_equip_stone: 火 50%")
	# replace 舊 slot0 時 clamp 做咗 (換 32001 風10%)
	sim.cmd_debug_give(id, 32001, 1)
	sim.cmd_equip_jewel(id, 32001, 0)
	check(int(ch["equip"]["jewels"][0]) == 32001, "slot 0 取代成功")


# ---------- 武器裝備 ----------
func t_equip_weapon(data: GameData) -> void:
	var sim := Sim.new(data, 8)
	var id := sim.spawn_player("t")
	var ch: Dictionary = sim.player_ch()
	check(int(ch["equip"]["weapon"]) == 10001, "開場武器: 柳葉刀 (cat1)")
	sim.cmd_debug_give(id, 10042, 1)     # 飛鷹寶戟 (矛 cat3)
	sim.cmd_equip_weapon(id, 10042)
	check(int(ch["equip"]["weapon"]) == 10042, "裝備飛鷹寶戟")
	sim.cmd_equip_weapon(id, 65210)      # 藥水唔係武器
	check(int(ch["equip"]["weapon"]) == 10042, "非武器拒絕")
	check(_bag_n(sim, id, 10042) == 1, "裝備唔消耗")


# ---------- 元素術書需要特殊石 (Step 9 遺留, spec 02 §3.2) ----------
func t_cast_need_jewel(data: GameData) -> void:
	var sim := Sim.new(data, 9)
	var id := sim.spawn_player("t", "daoshi")
	var ch: Dictionary = sim.player_ch()
	ch["level"] = 25
	sim._sync_stats(sim.ent(id))
	# 搵地之術 item id
	var di_item := 0
	for s in data.spells:
		if String(s["id"]) == "di_s":
			di_item = int(s["item"])
	sim.cmd_debug_give(id, di_item, 1)
	sim.cmd_equip_spellbook(id, di_item, 0)
	var mob_id := _spawn_one(sim, 1001)
	_put(sim, mob_id, 14, 14)
	_put(sim, id, 14, 16)
	# 未裝地之石: 拒
	sim.cmd_cast_spell(id, 0, mob_id)
	check(not sim.ent(id).has("casting"), "元素術冇對應特殊石: 唔比施")
	# (debug: 收 msg 已移除)
	# 裝 32302 地之石 (特殊) 落 slot 1
	sim.cmd_debug_give(id, 32302, 1)
	sim.cmd_equip_jewel(id, 32302, 1)
	sim.cmd_cast_spell(id, 0, mob_id)
	check(sim.ent(id).has("casting"), "有地之石: 施到 (詠唱中)")
	# spell_jewel_bonus 接入: 再裝 slot0 地屬石 50% → 公式層面已測, sim 傳值冇錯就得
	var st := sim._equip_stone(ch)
	check(str(st.get("elem", "")) == "" or st.is_empty(), "冇slot0石: 不影響特殊石檢查")


# ---------- 絕招框架 ----------
func t_ultimate_framework(data: GameData) -> void:
	var sim := Sim.new(data, 10)
	var id := sim.spawn_player("t")       # yishi
	var ch: Dictionary = sim.player_ch()
	var ult: Dictionary = data.ult_by_id["wanli"]
	# 未學
	sim.cmd_use_ultimate(id, "wanli")
	check(int(ch["mp"]) > 0, "未學: 唔扣 MP")
	# 學識
	ch["ultimates"] = ["wanli"]
	check(int(data.cats.get(10001, 0)) == 1, "柳葉刀 cat1 (刀)")
	sim.cmd_use_ultimate(id, "wanli")
	check(int(ch["mp"]) == RulesStats.max_mp(1, ch["attrs"]), "武器唔啱: 唔扣 MP")
	# 裝矛
	sim.cmd_debug_give(id, 10042, 1)
	sim.cmd_equip_weapon(id, 10042)
	# 城內 → 拒 (安全區)
	sim.cmd_use_ultimate(id, "wanli")
	check(int(ch["mp"]) == RulesStats.max_mp(1, ch["attrs"]), "安全區: 唔扣 MP")
	# 出城 + 兩隻怪喺半徑 2 內
	_put(sim, id, 35, 35)
	var m1 := _spawn_one(sim, 1001)
	var m2 := _spawn_one(sim, 1001, m1)
	_put(sim, m1, 35, 34)
	_put(sim, m2, 36, 36)
	var mp0 := int(ch["mp"])
	var sp0 := int(ch["sp"])
	var hits := {"n": 0}
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev.get("k", "") == "ult_hit":
			hits["n"] = int(hits["n"]) + 1)
	sim.cmd_use_ultimate(id, "wanli")
	check(hits["n"] == 2, "大範圍: 打中 2 隻怪")
	check(int(ch["mp"]) == mp0 - 15 and int(ch["sp"]) == sp0 - 20, "絕招扣 MP15+SP20")
	check(int(ch["ultCd"]["wanli"]) == sim.tick + 300, "冷卻設定 300 tick")
	# 冷卻中
	var mp1 := int(ch["mp"])
	sim.cmd_use_ultimate(id, "wanli")
	check(int(ch["mp"]) == mp1, "冷卻中: 唔扣 MP")
	# 怪死嘅 check (dmg 至少 1)
	var died := 0
	for e in sim.ents.values():
		if e["kind"] == "mob":
			died += 1
	check(died == 0, "絕招後兩隻怪死晒 (lv1 都有傷害)"); 
	# 公式層面確認絕招傷害
	var calc := RulesCombat.calc_damage(12.0, 10.0, 0.0, Callable(func() -> float: return 1.0)) * 2.0
	check(calc >= 2, "絕招傷害公式: (武力×1.5+武器強度)×2.0 起碼 2")
	# 唔係 yishi 職用唔到 (select class 得 lv1 得)
	var t2 := sim.spawn_player("t2", "daoshi")
	var ch2: Dictionary = sim.ent(t2)["ch"]
	ch2["ultimates"] = ["wanli"]
	sim.cmd_use_ultimate(t2, "wanli")
	check(int(ch2["mp"]) == RulesStats.max_mp(1, ch2["attrs"]), "其他職: 用唔到義士絕招")


# ---------- 融合 (sim) ----------
func t_fusion_sim(data: GameData) -> void:
	var sim := Sim.new(data, 11)
	var id := sim.spawn_player("t")
	var ch: Dictionary = sim.player_ch()
	ch["level"] = 10
	sim._sync_stats(sim.ent(id))
	# 未喺打鐵鋪
	sim.cmd_fusion_start(id)
	check((ch.get("fusing", {}) as Dictionary).is_empty(), "唔喺打鐵鋪: 唔開始")
	# 去打鐵鋪 + 背包屬性石
	_put(sim, id, int(data.facilities["forge"]["x"]), int(data.facilities["forge"]["y"]))
	sim.cmd_debug_give(id, 32001, 2)     # 飄嵐之石 風10% ×2
	sim.cmd_fusion_start(id)
	check(not (ch.get("fusing", {}) as Dictionary).is_empty(), "開始融合 QTE")
	var start := int(ch["fusing"]["start"])
	# 即時撳 (太早) → fail
	sim.cmd_fusion_hit(id)
	check((ch.get("fusing", {}) as Dictionary).is_empty(), "fail 後 fusing 清除")
	check(_bag_n(sim, id, 32001) == 2, "fail 唔扣石")
	# 再嚟, 行 15 tick 先撳 → ok
	sim.cmd_fusion_start(id)
	start = int(ch["fusing"]["start"])
	for i in 15:
		sim.step()
	check(sim.tick - start == 15, "tick 推進 15")
	sim.cmd_fusion_hit(id)
	check(_bag_n(sim, id, 32001) == 1, "成功扣 1 粒石")
	check(bool((ch.get("fusedJewels", {}) as Dictionary).has(10001)), "武器已嵌石")
	var f: Dictionary = ch["fusedJewels"][10001]
	check(str(f.get("elem", "")) == "wind" and absf(float(f.get("pct", 0.0)) - 0.1) < 0.0001, "嵌石: 風 10%")
	# 有效加成 (物理相剋)
	check(absf(sim._phys_elem_mult(ch, "earth") - 1.05) < 0.0001, "風10% 石剋地: ×1.05")
	check(absf(sim._phys_elem_mult(ch, "wind") - 1.0) < 0.0001, "同屬冇加成")
	# 已嵌武器唔可以再融合
	sim.cmd_fusion_start(id)
	check((ch.get("fusing", {}) as Dictionary).is_empty(), "已嵌石武器: 唔可以再融合")
	# 換另一把武器 + 嵌另一粒
	sim.cmd_debug_give(id, 10002, 1)     # 鬼頭刀 (刀)
	sim.cmd_equip_weapon(id, 10002)
	sim.cmd_fusion_start(id)
	check(not (ch.get("fusing", {}) as Dictionary).is_empty(), "另一把武器可以融合")
	sim.cmd_fusion_hit(id)               # 失敗, 再成功嚟
	sim.cmd_fusion_start(id)
	start = int(ch["fusing"]["start"])
	for i in 15:
		sim.step()
	sim.cmd_fusion_hit(id)
	check(bool((ch.get("fusedJewels", {}) as Dictionary).has(10002)), "第二把嵌石成功")
	# cleanup: 背包冇 10002 → fusedJewels 清除
	RulesShop.remove_item(ch["bag"], 10002, 1)
	sim._cleanup_fused(ch)
	check(not (ch.get("fusedJewels", {}) as Dictionary).has(10002), "賣晒武器: 清除融合記錄")


# ---------- 義士三招絕招任務鏈 (spec 06 §5) ----------
func t_ult_quest_chain(data: GameData) -> void:
	var sim := Sim.new(data, 12)
	var id := sim.spawn_player("t")
	var ch: Dictionary = sim.player_ch()
	ch["level"] = 20
	sim._full_heal(ch)
	sim._sync_stats(sim.ent(id))
	# ---- 萬里鷹翔: 等到辰時 (tick 256+) ----
	for i in 300:
		sim.step()
	check(_vis(sim, "guard_captain"), "20 級 + 辰時: 禁衛大隊長現身")
	# 未答啱問題前: talk 觸發 (ask stage)
	_talk(sim, id, "guard_captain")
	check((ch["quests"] as Dictionary).has("ult_wanli"), "萬里鷹翔: 任務觸發")
	check(int(ch["quests"]["ult_wanli"]["stage"]) == 0, "ask stage 未推進")
	sim.cmd_quest_answer(id, "ult_wanli", 1)
	check(int(ch["quests"]["ult_wanli"]["stage"]) == 0, "答錯: 唔推進")
	sim.cmd_quest_answer(id, "ult_wanli", 0)
	check(int(ch["quests"]["ult_wanli"]["stage"]) == 1, "答啱: 推進到 collect")
	check(_bag_n(sim, id, 58009) == 1, "殲盜密函到手")
	# 唔夠令 → turnin 唔得
	sim.cmd_quest_turnin(id, "ult_wanli")
	check(int(ch["quests"]["ult_wanli"]["stage"]) == 1, "霸盜令唔夠: 唔推進")
	check(not bool(ch["questDone"].get("ult_wanli", false)), "未完成")
	# 攞 20 個令 (debug_give) → turnin
	sim.cmd_debug_give(id, 58010, 20)
	_talk(sim, id, "guard_captain")
	sim.cmd_quest_turnin(id, "ult_wanli")
	check(bool(ch["questDone"].get("ult_wanli", false)), "萬里鷹翔: 完成")
	check((ch["ultimates"] as Array).has("wanli"), "學識萬里鷹翔")
	check(_bag_n(sim, id, 10042) == 1, "獎勵: 飛鷹寶戟")
	# ---- 大鵬展翅: 35 級 + 鎮長 (子~卯 = 下一個 day tick 720+0..255) ----
	ch["level"] = 35
	sim._full_heal(ch)
	sim._sync_stats(sim.ent(id))
	for i in 600:
		sim.step()          # tick 900 → day1 ke ~25 (子~卯)
	check(_vis(sim, "town_head"), "35 級 + 子~卯: 鎮長現身")
	_talk(sim, id, "town_head")
	check((ch["quests"] as Dictionary).has("ult_dapeng"), "大鵬展翅: 任務觸發")
	check(_bag_n(sim, id, 58017) == 1, "晉陽殲盜令到手")
	# 守門流浪兵 → PK 戰
	var btl := {"n": 0}
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev.get("k", "") == "quest_battle":
			btl["n"] = int(btl["n"]) + 1)
	_talk(sim, id, "stray_soldier")     # fight stage: 對話唔推進
	check(int(ch["quests"]["ult_dapeng"]["stage"]) == 1, "fight stage 未由對話推進")
	sim.cmd_quest_battle(id, "ult_dapeng")
	check(btl["n"] == 1, "PK 戰: boss 召喚事件")
	var boss := 0
	for e in sim.ents.values():
		var em: Dictionary = e
		if str(em.get("mob", {}).get("quest_boss", "")) == "ult_dapeng":
			boss = int(em["id"])
	check(boss != 0, "瀧銘 boss 出現")
	# 打贏: 手動削血 + 攻擊
	var be: Dictionary = sim.ent(boss)
	be["hp"] = 1
	sim.cmd_attack(id, boss)
	for i in 90:
		sim.step()
		if sim.ent(boss).is_empty():
			break
	check(not bool(ch["questDone"].get("ult_dapeng", false)), "boss 死: 未done (要交頭顱)")
	check((ch["quests"] as Dictionary).has("ult_dapeng"), "boss 死: quest 仲進行中 (要交頭顱)")
	check(int(ch["quests"]["ult_dapeng"]["stage"]) == 2, "boss 死: 推進到 collect 頭顱")
	check(_bag_n(sim, id, 58018) == 1, "瀧銘頭顱掉落")
	# 交頭顱
	_talk(sim, id, "town_head")
	sim.cmd_quest_turnin(id, "ult_dapeng")
	check(bool(ch["questDone"].get("ult_dapeng", false)), "大鵬展翅: 完成")
	check((ch["ultimates"] as Array).has("dapeng"), "學識大鵬展翅")
	check(_bag_n(sim, id, 58019) == 1, "呂代槍文集到手")
	# ---- 力拔山河: 45 級 + 呂布 (午~未 = tick 1104..1151) ----
	ch["level"] = 45
	sim._full_heal(ch)
	sim._sync_stats(sim.ent(id))
	for i in 250:
		sim.step()          # tick ~1150 → day1 午~未
	check(_vis(sim, "lvbu"), "45 級 + 午~未: 呂布現身")
	_talk(sim, id, "lvbu")
	check((ch["quests"] as Dictionary).has("ult_libashan"), "力拔山河: 任務觸發")
	check(_bag_n(sim, id, 58039) == 1, "呂布求礦書到手")
	# 5 種礦逐個 turnin
	var ores := [[25120, 50], [25121, 40], [25122, 30], [25123, 20], [25124, 10]]
	for pair in ores:
		sim.cmd_debug_give(id, int(pair[0]), int(pair[1]))
	for i in 5:
		_talk(sim, id, "lvbu")
		sim.cmd_quest_turnin(id, "ult_libashan")
	check(bool(ch["questDone"].get("ult_libashan", false)), "力拔山河: 完成")
	check((ch["ultimates"] as Array).has("libashan"), "學識力拔山河")
	check((ch["ultimates"] as Array).size() == 3, "三招絕招齊")
	# 三招唔可以重覆學 (reward 唔重複 append)
	sim.cmd_quest_turnin(id, "ult_libashan")   # 已完成再 turnin 冇嘢發生
	check((ch["ultimates"] as Array).size() == 3, "三招絕招齊 + 唔重複")


func t_save_roundtrip(data: GameData) -> void:
	var sim := Sim.new(data, 13)
	var id := sim.spawn_player("t")
	var ch: Dictionary = sim.player_ch()
	ch["level"] = 20
	sim._full_heal(ch)
	sim._sync_stats(sim.ent(id))
	# 準備狀態: 學一招 + 嵌石 + 裝石 + 任務進行中
	ch["ultimates"] = ["wanli"]
	ch["ultCd"] = {"wanli": sim.tick + 30}
	sim.cmd_debug_give(id, 32001, 1)
	sim.cmd_debug_give(id, 32302, 1)
	ch["fusedJewels"][10001] = {"elem": "wind", "pct": 0.1}
	sim.cmd_equip_jewel(id, 32302, 1)
	# 存檔 → 載入 → 檢查
	var s := sim.save_string()
	var sim2 := Sim.load_string(data, s)
	check(sim2 != null, "存檔載入成功")
	var ch2: Dictionary = sim2.player_ch()
	check((ch2["ultimates"] as Array).has("wanli"), "roundtrip: 絕招列表")
	check(int(ch2["ultCd"]["wanli"]) > 0, "roundtrip: 絕招冷卻")
	check(bool((ch2.get("fusedJewels", {}) as Dictionary).has("10001")), "roundtrip: 武器嵌石")
	check(int(ch2["equip"]["jewels"][1]) == 32302, "roundtrip: 寶石欄")
	check(ch2["level"] == 20, "roundtrip: 等級")
	# save→load→save 一致
	var s2 := sim2.save_string()
	check(s2 == s, "roundtrip: save→load→save 字串一致")