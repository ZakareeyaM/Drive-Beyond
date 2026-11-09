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

static func baked(vid: String) -> Dictionary:
	if not _cache.has(vid):
		_cache[vid] = _bake_pack(vid) if VehicleModels.is_pack(vid) else _bake(vid)
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

static func build(vid: String, custom: Dictionary) -> Dictionary:
	var data: Dictionary = baked(vid)
	if data.is_empty():
		return {}
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
	if bool(cfg.get("pack", false)):
		return cfg["collision_pack"]
	for b in cfg.get("collision", []):
		var a: Vector3 = to_car(data, b["min"])
		var c: Vector3 = to_car(data, b["max"])
		var lo := Vector3(minf(a.x, c.x), minf(a.y, c.y), minf(a.z, c.z))
		var hi := Vector3(maxf(a.x, c.x), maxf(a.y, c.y), maxf(a.z, c.z))
		res.append({"pos": (lo + hi) * 0.5, "size": hi - lo})
	return res
