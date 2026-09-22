class_name SaveSys
extends RefCounted
# 存檔層 (Step 4.1): Godot 冇內建 SQLite → 用 JSON 檔 (user://save/*.json)。
# 檔案格式 = sim.save_string() (state + rng)，同 legacy 版「單一檔案可重現」一致。
# 目標: 角色/背包/世界狀態/NPC 記憶全部喺 state 內，將來可搬去 SQLite。

const SLOT := "user://save/slot1.json"
const AUTOSLOT := "user://save/autoslot.json"


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