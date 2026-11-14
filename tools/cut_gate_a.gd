extends SceneTree
## One-off: opens a drive-through entrance in the Riverside Raceway (Track 1) pit-building facade that faced Speedway Road.
## The facade is a 2 m thick west wall (x -96..-95) + a closed pocket + an east wall with a door frame; the arch posts stand at
## z -75.9..-75.2 and z -67.4..-66.5.  Everything inside the window below the lintel is cut out (triangles are CLIPPED against the window,
## not dropped, so the wall either side stays intact); floors are kept, and the 0.3-0.5 m door sill / step on the far side is levelled.
## Applied to the visual mesh and the collision shape alike (track-local coordinates, y 0 = driving surface).
const X0 := -97.5
const X1 := -86.6
const Z0 := -75.2
const Z1 := -67.4
const YT := 5.0          # clear height of the opening (lintel and everything above stays)
# The facade stands on a 0.31-0.34 m plinth (pocket floor 0.31, paddock platform 0.34) whose vertical edge is a step no car or kart can climb.
# Inside the opening the plinth floor is turned into a ramp rising from the road level at RAMP_X0 to its full height at RAMP_X1.
const RAMP_X0 := -95.0
const RAMP_X1 := -89.0
const ROAD_Y := -0.01

# vertex = PackedFloat32Array [x y z nx ny nz r g b a]
func _lerp(a: PackedFloat32Array, b: PackedFloat32Array, t: float) -> PackedFloat32Array:
	var o := PackedFloat32Array()
	o.resize(a.size())
	for i in range(a.size()):
		o[i] = lerpf(a[i], b[i], t)
	return o

## split a convex polygon by plane coord[axis] = val -> [low, high]
func _split(poly: Array, axis: int, val: float) -> Array:
	var low: Array = []
	var high: Array = []
	var n: int = poly.size()
	for i in range(n):
		var a: PackedFloat32Array = poly[i]
		var b: PackedFloat32Array = poly[(i + 1) % n]
		var da: float = a[axis] - val
		var db: float = b[axis] - val
		if da <= 0.0:
			low.append(a)
		if da >= 0.0:
			high.append(a)
		if (da < 0.0 and db > 0.0) or (da > 0.0 and db < 0.0):
			var t: float = da / (da - db)
			var m: PackedFloat32Array = _lerp(a, b, t)
			low.append(m)
			high.append(m)
	return [low, high]

func _area_ok(poly: Array) -> bool:
	if poly.size() < 3:
		return false
	var s := Vector3.ZERO
	var p0 := Vector3(poly[0][0], poly[0][1], poly[0][2])
	for i in range(1, poly.size() - 1):
		var p1 := Vector3(poly[i][0], poly[i][1], poly[i][2])
		var p2 := Vector3(poly[i + 1][0], poly[i + 1][1], poly[i + 1][2])
		s += (p1 - p0).cross(p2 - p0)
	return s.length() > 1e-6

## triangle minus the window box; returns the polygons that remain
func _cut(tri: Array) -> Array:
	var ymin := minf(tri[0][1], minf(tri[1][1], tri[2][1]))
	var ymax := maxf(tri[0][1], maxf(tri[1][1], tri[2][1]))
	var xmin := minf(tri[0][0], minf(tri[1][0], tri[2][0]))
	var xmax := maxf(tri[0][0], maxf(tri[1][0], tri[2][0]))
	var zmin := minf(tri[0][2], minf(tri[1][2], tri[2][2]))
	var zmax := maxf(tri[0][2], maxf(tri[1][2], tri[2][2]))
	if xmax <= X0 or xmin >= X1 or zmax <= Z0 or zmin >= Z1 or ymin >= YT:
		return [tri]
	var p0 := Vector3(tri[0][0], tri[0][1], tri[0][2])
	var p1 := Vector3(tri[1][0], tri[1][1], tri[1][2])
	var p2 := Vector3(tri[2][0], tri[2][1], tri[2][2])
	var nrm: Vector3 = (p1 - p0).cross(p2 - p0).normalized()
	if absf(nrm.y) > 0.8 and ymax < 0.7:
		if ymin > 0.2 and xmax > RAMP_X0 and xmin < RAMP_X1 and zmax > Z0 and zmin < Z1:
			return _ramp(tri)
		return [tri]       # floor: keep
	var keep: Array = []
	var rem: Array = [tri]
	for ax in [[0, X0, X1], [2, Z0, Z1]]:
		var nxt: Array = []
		for poly in rem:
			var s1: Array = _split(poly, ax[0], ax[1])
			keep.append(s1[0])
			var s2: Array = _split(s1[1], ax[0], ax[2])
			keep.append(s2[1])
			nxt.append(s2[0])
		rem = nxt
	for poly in rem:
		var sy: Array = _split(poly, 1, YT)
		keep.append(sy[1])           # above the lintel line stays, below is the opening
	var out: Array = []
	for poly in keep:
		if _area_ok(poly):
			out.append(poly)
	return out

## plinth floor triangle: the part inside the opening (z Z0..Z1, x RAMP_X0..RAMP_X1) becomes a ramp, the rest is untouched
func _ramp(tri: Array) -> Array:
	var out: Array = []
	var rem: Array = [tri]
	var mid: Array = [tri]
	out.clear()
	# z band
	var inz: Array = []
	var s1: Array = _split(tri, 2, Z0)
	out.append(s1[0])
	var s2: Array = _split(s1[1], 2, Z1)
	out.append(s2[1])
	inz = s2[0]
	# x band inside the z band
	var s3: Array = _split(inz, 0, RAMP_X0)
	out.append(s3[0])
	var s4: Array = _split(s3[1], 0, RAMP_X1)
	out.append(s4[1])
	var ramp_poly: Array = s4[0]
	var rp: Array = []
	for vtx in ramp_poly:
		var w: PackedFloat32Array = (vtx as PackedFloat32Array).duplicate()
		var t: float = clampf((w[0] - RAMP_X0) / (RAMP_X1 - RAMP_X0), 0.0, 1.0)
		w[1] = lerpf(ROAD_Y, w[1], t)
		rp.append(w)
	out.append(rp)
	var res: Array = []
	for poly in out:
		if _area_ok(poly):
			res.append(poly)
	return res

func _level(v: Vector3) -> Vector3:
	return v

func _init() -> void:
	# ---------------- visual mesh
	var m: ArrayMesh = load("res://assets/tracks/track_a.res")
	var a: Array = m.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var col: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var oc := PackedColorArray()
	var cut_n := 0
	for i in range(0, idx.size(), 3):
		var tri: Array = []
		for k in range(3):
			var j: int = idx[i + k]
			var c: Color = col[j] if col.size() > j else Color.WHITE
			tri.append(PackedFloat32Array([v[j].x, v[j].y, v[j].z, nrm[j].x, nrm[j].y, nrm[j].z, c.r, c.g, c.b, c.a]))
		var polys: Array = _cut(tri)
		if polys.size() != 1 or polys[0] != tri:
			cut_n += 1
		for poly in polys:
			for q in range(1, poly.size() - 1):
				for e in [poly[0], poly[q], poly[q + 1]]:
					var pe: PackedFloat32Array = e
					ov.append(_level(Vector3(pe[0], pe[1], pe[2])))
					on.append(Vector3(pe[3], pe[4], pe[5]).normalized())
					oc.append(Color(pe[6], pe[7], pe[8], pe[9]))
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = ov
	arr[Mesh.ARRAY_NORMAL] = on
	arr[Mesh.ARRAY_COLOR] = oc
	var nm := ArrayMesh.new()
	nm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	nm.surface_set_material(0, m.surface_get_material(0))
	ResourceSaver.save(nm, "res://assets/tracks/track_a.res")
	print("GATE mesh: tris ", idx.size() / 3, " -> ", ov.size() / 3, " (cut ", cut_n, ")")
	# ---------------- collision
	var sh: ConcavePolygonShape3D = load("res://assets/tracks/track_a_col.res")
	var f: PackedVector3Array = sh.get_faces()
	var of := PackedVector3Array()
	var cut_c := 0
	for i in range(0, f.size(), 3):
		var tri2: Array = []
		for k in range(3):
			tri2.append(PackedFloat32Array([f[i + k].x, f[i + k].y, f[i + k].z, 0, 0, 0, 0, 0, 0, 0]))
		var polys2: Array = _cut(tri2)
		if polys2.size() != 1 or polys2[0] != tri2:
			cut_c += 1
		for poly in polys2:
			for q in range(1, poly.size() - 1):
				for e in [poly[0], poly[q], poly[q + 1]]:
					var pe2: PackedFloat32Array = e
					of.append(_level(Vector3(pe2[0], pe2[1], pe2[2])))
	var ns := ConcavePolygonShape3D.new()
	ns.set_faces(of)
	ns.backface_collision = true
	ResourceSaver.save(ns, "res://assets/tracks/track_a_col.res")
	print("GATE col: tris ", f.size() / 3, " -> ", of.size() / 3, " (cut ", cut_c, ")")
	quit()
