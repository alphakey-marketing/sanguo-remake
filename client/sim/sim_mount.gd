extends "res://sim/sim_station.gd"
# Sim 繼承鏈: 座騎 (Step 17a, spec 07 §1~5)
# 狀態喺 ch: mounts = [座騎 m] (最多 5 匹)、mountSeq = uid 計數、riding = 騎緊身邊嗰匹
# 身邊最多 1 匹 (where "with"/"graze")，其餘寄喺馬廄 (where "stable" + stable key)；規則喺 rules/mount.gd
# 馬廄 = facilities.json stable:true；用品經 cmd_buy (sim_econ._shop_for 認得馬廄)


func _mcfg() -> Dictionary:
	return data.mounts


func _mounts(ch: Dictionary) -> Array:
	if not ch.has("mounts"):
		ch["mounts"] = []
	return ch["mounts"]


func _mount_by_uid(ch: Dictionary, uid: int) -> Dictionary:
	for m in ch.get("mounts", []):
		if int(m["uid"]) == uid:
			return m
	return {}


# 身邊嗰匹 (放牧中都計，where "with"/"graze")
func mount_near_me(ch: Dictionary) -> Dictionary:
	for m in ch.get("mounts", []):
		if String(m["where"]) == "with" or String(m["where"]) == "graze":
			return m
	return {}


func is_riding(ch: Dictionary) -> bool:
	return bool(ch.get("riding", false))


# 企喺邊個馬廄隔籬 → facility key ("" = 唔喺)
func stable_near(e: Dictionary) -> String:
	for k in data.facilities:
		var f = data.facilities[k]
		if f is Dictionary and bool(f.get("stable", false)) and _near(e, int(f["x"]), int(f["y"])):
			return String(k)
	return ""


func _mname(m: Dictionary) -> String:
	return RulesMount.display_name(_mcfg(), m)


func _player_mount(id: int, uid: int) -> Array:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return []
	var m := _mount_by_uid(e["ch"], uid)
	if m.is_empty():
		_msg(id, "冇呢匹座騎")
		return []
	return [e, m]


# ---- 馬廄: 買馬 / 寄養 / 領馬 ----
# breed = 品種 id；tamed = 買已養大嘅成年馬 (tamed.breed 先有)
func cmd_mount_buy(id: int, breed: String, tamed: bool = false) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var cfg := _mcfg()
	var key := stable_near(e)
	if key == "":
		return _msg(id, "要去馬廄先買到馬")
	if RulesMount.breed_def(cfg, breed).is_empty() or (tamed and breed != String(cfg["tamed"]["breed"])):
		return _msg(id, "馬廄冇呢隻馬")
	var ch: Dictionary = e["ch"]
	var ms := _mounts(ch)
	if ms.size() >= int(cfg["maxOwned"]):
		return _msg(id, "最多養 %d 匹馬" % int(cfg["maxOwned"]))
	var price := int(cfg["tamed"]["price"]) if tamed else int(cfg["foalPrice"])
	if int(ch["gold"]) < price:
		return _msg(id, "買馬要 %d 金" % price)
	ch["gold"] = int(ch["gold"]) - price
	var uid := int(ch.get("mountSeq", 0)) + 1
	ch["mountSeq"] = uid
	var m := RulesMount.new_mount(cfg, breed, uid, tamed)
	if not mount_near_me(ch).is_empty():            # 身邊已經有 → 新馬寄喺呢度
		m["where"] = "stable"
		m["stable"] = key
	ms.append(m)
	_emit({"k": "mount", "dst": id, "act": "buy", "uid": uid})
	_msg(id, "買咗%s（%d 金）%s" % [_mname(m), price, "，寄咗喺%s" % data.facilities[key]["name"] if m["where"] == "stable" else "，跟住你"])


func cmd_mount_stable(id: int, uid: int) -> void:
	var r := _player_mount(id, uid)
	if r.is_empty():
		return
	var e: Dictionary = r[0]
	var m: Dictionary = r[1]
	var key := stable_near(e)
	if key == "":
		return _msg(id, "要去馬廄先寄得")
	if String(m["where"]) != "with":
		return _msg(id, "%s唔喺身邊" % _mname(m))
	_set_riding(e, false)
	m["where"] = "stable"
	m["stable"] = key
	_msg(id, "%s寄咗喺%s" % [_mname(m), data.facilities[key]["name"]])


# 領馬: 任何一間馬廄都領得 (馬廄互通【自訂】)；身邊有另一匹 = 自動寄低換
func cmd_mount_take(id: int, uid: int) -> void:
	var r := _player_mount(id, uid)
	if r.is_empty():
		return
	var e: Dictionary = r[0]
	var m: Dictionary = r[1]
	var key := stable_near(e)
	if key == "":
		return _msg(id, "要去馬廄先領得")
	if String(m["where"]) != "stable":
		return _msg(id, "%s冇寄喺馬廄" % _mname(m))
	var cur := mount_near_me(e["ch"])
	if not cur.is_empty():
		if String(cur["where"]) == "graze":
			return _msg(id, "%s放緊牧，召返先" % _mname(cur))
		_set_riding(e, false)
		cur["where"] = "stable"
		cur["stable"] = key
	m["where"] = "with"
	m["stable"] = ""
	_msg(id, "領咗%s出嚟" % _mname(m))


# ---- 飼養動作 ----
# act = feed/play/scold/gift/train/heal；item = 用嘅道具 (要道具嘅動作)
func cmd_mount_act(id: int, uid: int, act: String, item: int = 0) -> void:
	var r := _player_mount(id, uid)
	if r.is_empty():
		return
	var e: Dictionary = r[0]
	var m: Dictionary = r[1]
	var ch: Dictionary = e["ch"]
	var cfg := _mcfg()
	var why := RulesMount.act_why(cfg, m, act)
	if why != "":
		return _msg(id, why)
	var ad: Dictionary = cfg["acts"][act]
	var items: Array = ad.get("items", [])
	if not items.is_empty():
		if not (items.has(item) or items.has(float(item))):
			return _msg(id, "%s要用啱嘅道具" % ad["name"])
		if RulesShop.count_item(ch["bag"], item) <= 0:
			return _msg(id, "背包冇%s" % data.names.get(item, "呢件"))
	var ap := int(cfg["apCost"])
	if ap_of(ch) < ap:
		return _msg(id, "行動力唔夠 (要 %d)" % ap)
	ch["ap"] = ap_of(ch) - ap
	var effs: Array = []
	if not items.is_empty():
		RulesShop.remove_item(ch["bag"], item, 1)
		effs = data.info.get(item, {}).get("effects", [])
	var res := RulesMount.apply_act(cfg, m, act, effs)
	var what := String(ad["name"]) + ("（%s）" % data.names.get(item, "") if item > 0 and not items.is_empty() else "")
	_msg(id, "%s %s：%s" % [_mname(m), what, "、".join(res["changes"]) if not (res["changes"] as Array).is_empty() else "冇乜變化"])
	if bool(res["dizzy"]):
		_mount_dizzy(e, m)
	_emit({"k": "mount", "dst": id, "act": act, "uid": uid})


func _mount_dizzy(e: Dictionary, m: Dictionary) -> void:
	_set_riding(e, false)
	_msg(int(e["id"]), "%s攰到頭暈 (@_@)！寄喺馬廄過子時就好返" % _mname(m))


func cmd_mount_rename(id: int, uid: int, nick: String) -> void:
	var r := _player_mount(id, uid)
	if r.is_empty():
		return
	var m: Dictionary = r[1]
	m["nick"] = nick.strip_edges().substr(0, 8)
	_msg(id, "座騎改名做「%s」" % _mname(m))


# 丟棄荒野【原】: 刪除 (唔可以喺放牧中丟)
func cmd_mount_abandon(id: int, uid: int) -> void:
	var r := _player_mount(id, uid)
	if r.is_empty():
		return
	var e: Dictionary = r[0]
	var m: Dictionary = r[1]
	if String(m["where"]) == "graze":
		return _msg(id, "放緊牧，召返先")
	if String(m["where"]) == "with":
		_set_riding(e, false)
	var nm := _mname(m)
	_mounts(e["ch"]).erase(m)
	_msg(id, "你將%s放咗落荒野……" % nm)


func cmd_mount_point(id: int, uid: int, attr: String) -> void:
	var r := _player_mount(id, uid)
	if r.is_empty():
		return
	var m: Dictionary = r[1]
	var cfg := _mcfg()
	var why := RulesMount.point_why(cfg, m, attr)
	if why != "":
		return _msg(id, why)
	RulesMount.spend_point(cfg, m, attr)
	_msg(id, "%s %s +1（%d）" % [_mname(m), cfg["attrNames"][attr], int(m["attrs"][attr])])


# ---- 騎乘 ----
func cmd_mount_ride(id: int, on: bool) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	if not on:
		if is_riding(ch):
			_set_riding(e, false)
			_msg(id, "落馬")
		return
	var m := mount_near_me(ch)
	if m.is_empty():
		return _msg(id, "身邊冇座騎")
	var why := RulesMount.ride_why(_mcfg(), m)
	if why != "":
		return _msg(id, why)
	if e.has("casting"):
		e.erase("casting")
		_emit({"k": "cast_interrupted", "dst": id, "reason": "move"})
	_set_riding(e, true)
	_msg(id, "騎上%s（移速 ×%.2f）" % [_mname(m), RulesMount.ride_mult(_mcfg(), m)])


func _set_riding(e: Dictionary, on: bool) -> void:
	var ch: Dictionary = e["ch"]
	if is_riding(ch) == on:
		return
	ch["riding"] = on
	_emit({"k": "mount", "dst": int(e["id"]), "act": "ride" if on else "dismount"})


func _mount_drop(e: Dictionary, why: String) -> void:
	if not e.has("ch") or not is_riding(e["ch"]):
		return
	_set_riding(e, false)
	if why == "attack":
		_msg(int(e["id"]), "騎馬用唔到一般武器，落馬作戰")


# 呢個 tick 行幾多格: 騎緊 = 按移速倍數 (step() 叫)
func _ride_steps(e: Dictionary) -> int:
	if not e.has("ch") or not is_riding(e["ch"]):
		return 1
	var m := mount_near_me(e["ch"])
	if m.is_empty():
		return 1
	return RulesMount.steps_at(RulesMount.ride_mult(_mcfg(), m), tick)


# 騎住行咗 n 格 → 座騎疲勞；頭暈 = 落馬
func _ride_moved(e: Dictionary, n: int) -> void:
	if n <= 0 or not e.has("ch") or not is_riding(e["ch"]):
		return
	var m := mount_near_me(e["ch"])
	if m.is_empty():
		return
	if RulesMount.ride_tiles(_mcfg(), m, n):
		_mount_dizzy(e, m)


# ---- 放牧【原=馴馬專用哨；一個時辰；再吹 = 緊急召回】 ----
func cmd_mount_graze(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var cfg := _mcfg()
	if RulesShop.count_item(ch["bag"], int(cfg["whistle"])) <= 0:
		return _msg(id, "要有%s先放得牧" % data.names.get(int(cfg["whistle"]), "馴馬專用哨"))
	var m := mount_near_me(ch)
	if m.is_empty():
		return _msg(id, "身邊冇座騎")
	if String(m["where"]) == "graze":          # 緊急召回: 冇成果、少少疲勞
		m["where"] = "with"
		RulesMount.add_fatigue(cfg, m, int(cfg["graze"]["fatigue"]["recall"]))
		return _msg(id, "吹哨召回%s" % _mname(m))
	var why := RulesMount.graze_why(cfg, m)
	if why != "":
		return _msg(id, why)
	_set_riding(e, false)
	m["where"] = "graze"
	m["back"] = tick + int(cfg["grazeTicks"])
	_msg(id, "吹哨放%s出去放牧（一個時辰後返）" % _mname(m))


# 每 tick: 放牧到鐘 → 擲結果 (step() 叫)
func _mount_tick() -> void:
	var cfg := _mcfg()
	for e in ents.values():
		if not e.has("ch"):
			continue
		for m in e["ch"].get("mounts", []):
			if String(m["where"]) == "graze" and tick >= int(m["back"]):
				_graze_return(e, m, cfg)


func _graze_return(e: Dictionary, m: Dictionary, cfg: Dictionary) -> void:
	var id := int(e["id"])
	var res := RulesMount.graze_roll(cfg, m, rng.next(), rng.next())
	m["where"] = "with"
	var out := RulesMount.graze_apply(cfg, m, res)
	var nm := _mname(m)
	match String(res["kind"]):
		"good":
			var lv := int(out["levels"])
			_msg(id, "%s放牧返嚟，成長咗！%s" % [nm, "優秀值 +%d（有點數可以分配）" % lv if lv > 0 else "成長值 %d/%d" % [int(m["grow"]), int(cfg["graze"]["growNeed"])]])
		"find":
			var it := int(res["item"])
			RulesShop.add_item(e["ch"]["bag"], it, 1)
			_msg(id, "%s放牧返嚟，咬住%s返嚟！" % [nm, data.names.get(it, "?")])
		"hurt":
			_msg(id, "%s放牧返嚟受咗傷（%s，生命力 −%d）" % [nm, cfg["statuses"][res["status"]]["name"], int(cfg["graze"]["hurtLife"])])
		_:
			_msg(id, "%s放牧返嚟，無事發生" % nm)
	if (m["status"] as Dictionary).has("dizzy"):
		_msg(id, "%s攰到頭暈 (@_@)" % nm)
	_emit({"k": "mount", "dst": id, "act": "graze_back", "uid": int(m["uid"]), "res": String(res["kind"])})


# ---- 每日子時 ----
func _mount_daily(_day: int) -> void:
	var cfg := _mcfg()
	for e in ents.values():
		if not e.has("ch") or (e["ch"].get("mounts", []) as Array).is_empty():
			continue
		var id := int(e["id"])
		var ms: Array = e["ch"]["mounts"]
		for m in ms.duplicate():
			var ev := RulesMount.daily(cfg, m, _stable_plague(m))
			var nm := _mname(m)
			if ev.has("dead"):
				if String(m["where"]) != "stable":
					_set_riding(e, false)
				ms.erase(m)
				_emit({"k": "mount", "dst": id, "act": "dead", "uid": int(m["uid"])})
				_msg(id, "獸醫來信：%s已經離開咗你……" % nm)
				continue
			if ev.has("grown"):
				_msg(id, "%s長大咗，入成熟期！屬性定型，親密度夠就騎得" % nm)
			if ev.has("old"):
				_msg(id, "%s入咗衰老期，大約仲有 %d 日壽命" % [nm, int(cfg["oldDays"])])
			if is_riding(e["ch"]) and String(m["where"]) == "with" and RulesMount.ride_why(cfg, m) != "":
				_set_riding(e, false)


# 寄喺有瘟疫嘅城嘅馬廄 (馬瘟)【自訂】
func _stable_plague(m: Dictionary) -> bool:
	if String(m["where"]) != "stable":
		return false
	var city := String(data.facilities.get(String(m["stable"]), {}).get("city", ""))
	for d in state["disasters"]:
		if String(d["city"]) == city and String(d.get("id", "")) == "plague":
			return true
	return false


# ---- UI 讀取 ----
# 座騎清單 (UI): 每匹加埋計好嘅顯示欄
func mount_view(id: int) -> Dictionary:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return {}
	var ch: Dictionary = e["ch"]
	var cfg := _mcfg()
	var list: Array = []
	for m in ch.get("mounts", []):
		var acts := {}
		for a in cfg["acts"]:
			acts[a] = {"left": RulesMount.acts_left(cfg, m, a), "why": RulesMount.act_why(cfg, m, a)}
		var st := RulesMount.stage(cfg, m)
		list.append({"uid": int(m["uid"]), "name": _mname(m), "breed": String(RulesMount.breed_def(cfg, String(m["breed"]))["name"]),
			"stage": st, "stageName": RulesMount.STAGE_NAMES[st], "age": int(m["age"]), "where": String(m["where"]),
			"stableName": String(data.facilities.get(String(m["stable"]), {}).get("name", "")),
			"life": int(m["life"]), "lifeMax": RulesMount.life_max(cfg, m), "satiety": int(m["satiety"]),
			"intimacy": int(m["intimacy"]), "mood": int(m["mood"]), "moodName": RulesMount.mood_name(cfg, m),
			"fatigue": int(m["fatigue"]), "fatigueMax": RulesMount.fatigue_max(cfg, m), "attrs": (m["attrs"] as Dictionary).duplicate(),
			"excel": int(m["excel"]), "grow": int(m["grow"]), "points": int(m["points"]),
			"status": RulesMount.status_names(cfg, m), "acts": acts,
			"rideWhy": RulesMount.ride_why(cfg, m), "grazeWhy": RulesMount.graze_why(cfg, m),
			"grazeLeft": maxi(0, int(m["back"]) - tick) if String(m["where"]) == "graze" else 0,
			"speed": RulesMount.ride_mult(cfg, m)})
	return {"list": list, "riding": is_riding(ch), "stable": stable_near(e), "gold": int(ch["gold"]),
		"ap": ap_of(ch), "hasWhistle": RulesShop.count_item(ch["bag"], int(cfg["whistle"])) > 0}
