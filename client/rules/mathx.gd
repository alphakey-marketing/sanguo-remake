class_name MathX
extends RefCounted
# 同 JS Math.round 一致 (.5 向上)；GDScript roundi 對負數 .5 係向外，會同 TS 版偏差

static func js_round(x: float) -> int:
	return int(floor(x + 0.5))


# rng: Callable 回傳 [0,1)；冇傳就用全域隨機
static func roll(rng: Callable) -> float:
	if rng.is_null():
		return randf()
	return float(rng.call())
