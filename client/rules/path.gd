class_name RulesPath
extends RefCounted
# A* 4 方向尋路 (spec 12 §3)【自訂】。純函數 + 決定性: 同 f 先比 h，再比入隊次序。
# walk = 全域行得表 (1/0)，w = 全域闊。cell = y*w+x。
# avoid = 唔好經過嘅格 (例如 auto 傳送點)，終點除外。
# 回傳路徑 (唔包起點、包終點)；搵唔到 / 超過 max_nodes = []

const _SEQ_BITS := 20
const _H_BITS := 14


static func find(walk: PackedByteArray, w: int, from: int, to: int, max_nodes: int, avoid: Dictionary = {}) -> Array:
	if from == to or to < 0 or to >= walk.size() or walk[to] == 0:
		return []
	var tx := to % w
	var ty := to / w
	var g := {from: 0}
	var came := {}
	var closed := {}
	var heap_k := PackedInt64Array()
	var heap_c := PackedInt32Array()
	var seq := 0
	_push(heap_k, heap_c, _key(_h(from, w, tx, ty), _h(from, w, tx, ty), seq), from)
	var expanded := 0
	while heap_k.size() > 0:
		var cur := _pop(heap_k, heap_c)
		if closed.has(cur):
			continue
		if cur == to:
			var out: Array = []
			var c := cur
			while c != from:
				out.append(c)
				c = int(came[c])
			out.reverse()
			return out
		closed[cur] = true
		expanded += 1
		if expanded > max_nodes:
			return []
		var cx := cur % w
		var gc := int(g[cur]) + 1
		# 次序固定: 右 左 下 上
		for n in [cur + 1 if cx + 1 < w else -1, cur - 1 if cx > 0 else -1, cur + w, cur - w]:
			if n < 0 or n >= walk.size() or walk[n] == 0 or closed.has(n):
				continue
			if n != to and avoid.has(n):
				continue
			if g.has(n) and int(g[n]) <= gc:
				continue
			g[n] = gc
			came[n] = cur
			seq += 1
			var h := _h(n, w, tx, ty)
			_push(heap_k, heap_c, _key(gc + h, h, seq), n)
	return []


# 目的地行唔到 (圍封/太遠超 cap) → BFS 搵最近嘅行得到格，回路徑 (唔包起點)；原地最近 = []
# 用 max_nodes 限制擴展數；同樣 avoid 傳送點。決定性: 固定方向次序，同距先到先得。
static func reach_nearest(walk: PackedByteArray, w: int, from: int, to: int, max_nodes: int, avoid: Dictionary = {}) -> Array:
	var tx := to % w
	var ty := to / w
	var came := {from: -1}
	var q: Array = [from]
	var qi := 0
	var best := from
	var best_h := _h(from, w, tx, ty)
	while qi < q.size() and qi < max_nodes:
		var cur: int = q[qi]
		qi += 1
		var h := _h(cur, w, tx, ty)
		if h < best_h and not avoid.has(cur):
			best_h = h
			best = cur
		var cx := cur % w
		for n in [cur + 1 if cx + 1 < w else -1, cur - 1 if cx > 0 else -1, cur + w, cur - w]:
			if n < 0 or n >= walk.size() or walk[n] == 0 or came.has(n) or avoid.has(n):
				continue
			came[n] = cur
			q.append(n)
	var out: Array = []
	var c := best
	while c != from:
		out.append(c)
		c = int(came[c])
	out.reverse()
	return out


static func _h(c: int, w: int, tx: int, ty: int) -> int:
	return absi(c % w - tx) + absi(c / w - ty)


static func _key(f: int, h: int, seq: int) -> int:
	return (f << (_H_BITS + _SEQ_BITS)) | (mini(h, (1 << _H_BITS) - 1) << _SEQ_BITS) | mini(seq, (1 << _SEQ_BITS) - 1)


static func _push(hk: PackedInt64Array, hc: PackedInt32Array, k: int, c: int) -> void:
	hk.append(k)
	hc.append(c)
	var i := hk.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if hk[p] <= hk[i]:
			break
		var tk := hk[p]; hk[p] = hk[i]; hk[i] = tk
		var tc := hc[p]; hc[p] = hc[i]; hc[i] = tc
		i = p


static func _pop(hk: PackedInt64Array, hc: PackedInt32Array) -> int:
	var top := hc[0]
	var last := hk.size() - 1
	hk[0] = hk[last]
	hc[0] = hc[last]
	hk.resize(last)
	hc.resize(last)
	var i := 0
	var n := hk.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < n and hk[l] < hk[m]:
			m = l
		if r < n and hk[r] < hk[m]:
			m = r
		if m == i:
			break
		var tk := hk[m]; hk[m] = hk[i]; hk[i] = tk
		var tc := hc[m]; hc[m] = hc[i]; hc[i] = tc
		i = m
	return top
