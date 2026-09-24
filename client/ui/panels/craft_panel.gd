class_name CraftPanel
extends GamePanel
# 進階生產面板 (Step 12, spec 05 §4): 喺廚房/藥房/工房開 = 每個進階技能一頁 + 「修理」頁 (工房)；打鐵鋪開 = 「修理服務」。
# 左 = 配方 / 要修嘅裝備列表；右 = 詳情 (材料 有/要、成功率、原因) + 確認掣。
# 可唔可以做由 sim.adv_check 判斷 (同 sim 一致)；UI 只發 craft / repair / repair_service 意圖。

const LIST_AHEAD := 10         # 配方列表顯示到 技能等級 + 10
const LIST_MAX := 60           # 最多列幾多個 (高等配方由尾計)

var skills: Array = []         # 呢間設施做得嘅進階技能
var has_repair := false        # 有「修理」頁 (自己修)
var service := false           # 打鐵鋪修理服務
var sel := 0


func _init(m: Node) -> void:
	super(m)


# 廚房/藥房/工房
func open_craft(fac_name: String, crafts: Array) -> void:
	service = false
	skills = crafts
	has_repair = false
	var names: Array = []
	for sk in crafts:
		names.append(str(main.data.work_adv[sk]["name"]))
		if not (main.data.work_adv[sk].get("repairs", []) as Array).is_empty():
			has_repair = true
	if has_repair:
		names.append("修理")
	title_lbl.text = fac_name
	_reset(names)


# 打鐵鋪修理服務
func open_service(fac_name: String) -> void:
	service = true
	skills = []
	has_repair = false
	title_lbl.text = fac_name
	_reset(["修理服務"])


func _reset(names: Array) -> void:
	sel = 0
	tab = 0
	set_tabs(names)
	open()


func set_tab(i: int) -> void:
	sel = 0
	super(i)


func sig() -> String:
	var ch: Dictionary = main.ch
	return JSON.stringify([tab, sel, ch.get("bag", []), ch.get("workLv", {}), ch.get("tools", {}), ch.get("sp", 0), ch.get("gold", 0),
		ch.get("equip", {}).get("dur", {})])


func _me() -> Dictionary:
	return main.sim.ent(main.my_id)


func _bag_n(id: int) -> int:
	return RulesShop.count_item(main.ch.get("bag", []), id)


func _cols() -> Array:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.2
	row.add_child(left)
	var rs := scroll()
	row.add_child(rs)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	rs.add_child(right)
	return [left, right]


func _build_body() -> void:
	var ch: Dictionary = main.ch
	if ch.is_empty() or main.sim == null:
		return
	var lr := _cols()
	if service or tab >= skills.size():
		_build_repair(lr[0], lr[1], ch)
	else:
		_build_craft(lr[0], lr[1], ch, String(skills[tab]))


# 技能狀態列: 等級/經驗 + 工具
func _skill_head(p: Control, ch: Dictionary, skill: String) -> void:
	var sim = main.sim
	var ad: Dictionary = main.data.work_adv[skill]
	var lv: int = sim.work_lv(ch, skill)
	if lv <= 0:
		p.add_child(lbl("%s 未解鎖" % ad["name"], 15, UiTheme.BAD))
		return
	var w: Dictionary = ch.get("workLv", {}).get(skill, {"lv": lv, "exp": 0})
	p.add_child(lbl("%s Lv%d  (%d/%d)" % [ad["name"], lv, int(w.get("exp", 0)), RulesWork.exp_to_next(lv, main.data.work_meta["level"])], 15, UiTheme.GOLD))
	var tool: Dictionary = ch.get("tools", {}).get(skill, {})
	var tid := int(ad["tool"])
	if tool.is_empty():
		if _bag_n(tid) > 0:
			p.add_child(btn("裝備%s" % item_name(tid), func() -> void: main._send({"t": "equip_tool", "skill": skill, "item": tid})))
		else:
			p.add_child(lbl("未裝%s（工具店有得買）" % item_name(tid), 13, UiTheme.BAD))
	else:
		p.add_child(lbl("%s 耐久 %d" % [item_name(int(tool["item"])), int(tool["dur"])], 13, UiTheme.DIM))


func _build_craft(left: Control, right: Control, ch: Dictionary, skill: String) -> void:
	var sim = main.sim
	var ad: Dictionary = main.data.work_adv[skill]
	_skill_head(left, ch, skill)
	var lv: int = sim.work_lv(ch, skill)
	if lv <= 0:
		var names: Array = []
		for s in ad["from"]:
			names.append(str(main.data.work[s]["name"]))
		left.add_child(wrap_lbl("要%s其中一樣做到 %d 級先解鎖。" % ["/".join(names), int(ad["unlockLv"])], 14, UiTheme.DIM))
		return
	var counts: Dictionary = sim._bag_counts(ch.get("bag", []))
	var sc := scroll()
	left.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	sc.add_child(list)
	var shown: Array = []
	for r in main.data.recipes_by_skill.get(skill, []):
		if int(r["lv"]) <= lv + LIST_AHEAD:
			shown.append(r)
	if shown.size() > LIST_MAX:
		shown = shown.slice(shown.size() - LIST_MAX)
	for r in shown:
		var id := int(r["id"])
		var lv_ok := int(r["lv"]) <= lv
		var mat_ok := RulesWork.has_materials(counts, r["need"])
		var b := btn("%s  Lv%d%s" % [item_name(id), int(r["lv"]), "  ✓" if lv_ok and mat_ok else ""], func() -> void:
			sel = id
			refresh(true))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.set_pressed_no_signal(sel == id)
		b.add_theme_color_override("font_color", UiTheme.GOOD if lv_ok and mat_ok else UiTheme.TEXT if lv_ok else UiTheme.DIM)
		list.add_child(b)
	if sel == 0 or not main.data.recipes.has(sel):
		right.add_child(wrap_lbl("揀一個配方。✓ = 材料齊、等級夠。", 14, UiTheme.DIM))
		return
	var rc: Dictionary = main.data.recipes[sel]
	right.add_child(lbl(item_name(sel), 18, UiTheme.GOLD))
	for s in item_desc(sel):
		right.add_child(wrap_lbl(str(s), 13, UiTheme.DIM))
	right.add_child(lbl("要%s Lv%d" % [ad["name"], int(rc["lv"])], 14, UiTheme.TEXT if int(rc["lv"]) <= lv else UiTheme.BAD))
	right.add_child(lbl("材料:", 14))
	for m in rc["need"]:
		var have := int(counts.get(int(m[0]), 0))
		right.add_child(lbl("  %s  %d/%d" % [item_name(int(m[0])), have, int(m[1])], 14, UiTheme.GOOD if have >= int(m[1]) else UiTheme.BAD))
	var p := RulesWork.craft_chance(lv, int(rc["lv"]), main.data.work_meta["craftRate"])
	right.add_child(lbl("成功率 %d%%   失敗 %d%% 機會冇咗材料" % [roundi(p * 100), roundi(float(main.data.work_meta["craftRate"]["failLoseMat"]) * 100)], 13, UiTheme.DIM))
	var err: String = sim.adv_check(_me(), skill, int(rc["lv"]))
	if err == "" and not RulesWork.has_materials(counts, rc["need"]):
		err = "材料唔夠"
	if err != "":
		right.add_child(lbl(err, 13, UiTheme.BAD))
	var id2 := sel
	var b2 := btn("製作", func() -> void: main._send({"t": "craft", "item": id2}))
	b2.disabled = err != ""
	right.add_child(b2)


# 要修嘅裝備: 身上 + 背包有耐久記錄嘅 (唔滿)；自己修 = 只列呢間設施技能修得嘅
func _repair_items(ch: Dictionary) -> Array:
	var out: Array = []
	var dur: Dictionary = ch.get("equip", {}).get("dur", {})
	for k in dur:
		var id := int(k)
		var mx: int = main.sim._max_dur(id)
		if mx <= 0 or _bag_n(id) <= 0:
			continue
		if not service and not skills.has(main.sim.repair_skill(id)):
			continue
		out.append(id)
	out.sort()
	return out


func _build_repair(left: Control, right: Control, ch: Dictionary) -> void:
	var sim = main.sim
	var dur: Dictionary = ch.get("equip", {}).get("dur", {})
	if service:
		left.add_child(lbl("金 %d" % int(ch.get("gold", 0)), 15, UiTheme.GOLD))
	else:
		left.add_child(wrap_lbl("武器 = 冶鐵、頭/身/靴 = 修繕、戒指/項鍊 = 木匠", 13, UiTheme.DIM))
	var sc := scroll()
	left.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	sc.add_child(list)
	var items := _repair_items(ch)
	if items.is_empty():
		list.add_child(lbl("（冇裝備要修）", 14, UiTheme.DIM))
	for id in items:
		var mx: int = sim._max_dur(id)
		var cur := int(dur.get(str(id), mx))
		var b := btn("%s  %d/%d" % [item_name(id), cur, mx], func() -> void:
			sel = id
			refresh(true))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.set_pressed_no_signal(sel == id)
		b.add_theme_color_override("font_color", UiTheme.BAD if cur <= 0 else UiTheme.TEXT if cur < mx else UiTheme.DIM)
		list.add_child(b)
	if sel == 0 or not items.has(sel):
		right.add_child(wrap_lbl("揀一件裝備。耐久 0 = 效果減半。", 14, UiTheme.DIM))
		return
	var id2 := sel
	var mx2: int = sim._max_dur(id2)
	var cur2 := int(dur.get(str(id2), mx2))
	right.add_child(lbl(item_name(id2), 18, UiTheme.GOLD))
	right.add_child(lbl("耐久 %d/%d" % [cur2, mx2], 15, UiTheme.BAD if cur2 <= 0 else UiTheme.TEXT))
	if cur2 >= mx2:
		right.add_child(lbl("耐久已滿", 14, UiTheme.DIM))
		return
	if service:
		var cost: int = sim.repair_service_cost(ch, id2)
		var ok := int(ch.get("gold", 0)) >= cost
		right.add_child(lbl("修理費 %d 金%s" % [cost, "" if ok else "（唔夠錢）"], 15, UiTheme.TEXT if ok else UiTheme.BAD))
		var b1 := btn("修理", func() -> void: main._send({"t": "repair_service", "item": id2}))
		b1.disabled = not ok
		right.add_child(b1)
		return
	var skill: String = sim.repair_skill(id2)
	var need: int = sim.repair_need_lv(id2)
	_skill_head(right, ch, skill)
	right.add_child(lbl("要%s Lv%d" % [main.data.work_adv[skill]["name"], need], 14))
	var err: String = sim.adv_check(_me(), skill, need)
	if err != "":
		right.add_child(lbl(err, 13, UiTheme.BAD))
	var b2 := btn("自己修理", func() -> void: main._send({"t": "repair", "item": id2}))
	b2.disabled = err != ""
	right.add_child(b2)
