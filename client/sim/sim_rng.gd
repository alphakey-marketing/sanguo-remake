class_name SimRng
extends RefCounted
# 種子 RNG (mulberry32)。狀態只有一個 32 位整數 → 可存檔、可重現

const M := 0xFFFFFFFF

var s: int = 0


func _init(seed_value: int = 1) -> void:
	s = seed_value & M


func next() -> float:
	s = (s + 0x6D2B79F5) & M
	var t := s
	t = ((t ^ (t >> 15)) * (t | 1)) & M
	t = (t ^ ((t + (((t ^ (t >> 7)) * (t | 61)) & M)) & M)) & M
	return float((t ^ (t >> 14)) & M) / 4294967296.0


# [0, n)
func below(n: int) -> int:
	return int(floor(next() * n))
