class_name WorldPrepLib
extends RefCounted
## Shared helpers for tools/prepare_world.gd: merge MeshInstance3D surfaces into vertex-coloured groups, decimate, save.

class Group:
	var name: String
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()

	func add(arr: Array, xf: Transform3D, color: Color) -> void:
		var base: int = v.size()
		var b: Basis = xf.basis.inverse().transposed()
		var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var sn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var suv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		for k in range(sv.size()):
			v.append(xf * sv[k])
			n.append((b * sn[k]).normalized() if sn.size() == sv.size() else Vector3.UP)
			uv.append(suv[k] if suv.size() == sv.size() else Vector2.ZERO)
			col.append(color)
		var si: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if si.is_empty():
			for i in range(sv.size()):
				si.append(i)
		for i in si:
			idx.append(base + i)

	func tris() -> int:
		return idx.size() / 3

	func aabb() -> AABB:
		var bb := AABB()
		for i in range(v.size()):
			if i == 0:
				bb = AABB(v[0], Vector3.ZERO)
			else:
				bb = bb.expand(v[i])
		return bb

static func world_xf(n: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != root:
		if c is Node3D:
			xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf

static func base_color(m: Material) -> Color:
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_color
	return Color(0.6, 0.6, 0.6)

static func load_scene(path: String) -> Node:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(path, st) != OK:
		return null
	return doc.generate_scene(st)

static func decimate(g: Group, target_tris: int) -> void:
	for _p in range(6):
		if g.tris() <= target_tris or g.tris() < 40:
			return
		if not _decimate_once(g, target_tris):
			return

static func _decimate_once(g: Group, target_tris: int) -> bool:
	var before: int = g.idx.size()
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = g.v
	arr[Mesh.ARRAY_NORMAL] = g.n
	arr[Mesh.ARRAY_TEX_UV] = g.uv
	arr[Mesh.ARRAY_COLOR] = g.col
	arr[Mesh.ARRAY_INDEX] = g.idx
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr)
	im.generate_lods(60.0, 25.0, [])
	var best: int = -1
	var lods: int = im.get_surface_lod_count(0)
	# choose the LOD whose triangle count is closest to the target (but not below 55% of it)
	var best_d: float = INF
	for l in range(lods):
		var sz: int = im.get_surface_lod_indices(0, l).size()
		if sz < int(target_tris * 3 * 0.55):
			continue
		var d: float = absf(log(float(sz) / float(target_tris * 3)))
		if d < best_d:
			best_d = d
			best = l
	if best < 0:
		return false
	var ni: PackedInt32Array = im.get_surface_lod_indices(0, best)
	if ni.size() >= before * 0.97:
		return false
	var remap := {}
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	var nuv := PackedVector2Array()
	var nc := PackedColorArray()
	var nidx := PackedInt32Array()
	for i in ni:
		if not remap.has(i):
			remap[i] = nv.size()
			nv.append(g.v[i]); nn.append(g.n[i]); nuv.append(g.uv[i]); nc.append(g.col[i])
		nidx.append(remap[i])
	g.v = nv; g.n = nn; g.uv = nuv; g.col = nc; g.idx = nidx
	return true

static func to_mesh(g: Group, use_col: bool = true, use_uv: bool = false) -> ArrayMesh:
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = g.v
	arr[Mesh.ARRAY_NORMAL] = g.n
	if use_uv:
		arr[Mesh.ARRAY_TEX_UV] = g.uv
	if use_col:
		arr[Mesh.ARRAY_COLOR] = g.col
	arr[Mesh.ARRAY_INDEX] = g.idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am

## split a Group into connected components (vertices welded by position); returns Array[Group]
static func components(g: Group) -> Array:
	var weld := {}
	var vid := PackedInt32Array()
	vid.resize(g.v.size())
	for i in range(g.v.size()):
		var k := Vector3i((g.v[i] * 1000.0).round())
		if not weld.has(k):
			weld[k] = weld.size()
		vid[i] = weld[k]
	var parent := PackedInt32Array()
	parent.resize(weld.size())
	for i in range(parent.size()):
		parent[i] = i
	var find := func(a: int) -> int:
		while parent[a] != a:
			parent[a] = parent[parent[a]]
			a = parent[a]
		return a
	for t in range(g.idx.size() / 3):
		var a: int = find.call(vid[g.idx[t * 3]])
		var b: int = find.call(vid[g.idx[t * 3 + 1]])
		var c: int = find.call(vid[g.idx[t * 3 + 2]])
		parent[b] = a
		parent[find.call(c)] = a
	var groups := {}
	for t in range(g.idx.size() / 3):
		var r: int = find.call(vid[g.idx[t * 3]])
		if not groups.has(r):
			groups[r] = Group.new()
		var gg: Group = groups[r]
		for q in range(3):
			var i: int = g.idx[t * 3 + q]
			gg.idx.append(gg.v.size())
			gg.v.append(g.v[i]); gg.n.append(g.n[i]); gg.uv.append(g.uv[i]); gg.col.append(g.col[i])
	return groups.values()
