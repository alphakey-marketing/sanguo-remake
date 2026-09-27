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


static func save(sim: Sim, slot: String = SLOT) -> bool:
	ensure_dir()
	var f := FileAccess.open(slot, FileAccess.WRITE)
	if f == null or not f.is_open():
		return false
	var ok := f.store_string(sim.save_string())
	f.close()
	return ok


static func read_sim(data: GameData, slot: String = SLOT) -> Sim:
	if not has(slot):
		return null
	var s := FileAccess.get_file_as_string(slot)
	return Sim.load_string(data, s)


static func autosave(sim: Sim) -> bool:
	return save(sim, AUTOSLOT)


static func read_autosave(data: GameData) -> Sim:
	return read_sim(data, AUTOSLOT)


# ---- 多角色 slot（U-fix: 建角/存檔主頁面） ----
static func slot_path(n: int) -> String:
	return "user://save/char_slot%d.json" % n


static func slot_exists(n: int) -> bool:
	return has(slot_path(n))


static func save_slot(sim: Sim, n: int) -> bool:
	return save(sim, slot_path(n))


static func read_slot(data: GameData, n: int) -> Sim:
	return read_sim(data, slot_path(n))


static func delete_slot(n: int) -> void:
	var p := slot_path(n)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


# 揀存檔主頁面用: 每個 slot 嘅簡介 {n, exists, name, level, day}
static func slot_summaries(data: GameData) -> Array:
	var out: Array = []
	for n in range(1, SLOT_COUNT + 1):
		var info := {"n": n, "exists": false, "name": "", "level": 1, "day": 1}
		if slot_exists(n):
			var sim := read_slot(data, n)
			if sim != null:
				var pid := int(sim.state.get("player_id", 0))
				var ch: Dictionary = sim.state.get("chars", {}).get(str(pid), {})
				info["exists"] = true
				info["name"] = str(ch.get("name", "?"))
				info["level"] = int(ch.get("level", 1))
				info["day"] = int(sim.clock_view().get("day", 1))
		out.append(info)
	return out