extends SceneTree
## godot --headless --path . -s tools/buggy_comp.gd -- res://_src/dune.glb <min_tris>   : connected components (world frame) of every mesh
func _initialize() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var root: Node = WorldPrepLib.load_scene(a[0])
	var mint: int = int(a[1]) if a.size() > 1 else 100
	var n := 0
	var big := []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf: Transform3D = WorldPrepLib.world_xf(m, root)
		for s in range(m.mesh.get_surface_count()):
			var g := WorldPrepLib.Group.new()
			g.add(m.mesh.surface_get_arrays(s), xf, Color.WHITE)
			var comps: Array = WorldPrepLib.components(g)
			var mat: Material = m.mesh.surface_get_material(s)
			for c in comps:
				n += 1
				var t: int = c.idx.size() / 3
				if t >= mint:
					var bb: AABB = c.aabb()
					big.append("COMP %s s%d mat=%s tris=%d c=(%.3f,%.3f,%.3f) size=(%.3f,%.3f,%.3f)" % [m.name, s, mat.resource_name if mat else "-", t, bb.get_center().x, bb.get_center().y, bb.get_center().z, bb.size.x, bb.size.y, bb.size.z])
	print("COMP total components ", n)
	for l in big:
		print(l)
	quit()
