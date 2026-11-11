extends SceneTree
## godot --headless --path . -s tools/prepare_world.gd -- <job> [<job>...]   jobs: signal
## Converts the raw world-expansion GLBs (res://_src/*.glb) into lean meshes under assets/world/.
const L := preload("res://tools/world_prep_lib.gd")

func _initialize() -> void:
	for j in OS.get_cmdline_user_args():
		await call("_job_" + j)
	quit()

func _disc(c: Vector3, r: float, g: Object) -> void:
	var base: int = g.v.size()
	g.v.append(c); g.n.append(Vector3.BACK); g.uv.append(Vector2.ZERO); g.col.append(Color.WHITE)
	for i in range(10):
		var a: float = TAU * float(i) / 10.0
		g.v.append(c + Vector3(cos(a) * r, sin(a) * r, 0)); g.n.append(Vector3.BACK); g.uv.append(Vector2.ZERO); g.col.append(Color.WHITE)
	for i in range(10):
		g.idx.append(base); g.idx.append(base + 1 + (i + 1) % 10); g.idx.append(base + 1 + i)

## Traffic_signals.glb: pole + mast arm + horizontal head + vertical head + street lamp (variant "_002"); the sign boards are
## dropped, the three lens colours become flat discs (driven by the traffic-light state at runtime)
func _job_signal() -> void:
	var root: Node = L.load_scene("res://_src/Traffic_signals.glb")
	var per := {}
	var origin := Vector3.ZERO
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.get_parent().name.ends_with("_002"):
			continue
		var mn: String = m.mesh.surface_get_material(0).resource_name
		if not per.has(mn):
			per[mn] = L.Group.new()
		var xf: Transform3D = L.world_xf(m, root)
		per[mn].add(m.mesh.surface_get_arrays(0), xf, L.base_color(m.mesh.surface_get_material(0)))
		if mn == "Material.001" and m.get_aabb().size.y > 5.0 or (mn == "Material.001" and (xf * m.get_aabb()).size.y > 9.0):
			var bb: AABB = xf * m.get_aabb()
			origin = Vector3(bb.get_center().x, bb.position.y, bb.get_center().z)
	var body := L.Group.new()
	var lens := {"r": L.Group.new(), "y": L.Group.new(), "g": L.Group.new()}
	for mn in per:
		var comps: Array = L.components(per[mn])
		for c in comps:
			var bb: AABB = c.aabb()
			var ctr: Vector3 = bb.get_center() - origin
			if mn in ["sign_red", "sign_white", "sign_black", "Material.004"]:
				continue
			if mn == "military_green.001" and bb.size.z < 0.02 and bb.size.x > 0.3 and bb.size.y > 0.3:
				continue   # flat sign backings
			if mn == "red_glass" or mn == "yellow_glass":
				var horiz: bool = (bb.get_center().y > 6.5)
				var key: String = "y"
				if mn == "red_glass":
					# horizontal head: red = the left-most lens seen from the front (-X), green = the one next to the pole
					# vertical head: red = top, green = bottom
					var rel_x: float = ctr.x
					key = ("r" if rel_x < -4.9 else "g") if horiz else ("r" if ctr.y > 5.8 else "g")
				_disc(Vector3(ctr.x, ctr.y, bb.position.z + bb.size.z - origin.z + 0.004), 0.135, lens[key])
				continue
			var col: Color = L.base_color(per[mn] if false else null)
			for i in range(c.col.size()):
				pass
			body.add(_arrays_of(c), Transform3D.IDENTITY, _mat_col(mn))
	for g in [body]:
		for i in range(g.v.size()):
			g.v[i] -= origin
	print("signal pre tris body ", body.tris())
	L.decimate(body, 1400)
	print("signal tris body ", body.tris(), " discs ", lens["r"].tris(), " origin ", origin)
	ResourceSaver.save(L.to_mesh(body), "res://assets/world/signal_body.res")
	for k in lens:
		ResourceSaver.save(L.to_mesh(lens[k], false), "res://assets/world/signal_lens_%s.res" % k)
	print(body.aabb())

func _arrays_of(g: Object) -> Array:
	var a: Array = []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = g.v; a[Mesh.ARRAY_NORMAL] = g.n; a[Mesh.ARRAY_TEX_UV] = g.uv; a[Mesh.ARRAY_INDEX] = g.idx
	return a

func _mat_col(mn: String) -> Color:
	var cols := {"military_green": Color(0.2, 0.24, 0.17), "military_green.001": Color(0.21, 0.22, 0.16), "Material.001": Color(0.27, 0.3, 0.23),
		"Material.008": Color(0.65, 0.65, 0.65), "tunnel": Color(0.03, 0.03, 0.03), "Material.003": Color(0.85, 0.85, 0.85),
		"Material.006": Color(0.16, 0.15, 0.13), "Material.007": Color(0.08, 0.08, 0.08), "street_lamp": Color(0.74, 0.65, 0.5),
		"street_lamp_reflector_bowl": Color(0.9, 0.9, 0.9), "Material.011": Color(0.9, 0.9, 0.9)}
	return cols.get(mn, Color(0.4, 0.4, 0.4))

## stylized_palm_tree.glb -> one vertex-coloured mesh (texture sampled per vertex), ~6.5 m tall, origin at the trunk foot
func _job_palm() -> void:
	var root: Node = L.load_scene("res://_src/stylized_palm_tree.glb")
	var g := L.Group.new()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in range(m.mesh.get_surface_count()):
			var mat: Material = m.mesh.surface_get_material(s)
			var img: Image = null
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
				img = ((mat as BaseMaterial3D).albedo_texture as Texture2D).get_image()
				if img.is_compressed():
					img.decompress()
			var start: int = g.v.size()
			g.add(m.mesh.surface_get_arrays(s), L.world_xf(m, root), Color.WHITE)
			if img != null:
				for i in range(start, g.v.size()):
					var uv: Vector2 = g.uv[i]
					var px: int = clampi(int(fposmod(uv.x, 1.0) * img.get_width()), 0, img.get_width() - 1)
					var py: int = clampi(int(fposmod(uv.y, 1.0) * img.get_height()), 0, img.get_height() - 1)
					g.col[i] = img.get_pixel(px, py)
	var bb: AABB = g.aabb()
	print("palm raw aabb ", bb, " tris ", g.tris())
	var k: float = 6.5 / bb.size.y
	var foot := Vector3(bb.get_center().x, bb.position.y, bb.get_center().z)
	# trunk foot = centroid of the lowest vertices
	var low := Vector3.ZERO
	var nl: int = 0
	for v in g.v:
		if v.y < bb.position.y + bb.size.y * 0.05:
			low += v
			nl += 1
	if nl > 0:
		foot = Vector3(low.x / nl, bb.position.y, low.z / nl)
	for i in range(g.v.size()):
		g.v[i] = (g.v[i] - foot) * k
	print("palm final aabb ", g.aabb())
	var am: ArrayMesh = L.to_mesh(g)
	ResourceSaver.save(am, "res://assets/world/palm.res")

# ------------------------------------------------------------------------------------------------ buildings
const BIZ := {   # id -> [mesh-name prefix, tri budget]
	"biz_restaurant": ["Restaurant", 3000], "biz_shop": ["Shop", 2500], "biz_pizza": ["Pizza", 2600], "biz_burger": ["Burger", 3500],
	"biz_cafe": ["Cafe", 4200], "biz_mall": ["ShoppingCenter", 6000], "biz_cinema": ["Cinema", 3500],
}
const ACC := {"acc_1": 4500, "acc_2": 4000, "acc_3": 2500, "acc_4": 2500, "acc_5": 2500, "acc_6": 2500, "acc_7": 2500, "acc_8": 3000, "acc_9": 4500, "acc_10": 4500}

func _pack_material(root: Node, atlas_name: String) -> StandardMaterial3D:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: Material = (mi as MeshInstance3D).mesh.surface_get_material(0)
		if m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture != null:
			var img: Image = ((m as BaseMaterial3D).albedo_texture as Texture2D).get_image()
			if img.is_compressed():
				img.decompress()
			print(atlas_name, " atlas ", img.get_size())
			var mx: int = maxi(img.get_width(), img.get_height())
			if mx > 1024:
				var k: float = 1024.0 / float(mx)
				img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
			var nm := StandardMaterial3D.new()
			nm.albedo_texture = ImageTexture.create_from_image(img)
			nm.roughness = 1.0
			nm.metallic_specular = 0.1
			nm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			ResourceSaver.save(nm, "res://assets/world/bld/%s_mat.res" % atlas_name)
			return nm
	return null

func _save_building(id: String, g: Object, scale: float, mat_path: String, sizes: Dictionary) -> void:
	for i in range(g.v.size()):
		g.v[i] *= scale
	var bb: AABB = g.aabb()
	var org := Vector3(bb.get_center().x, bb.position.y, bb.get_center().z)
	for i in range(g.v.size()):
		g.v[i] -= org
	var before: int = g.tris()
	L.decimate(g, int(sizes[id]))
	var am: ArrayMesh = L.to_mesh(g, false, true)
	var mat: Material = load(mat_path)
	am.surface_set_material(0, mat)
	var root3 := Node3D.new()
	root3.name = id
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = am
	root3.add_child(mi)
	mi.owner = root3
	var ps := PackedScene.new()
	ps.pack(root3)
	ResourceSaver.save(ps, "res://assets/world/bld/%s.tscn" % id)
	var sz: Vector3 = g.aabb().size
	print("BLD ", id, " tris ", before, "->", g.tris(), "  \"", id, "\": {\"w\": ", snappedf(sz.x, 0.01), ", \"h\": ", snappedf(sz.y, 0.01), ", \"d\": ", snappedf(sz.z, 0.01), "},")

func _job_biz() -> void:
	var root: Node = L.load_scene("res://_src/low_poly_business_buildings_pack.glb")
	_pack_material(root, "biz")
	var budgets := {}
	for id in BIZ:
		budgets[id] = BIZ[id][1]
	for id in BIZ:
		var g := L.Group.new()
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.name.begins_with(String(BIZ[id][0])) and not m.name.begins_with("Collider") and (String(BIZ[id][0]) != "Shop" or not m.name.begins_with("ShoppingCenter")):
				for s in range(m.mesh.get_surface_count()):
					g.add(m.mesh.surface_get_arrays(s), L.world_xf(m, root), Color.WHITE)
		_save_building(id, g, 2.3, "res://assets/world/bld/biz_mat.res", budgets)

func _job_acc() -> void:
	var root: Node = L.load_scene("res://_src/low_poly_accommodations_buildings.glb")
	_pack_material(root, "acc")
	for i in range(1, 11):
		var id := "acc_%d" % i
		var g := L.Group.new()
		for mi in root.find_children("PublicBuilding_%d_*" % i, "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for s in range(m.mesh.get_surface_count()):
				g.add(m.mesh.surface_get_arrays(s), L.world_xf(m, root), Color.WHITE)
		_save_building(id, g, 2.2, "res://assets/world/bld/acc_mat.res", ACC)

# ------------------------------------------------------------------------------------------------ airport
# id -> [visual mesh name, collider mesh name, tri budget, collider mode]. Everything keeps its position from the pack
# (the pack lays terminal / planes / vehicles out as one apron), only the origin of each piece moves to its footprint centre.
const AIRPORT := {
	"terminal_1": ["07_Modulo1_AIRPORT_0", "07_ColliderMod1_COLLIDERS_0", 6000, "box"],
	"terminal_2": ["07_Modulo2_AIRPORT_0", "Cube_045_COLLIDERS_0", 4000, "box"],
	"tower": ["02_ControlTower_AIRPORT_0", "02_Collider_COLLIDERS_0", 1650, "box"],
	"hangar": ["04_Hangar_AIRPORT_0", "04_Collider_COLLIDERS_0", 3000, "box"],
	"jetbridge": ["06_Tunnel_AIRPORT_0", "06_Collider_COLLIDERS_0", 3000, "box"],
	"stairs": ["03_AirplaneStairs_AIRPORT_0", "03_Collider_COLLIDERS_0", 1500, "box"],
	"plane_1": ["18_1_Airplane_AIRPORT_0", "18_1_Collider_COLLIDERS_0", 4000, "hull"],
	"plane_2": ["18_2_Airplane_AIRPORT_0", "18_2_Collider_COLLIDERS_0", 4500, "hull"],
	"plane_3": ["18_3_Airplane_AIRPORT_0", "18_3_Collider_COLLIDERS_0", 4000, "hull"],
	"plane_4": ["18_4_Airplane_AIRPORT_0", "18_4_Collider_COLLIDERS_0", 3800, "hull"],
	"firetruck": ["19_Firetruck_AIRPORT_0", "19_Collider_COLLIDERS_0", 3500, "box"],
	"bus": ["20_PassengerBus_AIRPORT_0", "20_Collider_COLLIDERS_0", 3500, "box"],
	"baggage_1": ["21_1_BaggageTruck_AIRPORT_0", "21_1_Collider_COLLIDERS_0", 2500, "box"],
	"baggage_2": ["21_2_BaggageTruck_AIRPORT_0", "21_2_Collider_COLLIDERS_0", 2500, "box"],
	"baggage_3": ["21_3_BaggageTruck_AIRPORT_0", "21_3_Collider_COLLIDERS_0", 2000, "box"],
	"container_1": ["05_Container_AIRPORT_0", "05_Collider_COLLIDERS_0", 1000, "box"],
	"container_2": ["05_Container2_AIRPORT_0", "05_Collider2_COLLIDERS_0", 1000, "box"],
	"container_3": ["05_Container3_AIRPORT_0", "05_Collider3_COLLIDERS_0", 1000, "box"],
	"container_4": ["05_Container4_AIRPORT_0", "05_Collider4_COLLIDERS_0", 1000, "box"],
	"container_5": ["05_Container5_AIRPORT_0", "05_Collider5_COLLIDERS_0", 1000, "box"],
	"runway": ["LandingTrack1Straight_AIRPORT_0", "Collider1Straight_COLLIDERS_0", 200, "none"],
}

func _mesh_node(root: Node, nm: String) -> MeshInstance3D:
	for mi in root.find_children(nm, "MeshInstance3D", true, false):
		return mi as MeshInstance3D
	return null

func _group_of(root: Node, nm: String) -> Object:
	var g := L.Group.new()
	var m: MeshInstance3D = _mesh_node(root, nm)
	if m == null:
		push_error("missing mesh " + nm)
		return g
	for s in range(m.mesh.get_surface_count()):
		g.add(m.mesh.surface_get_arrays(s), L.world_xf(m, root), Color.WHITE)
	return g

func _job_airport() -> void:
	var root: Node = L.load_scene("res://_src/airport_pack_total.glb")
	var mat: StandardMaterial3D = _pack_material(root, "airport")
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ResourceSaver.save(mat, "res://assets/world/bld/airport_mat.res")
	var data := "class_name AirportData\nextends RefCounted\n## GENERATED by tools/prepare_world.gd (job airport). pos = footprint centre in the pack frame (x east, z south), size in metres.\n\nconst ITEMS := {\n"
	for id in AIRPORT:
		var cfg: Array = AIRPORT[id]
		var g: Object = _group_of(root, cfg[0])
		var bb: AABB = g.aabb()
		var org := Vector3(bb.get_center().x, bb.position.y, bb.get_center().z)
		if id == "runway":
			org.y = bb.end.y - 0.03          # top surface 3 cm above the origin height
		for i in range(g.v.size()):
			g.v[i] -= org
		var before: int = g.tris()
		L.decimate(g, int(cfg[2]))
		var am: ArrayMesh = L.to_mesh(g, false, true)
		am.surface_set_material(0, mat)
		var r3 := Node3D.new()
		r3.name = id
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = am
		r3.add_child(mi)
		mi.owner = r3
		var ps := PackedScene.new()
		ps.pack(r3)
		ResourceSaver.save(ps, "res://assets/world/airport/%s.tscn" % id)
		var shape_off := Vector3.ZERO
		var has_shape := false
		if cfg[3] != "none":
			var cg: Object = _group_of(root, cfg[1])
			for i in range(cg.v.size()):
				cg.v[i] -= org
			var cbb: AABB = cg.aabb()
			if cfg[3] == "box":
				var bs := BoxShape3D.new()
				bs.size = cbb.size
				ResourceSaver.save(bs, "res://assets/world/airport/%s_col.res" % id)
				shape_off = cbb.get_center()
			else:
				var cm: ArrayMesh = L.to_mesh(cg, false, false)
				var hull: ConvexPolygonShape3D = cm.create_convex_shape(true, true)
				ResourceSaver.save(hull, "res://assets/world/airport/%s_col.res" % id)
				print("   hull points ", hull.points.size())
			has_shape = true
		var sz: Vector3 = g.aabb().size
		data += "\t\"%s\": {\"pos\": Vector3(%.2f, %.2f, %.2f), \"size\": Vector3(%.2f, %.2f, %.2f), \"shape\": %s, \"shape_off\": Vector3(%.2f, %.2f, %.2f)},\n" % [id, org.x, org.y, org.z, sz.x, sz.y, sz.z, str(has_shape).to_lower(), shape_off.x, shape_off.y, shape_off.z]
		print("AP ", id, " tris ", before, "->", g.tris(), " pos ", org.snapped(Vector3.ONE * 0.1), " size ", sz.snapped(Vector3.ONE * 0.1))
	data += "}\n"
	var f := FileAccess.open("res://scripts/world/airport_data.gd", FileAccess.WRITE)
	f.store_string(data)
	f.close()

# ------------------------------------------------------------------------------------------------ pedestrians
## just_people.glb = 20 walking characters on one 703-bone skeleton + "Take 001" (10.8 s).  A skinned 703-bone skeleton per
## pedestrian is far too heavy for a phone, so the walk cycle is baked: each chosen character is skinned on the CPU at M poses
## of one stride (period found by comparing poses), re-centred, scaled to 1.75 m and stored as M surfaces of one ArrayMesh
## (assets/world/people/ped_<n>.res); PedManager swaps the frame mesh by walk phase.
const PED_CHARS := [0, 2, 5, 7, 10, 13, 16, 18]
const PED_FRAMES := 8

func _job_people() -> void:
	var root: Node = L.load_scene("res://_src/just_people.glb")
	_people_root = root
	get_root().add_child(root)
	await process_frame
	var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	var anim: Animation = ap.get_animation("Take 001")
	var skel: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var chars: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.skin != null and m.mesh.get_faces().size() > 3000:
			chars.append(m)
	print("PEOPLE chars ", chars.size())
	ap.play("Take 001")
	# --- period from character 0 ---
	var n: int = 108
	var poses: Array = []
	for i in range(n):
		ap.seek(float(i) * anim.length / float(n), true)
		ap.advance(0.0)
		poses.append(_skin_char(chars[0], skel))
	var dist := {}
	for k in range(4, 70):
		var d: float = 0.0
		var pa: PackedVector3Array = poses[0]
		var pb: PackedVector3Array = poses[k]
		var ca: Vector3 = _centroid(pa)
		var cb: Vector3 = _centroid(pb)
		for j in range(0, pa.size(), 5):
			d += ((pa[j] - ca) - (pb[j] - cb)).length_squared()
		dist[k] = d
	var best_k: int = 12
	var best_d: float = 0.0
	for k in range(5, 68):
		if float(dist[k]) < 3.0 and float(dist[k]) <= float(dist[k - 1]) and float(dist[k]) <= float(dist[k + 1]):
			best_k = k
			best_d = float(dist[k])
			break    # first deep minimum = one stride cycle
	var period: float = float(best_k) * anim.length / float(n)
	print("PEOPLE stride period ", period, " (k=", best_k, ") residual ", best_d)
	var out_i: int = 0
	for ci in PED_CHARS:
		var m: MeshInstance3D = chars[ci]
		var mat0: Material = m.mesh.surface_get_material(0)
		var nm := StandardMaterial3D.new()
		nm.roughness = 1.0
		nm.metallic_specular = 0.1
		if mat0 is BaseMaterial3D:
			nm.albedo_color = (mat0 as BaseMaterial3D).albedo_color
			var tx: Texture2D = (mat0 as BaseMaterial3D).albedo_texture
			if tx != null:
				var img: Image = tx.get_image()
				if img.is_compressed():
					img.decompress()
				if maxi(img.get_width(), img.get_height()) > 256:
					img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
				nm.albedo_texture = ImageTexture.create_from_image(img)
		var arrs: Array = m.mesh.surface_get_arrays(0)
		var am := ArrayMesh.new()
		var scale_k: float = 1.0
		var foot_y: float = 0.0
		for f in range(PED_FRAMES):
			ap.seek(float(f) * period / float(PED_FRAMES), true)
			ap.advance(0.0)
			var vs: PackedVector3Array = _skin_char(m, skel)
			var c: Vector3 = _centroid(vs)
			if f == 0:
				var lo: float = INF
				var hi: float = -INF
				for v in vs:
					lo = minf(lo, v.y)
					hi = maxf(hi, v.y)
				scale_k = 1.75 / (hi - lo)
				foot_y = lo
			var nv := PackedVector3Array()
			for v in vs:
				nv.append(Vector3(v.x - c.x, v.y - foot_y, v.z - c.z) * scale_k)
			var ns: PackedVector3Array = _skin_normals
			var arr: Array = []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = nv
			arr[Mesh.ARRAY_NORMAL] = ns
			arr[Mesh.ARRAY_TEX_UV] = arrs[Mesh.ARRAY_TEX_UV]
			arr[Mesh.ARRAY_INDEX] = arrs[Mesh.ARRAY_INDEX]
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			am.surface_set_material(f, nm)
		ResourceSaver.save(am, "res://assets/world/people/ped_%d.res" % out_i)
		print("PEOPLE ped_", out_i, " from char ", ci, " verts ", (arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), " scale ", scale_k)
		out_i += 1
	root.queue_free()

var _skin_normals := PackedVector3Array()
var _people_root: Node = null

func _centroid(vs: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for v in vs:
		c += v
	return c / float(maxi(vs.size(), 1))

## CPU skinning of surface 0 of a skinned mesh in the skeleton's current pose; fills _skin_normals
func _skin_char(m: MeshInstance3D, skel: Skeleton3D) -> PackedVector3Array:
	var arrs: Array = m.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arrs[Mesh.ARRAY_NORMAL]
	var bones = arrs[Mesh.ARRAY_BONES]
	var weights = arrs[Mesh.ARRAY_WEIGHTS]
	var skin: Skin = m.skin
	var xf: Array = []
	for k in range(skin.get_bind_count()):
		var b: int = skin.get_bind_bone(k)
		if b < 0:
			b = skel.find_bone(skin.get_bind_name(k))
		xf.append(L.world_xf(skel, _people_root) * skel.get_bone_global_pose(b) * skin.get_bind_pose(k))
	var out := PackedVector3Array()
	_skin_normals = PackedVector3Array()
	var per: int = bones.size() / vs.size()
	for i in range(vs.size()):
		var p := Vector3.ZERO
		var nn := Vector3.ZERO
		for j in range(per):
			var w: float = weights[i * per + j]
			if w <= 0.0:
				continue
			var t: Transform3D = xf[int(bones[i * per + j])]
			p += (t * vs[i]) * w
			nn += (t.basis.orthonormalized() * ns[i]) * w
		out.append(p)
		_skin_normals.append(nn.normalized())
	return out

# ------------------------------------------------------------------------------------------------ birds
## birds.glb = 5 small skinned birds (10 bones each) + "Scene" (0.667 s flap loop): baked as 6 wing-beat poses per bird
const BIRD_FRAMES := 6

func _job_birds() -> void:
	var root: Node = L.load_scene("res://_src/birds.glb")
	_people_root = root
	get_root().add_child(root)
	await process_frame
	var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	var anim: Animation = ap.get_animation("Scene")
	ap.play("Scene")
	var bi: int = 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.skin == null or m.mesh.get_faces().size() < 300:
			continue
		var skel: Skeleton3D = m.get_node(m.skeleton) as Skeleton3D
		var am := ArrayMesh.new()
		var arrs: Array = m.mesh.surface_get_arrays(0)
		var mat: Material = m.mesh.surface_get_material(0)
		var c0 := Vector3.ZERO
		for f in range(BIRD_FRAMES):
			ap.seek(float(f) * anim.length / float(BIRD_FRAMES), true)
			ap.advance(0.0)
			var vs: PackedVector3Array = _skin_char_sk(m, skel)
			if f == 0:
				c0 = _centroid(vs)
			var nv := PackedVector3Array()
			for v in vs:
				nv.append((v - c0) * 1.6)
			var arr: Array = []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = nv
			arr[Mesh.ARRAY_NORMAL] = _skin_normals
			arr[Mesh.ARRAY_INDEX] = arrs[Mesh.ARRAY_INDEX]
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			am.surface_set_material(f, mat)
		ResourceSaver.save(am, "res://assets/world/people/bird_%d.res" % bi)
		print("BIRD ", bi, " ", m.name, " aabb f0 ", am.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), " verts")
		bi += 1
	root.queue_free()

func _skin_char_sk(m: MeshInstance3D, skel: Skeleton3D) -> PackedVector3Array:
	return _skin_char(m, skel)

# ------------------------------------------------------------------------------------------------ dog
## dog.glb = one static 52.8k-triangle mesh (no skeleton, no animation): decimated, walk gait is done by a small vertex shader
func _job_dog() -> void:
	var root: Node = L.load_scene("res://_src/dog.glb")
	var g := L.Group.new()
	var tex: Texture2D = null
	var tint := Color.WHITE
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var mat: Material = m.mesh.surface_get_material(0)
		if mat is BaseMaterial3D:
			tex = (mat as BaseMaterial3D).albedo_texture
			tint = (mat as BaseMaterial3D).albedo_color
		g.add(m.mesh.surface_get_arrays(0), L.world_xf(m, root), Color.WHITE)
	var bb: AABB = g.aabb()
	print("DOG raw aabb ", bb, " tris ", g.tris())
	L.decimate(g, 2600)
	var bb2: AABB = g.aabb()
	var org := Vector3(bb2.get_center().x, bb2.position.y, bb2.get_center().z)
	for i in range(g.v.size()):
		g.v[i] -= org
	print("DOG final aabb ", g.aabb(), " tris ", g.tris())
	var am: ArrayMesh = L.to_mesh(g, false, true)
	var nm := StandardMaterial3D.new()
	nm.roughness = 1.0
	nm.albedo_color = tint
	if tex != null:
		var img: Image = tex.get_image()
		if img.is_compressed():
			img.decompress()
		if maxi(img.get_width(), img.get_height()) > 512:
			img.resize(512, 512, Image.INTERPOLATE_LANCZOS)
		nm.albedo_texture = ImageTexture.create_from_image(img)
	am.surface_set_material(0, nm)
	ResourceSaver.save(am, "res://assets/world/people/dog.res")
