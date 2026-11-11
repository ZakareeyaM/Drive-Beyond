extends SceneTree
func _initialize() -> void:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file("res://_src/Traffic_signals.glb", st)
	var root: Node = doc.generate_scene(st)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf: Transform3D = Transform3D.IDENTITY
		var n: Node = m
		while n != null and n != root:
			if n is Node3D: xf = (n as Node3D).transform * xf
			n = n.get_parent()
		for s in range(m.mesh.get_surface_count()):
			var mat: Material = m.mesh.surface_get_material(s)
			var arr: Array = m.mesh.surface_get_arrays(s)
			var bb := AABB()
			var first := true
			for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var w: Vector3 = xf * v
				if first: bb = AABB(w, Vector3.ZERO); first = false
				else: bb = bb.expand(w)
			var col := Color.WHITE
			if mat is BaseMaterial3D: col = (mat as BaseMaterial3D).albedo_color
			print(m.get_parent().name, "|", m.name, " s", s, " ", mat.resource_name if mat else "-", " col ", col.to_html(false), " emis ", (mat as BaseMaterial3D).emission_enabled if mat is BaseMaterial3D else false, " tris ", (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size()/3, " bb ", bb.position.snapped(Vector3.ONE*0.01), bb.size.snapped(Vector3.ONE*0.01))
	quit()
