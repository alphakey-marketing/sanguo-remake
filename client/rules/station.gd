class_name RulesStation
extends RefCounted
# 驛站快速傳送 (Step 16.5, spec 12 §1 B3)【自訂】: 城池驛站之間收費傳送，一開始全部開放。
# 車費 = base + perHop × 過圖次數 (兩個驛站所在地圖之間最少過幾多次圖)。數值喺 world.json station


static func fare(hops: int, cfg: Dictionary) -> int:
	return int(cfg["base"]) + int(cfg["perHop"]) * maxi(0, hops)


# facilities.json 入面 station:true 嘅 key (保持檔案順序 = UI 列表順序)
static func keys(facilities: Dictionary) -> Array:
	var out: Array = []
	for k in facilities:
		var f = facilities[k]
		if f is Dictionary and bool(f.get("station", false)):
			out.append(String(k))
	return out


# 傳送得唔得: "" = 得；否則係原因。remote = 戰騎「玄妙」效果（唔喺驛站都用到驛站介面）
static func check(from_key: String, to_key: String, facilities: Dictionary, hops: int, gold: int, cfg: Dictionary, remote: bool = false) -> String:
	if from_key == "" and not remote:
		return "要去驛站先得"
	var t = facilities.get(to_key, {})
	if not (t is Dictionary) or not bool(t.get("station", false)):
		return "冇呢個驛站"
	if to_key == from_key:
		return "你已經喺呢個驛站"
	if hops < 0:
		return "去唔到%s" % t["name"]
	var f := fare(hops, cfg)
	if gold < f:
		return "車費要 %d 金，唔夠錢" % f
	return ""
