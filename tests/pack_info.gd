extends SceneTree
# prints world-space AABBs (metres) of the direct meaningful nodes of a GLB: godot --headless --script tests/pack_info.gd -- res://x.glb
func _init() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var inst: Node = (load(path) as PackedScene).instantiate()
	var rows: Array = []
	_walk(inst, Transform3D.IDENTITY, rows)
	rows.sort_custom(func(a, b): return a["vol"] > b["vol"])
	for r in rows.slice(0, 70):
		print("%-34s tris %6d size %s pos %s" % [r["name"], r["tris"], str((r["size"] as Vector3).snapped(Vector3(0.1, 0.1, 0.1))), str((r["ctr"] as Vector3).snapped(Vector3(1, 1, 1)))])
	print("meshnodes ", rows.size())
	quit()
func _walk(n: Node, xf: Transform3D, rows: Array) -> void:
	var cur: Transform3D = xf
	if n is Node3D:
		cur = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m: Mesh = (n as MeshInstance3D).mesh
		var bb: AABB = cur * m.get_aabb()
		var t := 0
		for s in range(m.get_surface_count()):
			var a: Array = m.surface_get_arrays(s)
			t += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		rows.append({"name": n.name, "tris": t, "size": bb.size, "ctr": bb.get_center(), "vol": bb.size.x * bb.size.y * bb.size.z})
	for c in n.get_children():
		_walk(c, cur, rows)
