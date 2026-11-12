extends SceneTree
func _initialize() -> void:
	var root: Node = WorldPrepLib.load_scene("res://_src/kart.glb")
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf: Transform3D = WorldPrepLib.world_xf(m, root)
		for s in range(m.mesh.get_surface_count()):
			var g := WorldPrepLib.Group.new()
			var arr: Array = m.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			for i in range(v.size()):
				g.v.append(xf * v[i] * 0.01); g.n.append(n[i]); g.uv.append(uv[i] if uv.size() > i else Vector2.ZERO); g.col.append(Color.WHITE)
			g.idx = idx
			var comps: Array = WorldPrepLib.components(g)
			print("OBJ ", m.name, " surf ", s, " comps ", comps.size())
			for c in comps:
				var bb := AABB(c.v[0], Vector3.ZERO)
				for p in c.v: bb = bb.expand(p)
				if c.idx.size() / 3 > 150:
					print("   comp tris ", c.idx.size() / 3, " pos ", bb.position.snapped(Vector3.ONE * 0.01), " size ", bb.size.snapped(Vector3.ONE * 0.01))
	quit()
