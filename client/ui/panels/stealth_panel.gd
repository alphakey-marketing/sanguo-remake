class_name StealthPanel
extends GamePanel
# 巫女特技「潛行」小遊戲 (S02c, spec 02 §6【自訂】簡化): 行車之間穿越。
# sim 權威: cmd_use_skill("yinxing") -> 生成行車空隙 pattern -> emit stealth_open -> 呢個面板
# -> 撳「穿過」-> cmd_stealth_cross -> 每卡車空隙啱時嗰下穿 -> 全穿成功 emit stealth_done（面板閂 + 入潛行）；
#            撞車 -> emit stealth_fail（面板閂，可以再試）。
# 畫面: 一條車路，一路 update 車位 + 穿梭點；穿梭點行到空隙嗰吓顯示「宜家穿！」。


var _road_lbl: Label
var _hit_lbl: Label
var _prog_lbl: Label


func _init(m: Node) -> void:
	super(m)
	margin = 20.0


func _win_rect(safe: Rect2) -> Rect2:
	var w := minf(safe.size.x - 20, 460.0)
	var h := minf(safe.size.y - 20, 200.0)
	return Rect2(safe.position.x + (safe.size.x - w) / 2, safe.end.y - h - 10, w, h)


func sig() -> String:
	return "stealth"        # 一次過砌；progress 由 _process 更新（唔想每 tick 重砌成個面板）


func _build_body() -> void:
	title_lbl.text = "潛行"
	_road_lbl = Label.new()
	_road_lbl.add_theme_font_size_override("font_size", 16)
	_hit_lbl = Label.new()
	_hit_lbl.add_theme_font_size_override("font_size", 15)
	_hit_lbl.add_theme_color_override("font_color", UiTheme.GOLD)
	_prog_lbl = Label.new()
	_prog_lbl.add_theme_font_size_override("font_size", 14)
	body.add_child(wrap_lbl("行車之間穿越：車車之間有「·」空隙，等穿梭點「▲」行到空隙嗰吓先撳「穿過」。撞車就失敗！", 14))
	body.add_child(_prog_lbl)
	body.add_child(_road_lbl)
	body.add_child(_hit_lbl)
	var b := btn("穿過", func() -> void:
		main._send({"t": "stealth_cross"}))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(120, 48)
	body.add_child(b)
	body.add_child(lbl("（成功自動入潛行 10 分鐘；撞車就失敗，可再撳潛行再試）", 11, UiTheme.GOLD))
	_refresh_road()


func _process(delta: float) -> void:
	super(delta)
	if visible:
		_refresh_road()


# 由 sim 權威讀: main.sim.player_ch()["stealthGame"]，一路畫車位同穿梭點
func _refresh_road() -> void:
	if _road_lbl == null:
		return
	var now := int(main.sim.state["tick"])
	var ch: Dictionary = main.sim.player_ch()
	var g: Dictionary = ch.get("stealthGame", {})
	if g.is_empty():
		_prog_lbl.text = "（冇行車睇緊）"
		_road_lbl.text = ""
		_hit_lbl.text = "喺外面撳「潛行」開始"
		return
	var pattern: Array = g["pattern"]
	var start := int(g["start"])
	var crossed := int(g.get("crossed", 0))
	var shown := mini(crossed + 1, RulesStealth.GAP_COUNT)
	_prog_lbl.text = "第 %d/%d 卡車之間（要穿晒 %d 卡先入潛行）" % [shown, RulesStealth.GAP_COUNT, RulesStealth.GAP_COUNT]
	var per := RulesStealth.CART_PERIOD
	var gw := RulesStealth.GAP_W
	var gap_idx := mini(crossed, RulesStealth.GAP_COUNT - 1)
	var off := int(pattern[gap_idx])
	var rel := ((now - start) % per + per) % per
	var chars: Array = []
	for i in per:
		chars.append("·" if (i >= off and i < off + gw) else "車")
	chars[mini(rel, per - 1)] = "▲"
	_road_lbl.text = "「" + "".join(chars) + "」"
	_hit_lbl.text = "宜家穿！" if (rel >= off and rel < off + gw) else "等空隙…"