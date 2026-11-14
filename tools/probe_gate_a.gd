extends SceneTree
func _init() -> void:
	var sh: ConcavePolygonShape3D = load("res://assets/tracks/track_a_col.res")
	var f: PackedVector3Array = sh.get_faces()
	for i in range(0, f.size(), 3):
		var mnx := minf(f[i].x, minf(f[i+1].x, f[i+2].x)); var mxx := maxf(f[i].x, maxf(f[i+1].x, f[i+2].x))
		var mnz := minf(f[i].z, minf(f[i+1].z, f[i+2].z)); var mxz := maxf(f[i].z, maxf(f[i+1].z, f[i+2].z))
		var mny := minf(f[i].y, minf(f[i+1].y, f[i+2].y)); var mxy := maxf(f[i].y, maxf(f[i+1].y, f[i+2].y))
		if mxx > -98.0 and mnx < -93.0 and mxz > -73.0 and mnz < -71.0 and mny < 5.0:
			print("GATE x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f]" % [mnx, mxx, mny, mxy, mnz, mxz])
	quit()
