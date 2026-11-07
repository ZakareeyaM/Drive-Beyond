class_name MeshLib
extends RefCounted
## Procedural low-poly mesh helpers (no external assets needed).
## All meshes carry vertex colours so one material can draw many looks.

static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n: Vector3 = (c - a).cross(b - a).normalized()  # Godot front faces are clockwise
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(a)
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(c)

static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	tri(st, a, b, c, col)
	tri(st, a, c, d, col)

static func add_box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color, basis: Basis = Basis.IDENTITY) -> void:
	var h: Vector3 = size * 0.5
	var p: Array = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				p.append(center + basis * Vector3(h.x * sx, h.y * sy, h.z * sz))
	# index = (sx<0?0:4) + (sy<0?0:2) + (sz<0?0:1)
	quad(st, p[4], p[5], p[7], p[6], col)  # +x
	quad(st, p[0], p[2], p[3], p[1], col)  # -x
	quad(st, p[2], p[6], p[7], p[3], col)  # +y
	quad(st, p[0], p[1], p[5], p[4], col)  # -y
	quad(st, p[1], p[3], p[7], p[5], col)  # +z
	quad(st, p[0], p[4], p[6], p[2], col)  # -z

static func add_cylinder(st: SurfaceTool, base: Vector3, r0: float, r1: float, height: float, sides: int, col: Color, caps: bool = true) -> void:
	for i in range(sides):
		var a0: float = TAU * float(i) / float(sides)
		var a1: float = TAU * float(i + 1) / float(sides)
		var b0: Vector3 = base + Vector3(cos(a0) * r0, 0, sin(a0) * r0)
		var b1: Vector3 = base + Vector3(cos(a1) * r0, 0, sin(a1) * r0)
		var t0: Vector3 = base + Vector3(cos(a0) * r1, height, sin(a0) * r1)
		var t1: Vector3 = base + Vector3(cos(a1) * r1, height, sin(a1) * r1)
		quad(st, b1, b0, t0, t1, col)
		if caps:
			tri(st, base + Vector3(0, height, 0), t1, t0, col)

static func add_wheel_disc(st: SurfaceTool, center: Vector3, radius: float, width: float, sides: int, col: Color, axis_x: bool = true) -> void:
	# cylinder with axis along X
	for i in range(sides):
		var a0: float = TAU * float(i) / float(sides)
		var a1: float = TAU * float(i + 1) / float(sides)
		var p0 := Vector3(0, cos(a0) * radius, sin(a0) * radius)
		var p1 := Vector3(0, cos(a1) * radius, sin(a1) * radius)
		var hx := Vector3(width * 0.5, 0, 0)
		quad(st, center + p0 - hx, center + p1 - hx, center + p1 + hx, center + p0 + hx, col)
		tri(st, center + hx, center + p0 + hx, center + p1 + hx, col)
		tri(st, center - hx, center + p1 - hx, center + p0 - hx, col)

static func commit(st: SurfaceTool) -> ArrayMesh:
	return st.commit()

static func unit_box(color: Color = Color.WHITE) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	add_box(st, Vector3(0, 0.5, 0), Vector3.ONE, color)
	return st.commit()

static func roof_prism(color: Color = Color.WHITE) -> ArrayMesh:
	## base at y=0, ridge at y=1 along Z, width 1 (x), length 1 (z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-0.5, 0, -0.5)
	var b := Vector3(0.5, 0, -0.5)
	var c := Vector3(0.5, 0, 0.5)
	var d := Vector3(-0.5, 0, 0.5)
	var r0 := Vector3(0, 1, -0.5)
	var r1 := Vector3(0, 1, 0.5)
	quad(st, d, c, r1 + Vector3(0, 0, 0), r1, color) if false else null
	quad(st, a, d, r1, r0, color)   # left slope
	quad(st, c, b, r0, r1, color)   # right slope
	tri(st, b, a, r0, color)        # front gable
	tri(st, d, c, r1, color)        # back gable
	return st.commit()

static func pine_tree() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	add_cylinder(st, Vector3.ZERO, 0.28, 0.2, 2.6, 5, Color(0.32, 0.22, 0.13), false)
	add_cylinder(st, Vector3(0, 1.6, 0), 2.1, 0.15, 3.2, 6, Color(0.1, 0.3, 0.13), false)
	add_cylinder(st, Vector3(0, 3.4, 0), 1.65, 0.1, 3.0, 6, Color(0.12, 0.35, 0.15), false)
	add_cylinder(st, Vector3(0, 5.0, 0), 1.1, 0.05, 2.6, 6, Color(0.14, 0.4, 0.17), false)
	return st.commit()

static func oak_tree() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	add_cylinder(st, Vector3.ZERO, 0.32, 0.22, 3.0, 5, Color(0.35, 0.25, 0.15), false)
	add_cylinder(st, Vector3(0, 2.2, 0), 0.5, 2.6, 1.6, 7, Color(0.2, 0.45, 0.14), false)
	add_cylinder(st, Vector3(0, 3.8, 0), 2.6, 1.2, 1.7, 7, Color(0.25, 0.52, 0.16), true)
	return st.commit()

static func palm_tree() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	add_cylinder(st, Vector3.ZERO, 0.3, 0.18, 6.2, 5, Color(0.5, 0.38, 0.24), false)
	for i in range(7):
		var a: float = TAU * float(i) / 7.0
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var base := Vector3(0, 6.2, 0)
		var tip: Vector3 = base + dir * 3.4 + Vector3(0, -1.4, 0)
		var mid: Vector3 = base + dir * 1.6 + Vector3(0, 0.5, 0)
		quad(st, base - side * 0.15, mid - side * 0.55, mid + side * 0.55, base + side * 0.15, Color(0.15, 0.45, 0.17))
		tri(st, mid - side * 0.55, tip, mid + side * 0.55, Color(0.12, 0.38, 0.15))
		tri(st, mid + side * 0.55, tip, mid - side * 0.55, Color(0.12, 0.38, 0.15))
		tri(st, base - side * 0.15, base + side * 0.15, mid + side * 0.55, Color(0.15, 0.45, 0.17)) if false else null
	return st.commit()

static func cactus() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var g := Color(0.2, 0.42, 0.2)
	add_cylinder(st, Vector3.ZERO, 0.3, 0.26, 3.2, 6, g, true)
	add_box(st, Vector3(0.65, 1.7, 0), Vector3(0.9, 0.3, 0.3), g)
	add_cylinder(st, Vector3(0.9, 1.7, 0), 0.17, 0.15, 1.1, 5, g, true)
	add_box(st, Vector3(-0.6, 2.1, 0), Vector3(0.8, 0.28, 0.28), g)
	add_cylinder(st, Vector3(-0.85, 2.1, 0), 0.16, 0.14, 0.8, 5, g, true)
	return st.commit()

static func rock() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rings: int = 3
	var seg: int = 7
	var verts: Array = []
	for r in range(rings + 1):
		var row: Array = []
		var ang: float = PI * 0.5 * float(r) / float(rings)
		for s in range(seg):
			var a: float = TAU * float(s) / float(seg)
			var rad: float = cos(ang) * rng.randf_range(0.75, 1.15)
			row.append(Vector3(cos(a) * rad, sin(ang) * rng.randf_range(0.6, 0.95), sin(a) * rad))
		verts.append(row)
	for r in range(rings):
		for s in range(seg):
			var s2: int = (s + 1) % seg
			var shade: float = rng.randf_range(0.85, 1.05)
			var col := Color(0.45, 0.43, 0.4) * shade
			col.a = 1.0
			quad(st, verts[r][s], verts[r][s2], verts[r + 1][s2], verts[r + 1][s], col)
	var top: Vector3 = Vector3(0, 0.9, 0)
	for s in range(seg):
		tri(st, verts[rings][s], verts[rings][(s + 1) % seg], top, Color(0.5, 0.48, 0.45))
	return st.commit()

static func street_lamp() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grey := Color(0.2, 0.21, 0.23)
	add_cylinder(st, Vector3.ZERO, 0.12, 0.08, 7.0, 5, grey, false)
	add_box(st, Vector3(0.9, 7.1, 0), Vector3(1.9, 0.12, 0.14), grey)
	add_box(st, Vector3(1.75, 7.0, 0), Vector3(0.9, 0.14, 0.32), Color(1.0, 0.9, 0.65))
	return st.commit()

static func glow_quad(size: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h: float = size * 0.5
	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(0, 0)); st.add_vertex(Vector3(-h, 0, -h))
	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(1, 0)); st.add_vertex(Vector3(h, 0, -h))
	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(1, 1)); st.add_vertex(Vector3(h, 0, h))
	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(0, 0)); st.add_vertex(Vector3(-h, 0, -h))
	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(1, 1)); st.add_vertex(Vector3(h, 0, h))
	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(0, 1)); st.add_vertex(Vector3(-h, 0, h))
	return st.commit()

static func beam_mesh(radius: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides: int = 12
	for i in range(sides):
		var a0: float = TAU * float(i) / float(sides)
		var a1: float = TAU * float(i + 1) / float(sides)
		var b0 := Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var b1 := Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var t0 := Vector3(cos(a0) * radius * 0.6, height, sin(a0) * radius * 0.6)
		var t1 := Vector3(cos(a1) * radius * 0.6, height, sin(a1) * radius * 0.6)
		st.set_uv(Vector2(0, 0)); st.set_normal(Vector3.UP); st.add_vertex(b0)
		st.set_uv(Vector2(0, 1)); st.set_normal(Vector3.UP); st.add_vertex(t0)
		st.set_uv(Vector2(0, 1)); st.set_normal(Vector3.UP); st.add_vertex(t1)
		st.set_uv(Vector2(0, 0)); st.set_normal(Vector3.UP); st.add_vertex(b0)
		st.set_uv(Vector2(0, 1)); st.set_normal(Vector3.UP); st.add_vertex(t1)
		st.set_uv(Vector2(0, 0)); st.set_normal(Vector3.UP); st.add_vertex(b1)
	return st.commit()
