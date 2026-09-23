class_name DialogPanel
extends GamePanel
# NPC 對話框（客棧/練兵場/私塾/寺廟/打鐵鋪/任務答題）: 下半屏視窗 + 大選項掣。
# source: Callable -> {title, text, options: [{label, cb: Callable, disabled?}], qte?: Callable -> float 0..1}
# 內容由 source 每 0.2 秒重新計（金錢/狀態變咗掣會即時轉灰）。

var source: Callable
var qte_bar: Control


func _init(m: Node) -> void:
	super(m)


func open_with(src: Callable) -> void:
	source = src
	open()


func _win_rect(safe: Rect2) -> Rect2:
	var w := minf(safe.size.x - 20, 520.0)
	var h := minf(safe.size.y - 20, 250.0)
	return Rect2(safe.position.x + (safe.size.x - w) / 2, safe.end.y - h - 10, w, h)


func _content() -> Dictionary:
	if not source.is_valid():
		return {}
	return source.call()


func sig() -> String:
	var c := _content()
	var labs: Array = [c.get("title", ""), c.get("text", "")]
	for o in c.get("options", []):
		labs.append([o.get("label", ""), o.get("disabled", false)])
	return JSON.stringify(labs)


func _process(delta: float) -> void:
	super(delta)
	if visible and qte_bar != null:
		qte_bar.queue_redraw()


func _build_body() -> void:
	var c := _content()
	if c.is_empty():
		close()
		return
	title_lbl.text = str(c.get("title", ""))
	var sc := scroll()
	sc.custom_minimum_size.y = 40
	sc.add_child(wrap_lbl(str(c.get("text", "")), 15))
	body.add_child(sc)
	qte_bar = null
	if c.has("qte"):
		var q: Callable = c["qte"]
		qte_bar = Control.new()
		qte_bar.custom_minimum_size = Vector2(0, 26)
		qte_bar.draw.connect(func() -> void: _draw_qte(qte_bar, float(q.call())))
		body.add_child(qte_bar)
	var opts: Array = c.get("options", [])
	var g := GridContainer.new()
	g.columns = 1 if opts.size() <= 2 or win.size.x < 420 else 2
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	body.add_child(g)
	for o in opts:
		var cb: Callable = o["cb"]
		var b := btn(str(o["label"]), cb)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = bool(o.get("disabled", false))
		g.add_child(b)


# 融合集氣棒: 金色窗口 = RulesJewel 目標 ± 窗口
func _draw_qte(c: Control, pos: float) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Color(0.15, 0.15, 0.15))
	var x0 := r.size.x * (RulesJewel.FUSION_TARGET - RulesJewel.FUSION_WINDOW)
	c.draw_rect(Rect2(x0, 0, r.size.x * RulesJewel.FUSION_WINDOW * 2, r.size.y), Color(0.6, 0.75, 0.2))
	c.draw_rect(Rect2(r.size.x * clampf(pos, 0, 1) - 2, -3, 4, r.size.y + 6), Color(1, 0.4, 0.2))
