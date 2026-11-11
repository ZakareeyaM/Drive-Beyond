extends SceneTree
# godot --headless --path . -s tools/glb_inspect.gd -- <glb> [max_depth]  : hierarchy with mesh/tri counts, AABBs, skeletons, animations
func _initialize() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(a[0], st) != OK:
		print("LOAD FAIL"); quit(); return
	var root: Node = doc.generate_scene(st)
	var maxd: int = int(a[1]) if a.size() > 1 else 3
	print("ROOT ", root.name, " children ", root.get_child_count(), " materials ", st.materials.size(), " textures ", st.textures.size(), " anims ", st.animations.size())
	for an in st.animations:
		print("  ANIM ", an.resource_name, " ", (an as GLTFAnimation).original_name if "original_name" in an else "")
	var tot := _walk(root, Transform3D.IDENTITY, 0, maxd)
	print("TOTAL tris ", tot[0], " meshes ", tot[1])
	for n in root.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		for an in ap.get_animation_list():
			print("  PLAYER ", n.name, " anim ", an, " len ", ap.get_animation(an).length, " tracks ", ap.get_animation(an).get_track_count())
	for n in root.find_children("*", "Skeleton3D", true, false):
		print("  SKELETON ", n.name, " bones ", (n as Skeleton3D).get_bone_count())
	quit()

func _tris(m: Mesh) -> int:
	var t := 0
	for s in range(m.get_surface_count()):
		var arr: Array = m.surface_get_arrays(s)
		var ix = arr[Mesh.ARRAY_INDEX]
		t += (ix.size() if ix != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
	return t

func _walk(n: Node, xf: Transform3D, d: int, maxd: int) -> Array:
	var tris := 0
	var meshes := 0
	var nxf := xf
	if n is Node3D:
		nxf = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		tris += _tris((n as MeshInstance3D).mesh)
		meshes += 1
	for c in n.get_children():
		var r := _walk(c, nxf, d + 1, maxd)
		tris += r[0]
		meshes += r[1]
	if d <= maxd and d > 0:
		var info := ""
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var bb: AABB = nxf * (n as MeshInstance3D).get_aabb()
			info = " AABB pos %s size %s" % [str(bb.position.snapped(Vector3.ONE * 0.01)), str(bb.size.snapped(Vector3.ONE * 0.01))]
		print("  ".repeat(d), n.name, " [", n.get_class(), "] tris ", tris, " meshes ", meshes, info)
	return [tris, meshes]
