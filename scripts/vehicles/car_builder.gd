class_name CarBuilder
extends RefCounted
## Procedural car models: lofted body shell + greenhouse + details.
## Forward is -Z, origin is at ground level in the middle of the car.

static func _cs(v: float, n: float) -> float:
	return signf(v) * pow(absf(v), 2.0 / n)

static func _prof(keys: Array, t: float) -> float:
	# piecewise smooth interpolation over [[t, value], ...]
	if t <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if t <= keys[i][0]:
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			var u: float = (t - a[0]) / maxf(0.0001, b[0] - a[0])
			u = u * u * (3.0 - 2.0 * u) * 0.5 + u * 0.5
			return lerpf(a[1], b[1], u)
	return keys[keys.size() - 1][1]

static func _loft_mesh(rings: Array, cap_start: bool, cap_end: bool) -> Dictionary:
	var M: int = (rings[0] as PackedVector3Array).size()
	var verts := PackedVector3Array()
	for r in rings:
		verts.append_array(r)
	var idx := PackedInt32Array()
	for i in range(rings.size() - 1):
		for j in range(M):
			var j2: int = (j + 1) % M
			var a: int = i * M + j
			var b: int = i * M + j2
			var c: int = (i + 1) * M + j
			var d: int = (i + 1) * M + j2
			idx.append(a); idx.append(c); idx.append(b)
			idx.append(b); idx.append(c); idx.append(d)
	if cap_start:
		var ctr := Vector3.ZERO
		for p in rings[0]:
			ctr += p
		ctr /= float(M)
		var ci: int = verts.size()
		verts.append(ctr)
		for j in range(M):
			idx.append(ci); idx.append(j); idx.append((j + 1) % M)
	if cap_end:
		var ctr2 := Vector3.ZERO
		var last: int = rings.size() - 1
		for p in rings[last]:
			ctr2 += p
		ctr2 /= float(M)
		var ci2: int = verts.size()
		verts.append(ctr2)
		for j in range(M):
			idx.append(ci2); idx.append(last * M + (j + 1) % M); idx.append(last * M + j)
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	for t in range(0, idx.size(), 3):
		var a2: Vector3 = verts[idx[t]]
		var n: Vector3 = (verts[idx[t + 2]] - a2).cross(verts[idx[t + 1]] - a2)
		norms[idx[t]] += n
		norms[idx[t + 1]] += n
		norms[idx[t + 2]] += n
	for i in range(norms.size()):
		norms[i] = norms[i].normalized()
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	return {"arr": arr}

static func _mesh_from(d: Dictionary) -> ArrayMesh:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, d["arr"])
	return m

static func _mi(mesh: Mesh, mat: Material, parent: Node3D, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func _box_mi(parent: Node3D, mat: Material, pos: Vector3, size: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := _mi(bm, mat, parent, pos)
	mi.rotation = rot
	return mi

static func detail_material(rough: float = 0.55, metal: float = 0.1) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.03, 0.03, 0.035)
	m.roughness = rough
	m.metallic = metal
	return m

static func emissive_material(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col * 0.4
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.roughness = 0.2
	return m

static func body_width_at(v: Dictionary, t: float) -> float:
	# never wider than the wheels can fill: keeps tyres/rims visible instead of buried in the flanks
	var W: float = minf(float(v["W"]) * 0.5, float(v["track"]) * 0.5 + float(v["ww"]) * 0.4)
	var f: float = 0.8 + 0.2 * smoothstep(0.0, 0.2, t)
	f *= 1.0 - 0.16 * smoothstep(0.8, 1.0, t)
	return W * f

static func build(vid: String, custom: Dictionary) -> Dictionary:
	var v: Dictionary = Data.vehicle(vid)
	var L: float = float(v["L"])
	var W: float = float(v["W"])
	var belly: float = float(v["belly"])
	var hood: float = float(v["hood"])
	var belt: float = float(v["belt"])
	var trunk: float = float(v["trunk"])
	var roof: float = float(v["roof"])
	var cab0: float = float(v["cab0"])
	var cab1: float = float(v["cab1"])
	var roof0: float = float(v["roof0"])
	var roof1: float = float(v["roof1"])
	var cat: String = v["cat"]
	var pickup: bool = cat == "Pickup Truck"
	var root := Node3D.new()
	root.name = "Model"
	var out: Dictionary = {"root": root}
	# ------------------------------------------------ paint + materials
	var paint := ShaderMaterial.new()
	paint.shader = load("res://shaders/car_paint.gdshader")
	var c1: Color = Data.PAINTS[int(custom.get("paint", 0)) % Data.PAINTS.size()]["c"]
	var c2: Color = Data.PAINTS[int(custom.get("paint2", 1)) % Data.PAINTS.size()]["c"]
	paint.set_shader_parameter("paint1", c1)
	paint.set_shader_parameter("paint2", c2)
	paint.set_shader_parameter("body_top", belt)
	var tt: bool = bool(custom.get("two_tone", false)) or (custom.get("paint2", 1) != custom.get("paint", 0) and int(custom.get("paint2", 1)) != 1)
	paint.set_shader_parameter("two_tone", 1.0 if tt else 0.0)
	paint.set_shader_parameter("metallic_amt", 0.35 if cat in ["Pickup Truck", "SUV", "Off-Road", "Hatchback", "Sedan"] else 0.65)
	var dent_arr: Array = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
	paint.set_shader_parameter("dents", dent_arr)
	out["paint"] = paint
	var tint_i: int = clampi(int(custom.get("tint", 1)), 0, 3)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.04, 0.06, 0.09, [0.35, 0.55, 0.78, 0.94][tint_i])
	glass.metallic = 0.75
	glass.roughness = 0.04
	glass.emission_enabled = true
	glass.emission = Color(0.03, 0.05, 0.08)
	glass.cull_mode = BaseMaterial3D.CULL_BACK
	out["glass"] = glass
	var dark := detail_material()
	var chrome := detail_material(0.25, 0.9)
	chrome.albedo_color = Color(0.7, 0.72, 0.75)
	var hl_col: Color = Data.HEADLIGHTS[int(custom.get("headlights", 0)) % Data.HEADLIGHTS.size()]["c"]
	out["head_color"] = hl_col
	var head_mat := emissive_material(hl_col, 0.6)
	var tail_mat := emissive_material(Color(1.0, 0.05, 0.03), 0.5)
	out["head_mat"] = head_mat
	out["tail_mat"] = tail_mat
	# ------------------------------------------------ body loft
	var top_keys: Array = [[0.0, hood * 0.76], [0.04, hood * 0.9], [0.1, hood], [cab0, belt * 0.985], [cab1, belt], [minf(cab1 + 0.03, 0.985), trunk], [1.0, trunk * 0.9]]
	if pickup:
		top_keys = [[0.0, hood * 0.78], [0.05, hood * 0.92], [0.1, hood], [cab0, belt * 0.985], [cab1, belt], [cab1 + 0.01, belt - 0.3], [1.0, belt - 0.32]]
	var N: int = 30
	var M: int = 20
	var rings: Array = []
	for i in range(N + 1):
		var t: float = 0.5 - 0.5 * cos(PI * float(i) / float(N))
		var z: float = -L * 0.5 + t * L
		var wv: float = body_width_at(v, t)
		var top: float = _prof(top_keys, t)
		var bot: float = belly + 0.1 * (smoothstep(0.1, 0.0, t) + smoothstep(0.9, 1.0, t))
		var e: float = 1.0
		if t < 0.03:
			e = sqrt(maxf(0.0, 1.0 - pow((0.03 - t) / 0.03, 2.0)))
		elif t > 0.97:
			e = sqrt(maxf(0.0, 1.0 - pow((t - 0.97) / 0.03, 2.0)))
		e = maxf(e, 0.14)
		var mid: float = (top + bot) * 0.5
		var hh: float = (top - bot) * 0.5 * e
		var ww: float = wv * e
		var ring := PackedVector3Array()
		for j in range(M):
			var a: float = TAU * float(j) / float(M)
			ring.append(Vector3(ww * _cs(cos(a), 5.2), mid + hh * _cs(sin(a), 4.2), z))
		rings.append(ring)
	var body_mi: MeshInstance3D = _mi(_mesh_from(_loft_mesh(rings, true, true)), paint, root)
	body_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	out["body_mi"] = body_mi
	# ------------------------------------------------ greenhouse
	var g_keys: Array = [[cab0, belt], [roof0, roof], [roof1, roof], [cab1, belt]]
	var grings: Array = []
	var GN: int = 12
	for i in range(GN + 1):
		var t2: float = lerpf(cab0, cab1, float(i) / float(GN))
		var z2: float = -L * 0.5 + t2 * L
		var wv2: float = body_width_at(v, t2) * 0.9
		var ytop: float = _prof(g_keys, t2)
		var ybot: float = belt - 0.03
		var ring2 := PackedVector3Array()
		var hgt: float = maxf(0.001, ytop - ybot)
		var topw: float = wv2 * 0.74
		var pts2: Array = [Vector2(wv2, 0.0), Vector2(wv2 * 0.97, hgt * 0.5), Vector2(topw + 0.06, hgt * 0.95), Vector2(topw * 0.5, hgt), Vector2(-topw * 0.5, hgt), Vector2(-topw - 0.06, hgt * 0.95), Vector2(-wv2 * 0.97, hgt * 0.5), Vector2(-wv2, 0.0), Vector2(-wv2 * 0.5, -0.02), Vector2(wv2 * 0.5, -0.02)]
		# order: start right-mid, go up and over the top then back under (CCW seen from +z)
		for p in pts2:
			ring2.append(Vector3(p.x, ybot + p.y, z2))
		grings.append(ring2)
	var g_mi: MeshInstance3D = _mi(_mesh_from(_loft_mesh(grings, true, true)), glass, root)
	g_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	out["glass_mi"] = g_mi
	# roof panel (paint)
	var roof_len: float = (roof1 - roof0) * L
	var roof_w: float = body_width_at(v, (roof0 + roof1) * 0.5) * 0.9 * 0.74 * 1.0
	if roof_len > 0.15:
		var rp: MeshInstance3D = _box_mi(root, paint, Vector3(0, roof + 0.005, -L * 0.5 + (roof0 + roof1) * 0.5 * L), Vector3(roof_w * 1.0, 0.045, roof_len + 0.08))
		rp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# ------------------------------------------------ details
	var wheel_z: float = float(v["wb"]) * 0.5
	var tf: float = 0.5 - wheel_z / L
	var tr: float = 0.5 + wheel_z / L
	var wr: float = float(v["wr"])
	# wheel arch shadows
	var arch_mat := StandardMaterial3D.new()
	arch_mat.albedo_color = Color(0.01, 0.01, 0.012)
	arch_mat.roughness = 1.0
	for side in [-1.0, 1.0]:
		for zt in [tf, tr]:
			var wx: float = body_width_at(v, zt) * 0.985 + 0.004
			var cyl := CylinderMesh.new()
			cyl.top_radius = wr + 0.05
			cyl.bottom_radius = wr + 0.05
			cyl.height = 0.02
			cyl.radial_segments = 20
			cyl.cap_top = true
			cyl.cap_bottom = true
			var am := _mi(cyl, arch_mat, root, Vector3(side * wx, wr, -L * 0.5 + zt * L))
			am.rotation = Vector3(0, 0, PI * 0.5)
	# door lines + handles
	for side in [-1.0, 1.0]:
		var dx: float = body_width_at(v, 0.5) * 0.995 + 0.003
		var yb: float = belly + 0.18
		var yt: float = belt - 0.05
		var d_front: float = -L * 0.5 + cab0 * L + 0.05
		var d_rear: float = -L * 0.5 + cab1 * L - (0.1 if not pickup else 0.0)
		for zz in [d_front, (d_front + d_rear) * 0.5, d_rear]:
			_box_mi(root, dark, Vector3(side * dx, (yb + yt) * 0.5, zz), Vector3(0.006, yt - yb, 0.006))
		_box_mi(root, chrome, Vector3(side * (dx + 0.005), yt - 0.14, (d_front + d_rear) * 0.5 - 0.35 * (d_rear - d_front) * 0.5), Vector3(0.02, 0.025, 0.14))
		# mirrors
		var mz: float = -L * 0.5 + (cab0 + 0.01) * L
		var mw: float = body_width_at(v, cab0)
		_box_mi(root, dark, Vector3(side * (mw * 0.9 + 0.03), belt + 0.01, mz + 0.1), Vector3(0.1, 0.03, 0.04))
		_box_mi(root, paint, Vector3(side * (mw * 0.9 + 0.09), belt + 0.05, mz + 0.1), Vector3(0.1, 0.085, 0.06))
	# grille + lower intake
	var gw: float = body_width_at(v, 0.02) * 1.2
	_box_mi(root, dark, Vector3(0, belly + (hood - belly) * 0.38, -L * 0.5 + 0.02), Vector3(gw, (hood - belly) * 0.3, 0.05))
	_box_mi(root, dark, Vector3(0, belly + 0.09, -L * 0.5 + 0.03), Vector3(gw * 1.35, 0.1, 0.05))
	# headlights
	var hx: float = body_width_at(v, 0.05) * 0.60
	var hy: float = hood - (hood - belly) * 0.26
	var hl_size := Vector3(0.30, 0.085, 0.07) * (W / 1.9)
	var head_pos: Array = []
	for side in [-1.0, 1.0]:
		# dark bezel first, lamp sits inside it and is sunk into the nose so nothing floats
		var bz: MeshInstance3D = _box_mi(root, dark, Vector3(side * hx, hy, -L * 0.5 + 0.075), hl_size + Vector3(0.05, 0.04, -0.02))
		bz.rotation = Vector3(0, side * 0.2, 0)
		var hm: MeshInstance3D = _box_mi(root, head_mat, Vector3(side * hx, hy, -L * 0.5 + 0.065), hl_size)
		hm.rotation = Vector3(0, side * 0.2, 0)
		head_pos.append(Vector3(side * hx, hy, -L * 0.5 + 0.1))
	out["head_pos"] = head_pos
	# taillights
	var tx: float = body_width_at(v, 0.95) * 0.5
	var ty: float = trunk - (trunk - belly) * 0.24
	var tail_pos: Array = []
	for side in [-1.0, 1.0]:
		# dark bezel + lamp sunk into the tail, angled to follow the rounded corner
		var tb: MeshInstance3D = _box_mi(root, dark, Vector3(side * tx, ty, L * 0.5 - 0.075), Vector3(0.3 * (W / 1.9) + 0.04, 0.09, 0.07))
		tb.rotation = Vector3(0, side * -0.1, 0)
		var tl: MeshInstance3D = _box_mi(root, tail_mat, Vector3(side * tx, ty, L * 0.5 - 0.066), Vector3(0.3 * (W / 1.9), 0.06, 0.07))
		tl.rotation = Vector3(0, side * -0.1, 0)
		tail_pos.append(Vector3(side * tx, ty, L * 0.5 - 0.1))
	if cat in ["Sports Car", "Supercar", "Hypercar", "Muscle Car"]:
		_box_mi(root, tail_mat, Vector3(0, ty, L * 0.5 - 0.06), Vector3(maxf(tx * 2.0 - 0.45, 0.1), 0.03, 0.05))
	# dark lower rear valance (matches the front intake band) ties bumper, plate and exhausts together
	_box_mi(root, dark, Vector3(0, belly + 0.14, L * 0.5 - 0.06), Vector3(body_width_at(v, 0.96) * 1.5, 0.2, 0.07))
	out["tail_pos"] = tail_pos
	# plates
	var plate_text: String = String(custom.get("plate", "DB-001"))
	for zsgn in [1.0, -1.0]:
		var pz: float = zsgn * (L * 0.5 + 0.005)
		var plate := _box_mi(root, emissive_material(Color(0.95, 0.95, 0.9), 0.15), Vector3(0, belly + 0.26 if zsgn < 0 else belly + 0.40, pz - zsgn * 0.03), Vector3(0.5, 0.12, 0.02))
		var lab := Label3D.new()
		lab.text = plate_text
		lab.font_size = 48
		lab.pixel_size = 0.0023
		lab.modulate = Color(0.05, 0.05, 0.1)
		lab.outline_size = 0
		lab.position = Vector3(0, 0, 0.008 * zsgn)
		lab.rotation = Vector3(0, 0 if zsgn > 0 else PI, 0)
		lab.double_sided = false
		plate.add_child(lab)
	# exhausts
	var ex_lvl: int = int(custom.get("exhaust_level", 0))
	var ex_r: float = 0.045 + 0.012 * ex_lvl
	for side in [-1.0, 1.0]:
		var ec := CylinderMesh.new()
		ec.top_radius = ex_r
		ec.bottom_radius = ex_r
		ec.height = 0.16
		var em := _mi(ec, chrome, root, Vector3(side * W * 0.25, belly + 0.09, L * 0.5 - 0.03))
		em.rotation = Vector3(PI * 0.5, 0, 0)
	# front/rear bumper styles
	var bs: int = int(custom.get("bumper", 0))
	if bs >= 1:
		_box_mi(root, dark, Vector3(0, belly + 0.045, -L * 0.5 - 0.03), Vector3(W * 0.9, 0.06, 0.28 if bs == 1 else 0.4))
		if bs == 2:
			for side in [-1.0, 1.0]:
				_box_mi(root, paint, Vector3(side * W * 0.44, belly + 0.18, -L * 0.5 + 0.05), Vector3(0.05, 0.14, 0.22), Vector3(0, 0, side * 0.3))
			_box_mi(root, dark, Vector3(0, belly + 0.05, L * 0.5 + 0.02), Vector3(W * 0.8, 0.08, 0.2))
		else:
			_box_mi(root, dark, Vector3(0, belly + 0.06, L * 0.5 + 0.01), Vector3(W * 0.8, 0.06, 0.1))
	# body kits
	var bk: int = int(custom.get("bodykit", 0))
	if bk >= 1:
		for side in [-1.0, 1.0]:
			_box_mi(root, paint, Vector3(side * (body_width_at(v, 0.5) + 0.01), belly + 0.06, 0.0), Vector3(0.1, 0.1, (tr - tf) * L - 0.2))
		if bk == 2:
			for side in [-1.0, 1.0]:
				for zt2 in [tf, tr]:
					var flare := _box_mi(root, paint, Vector3(side * (body_width_at(v, zt2) + 0.03), wr + 0.12, -L * 0.5 + zt2 * L), Vector3(0.12, 0.1, wr * 2.0 + 0.45))
					flare.rotation = Vector3(0, 0, side * 0.35)
	# spoilers
	var sp: int = int(custom.get("spoiler", 0))
	var sp_h: float = trunk
	if sp == 1:
		_box_mi(root, paint, Vector3(0, sp_h + 0.035, L * 0.5 - 0.22), Vector3(W * 0.7, 0.05, 0.22), Vector3(0.12, 0, 0))
	elif sp >= 2:
		var wing_h: float = 0.26 if sp == 2 else 0.4
		var wing_w: float = W * (0.82 if sp == 2 else 0.95)
		for side in [-1.0, 1.0]:
			_box_mi(root, dark, Vector3(side * W * 0.3, sp_h + wing_h * 0.5, L * 0.5 - 0.35), Vector3(0.05, wing_h, 0.12))
		_box_mi(root, paint, Vector3(0, sp_h + wing_h, L * 0.5 - 0.35), Vector3(wing_w, 0.045, 0.36 if sp == 2 else 0.45), Vector3(0.08, 0, 0))
		for side in [-1.0, 1.0]:
			_box_mi(root, dark, Vector3(side * wing_w * 0.5, sp_h + wing_h + 0.04, L * 0.5 - 0.35), Vector3(0.03, 0.14, 0.45))
	# category extras
	if cat == "Muscle Car":
		_box_mi(root, dark, Vector3(0, hood + 0.05, -L * 0.5 + 0.28 * L), Vector3(0.5, 0.1, 0.75))
		_box_mi(root, chrome, Vector3(0, belly + 0.08, -L * 0.5 - 0.02), Vector3(W * 0.95, 0.05, 0.06))
	elif cat in ["Supercar", "Hypercar"]:
		for side in [-1.0, 1.0]:
			_box_mi(root, dark, Vector3(side * (body_width_at(v, 0.62) + 0.005), belly + (belt - belly) * 0.55, -L * 0.5 + 0.62 * L), Vector3(0.04, 0.16, 0.55))
		_box_mi(root, dark, Vector3(0, trunk + 0.01, L * 0.5 - 0.5), Vector3(W * 0.5, 0.02, 0.5))
	elif cat == "SUV" or cat == "Off-Road":
		for side in [-1.0, 1.0]:
			_box_mi(root, dark, Vector3(side * roof_w * 0.45, roof + 0.05, -L * 0.5 + (roof0 + roof1) * 0.5 * L), Vector3(0.04, 0.05, roof_len * 0.9))
		if cat == "Off-Road":
			_box_mi(root, dark, Vector3(0, roof + 0.18, -L * 0.5 + (roof0 + roof1) * 0.5 * L), Vector3(roof_w * 0.95, 0.04, roof_len * 0.85))
			for side in [-1.0, 1.0]:
				_box_mi(root, dark, Vector3(side * roof_w * 0.45, roof + 0.1, -L * 0.5 + (roof0 + roof1) * 0.5 * L), Vector3(0.03, 0.12, roof_len * 0.85))
			_box_mi(root, dark, Vector3(0, belly + 0.2, -L * 0.5 - 0.08), Vector3(W * 0.7, 0.07, 0.1))
			_box_mi(root, dark, Vector3(0, hood + 0.0, L * 0.5 + 0.05), Vector3(0.05, 0.05, 0.05))
	elif pickup:
		var bed_z0: float = -L * 0.5 + cab1 * L
		var bed_len: float = L * 0.5 - bed_z0 - 0.02
		var wall_y: float = belt - 0.32
		for side in [-1.0, 1.0]:
			_box_mi(root, paint, Vector3(side * (body_width_at(v, 0.8) - 0.04), wall_y + 0.2, bed_z0 + bed_len * 0.5), Vector3(0.08, 0.4, bed_len))
		_box_mi(root, paint, Vector3(0, wall_y + 0.2, L * 0.5 - 0.04), Vector3(body_width_at(v, 0.95) * 2.0 - 0.1, 0.4, 0.06))
		_box_mi(root, paint, Vector3(0, wall_y + 0.2, bed_z0 + 0.04), Vector3(body_width_at(v, 0.7) * 2.0 - 0.1, 0.4, 0.06))
		_box_mi(root, dark, Vector3(0, wall_y + 0.02, bed_z0 + bed_len * 0.5), Vector3(body_width_at(v, 0.8) * 2.0 - 0.18, 0.02, bed_len - 0.1))
	elif cat == "Hatchback":
		_box_mi(root, paint, Vector3(0, roof - 0.01, -L * 0.5 + cab1 * L - 0.08), Vector3(roof_w * 0.9, 0.04, 0.28), Vector3(0.1, 0, 0))
	# underglow
	var ug_i: int = int(custom.get("underglow", 0))
	var ug_col: Color = Data.UNDERGLOWS[ug_i % Data.UNDERGLOWS.size()]["c"]
	var ug := Node3D.new()
	ug.name = "Underglow"
	var ug_mat := StandardMaterial3D.new()
	ug_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ug_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ug_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ug_mat.albedo_color = Color(ug_col.r, ug_col.g, ug_col.b, 0.55)
	var ug_plane := PlaneMesh.new()
	ug_plane.size = Vector2(W * 1.15, L * 1.05)
	var ug_mi := _mi(ug_plane, ug_mat, ug, Vector3(0, 0.07, 0))
	ug_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ug_light := OmniLight3D.new()
	ug_light.light_color = ug_col
	ug_light.omni_range = 4.5
	ug_light.light_energy = 1.4
	ug_light.position = Vector3(0, 0.25, 0)
	ug.add_child(ug_light)
	ug.visible = ug_i > 0
	root.add_child(ug)
	out["underglow"] = ug
	return out

## One wheel visual: tyre + rim. Axis along X.
static func build_wheel(vid: String, custom: Dictionary) -> MeshInstance3D:
	var v: Dictionary = Data.vehicle(vid)
	var wr: float = float(v["wr"])
	var ww: float = float(v["ww"])
	var rim_style: int = int(custom.get("rims", 0))
	var rim_col: Color = Data.PAINTS[int(custom.get("wheel_color", 8)) % Data.PAINTS.size()]["c"]
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	MeshLib.add_wheel_disc(st, Vector3.ZERO, wr, ww, 22, Color(0.07, 0.07, 0.075))
	st.commit(mesh)
	var rst := SurfaceTool.new()
	rst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rr: float = wr * (0.66 if v["cat"] != "Off-Road" else 0.56)
	var hx: float = ww * 0.5 + 0.004
	MeshLib.add_wheel_disc(rst, Vector3(0, 0, 0), rr, ww * 0.99, 20, rim_col.lerp(Color(0.8, 0.82, 0.86), 0.45) * 0.8)
	var spoke_col: Color = rim_col.lerp(Color(0.85, 0.87, 0.9), 0.5)
	var spokes: int = [5, 5, 12, 8][clampi(rim_style, 0, 3)]
	var spoke_w: float = [0.06, 0.07, 0.022, 0.04][clampi(rim_style, 0, 3)]
	for i in range(spokes):
		var a: float = TAU * float(i) / float(spokes)
		var dir := Vector3(0, cos(a), sin(a))
		var side := Vector3(0, -dir.z, dir.y)
		var twist: float = 0.0 if rim_style != 3 else 0.35
		var tip: Vector3 = dir * rr * 0.96 + side * twist * rr * 0.3
		for fs in [1.0, -1.0]:
			var base := Vector3(hx * fs, 0, 0)
			var p0: Vector3 = base + dir * rr * 0.16 - side * spoke_w
			var p1: Vector3 = base + dir * rr * 0.16 + side * spoke_w
			var p2: Vector3 = base + tip + side * spoke_w * 0.8
			var p3: Vector3 = base + tip - side * spoke_w * 0.8
			MeshLib.quad(rst, p0, p3, p2, p1, spoke_col)
			MeshLib.quad(rst, p1, p2, p3, p0, spoke_col)
	# hub cap
	for fs2 in [1.0, -1.0]:
		MeshLib.add_wheel_disc(rst, Vector3(hx * fs2, 0, 0), rr * 0.2, 0.02, 10, spoke_col)
	rst.commit(mesh)
	var tyre := StandardMaterial3D.new()
	tyre.vertex_color_use_as_albedo = true
	tyre.roughness = 0.92
	var rim := StandardMaterial3D.new()
	rim.vertex_color_use_as_albedo = true
	rim.metallic = 0.85
	rim.roughness = 0.28
	mesh.surface_set_material(0, tyre)
	mesh.surface_set_material(1, rim)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
