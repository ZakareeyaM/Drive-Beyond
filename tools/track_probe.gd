extends SceneTree
# godot --headless --path . -s tools/track_probe.gd -- <glb>  : per piece tris, bbox and atlas colour at the UV centroid
func _initialize() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var root: Node = WorldPrepLib.load_scene(a[0])
	var rows: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf: Transform3D = WorldPrepLib.world_xf(m, root)
		for s in range(m.mesh.get_surface_count()):
			var mat := m.mesh.surface_get_material(s)
			var arr: Array = m.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var idx = arr[Mesh.ARRAY_INDEX]
			var tris: int = (idx.size() if idx != null else v.size()) / 3
			var bb := AABB(xf * v[0], Vector3.ZERO)
			var uc := Vector2.ZERO
			for i in range(v.size()):
				bb = bb.expand(xf * v[i])
				if uv.size() == v.size():
					uc += uv[i]
			var col := Color.BLACK
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture and uv.size() == v.size():
				var img: Image = (mat as BaseMaterial3D).albedo_texture.get_image()
				if img.is_compressed():
					img.decompress()
				uc /= float(v.size())
				col = img.get_pixel(clampi(int(fposmod(uc.x, 1.0) * img.get_width()), 0, img.get_width() - 1), clampi(int(fposmod(uc.y, 1.0) * img.get_height()), 0, img.get_height() - 1))
			rows.append([String(m.name), tris, bb.position, bb.size, col])
	for r in rows:
		print("P %s tris %d pos (%.1f %.1f %.1f) size (%.1f %.1f %.1f) col %s" % [r[0], r[1], r[2].x, r[2].y, r[2].z, r[3].x, r[3].y, r[3].z, (r[4] as Color).to_html(false)])
	quit()
