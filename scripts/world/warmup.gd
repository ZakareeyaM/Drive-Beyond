class_name WarmUp
extends Node
## First-use cost removal.  GPU shader variants, material textures and mesh buffers are created lazily the first
## time something is drawn, which on a phone shows up as a hitch the first time a new building type, vehicle model or
## vegetation type enters view.  This draws one tiny instance of every world asset (parented to the active camera so it is
## always inside the frustum) in small batches while the loading screen is up, then frees them.
## With profile = true each batch's frame time is printed ("WARMUP ...") so the expensive first-uses are visible.

var world: World
var profile: bool = false
var report: Array = []
const BATCH := 3

func run(w: World) -> void:
	world = w
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var holder := Node3D.new()
	holder.name = "WarmUpHolder"
	cam.add_child(holder)
	holder.position = Vector3(0, 0, -4)
	var jobs: Array = _jobs()
	var i: int = 0
	var made: Array = []
	var last: int = Time.get_ticks_usec()
	for j in jobs:
		var n: Node3D = (j["make"] as Callable).call()
		if n == null:
			continue
		n.scale = Vector3.ONE * float(j.get("scale", 1.0))
		n.position = Vector3(randf_range(-0.4, 0.4), randf_range(-0.3, 0.3), 0)
		holder.add_child(n)
		made.append(n)
		i += 1
		if i % BATCH == 0:
			await get_tree().process_frame
			await get_tree().process_frame
			var now: int = Time.get_ticks_usec()
			report.append([String(j["name"]), float(now - last) / 1000.0])
			last = now
			for m in made:
				(m as Node).queue_free()
			made.clear()
			if profile:
				print("WARMUP batch ending %s: %.0f ms" % [j["name"], report.back()[1]])
	await get_tree().process_frame
	holder.queue_free()
	queue_free()

func _jobs() -> Array:
	var jobs: Array = []
	var a: Dictionary = world.assets
	# streamed-world materials: tiny quads in the exact vertex formats the chunk builder uses
	jobs.append({"name": "terrain", "make": func() -> Node3D: return _quad(a["mat_terrain"], true, false), "scale": 0.1})
	jobs.append({"name": "road", "make": func() -> Node3D: return _quad(a["mat_road"], true, true), "scale": 0.1})
	jobs.append({"name": "sidewalk", "make": func() -> Node3D: return _quad(a["mat_plain"], true, false), "scale": 0.1})
	for name in ["bld", "roof", "struct", "pine", "oak", "palm", "cactus", "rock", "lamp", "pool"]:
		for fl in [[false, false], [true, false], [true, true]]:
			var nm: String = name
			var f: Array = fl
			jobs.append({"name": "mm_%s_%s%s" % [nm, f[0], f[1]], "make": func() -> Node3D: return _mm(a, nm, f[0], f[1]), "scale": 0.02})
	# imported building models and the petrol station
	for id in PackBuildings.SIZES:
		var bid: String = id
		jobs.append({"name": "bld_" + bid, "make": func() -> Node3D: return _scene(PackBuildings.path_of(bid)), "scale": 0.01})
	jobs.append({"name": "station", "make": func() -> Node3D: return _scene(GasStation.MODEL), "scale": 0.02})
	# every vehicle model traffic can spawn, plus the player's
	var vids: Array = []
	for v in TrafficManager.VIDS:
		if not vids.has(v):
			vids.append(v)
	if not vids.has(Game.selected):
		vids.append(Game.selected)
	for v in vids:
		var vid: String = v
		jobs.append({"name": "car_" + vid, "make": func() -> Node3D: return _car(vid), "scale": 0.1})
	return jobs

func _quad(mat: Material, nrm: bool, uv: bool) -> Node3D:
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)])
	arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arr[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	if uv:
		arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.rotation.x = deg_to_rad(90)
	return mi

func _mm(a: Dictionary, name: String, col: bool, cust: bool) -> Node3D:
	if not a.has("mesh_" + name):
		return null
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.use_colors = col
	m.use_custom_data = cust
	m.mesh = a["mesh_" + name]
	m.instance_count = 1
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = m
	mi.material_override = a["mat_" + name]
	return mi

func _scene(path: String) -> Node3D:
	var ps: PackedScene = load(path) as PackedScene
	if ps == null:
		return null
	return ps.instantiate() as Node3D

func _car(vid: String) -> Node3D:
	var c: Dictionary = Data.default_custom(vid)
	var m: Dictionary = CarBuilder.build(vid, c)
	return m["root"] as Node3D
