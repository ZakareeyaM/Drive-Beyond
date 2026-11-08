class_name HeroCars
extends RefCounted
## Hand-tuned, higher-detail procedural models for the four showcase cars
## (red GT coupe, black pickup, white sports coupe, blue muscle car).
## Uses the same coordinate system as CarBuilder: forward = -Z, origin at ground level mid-car.
## Shell = lofted tub with a real shoulder line + lofted glasshouse + painted roof/pillars.

const HERO_IDS := ["kestrel_r", "hauler_r", "vela_gt", "brawler_69"]

static func is_hero(vid: String) -> bool:
	return vid in HERO_IDS

# ------------------------------------------------------------------ geometry helpers
static func _chaikin(pts: Array, closed: bool = true) -> Array:
	var out: Array = []
	var n: int = pts.size()
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		if not closed and i == n - 1:
			break
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	return out

## Closed ring from right-half normalised points (x frac, y frac), bottom-centre -> top-centre.
static func _ring(norm: Array, hw: float, y0: float, y1: float, z: float, smooth_iter: int = 1) -> PackedVector3Array:
	var pts: Array = []
	for p in norm:
		pts.append(Vector2(p.x * hw, y0 + p.y * (y1 - y0)))
	for i in range(norm.size() - 2, 0, -1):
		pts.append(Vector2(-norm[i].x * hw, y0 + norm[i].y * (y1 - y0)))
	for k in smooth_iter:
		pts = _chaikin(pts)
	var ring := PackedVector3Array()
	for p in pts:
		ring.append(Vector3(p.x, p.y, z))
	return ring

static func _beam(parent: Node3D, mat: Material, a: Vector3, b: Vector3, thick: float) -> MeshInstance3D:
	var bm := BoxMesh.new()
	var len: float = a.distance_to(b)
	bm.size = Vector3(thick, thick, len)
	var mi := CarBuilder._mi(bm, mat, parent, (a + b) * 0.5)
	var d: Vector3 = (b - a).normalized()
	var up: Vector3 = Vector3.UP if absf(d.y) < 0.98 else Vector3.RIGHT
	mi.transform = Transform3D(Basis.looking_at(d, up), (a + b) * 0.5)
	return mi

## Arc ribbon around a wheel arch (axis X), r0..r1 radial, from x to x+dx, over [a0,a1] degrees (0 = up, signed to front/back).
static func _arch_lip(parent: Node3D, mat: Material, center: Vector3, r0: float, r1: float, dx: float, a0: float, a1: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = 18
	for i in n:
		var u0: float = deg_to_rad(lerpf(a0, a1, float(i) / n))
		var u1: float = deg_to_rad(lerpf(a0, a1, float(i + 1) / n))
		var d0 := Vector3(0, cos(u0), sin(u0))
		var d1 := Vector3(0, cos(u1), sin(u1))
		var i0: Vector3 = d0 * r0
		var i1: Vector3 = d1 * r0
		var o0: Vector3 = d0 * r1
		var o1: Vector3 = d1 * r1
		var sx := Vector3(dx, 0, 0)
		# outer face (facing out along dx), top face, inner face
		_quad(st, o0 + sx, o1 + sx, i1 + sx, i0 + sx, dx)
		_quad(st, o0, o1, o1 + sx, o0 + sx, 0.0)
		_quad(st, i1, i0, i0 + sx, i1 + sx, 0.0)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.015, 0.015, 0.018)
	tm.roughness = 0.8
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = tm
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, flip: float) -> void:
	# double-sided so winding never matters
	for tri in [[a, b, c], [a, c, d]]:
		for p in tri:
			st.add_vertex(p)

static func _torus(parent: Node3D, mat: Material, pos: Vector3, r_in: float, r_out: float, face_z: bool = true) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = r_in
	tm.outer_radius = r_out
	tm.rings = 16
	tm.ring_segments = 8
	var mi := CarBuilder._mi(tm, mat, parent, pos)
	mi.rotation = Vector3(PI * 0.5, 0, 0) if face_z else Vector3(0, 0, PI * 0.5)
	return mi

static func _cyl(parent: Node3D, mat: Material, pos: Vector3, r: float, h: float, axis: String = "z") -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 14
	cm.rings = 1
	var mi := CarBuilder._mi(cm, mat, parent, pos)
	if axis == "z":
		mi.rotation = Vector3(PI * 0.5, 0, 0)
	elif axis == "x":
		mi.rotation = Vector3(0, 0, PI * 0.5)
	return mi

static func _bx(parent: Node3D, mat: Material, pos: Vector3, size: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return CarBuilder._box_mi(parent, mat, pos, size, rot)

# ------------------------------------------------------------------ shell
## cfg: hw(t) bot(t) top(t) key arrays, norm ring, end rounding.
static func _build_tub(root: Node3D, paint: Material, v: Dictionary, cfg: Dictionary) -> MeshInstance3D:
	var L: float = float(v["L"])
	var W2: float = float(v["W"]) * 0.5
	var N: int = 36
	var rings: Array = []
	var fr: float = float(cfg.get("e_front", 0.02))
	var rr: float = float(cfg.get("e_rear", 0.02))
	for i in range(N + 1):
		var t: float = 0.5 - 0.5 * cos(PI * float(i) / float(N))
		var z: float = -L * 0.5 + t * L
		var hw: float = W2 * CarBuilder._prof(cfg["hw"], t)
		var y0: float = CarBuilder._prof(cfg["bot"], t)
		var y1: float = CarBuilder._prof(cfg["top"], t)
		var e: float = 1.0
		if t < fr:
			e = sqrt(maxf(0.0, 1.0 - pow((fr - t) / fr, 2.0)))
		elif t > 1.0 - rr:
			e = sqrt(maxf(0.0, 1.0 - pow((t - (1.0 - rr)) / rr, 2.0)))
		e = maxf(e, 0.55)
		var ym: float = (y0 + y1) * 0.5
		var hh: float = (y1 - y0) * 0.5 * lerpf(1.0, e, 0.6)
		rings.append(_ring(cfg["norm"], hw * e, ym - hh, ym + hh, z, 1))
	var mi: MeshInstance3D = CarBuilder._mi(CarBuilder._mesh_from(CarBuilder._loft_mesh(rings, true, true)), paint, root)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi

## Glasshouse: glass loft + painted roof slab + pillars. g: cab0,cab1,roof0,roof1, base/top width factors, roof y, belt y
static func _build_cabin(root: Node3D, paint: Material, glass: Material, dark: Material, v: Dictionary, cfg: Dictionary, g: Dictionary) -> MeshInstance3D:
	var L: float = float(v["L"])
	var belt: float = float(g["belt"])
	var roof: float = float(g["roof"])
	var c0: float = float(g["cab0"])
	var c1: float = float(g["cab1"])
	var r0: float = float(g["roof0"])
	var r1: float = float(g["roof1"])
	var W2: float = float(v["W"]) * 0.5
	var wf: float = float(g.get("wf", 0.88))     # base width as fraction of tub half-width
	var tf: float = float(g.get("tf", 0.70))     # roof half-width fraction
	var norm: Array = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.97, 0.3), Vector2(0.9, 0.7), Vector2(0.82, 0.93), Vector2(0.6, 1.0), Vector2(0.0, 1.0)]
	var GN: int = 20
	var rings: Array = []
	var roof_rings: Array = []
	var top_keys: Array = g.get("top_keys", [[c0, belt], [r0, roof], [r1, roof], [c1, belt]])
	for i in range(GN + 1):
		var t: float = lerpf(c0, c1, float(i) / float(GN))
		var z: float = -L * 0.5 + t * L
		var hw: float = W2 * CarBuilder._prof(cfg["hw"], t) * wf
		var ytop: float = CarBuilder._prof(top_keys, t)
		# roof half-width tapers at the screen and tail, so the glasshouse reads as a sloped canopy
		var taper: float = smoothstep(0.0, 0.25, float(i) / float(GN)) * smoothstep(1.0, 0.75, float(i) / float(GN))
		var tw: float = lerpf(0.55, tf, taper)
		var nn: Array = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.98, 0.3), Vector2(lerpf(1.0, tw, 0.5), 0.72), Vector2(tw + 0.12, 0.93), Vector2(tw * 0.55, 1.0), Vector2(0.0, 1.0)]
		var ring: PackedVector3Array = _ring(nn, hw, belt - 0.03, ytop, z, 1)
		rings.append(ring)
		# roof slab only exists where the roof is high enough
		var rh: float = ytop - belt
		if rh > (roof - belt) * 0.82:
			var sl: Array = [Vector2(0.0, 0.0), Vector2(tw + 0.1, -0.0), Vector2(tw + 0.12, 0.0), Vector2(tw * 0.55, 0.0), Vector2(0.0, 0.0)]
			var ys: float = ytop
			var ww: float = hw
			var pts := PackedVector3Array()
			var half: Array = [Vector2(0.0, ys - 0.07), Vector2(ww * (tw + 0.1), ys - 0.07), Vector2(ww * (tw + 0.1), ys - 0.035), Vector2(ww * (tw * 0.55), ys + 0.012), Vector2(0.0, ys + 0.012)]
			var full: Array = []
			for p in half:
				full.append(p)
			for k in range(half.size() - 2, 0, -1):
				full.append(Vector2(-half[k].x, half[k].y))
			for p in full:
				pts.append(Vector3(p.x, p.y, z))
			roof_rings.append(pts)
	var g_mi: MeshInstance3D = CarBuilder._mi(CarBuilder._mesh_from(CarBuilder._loft_mesh(rings, true, true)), glass, root)
	g_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if roof_rings.size() > 3:
		var rm: MeshInstance3D = CarBuilder._mi(CarBuilder._mesh_from(CarBuilder._loft_mesh(roof_rings, true, true)), paint, root)
		rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# pillars (A / B / C) as slim painted beams along the glasshouse edge
	var tmid0: float = c0
	var zA0: float = -L * 0.5 + c0 * L
	var zA1: float = -L * 0.5 + r0 * L
	var zC0: float = -L * 0.5 + c1 * L
	var zC1: float = -L * 0.5 + r1 * L
	var hA0: float = W2 * CarBuilder._prof(cfg["hw"], c0) * wf
	var hA1: float = W2 * CarBuilder._prof(cfg["hw"], r0) * wf * tf
	var hC0: float = W2 * CarBuilder._prof(cfg["hw"], c1) * wf
	var hC1: float = W2 * CarBuilder._prof(cfg["hw"], r1) * wf * tf
	var pt: float = float(g.get("pillar", 0.045))
	for side in [-1.0, 1.0]:
		_beam(root, paint, Vector3(side * hA0 * 0.97, belt, zA0), Vector3(side * (hA1 + 0.04), roof - 0.03, zA1), pt)
		_beam(root, paint, Vector3(side * hC0 * 0.97, belt, zC0), Vector3(side * (hC1 + 0.04), roof - 0.03, zC1), pt * 1.3)
		if bool(g.get("b_pillar", true)):
			var zB: float = lerpf(zA1, zC1, 0.5)
			var hB: float = W2 * CarBuilder._prof(cfg["hw"], 0.5) * wf * lerpf(1.0, tf, 0.75)
			_beam(root, dark, Vector3(side * hB * 1.01, belt, zB), Vector3(side * hB * 0.9, roof - 0.04, zB), 0.06)
	return g_mi

static func _wheel_arches(root: Node3D, paint_or_trim: Material, v: Dictionary, cfg: Dictionary, lip: float = 0.05, depth: float = 0.05, a_span: float = 100.0) -> void:
	var L: float = float(v["L"])
	var wr: float = float(v["wr"])
	var wb: float = float(v["wb"])
	var arch_mat := StandardMaterial3D.new()
	arch_mat.albedo_color = Color(0.008, 0.008, 0.01)
	arch_mat.roughness = 1.0
	for side in [-1.0, 1.0]:
		for fz in [-1.0, 1.0]:
			var zc: float = fz * wb * 0.5
			var t: float = (zc + L * 0.5) / L
			var hw: float = float(v["W"]) * 0.5 * CarBuilder._prof(cfg["hw"], t)
			# dark wheel-well disc sits just proud of the body, lip frames it
			var disc := CylinderMesh.new()
			disc.top_radius = wr + lip * 0.6
			disc.bottom_radius = wr + lip * 0.6
			disc.height = 0.03
			disc.radial_segments = 22
			var dm := CarBuilder._mi(disc, arch_mat, root, Vector3(side * (hw - 0.012), wr, zc))
			dm.rotation = Vector3(0, 0, PI * 0.5)
			if paint_or_trim != null:
				var x0: float = hw - 0.015
				var dxx: float = depth * side
				_arch_lip(root, paint_or_trim, Vector3(x0, wr, zc), wr + lip * 0.6, wr + lip * 0.6 + 0.045, dxx, -a_span, a_span)

static func _mirrors(root: Node3D, paint: Material, dark: Material, v: Dictionary, cfg: Dictionary, belt: float, t_cab: float, size: float = 1.0) -> void:
	var L: float = float(v["L"])
	var hw: float = float(v["W"]) * 0.5 * CarBuilder._prof(cfg["hw"], t_cab) * 0.86
	for side in [-1.0, 1.0]:
		var z: float = -L * 0.5 + (t_cab + 0.012) * L
		_bx(root, dark, Vector3(side * (hw + 0.04), belt + 0.02, z + 0.06), Vector3(0.12, 0.035, 0.04), Vector3(0, 0, side * 0.2))
		_bx(root, paint, Vector3(side * (hw + 0.13) , belt + 0.075, z + 0.1), Vector3(0.1, 0.09, 0.2) * size)

static func _door_lines(root: Node3D, dark: Material, chrome: Material, v: Dictionary, cfg: Dictionary, belly: float, belt: float, z0: float, z1: float, handle_front: bool = true) -> void:
	var hw: float = float(v["W"]) * 0.5 * CarBuilder._prof(cfg["hw"], 0.5) * 1.0
	for side in [-1.0, 1.0]:
		for zz in [z0, z1]:
			_bx(root, dark, Vector3(side * (hw + 0.002), (belly + belt) * 0.5 + 0.02, zz), Vector3(0.004, belt - belly - 0.14, 0.008))
		_bx(root, dark, Vector3(side * (hw + 0.002), belly + 0.14, (z0 + z1) * 0.5), Vector3(0.004, 0.008, z1 - z0))
		_bx(root, chrome, Vector3(side * (hw + 0.012), belt - 0.1, lerpf(z0, z1, 0.22)), Vector3(0.02, 0.03, 0.14))

static func _plate(root: Node3D, text: String, pos: Vector3, rear: bool, w: float = 0.52) -> void:
	var pm := CarBuilder.emissive_material(Color(0.95, 0.95, 0.9), 0.15)
	var pl := CarBuilder._box_mi(root, pm, pos, Vector3(w, w * 0.22, 0.02))
	var lab := Label3D.new()
	lab.text = text
	lab.font_size = 48
	lab.pixel_size = 0.0023
	lab.modulate = Color(0.05, 0.05, 0.1)
	lab.outline_size = 0
	lab.position = Vector3(0, 0, 0.011 if rear else -0.011)
	lab.rotation = Vector3(0, 0 if rear else PI, 0)
	lab.double_sided = false
	pl.add_child(lab)

# ------------------------------------------------------------------ per-car configuration
static func _cfg(vid: String, v: Dictionary) -> Dictionary:
	var hood: float = float(v["hood"])
	var belt: float = float(v["belt"])
	var trunk: float = float(v["trunk"])
	var belly: float = float(v["belly"])
	var cab0: float = float(v["cab0"])
	var cab1: float = float(v["cab1"])
	var norm: Array = [Vector2(0.0, 0.0), Vector2(0.78, 0.0), Vector2(0.97, 0.14), Vector2(1.0, 0.5), Vector2(0.97, 0.76), Vector2(0.84, 0.94), Vector2(0.5, 1.0), Vector2(0.0, 1.0)]
	var c: Dictionary = {"norm": norm}
	c["bot"] = [[0.0, belly + 0.14], [0.06, belly + 0.03], [0.94, belly + 0.03], [1.0, belly + 0.15]]
	match vid:
		"kestrel_r":
			c["hw"] = [[0.0, 0.84], [0.04, 0.95], [0.2, 0.99], [0.5, 1.0], [0.78, 1.0], [0.94, 0.95], [1.0, 0.88]]
			c["top"] = [[0.0, hood * 0.8], [0.04, hood * 0.94], [0.12, hood], [cab0, belt * 0.985], [cab1, belt], [0.93, trunk], [1.0, trunk * 0.93]]
			c["e_front"] = 0.035
			c["e_rear"] = 0.03
		"vela_gt":
			c["hw"] = [[0.0, 0.84], [0.04, 0.94], [0.2, 0.98], [0.5, 1.0], [0.78, 0.99], [0.94, 0.94], [1.0, 0.88]]
			c["top"] = [[0.0, hood * 0.82], [0.04, hood * 0.95], [0.14, hood], [cab0, belt * 0.985], [cab1, belt], [0.94, trunk], [1.0, trunk * 0.94]]
			c["e_front"] = 0.035
			c["e_rear"] = 0.03
		"brawler_69":
			c["hw"] = [[0.0, 0.9], [0.04, 0.97], [0.25, 1.0], [0.5, 0.97], [0.76, 0.98], [0.95, 1.0], [1.0, 0.93]]
			c["top"] = [[0.0, hood * 0.86], [0.03, hood * 0.96], [0.1, hood], [cab0, belt * 0.985], [cab1, belt], [0.84, trunk], [1.0, trunk * 0.96]]
			c["e_front"] = 0.022
			c["e_rear"] = 0.022
		_:
			c["hw"] = [[0.0, 0.92], [0.04, 0.98], [0.3, 1.0], [0.7, 1.0], [0.96, 0.99], [1.0, 0.94]]
			c["top"] = [[0.0, hood * 0.86], [0.03, hood * 0.95], [0.08, hood], [cab0, hood * 1.02], [cab0 + 0.05, belt * 0.99], [cab1, belt], [cab1 + 0.012, belt - 0.34], [1.0, belt - 0.36]]
			c["e_front"] = 0.02
			c["e_rear"] = 0.015
	return c

static func _lamp(root: Node3D, bezel: Material, lamp: Material, pos: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	var b: MeshInstance3D = _bx(root, bezel, pos, size + Vector3(0.04, 0.035, 0.0), Vector3(0, yaw, 0))
	var l: MeshInstance3D = _bx(root, lamp, pos + Vector3(0, 0, 0.0), size, Vector3(0, yaw, 0))
	l.position.z += (-0.012 if pos.z < 0.0 else 0.012)

static func _ring_lamp(root: Node3D, bezel: Material, lamp: Material, rim: Material, pos: Vector3, r: float, dir: float) -> void:
	_cyl(root, bezel, pos, r * 1.15, 0.05)
	_cyl(root, lamp, pos + Vector3(0, 0, dir * 0.012), r * 0.85, 0.05)
	_torus(root, rim, pos + Vector3(0, 0, dir * 0.03), r * 0.95, r * 1.2)

# ------------------------------------------------------------------ entry point
static func build(vid: String, root: Node3D, v: Dictionary, custom: Dictionary, out: Dictionary, paint: Material, glass: Material, dark: Material, chrome: Material, head_mat: Material, tail_mat: Material) -> void:
	var L: float = float(v["L"])
	var belly: float = float(v["belly"])
	var hood: float = float(v["hood"])
	var belt: float = float(v["belt"])
	var trunk: float = float(v["trunk"])
	var roof: float = float(v["roof"])
	var wr: float = float(v["wr"])
	var vv: Dictionary = v.duplicate()
	vv["W"] = minf(float(v["W"]), float(v["track"]) + float(v["ww"]) * 0.9)
	var W: float = float(vv["W"])
	var W2: float = W * 0.5
	var cfg: Dictionary = _cfg(vid, vv)
	var body_mi: MeshInstance3D = _build_tub(root, paint, vv, cfg)
	var g: Dictionary = {"belt": belt, "roof": roof, "cab0": v["cab0"], "cab1": v["cab1"], "roof0": v["roof0"], "roof1": v["roof1"]}
	if vid == "brawler_69":
		g["wf"] = 0.9
		g["tf"] = 0.76
	elif vid == "hauler_r":
		g["wf"] = 0.92
		g["tf"] = 0.86
		g["pillar"] = 0.09
	elif vid == "kestrel_r":
		g["tf"] = 0.66
	var g_mi: MeshInstance3D = _build_cabin(root, paint, glass, dark, vv, cfg, g)
	out["body_mi"] = body_mi
	out["glass_mi"] = g_mi
	_wheel_arches(root, dark, vv, cfg, 0.05, 0.055, 78.0 if vid != "hauler_r" else 90.0)
	var cab0: float = float(v["cab0"])
	var cab1: float = float(v["cab1"])
	_mirrors(root, paint, dark, vv, cfg, belt, cab0, 1.25 if vid == "hauler_r" else 1.0)
	_door_lines(root, dark, chrome, vv, cfg, belly, belt, -L * 0.5 + cab0 * L + 0.1, -L * 0.5 + cab1 * L - (0.0 if vid == "hauler_r" else 0.12))
	var lamps: Array = []
	var tails: Array = []
	var zf: float = -L * 0.5
	var zr: float = L * 0.5
	var bwf: float = W2 * CarBuilder._prof(cfg["hw"], 0.03)
	var bwr: float = W2 * CarBuilder._prof(cfg["hw"], 0.97)
	var rim_m: Material = chrome
	var plate_text: String = String(custom.get("plate", "DB-001"))
	match vid:
		"kestrel_r":
			# --- front: wide low intake, small grille, swept slim lamps, splitter
			_bx(root, dark, Vector3(0, belly + 0.20, zf + 0.025), Vector3(bwf * 1.35, 0.2, 0.06))
			_bx(root, dark, Vector3(0, belly + 0.43, zf + 0.03), Vector3(bwf * 0.9, 0.14, 0.05))
			_bx(root, chrome, Vector3(0, belly + 0.43, zf + 0.012), Vector3(bwf * 0.9 + 0.04, 0.02, 0.03))
			_bx(root, dark, Vector3(0, belly + 0.045, zf - 0.03), Vector3(W * 0.92, 0.035, 0.26))
			for s in [-1.0, 1.0]:
				_lamp(root, dark, head_mat, Vector3(s * bwf * 0.66, hood - 0.1, zf + 0.12), Vector3(0.3, 0.085, 0.08), s * 0.3)
				lamps.append(Vector3(s * bwf * 0.66, hood - 0.1, zf + 0.15))
				_bx(root, dark, Vector3(s * bwf * 0.78, belly + 0.22, zf + 0.04), Vector3(0.16, 0.1, 0.05))
				_bx(root, dark, Vector3(s * 0.34, hood + 0.004, zf + L * 0.27), Vector3(0.24, 0.012, 0.55))
				_bx(root, dark, Vector3(s * (W2 * 0.99 + 0.004), belly + 0.42, zf + L * 0.27), Vector3(0.012, 0.16, 0.34))
				_bx(root, dark, Vector3(s * (W2 * 1.0 + 0.004), belly + 0.30, zr - L * 0.14), Vector3(0.012, 0.12, 0.3))
			# --- rear: four round lamps, diffuser, quad pipes, GT wing
			_bx(root, dark, Vector3(0, belly + 0.2, zr - 0.03), Vector3(bwr * 1.7, 0.3, 0.07))
			for s in [-1.0, 1.0]:
				for k in [0.46, 0.7]:
					var lp := Vector3(s * bwr * k * 1.05, trunk - 0.18, zr - 0.012)
					_cyl(root, dark, lp, 0.082, 0.05)
					_cyl(root, tail_mat, lp + Vector3(0, 0, 0.014), 0.058, 0.05)
					_torus(root, chrome, lp + Vector3(0, 0, 0.02), 0.062, 0.086)
					tails.append(lp + Vector3(0, 0, -0.03))
			var ex_r: float = 0.05 + 0.01 * int(custom.get("exhaust_level", 0))
			for s in [-1.0, 1.0]:
				for k in [0.14, 0.3]:
					_cyl(root, chrome, Vector3(s * bwr * k * 1.4, belly + 0.14, zr + 0.01), ex_r, 0.12)
					_cyl(root, dark, Vector3(s * bwr * k * 1.4, belly + 0.14, zr + 0.065), ex_r * 0.72, 0.03)
			for i in range(-3, 4):
				_bx(root, dark, Vector3(i * 0.09, belly + 0.05, zr + 0.01), Vector3(0.012, 0.08, 0.1))
			var wz: float = zr - 0.42
			for s in [-1.0, 1.0]:
				_bx(root, dark, Vector3(s * W2 * 0.4, trunk + 0.17, wz + 0.02), Vector3(0.05, 0.36, 0.12), Vector3(0.12, 0, 0))
				_bx(root, dark, Vector3(s * W2 * 0.9, trunk + 0.36, wz), Vector3(0.025, 0.2, 0.5), Vector3(0.06, 0, 0))
			_bx(root, dark, Vector3(0, trunk + 0.36, wz), Vector3(W * 0.88, 0.04, 0.38), Vector3(0.07, 0, 0))
			_bx(root, paint, Vector3(0, trunk + 0.375, wz + 0.01), Vector3(W * 0.7, 0.012, 0.3), Vector3(0.07, 0, 0))
			_plate(root, plate_text, Vector3(0, belly + 0.62, zr + 0.002), true)
			_plate(root, plate_text, Vector3(0, belly + 0.2, zf - 0.002), false)
		"hauler_r":
			var bw: float = bwf
			# --- front: huge grille w/ chrome bars, stacked lamps, tall bumper
			_bx(root, dark, Vector3(0, hood - 0.26, zf + 0.025), Vector3(bw * 1.08, 0.5, 0.07))
			for i in range(3):
				_bx(root, chrome, Vector3(0, hood - 0.1 - i * 0.14, zf - 0.006), Vector3(bw * 1.08, 0.028, 0.04))
			_bx(root, chrome, Vector3(0, hood - 0.26, zf - 0.006), Vector3(0.04, 0.5, 0.04))
			_bx(root, chrome, Vector3(0, hood + -0.0, zf + 0.0), Vector3(bw * 1.16, 0.035, 0.05))
			for s in [-1.0, 1.0]:
				_lamp(root, dark, head_mat, Vector3(s * (bw * 0.82), hood - 0.16, zf + 0.13), Vector3(0.22, 0.11, 0.08), s * 0.2)
				_lamp(root, dark, head_mat, Vector3(s * (bw * 0.82), hood - 0.3, zf + 0.12), Vector3(0.16, 0.06, 0.08), s * 0.2)
				lamps.append(Vector3(s * bw * 0.82, hood - 0.16, zf + 0.15))
				_cyl(root, head_mat, Vector3(s * bw * 0.72, belly + 0.26, zf - 0.03), 0.055, 0.06)
				_bx(root, dark, Vector3(s * (W2 * 1.0 + 0.04), belly + 0.14, -L * 0.5 + L * 0.44), Vector3(0.1, 0.035, L * 0.2))
			_bx(root, dark, Vector3(0, belly + 0.17, zf - 0.04), Vector3(W * 0.98, 0.22, 0.2))
			_bx(root, chrome, Vector3(0, belly + 0.3, zf - 0.04), Vector3(W * 0.96, 0.04, 0.2))
			_bx(root, dark, Vector3(0, belly + 0.1, zf + 0.0), Vector3(bw * 0.9, 0.12, 0.1))
			# --- bed
			var cab1z: float = zf + cab1 * L
			var bed_len: float = zr - cab1z - 0.02
			var wy: float = belt - 0.34
			var bwb: float = W2 * CarBuilder._prof(cfg["hw"], 0.8)
			for s in [-1.0, 1.0]:
				_bx(root, paint, Vector3(s * (bwb - 0.05), wy + 0.22, cab1z + bed_len * 0.5), Vector3(0.1, 0.44, bed_len))
				_bx(root, dark, Vector3(s * (bwb - 0.05), wy + 0.45, cab1z + bed_len * 0.5), Vector3(0.12, 0.03, bed_len + 0.01))
			_bx(root, paint, Vector3(0, wy + 0.22, cab1z + 0.05), Vector3(bwb * 2.0 - 0.12, 0.44, 0.1))
			_bx(root, paint, Vector3(0, wy + 0.2, zr - 0.05), Vector3(bwr * 2.0 - 0.04, 0.4, 0.09))
			_bx(root, dark, Vector3(0, wy + 0.42, zr - 0.05), Vector3(bwr * 2.0 - 0.02, 0.03, 0.11))
			_bx(root, dark, Vector3(0, wy + 0.02, cab1z + bed_len * 0.5), Vector3(bwb * 2.0 - 0.2, 0.025, bed_len - 0.1))
			_bx(root, chrome, Vector3(0, wy + 0.3, zr + 0.002), Vector3(0.3, 0.035, 0.02))
			# --- rear: vertical lamps in the bed corners, chrome bumper
			for s in [-1.0, 1.0]:
				var tp := Vector3(s * (bwr - 0.1), wy + 0.2, zr + 0.003)
				_bx(root, dark, tp, Vector3(0.16, 0.36, 0.04))
				_bx(root, tail_mat, tp + Vector3(0, 0, 0.012), Vector3(0.1, 0.3, 0.04))
				tails.append(tp + Vector3(0, 0, -0.05))
			_bx(root, dark, Vector3(0, belly + 0.16, zr + 0.01), Vector3(W * 0.98, 0.2, 0.2))
			_bx(root, chrome, Vector3(0, belly + 0.28, zr + 0.01), Vector3(W * 0.96, 0.05, 0.2))
			var ex_r2: float = 0.05 + 0.01 * int(custom.get("exhaust_level", 0))
			_cyl(root, chrome, Vector3(W2 * 0.55, belly + 0.02, zr - 0.15), ex_r2, 0.3, "z")
			# cab roof marker lights
			var amber: Material = CarBuilder.emissive_material(Color(1.0, 0.55, 0.05), 0.5)
			for k in [-0.3, 0.0, 0.3]:
				_bx(root, amber, Vector3(k, roof + 0.045, zf + float(v["roof0"]) * L + 0.02), Vector3(0.1, 0.05, 0.05))
			# side steps
			for s in [-1.0, 1.0]:
				_bx(root, dark, Vector3(s * (W2 + 0.02), belly + 0.06, zf + (cab0 + cab1) * 0.5 * L), Vector3(0.14, 0.04, (cab1 - cab0) * L * 0.9))
			_plate(root, plate_text, Vector3(0, belly + 0.62, zr + 0.002), true)
			_plate(root, plate_text, Vector3(0, belly + 0.2, zf - 0.14), false)
		"vela_gt":
			# --- front: sharp slim lamps, small upper grille, wide lower intake with round fog lamps
			_bx(root, dark, Vector3(0, belly + 0.18, zf + 0.025), Vector3(bwf * 1.12, 0.18, 0.06))
			_bx(root, dark, Vector3(0, belly + 0.4, zf + 0.03), Vector3(bwf * 0.62, 0.1, 0.05))
			_bx(root, chrome, Vector3(0, belly + 0.4, zf + 0.012), Vector3(bwf * 0.62 + 0.03, 0.015, 0.03))
			_bx(root, dark, Vector3(0, belly + 0.045, zf - 0.02), Vector3(W * 0.9, 0.03, 0.22))
			for s in [-1.0, 1.0]:
				_lamp(root, dark, head_mat, Vector3(s * bwf * 0.72, hood - 0.09, zf + 0.1), Vector3(0.28, 0.075, 0.07), s * 0.35)
				lamps.append(Vector3(s * bwf * 0.72, hood - 0.09, zf + 0.13))
				_cyl(root, dark, Vector3(s * bwf * 0.78, belly + 0.2, zf + 0.0), 0.06, 0.05)
				_cyl(root, head_mat, Vector3(s * bwf * 0.78, belly + 0.2, zf - 0.01), 0.04, 0.05)
				for k in range(3):
					_bx(root, dark, Vector3(s * (W2 * 0.99 + 0.004), belly + 0.36 + k * 0.035, zf + L * 0.3), Vector3(0.012, 0.014, 0.2))
			# --- rear: slim wraparound lamps, ducktail, dual pipes, diffuser
			_bx(root, dark, Vector3(0, belly + 0.17, zr - 0.03), Vector3(bwr * 1.6, 0.24, 0.07))
			for s in [-1.0, 1.0]:
				var tp2 := Vector3(s * bwr * 0.62, trunk - 0.15, zr - 0.012)
				_bx(root, dark, tp2, Vector3(0.42, 0.11, 0.05), Vector3(0, s * -0.12, 0))
				_bx(root, tail_mat, tp2 + Vector3(0, 0, 0.012), Vector3(0.38, 0.07, 0.05), Vector3(0, s * -0.12, 0))
				tails.append(tp2 + Vector3(0, 0, -0.04))
			var ex_r3: float = 0.048 + 0.01 * int(custom.get("exhaust_level", 0))
			for s in [-1.0, 1.0]:
				_cyl(root, chrome, Vector3(s * bwr * 0.38, belly + 0.13, zr + 0.01), ex_r3, 0.12)
				_cyl(root, dark, Vector3(s * bwr * 0.38, belly + 0.13, zr + 0.065), ex_r3 * 0.72, 0.03)
			_bx(root, paint, Vector3(0, trunk + 0.02, zr - 0.2), Vector3(W * 0.62, 0.035, 0.28), Vector3(0.14, 0, 0))
			_plate(root, plate_text, Vector3(0, belly + 0.54, zr + 0.002), true)
			_plate(root, plate_text, Vector3(0, belly + 0.18, zf - 0.002), false)
		"brawler_69":
			# --- front: full-width black grille in chrome frame, hidden round lamps, chrome bumper
			_bx(root, dark, Vector3(0, hood - 0.2, zf + 0.025), Vector3(bwf * 1.52, 0.26, 0.07))
			_bx(root, chrome, Vector3(0, hood - 0.07, zf + 0.0), Vector3(bwf * 1.56, 0.03, 0.06))
			_bx(root, chrome, Vector3(0, hood - 0.33, zf + 0.0), Vector3(bwf * 1.56, 0.03, 0.06))
			for s in [-1.0, 1.0]:
				_bx(root, chrome, Vector3(s * bwf * 0.77, hood - 0.2, zf + 0.0), Vector3(0.03, 0.29, 0.06))
				var lp2 := Vector3(s * bwf * 0.4, hood - 0.2, zf + 0.04)
				_ring_lamp(root, dark, head_mat, chrome, lp2, 0.095, -1.0)
				lamps.append(lp2 + Vector3(0, 0, 0.05))
			for i in range(-4, 5):
				if i != 0:
					_bx(root, chrome, Vector3(i * bwf * 0.17, hood - 0.2, zf - 0.004), Vector3(0.012, 0.22, 0.03))
			_bx(root, chrome, Vector3(0, belly + 0.2, zf - 0.04), Vector3(W * 0.97, 0.1, 0.12))
			_bx(root, dark, Vector3(0, belly + 0.1, zf + 0.0), Vector3(bwf * 1.3, 0.14, 0.08))
			# hood bulge + twin scoops
			_bx(root, paint, Vector3(0, hood + 0.025, zf + L * 0.3), Vector3(W * 0.3, 0.05, L * 0.28))
			for s in [-1.0, 1.0]:
				_bx(root, dark, Vector3(s * W * 0.07, hood + 0.065, zf + L * 0.25), Vector3(0.14, 0.04, 0.3))
				_bx(root, chrome, Vector3(s * (W2 * 0.985 + 0.004), belly + 0.32, zf + L * 0.5), Vector3(0.012, 0.025, L * 0.6))
			# --- rear: big wide lamps, chrome bumper, dual pipes
			_bx(root, dark, Vector3(0, trunk - 0.2, zr - 0.012), Vector3(bwr * 1.7, 0.2, 0.05))
			for s in [-1.0, 1.0]:
				var tp3 := Vector3(s * bwr * 0.58, trunk - 0.2, zr - 0.006)
				_bx(root, chrome, tp3, Vector3(0.52, 0.16, 0.04))
				_bx(root, tail_mat, tp3 + Vector3(0, 0, 0.012), Vector3(0.46, 0.1, 0.04))
				tails.append(tp3 + Vector3(0, 0, -0.04))
			_bx(root, chrome, Vector3(0, belly + 0.2, zr + 0.03), Vector3(W * 0.97, 0.12, 0.12))
			_bx(root, dark, Vector3(0, belly + 0.1, zr - 0.02), Vector3(bwr * 1.4, 0.1, 0.08))
			var ex_r4: float = 0.05 + 0.01 * int(custom.get("exhaust_level", 0))
			for s in [-1.0, 1.0]:
				_cyl(root, chrome, Vector3(s * bwr * 0.45, belly + 0.08, zr + 0.0), ex_r4, 0.16)
			_plate(root, plate_text, Vector3(0, trunk - 0.52, zr + 0.002), true)
			_plate(root, plate_text, Vector3(0, belly + 0.34, zf - 0.1), false)
	out["head_pos"] = lamps
	out["tail_pos"] = tails

## Generic customisation parts (exhaust tips are drawn by the hero builders themselves).
static func add_custom(root: Node3D, v: Dictionary, custom: Dictionary, paint: Material, dark: Material, vid: String) -> void:
	var L: float = float(v["L"])
	var W: float = float(v["W"])
	var belly: float = float(v["belly"])
	var trunk: float = float(v["trunk"])
	var wr: float = float(v["wr"])
	var wb: float = float(v["wb"])
	var tf: float = 0.5 - wb * 0.5 / L
	var tr: float = 0.5 + wb * 0.5 / L
	var bs: int = int(custom.get("bumper", 0))
	if bs >= 1:
		_bx(root, dark, Vector3(0, belly + 0.045, -L * 0.5 - 0.03), Vector3(W * 0.9, 0.06, 0.28 if bs == 1 else 0.4))
		if bs == 2:
			for side in [-1.0, 1.0]:
				_bx(root, paint, Vector3(side * W * 0.44, belly + 0.18, -L * 0.5 + 0.05), Vector3(0.05, 0.14, 0.22), Vector3(0, 0, side * 0.3))
			_bx(root, dark, Vector3(0, belly + 0.05, L * 0.5 + 0.02), Vector3(W * 0.8, 0.08, 0.2))
		else:
			_bx(root, dark, Vector3(0, belly + 0.06, L * 0.5 + 0.01), Vector3(W * 0.8, 0.06, 0.1))
	var bk: int = int(custom.get("bodykit", 0))
	if bk >= 1:
		for side in [-1.0, 1.0]:
			_bx(root, paint, Vector3(side * (CarBuilder.body_width_at(v, 0.5) + 0.01), belly + 0.06, 0.0), Vector3(0.1, 0.1, (tr - tf) * L - 0.2))
		if bk == 2:
			for side in [-1.0, 1.0]:
				for zt2 in [tf, tr]:
					var flare: MeshInstance3D = _bx(root, paint, Vector3(side * (CarBuilder.body_width_at(v, zt2) + 0.03), wr + 0.12, -L * 0.5 + zt2 * L), Vector3(0.12, 0.1, wr * 2.0 + 0.45))
					flare.rotation = Vector3(0, 0, side * 0.35)
	var sp: int = int(custom.get("spoiler", 0))
	if sp >= 1 and vid != "kestrel_r":
		var sp_h: float = trunk
		if sp == 1:
			_bx(root, paint, Vector3(0, sp_h + 0.035, L * 0.5 - 0.22), Vector3(W * 0.7, 0.05, 0.22), Vector3(0.12, 0, 0))
		else:
			var wing_h: float = 0.26 if sp == 2 else 0.4
			var wing_w: float = W * (0.82 if sp == 2 else 0.95)
			for side in [-1.0, 1.0]:
				_bx(root, dark, Vector3(side * W * 0.3, sp_h + wing_h * 0.5, L * 0.5 - 0.35), Vector3(0.05, wing_h, 0.12))
			_bx(root, paint, Vector3(0, sp_h + wing_h, L * 0.5 - 0.35), Vector3(wing_w, 0.045, 0.36 if sp == 2 else 0.45), Vector3(0.08, 0, 0))
