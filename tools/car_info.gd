extends SceneTree
# godot --headless --path . -s tools/car_info.gd -- <glb> [regex]    -> hierarchy / AABB / tri summary of a vehicle GLB
func _initialize() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = a[0]
	var rx := RegEx.new()
	rx.compile("(?i)" + (a[1] if a.size() > 1 else "wheel|tire|tyre|rim|head|lamp|light|glass|window|brake|disc|caliper|police|siren"))
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err: int = doc.append_from_file(path, st)
	if err != OK:
		print("LOAD FAIL ", err)
		quit()
		return
	var root: Node = doc.generate_scene(st)
	var all := AABB()
	var first := true
	var tris := 0
	var nmesh := 0
	var mats := {}
	var items: Array = []
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var n: Node = e[0]
		var xf: Transform3D = e[1]
		if n is Node3D:
			xf = xf * (n as Node3D).transform
		for c in n.get_children():
			stack.append([c, xf])
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var ab: AABB = xf * mi.get_aabb()
			if first:
				all = ab
				first = false
			else:
				all = all.merge(ab)
			var t := 0
			var mn: Array = []
			for s in range(mi.mesh.get_surface_count()):
				var arr: Array = mi.mesh.surface_get_arrays(s)
				var idx = arr[Mesh.ARRAY_INDEX]
				t += (idx.size() if idx != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
				var m: Material = mi.mesh.surface_get_material(s)
				var mname: String = m.resource_name if m else "-"
				mn.append(mname)
				mats[mname] = true
			tris += t
			nmesh += 1
			items.append([String(mi.name), ab, t, mn])
	print("FILE %s meshes=%d tris=%d materials=%d" % [path.get_file(), nmesh, tris, mats.size()])
	var mt: Dictionary = {}
	for it0 in items:
		for k in range(it0[3].size()):
			mt[it0[3][k]] = int(mt.get(it0[3][k], 0)) + 1
	print("MATS ", mt)
	print("BBOX pos=%s size=%s" % [all.position, all.size])
	for it in items:
		var hit: bool = rx.search(it[0]) != null
		for m in it[3]:
			if rx.search(m) != null:
				hit = true
		if hit:
			var ab2: AABB = it[1]
			print("  %-48s c=(%.3f,%.3f,%.3f) s=(%.3f,%.3f,%.3f) tris=%d %s" % [String(it[0]).left(48), ab2.get_center().x, ab2.get_center().y, ab2.get_center().z, ab2.size.x, ab2.size.y, ab2.size.z, it[2], str(it[3]).left(50)])
	quit()
