extends "res://sim/sim_comm.gd"
# Sim 繼承鏈: 驛站快速傳送 (Step 16.5, spec 12 §1 B3)【自訂】
# 驛站 = facilities.json 有 station:true 嘅設施；規則喺 rules/station.gd。唔使存檔狀態 (全部開放)


# 企喺邊個驛站隔籬 → facility key ("" = 唔喺)
func station_near(e: Dictionary) -> String:
	for k in RulesStation.keys(data.facilities):
		var f: Dictionary = data.facilities[k]
		if _near(e, int(f["x"]), int(f["y"])):
			return k
	return ""


func _station_hops(from_key: String, to_key: String) -> int:
	var a: Dictionary = data.facilities[from_key]
	var b: Dictionary = data.facilities[to_key]
	var ma := map_id_at(int(a["x"]), int(a["y"]))
	var mb := map_id_at(int(b["x"]), int(b["y"]))
	if _is_orig_map(ma) and _is_orig_map(mb):    # 兩站都喺原版世界: 外圍 25 連線已通，用真實過圖數
		return map_hops(ma, mb)
	var extra := 0                                # 一邊係原版、本城冇舊圖 (如陳留) = 經許昌: 真實過圖去許昌 + 舊圖由許昌起計
	var xa := _hop_map(int(a["x"]), int(a["y"]))
	var xb := _hop_map(int(b["x"]), int(b["y"]))
	if _is_orig_map(ma) and _city_map(String(data.map_by_id[ma].get("cityOf", ""))).is_empty():
		var h := map_hops(ma, "xuchang_o")
		if h < 0:
			return -1
		extra = h
		xa = "xuchang"
	elif _is_orig_map(mb) and _city_map(String(data.map_by_id[mb].get("cityOf", ""))).is_empty():
		var h2 := map_hops(mb, "xuchang_o")
		if h2 < 0:
			return -1
		extra = h2
		xb = "xuchang"
	var base := map_hops(xa, xb)
	return base + extra if base >= 0 else -1


func _is_orig_map(mid: String) -> bool:
	return data.map_by_id.get(mid, {}).has("orig")


# 驛站車費用嘅「地圖」: 原版圖 (cityOf) 借返所屬城嘅舊圖算過圖數，因為原版世界未連去其他城
func _hop_map(x: int, y: int) -> String:
	var mid := map_id_at(x, y)
	var md: Dictionary = data.map_by_id.get(mid, {})
	var c := String(md.get("cityOf", ""))
	if c != "":
		var cm := _city_map(c)
		if not cm.is_empty():
			return String(cm["id"])
	return mid


# 驛站面板視圖 (UI): 喺邊個驛站 + 其他驛站車費 (唔喺驛站 = from "")；S07c「玄妙」→ 唔喺驛站都用到
func station_view(id: int) -> Dictionary:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return {}
	var from := station_near(e)
	var remote := from == "" and _friend_effect_active(e, "station")
	var gold := int(e["ch"]["gold"])
	var cfg: Dictionary = data.world["station"]
	var list: Array = []
	for k in RulesStation.keys(data.facilities):
		if k == from:
			continue
		var hops := -1
		if from != "":
			hops = _station_hops(from, k)
		elif remote:
			var f: Dictionary = data.facilities[k]
			hops = map_hops(_hop_map(int(e["x"]), int(e["y"])), _hop_map(int(f["x"]), int(f["y"])))
		list.append({"key": k, "name": String(data.facilities[k]["name"]), "hops": hops,
			"fare": RulesStation.fare(hops, cfg) if hops >= 0 else 0,
			"why": RulesStation.check(from, k, data.facilities, hops, gold, cfg, remote)})
	return {"from": from, "remote": remote, "gold": gold, "list": list}


# 搭驛站去 to_key: 扣車費 → 即時去到目的驛站 (同伴一齊跟過去)；斷吟唱/自動尋路/攻擊目標
# S07c「玄妙」: 唔喺驛站但學咗效果 → remote 傳送 (車費由所在地圖起計)
func cmd_station(id: int, to_key: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var from := station_near(e)
	var remote := from == "" and _friend_effect_active(e, "station")
	var hops := -1
	if data.facilities.has(to_key):
		if from != "":
			hops = _station_hops(from, to_key)
		elif remote:
			var tt: Dictionary = data.facilities[to_key]
			hops = map_hops(_hop_map(int(e["x"]), int(e["y"])), _hop_map(int(tt["x"]), int(tt["y"])))
	var cfg: Dictionary = data.world["station"]
	var why := RulesStation.check(from, to_key, data.facilities, hops, int(ch["gold"]), cfg, remote)
	if why != "":
		return _msg(id, why)
	var fare := RulesStation.fare(hops, cfg)
	ch["gold"] = int(ch["gold"]) - fare
	var t: Dictionary = data.facilities[to_key]
	var p := _free_near(int(t["x"]), int(t["y"]))
	_put_ent(e, p.x, p.y)
	e["atk_target"] = 0
	e.erase("goto")
	if e.has("casting"):
		e.erase("casting")
		_emit({"k": "cast_interrupted", "dst": id, "reason": "travel"})
	var c := _companion_of(e)
	if not c.is_empty() and int(c["hp"]) > 0:
		var cp := _free_near(p.x, p.y)
		_put_ent(c, cp.x, cp.y)
		c["atk_target"] = 0
	_emit({"k": "travel", "dst": id, "to": String(t["name"]), "x": e["x"], "y": e["y"],
		"map": map_id_at(int(e["x"]), int(e["y"])), "station": true})
	_msg(id, "搭驛站馬車去到%s（車費 %d 金）" % [t["name"], fare])
