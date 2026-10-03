class_name RulesScene
extends RefCounted
# 特殊場景純函數 (S04d, spec 04 §4)【原 sy3_10_1~7】: 桃花渡/七彩奪寶陣首批。
# 場景 = 多層地圖階梯 (同戰役)，但:
#  - 開門窗 = game 日曆 (每月初一~初三、十五~十七 = schedule.days, 1 起)【單機化】,唔係戰役嗰種時辰窗
#  - 每層可以有多款怪物 (density 隻) + 指定 boss (boss:true) 打完先過層
#  - 掉落用地面掉落物 (S04a)（怪物自己帶 drops 攻略全表），唔似戰役直入袋

const DEFAULT_MONTH_DAYS := 30


static func find(scenes: Array, id: String) -> Dictionary:
	for s in scenes:
		if String(s["id"]) == id:
			return s
	return {}


# game 月第幾日 (1 起)。day 由 day_of_tick 計出嚟 (0 起)
static func day_of_month(day: int, month_days: int) -> int:
	return day % maxi(1, month_days) + 1


# 場景今日開唔開門 (game 日曆窗口): schedule.days 包唔包今日
static func is_open(scene: Dictionary, day: int, month_days: int) -> bool:
	var days: Array = scene.get("schedule", {}).get("days", [])
	if days.is_empty():
		return true                 # 冇 schedule = 長期開放
	var dom := day_of_month(day, month_days)
	for dd in days:
		if int(dd) == dom:
			return true
	return false


# 揀今日常見錯誤點提示用: 唔開就話幾號開
static func open_days_text(scene: Dictionary) -> String:
	var days: Array = scene.get("schedule", {}).get("days", [])
	if days.is_empty():
		return "長期開放"
	var parts: Array = []
	var i := 0
	while i < days.size():
		var j := i
		while j + 1 < days.size() and int(days[j + 1]) == int(days[j]) + 1:
			j += 1
		if i == j:
			parts.append("%d日" % int(days[i]))
		else:
			parts.append("%d~%d日" % [int(days[i]), int(days[j])])
		i = j + 1
	return "、".join(parts)


# 可以入? 得 = ""，唔得 = 提示字
static func can_enter(scene: Dictionary, level: int, day: int, month_days: int, force_open := false) -> String:
	if scene.is_empty():
		return "而家冇特殊場景開放"
	if not force_open and not is_open(scene, day, month_days):
		return "今日唔係%s開門日（每月%s）" % [String(scene.get("name", "")), open_days_text(scene)]
	if level < int(scene.get("minLevel", 1)):
		return "武等 ≥ %d 先入得%s" % [int(scene["minLevel"]), String(scene.get("name", ""))]
	return ""


static func layer_of(scene: Dictionary, idx: int) -> Dictionary:
	var layers: Array = scene.get("layers", [])
	if idx < 0 or idx >= layers.size():
		return {}
	return layers[idx]


static func layer_count(scene: Dictionary) -> int:
	return (scene.get("layers", []) as Array).size()


static func is_last_layer(scene: Dictionary, idx: int) -> bool:
	return idx >= layer_count(scene) - 1


# 層入面邊隻係大頭目 (boss:true)；冇 = "" (該層冇 boss → 就咁打齊唔使過層, 由 sim 決定)
static func layer_boss(scene: Dictionary, layer: Dictionary) -> String:
	for mid in layer.get("monsters", []):
		if bool(scene_boss_of(scene, int(mid))):
			return str(mid)
	return ""


# 場景怪物 list (id -> def)
static func scene_boss_of(scene: Dictionary, mid: int) -> bool:
	for md in scene.get("monsters", []):
		if int(md["id"]) == mid:
			return bool(md.get("boss", false))
	return false