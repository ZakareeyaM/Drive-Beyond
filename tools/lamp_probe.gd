extends SceneTree
func _initialize():
	for id in ["countach","m3_gtr","sesto","nsx","gclass","mustang","amg_one"]:
		var inst = (load("res://assets/vehicles/fleet/%s.glb" % id) as PackedScene).instantiate()
		var m: ArrayMesh = (inst.find_child("Body", true, false) as MeshInstance3D).mesh
		var bb = m.get_aabb()
		var zmin = bb.position.z; var zmax = bb.end.z
		var res = {}
		for s in range(m.get_surface_count()):
			var nm = m.surface_get_material(s).resource_name
			if not (nm in ["lamp_head","lamp_lens_front","lamp_tail"]): continue
			var vs: PackedVector3Array = m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in vs:
				var front = v.z < zmin + 0.5
				var rear = v.z > zmax - 0.5
				if not (front or rear): continue
				if absf(v.x) < 0.25: continue
				var key = "%s_%s_%s" % [nm, "F" if front else "R", "L" if v.x < 0 else "R"]
				if not res.has(key): res[key] = [Vector3.ZERO, 0, Vector3(1e9,1e9,1e9), Vector3(-1e9,-1e9,-1e9)]
				res[key][0] += v; res[key][1] += 1
				res[key][2] = res[key][2].min(v); res[key][3] = res[key][3].max(v)
		print("== ", id, " zmin ", snappedf(zmin,0.01), " zmax ", snappedf(zmax,0.01), " h ", snappedf(bb.end.y,0.01))
		for k in res:
			var c = res[k][0] / res[k][1]
			print("  ", k, " n=", res[k][1], " c=", c.snapped(Vector3.ONE*0.01), " lo=", res[k][2].snapped(Vector3.ONE*0.01), " hi=", res[k][3].snapped(Vector3.ONE*0.01))
		inst.free()
	quit()
