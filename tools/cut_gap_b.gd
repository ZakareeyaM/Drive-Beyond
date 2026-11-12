extends SceneTree
## One-off: flattens the 0.45 m kerb ridge between the Track 2 paddock apron and the pit straight (x -24..-14.5, z 54..66, track-local) so the go-kart
## (wheel radius 0.15 m) can drive from its pad onto the circuit.  Applied to the visual mesh and the collision shape alike.
const X0 := -22.5
const X1 := -17.0
const Z0 := 54.0
const Z1 := 66.0
func _fix(v: Vector3, ys: float) -> Vector3:
	if v.x > X0 and v.x < X1 and v.z > Z0 and v.z < Z1 and v.y > ys:
		return Vector3(v.x, ys, v.z)
	return v
func _init() -> void:
	var m: ArrayMesh = load("res://assets/tracks/track_b.res")
	var a: Array = m.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var yroad := 0.0      # driving surface of the pit straight (ray probes: 11.00 world = 0.0 local)
	for i in range(v.size()):
		v[i] = _fix(v[i], yroad)
	a[Mesh.ARRAY_VERTEX] = v
	if a[Mesh.ARRAY_NORMAL] != null:
		pass
	var nm := ArrayMesh.new()
	nm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	nm.surface_set_material(0, m.surface_get_material(0))
	ResourceSaver.save(nm, "res://assets/tracks/track_b.res")
	var sh: ConcavePolygonShape3D = load("res://assets/tracks/track_b_col.res")
	var f: PackedVector3Array = sh.get_faces()
	for i in range(f.size()):
		f[i] = _fix(f[i], yroad)
	var ns := ConcavePolygonShape3D.new()
	ns.set_faces(f)
	ns.backface_collision = true
	ResourceSaver.save(ns, "res://assets/tracks/track_b_col.res")
	print("GAP done, road y ", yroad)
	quit()
