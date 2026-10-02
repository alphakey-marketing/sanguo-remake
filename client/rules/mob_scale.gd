class_name RulesMobScale
extends RefCounted
# 怪物數值曲線 (data/mob_curve.json) + spawn 級別覆蓋縮放。純函數。

# 曲線 key: 0 hp, 1 atk, 2 def (anchors 內位置 1..3)；等級之間按對數內插，超出兩端沿用端點
static func curve(cv: Dictionary, lv: int, k: int) -> float:
	var a: Array = cv["anchors"]
	if lv <= int(a[0][0]):
		return maxf(float(a[0][k + 1]), 0.0)
	for i in range(1, a.size()):
		if lv <= int(a[i][0]):
			var l0 := float(a[i - 1][0])
			var l1 := float(a[i][0])
			var y0 := float(a[i - 1][k + 1])
			var y1 := float(a[i][k + 1])
			var t := (float(lv) - l0) / (l1 - l0)
			if y0 <= 0.0 or y1 <= 0.0:
				return y0 + (y1 - y0) * t      # def 有 0 值: 直線內插
			return exp(log(y0) + (log(y1) - log(y0)) * t)
	return float(a[a.size() - 1][k + 1])


# 殺同級怪升一級要幾多隻
static func kills(cv: Dictionary, lv: int) -> int:
	for p in cv["kills"]:
		if lv <= int(p[0]):
			return int(p[1])
	return int(cv["kills"][cv["kills"].size() - 1][1])


# 怪 exp = 升級需要 / kills
static func exp_at(cv: Dictionary, lv: int) -> int:
	return maxi(1, int(round(float(ExpTable.need(lv)) / float(kills(cv, lv)))))


# 將怪 def (基準等級 b.level) 縮放到 lv：hp/atk/def/exp 按曲線比例，gold 按等級比例
static func scaled(b: Dictionary, lv: int, cv: Dictionary) -> Dictionary:
	var d: Dictionary = b.duplicate(true)
	var l0 := maxi(1, int(b["level"]))
	d["level"] = lv
	d["hp"] = maxi(1, int(round(float(b["hp"]) * curve(cv, lv, 0) / maxf(curve(cv, l0, 0), 1.0))))
	d["atk"] = maxi(1, int(round(float(b["atk"]) * curve(cv, lv, 1) / maxf(curve(cv, l0, 1), 1.0))))
	d["def"] = int(round(float(b["def"]) * curve(cv, lv, 2) / maxf(curve(cv, l0, 2), 0.5)))
	d["exp"] = maxi(1, int(round(float(b["exp"]) * float(exp_at(cv, lv)) / float(exp_at(cv, l0)))))
	var g: Array = b.get("gold", [0, 0])
	d["gold"] = [int(g[0]), int(round(float(g[1]) * float(lv) / float(l0)))]
	return d
