extends SceneTree
## One-off: makes the already generated track collision shapes two-sided (same step as in prepare_tracks.gd).
func _init() -> void:
	for id in ["a", "b"]:
		var path: String = "res://assets/tracks/track_%s_col.res" % id
		var sh: ConcavePolygonShape3D = load(path)
		var f: PackedVector3Array = sh.get_faces()
		var n0: int = f.size()
		for i in range(0, n0, 3):
			f.append(f[i])
			f.append(f[i + 2])
			f.append(f[i + 1])
		var ns := ConcavePolygonShape3D.new()
		ns.set_faces(f)
		ns.backface_collision = true
		ResourceSaver.save(ns, path)
		print("FIXCOL ", id, " ", n0 / 3, " -> ", f.size() / 3)
	quit()
