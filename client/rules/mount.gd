class_name RulesMount
extends RefCounted
# 座騎 (Step 17a, spec 07 §1~5): 純函數，數值喺 data/mounts.json (cfg)。
# 座騎 m = 純資料 Dictionary (存喺 ch.mounts):
#   {uid, breed, nick, sex, age, life, satiety, intimacy, mood, fatigue, attrs{learn,burst,run,endure,stamina},
#    grow, excel, points, status{}, acts{}, where("with"/"stable"/"graze"), stable, back, rideAcc}
# 隨機數由 caller 傳入 (SimRng)，呢度唔擲骰


static func breed_def(cfg: Dictionary, breed: String) -> Dictionary:
	for b in cfg["breeds"]:
		if String(b["id"]) == breed:
			return b
	return {}


# 新馬: 幼馬 = 基本 10、特長 20【自訂】；tamed = 馬廄已養大嘅成年馬 (直接成年 + 親密度夠騎)
static func new_mount(cfg: Dictionary, breed: String, uid: int, tamed: bool = false) -> Dictionary:
	var b := breed_def(cfg, breed)
	var st: Dictionary = cfg["start"]
	var attrs := {}
	for a in cfg["attrs"]:
		attrs[a] = int(cfg["attrTrait"]) if String(b.get("trait", "")) == String(a) else int(cfg["attrBase"])
	var m := {"uid": uid, "breed": breed, "nick": "", "sex": "f", "age": 0, "life": int(st["life"]),
		"satiety": int(st["satiety"]), "intimacy": int(st["intimacy"]), "mood": int(st["mood"]), "fatigue": 0,
		"attrs": attrs, "grow": 0, "excel": 0, "points": 0, "status": {}, "acts": {}, "where": "with", "stable": "", "back": 0, "rideAcc": 0,
		"bpts": 0, "totalBpts": 0, "caps": {}, "adv": false}
	if tamed:
		var tm: Dictionary = cfg["tamed"]
		m["age"] = int(cfg["foalDays"])
		m["intimacy"] = int(tm["intimacy"])
		for a in cfg["attrs"]:
			attrs[a] = int(tm["attr"])
	return m


# 襁褓期 foal (頭 foalDays 日) / 成熟期 adult / 衰老期 old (死前 oldDays 日)【原】
static func stage(cfg: Dictionary, m: Dictionary) -> String:
	var age := int(m["age"])
	if age < int(cfg["foalDays"]):
		return "foal"
	if age >= int(cfg["lifeDays"]) - int(cfg["oldDays"]):
		return "old"
	return "adult"


const STAGE_NAMES := {"foal": "襁褓期", "adult": "成熟期", "old": "衰老期"}


# 顯示名: 有暱稱用暱稱；幼馬 = 品種名，成年 = 成馬名【原】
static func display_name(cfg: Dictionary, m: Dictionary) -> String:
	if String(m.get("nick", "")) != "":
		return String(m["nick"])
	var b := breed_def(cfg, String(m["breed"]))
	if stage(cfg, m) == "foal":
		return String(b.get("name", "馬"))
	if bool(m.get("adv", false)):
		return String(b.get("advAdult", b.get("adult", "馬")))
	return String(b.get("adult", "馬"))


# 疲勞上限 = 基本 + 忍耐力【原=忍耐力決定上限】
static func fatigue_max(cfg: Dictionary, m: Dictionary) -> int:
	return int(cfg["fatigueBase"]) + int(m["attrs"]["endure"])


# 生命力上限 = 100 (進階馬 ×2【原】) + 優秀值 × levelLife (放牧成長會加)
static func life_max(cfg: Dictionary, m: Dictionary) -> int:
	var base := int(cfg["start"]["life"]) * (2 if bool(m.get("adv", false)) else 1)
	return base + int(m.get("excel", 0)) * int(cfg["graze"]["levelLife"])


# 屬性上限: 底 attrCap + 繁衍積點兌換嘅 cap 加成 + 進階馬額外上限【原】
static func attr_cap(cfg: Dictionary, m: Dictionary, attr: String) -> int:
	var bonus := int((m.get("caps", {}) as Dictionary).get(attr, 0))
	if bool(m.get("adv", false)):
		bonus += int(cfg["breed"].get("advCapBonus", 0))
	return int(cfg["attrCap"]) + bonus


static func mood_name(cfg: Dictionary, m: Dictionary) -> String:
	if (m["status"] as Dictionary).has("dizzy"):
		return "@_@"                                        # 頭暈【原】
	for row in cfg["moods"]:
		if int(m["mood"]) >= int(row[0]):
			return String(row[1])
	return String(cfg["moods"][-1][1])


static func status_names(cfg: Dictionary, m: Dictionary) -> Array:
	var out: Array = []
	for s in m["status"]:
		out.append(String(cfg["statuses"].get(s, {}).get("name", s)))
	return out


static func _status_flag(cfg: Dictionary, m: Dictionary, flag: String) -> String:
	for s in m["status"]:
		var sd: Dictionary = cfg["statuses"].get(s, {})
		if bool(sd.get(flag, false)):
			return String(sd["name"])
	return ""


# 騎得唔得: "" = 得【原=成熟期 + 親密度 >= 60】
static func ride_why(cfg: Dictionary, m: Dictionary) -> String:
	if String(m["where"]) != "with":
		return "座騎唔喺身邊"
	if stage(cfg, m) == "foal":
		return "襁褓期嘅小馬未騎得"
	if int(m["intimacy"]) < int(cfg["rideIntimacy"]):
		return "親密度要 %d 先騎得 (而家 %d)" % [int(cfg["rideIntimacy"]), int(m["intimacy"])]
	var st := _status_flag(cfg, m, "noRide")
	if st != "":
		return "座騎%s，騎唔到" % st
	return ""


# 飼養動作做得唔得 (唔計道具/行動力): "" = 得
static func act_why(cfg: Dictionary, m: Dictionary, act: String) -> String:
	var ad: Dictionary = cfg["acts"].get(act, {})
	if ad.is_empty():
		return "冇呢個動作"
	if String(m["where"]) != "with":
		return "座騎唔喺身邊"
	if act != "heal":
		var st := _status_flag(cfg, m, "noAct")
		if st != "":
			return "座騎%s，淨係醫得" % st
	var lim := int(ad.get("limit", 0))
	if lim > 0 and int(m["acts"].get(act, 0)) >= lim:
		return "今日%s已經做咗 %d 次" % [ad["name"], lim]
	return ""


static func acts_left(cfg: Dictionary, m: Dictionary, act: String) -> int:
	var lim := int(cfg["acts"][act].get("limit", 0))
	return -1 if lim <= 0 else maxi(0, lim - int(m["acts"].get(act, 0)))


# 原版 effect value 係 uint16: > 32767 = 負數
static func eff_value(v: int) -> int:
	return v - 65536 if v > 32767 else v


static func _clamp_attr(cfg: Dictionary, m: Dictionary, attr: String, v: int) -> int:
	return clampi(v, 0, attr_cap(cfg, m, attr))


# 加疲勞: 爆表 = 頭暈【原】；返 true = 啱啱頭暈
static func add_fatigue(cfg: Dictionary, m: Dictionary, n: int) -> bool:
	var fm := fatigue_max(cfg, m)
	m["fatigue"] = clampi(int(m["fatigue"]) + n, 0, fm)
	if n > 0 and int(m["fatigue"]) >= fm and not (m["status"] as Dictionary).has("dizzy"):
		m["status"]["dizzy"] = true
		return true
	return false


# 做一個飼養動作 (已 check 過 act_why + 道具)；effects = 道具 effects [{type,value}] (冇道具 = [])
# 屬性只喺襁褓期升【原=成熟期屬性停】；飽食/疲勞/情緒/生命力/治異常任何時候都有效
# 返 {"dizzy": bool, "changes": [文字]}
static func apply_act(cfg: Dictionary, m: Dictionary, act: String, effects: Array) -> Dictionary:
	var ad: Dictionary = cfg["acts"][act]
	var foal := stage(cfg, m) == "foal"
	var names: Dictionary = cfg["attrNames"]
	var changes: Array = []
	var fat := int(ad.get("fatigue", 0))
	var mood := int(ad.get("mood", 0))
	var deltas := {}
	var ad_attr: Dictionary = ad.get("attr", {})
	for a in ad_attr:
		deltas[a] = int(deltas.get(a, 0)) + int(ad_attr[a])
	var keys: Dictionary = cfg["effectKeys"]
	for e in effects:
		var k := String(keys.get(str(int(e["type"])), ""))
		var v := eff_value(int(e["value"]))
		if k == "":
			continue
		if k.begins_with("cure:"):
			var s := k.substr(5)
			if (m["status"] as Dictionary).has(s):
				m["status"].erase(s)
				changes.append("%s好返" % cfg["statuses"][s]["name"])
		elif k == "fatigue":
			fat += v
		elif k == "mood":
			mood += v
		elif k == "satiety":
			var s0 := int(m["satiety"])
			m["satiety"] = clampi(s0 + v, 0, 100)
			changes.append("飽食度 %+d" % (int(m["satiety"]) - s0))
		elif k == "life":
			var l0 := int(m["life"])
			m["life"] = clampi(l0 + v, 0, life_max(cfg, m))
			changes.append("生命力 %+d" % (int(m["life"]) - l0))
		else:
			deltas[k] = int(deltas.get(k, 0)) + v
	if foal:
		for a in cfg["attrs"]:
			if not deltas.has(a):
				continue
			var a0 := int(m["attrs"][a])
			m["attrs"][a] = _clamp_attr(cfg, m, a, a0 + int(deltas[a]))
			if int(m["attrs"][a]) != a0:
				changes.append("%s %+d" % [names[a], int(m["attrs"][a]) - a0])
	elif not deltas.is_empty():
		changes.append("(成年屬性唔再升)")
	if mood != 0:
		var m0 := int(m["mood"])
		m["mood"] = clampi(m0 + mood, 0, 100)
		changes.append("情緒 %+d" % (int(m["mood"]) - m0))
	var f0 := int(m["fatigue"])
	var dizzy := add_fatigue(cfg, m, fat)
	if int(m["fatigue"]) != f0:
		changes.append("疲勞 %+d" % (int(m["fatigue"]) - f0))
	m["acts"][act] = int(m["acts"].get(act, 0)) + 1
	return {"dizzy": dizzy, "changes": changes}


# 每日子時結算【原=情緒必降；情緒好加親密度；襁褓期要帶喺身邊；馬廄過子時疲勞/頭暈恢復；飽食 <50 疲勞唔降】
# plague = 寄喺有瘟疫嘅城【自訂=原版馬瘟全死，單機改做扣生命力】
# intimacy_mul = 親密度成長倍率 (S07d 武將特技「馴馬」)；只放大正成長，唔放大跌幅。預設 1.0 = 舊行為
# 返事件 Array: "grown" 啱啱成年 / "old" 入衰老期 / "dead" 死亡
static func daily(cfg: Dictionary, m: Dictionary, plague: bool, intimacy_mul: float = 1.0) -> Array:
	var d: Dictionary = cfg["daily"]
	var ev: Array = []
	var where := String(m["where"])
	var foal := stage(cfg, m) == "foal"
	# 親密度: 睇結算前嘅情緒
	if not (foal and where == "stable"):
		var dv := 0
		for row in d["intimacy"]:
			if int(m["mood"]) >= int(row[0]):
				dv = int(row[1])
				break
		if dv > 0 and intimacy_mul > 1.0:
			dv = MathX.js_round(float(dv) * intimacy_mul)
		m["intimacy"] = clampi(int(m["intimacy"]) + dv, 0, 100)
	# 情緒必降；肚餓/好攰再跌
	var mood := int(d["mood"])
	if int(m["satiety"]) < 50:
		mood += int(d["moodHungry"])
	if int(m["fatigue"]) >= int(fatigue_max(cfg, m) * float(d["tiredFrac"])):
		mood += int(d["moodTired"])
	m["mood"] = clampi(int(m["mood"]) + mood, 0, 100)
	# 疲勞: 馬廄 = 清零 + 頭暈好返；其他 = 飽食夠先回
	if where == "stable":
		m["fatigue"] = 0
		m["status"].erase("dizzy")
	elif int(m["satiety"]) >= 50:
		var rec := int(d["recoverBase"]) + int(float(m["attrs"]["stamina"]) * float(d["recoverPerStamina"]))
		m["fatigue"] = maxi(0, int(m["fatigue"]) - rec)
	m["satiety"] = clampi(int(m["satiety"]) + int(d["satiety"]), 0, 100)
	# 異常狀態 / 馬瘟扣生命力
	var loss := 0
	for s in m["status"]:
		loss += int(cfg["statuses"].get(s, {}).get("life", 0))
	if plague and where == "stable":
		loss += int(d["plagueLife"])
	m["life"] = maxi(0, int(m["life"]) - loss)
	m["acts"] = {}
	# 年歲
	var st0 := stage(cfg, m)
	m["age"] = int(m["age"]) + 1
	var st1 := stage(cfg, m)
	if st0 == "foal" and st1 != "foal":
		ev.append("grown")
	if st0 != "old" and st1 == "old":
		ev.append("old")
	if int(m["life"]) <= 0 or int(m["age"]) >= int(cfg["lifeDays"]):
		ev.append("dead")
	return ev


# ================= 騎乘 =================
# 移速倍數【原=+50%，奔跑力調】
static func ride_mult(cfg: Dictionary, m: Dictionary) -> float:
	return float(cfg["rideSpeed"]) + float(m["attrs"]["run"]) * float(cfg["runSpeed"])


# 呢個 tick 行幾多格: floor((t+1)×mult) − floor(t×mult)，冇狀態、可重現
static func steps_at(mult: float, t: int) -> int:
	return int(floor((t + 1) * mult)) - int(floor(t * mult))


# 每行幾多格加 1 疲勞 (體力高 = 捱得耐)
static func tiles_per_fatigue(cfg: Dictionary, m: Dictionary) -> int:
	return int(cfg["rideTiles"]) + int(float(m["attrs"]["stamina"]) * float(cfg["rideTilesPerStamina"]))


# 騎住行咗 n 格: 累積 → 加疲勞；返 true = 頭暈 (要落馬)
static func ride_tiles(cfg: Dictionary, m: Dictionary, n: int) -> bool:
	var per := tiles_per_fatigue(cfg, m)
	var acc := int(m.get("rideAcc", 0)) + n
	var add := acc / per
	m["rideAcc"] = acc % per
	return add > 0 and add_fatigue(cfg, m, add)


# ================= 放牧 =================
# 放牧得唔得: "" = 得 (成年、唔頭暈/骨折/昏迷)
static func graze_why(cfg: Dictionary, m: Dictionary) -> String:
	if String(m["where"]) != "with":
		return "座騎唔喺身邊"
	if stage(cfg, m) == "foal":
		return "襁褓期嘅小馬唔放得牧"
	var st := _status_flag(cfg, m, "noRide")
	if st != "":
		return "座騎%s，唔放得牧" % st
	return ""


# 結果機率 (爆發力愈高好結果愈多【原】): 返 {good, find, hurt}
static func graze_odds(cfg: Dictionary, m: Dictionary) -> Dictionary:
	var g: Dictionary = cfg["graze"]
	var b := float(m["attrs"]["burst"])
	var out := {}
	for k in ["good", "find", "hurt"]:
		var p: Array = g["p" + k.capitalize()]
		out[k] = clampf(float(p[0]) + float(p[1]) * b, 0.0, 1.0)
	return out


# 擲結果: r1 揀狀況、r2 揀嘢 (執嘢 = loot 權重；受傷 = hurtStatus)
# 返 {kind: none/good/find/hurt, item, status}
static func graze_roll(cfg: Dictionary, m: Dictionary, r1: float, r2: float) -> Dictionary:
	var o := graze_odds(cfg, m)
	var g: Dictionary = cfg["graze"]
	if r1 < float(o["good"]):
		return {"kind": "good"}
	if r1 < float(o["good"]) + float(o["find"]):
		var tot := 0
		for row in g["loot"]:
			tot += int(row[1])
		var pick := r2 * tot
		for row in g["loot"]:
			pick -= int(row[1])
			if pick < 0:
				return {"kind": "find", "item": int(row[0])}
		return {"kind": "find", "item": int(g["loot"][-1][0])}
	if r1 < float(o["good"]) + float(o["find"]) + float(o["hurt"]):
		var hs: Array = g["hurtStatus"]
		return {"kind": "hurt", "status": String(hs[mini(hs.size() - 1, int(r2 * hs.size()))])}
	return {"kind": "none"}


# 套用放牧結果 (執到嘅嘢由 caller 放入背包)；返 {"levels": 升咗幾多級優秀值}
static func graze_apply(cfg: Dictionary, m: Dictionary, res: Dictionary) -> Dictionary:
	var g: Dictionary = cfg["graze"]
	var kind := String(res["kind"])
	var levels := 0
	match kind:
		"good":
			# 成長值 × (1 + 學習力/100)【原=學習力 = 成年後成長速度】
			m["grow"] = int(m["grow"]) + int(float(g["grow"]) * (1.0 + float(m["attrs"]["learn"]) / 100.0))
			while int(m["grow"]) >= int(g["growNeed"]):
				m["grow"] = int(m["grow"]) - int(g["growNeed"])
				m["excel"] = int(m["excel"]) + 1
				m["points"] = int(m["points"]) + 1
				m["life"] = int(m["life"]) + int(g["levelLife"])
				levels += 1
		"hurt":
			m["life"] = maxi(0, int(m["life"]) - int(g["hurtLife"]))
			m["status"][String(res["status"])] = true
	add_fatigue(cfg, m, int(g["fatigue"].get(kind, 0)))
	return {"levels": levels}


# 優秀值點數分配: 1 點 = 屬性 +1 (上限 attrCapPoints)【原=每 +1 級 1 點分配 5 屬性】
static func point_why(cfg: Dictionary, m: Dictionary, attr: String) -> String:
	if not (cfg["attrs"] as Array).has(attr):
		return "冇呢個屬性"
	if int(m.get("points", 0)) <= 0:
		return "冇點數可以分配"
	if int(m["attrs"][attr]) >= int(cfg["attrCapPoints"]):
		return "%s已經到頂" % cfg["attrNames"][attr]
	return ""


static func spend_point(cfg: Dictionary, m: Dictionary, attr: String) -> bool:
	if point_why(cfg, m, attr) != "":
		return false
	m["points"] = int(m["points"]) - 1
	m["attrs"][attr] = int(m["attrs"][attr]) + 1
	return true


# ================= 繁衍 (Step 17b, spec 07 §6) =================
# 單機簡化【自訂】: 配種 = 馬廄「種馬借用」(caller 收 studPrice 金) + 揀種馬品種 sire
# 胎教小遊戲: 落注 5 選 1，估中攞返 betOdds[中嗰個] 積點；胎氣必 +1；100 胎氣可以接生
# 懶人胎教: 放咗 lazyDays 日自動生，積點封頂 lazyBpts

static func breed_why(cfg: Dictionary, m: Dictionary) -> String:
	if String(m["sex"]) != "f":
		return "唔係母馬，配唔到種"
	if stage(cfg, m) != "adult":
		return "要成熟期先配得種"
	if m.has("preg"):
		return "已經有咗身孕"
	return ""


static func breed_start(cfg: Dictionary, m: Dictionary, sire: String) -> void:
	var b: Dictionary = cfg["breed"]
	m["preg"] = {"sire": sire, "motive": int(b["motiveStart"]), "taiqi": 0, "bpts": 0, "lazy": false, "lazyDay": 0}


static func breed_ready(cfg: Dictionary, m: Dictionary) -> bool:
	if not m.has("preg"):
		return false
	return int(m["preg"]["taiqi"]) >= int(cfg["breed"]["taiqiNeed"])


static func breed_can_play(cfg: Dictionary, m: Dictionary) -> String:
	if not m.has("preg"):
		return "未配種"
	if breed_ready(cfg, m):
		return "胎氣夠喇，可以接生"
	if int(m["preg"]["motive"]) < int(cfg["breed"]["betCost"]):
		return "動力值唔夠，聽日先再嚟"
	return ""


# 擲跑馬燈: outcome 平均 5 揀 1；估中 (choice == outcome) 攞返 betOdds[outcome] 積點
static func breed_bet(cfg: Dictionary, choice: int, r: float) -> Dictionary:
	var b: Dictionary = cfg["breed"]
	var n: int = (b["bets"] as Array).size()
	var outcome := mini(n - 1, int(r * n))
	var win := choice == outcome
	var pts := int((b["betOdds"] as Array)[outcome]) if win else 0
	return {"win": win, "outcome": outcome, "points": pts}


# 落一次注: 扣動力、胎氣 +1、中咗加積點
static func breed_play(cfg: Dictionary, m: Dictionary, choice: int, r: float) -> Dictionary:
	var b: Dictionary = cfg["breed"]
	var preg: Dictionary = m["preg"]
	var res := breed_bet(cfg, choice, r)
	preg["motive"] = maxi(0, int(preg["motive"]) - int(b["betCost"]))
	preg["taiqi"] = int(preg["taiqi"]) + 1
	preg["bpts"] = int(preg["bpts"]) + int(res["points"])
	return res


# 每日子時: 動力值回復 (<50 時 +40，否則 +20)；懶人胎教到期自動填滿。返 "ready" = 啱啱夠胎氣
static func breed_daily(cfg: Dictionary, m: Dictionary) -> String:
	if not m.has("preg"):
		return ""
	var b: Dictionary = cfg["breed"]
	var preg: Dictionary = m["preg"]
	var was_ready := breed_ready(cfg, m)
	var gain := int(b["motiveGainLow"]) if int(preg["motive"]) < int(b["motiveLowThresh"]) else int(b["motiveGainHigh"])
	preg["motive"] = clampi(int(preg["motive"]) + gain, 0, int(b["motiveCap"]))
	if bool(preg.get("lazy", false)) and not was_ready:
		preg["lazyDay"] = int(preg.get("lazyDay", 0)) + 1
		if int(preg["lazyDay"]) >= int(b["lazyDays"]):
			preg["taiqi"] = int(b["taiqiNeed"])
			preg["bpts"] = int(b["lazyBpts"])
	return "ready" if (not was_ready and breed_ready(cfg, m)) else ""


# 接生: 品種 = 母血機率 damWeight : sire 血 sireWeight【原】；性別多數母【原】
static func breed_birth(cfg: Dictionary, m: Dictionary, r1: float, r2: float) -> Dictionary:
	var b: Dictionary = cfg["breed"]
	var dam := String(m["breed"])
	var sire := String(m["preg"]["sire"])
	var dw := float(b["damWeight"])
	var sw := float(b["sireWeight"])
	var pick := dam if r1 * (dw + sw) < dw else sire
	var sex := "m" if r2 < float(b["maleChance"]) else "f"
	var bpts := int(m["preg"]["bpts"])
	m.erase("preg")
	return {"breed": pick, "sex": sex, "bpts": bpts}


# 新小馬 (領走後正式加入 ch.mounts)：帶住接生嗰陣嘅積點，即刻 check 進階
static func new_foal(cfg: Dictionary, breed: String, uid: int, sex: String, bpts: int) -> Dictionary:
	var m := new_mount(cfg, breed, uid, false)
	m["sex"] = sex
	m["bpts"] = bpts
	m["totalBpts"] = bpts
	_check_advance(cfg, m)
	return m


static func _check_advance(cfg: Dictionary, m: Dictionary) -> void:
	if bool(m.get("adv", false)):
		return
	var adv_need := int(breed_def(cfg, String(m["breed"])).get("advNeed", 1 << 30))
	if int(m.get("totalBpts", 0)) >= adv_need:
		m["adv"] = true


# 積點分配: 照品種兌換錶，1 點換 1 個對應屬性上限【原=烏孫馬 3 點 → +1 爆發力上限】
static func spend_bpt_why(cfg: Dictionary, m: Dictionary, attr: String) -> String:
	if not (cfg["attrs"] as Array).has(attr):
		return "冇呢個屬性"
	var cost := int(breed_def(cfg, String(m["breed"])).get("exchange", {}).get(attr, 1))
	if int(m.get("bpts", 0)) < cost:
		return "積點唔夠 (要 %d)" % cost
	return ""


static func spend_bpt(cfg: Dictionary, m: Dictionary, attr: String) -> bool:
	if spend_bpt_why(cfg, m, attr) != "":
		return false
	var cost := int(breed_def(cfg, String(m["breed"])).get("exchange", {}).get(attr, 1))
	m["bpts"] = int(m["bpts"]) - cost
	var caps: Dictionary = m.get("caps", {})
	caps[attr] = int(caps.get(attr, 0)) + 1
	m["caps"] = caps
	return true
