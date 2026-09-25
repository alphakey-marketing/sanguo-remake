extends SceneTree
# 潛行純函數測試 (S02c, spec 02 §6): RulesStealth 行車空隙 pattern / 穿越判定 / 潛行狀態。
# 跑: Godot --headless --path client --script tests/run_stealth.gd

var fails := 0
var total := 0
var _rh: Array = []          # 保住 SimRng 實例 (RefCounted, 依 instance 先唔好被free)


func _init() -> void:
	t_pattern_deterministic()
	t_gap_open()
	t_cross_pattern()
	t_stealth_state()
	print("[TEST] stealth: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


func _rng(seed: int) -> Callable:
	var s := SimRng.new(seed)
	_rh.append(s)
	return Callable(s, "next")


func t_pattern_deterministic() -> void:
	var r1 := _rng(7)
	var p1 := RulesStealth.make_pattern(r1)
	var r2 := _rng(7)
	var p2 := RulesStealth.make_pattern(r2)
	check(p1.size() == RulesStealth.GAP_COUNT, "pattern 有 %d 卡空隙" % RulesStealth.GAP_COUNT)
	check(p1[0] == p2[0] and p1[1] == p2[1] and p1[2] == p2[2], "同 seed → 同 pattern (可重現)")
	for i in RulesStealth.GAP_COUNT:
		var off := int(p1[i])
		check(off >= 0 and off <= RulesStealth.CART_PERIOD - RulesStealth.GAP_W, "offset[%d]=%d 喺有效範圍" % [i, off])


func t_gap_open() -> void:
	var pat := [2, 0, 5]
	var start := 100
	# gap0 窗口 = [100+2*0+2, +3) = [102,105)
	check(not RulesStealth.gap_open(pat, start, 0, 101), "gap0 未到: 101 唔開")
	check(RulesStealth.gap_open(pat, start, 0, 102), "gap0 幵: 102 開")
	check(RulesStealth.gap_open(pat, start, 0, 104), "gap0 開: 104 開")
	check(not RulesStealth.gap_open(pat, start, 0, 105), "gap0 結束: 105 唔開")
	# gap1 窗口 = [100+1*10+0, +3) = [110,113)
	check(RulesStealth.gap_open(pat, start, 1, 110), "gap1 開: 110")
	check(not RulesStealth.gap_open(pat, start, 1, 113), "gap1 完: 113 唔開")
	# 越界 index
	check(not RulesStealth.gap_open(pat, start, 5, 120), "越界 index: 唔開")
	check(not RulesStealth.gap_open(pat, start, -1, 120), "負 index: 唔開")


func t_cross_pattern() -> void:
	var pat := [2, 0, 5]
	var start := 100
	# 順序穿: gap0 -> gap1 -> gap2
	check(RulesStealth.cross_pattern(pat, start, 0, 104), "cross gap0 ok")
	check(RulesStealth.cross_pattern(pat, start, 1, 112), "cross gap1 ok")
	check(RulesStealth.cross_pattern(pat, start, 2, 125), "cross gap2 ok")
	# 撳早/撳遲 -> 唔得 (仲喺 gap0 嘅 phase 撳, = 撞車)
	check(not RulesStealth.cross_pattern(pat, start, 0, 101), "cross gap0 撳早: 撞車")
	check(not RulesStealth.cross_pattern(pat, start, 0, 120), "cross gap0 撳錯時段: 撞車")


func t_stealth_state() -> void:
	var st := {}
	var tick := 500
	check(not RulesSpell.has(st, "stealth", tick), "初時唔係潛行")
	RulesSpell.add_status(st, "stealth", RulesStealth.STEALTH_TICKS, tick)
	check(RulesStealth.is_stealth(st, tick), "加入後係潛行")
	check(RulesStealth.is_stealth(st, tick + RulesStealth.STEALTH_TICKS - 1), "就完之前仲係潛行")
	check(not RulesStealth.is_stealth(st, tick + RulesStealth.STEALTH_TICKS), "時間到唔係潛行")
	check(RulesStealth.STEALTH_CD_TICKS == 720, "潛行 CD = 1 game 日 (720 tick)")
	check(RulesStealth.STEALTH_TICKS == 5, "潛行持續 = 10 分鐘 (5 tick)")