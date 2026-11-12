extends SceneTree
# godot --headless --path . -s tools/mat_dump.gd -- <glb> : mesh name, tris, material names (+colour), world AABB
func _initialize() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(a[0], st)
	var root: Node = doc.generate_scene(st)
	_walk(root, Transform3D.IDENTITY)
	quit()
func _walk(n: Node, xf: Transform3D) -> void:
	var cur := xf
	if n is Node3D:
		cur = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		var ms := ""
		for s in range(mi.mesh.get_surface_count()):
			var m := mi.mesh.surface_get_material(s)
			var c := ""
			if m is BaseMaterial3D:
				c = str((m as BaseMaterial3D).albedo_color.to_html(false)) + ("T" if (m as BaseMaterial3D).albedo_texture else "") + ("A" if (m as BaseMaterial3D).transparency != 0 else "")
			ms += "%s{%s} " % [m.resource_name if m else "-", c]
		var bb: AABB = cur * mi.get_aabb()
		print("M %s | %s | pos %s size %s" % [mi.name, ms, str(bb.position.snapped(Vector3.ONE * 0.01)), str(bb.size.snapped(Vector3.ONE * 0.01))])
	for c in n.get_children():
		_walk(c, cur)
