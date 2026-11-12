extends SceneTree
## Offline: godot --headless --path . -s tools/prepare_tracks.gd -- a b     (needs res://_src/track_a.glb = low_poly_race_track.glb,
## res://_src/track_b.glb = lowpoly_racetrack.glb; raw GLBs are not shipped)
## Both models are palette-atlas models.  They are converted to: vertex-coloured meshes (no texture), a decimated trimesh collision
## shape, and a data file (scripts/world/tracks_data.gd) with the lap gates / kart spot in the track's own frame.
## Track frame: x/z centred on the kept geometry's bounding box, y = 0 at the driving surface, scaled by "scale".
const T := {
	"a": {"src": "res://_src/track_a.glb", "scale": 4.5, "yref": 0.52, "budget": 26000, "trees": 9000, "col": 14000, "tree_rx": true,
		# gates in model (raw) coordinates: [x, z, dir_x, dir_z]  - driving direction: north up the main straight
		"gates": [[0.1, 11.5, 0, -1], [0.1, -5.0, 0, -1], [5.2, -14.0, 0, 1], [14.6, -5.6, 0, 1], [8.0, 6.6, -1, 0], [-10.0, 6.6, -1, 0], [-10.0, 1.6, 1, 0], [-5.0, 12.0, 0, 1], [0.1, 14.5, 0, -1]],
		"kart": [-5.5, -13.0, 1, 0], "gate_w": 3.6, "road_w": 2.8, "carve": [[-22.6, -6.9, 33.6, 3.4], [6.0, 10.2, 15.5, 12.3]]},
	"b": {"src": "res://_src/track_b.glb", "scale": 1.0, "yref": 0.36, "budget": 52000, "trees": 0, "col": 14000, "skip_loose": true,
		"gates": [[0.3, 1.8, 0, -1], [0.3, -27.0, 0, -1], [0.3, -70.0, 0, -1], [45.0, -95.2, 1, 0], [45.0, -145.2, -1, 0], [-50.0, -157.0, -1, 0], [-100.0, -100.0, 0, 1], [-60.0, -55.2, 1, 0], [0.3, -55.2, 1, 0], [95.0, -55.2, 1, 0], [130.0, -30.0, 0, 1], [90.0, -5.5, -1, 0], [49.7, 28.0, 0, 1], [24.5, 59.4, -1, 0], [0.3, 35.0, 0, -1]],
		"kart": [-12.0, 14.0, 1, 0], "gate_w": 18.0, "road_w": 10.0, "carve": []},
}

func _initialize() -> void:
	var ids: PackedStringArray = OS.get_cmdline_user_args()
	var data := {}
	for id in ids:
		data[id] = _do(id, T[id])
	_write_data(data)
	quit()

func _atlas_col(mat: Material, uv: Vector2, img: Image) -> Color:
	if img == null:
		return (mat as BaseMaterial3D).albedo_color if mat is BaseMaterial3D else Color(0.5, 0.5, 0.5)
	var x: int = clampi(int(fposmod(uv.x, 1.0) * img.get_width()), 0, img.get_width() - 1)
	var y: int = clampi(int(fposmod(uv.y, 1.0) * img.get_height()), 0, img.get_height() - 1)
	return img.get_pixel(x, y)

func _do(id: String, cfg: Dictionary) -> Dictionary:
	var root: Node = WorldPrepLib.load_scene(cfg["src"])
	var pieces: Array = []
	var imgs := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf: Transform3D = WorldPrepLib.world_xf(m, root)
		for s in range(m.mesh.get_surface_count()):
			var mat: Material = m.mesh.surface_get_material(s)
			var img: Image = null
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture:
				if not imgs.has(mat):
					var im2: Image = (mat as BaseMaterial3D).albedo_texture.get_image()
					if im2.is_compressed():
						im2.decompress()
					imgs[mat] = im2
				img = imgs[mat]
			var g := WorldPrepLib.Group.new()
			g.add(m.mesh.surface_get_arrays(s), xf, Color.WHITE)
			for i in range(g.v.size()):
				g.col[i] = _atlas_col(mat, g.uv[i], img)
			var bb: AABB = g.aabb()
			if cfg.get("skip_loose", false) and bb.get_center().x < -22.0 and bb.get_center().z > -50.0:
				continue
			pieces.append({"g": g, "bb": bb})
	var all := AABB()
	var first := true
	for p in pieces:
		all = (p["bb"] as AABB) if first else all.merge(p["bb"])
		first = false
	var S: float = cfg["scale"]
	var c := Vector3(all.get_center().x, 0.0, all.get_center().z)
	var yref: float = cfg["yref"]
	print("TRACK ", id, " pieces ", pieces.size(), " raw bounds ", all, " centre ", c)
	var base := WorldPrepLib.Group.new()
	var trees := WorldPrepLib.Group.new()
	var solid := WorldPrepLib.Group.new()   # collision: ground / road / kerbs
	var walls := WorldPrepLib.Group.new()   # collision: fences, tall barriers
	var ntree := 0
	for p in pieces:
		var g: WorldPrepLib.Group = p["g"]
		var bb: AABB = p["bb"]
		var mc := Color(0, 0, 0)
		for col in g.col:
			mc += col
		mc = mc / float(maxi(1, g.col.size()))
		var is_tree: bool = cfg.get("tree_rx", false) and bb.size.length() < 3.6 and mc.g > mc.r * 1.25 and mc.g > mc.b * 1.5
		var dst: WorldPrepLib.Group = trees if is_tree else base
		_append(dst, g, c, yref, S)
		if is_tree:
			ntree += 1
		else:
			_append(walls if bb.size.y * S > 0.9 and bb.size.y > bb.size.x * 0.0 and (bb.size.x < 1.0 / S * 3.0 or bb.size.z < 1.0 / S * 3.0) else solid, g, c, yref, S)
	print("TRACK ", id, " base tris ", base.tris(), " trees ", trees.tris(), " (", ntree, " pieces) solid ", solid.tris(), " walls ", walls.tris())
	WorldPrepLib.decimate(base, int(cfg["budget"]))
	if trees.tris() > 0:
		WorldPrepLib.decimate(trees, int(cfg["trees"]))
	WorldPrepLib.decimate(solid, int(cfg["col"]))
	WorldPrepLib.decimate(walls, 3000)
	print("TRACK ", id, " after: base ", base.tris(), " trees ", trees.tris(), " solid ", solid.tris(), " walls ", walls.tris())
	ResourceSaver.save(WorldPrepLib.to_mesh(base, true, false), "res://assets/tracks/track_%s.res" % id)
	if trees.tris() > 0:
		ResourceSaver.save(WorldPrepLib.to_mesh(trees, true, false), "res://assets/tracks/track_%s_trees.res" % id)
	var faces := PackedVector3Array()
	for gg in [solid, walls]:
		for i in gg.idx:
			faces.append(gg.v[i])
	# the source meshes have mixed winding and Jolt's wheel rays ignore back faces: make every triangle two-sided
	var n0: int = faces.size()
	for i in range(0, n0, 3):
		faces.append(faces[i])
		faces.append(faces[i + 2])
		faces.append(faces[i + 1])
	var shp := ConcavePolygonShape3D.new()
	shp.set_faces(faces)
	shp.backface_collision = true
	ResourceSaver.save(shp, "res://assets/tracks/track_%s_col.res" % id)
	var half := Vector2(all.size.x, all.size.z) * 0.5 * S
	var gates: Array = []
	for gt in cfg["gates"]:
		gates.append([(gt[0] - c.x) * S, (gt[1] - c.z) * S, gt[2], gt[3]])
	var kt: Array = cfg["kart"]
	var carve: Array = []
	for r in cfg["carve"]:
		carve.append([(r[0] - c.x) * S, (r[1] - c.z) * S, r[2] * S, r[3] * S])
	return {"half": half, "gates": gates, "kart": [(kt[0] - c.x) * S, (kt[1] - c.z) * S, kt[2], kt[3]], "gate_w": float(cfg["gate_w"]) * S, "road_w": float(cfg["road_w"]) * S, "carve": carve, "ymax": (all.end.y - yref) * S, "ymin": (all.position.y - yref) * S}

func _append(dst: WorldPrepLib.Group, g: WorldPrepLib.Group, c: Vector3, yref: float, S: float) -> void:
	var b0: int = dst.v.size()
	for i in range(g.v.size()):
		dst.v.append(Vector3((g.v[i].x - c.x) * S, (g.v[i].y - yref) * S, (g.v[i].z - c.z) * S))
		dst.n.append(g.n[i]); dst.uv.append(Vector2.ZERO); dst.col.append(g.col[i])
	for i in g.idx:
		dst.idx.append(b0 + i)

func _write_data(data: Dictionary) -> void:
	var f := FileAccess.open("res://scripts/world/tracks_data.gd", FileAccess.WRITE)
	f.store_line("class_name TracksData")
	f.store_line("extends RefCounted")
	f.store_line("## GENERATED by tools/prepare_tracks.gd - do not edit.  Per track (track frame: x/z centred, y 0 = driving surface):")
	f.store_line("## half = half extents (x,z), gates = [x, z, dir_x, dir_z] in lap order (gate 0 is the start/finish line), kart = [x, z, dir_x, dir_z]")
	f.store_line("const DATA := {")
	for id in data:
		var d: Dictionary = data[id]
		f.store_line("\t\"%s\": {" % id)
		f.store_line("\t\t\"half\": Vector2(%.2f, %.2f)," % [d["half"].x, d["half"].y])
		f.store_line("\t\t\"ymax\": %.2f, \"ymin\": %.2f," % [d["ymax"], d["ymin"]])
		f.store_line("\t\t\"gate_w\": %.2f, \"road_w\": %.2f," % [d["gate_w"], d["road_w"]])
		f.store_line("\t\t\"gates\": %s," % str(d["gates"]))
		f.store_line("\t\t\"kart\": %s," % str(d["kart"]))
		f.store_line("\t\t\"carve\": %s," % str(d["carve"]))
		f.store_line("\t},")
	f.store_line("}")
	f.close()
