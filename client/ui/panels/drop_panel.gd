class_name DropPanel
extends GamePanel
# 掉寶表：靜態查詢面板，唔發 sim 意圖，淨係查 GameData.monsters 嘅 drops/rareDrops 起反查表
# item id -> [{mon 名, lv, p, rare}]，比玩家知邊隻怪/機率幾多。

var _idx: Dictionary = {}   # item id -> Array[{mon, lv, p, rare}]
var _built := false
var _expanded: Dictionary = {}   # item id -> bool


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "掉寶表"
	set_tabs(["全部", "武器", "防具"])


func _ensure_index() -> void:
	if _built:
		return
	_built = true
	for mid in main.data.monsters:
		var md: Dictionary = main.data.monsters[mid]
		var mname := str(md.get("name", "?"))
		var lv := int(md.get("level", 0))
		for d in md.get("drops", []):
			_add(int(d["item"]), mname, lv, float(d.get("p", 0.0)), false)
		for d in md.get("rareDrops", []):
			_add(int(d["item"]), mname, lv, float(d.get("p", 0.0)), true)


func _add(item_id: int, mname: String, lv: int, p: float, rare: bool) -> void:
	if not _idx.has(item_id):
		_idx[item_id] = []
	(_idx[item_id] as Array).append({"mon": mname, "lv": lv, "p": p, "rare": rare})


func sig() -> String:
	return "%d|%s" % [tab, JSON.stringify(_expanded)]


func _build_body() -> void:
	_ensure_index()
	var sc := scroll()
	body.add_child(sc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var ids: Array = _idx.keys()
	ids.sort_custom(func(a, b) -> bool: return item_name(a) < item_name(b))
	var shown := 0
	for id in ids:
		if tab == 1 and not main.data.weapons.has(id):
			continue
		if tab == 2 and not main.data.armors.has(id):
			continue
		shown += 1
		var entries: Array = (_idx[id] as Array).duplicate()
		entries.sort_custom(func(a, b) -> bool: return float(a["p"]) > float(b["p"]))
		var open_ := bool(_expanded.get(id, false))
		var row := btn("%s  %s（%d 個來源）" % ["▼" if open_ else "▶", item_name(id), entries.size()],
			func() -> void:
				_expanded[id] = not open_
				refresh(true))
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(row)
		if open_:
			for e in entries:
				var pct := float(e["p"]) * 100.0
				var tag := "稀有" if bool(e["rare"]) else "掉落"
				v.add_child(lbl("　　%s Lv%d — %s %.2f%%" % [str(e["mon"]), int(e["lv"]), tag, pct], 13, UiTheme.TEXT))
	if shown == 0:
		v.add_child(lbl("（呢類冇掉寶紀錄）", 14, UiTheme.TEXT))
