extends Node
# Verifies the GLB bake: wheel assignment, measured vs. Data spec dimensions, collision boxes.
func _ready() -> void:
	for vid in VehicleModels.REGISTRY:
		var d: Dictionary = GlbVehicle.baked(vid)
		if d.is_empty():
			print("FAIL bake ", vid); get_tree().quit(1); return
		var spec: Dictionary = Data.vehicle(vid)
		var wc: Array = d["wheel_car"]
		print(vid, " wheel pieces ", d["wheel_piece_counts"], " body pieces ", d["body_tris"])
		var body: ArrayMesh = d["body"]
		var aabb: AABB = body.get_aabb()
		print(" body aabb pos ", aabb.position, " size ", aabb.size, " surfaces ", body.get_surface_count())
		var tri := 0
		for i in body.get_surface_count():
			tri += (body.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		for w in d["wheels"]:
			for i in (w as ArrayMesh).get_surface_count():
				tri += ((w as ArrayMesh).surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		print(" triangles total ", tri)
		var track: float = absf((wc[1] as Vector3).x - (wc[0] as Vector3).x)
		var wb: float = absf((wc[2] as Vector3).z - (wc[0] as Vector3).z)
		print(" measured track %.3f (spec %.3f)  wheelbase %.3f (spec %.3f)  wheel radius %.3f (spec %.3f)" % [track, spec["track"], wb, spec["wb"], d["wheel_radius"], spec["wr"]])
		print(" wheel centres ", wc)
		print(" length %.3f (spec %.3f) width %.3f (spec %.3f) height %.3f" % [aabb.size.z, spec["L"], aabb.size.x, spec["W"], aabb.end.y])
		for b in GlbVehicle.collision_boxes(vid):
			print(" collision box ", b)
	get_tree().quit()
