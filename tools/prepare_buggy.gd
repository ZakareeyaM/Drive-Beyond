extends SceneTree
## Offline:  godot --headless --path . -s tools/prepare_buggy.gd -- dune [dry]     (needs res://_src/dune.glb / scifi.glb, not shipped)
## Turns the supplied off-road buggy GLBs into game-ready GLBs  assets/vehicles/fleet/<id>.glb  (metres, nose -Z, origin on the ground
## between the axles, Body + Wheel_0..3 with 0 front -X, 1 front +X, 2 rear -X, 3 rear +X) - the same layout the other fleet cars use.
## Neither source has separate wheel nodes: every wheel is a cluster of small components (tyre, rim, hub, brake) of several meshes, found
## here by proximity to the four wheel centres.  Wheels are re-centred on the axle so the physics wheel can spin and steer them.
const CFG := {
	"dune": {"src": "res://_src/dune.glb", "fwd": Vector3(-0.633, 0.0, 0.773), "scale": 0.07,
		# measured wheel centres in the ALIGNED frame (metres): 0 front -X, 1 front +X, 2 rear -X, 3 rear +X
		"wc": [Vector3(-0.67, -0.21, -1.04), Vector3(0.87, -0.21, -1.04), Vector3(-0.67, -0.07, 1.30), Vector3(0.87, -0.07, 1.30)],
		"wr": [0.35, 0.35, 0.49, 0.49], "front_scale": 1.4, "out": "res://assets/vehicles/fleet/dune_buggy.glb", "name": "dune_buggy"},
	# sci-fi buggy: source is ~1 unit = 1 m but toy sized (1.44 x 0.65 x 2.0), nose is +Z (bumper plate + windscreen), big tyres at the REAR
	"scifi": {"src": "res://_src/scifi.glb", "fwd": Vector3(0.0, 0.0, 1.0), "scale": 1.4,
		"wc_src": [Vector3(0.53, -0.10, 0.69), Vector3(-0.53, -0.10, 0.69), Vector3(0.59, -0.07, -0.75), Vector3(-0.59, -0.07, -0.75)],   # source frame: front pair (z +0.69), rear pair (z -0.75)
		"wr": [0.315, 0.315, 0.35, 0.35], "front_scale": 1.111, "dx": 0.17, "decim": 0.2,
		"out": "res://assets/vehicles/fleet/scifi_buggy.glb", "name": "scifi_buggy"},
}

func _initialize() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var id: String = a[0]
	var dry: bool = a.size() > 1 and a[1] == "dry"
	var cfg: Dictionary = CFG[id]
	var root: Node = WorldPrepLib.load_scene(cfg["src"])
	var rot := Basis(Vector3.UP, (cfg["fwd"] as Vector3).normalized().signed_angle_to(Vector3(0, 0, -1), Vector3.UP))
	var k: float = cfg["scale"]
	var xform := Transform3D(rot * Basis.from_scale(Vector3.ONE * k), Vector3.ZERO)
	var wc: Array = []
	if cfg.has("wc_src"):
		for w in cfg["wc_src"]:
			wc.append(xform * (w as Vector3))
	else:
		wc = cfg["wc"]
	var dxm: float = float(cfg.get("dx", 0.2))
	var pieces: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf: Transform3D = xform * WorldPrepLib.world_xf(m, root)
		for s in range(m.mesh.get_surface_count()):
			var g := WorldPrepLib.Group.new()
			g.add(m.mesh.surface_get_arrays(s), xf, Color.WHITE)
			for c in WorldPrepLib.components(g):
				var tn: int = c.idx.size() / 3
				if cfg.has("decim") and tn > 600:
					WorldPrepLib.decimate(c, 600 + int((tn - 600) * float(cfg["decim"])))
				pieces.append({"obj": String(m.name), "g": c, "mat": m.mesh.surface_get_material(s), "bb": c.aabb()})
	print("BUGGY aligned wheel centres: ", wc)
	var wheels: Array = [[], [], [], []]
	for p in pieces:
		var c: Vector3 = (p["bb"] as AABB).get_center()
		var best := -1
		var bd := 1e9
		for i in range(4):
			var d: float = Vector2((c - wc[i]).y, (c - wc[i]).z).length()    # distance in the wheel plane (axle along X)
			if absf((c - wc[i]).x) >= dxm:
				continue
			if d < bd:
				bd = d
				best = i
		var bs: Vector3 = (p["bb"] as AABB).size
		var r: float = float(cfg["wr"][best])
		if bd < r * 1.1 and absf((c - wc[best]).x) < dxm and bs.y < r * 2.3 and bs.z < r * 2.3 and bs.x < 0.35:
			(wheels[best] as Array).append(p)
	for i in range(4):
		var bb := AABB()
		var f := true
		var tris := 0
		for p in wheels[i]:
			bb = (p["bb"] as AABB) if f else bb.merge(p["bb"])
			f = false
			tris += (p["g"] as WorldPrepLib.Group).idx.size() / 3
		print("BUGGY wheel %d: pieces %d tris %d c=%s size=%s" % [i, wheels[i].size(), tris, str(bb.get_center()), str(bb.size)])
	if dry:
		for p in pieces:
			var b2: AABB = p["bb"]
			if b2.size.y > 0.45 and b2.size.z > 0.45 and b2.size.x < 0.5:
				print("BUGGY disc %s tris=%d c=(%.2f,%.2f,%.2f) s=(%.2f,%.2f,%.2f)" % [p["obj"], (p["g"] as WorldPrepLib.Group).idx.size() / 3, b2.get_center().x, b2.get_center().y, b2.get_center().z, b2.size.x, b2.size.y, b2.size.z])
		for p in []:
			var b: AABB = p["bb"]
			print("BUGGY w0 piece %s tris=%d c=(%.2f,%.2f,%.2f) s=(%.2f,%.2f,%.2f)" % [p["obj"], (p["g"] as WorldPrepLib.Group).idx.size() / 3, b.get_center().x, b.get_center().y, b.get_center().z, b.size.x, b.size.y, b.size.z])
	var tot := AABB()
	var f2 := true
	for p in pieces:
		tot = (p["bb"] as AABB) if f2 else tot.merge(p["bb"])
		f2 = false
	print("BUGGY total aabb ", tot)
	if not dry:
		_write(cfg, pieces, wheels, wc, tot)
	quit()

func _small(t: Texture2D, maxs: int) -> Texture2D:
	var img: Image = t.get_image()
	if img.is_compressed():
		img.decompress()
	var m: int = maxi(img.get_width(), img.get_height())
	if m > maxs:
		var kk: float = float(maxs) / float(m)
		img.resize(maxi(4, int(img.get_width() * kk)), maxi(4, int(img.get_height() * kk)), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

func _mat(src: Material, cache: Dictionary) -> StandardMaterial3D:
	var key: String = str(src.get_instance_id())
	if cache.has(key):
		return cache[key]
	var sm := StandardMaterial3D.new()
	sm.resource_name = src.resource_name
	if src is BaseMaterial3D:
		var bm := src as BaseMaterial3D
		sm.albedo_color = bm.albedo_color
		if bm.albedo_texture:
			sm.albedo_texture = _small(bm.albedo_texture, 1024)
		sm.cull_mode = bm.cull_mode
		sm.transparency = bm.transparency
	sm.metallic = 0.1
	sm.roughness = 0.6
	cache[key] = sm
	return sm

func _append(dst: Dictionary, p: Dictionary, off: Vector3, wcen: Vector3, sc: float) -> void:
	var key: String = String((p["mat"] as Material).resource_name) + str((p["mat"] as Material).get_instance_id())
	if not dst.has(key):
		dst[key] = {"mat": p["mat"], "g": WorldPrepLib.Group.new()}
	var dg: WorldPrepLib.Group = dst[key]["g"]
	var sg: WorldPrepLib.Group = p["g"]
	var b0: int = dg.v.size()
	for q in range(sg.v.size()):
		dg.v.append(((sg.v[q] - off) - wcen) * sc); dg.n.append(sg.n[q]); dg.uv.append(sg.uv[q]); dg.col.append(sg.col[q])
	for q in sg.idx:
		dg.idx.append(b0 + q)

func _mesh(groups: Dictionary, mats: Dictionary) -> ArrayMesh:
	var am := ArrayMesh.new()
	for key in groups.keys():
		var g: WorldPrepLib.Group = groups[key]["g"]
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = g.v; arr[Mesh.ARRAY_NORMAL] = g.n; arr[Mesh.ARRAY_TEX_UV] = g.uv; arr[Mesh.ARRAY_INDEX] = g.idx
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(am.get_surface_count() - 1, _mat(groups[key]["mat"], mats))
	return am

func _write(cfg: Dictionary, pieces: Array, wheels: Array, wc: Array, tot: AABB) -> void:
	var in_wheel := {}
	for w in wheels:
		for p in w:
			in_wheel[p] = true
	var mid_x: float = (float((wc[0] as Vector3).x) + float((wc[1] as Vector3).x)) * 0.5
	var ground: float = tot.position.y
	var origin := Vector3(mid_x, ground, ((wc[0] as Vector3).z + (wc[2] as Vector3).z) * 0.5)
	var rr: float = float(cfg["wr"][2])
	var mats := {}
	var body := {}
	for p in pieces:
		if not in_wheel.has(p):
			_append(body, p, origin, Vector3.ZERO, 1.0)
	var out := Node3D.new()
	out.name = String(cfg["name"])
	var bmi := MeshInstance3D.new()
	bmi.name = "Body"
	bmi.mesh = _mesh(body, mats)
	out.add_child(bmi)
	bmi.owner = out
	for i in range(4):
		var wcen: Vector3 = (wc[i] as Vector3)
		var sc: float = float(cfg["front_scale"]) if i < 2 else 1.0
		var wg := {}
		for p in wheels[i]:
			_append(wg, p, origin, wcen - origin, sc)
		var wmi := MeshInstance3D.new()
		wmi.name = "Wheel_%d" % i
		wmi.mesh = _mesh(wg, mats)
		wmi.position = Vector3(wcen.x - origin.x, rr, wcen.z - origin.z)
		out.add_child(wmi)
		wmi.owner = out
	print("BUGGY body aabb ", (bmi.mesh as ArrayMesh).get_aabb(), " ground ", ground)
	var gd := GLTFDocument.new()
	gd.set_image_format("JPEG")
	gd.lossy_quality = 0.85
	var gs := GLTFState.new()
	gd.append_from_scene(out, gs)
	gd.write_to_filesystem(gs, String(cfg["out"]))
	print("BUGGY wrote ", cfg["out"])
