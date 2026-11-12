extends SceneTree
# godot --headless --path . -s tools/track_h.gd -- <glb> x,z x,z ... : highest surface y at each (x,z) (all hit heights listed)
func _initialize() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var root: Node = WorldPrepLib.load_scene(a[0])
	var tris: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf: Transform3D = WorldPrepLib.world_xf(m, root)
		for s in range(m.mesh.get_surface_count()):
			var arr: Array = m.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx = arr[Mesh.ARRAY_INDEX]
			var n: int = (idx.size() if idx != null else v.size())
			for t in range(n / 3):
				var i0: int = idx[t * 3] if idx != null else t * 3
				var i1: int = idx[t * 3 + 1] if idx != null else t * 3 + 1
				var i2: int = idx[t * 3 + 2] if idx != null else t * 3 + 2
				tris.append([xf * v[i0], xf * v[i1], xf * v[i2]])
	for k in range(1, a.size()):
		var p: PackedStringArray = a[k].split(",")
		var x: float = float(p[0]); var z: float = float(p[1])
		var hs: Array = []
		for t in tris:
			var h: Variant = Geometry3D.ray_intersects_triangle(Vector3(x, 100, z), Vector3.DOWN, t[0], t[1], t[2])
			if h != null:
				hs.append(snappedf((h as Vector3).y, 0.01))
		hs.sort()
		hs.reverse()
		print("H (%s,%s) -> %s" % [p[0], p[1], str(hs.slice(0, 5))])
	quit()
