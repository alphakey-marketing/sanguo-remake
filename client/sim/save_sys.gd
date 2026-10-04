class_name SaveSys
extends RefCounted
# 存檔層 (Step 4.1): Godot 冇內建 SQLite → 用 JSON 檔 (user://save/*.json)。
# 檔案格式 = sim.save_string() (state + rng)，同 legacy 版「單一檔案可重現」一致。
# 目標: 角色/背包/世界狀態/NPC 記憶全部喺 state 內，將來可搬去 SQLite。
# U-fix: 加多角色 slot（slot1~SLOT_COUNT），配合開場「主頁面」panel 揀存檔/新建角。
# 每個 slot 有自己嗰份 autosave；AUTOSLOT 常數保留住做「而家用緊嗰個 slot」嘅路徑（向下兼容）。

const SLOT := "user://save/slot1.json"
const AUTOSLOT := "user://save/autoslot.json"
const SLOT_COUNT := 3


static func has(slot: String = SLOT) -> bool:
	return FileAccess.file_exists(slot)


static func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://save"))


# 存檔格式 v2: {"v":2,"meta":{..},"state":..,"rng":..}；v1 (冇 v/meta) 照讀得
const FORMAT_VER := 2


# 揀存檔畫面用嘅簡介 (唔使載入成個 Sim)
static func make_meta(sim: Sim) -> Dictionary:
	var pid := int(sim.state.get("player_id", 0))
	var pe: Dictionary = sim.ent(pid)
	var ch: Dictionary = sim.state.get("chars", {}).get(str(pid), {})
	if ch.is_empty():
		ch = pe.get("ch", {})
	var cls: Dictionary = sim.data.classes.get(str(ch.get("classId", "")), {})
	var zv: Dictionary = sim.zone_view(int(pe.get("x", 0)), int(pe.get("y", 0))) if not pe.is_empty() else {}
	var place := str(zv.get("area", ""))
	if place == "":
		place = str(zv.get("name", ""))
	return {"name": str(ch.get("name", "?")), "level": int(ch.get("level", 1)),
		"cls": str(cls.get("name", "")), "classId": str(ch.get("classId", "")),
		"day": int(sim.clock_view().get("day", 1)), "place": place,
		"gold": int(ch.get("gold", 0)), "ts": int(Time.get_unix_time_from_system())}


# 原子寫入: 先寫 .tmp → 舊檔轉 .bak → .tmp 改正檔；中途死機最多剩 .tmp/.bak，正檔唔會半截
static func save(sim: Sim, slot: String = SLOT) -> bool:
	ensure_dir()
	# 唔好 parse 再 stringify: rng 係大整數，過 float 會失精度 → 續跑唔一致。直接拼字串
	var body := sim.save_string()
	if not body.ends_with("}"):
		return false
	body = body.substr(0, body.length() - 1) + ',"v":%d,"meta":%s}' % [FORMAT_VER, JSON.stringify(make_meta(sim))]
	var tmp := slot + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null or not f.is_open():
		return false
	var ok := f.store_string(body)
	f.close()
	if not ok:
		return false
	var gp := ProjectSettings.globalize_path(slot)
	if FileAccess.file_exists(slot):
		DirAccess.copy_absolute(gp, gp + ".bak")
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), gp) == OK


# 讀檔: 正檔壞咗就試 .bak；兩個都唔得 = null
static func read_sim(data: GameData, slot: String = SLOT) -> Sim:
	for p in [slot, slot + ".bak"]:
		if has(p):
			var sim := Sim.load_string(data, FileAccess.get_file_as_string(p))
			if sim != null:
				return sim
	return null


# 檔案狀態: "none" 冇檔 / "ok" 正檔讀得 / "bak" 正檔壞但 .bak 得 / "bad" 兩個都壞
static func slot_state(slot: String) -> String:
	if not has(slot) and not has(slot + ".bak"):
		return "none"
	if _meta_of(slot).get("ok", false):
		return "ok"
	if has(slot + ".bak") and _meta_of(slot + ".bak").get("ok", false):
		return "bak"
	return "bad"


# 只 parse JSON 攞 meta (v1 舊檔冇 meta → 由 state 抽)
static func _meta_of(path: String) -> Dictionary:
	if not has(path):
		return {"ok": false}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary or not d.has("state") or not d.has("rng"):
		return {"ok": false}
	var m: Dictionary = d.get("meta", {})
	if m.is_empty():
		var st: Dictionary = d["state"]
		var pid := str(int(st.get("player_id", 0)))
		var ch: Dictionary = st.get("ents", {}).get(pid, {}).get("ch", {})
		m = {"name": str(ch.get("name", "?")), "level": int(ch.get("level", 1)), "cls": "", "classId": str(ch.get("classId", "")),
			"day": int(st.get("clock", {}).get("day", 0)) + 1, "place": "", "gold": int(ch.get("gold", 0)), "ts": 0}
	m = m.duplicate()
	m["ok"] = true
	return m


static func autosave(sim: Sim) -> bool:
	return save(sim, AUTOSLOT)


static func read_autosave(data: GameData) -> Sim:
	return read_sim(data, AUTOSLOT)


# ---- 多角色 slot（U-fix: 建角/存檔主頁面） ----
static func slot_path(n: int) -> String:
	return "user://save/char_slot%d.json" % n


static func slot_exists(n: int) -> bool:
	return has(slot_path(n)) or has(slot_path(n) + ".bak")


static func save_slot(sim: Sim, n: int) -> bool:
	return save(sim, slot_path(n))


static func read_slot(data: GameData, n: int) -> Sim:
	return read_sim(data, slot_path(n))


static func delete_slot(n: int) -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		var p: String = slot_path(n) + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


# 揀存檔主頁面用: 每個 slot 嘅簡介 {n, exists, state, name, level, cls, day, place, gold, ts}
static func slot_summaries(_data: GameData = null) -> Array:
	var out: Array = []
	for n in range(1, SLOT_COUNT + 1):
		var info := {"n": n, "exists": false, "state": "none", "name": "", "level": 1, "cls": "", "day": 1, "place": "", "gold": 0, "ts": 0}
		var st := slot_state(slot_path(n))
		info["state"] = st
		if st != "none":
			info["exists"] = true
			var m := _meta_of(slot_path(n) if st == "ok" else slot_path(n) + ".bak")
			if m.get("ok", false):
				for k in ["name", "level", "cls", "day", "place", "gold", "ts"]:
					info[k] = m[k]
		out.append(info)
	return out


# unix 秒 → "10-04 21:30"；0 = 未存過
static func ts_text(ts: int) -> String:
	if ts <= 0:
		return "未存"
	var d := Time.get_datetime_dict_from_unix_time(ts + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	return "%02d-%02d %02d:%02d" % [d.month, d.day, d.hour, d.minute]
