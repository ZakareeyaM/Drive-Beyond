extends SceneTree
func _initialize():
	var out = {}
	for id in ["countach","m3_gtr","sesto","nsx","gclass","mustang","amg_one","airport_car","civic","camaro","c63","go_kart","dune_buggy","scifi_buggy"]:
		var inst = (load("res://assets/vehicles/fleet/%s.glb" % id) as PackedScene).instantiate()
		var bb = (inst.find_child("Body", true, false) as MeshInstance3D).mesh.get_aabb()
		var w = []
		var r = 0.0; var ww = 0.0
		for i in range(4):
			var n = inst.find_child("Wheel_%d" % i, true, false) as MeshInstance3D
			w.append([n.position.x, n.position.y, n.position.z])
			r += n.mesh.get_aabb().size.y * 0.125; ww += n.mesh.get_aabb().size.x * 0.25
		out[id] = {"wheels": w, "wr": r, "ww": ww, "zmin": bb.position.z, "zmax": bb.end.z, "ymax": bb.end.y, "width": bb.size.x}
		inst.free()
	print("JSON", JSON.stringify(out))
	quit()
