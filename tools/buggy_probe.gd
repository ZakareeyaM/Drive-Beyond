extends SceneTree
## godot --headless --path . -s tools/buggy_probe.gd -- res://_src/dune.glb   : world-space AABB, tris and material of every mesh
func _tris(m: Mesh) -> int:
	var t := 0
	for s in range(m.get_surface_count()):
		var ix = m.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
		t += (ix.size() if ix != null else m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()) / 3
	return t
func _walk(n: Node, xf: Transform3D, out: Array) -> void:
	var cur := xf
	if n is Node3D:
		cur = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		var bb: AABB = cur * mi.mesh.get_aabb()
		var mat := mi.mesh.surface_get_material(0)
		var mn := ""
		var ts := ""
		if mat is StandardMaterial3D:
			mn = "%s %s" % [mat.resource_name, str((mat as StandardMaterial3D).albedo_color)]
			var t := (mat as StandardMaterial3D).albedo_texture
			ts = "%dx%d" % [t.get_width(), t.get_height()] if t else "-"
		out.append([n.name, _tris(mi.mesh), bb, mn, ts, mi.mesh.get_surface_count()])
	for c in n.get_children():
		_walk(c, cur, out)
func _initialize() -> void:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(OS.get_cmdline_user_args()[0], st)
	var root := doc.generate_scene(st)
	var out: Array = []
	_walk(root, Transform3D.IDENTITY, out)
	var tot := AABB()
	var first := true
	for o in out:
		tot = (o[2] as AABB) if first else tot.merge(o[2])
		first = false
	print("BUG total AABB ", tot, " meshes ", out.size())
	for o in out:
		var b: AABB = o[2]
		print("BUG %s tris=%d c=(%.2f,%.2f,%.2f) s=(%.2f,%.2f,%.2f) surf=%d mat=%s tex=%s" % [o[0], o[1], b.get_center().x, b.get_center().y, b.get_center().z, b.size.x, b.size.y, b.size.z, o[5], o[3], o[4]])
	quit()
