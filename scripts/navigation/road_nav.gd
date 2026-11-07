class_name RoadNav
extends RefCounted
## A* routing over the road graph. Produces drivable polylines for the player's
## GPS, race opponents and police.

var w: WorldGen
var astar := AStar3D.new()
var pair_edge: Dictionary = {}

func _init(world: WorldGen) -> void:
	w = world
	for i in w.nodes.size():
		astar.add_point(i, w.nodes[i])
	for ei in w.edges.size():
		var e: Dictionary = w.edges[ei]
		var a: int = e["a"]
		var b: int = e["b"]
		var kind: String = e["kind"]
		var speed: float = float(e["limit"])
		var cost: float = float(e["len"]) / maxf(speed, 5.0) * 10.0
		if kind == "dirt":
			cost *= 1.6
		var k1: int = a * 10000 + b
		var k2: int = b * 10000 + a
		if pair_edge.has(k1) and float(w.edges[pair_edge[k1]]["len"]) <= float(e["len"]):
			continue
		pair_edge[k1] = ei
		pair_edge[k2] = ei
		if not astar.are_points_connected(a, b):
			astar.connect_points(a, b, true)
		astar.set_point_weight_scale(a, 1.0)
		# AStar3D uses euclidean cost by default; scale weights through _compute_cost not available, so
		# long slow roads are penalised by weight scale of the destination point
	for i in w.nodes.size():
		pass

func edge_polyline(ei: int, from_node: int) -> PackedVector3Array:
	var e: Dictionary = w.edges[ei]
	var pts: PackedVector3Array = e["pts"]
	if int(e["a"]) == from_node:
		return pts
	var r := PackedVector3Array()
	for i in range(pts.size() - 1, -1, -1):
		r.append(pts[i])
	return r

func _slice(ei: int, idx: int, to_node: int) -> PackedVector3Array:
	## points from sample idx to the given end node of edge ei
	var e: Dictionary = w.edges[ei]
	var pts: PackedVector3Array = e["pts"]
	var r := PackedVector3Array()
	if int(e["b"]) == to_node:
		for i in range(idx, pts.size()):
			r.append(pts[i])
	else:
		for i in range(idx, -1, -1):
			r.append(pts[i])
	return r

func _len(p: PackedVector3Array) -> float:
	var l: float = 0.0
	for i in range(1, p.size()):
		l += p[i].distance_to(p[i - 1])
	return l

func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var s: Dictionary = w.nearest_road(from, 600.0)
	var d: Dictionary = w.nearest_road(to, 600.0)
	if s.is_empty() or d.is_empty():
		return PackedVector3Array()
	var se: int = s["edge"]
	var de: int = d["edge"]
	var out := PackedVector3Array()
	if se == de:
		var pts: PackedVector3Array = w.edges[se]["pts"]
		var i0: int = s["idx"]
		var i1: int = d["idx"]
		if i0 <= i1:
			for i in range(i0, i1 + 1):
				out.append(pts[i])
		else:
			for i in range(i0, i1 - 1, -1):
				out.append(pts[i])
		return out
	var best_cost: float = INF
	var best: PackedVector3Array
	var s_nodes: Array = [int(w.edges[se]["a"]), int(w.edges[se]["b"])]
	var d_nodes: Array = [int(w.edges[de]["a"]), int(w.edges[de]["b"])]
	for sn in s_nodes:
		var part_a: PackedVector3Array = _slice(se, s["idx"], sn)
		for dn in d_nodes:
			var part_c: PackedVector3Array = _slice(de, d["idx"], dn)
			part_c.reverse()
			var ids: PackedInt64Array = astar.get_id_path(sn, dn)
			if ids.size() == 0:
				continue
			var mid := PackedVector3Array()
			var cur: int = sn
			for k in range(1, ids.size()):
				var nxt: int = ids[k]
				var ei: int = pair_edge.get(cur * 10000 + nxt, -1)
				if ei < 0:
					continue
				var poly: PackedVector3Array = edge_polyline(ei, cur)
				for q in range(1 if mid.size() > 0 else 0, poly.size()):
					mid.append(poly[q])
				cur = nxt
			var total: PackedVector3Array = PackedVector3Array()
			total.append_array(part_a)
			total.append_array(mid)
			total.append_array(part_c)
			var cost: float = _len(total)
			if cost < best_cost:
				best_cost = cost
				best = total
	return best if best_cost < INF else out

## Returns cumulative lengths for a polyline
static func cumulative(p: PackedVector3Array) -> PackedFloat32Array:
	var c := PackedFloat32Array()
	var l: float = 0.0
	for i in range(p.size()):
		if i > 0:
			l += Vector2(p[i].x - p[i - 1].x, p[i].z - p[i - 1].z).length()
		c.append(l)
	return c

## Simplifies a polyline so the UI can draw it cheaply
static func decimate(p: PackedVector3Array, step: float) -> PackedVector3Array:
	var r := PackedVector3Array()
	if p.size() == 0:
		return r
	r.append(p[0])
	var acc: float = 0.0
	for i in range(1, p.size()):
		acc += p[i].distance_to(p[i - 1])
		if acc >= step or i == p.size() - 1:
			r.append(p[i])
			acc = 0.0
	return r
