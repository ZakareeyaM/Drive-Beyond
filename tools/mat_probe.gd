extends SceneTree
func _initialize():
	for id in ["countach","m3_gtr","sesto","nsx","gclass","mustang","amg_one"]:
		var inst = (load("res://assets/vehicles/fleet/%s.glb" % id) as PackedScene).instantiate()
		var m: ArrayMesh = (inst.find_child("Body", true, false) as MeshInstance3D).mesh
		var s_ = []
		for s in range(m.get_surface_count()):
			var mat = m.surface_get_material(s) as BaseMaterial3D
			s_.append("%s[%s%s%s]" % [mat.resource_name.right(18), mat.albedo_color.to_html(false), "T" if mat.albedo_texture else "", "a" if mat.transparency != 0 else ""])
		print(id, ": ", " ".join(s_))
		var w = inst.find_child("Wheel_0", true, false) as MeshInstance3D
		var l = []
		for s in range(w.mesh.get_surface_count()):
			var mat = w.mesh.surface_get_material(s) as BaseMaterial3D
			l.append("%s[%s%s]" % [mat.resource_name, mat.albedo_color.to_html(false), "T" if mat.albedo_texture else ""])
		print("   wheel0 pos ", w.position, " ", " ".join(l))
		for i in range(1,4):
			print("   wheel", i, (inst.find_child("Wheel_%d" % i, true, false) as Node3D).position)
		inst.free()
	quit()
