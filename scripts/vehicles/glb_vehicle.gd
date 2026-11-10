class_name GlbVehicle
extends RefCounted
## Turns an external GLB car (configured in VehicleModels) into the same "model dictionary"
## that CarBuilder.build() returns, so Vehicle / showroom / garage need no model-specific code.
##
##  * The ~300 tiny meshes of the GLB are baked once (and cached) into ONE body mesh (1 surface per
##    material) plus one mesh per wheel -> a handful of draw calls instead of hundreds.
##  * Wheel pieces are found by position (see VehicleModels.wheel_seeds), re-centred on their own
##    axle pivot and returned in out["wheel_meshes"]; Vehicle parents them to its VehicleWheel3D nodes,
##    so steering, suspension travel and rolling are driven by the existing vehicle physics.
##  * Body texels of the model's paint colour are re-tinted by shaders/glb_body.gdshader, which also
##    provides the dent / wear parameters used by the existing damage system.

const BODY_SHADER := "res://shaders/glb_body.gdshader"
const PACK_SHADER := "res://shaders/pack_body.gdshader"
const FLEET_SHADER := "res://shaders/fleet_body.gdshader"
const LAMP_NAMES := ["lamp_head", "lamp_tail", "lamp_lens_front"]
static var _cache: Dictionary = {}

static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var cur: Transform3D = xf
	if n is Node3D:
		cur = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append({"mesh": (n as MeshInstance3D).mesh, "xf": cur})
	for c in n.get_children():
		_collect(c, cur, out)

static func _merge(pieces: Array, base: Transform3D) -> ArrayMesh:
	var by_mat: Dictionary = {}
	var order: Array = []
	for p in pieces:
		var m: Mesh = p["mesh"]
		for s in range(m.get_surface_count()):
			var mat: Material = m.surface_get_material(s)
			if not by_mat.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_mat[mat] = st
				order.append(mat)
			(by_mat[mat] as SurfaceTool).append_from(m, s, base * (p["xf"] as Transform3D))
	var am := ArrayMesh.new()
	for mat in order:
		(by_mat[mat] as SurfaceTool).commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mat)
	return am

static func _bake(vid: String) -> Dictionary:
	var cfg: Dictionary = VehicleModels.cfg(vid)
	var ps: PackedScene = load(String(cfg["glb"])) as PackedScene
	if ps == null:
		push_error("GlbVehicle: cannot load " + String(cfg["glb"]))
		return {}
	var inst: Node = ps.instantiate()
	var pieces: Array = []
	_collect(inst, Transform3D.IDENTITY, pieces)
	inst.free()
	var seeds: Array = cfg["wheel_seeds"]
	var r: float = float(cfg["wheel_radius"])
	var hw: float = float(cfg["wheel_half_width"])
	var wheel_pieces: Array = [[], [], [], []]
	var wheel_bb: Array = [AABB(), AABB(), AABB(), AABB()]
	var wheel_has: Array = [false, false, false, false]
	var body_pieces: Array = []
	for p in pieces:
		var bb: AABB = (p["xf"] as Transform3D) * (p["mesh"] as Mesh).get_aabb()
		var ctr: Vector3 = bb.get_center()
		var wi: int = -1
		for i in range(4):
			var s: Vector3 = seeds[i]
			if absf(ctr.x - s.x) <= hw and bb.size.x <= hw * 2.0 + 0.001 and bb.size.y <= r * 2.1 and bb.size.z <= r * 2.1 \
					and Vector2(ctr.y - s.y, ctr.z - s.z).length() <= r:
				wi = i
				break
		if wi >= 0:
			(wheel_pieces[wi] as Array).append(p)
			wheel_bb[wi] = bb if not wheel_has[wi] else (wheel_bb[wi] as AABB).merge(bb)
			wheel_has[wi] = true
		else:
			body_pieces.append(p)
	for i in range(4):
		if not wheel_has[i]:
			push_error("GlbVehicle: wheel %d of %s not found" % [i, vid])
			return {}
	var centres: Array = []
	for i in range(4):
		centres.append((wheel_bb[i] as AABB).get_center())
	var origin := Vector3(0, 0, 0)
	for c in centres:
		origin += (c as Vector3) * 0.25
	origin.y = 0.0
	var sc: float = float(cfg["scale"])
	var rot := Basis(Vector3.UP, deg_to_rad(float(cfg.get("yaw_deg", 0.0))))
	var S := Basis.from_scale(Vector3.ONE * sc)
	var base := Transform3D(rot * S, Vector3.ZERO)
	var body: ArrayMesh = _merge(body_pieces, base * Transform3D(Basis.IDENTITY, -origin))
	var wheels: Array = []
	var wheel_car: Array = []
	for i in range(4):
		var c: Vector3 = centres[i]
		wheels.append(_merge(wheel_pieces[i], base * Transform3D(Basis.IDENTITY, -c)))
		wheel_car.append(base * (c - origin))
	var wr: float = ((wheel_bb[0] as AABB).size.y * 0.5) * sc
	return {"body": body, "wheels": wheels, "origin": origin, "base": base, "wheel_car": wheel_car, "wheel_radius": wr,
			"body_tris": body_pieces.size(), "wheel_piece_counts": [wheel_pieces[0].size(), wheel_pieces[1].size(), wheel_pieces[2].size(), wheel_pieces[3].size()]}

## Traffic-pack car: the GLB was pre-split by tools/split_traffic_pack.py (Body + Wheel_0..3, metres, origin on the
## ground between the axles), so nothing has to be detected or merged at run time.
static func _bake_pack(vid: String) -> Dictionary:
	var cfg: Dictionary = VehicleModels.cfg(vid)
	var ps: PackedScene = load(String(cfg["glb"])) as PackedScene
	if ps == null:
		push_error("GlbVehicle: cannot load " + String(cfg["glb"]))
		return {}
	var inst: Node = ps.instantiate()
	var body_n: MeshInstance3D = inst.find_child("Body", true, false) as MeshInstance3D
	var wheels: Array = []
	var wcar: Array = []
	for i in range(4):
		var wn: MeshInstance3D = inst.find_child("Wheel_%d" % i, true, false) as MeshInstance3D
		if wn == null or body_n == null:
			push_error("GlbVehicle: %s is missing Body/Wheel_%d" % [vid, i])
			inst.free()
			return {}
		wheels.append(wn.mesh)
		wcar.append(wn.position)
	var body: Mesh = body_n.mesh
	inst.free()
	return {"body": body, "wheels": wheels, "origin": Vector3.ZERO, "base": Transform3D.IDENTITY, "wheel_car": wcar,
			"wheel_radius": float(Data.vehicle(vid)["wr"]), "pack": true}

## Collection car: same Body + Wheel_0..3 layout as the traffic pack, plus the lamp surfaces split into head / tail
## lamps and the lamp positions measured from that geometry.
static func _bake_fleet(vid: String) -> Dictionary:
	var d: Dictionary = _bake_pack(vid)
	if d.is_empty():
		return d
	var r: Dictionary = _split_lamps(d["body"] as ArrayMesh, vid)
	d["body"] = r["mesh"]
	d["roles"] = r["roles"]
	d["head_pos"] = r["head_pos"]
	d["tail_pos"] = r["tail_pos"]
	d["fleet"] = true
	return d

## The prepared GLB has up to three lamp surfaces (lamp_head / lamp_tail / lamp_lens_front) whose names come from the
## source materials and are not reliable about front vs rear.  Re-sort their triangles by position: front zone
## (z < 0.6 * nose) -> "head", rear zone -> "tail", anything else stays a plain dark part.  The centroids of the head /
## tail triangles (left / right of the centre line) give the real lamp positions used for the lights.
static func _split_lamps(src: ArrayMesh, vid: String) -> Dictionary:
	var bb: AABB = src.get_aabb()
	var zf: float = bb.position.z * 0.6
	var zr: float = bb.end.z * 0.6
	var am := ArrayMesh.new()
	var roles: Array = []
	var head := {"v": PackedVector3Array(), "n": PackedVector3Array()}
	var tail := {"v": PackedVector3Array(), "n": PackedVector3Array()}
	var rest := {"v": PackedVector3Array(), "n": PackedVector3Array()}
	var acc: Dictionary = {"hl": [Vector3.ZERO, 0, 1e9], "hr": [Vector3.ZERO, 0, 1e9], "tl": [Vector3.ZERO, 0, -1e9], "tr": [Vector3.ZERO, 0, -1e9]}
	var dark: Material = null
	for s in range(src.get_surface_count()):
		var mat: Material = src.surface_get_material(s)
		var nm: String = mat.resource_name if mat else ""
		if nm == "solid":
			dark = mat
		if not LAMP_NAMES.has(nm):
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(s))
			am.surface_set_material(am.get_surface_count() - 1, mat)
			roles.append(_role_of(nm, mat))
			continue
		var arr: Array = src.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if ix.is_empty():
			ix.resize(vs.size())
			for k in range(vs.size()):
				ix[k] = k
		for t in range(0, ix.size() - 2, 3):
			var a: int = ix[t]
			var b: int = ix[t + 1]
			var c: int = ix[t + 2]
			var ctr: Vector3 = (vs[a] + vs[b] + vs[c]) / 3.0
			var dst: Dictionary = rest
			if absf(ctr.x) > 0.2:
				if ctr.z < zf:
					dst = head
					_acc(acc["hl" if ctr.x < 0.0 else "hr"], vs[a], vs[b], vs[c], true)
				elif ctr.z > zr:
					dst = tail
					_acc(acc["tl" if ctr.x < 0.0 else "tr"], vs[a], vs[b], vs[c], false)
			for q in [a, b, c]:
				(dst["v"] as PackedVector3Array).append(vs[q])
				(dst["n"] as PackedVector3Array).append(ns[q] if ns.size() == vs.size() else Vector3.UP)
	var head_i: int = -1
	var tail_i: int = -1
	for pair in [["head", head], ["tail", tail], ["rest", rest]]:
		var dd: Dictionary = pair[1]
		if (dd["v"] as PackedVector3Array).is_empty():
			continue
		var a2: Array = []
		a2.resize(Mesh.ARRAY_MAX)
		a2[Mesh.ARRAY_VERTEX] = dd["v"]
		a2[Mesh.ARRAY_NORMAL] = dd["n"]
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
		var m2: Material = dark if (pair[0] == "rest" and dark != null) else StandardMaterial3D.new()
		am.surface_set_material(am.get_surface_count() - 1, m2)
		roles.append(pair[0])
	var hp: Array = [_centroid(acc["hl"], bb, true, -1.0), _centroid(acc["hr"], bb, true, 1.0)]
	var tp: Array = [_centroid(acc["tl"], bb, false, -1.0), _centroid(acc["tr"], bb, false, 1.0)]
	return {"mesh": am, "roles": roles, "head_pos": hp, "tail_pos": tp}

static func _acc(a: Array, p: Vector3, q: Vector3, r: Vector3, front: bool) -> void:
	a[0] = (a[0] as Vector3) + (p + q + r)
	a[1] = int(a[1]) + 3
	a[2] = minf(float(a[2]), minf(p.z, minf(q.z, r.z))) if front else maxf(float(a[2]), maxf(p.z, maxf(q.z, r.z)))

## lamp centre (x, y of the mean vertex; z = the outermost point of the lamp so the light sits at the lens surface).
## Falls back to proportions of the body box when a side has no lamp geometry.
static func _centroid(a: Array, bb: AABB, front: bool, side: float) -> Vector3:
	if int(a[1]) < 3:
		return Vector3(side * bb.size.x * 0.3, bb.size.y * (0.42 if front else 0.55), bb.position.z + 0.05 if front else bb.end.z - 0.05)
	var m: Vector3 = (a[0] as Vector3) / float(a[1])
	return Vector3(m.x, m.y, float(a[2]))

static func _role_of(nm: String, mat: Material) -> String:
	var l: String = nm.to_lower()
	if l == "paint":
		return "paint"
	if l.contains("glass") or l == "glass":
		return "glass"
	if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
		return "tex"
	return "other"

static func baked(vid: String) -> Dictionary:
	if not _cache.has(vid):
		if VehicleModels.is_fleet(vid):
			_cache[vid] = _bake_fleet(vid)
		elif VehicleModels.is_pack(vid):
			_cache[vid] = _bake_pack(vid)
		else:
			_cache[vid] = _bake(vid)
	return _cache[vid]

static func to_car(data: Dictionary, p: Vector3) -> Vector3:
	return (data["base"] as Transform3D) * (p - (data["origin"] as Vector3))

static func _quad_mesh(quads: Array, data: Dictionary) -> ArrayMesh:
	if quads.is_empty():
		return ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in quads:
		var a: Vector3 = to_car(data, q[0])
		var b: Vector3 = to_car(data, q[1])
		var c: Vector3 = to_car(data, q[2])
		var d: Vector3 = to_car(data, q[3])
		for v in [a, b, c, a, c, d]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()

static func _lamp_mesh(cfg: Dictionary, data: Dictionary, head: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sc: float = float(cfg["scale"])
	if bool(cfg.get("pack", false)):
		return ArrayMesh.new()   # lamps are part of the texture; the lights themselves are SpotLights at head_pos/tail_pos
	if head:
		var cm := CylinderMesh.new()
		cm.top_radius = float(cfg["head_lamp_radius"]) * sc
		cm.bottom_radius = cm.top_radius
		cm.height = 0.02 * sc
		cm.radial_segments = 10
		cm.rings = 1
		for lp in cfg["head_lamps"]:
			var t := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), to_car(data, lp))
			st.append_from(cm, 0, t)
	else:
		var bm := BoxMesh.new()
		for tl in cfg["tail_lamps"]:
			var sz: Vector3 = (tl["size"] as Vector3) * sc
			var t2 := Transform3D(Basis.from_scale(sz), to_car(data, tl["pos"]))
			st.append_from(bm, 0, t2)
	return st.commit()

static var _white_tex: ImageTexture = null

static func _white() -> ImageTexture:
	if _white_tex == null:
		var im := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		im.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(im)
	return _white_tex

static func _wheel_material(src: Material) -> Material:
	if src is BaseMaterial3D:
		var m: StandardMaterial3D = (src as BaseMaterial3D).duplicate() as StandardMaterial3D
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color.WHITE
		return m
	return src

## Collection car: surfaces are classified in _split_lamps (roles) -> paint (re-colourable, dents), glass, head / tail
## lamps (emissive, shared with the headlight / brake-light logic), textured parts (dents), everything else untouched.
static func _build_fleet(vid: String, custom: Dictionary, data: Dictionary) -> Dictionary:
	var cfg: Dictionary = VehicleModels.cfg(vid)
	var spec: Dictionary = Data.vehicle(vid)
	var root := Node3D.new()
	root.name = "Model"
	var out: Dictionary = {"root": root}
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = data["body"]
	root.add_child(body)
	out["body_mi"] = body
	var c1: Color = Data.PAINTS[int(custom.get("paint", 0)) % Data.PAINTS.size()]["c"]
	var stock: bool = int(custom.get("paint", 0)) == int(spec.get("paint", 0))
	var paint_col: Color = (cfg["paint_rgb"] as Color) if stock else c1
	var dent_arr: Array = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
	var shader: Shader = load(FLEET_SHADER)
	var tint_i: int = clampi(int(custom.get("tint", 1)), 0, 3)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.04, 0.06, 0.09, [0.6, 0.82, 0.9, 0.96][tint_i])
	glass.metallic = 0.6
	glass.roughness = 0.08
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	out["glass"] = glass
	out["glass_alpha"] = [0.6, 0.82, 0.9, 0.96]
	var hl_col: Color = Data.HEADLIGHTS[int(custom.get("headlights", 0)) % Data.HEADLIGHTS.size()]["c"]
	out["head_color"] = hl_col
	var head_mat := CarBuilder.emissive_material(hl_col, 0.6)
	var tail_mat := CarBuilder.emissive_material(Color(1.0, 0.05, 0.03), 0.5)
	out["head_mat"] = head_mat
	out["tail_mat"] = tail_mat
	var paint: ShaderMaterial = null
	var extra: Array = []
	var roles: Array = data["roles"]
	for s in range(body.mesh.get_surface_count()):
		var role: String = roles[s]
		var src: Material = body.mesh.surface_get_material(s)
		match role:
			"paint":
				var sm := ShaderMaterial.new()
				sm.shader = shader
				sm.set_shader_parameter("albedo_tex", _white())
				sm.set_shader_parameter("paint1", paint_col)
				sm.set_shader_parameter("src_rgb", Vector3(1, 1, 1))
				sm.set_shader_parameter("repaint", 1.0)
				sm.set_shader_parameter("metallic_amt", 0.55)
				sm.set_shader_parameter("dents", dent_arr)
				body.set_surface_override_material(s, sm)
				if paint == null:
					paint = sm
				else:
					extra.append(sm)
			"glass":
				body.set_surface_override_material(s, glass)
			"head":
				body.set_surface_override_material(s, head_mat)
			"tail":
				body.set_surface_override_material(s, tail_mat)
			"tex":
				var bm: BaseMaterial3D = src as BaseMaterial3D
				if bm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
					var tm := ShaderMaterial.new()
					tm.shader = shader
					tm.set_shader_parameter("albedo_tex", bm.albedo_texture)
					tm.set_shader_parameter("repaint", 0.0)
					tm.set_shader_parameter("metallic_amt", 0.0)
					tm.set_shader_parameter("dents", dent_arr)
					body.set_surface_override_material(s, tm)
					extra.append(tm)
			_:
				if src is BaseMaterial3D:
					body.set_surface_override_material(s, _wheel_material(src))
	out["paint"] = paint
	out["paint_extra"] = extra
	var gmi := MeshInstance3D.new()   # empty: keeps the "Glass" node of the other cars (showroom / tests look it up)
	gmi.name = "Glass"
	root.add_child(gmi)
	out["glass_mi"] = gmi
	out["head_pos"] = data["head_pos"]
	out["tail_pos"] = data["tail_pos"]
	var wm: Array = []
	for i in range(4):
		var wmesh: ArrayMesh = (data["wheels"] as Array)[i]
		wm.append(wmesh)
	out["wheel_meshes"] = wm
	out["wheel_materials"] = true
	CarBuilder._add_underglow(root, spec, custom, out)
	return out

static func build(vid: String, custom: Dictionary) -> Dictionary:
	var data: Dictionary = baked(vid)
	if data.is_empty():
		return {}
	if bool(data.get("fleet", false)):
		return _build_fleet(vid, custom, data)
	var cfg: Dictionary = VehicleModels.cfg(vid)
	var spec: Dictionary = Data.vehicle(vid)
	var root := Node3D.new()
	root.name = "Model"
	var out: Dictionary = {"root": root}
	# --- body ---------------------------------------------------------------------------------------
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = data["body"]
	root.add_child(body)
	out["body_mi"] = body
	var c1: Color = Data.PAINTS[int(custom.get("paint", 0)) % Data.PAINTS.size()]["c"]
	var dent_arr: Array = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
	var pack: bool = bool(cfg.get("pack", false))
	var shader: Shader = load(PACK_SHADER if pack else BODY_SHADER)
	var paint_names: Array = cfg.get("paint_materials", ["material_0"])
	var paint: ShaderMaterial = null
	var extra: Array = []
	for s in range(body.mesh.get_surface_count()):
		var src: Material = body.mesh.surface_get_material(s)
		if src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture != null:
			var sm := ShaderMaterial.new()
			sm.shader = shader
			sm.set_shader_parameter("albedo_tex", (src as BaseMaterial3D).albedo_texture)
			sm.set_shader_parameter("paint1", c1)
			sm.set_shader_parameter("dents", dent_arr)
			var is_paint: bool = paint_names.has(src.resource_name)
			if pack:   # stock paint = the model's own texture; any other colour re-tints the paint texels
				is_paint = int(custom.get("paint", 0)) != int(spec.get("paint", 0))
			sm.set_shader_parameter("repaint", 1.0 if is_paint else 0.0)
			if pack:
				var pc: Color = cfg["paint_rgb"]
				sm.set_shader_parameter("src_rgb", Vector3(pc.r, pc.g, pc.b))
			body.set_surface_override_material(s, sm)
			if is_paint and paint == null:
				paint = sm
			else:
				extra.append(sm)
	out["paint"] = paint
	out["paint_extra"] = extra
	# --- glass --------------------------------------------------------------------------------------
	var tint_i: int = clampi(int(custom.get("tint", 1)), 0, 3)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.04, 0.06, 0.09, [0.6, 0.82, 0.9, 0.96][tint_i])
	glass.metallic = 0.6
	glass.roughness = 0.08
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	out["glass"] = glass
	out["glass_alpha"] = [0.6, 0.82, 0.9, 0.96]   # open-cabin model: darker default glass hides the interior
	var gmi := MeshInstance3D.new()
	gmi.name = "Glass"
	gmi.mesh = _quad_mesh(cfg["glass"], data)
	gmi.material_override = glass
	gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(gmi)
	out["glass_mi"] = gmi
	# --- lamps --------------------------------------------------------------------------------------
	var hl_col: Color = Data.HEADLIGHTS[int(custom.get("headlights", 0)) % Data.HEADLIGHTS.size()]["c"]
	out["head_color"] = hl_col
	var head_mat := CarBuilder.emissive_material(hl_col, 0.6)
	var tail_mat := CarBuilder.emissive_material(Color(1.0, 0.05, 0.03), 0.5)
	out["head_mat"] = head_mat
	out["tail_mat"] = tail_mat
	var hm := MeshInstance3D.new()
	hm.name = "HeadLamps"
	hm.mesh = _lamp_mesh(cfg, data, true)
	hm.material_override = head_mat
	hm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(hm)
	var tm := MeshInstance3D.new()
	tm.name = "TailLamps"
	tm.mesh = _lamp_mesh(cfg, data, false)
	tm.material_override = tail_mat
	tm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(tm)
	var hp: Array = []
	for p in cfg["head_spots"]:
		hp.append(to_car(data, p))
	out["head_pos"] = hp
	var tp: Array = []
	for tl in cfg["tail_lamps"]:
		tp.append(to_car(data, tl["pos"]))
	out["tail_pos"] = tp
	out["wheel_meshes"] = data["wheels"]
	CarBuilder._add_underglow(root, spec, custom, out)
	return out

## Collision boxes (car space, metres, relative to the car origin on the ground): [{pos, size}]
static func collision_boxes(vid: String) -> Array:
	var data: Dictionary = baked(vid)
	var cfg: Dictionary = VehicleModels.cfg(vid)
	var res: Array = []
	if data.is_empty():
		return res
	if bool(cfg.get("pack", false)) or bool(cfg.get("fleet", false)):
		return cfg["collision_pack"]
	for b in cfg.get("collision", []):
		var a: Vector3 = to_car(data, b["min"])
		var c: Vector3 = to_car(data, b["max"])
		var lo := Vector3(minf(a.x, c.x), minf(a.y, c.y), minf(a.z, c.z))
		var hi := Vector3(maxf(a.x, c.x), maxf(a.y, c.y), maxf(a.z, c.z))
		res.append({"pos": (lo + hi) * 0.5, "size": hi - lo})
	return res
