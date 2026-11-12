extends SceneTree
## Offline: godot --headless --path . -s tools/prepare_kart.gd     (needs res://_src/kart.glb, not shipped)
## go_kart.glb has no separate wheel nodes: the four tyres are connected components of Object_6 (front wheels, 1680 tris each),
## Object_7 (rear tyres, 960 tris each) and Object_6's 400-tri hub discs next to the rear tyres. They are split out here so the
## VehicleWheel3D physics can spin / steer them.  Output assets/vehicles/fleet/go_kart.glb: metres, nose -Z, origin on the ground
## between the axles, Body + Wheel_0..3 (0 front -X, 1 front +X, 2 rear -X, 3 rear +X).  Front tyres (r 0.12) are scaled x1.29 to
## the rear radius (0.155) because the vehicle physics uses one wheel radius.
const OUT := "res://assets/vehicles/fleet/go_kart.glb"
const FRONT_SCALE := 1.29

func _small(t: Texture2D, maxs: int) -> Texture2D:
	var img: Image = t.get_image()
	if img.is_compressed():
		img.decompress()
	var m: int = maxi(img.get_width(), img.get_height())
	if m > maxs:
		var k: float = float(maxs) / float(m)
		img.resize(maxi(4, int(img.get_width() * k)), maxi(4, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

func _initialize() -> void:
	var root: Node = WorldPrepLib.load_scene("res://_src/kart.glb")
	var rot := Basis(Vector3.UP, PI)   # source nose +Z -> -Z
	var body := {}      # material name -> Group
	var wheels: Array = [[], [], [], []]   # per wheel: Array of {g, mat}
	var mats := {}
	var rear_tyre: Array = []
	var pieces: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf: Transform3D = WorldPrepLib.world_xf(m, root)
		xf = Transform3D(rot * Basis.from_scale(Vector3.ONE * 0.01), Vector3.ZERO) * xf
		for s in range(m.mesh.get_surface_count()):
			var mat: Material = m.mesh.surface_get_material(s)
			var g := WorldPrepLib.Group.new()
			g.add(m.mesh.surface_get_arrays(s), xf, Color.WHITE)
			for c in WorldPrepLib.components(g):
				pieces.append({"obj": String(m.name), "g": c, "mat": mat, "tris": c.idx.size() / 3, "bb": c.aabb()})
	for p in pieces:
		var bb: AABB = p["bb"]
		var c: Vector3 = bb.get_center()
		var slot: int = -1
		if p["obj"] == "Object_6" and p["tris"] == 1680:
			slot = (1 if c.x > 0 else 0)                       # front tyres
		elif p["obj"] == "Object_7" and p["tris"] == 960:
			slot = (3 if c.x > 0 else 2)                       # rear tyres
			rear_tyre.append(bb)
		if slot >= 0:
			(wheels[slot] as Array).append(p)
	for p in pieces:     # rear hub discs (Object_6, 400 tris) belong to the nearest rear tyre
		if p["obj"] == "Object_6" and p["tris"] == 400:
			(wheels[3 if (p["bb"] as AABB).get_center().x > 0 else 2] as Array).append(p)
	var in_wheel := {}
	for w in wheels:
		for p in w:
			in_wheel[p] = true
	for p in pieces:
		if in_wheel.has(p):
			continue
		var mat: Material = p["mat"]
		var key: String = String(mat.resource_name)
		if not body.has(key):
			body[key] = {"mat": mat, "g": WorldPrepLib.Group.new()}
		var dg: WorldPrepLib.Group = body[key]["g"]
		var sg: WorldPrepLib.Group = p["g"]
		var b0: int = dg.v.size()
		dg.v.append_array(sg.v); dg.n.append_array(sg.n); dg.uv.append_array(sg.uv); dg.col.append_array(sg.col)
		for i in sg.idx:
			dg.idx.append(b0 + i)
	# ground / axle frame from the tyres
	var cen: Array = []
	var ground: float = 1e9
	for i in range(4):
		var bb := AABB()
		var f := true
		for p in wheels[i]:
			bb = (p["bb"] as AABB) if f else bb.merge(p["bb"])
			f = false
		cen.append(bb.get_center())
		if i >= 2:
			ground = minf(ground, bb.position.y)
	var mid := Vector3.ZERO
	for c in cen:
		mid += (c as Vector3) * 0.25
	var origin := Vector3(0.0, ground, mid.z)
	var rr: float = 0.0
	for i in [2, 3]:
		var bbr := AABB()
		var fr := true
		for p in wheels[i]:
			bbr = (p["bb"] as AABB) if fr else bbr.merge(p["bb"])
			fr = false
		rr = maxf(rr, bbr.size.y * 0.5)
	var wy: float = rr   # tyre centre height above ground (all wheels share the rear radius)
	print("KART rear radius %.3f ground %.3f centres %s" % [rr, ground, str(cen)])
	var out := Node3D.new()
	out.name = "go_kart"
	var am := ArrayMesh.new()
	for k in body.keys():
		var g: WorldPrepLib.Group = body[k]["g"]
		var g2 := WorldPrepLib.Group.new()
		for i in range(g.v.size()):
			g2.v.append(g.v[i] - origin); g2.n.append(g.n[i]); g2.uv.append(g.uv[i]); g2.col.append(g.col[i])
		g2.idx = g.idx
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = g2.v; arr[Mesh.ARRAY_NORMAL] = g2.n; arr[Mesh.ARRAY_TEX_UV] = g2.uv; arr[Mesh.ARRAY_INDEX] = g2.idx
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(am.get_surface_count() - 1, _mat(body[k]["mat"], mats))
	var bmi := MeshInstance3D.new()
	bmi.name = "Body"
	bmi.mesh = am
	out.add_child(bmi)
	bmi.owner = out
	for i in range(4):
		var wc: Vector3 = cen[i] - origin
		var wpos := Vector3(wc.x, wy, wc.z)
		var sc: float = FRONT_SCALE if i < 2 else 1.0
		var wm := ArrayMesh.new()
		var by_mat := {}
		for p in wheels[i]:
			var key: String = String((p["mat"] as Material).resource_name)
			if not by_mat.has(key):
				by_mat[key] = {"mat": p["mat"], "g": WorldPrepLib.Group.new()}
			var dg: WorldPrepLib.Group = by_mat[key]["g"]
			var sg: WorldPrepLib.Group = p["g"]
			var b0: int = dg.v.size()
			for q in range(sg.v.size()):
				dg.v.append(((sg.v[q] - origin) - wc) * sc); dg.n.append(sg.n[q]); dg.uv.append(sg.uv[q]); dg.col.append(sg.col[q])
			for q in sg.idx:
				dg.idx.append(b0 + q)
		for k in by_mat.keys():
			var g: WorldPrepLib.Group = by_mat[k]["g"]
			var arr: Array = []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = g.v; arr[Mesh.ARRAY_NORMAL] = g.n; arr[Mesh.ARRAY_TEX_UV] = g.uv; arr[Mesh.ARRAY_INDEX] = g.idx
			wm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			wm.surface_set_material(wm.get_surface_count() - 1, _mat(by_mat[k]["mat"], mats))
		var wmi := MeshInstance3D.new()
		wmi.name = "Wheel_%d" % i
		wmi.mesh = wm
		wmi.position = wpos
		out.add_child(wmi)
		wmi.owner = out
	var bb2: AABB = am.get_aabb()
	print("KART body %s wheels at %s" % [str(bb2), str([(cen[0] - origin), (cen[1] - origin), (cen[2] - origin), (cen[3] - origin)])])
	var gd := GLTFDocument.new()
	gd.set_image_format("JPEG")
	gd.lossy_quality = 0.85
	var gs := GLTFState.new()
	gd.append_from_scene(out, gs)
	gd.write_to_filesystem(gs, OUT)
	quit()

func _mat(src: Material, cache: Dictionary) -> StandardMaterial3D:
	var k: String = str(src.get_instance_id())
	if cache.has(k):
		return cache[k]
	var sm := StandardMaterial3D.new()
	sm.resource_name = src.resource_name
	if src is BaseMaterial3D:
		var bm := src as BaseMaterial3D
		sm.albedo_color = bm.albedo_color
		if bm.albedo_texture:
			sm.albedo_texture = _small(bm.albedo_texture, 1024)
		sm.cull_mode = bm.cull_mode
	sm.metallic = 0.15
	sm.roughness = 0.55
	cache[k] = sm
	return sm
