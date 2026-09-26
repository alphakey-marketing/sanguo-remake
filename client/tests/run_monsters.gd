extends SceneTree
# Step 11 測試 (spec 04 §1~3, spec 11 §2): 怪物導入對照 + 洞窟傳送 + 逃跑/群攻/每日重生
# 跑: Godot --headless --path client --script tests/run_monsters.gd  (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_import_vectors(data)
	t_monster_count(data)
	t_item_ids(data)
	t_drop_rules(data)
	t_spawn_zones(data)
	t_gate_newbie(data)
	t_cave_geometry(data)
	t_flee_negative(data)
	t_group_aggro(data)
	t_boss(data)
	t_boss_daily(data)
	t_runan_travel(data)
	t_cave_shop(data)
	t_kill_drops_to_ground(data)
	t_dropped_ttl(data)
	t_dropped_pick(data)
	t_dropped_pick_bagfull(data)
	t_dropped_save_roundtrip(data)
	t_bag_weight_rules(data)
	t_mob_cast_ranged(data)
	t_mob_cast_dodge(data)
	t_mob_ranged_no_melee(data)
	t_boss_skills(data)
	t_cast_telegraph_expose(data)
	t_cast_save_roundtrip(data)
	print("[TEST] monsters scenarios: %d, fail %d" % [total, fails])
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


# npc_drops.csv 原行 (導入器同源)。boss 19001 唔喺 CSV，另行硬編碼。
# 格式: id,name,level,n_drops,drops(item(id)@rate ...)；rate 基數 100000
const CSV_VECTORS := [
	"11068,流氓1,14,9,銅鎚(10039)@200 古代劍(11037)@200 蒲扇(12002)@200 捷豹靴(22027)@60 精鋼戒指(23002)@200 嫦娥袖帶(15003)@200 甜蘿蔔(29042)@30000 賊寇錦囊(61506)@100 草菇(29067)@2500",
	"11069,流氓2,20,10,鬼頭刀(10002)@180 狼爪(11014)@180 鐵筆(12014)@180 鐵鞭(13002)@180 招魂幡(14002)@180 金絲袖帶(15002)@180 甜蘿蔔(29042)@30000 賊寇錦囊(61506)@200 補神草(29068)@2500 精製手套(31212)@200",
	"11070,地痞1,30,10,玄龜寶槍(10029)@150 玄龜寶環(11029)@150 玄龜寶弩(12029)@150 玄龜卷軸(13029)@150 玄龜符咒(14029)@150 玄龜寶琴(15029)@150 甜蘿蔔(29042)@30000 賊寇錦囊(61506)@200 野蔘(29069)@2500 精製鐵虎(31215)@200",
	"11072,盜賊1,9,9,鋼刀(10037)@400 鋼爪(11039)@200 皮靴(22025)@600 禪杖(13014)@200 虛極拂塵(14014)@200 青銅戒指(23001)@200 無花果(29041)@6000 野香菇(29040)@30000 草菇(29067)@2500",
	"11091,山賊,11,9,鋼刀(10037)@400 鋼爪(11039)@200 皮靴(22025)@600 禪杖(13014)@200 虛極拂塵(14014)@200 青銅戒指(23001)@200 野香菇(29040)@9000 仙楂(29038)@30000 草菇(29067)@2500",
	"12003,野兔,7,9,木箭(12201)@12000 光輝石墨(26037)@3600 仙楂(29038)@30000 甜蘿蔔(29042)@1600 梅子(29045)@6000 光輝之石(26038)@1200 細毛兔皮(25100)@3000 普通兔皮(25101)@1200 草菇(29067)@2500",
	"12005,母雞,11,10,無花果(29041)@2400 野芋(29039)@30000 雞蛋(29036)@9000 回血草(29043)@1800 梅子(29045)@3600 光輝之石(26038)@1200 大片山葉(29048)@1200 芳香軟石(25098)@1500 草菇(29067)@2500 精製乾糧(31208)@200",
	"12006,狐貍,18,10,速攻靴(22002)@150 純銀戒指(23003)@180 銀鍊子(24002)@150 狐貍皮(25109)@1500 光輝之石(26038)@3000 光明之石(26039)@500 甜蘿蔔(29042)@30000 獸肉(61503)@600 補神草(29068)@2500 精製腳蹄(31211)@200",
	"12011,猴子,11,9,無花果(29041)@2400 野芋(29039)@30000 回血草(29043)@9000 雞蛋(29036)@1800 梅子(29045)@3600 光輝之石(26038)@1200 甜味樹根(29049)@1200 紫色香草(25097)@1500 草菇(29067)@2500",
	"12012,野狗,16,10,生之石(32306)@6 光輝之石(26038)@600 回血草(29043)@6000 甜蘿蔔(29042)@900 梅子(29045)@4800 光輝之石(26038)@3000 甜蘿蔔(29042)@30000 獸骨(61502)@1000 補神草(29068)@2500 精製小球(31210)@200",
	"12013,野豬,14,10,地之石(32302)@6 十等箭(12202)@12000 回血草(29043)@30000 甜蘿蔔(29042)@900 梅子(29045)@3600 光輝之石(26038)@1200 甜味樹根(29049)@1200 紫色香草(25097)@1500 草菇(29067)@2500 精製補藥(31209)@200",
	"12014,花鹿,20,3,勇者頭盔(16027)@250 絕塵冠(17027)@250 玲瓏髮簪(18027)@250",
	"12017,大蟒,20,10,武者鎧甲(19027)@250 樂生袍(20027)@250 玲瓏霞衣(21027)@250 水之石(32303)@6 光輝之石(26038)@3000 光明之石(26039)@500 甜蘿蔔(29042)@30000 獸肉(61503)@600 補神草(29068)@2500 精製手套(31212)@200",
	"12018,山羊,14,3,精鋼頭盔(16013)@600 方外冠(17013)@600 迷情羽飾(18013)@600",
	"12019,瘋貓,14,10,無花果(29041)@2400 野芋(29039)@30000 回血草(29043)@9000 甜蘿蔔(29042)@900 梅子(29045)@3600 光輝之石(26038)@1200 甜味樹根(29049)@1200 紫色香草(25097)@1500 草菇(29067)@2500 精製補藥(31209)@200",
	"12021,野貂,9,9,無花果(29041)@2400 貂皮(25108)@1200 仙楂(29038)@30000 野芋(29039)@1800 梅子(29045)@3600 光輝之石(26038)@1200 大片山葉(29048)@1200 光輝石墨(26037)@1500 草菇(29067)@2500",
	"12028,黃蜂,20,9,火之石(32304)@6 光明之石(26039)@300 回血草(29043)@3000 芳香草(29044)@3000 梅子(29045)@2400 光輝之石(26038)@1200 甜蘿蔔(29042)@30000 香味粉末(25099)@15000 補神草(29068)@2500",
	"12029,蝴蝶精,9,9,無花果(29041)@2400 光輝石墨(26037)@1200 野香菇(29040)@9000 野芋(29039)@30000 梅子(29045)@3600 光輝之石(26038)@3600 大片山葉(29048)@1200 深色蟲藥粉(25103)@12000 草菇(29067)@2500",
	"12030,飛蛾怪,14,9,元氣之石(32101)@6 光輝之石(26038)@600 風之石(32301)@6 回血草(29043)@6000 梅子(29045)@2400 光輝之石(26038)@1200 甜蘿蔔(29042)@30000 高品質蟲粉(25104)@6000 草菇(29067)@2500",
	"12031,蜻蜓,9,9,無花果(29041)@2400 光輝石墨(26037)@1200 野香菇(29040)@9000 野芋(29039)@30000 梅子(29045)@40000 光輝之石(26038)@1200 大片山葉(29048)@1200 深色蟲藥粉(25103)@12000 草菇(29067)@2500",
	"12002,田鼠,1,7,田鼠碎骨(61501)@2000 光輝石墨(26037)@3600 仙楂(29038)@30000 野香菇(29040)@4500 梅子(29045)@2400 光輝之石(26038)@1200 苦味葉(29047)@1200",
	"26009,惡虎,28,8,虎威戰袍(19009)@400 虎威神袍(20018)@400 虎威仙裳(21018)@400 猛虎頭帶(16028)@360 伏虎冠(17028)@360 黃鶯羽飾(18028)@360 老虎飾品(61033)@2400 猛獸皮(61505)@1600",
	"12022,水鴨,5,0,",
	"12034,蝙蝠,20,0,",
	"12044,兔兒,5,0,",
	"12046,草貂,7,0,",
	# S04 補怪 (地圖密度/品種): 新 20 隻用 dropSrc 對應真實原版怪 (npc_drops.csv)
	"11071,地痞2,39,3,伏魔戒指(23058)@90 佛珠項鍊(24004)@75 藍影之石(32232)@5",
	"11073,盜賊2,48,8,流星鎚(10015)@45 雌雄雙股劍(11003)@45 保生扇(12040)@50 斷流鞭(13040)@50 清虛拂塵(14040)@50 白金匕首(15040)@50 飛燕腳環(22028)@65 賊首令牌(61509)@120",
	"11074,土匪1,32,10,雪貂頭帶(16002)@110 逍遙方巾(17002)@110 純銀髮簪(18002)@110 寂音箭(12205)@12000 甜味樹根(29049)@4000 酸辣湯(29051)@30000 通氣散(28034)@10000 賊寇錦囊(61506)@200 野蔘(29069)@2500 精製紫薰草(31217)@200",
	"11075,土匪2,46,3,驅邪戒指(23057)@90 地獄爪(11040)@45 金頭筆(12015)@75",
	"11086,小兵1,50,3,玄龜寶戒(23073)@75 金鍊子(24003)@60 御風靴(22003)@55",
	"11092,彎刀兵,13,9,鋼刀(10037)@400 鋼爪(11039)@200 皮靴(22025)@600 禪杖(13014)@200 虛極拂塵(14014)@200 青銅戒指(23001)@200 野香菇(29040)@9000 仙楂(29038)@30000 草菇(29067)@2500",
	"11093,長刀兵,14,9,銅鎚(10039)@200 古代劍(11037)@200 蒲扇(12002)@200 捷豹靴(22027)@60 精鋼戒指(23002)@200 嫦娥袖帶(15003)@200 野香菇(29040)@9000 仙楂(29038)@30000 草菇(29067)@2500",
	"11094,長槍兵,14,3,精鋼頭盔(16013)@600 方外冠(17013)@600 迷情羽飾(18013)@600",
	"11095,斧兵,16,3,精鋼鎧甲(19013)@600 鶴氅(20002)@600 迷情羽衣(21002)@600",
	"11096,巨斧兵,18,9,速攻靴(22002)@150 純銀戒指(23003)@180 銀鍊子(24002)@150 三界之石(32106)@6 無花果(29041)@2400 乾燥果實(29046)@3600 野香菇(29040)@9000 仙楂(29038)@30000 補神草(29068)@2500",
	"12004,公雞,13,10,無花果(29041)@2400 野芋(29039)@30000 雞蛋(29036)@9000 回血草(29043)@1800 梅子(29045)@3600 光輝之石(26038)@1200 甜味樹根(29049)@1200 芳香軟石(25098)@1500 草菇(29067)@2500 精製乾糧(31208)@200",
	"12007,野狼,21,10,虎威寶帶(16009)@200 虎威寶冠(17021)@200 虎威魔羽(18021)@200 智慧戒指(23034)@150 破損狼皮(25106)@3000 高級狼皮(25107)@1500 甜蘿蔔(29042)@30000 獸皮(61504)@400 補神草(29068)@2500 精製木虎(31213)@200",
	"12008,花豹,25,10,迷情戒指(23053)@180 羅剎劍(11002)@150 陰陽幡(14003)@150 地之石(32302)@6 九等箭(12204)@12000 回血草(29043)@6000 甜蘿蔔(29042)@30000 猛獸皮(61505)@200 補神草(29068)@2500 精製石虎(31214)@200",
	"12009,老虎,26,10,虎威戰袍(19009)@200 虎威神袍(20018)@200 虎威仙裳(21018)@200 猛虎頭帶(16028)@180 伏虎冠(17028)@180 黃鶯羽飾(18028)@180 生之石(32306)@6 猛獸皮(61505)@200 補神草(29068)@2500 精製石虎(31214)@200",
	"12010,大熊,26,10,狼牙棒(10014)@120 金爪(11015)@120 羽扇(12003)@150 哭喪棒(13015)@150 生之術(中)(30523)@150 精鋼匕首(15014)@150 生命之石(32102)@6 猛獸皮(61505)@200 補神草(29068)@2500 精製鐵虎(31215)@200",
	"12015,野牛,23,10,葉之術(中)(30514)@120 封咒術(30526)@120 解咒術(30528)@120 護甲術(30529)@120 護鏡術(30531)@120 聚力術(30533)@120 甜蘿蔔(29042)@30000 獸皮(61504)@400 補神草(29068)@2500 精製木虎(31213)@200",
	"12035,狐蝠精,31,10,凱旋戰袍(19028)@135 伏虎長袍(20028)@135 炎虎大衣(21028)@135 無蹤之石(32211)@6 風之石(32301)@6 酸辣湯(29051)@30000 通氣散(28034)@10000 燦爛之石(26040)@150 野蔘(29069)@2500 精製強力丸(31216)@200",
	"12036,蜥蜴王,37,10,英傑頭帶(16029)@90 遁世方巾(17029)@90 如意髮簪(18029)@90 封靈之石(32209)@6 肉包(29052)@30000 保生丹(28035)@10000 苦味葉(29047)@4000 甜味樹根(29049)@6000 野蔘(29069)@2500 精製收心丸(31219)@200",
	"13001,隨護衛,14,4,精鋼鎧甲(19013)@600 鶴氅(20002)@600 迷情羽衣(21002)@600 無之石(32305)@6",
	"13002,簡護衛,36,10,地之術(中)(30502)@75 水之術(中)(30505)@75 火之術(中)(30508)@75 風之術(中)(30511)@75 雲之術(中)(30520)@75 快速術(30535)@50 無邊之石(32207)@6 賊寇錦囊(61506)@200 野蔘(29069)@2500 精製寧神丹(31218)@200",
]

# boss 19001 手寫掉落 (item, p)
const BOSS_DROPS := [[61505, 0.5], [61504, 0.35], [29042, 0.3], [25107, 0.12], [28035, 0.08]]
const BOSS_RARE := [[32302, 0.02]]


# CSV 行解析 -> (item_id, p) 原次序
static func _parse_csv_line(line: String) -> Array:
	var f := line.split(",")
	var drops_raw := f[4] if f.size() > 4 else ""
	var out: Array = []
	var rx := RegEx.new()
	rx.compile(r"\((\d+)\)@(\d+)")
	for m in rx.search_all(drops_raw):
		out.append([int(m.get_string(1)), int(m.get_string(2)) / 100000.0])
	return out


# 對照: monsters.json 每隻怪 drops+rareDrops 平排 = CSV 拆「常見(p>=0.05) 先行、稀有殿後」嘅序
func t_import_vectors(data: GameData) -> void:
	for line in CSV_VECTORS:
		var f: PackedStringArray = String(line).split(",")
		var mid := int(f[0])
		var expected := _parse_csv_line(line)
		var common: Array = expected.filter(func(e: Array) -> bool: return e[1] >= 0.05)
		var rare: Array = expected.filter(func(e: Array) -> bool: return e[1] < 0.05)
		var exp_pair: Array = []
		for x in common:
			exp_pair.append(x)
		for x in rare:
			exp_pair.append(x)
		# 對照對象 = id 同 CSV 一樣，或者 dropSrc 指住呢行 (1~10 級新手怪借原版同名怪掉落)
		var targets: Array = []
		for d in data.monsters.values():
			if int(d["id"]) == mid or int(d.get("dropSrc", -1)) == mid:
				targets.append(d)
		check(not targets.is_empty(), "導入: CSV %d (%s) 有怪用緊" % [mid, f[1]])
		for d in targets:
			var actual: Array = []
			for x in d.get("drops", []):
				actual.append([int(x["item"]), float(x["p"])])
			for x in d.get("rareDrops", []):
				actual.append([int(x["item"]), float(x["p"])])
			var ok := actual.size() == exp_pair.size()
			if ok:
				for i in actual.size():
					if int(actual[i][0]) != int(exp_pair[i][0]) or absf(float(actual[i][1]) - float(exp_pair[i][1])) > 1e-9:
						ok = false
						break
			check(ok, "導入: %d %s 掉落 p 對照 CSV %d (%d 項)" % [int(d["id"]), f[1], mid, expected.size()])
			if not ok:
				print("      expected=%s\n      actual=%s" % [str(exp_pair), str(actual)])
	# boss 19001
	var boss: Dictionary = data.monsters.get(19001, {})
	check(not boss.is_empty(), "導入: boss 19001 存在")
	if not boss.is_empty():
		var bd: Array = []
		for x in boss.get("drops", []):
			bd.append([int(x["item"]), float(x["p"])])
		var br: Array = []
		for x in boss.get("rareDrops", []):
			br.append([int(x["item"]), float(x["p"])])
		check(bd == BOSS_DROPS and br == BOSS_RARE, "導入: boss 掉落硬編碼對照")
	check(bool(boss.get("flee", true)) == false, "導入: boss flee=false (唔會逃跑)")
	check(bool(boss.get("boss", false)) == true, "導入: boss 標記每日重生")


func t_monster_count(data: GameData) -> void:
	var imported := 0
	var hand := 0
	for d in data.monsters.values():
		if int(d["id"]) >= 10000:
			imported += 1
		else:
			hand += 1
	check(data.monsters.size() >= 30, "導入: 全場怪 ≥ 30 (而家 %d)" % data.monsters.size())
	check(imported >= 20, "導入: npc_drops 導入 ≥ 20 (而家 %d)" % imported)
	check(hand == 92, "導入: 原裝 11 隻 + Step 16 boss 3 隻 + Step 19 戰役 boss 4 隻 + S04 補怪 20 隻 + S04c 戰役 boss 26 隻 + S04d 場景怪 22 隻 + S06b 井底怪 2 隻 + 歷史任務 boss 4 隻 (而家 %d)" % hand)


func t_item_ids(data: GameData) -> void:
	var bad: Array = []
	for d in data.monsters.values():
		for x in d.get("drops", []) + d.get("rareDrops", []):
			if not data.item_ids.has(int(x["item"])):
				bad.append([d["id"], int(x["item"])])
	check(bad.is_empty(), "導入: 全部掉落 item id 喺 items.json (%d 個唔啱)" % bad.size())


# 全表: 每隻怪一係有 CSV 來源 (向量表)，一係喺【自訂】白名單；drops/rareDrops 按 0.05 分界、p 喺 (0,1]
const CUSTOM_DROPS := [1006, 1007, 1008, 1009, 1010, 1011, 1012, 1013, 1014, 19001, 1015, 1016, 1017, 1018, 19002, 19003, 19004, 1087, 1088, 1089, 1090, 1091, 1092]   # S01d: 19002~3 試煉怪（轉職考試）【自訂】；S06b: 1087~8 井底木乃伊/殭屍 + 1089~92 歷史任務 boss（程普/何進/黃蓋/張角）【自訂】
# S04c: 戰役 boss 1039~1064 (褚飛燕→十常侍 5 場 26 層，gen_battles.py 生成)【自訂】
const CUSTOM_BATTLE := [1039, 1040, 1041, 1042, 1043, 1044, 1045, 1046, 1047, 1048, 1049, 1050, 1051, 1052, 1053, 1054, 1055, 1056, 1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064]
# S04d: 特殊場景怪物 1065~1086 (桃花渡 15 隻 + 七彩奪寶陣 7 色孟獲，gen_scenes.py 生成)【自訂】
const CUSTOM_SCENE := [1065, 1066, 1067, 1068, 1069, 1070, 1071, 1072, 1073, 1074, 1075, 1076, 1077, 1078, 1079, 1080, 1081, 1082, 1083, 1084, 1085, 1086]

func t_drop_rules(data: GameData) -> void:
	var csv_ids := {}
	for line in CSV_VECTORS:
		csv_ids[int(String(line).split(",")[0])] = true
	var no_src: Array = []
	var bad_split: Array = []
	for d in data.monsters.values():
		var src := int(d.get("dropSrc", d["id"]))
		if not csv_ids.has(src) and not CUSTOM_DROPS.has(int(d["id"])) and not CUSTOM_BATTLE.has(int(d["id"])) and not CUSTOM_SCENE.has(int(d["id"])):
			no_src.append(int(d["id"]))
		for x in d.get("drops", []):
			if float(x["p"]) < 0.05 or float(x["p"]) > 1.0:
				bad_split.append([d["id"], x["item"]])
		for x in d.get("rareDrops", []):
			if float(x["p"]) >= 0.05 or float(x["p"]) <= 0.0:
				bad_split.append([d["id"], x["item"]])
	check(no_src.is_empty(), "導入: 每隻怪都有 CSV 來源或者喺【自訂】白名單 (冇嘅: %s)" % str(no_src))
	check(bad_split.is_empty(), "導入: drops p≥0.05 / rareDrops p<0.05 分界啱 (錯: %s)" % str(bad_split))


func t_spawn_zones(data: GameData) -> void:
	var zone_ids := {}
	for z in data.zones:
		zone_ids[String(z["id"])] = true
	var bad: Array = []
	for s in data.spawns:
		if not zone_ids.has(String(s["zone"])):
			bad.append(s)
		if not data.monsters.has(int(s["monster"])):
			bad.append(s)
	check(bad.is_empty(), "洞窟: 所有 spawn 嘅 monster/zone 都存在")
	for f in range(1, 11):
		check(zone_ids.has("runan_f%d" % f), "洞窟: runan_f%d zone 存在" % f)
	# 每洞窟層 spawn 至少 1 個
	var has_zone := {}
	for s in data.spawns:
		has_zone[String(s["zone"])] = true
	for f in range(1, 11):
		check(bool(has_zone.get("runan_f%d" % f, false)), "洞窟: 第 %d 層有 spawn" % f)
	# boss spawn 喺 10 層
	var boss_spawn := {}
	for s in data.spawns:
		if int(s["monster"]) == 19001:
			boss_spawn = s
	check(not boss_spawn.is_empty() and String(boss_spawn.get("zone", "")) == "runan_f10", "洞窟: boss spawn 喺 runan_f10")


func t_cave_geometry(data: GameData) -> void:
	var sim := Sim.new(data, 1)
	# 每層 = 獨立地圖: 四邊岩壁、行得格 > 200、同隔籬層唔相連 (spec 12 §2)
	for f in range(1, 11):
		var z := sim.zone_by_id("runan_f%d" % f)
		check(not z.is_empty(), "洞窟 %dF: zone 存在" % f)
		check(not sim.is_free(int(z["x0"]), int(z["y0"])) and not sim.is_free(int(z["x1"]), int(z["y1"])), "洞窟 %dF: 角位係岩壁" % f)
		check(not sim.is_free(int(z["x1"]) + 1, int(z["y0"]) + 5), "洞窟 %dF: 地圖外 = 虛空" % f)
		var walk := 0
		for x in range(int(z["x0"]), int(z["x1"]) + 1):
			for y in range(int(z["y0"]), int(z["y1"]) + 1):
				if sim.is_free(x, y):
					walk += 1
		check(walk > 200, "洞窟 %dF: 可步行格 > 200 (實際 %d)" % [f, walk])
	# 傳送點都喺自己地圖入面 + 可企
	for p in data.travel_points:
		var zv := sim.zone_view(int(p["x"]), int(p["y"]))
		check(String(zv.get("id", "")) == String(p["map"]), "傳送點 %s 喺 %s 入面" % [p["id"], p["map"]])
		check(sim.is_free(int(p["x"]), int(p["y"])), "傳送點 %s 可企" % p["id"])


# 逃跑: HP ≥ 20% 唔會觸發
func t_flee_negative(data: GameData) -> void:
	var sim := Sim.new(data, 12)
	var pid := sim.spawn_player("t")
	_put(sim, pid, 30, 50)
	var mid: Variant = sim._spawn_mob(12012, "field_1")
	_put(sim, int(mid["id"]), 32, 50)
	mid["mob"]["home_x"] = 32
	mid["mob"]["home_y"] = 50
	mid["hp"] = int(mid["max_hp"]) * 3 / 5          # 60% HP
	sim.damage(mid, 1, sim.ent(pid))
	check(String(mid["mob"]["state"]) != "flee" and String(mid["mob"]["state"]) == "chase",
		"逃跑: 60%% HP 唔會逃 (state=%s)" % mid["mob"]["state"])
	check(int(mid["hp"]) > 0, "逃跑: 輕輕打一吓只係扣 1")

	# 逃跑後: 每撞 1 吓 roll 一次 15%，搵一粒種子令佢喺死前逃到
	var sim2: Sim
	var mid2: Dictionary = {}
	var fled := false
	var p2id := -1
	var seed := 1
	while not fled and seed < 60:
		var s2 := Sim.new(data, seed)
		var p2 := s2.spawn_player("t")
		p2id = p2
		_put(s2, p2, 30, 50)
		var m2: Variant = s2._spawn_mob(12012, "field_1")
		_put(s2, int(m2["id"]), 32, 50)
		m2["mob"]["home_x"] = 32
		m2["mob"]["home_y"] = 50
		m2["hp"] = 50                                   # max_hp ~285 → 低過 20%
		for i in 49:
			if s2.ent(int(m2["id"])).is_empty():
				break
			s2.damage(s2.ent(int(m2["id"])), 1, s2.ent(p2))
			if String(s2.ent(int(m2["id"])).get("mob", {}).get("state", "")) == "flee":
				sim2 = s2
				mid2 = s2.ent(int(m2["id"]))
				fled = true
				break
		seed += 1
	check(fled, "逃跑: 低 HP 撞到逃得甩 (有種子)")
	if fled:
		check(int(mid2["hp"]) > 0, "逃跑: 逃走時仲未死")
		# 離 leash 就消失 + 排重生 + atk_target 清
		var alt := int(mid2["id"])
		sim2.ent(p2id)["atk_target"] = alt
		var gone := false
		for i in 120:
			sim2.step()
			if sim2.ent(alt).is_empty():
				gone = true
				break
		check(gone, "逃跑: 走甩咗 (120 tick 內消失)")
		var has_respawn := false
		for r in sim2.state["respawns"]:
			if int(r["def"]) == 12012 and String(r["zone"]) == "field_1":
				has_respawn = true
		check(has_respawn, "逃跑: 排咗重生")
		var clear := true
		for e in sim2.ents.values():
			if not e.has("ch"):
				continue
			if int(e["atk_target"]) == alt:
				clear = false
		check(clear, "逃跑: 玩家 atk_target 已清")


# 群攻: 打 1 隻 → 附近 5 格同類一齊仇恨；>5 格唔會
func t_group_aggro(data: GameData) -> void:
	var sim := Sim.new(data, 21)
	var pid := sim.spawn_player("t")
	_put(sim, pid, 28, 30)
	var a: Variant = sim._spawn_mob(12028, "field_1")   # 黃蜂 groups
	_put(sim, int(a["id"]), 30, 30)
	a["mob"]["home_x"] = 30
	a["mob"]["home_y"] = 30
	var b: Variant = sim._spawn_mob(12028, "field_1")
	_put(sim, int(b["id"]), 34, 30)                     # 距 a = 4 (≤5)
	b["mob"]["home_x"] = 34
	b["mob"]["home_y"] = 30
	var c: Variant = sim._spawn_mob(12028, "field_1")
	_put(sim, int(c["id"]), 36, 30)                     # 距 a = 6 (>5)
	c["mob"]["home_x"] = 36
	c["mob"]["home_y"] = 30
	sim.damage(a, 5, sim.ent(pid))
	check(String(a["mob"]["state"]) == "chase" and int(a["mob"]["target"]) == pid, "群攻: 被打嗰隻追仇")
	check(String(b["mob"]["state"]) == "chase" and int(b["mob"]["target"]) == pid, "群攻: 5 格內同類一齊追")
	check(String(c["mob"]["state"]) != "chase", "群攻: 6 格嗰隻唔會一齊追")
	# 有冇 fixed: b, c 唔會自己 aggro 到 player (player 28,30 距 b=6>aggroRange4, 距 c=8)
	sim.step()
	check(String(b["mob"]["state"]) == "chase", "群攻: step 後 b 仍然追緊")
	check(String(c["mob"]["state"]) == "wander", "群攻: step 後 c 仍然遊蕩")
	# 逃跑緊嘅同伴唔會被叫返嚟追
	var e: Variant = sim._spawn_mob(12028, "field_1")
	_put(sim, int(e["id"]), 31, 31)
	e["mob"]["state"] = "flee"
	e["mob"]["target"] = pid
	sim.damage(a, 5, sim.ent(pid))
	check(String(e["mob"]["state"]) == "flee", "群攻: 逃跑緊嘅同伴唔會被扯返嚟追")
	# 唔同種唔連鎖
	var f: Variant = sim._spawn_mob(12003, "field_1")   # 野兔 (唔同 def)
	_put(sim, int(f["id"]), 31, 29)
	sim.damage(a, 5, sim.ent(pid))
	check(String(f["mob"]["state"]) != "chase", "群攻: 唔同種怪唔會連鎖")


# boss: 每日重生 + 唔逃跑
func t_boss(data: GameData) -> void:
	var sim := Sim.new(data, 33)
	var pid := sim.spawn_player("t")
	sim.init_mobs()
	var boss_id := 0
	for e in sim.ents.values():
		if e["kind"] == "mob" and int(e["mob"]["def"]) == 19001:
			boss_id = int(e["id"])
	check(boss_id != 0, "每日重生: init_mobs 生咗 boss")
	var boss: Dictionary = data.monsters[19001]
	check(bool(boss.get("flee", true)) == false, "每日重生: boss flee=false")
	check(not sim.is_safe(int(sim.ent(boss_id)["x"]), int(sim.ent(boss_id)["y"])), "每日重生: boss 喺非安全區")


func t_boss_daily(data: GameData) -> void:
	var sim := Sim.new(data, 7)
	var pid := sim.spawn_player("t")
	_put(sim, pid, 100, 50)
	sim.init_mobs()
	var boss_id := 0
	for e in sim.ents.values():
		if e["kind"] == "mob" and int(e["mob"]["def"]) == 19001:
			boss_id = int(e["id"])
	check(boss_id != 0, "每日重生: 生咗 boss")
	var tpd := int(1440.0 / float(int(data.world["clock"]["gameMinPerTick"])))
	sim.step()                                          # tick=1
	var cur := sim.tick
	sim.damage(sim.ent(boss_id), 999999, sim.ent(pid))
	check(sim.ent(boss_id).is_empty(), "每日重生: boss 被打死")
	var resp := {}
	for r in sim.state["respawns"]:
		if int(r["def"]) == 19001:
			resp = r
	check(not resp.is_empty(), "每日重生: boss 排咗重生")
	var target_tick := (int(cur / tpd) + 1) * tpd
	if resp.has("at"):
		check(int(resp["at"]) == target_tick, "每日重生: 排喺下一個子時 (at=%d, 期望 %d)" % [int(resp["at"]), target_tick])
		check(String(resp["zone"]) == "runan_f10", "每日重生: zone 啱")
	# 同日唔會重生
	var seen := false
	for i in mini(60, tpd - sim.tick + 1):
		sim.step()
	for e in sim.ents.values():
		if e["kind"] == "mob" and int(e["mob"]["def"]) == 19001:
			seen = true
	check(not seen, "每日重生: 同日唔會再造出嚟")
	# 過咗子時就重生
	var guard := 0
	while sim.tick < target_tick and guard < tpd + 60:
		sim.step()
		guard += 1
	var alive := false
	for e in sim.ents.values():
		if e["kind"] == "mob" and int(e["mob"]["def"]) == 19001:
			alive = true
	check(alive, "每日重生: 過子時後 boss 重生")


func t_runan_travel(data: GameData) -> void:
	var sim := Sim.new(data, 9)
	var pid := sim.spawn_player("t")
	var tp := sim.travel_point_by_id("cave_enter")
	_put(sim, pid, int(tp["x"]), int(tp["y"]))
	# 每跳: 企喺 src 點 → cmd_travel → 到 dst 點 (傳送點定義互相交連)
	# 落去: cave_enter→f1_down→f2_down→...→f9_down；上返: f10_up→f9_up→...→f2_up→cave_f1
	var jumps := ["cave_enter", "f1_down", "f2_down", "f3_down", "f4_down", "f5_down", "f6_down",
		"f7_down", "f8_down", "f9_down", "f10_up", "f9_up", "f8_up", "f7_up", "f6_up", "f5_up",
		"f4_up", "f3_up", "f2_up", "cave_f1"]
	for src in jumps:
		var from_p := sim.travel_point_by_id(src)
		var to_p := sim.travel_point_by_id(str(from_p.get("to", "")))
		_put(sim, pid, int(from_p["x"]), int(from_p["y"]))
		sim.cmd_travel(pid, src)
		check(not to_p.is_empty() and int(sim.ent(pid)["x"]) == int(to_p["x"]) and int(sim.ent(pid)["y"]) == int(to_p["y"]),
			"洞窟: %s → %s 就到" % [src, from_p.get("to", "?")])
	# 而家企喺 cave_enter 附近 → 入返去, 存檔 roundtrip
	sim.cmd_travel(pid, "cave_enter")
	var s := sim.save_string()
	var loaded := Sim.load_string(data, s)
	check(loaded != null and loaded.save_string() == s, "洞窟: 傳送後存讀檔一致")
	check(String(loaded.zone_view(int(loaded.ent(pid)["x"]), int(loaded.ent(pid)["y"])).get("id", "")) == "runan_f1",
		"洞窟: 讀檔後仍在 1F")


func t_cave_shop(data: GameData) -> void:
	var sim := Sim.new(data, 5)
	var pid := sim.spawn_player("t")
	var sh: Dictionary = {}
	for x in data.shops:
		if String(x["id"]) == "runan":
			sh = x
	_put(sim, pid, int(sh["x"]), int(sh["y"]))              # 洞窟商店 (1F)
	var shop := sim._shop_for(sim.ent(pid))
	check(not shop.is_empty() and String(shop.get("id", "")) == "runan", "洞窟商店: 揀啱邊間 (1F)")
	var ch: Dictionary = sim.player_ch()
	ch["gold"] = 100000
	var item := int(shop["stock"][0])                        # 甜蘿蔔
	var g0 := int(ch["gold"])
	sim.cmd_buy(pid, item, 1)
	check(int(ch["gold"]) < g0, "洞窟商店: 買到 (扣錢)")
	sim.cmd_sell(pid, item, 1)
	check(int(ch["gold"]) > g0 - 100000, "洞窟商店: 賣返都得")
	var s := sim.save_string()
	var loaded := Sim.load_string(data, s)
	check(loaded != null and loaded.save_string() == s, "洞窟商店: 買賣後存讀檔一致")


# 北門 (gate_in, 許昌出城落地點) 新手友善: spawn area 喺 zone 入面；門口 6 格內只有 Lv≤3、18 格內冇 Lv11+ (重生都係)
func t_gate_newbie(data: GameData) -> void:
	var gate: Dictionary = {}
	for tp in data.travel_points:
		if String(tp["id"]) == "gate_in":
			gate = tp
	var gx := int(gate["x"])
	var gy := int(gate["y"])
	for sp in data.spawns:
		if not sp.has("area"):
			continue
		var z: Dictionary = {}
		for zz in data.zones:
			if String(zz["id"]) == String(sp.get("zone", "field_1")):
				z = zz
		var a: Array = sp["area"]
		check(int(a[0]) >= int(z["x0"]) and int(a[1]) >= int(z["y0"]) and int(a[2]) <= int(z["x1"]) and int(a[3]) <= int(z["y1"]),
			"北門: spawn area 喺 zone 入面 (%s)" % sp["monster"])
	for seed in [1, 2, 3]:
		var sim := Sim.new(data, seed)
		sim.init_mobs()
		for e in sim.ents.values():
			if e["kind"] != "mob":
				continue
			var dg := maxi(absi(int(e["x"]) - gx), absi(int(e["y"]) - gy))
			check((dg > 6 or int(e["level"]) <= 3) and (dg > 18 or int(e["level"]) <= 9), "北門: 門口附近冇高等怪 (%s Lv%d @%d,%d)" % [e["name"], int(e["level"]), int(e["x"]), int(e["y"])])
		# 重生都守 area
		for i in 20:
			var m: Variant = sim._spawn_mob(11070, "field_1")
			check(m != null and maxi(absi(int(m["x"]) - gx), absi(int(m["y"]) - gy)) > 30, "北門: 重生 Lv30 喺遠處 (潁水南岸)")


# ===== S04a 地面掉落物 (spec 04 §6) =====

# 殺怪: 金錢直入袋；物品以「跌落地」實體出現(唔直入袋)，跌喺怪死位
func t_kill_drops_to_ground(data: GameData) -> void:
	var sim := Sim.new(data, 51)
	var pid := sim.spawn_player("t")
	_put(sim, pid, 30, 30)
	var fake := 999999
	data.monsters[fake] = {"id": fake, "name": "測怪", "level": 5, "hp": 50, "exp": 10,
		"gold": [1, 1], "drops": [{"item": 29042, "p": 1.0}], "rareDrops": [], "alignment": 0}
	var m: Variant = sim._spawn_mob(fake, "field_1")
	_put(sim, int(m["id"]), 31, 30)
	var ch: Dictionary = sim.player_ch()
	ch["gold"] = 0
	sim.damage(sim.ent(int(m["id"])), 99999, sim.ent(pid))
	data.monsters.erase(fake)
	check(sim.ent(int(m["id"])).is_empty(), "掉落: 怪死咗")
	check(int(ch["gold"]) == 1, "掉落: 金錢照直入袋 (+%d)" % int(ch["gold"]))
	check(RulesShop.count_item(ch["bag"], 29042) == 0, "掉落: 物品唔直入袋")
	var dropped := 0
	for e in sim.ents.values():
		if e["kind"] == "dropped":
			dropped = int(e["id"])
	check(dropped != 0, "掉落: 地上有 dropped 實體")
	if dropped != 0:
		var d: Dictionary = sim.ent(dropped)
		check(int(d["x"]) == 31 and int(d["y"]) == 30, "掉落: 跌喺怪死位 (%d,%d)" % [int(d["x"]), int(d["y"])])
		var items: Array = d["drop"]["items"]
		check(items.size() == 1 and int(items[0]["id"]) == 29042 and int(items[0]["n"]) == 1,
			"掉落: 件數啱 %s" % str(items))
		check(int(d["drop"]["until"]) == sim.tick + 300, "掉落: until = tick + 300 (%d)" % int(d["drop"]["until"]))


# 跌落物過 300 tick 後消失
func t_dropped_ttl(data: GameData) -> void:
	var sim := Sim.new(data, 52)
	var pid := sim.spawn_player("t")
	_put(sim, pid, 30, 30)
	sim._drop_items(32, 32, [{"id": 29042, "n": 1}])
	var d_id := 0
	for e in sim.ents.values():
		if e["kind"] == "dropped":
			d_id = int(e["id"])
	check(d_id != 0, "TTL: 建立掉落物")
	var start := sim.tick
	for _i in 299:
		sim.step()
	check(not sim.ent(d_id).is_empty(), "TTL: 299 tick 仲喺")
	sim.step()                                          # 到 300
	check(sim.ent(d_id).is_empty(), "TTL: 300 tick 後消失")


# 行埋邊撳拾取: 落袋 + 實體消失
func t_dropped_pick(data: GameData) -> void:
	var sim := Sim.new(data, 53)
	var pid := sim.spawn_player("t")
	_put(sim, pid, 30, 30)
	var ch: Dictionary = sim.player_ch()
	ch["bag"] = []                                       # 清袋定值
	sim._drop_items(31, 31, [{"id": 29042, "n": 2}])
	var d_id := 0
	for e in sim.ents.values():
		if e["kind"] == "dropped":
			d_id = int(e["id"])
	check(d_id != 0, "拾取: 有掉落物")
	var got: Array = [{}]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "picked" and int(ev.get("dst", 0)) == pid:
			got[0] = ev)
	sim.cmd_pick(pid, d_id)
	check(RulesShop.count_item(ch["bag"], 29042) == 2, "拾取: 落袋 ×2")
	check(sim.ent(d_id).is_empty(), "拾取: 實體消失")
	check(bool((got[0] as Dictionary).get("full", false)) == false, "拾取: 未滿 flag false")
	# 遠咗執唔到
	sim._drop_items(40, 40, [{"id": 10001, "n": 1}])
	var d2 := 0
	for e in sim.ents.values():
		if e["kind"] == "dropped":
			d2 = int(e["id"])
	sim.cmd_pick(pid, d2)
	check(not sim.ent(d2).is_empty(), "拾取: 太遠唔執 (留落地)")


# 背包滿 (重量超 capBagWeight) 逐件試: 裝得落執, 裝唔落留落地 + full flag
func t_dropped_pick_bagfull(data: GameData) -> void:
	var sim := Sim.new(data, 54)
	var pid := sim.spawn_player("t")
	_put(sim, pid, 30, 30)
	var ch: Dictionary = sim.player_ch()
	ch["bag"] = []
	sim.data.world["dropped"]["capBagWeight"] = 2        # 甜蘿蔔(w1)裝到, 柳葉刀(w8)裝唔到
	sim._drop_items(31, 31, [{"id": 29042, "n": 1}, {"id": 10001, "n": 1}])
	var d_id := 0
	for e in sim.ents.values():
		if e["kind"] == "dropped":
			d_id = int(e["id"])
	check(d_id != 0, "背包滿: 有掉落物")
	var got: Array = [{}]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "picked" and int(ev.get("dst", 0)) == pid:
			got[0] = ev)
	sim.cmd_pick(pid, d_id)
	check(RulesShop.count_item(ch["bag"], 29042) == 1, "背包滿: 輕嘢裝到 (甜蘿蔔)")
	check(RulesShop.count_item(ch["bag"], 10001) == 0, "背包滿: 重嘢裝唔到")
	check(bool((got[0] as Dictionary).get("full", false)) == true, "背包滿: full flag true")
	check(not sim.ent(d_id).is_empty(), "背包滿: 實體留落地")
	if not sim.ent(d_id).is_empty():
		var items: Array = sim.ent(d_id)["drop"]["items"]
		check(items.size() == 1 and int(items[0]["id"]) == 10001, "背包滿: 留低重嘢 %s" % str(items))


# 跌落物存檔 roundtrip (打落 + 未執照樣存到讀返)
func t_dropped_save_roundtrip(data: GameData) -> void:
	var sim := Sim.new(data, 55)
	var pid := sim.spawn_player("t")
	_put(sim, pid, 30, 30)
	sim._drop_items(31, 31, [{"id": 29042, "n": 3}])
	var d_id := 0
	for e in sim.ents.values():
		if e["kind"] == "dropped":
			d_id = int(e["id"])
	var s := sim.save_string()
	var loaded := Sim.load_string(data, s)
	check(loaded != null and loaded.save_string() == s, "存檔: 跌落物存讀一致")
	check(not loaded.ent(d_id).is_empty(), "存檔: 讀檔後仍在")
	if not loaded.ent(d_id).is_empty():
		var ld: Dictionary = loaded.ent(d_id)
		var items: Array = ld["drop"]["items"]
		check(int(ld["x"]) == 31 and int(ld["y"]) == 31 and items.size() == 1 and int(items[0]["n"]) == 3,
			"存檔: 位置 + 件數保真")


# RulesShop 重量 helpers: bag_weight / bag_fits (負重式背包滿)
func t_bag_weight_rules(data: GameData) -> void:
	var wfn := func(i: int) -> int: return int(data.weights.get(i, 0))
	var bag: Array = [{"id": 29042, "n": 3}, {"id": 10001, "n": 1}]     # 甜蘿蔔 w1×3 + 柳葉刀 w8×1 = 11
	var w0 := RulesShop.bag_weight(bag, wfn)
	check(w0 == 11, "重量規則: bag_weight 加埋件數×重量 (=%d)" % w0)
	check(RulesShop.bag_fits(bag, 29042, 1, wfn, 12), "重量規則: 12 度裝到 1 件甜蘿蔔 (11+1)")
	check(RulesShop.bag_fits(bag, 10001, 1, wfn, 19), "重量規則: 19 度裝到 1 件刀 (11+8)")
	check(not RulesShop.bag_fits(bag, 10001, 1, wfn, 12), "重量規則: 12 度裝唔到刀 (12<19)")


# S04b 術法怪: 遠程術攻擊 —— 唔使埋身，喺術距內就吟唱；aoe 打到玩家
func t_mob_cast_ranged(data: GameData) -> void:
	var sim := Sim.new(data, 61)
	var pid := sim.spawn_player("t")
	_put(sim, pid, 30, 30)
	var m: Variant = sim._spawn_mob(1007, "field_1")    # 火之術(小) range5 aoe3 castTicks10
	_put(sim, int(m["id"]), 34, 30)                     # 距 player = 4 (≤5, 唔使埋身)
	m["mob"]["home_x"] = 34
	m["mob"]["home_y"] = 30
	var hits: Array = [0]                                # GDScript 閉包要用容器先會同步
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "spell_hit" and int(ev.get("src", 0)) == int(m["id"]) and int(ev.get("dst", 0)) == pid:
			hits[0] += 1)
	var hp0 := int(sim.ent(pid)["hp"])
	sim.damage(sim.ent(int(m["id"])), 1, sim.ent(pid))   # 拉仇恨 → chase
	for _i in 30:
		sim.step()
		if sim.ent(int(m["id"])).is_empty():
			break
	check(hits[0] > 0, "術法怪遠程: aoe 術打到玩家 (hits=%d)" % hits[0])
	check(int(sim.ent(pid)["hp"]) < hp0, "術法怪遠程: 玩家扣血 (%d→%d)" % [hp0, int(sim.ent(pid)["hp"])])


# S04b 走位可躲: 吟唱鎖定落點, 行開就躲到 / 企喺落點就中 (用吟唱落點確定性測試)
func t_mob_cast_dodge(data: GameData) -> void:
	# (a) 企喺落點 → 中
	var sa := Sim.new(data, 621)
	var pid_a := sa.spawn_player("t")
	_put(sa, pid_a, 30, 30)
	var ma: Variant = sa._spawn_mob(1007, "field_1")
	_put(sa, int(ma["id"]), 34, 30)
	ma["mob"]["home_x"] = 34; ma["mob"]["home_y"] = 30
	ma["mob"]["state"] = "chase"; ma["mob"]["target"] = pid_a
	var hit_a: Array = [0]
	sa.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "spell_hit" and int(ev.get("src", 0)) == int(ma["id"]) and int(ev.get("dst", 0)) == pid_a:
			hit_a[0] += 1)
	sa.ent(int(ma["id"]))["casting"] = {"spell": "huo_s", "target": pid_a, "done_at": sa.tick + 2, "x": 30, "y": 30}
	for _i in 4:
		sa.step()
	check(hit_a[0] > 0, "彈道落點: 企喺落點 -> 中 (hits=%d)" % hit_a[0])
	# (b) 行開落點 → 走位可躲
	var sb := Sim.new(data, 622)
	var pid_b := sb.spawn_player("t")
	_put(sb, pid_b, 30, 30)
	var mb: Variant = sb._spawn_mob(1007, "field_1")
	_put(sb, int(mb["id"]), 34, 30)
	_put(sb, pid_b, 35, 35)                              # 行開到 aoe3 之外 (離落點 (30,30) 5 格)
	mb["mob"]["home_x"] = 34; mb["mob"]["home_y"] = 30
	mb["mob"]["state"] = "chase"; mb["mob"]["target"] = pid_b
	var hit_b: Array = [0]
	sb.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "spell_hit" and int(ev.get("src", 0)) == int(mb["id"]) and int(ev.get("dst", 0)) == pid_b:
			hit_b[0] += 1)
	sb.ent(int(mb["id"]))["casting"] = {"spell": "huo_s", "target": pid_b, "done_at": sb.tick + 2, "x": 30, "y": 30}
	for _i in 4:
		sb.step()
	check(hit_b[0] == 0, "彈道落點: 行開咗 -> 躲到 (hits=%d)" % hit_b[0])


# S04b 術法怪遠程: 唔會埋身近戰 (spell CD 中都企定等冷卻)
func t_mob_ranged_no_melee(data: GameData) -> void:
	var sim := Sim.new(data, 63)
	var pid := sim.spawn_player("t")
	_put(sim, pid, 30, 30)
	var m: Variant = sim._spawn_mob(1009, "field_1")    # 中邪術 range4 castTicks15 spellCd 600
	_put(sim, int(m["id"]), 31, 30)                     # 距 1 (埋到身)
	m["mob"]["home_x"] = 31
	m["mob"]["home_y"] = 30
	var melee: Array = [0]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "hit" and int(ev.get("src", 0)) == int(m["id"]):
			melee[0] += 1)
	sim.damage(sim.ent(int(m["id"])), 1, sim.ent(pid))
	for _i in 45:
		sim.step()
		if sim.ent(int(m["id"])).is_empty():
			break
	check(melee[0] == 0, "術法怪遠程: 近身都唔會近戰 (melee_hits=%d)" % melee[0])


# S04b boss 技能表: 有 skills + 會輪流放 + skill_cd 記低
func t_boss_skills(data: GameData) -> void:
	var boss: Dictionary = data.monsters[19001]
	check(boss.has("skills") and (boss["skills"] as Array).size() == 2, "boss技能表: 有 2 個技能")
	var sim := Sim.new(data, 64)
	var pid := sim.spawn_player("t")
	_put(sim, pid, 30, 30)
	var m: Variant = sim._spawn_mob(19001, "field_1")
	_put(sim, int(m["id"]), 33, 30)                     # 距 3 (huo_s range5 內)
	m["mob"]["home_x"] = 33
	m["mob"]["home_y"] = 30
	var cast_count: Array = [0]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "cast_start" and int(ev.get("src", 0)) == int(m["id"]):
			cast_count[0] += 1)
	sim.damage(sim.ent(int(m["id"])), 1, sim.ent(pid))
	for _i in 60:
		sim.step()
		if sim.ent(int(m["id"])).is_empty():
			break
	check(cast_count[0] >= 1, "boss技能: 會用技能表放術 (cast=%d)" % cast_count[0])
	if not sim.ent(int(m["id"])).is_empty():
		check(sim.ent(int(m["id"]))["mob"].has("skill_cd"), "boss技能: skill_cd 已記")


# S04b 吟唱線索透出: view_ents 吟唱中怪帶 castX/castY/castSpell (UI 畫紅圈)
func t_cast_telegraph_expose(data: GameData) -> void:
	var sim := Sim.new(data, 65)
	var pid := sim.spawn_player("t")
	_put(sim, pid, 30, 30)
	var m: Variant = sim._spawn_mob(1007, "field_1")
	_put(sim, int(m["id"]), 34, 30)
	m["mob"]["home_x"] = 34
	m["mob"]["home_y"] = 30
	sim.damage(sim.ent(int(m["id"])), 1, sim.ent(pid))
	var ok := false
	for _i in 6:
		sim.step()
		var mm = sim.ent(int(m["id"]))
		if mm.is_empty():
			break
		if not mm.has("casting"):
			continue
		for v in sim.view_ents():
			if int(v["id"]) == int(m["id"]) and bool(v.get("casting", false)) \
					and int(v["castX"]) == 30 and int(v["castY"]) == 30 and String(v.get("castSpell", "")) == "huo_s":
				ok = true
		break
	check(ok, "吟唱線索: view_ents 透出 castX/castY/castSpell")


# S04b 存檔 roundtrip: 吟唱中 mob 存讀保持 casting
func t_cast_save_roundtrip(data: GameData) -> void:
	var sim := Sim.new(data, 66)
	var pid := sim.spawn_player("t")
	_put(sim, pid, 30, 30)
	var m: Variant = sim._spawn_mob(1007, "field_1")
	_put(sim, int(m["id"]), 34, 30)
	m["mob"]["home_x"] = 34
	m["mob"]["home_y"] = 30
	sim.damage(sim.ent(int(m["id"])), 1, sim.ent(pid))
	var casting := false
	for _i in 6:
		sim.step()
		var mm = sim.ent(int(m["id"]))
		if mm.is_empty():
			break
		if mm.has("casting"):
			casting = true
			break
	check(casting, "存檔: 吟唱已開始")
	if casting:
		var s := sim.save_string()
		var loaded := Sim.load_string(data, s)
		check(loaded != null and loaded.save_string() == s, "存檔: 吟唱中存讀一致")
		check(not loaded.ent(int(m["id"])).is_empty() and loaded.ent(int(m["id"])).has("casting"),
			"存檔: 讀檔後仲吟唱緊")
