extends SceneTree
## Offline vehicle preparation:   godot --headless --path . -s tools/prepare_fleet.gd -- <id> [<id>...]
## Turns a raw multi-part car GLB (hundreds of meshes, PBR materials, wrong scale/orientation) into a lean, game-ready
## GLB  assets/vehicles/fleet/<id>.glb :
##   Body     one MeshInstance3D, a handful of surfaces (paint / solid vertex-coloured parts / glass / head+tail lamps /
##            the few textured materials), decimated to the per-car triangle budget
##   Wheel_0..3  tyre + rim + brake per wheel, re-centred on the axle (0 front -X, 1 front +X, 2 rear -X, 3 rear +X)
## metres, nose = -Z, origin on the ground between the axles.  The source GLB is never modified.
## It also writes tools/fleet_report.json (dimensions, wheel radius, headlight / tail-light positions found from the geometry).

const SRC_DIR := "/tmp/newcars/"
const OUT_DIR := "res://assets/vehicles/fleet/"
const TEX_MAX := 1024

# per-car settings. budget = triangles for body (wheels are budgeted separately)
const CARS := {
	"countach": {"src": "countach.glb", "scale": 100.0, "budget": 26000, "paint": "CarPaint", "wheel_budget": 2500},
	"m3_gtr": {"src": "m3.glb", "scale": 100.0, "budget": 26000, "paint": "Carpaint", "wheel_budget": 2500},
	"sesto": {"src": "sesto.glb", "scale": 100.0, "budget": 26000, "paint": "NOPAINT", "wheel_budget": 2500},
	"nsx": {"src": "nsx.glb", "scale": 100.0, "budget": 28000, "paint": "PaintA", "wheel_budget": 2500},
	"gclass": {"src": "gclass.glb", "scale": 100.0, "budget": 30000, "paint": "Paint_Material", "wheel_budget": 2500},
	"mustang": {"src": "mustang.glb", "scale": 100.0, "budget": 28000, "paint": "Paint_Material", "wheel_budget": 2500},
	"airport_car": {"src": "airport_car.glb", "scale": 1.6, "budget": 12000, "paint": "Material_001", "wheel_budget": 1200},
	"amg_one": {"src": "amg_one.glb", "scale": 1.0, "budget": 30000, "paint": "amgprojone_paint", "wheel_budget": 2500},
	"civic": {"src": "civic.glb", "scale": 100.0, "budget": 26000, "paint": "Paint_Material", "wheel_budget": 2500, "tall_tyre": true},
	"camaro": {"src": "camaro.glb", "scale": 1.0, "budget": 24000, "paint": "NOPAINT", "wheel_budget": 2500, "skip": "(?i)blur", "tall_tyre": true},
	"c63": {"src": "c63.glb", "scale": 1.0, "budget": 26000, "paint": "NOPAINT", "wheel_budget": 2500, "skip": "(?i)position_front_and_back", "tall_tyre": true},
}
const WHEEL_RX := "(?i)tire|tyre|wheel|rim|calli|caliper|calier|brake|breaks|disk|disc|hubdecal"
const GLASS_RX := "(?i)window|clearglass|^glass|_glass$|cglass|^cglass|mglass"
const LAMP_RX := "(?i)light|lamp"
const LENS_RX := "(?i)red_glass|orange_glass|light_glass|redglass|orange"

func _initialize() -> void:
	var ids: PackedStringArray = OS.get_cmdline_user_args()
	var report: Dictionary = {}
	if FileAccess.file_exists("res://tools/fleet_report.json"):
		report = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fleet_report.json"))
	for id in ids:
		if CARS.has(id):
			report[id] = _prepare(id, CARS[id])
	var f := FileAccess.open("res://tools/fleet_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	quit()

# ---------------------------------------------------------------------------------------------- helpers
static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var cur: Transform3D = xf
	if n is Node3D:
		cur = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append({"mi": n, "xf": cur})
	for c in n.get_children():
		_collect(c, cur, out)

func _surf_arrays(mi: MeshInstance3D, s: int, xf: Transform3D) -> Dictionary:
	var arr: Array = mi.mesh.surface_get_arrays(s)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx.resize(v.size())
		for i in range(v.size()):
			idx[i] = i
	return {"v": v, "n": nrm, "uv": uv, "i": idx, "mat": mi.mesh.surface_get_material(s)}

class Group:
	var name: String
	var mat: Material
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	var use_col := false
	var textured := false

	func add(d: Dictionary, xf: Transform3D, color: Color) -> void:
		var base: int = v.size()
		var b: Basis = xf.basis.inverse().transposed()
		var src_v: PackedVector3Array = d["v"]
		var src_n: PackedVector3Array = d["n"]
		var src_uv: PackedVector2Array = d["uv"]
		for k in range(src_v.size()):
			v.append(xf * src_v[k])
			n.append((b * src_n[k]).normalized() if src_n.size() == src_v.size() else Vector3.UP)
			uv.append(src_uv[k] if src_uv.size() == src_v.size() else Vector2.ZERO)
			col.append(color)
		for i in d["i"]:
			idx.append(base + i)

func _mat_name(m: Material) -> String:
	return m.resource_name if m else ""

func _base_color(m: Material) -> Color:
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_color
	return Color(0.5, 0.5, 0.5)

func _small_tex(t: Texture2D, maxs: int) -> Texture2D:
	if t == null:
		return null
	var img: Image = t.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	var m: int = maxi(img.get_width(), img.get_height())
	if m > maxs:
		var k: float = float(maxs) / float(m)
		img.resize(maxi(4, int(img.get_width() * k)), maxi(4, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

## simplify one surface to ~target triangles using the engine's attribute-aware mesh optimiser (repeated passes)
func _decimate(g: Group, target_tris: int) -> void:
	for pass_i in range(6):
		var tris: int = g.idx.size() / 3
		if tris <= target_tris or tris < 60:
			return
		if not _decimate_once(g, target_tris):
			return

func _decimate_once(g: Group, target_tris: int) -> bool:
	var before: int = g.idx.size()
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = g.v
	arr[Mesh.ARRAY_NORMAL] = g.n
	arr[Mesh.ARRAY_TEX_UV] = g.uv
	arr[Mesh.ARRAY_COLOR] = g.col
	arr[Mesh.ARRAY_INDEX] = g.idx
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr)
	im.generate_lods(60.0, 25.0, [])
	var best: int = -1
	var lods: int = im.get_surface_lod_count(0)
	var want: int = target_tris * 3
	for l in range(lods):
		if im.get_surface_lod_size(0, l) <= want:
			best = l
			break
	if best < 0 and lods > 0:
		best = lods - 1
	if best < 0:
		return false
	var new_idx: PackedInt32Array = im.get_surface_lod_indices(0, best)
	if new_idx.size() >= before * 0.97:
		return false
	var remap := {}
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	var nuv := PackedVector2Array()
	var nc := PackedColorArray()
	var ni := PackedInt32Array()
	for i in new_idx:
		if not remap.has(i):
			remap[i] = nv.size()
			nv.append(g.v[i])
			nn.append(g.n[i])
			nuv.append(g.uv[i])
			nc.append(g.col[i])
		ni.append(remap[i])
	g.v = nv
	g.n = nn
	g.uv = nuv
	g.col = nc
	g.idx = ni
	return true

func _commit(groups: Array, name: String) -> ArrayMesh:
	var am := ArrayMesh.new()
	am.resource_name = name
	for g in groups:
		if g.idx.is_empty():
			continue
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = g.v
		arr[Mesh.ARRAY_NORMAL] = g.n
		arr[Mesh.ARRAY_TEX_UV] = g.uv
		if g.use_col:
			arr[Mesh.ARRAY_COLOR] = g.col
		arr[Mesh.ARRAY_INDEX] = g.idx
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(am.get_surface_count() - 1, g.mat)
		am.surface_set_name(am.get_surface_count() - 1, g.name)
	return am

func _solid_material(name: String, metallic: float, rough: float, alpha: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = name
	m.vertex_color_use_as_albedo = true
	m.metallic = metallic
	m.roughness = rough
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

# ---------------------------------------------------------------------------------------------- main
func _prepare(id: String, cfg: Dictionary) -> Dictionary:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(SRC_DIR + String(cfg["src"]), st) != OK:
		push_error("cannot load " + id)
		return {}
	var root: Node = doc.generate_scene(st)
	var pieces: Array = []
	_collect(root, Transform3D.IDENTITY, pieces)
	if cfg.has("skip"):   # drop pieces by name (e.g. transparent wheel-blur discs that would render as solid)
		var srx := RegEx.new(); srx.compile(String(cfg["skip"]))
		pieces = pieces.filter(func(q): return srx.search(String((q["mi"] as MeshInstance3D).name)) == null)
	var S: float = float(cfg["scale"])
	var wrx := RegEx.new(); wrx.compile(WHEEL_RX)
	var grx := RegEx.new(); grx.compile(GLASS_RX)
	var lrx := RegEx.new(); lrx.compile(LAMP_RX)
	var lensrx := RegEx.new(); lensrx.compile(LENS_RX)
	# ---- overall bounds (scaled) and nose direction
	var all := AABB()
	var first := true
	for p in pieces:
		var mi: MeshInstance3D = p["mi"]
		var ab: AABB = (p["xf"] as Transform3D) * mi.get_aabb()
		all = ab if first else all.merge(ab)
		first = false
	var ctr: Vector3 = all.get_center()
	# rear = side where red lens / tail pieces live
	var red_z: float = 0.0
	var red_n: int = 0
	for p in pieces:
		var mi2: MeshInstance3D = p["mi"]
		for s in range(mi2.mesh.get_surface_count()):
			if String(_mat_name(mi2.mesh.surface_get_material(s))).to_lower().contains("red"):
				red_z += (((p["xf"] as Transform3D) * mi2.get_aabb()).get_center().z - ctr.z)
				red_n += 1
	var nose_sign: float = -1.0 if red_z / maxf(1.0, red_n) > 0.0 else 1.0   # +1: nose at +z in source
	# source -> car space: scale, rotate so the nose is -Z, then translate (done once the wheels are known)
	var rot := Basis(Vector3.UP, PI) if nose_sign > 0.0 else Basis.IDENTITY
	var base := Transform3D(rot * Basis.from_scale(Vector3.ONE * S), Vector3.ZERO)
	# ---- classify pieces
	var wheel_pcs: Array = []
	var body_pcs: Array = []
	for p in pieces:
		var mi3: MeshInstance3D = p["mi"]
		var is_w: bool = false
		var xf: Transform3D = base * (p["xf"] as Transform3D)
		var ab2: AABB = xf * mi3.get_aabb()
		var mn: String = ""
		for s in range(mi3.mesh.get_surface_count()):
			mn += _mat_name(mi3.mesh.surface_get_material(s)) + "|"
		var big: bool = ab2.size.x > 1.2 or ab2.size.z > 1.2 or ab2.size.y > 1.2
		if (wrx.search(mn) != null or wrx.search(String(mi3.name)) != null) and not big:
			is_w = true
		(wheel_pcs if is_w else body_pcs).append(p)
	# ---- wheel groups by quadrant of the (car-space) piece centres
	var cc: Vector3 = base * ctr
	var wh: Array = [[], [], [], []]
	for p in wheel_pcs:
		var mi4: MeshInstance3D = p["mi"]
		var c: Vector3 = ((base * (p["xf"] as Transform3D)) * mi4.get_aabb()).get_center()
		var idx: int = (2 if c.z > cc.z else 0) + (1 if c.x > cc.x else 0)
		(wh[idx] as Array).append(p)
	var wb: Array = []
	for i in range(4):
		var b2 := AABB()
		var f2 := true
		for p in wh[i]:
			var mi5: MeshInstance3D = p["mi"]
			var ab3: AABB = (base * (p["xf"] as Transform3D)) * mi5.get_aabb()
			b2 = ab3 if f2 else b2.merge(ab3)
			f2 = false
		wb.append(b2)
	# tyre = the tallest piece of wheel 0 ; use the merged bbox of tyre-material pieces for radius if possible
	var wr: float = 0.0
	var wcen: Array = []
	for i in range(4):
		var tb := AABB()
		var ft := true
		for p in wh[i]:
			var mi6: MeshInstance3D = p["mi"]
			var ab4: AABB = (base * (p["xf"] as Transform3D)) * mi6.get_aabb()
			if ab4.size.y > (wb[i] as AABB).size.y * 0.85:
				tb = ab4 if ft else tb.merge(ab4)
				ft = false
		wcen.append(tb.get_center() if not ft else (wb[i] as AABB).get_center())
		wr = maxf(wr, tb.size.y * 0.5 if not ft else (wb[i] as AABB).size.y * 0.5)
	# robustness: one wheel of an axle may have swallowed a stray piece (inflated bbox) -> take y/z (and radius) from its partner
	wr = 0.0
	for pr in [[0, 1], [2, 3]]:
		var a_i: int = pr[0]
		var b_i: int = pr[1]
		var ca: Vector3 = wcen[a_i]
		var cb: Vector3 = wcen[b_i]
		if absf(ca.y - cb.y) > 0.04 or absf(ca.z - cb.z) > 0.04:
			var good: int = a_i if (wb[a_i] as AABB).size.y <= (wb[b_i] as AABB).size.y else b_i
			var bad: int = b_i if good == a_i else a_i
			var cg: Vector3 = wcen[good]
			var cbad: Vector3 = wcen[bad]
			wcen[bad] = Vector3(-cg.x + 2.0 * cc.x if absf(cbad.x - (-cg.x + 2.0 * cc.x)) > 0.05 else cbad.x, cg.y, cg.z)
			print("  fixed wheel %d centre -> %s" % [bad, str(wcen[bad])])
		wr = maxf(wr, minf((wb[a_i] as AABB).size.y, (wb[b_i] as AABB).size.y) * 0.5)
	var axle_mid := Vector3.ZERO
	for c in wcen:
		axle_mid += (c as Vector3) * 0.25
	var ground: float = axle_mid.y - wr
	var origin := Vector3(cc.x, ground, axle_mid.z)
	var carxf := Transform3D(Basis.IDENTITY, -origin) * base
	print("%s: nose_in_source=%+.0f scale=%.0f wheel_r=%.3f wheelbase=%.2f track=%.2f pieces body=%d wheel=%d" % [id, nose_sign, S, wr, absf((wcen[0] as Vector3).z - (wcen[2] as Vector3).z), absf((wcen[0] as Vector3).x - (wcen[1] as Vector3).x), body_pcs.size(), wheel_pcs.size()])
	# ---- body surfaces
	var paint_name: String = String(cfg["paint"])
	var groups: Dictionary = {}
	var order: Array = []
	var head_pts: Array = []
	var tail_pts: Array = []
	var paint_col := Color(0.5, 0.5, 0.5)
	var half_len: float = all.size.z * S * 0.5
	for p in body_pcs:
		var mi7: MeshInstance3D = p["mi"]
		var xf2: Transform3D = carxf * (p["xf"] as Transform3D)
		var pab: AABB = xf2 * mi7.get_aabb()
		for s in range(mi7.mesh.get_surface_count()):
			var d: Dictionary = _surf_arrays(mi7, s, xf2)
			var m: Material = d["mat"]
			var mname: String = _mat_name(m)
			var col: Color = _base_color(m)
			var key: String
			if paint_name != "NOPAINT" and mname.contains(paint_name):
				key = "paint"
				paint_col = col
			elif lensrx.search(mname) != null and pab.get_center().z > 0.0:
				key = "tail"
			elif lensrx.search(mname) != null:
				key = "lens_front"
			elif lrx.search(mname) != null or lrx.search(String(mi7.name)) != null and mname.to_lower().contains("light"):
				key = "head" if pab.get_center().z < 0.0 else "tail"
				if key == "head":
					head_pts.append(pab.get_center())
				else:
					tail_pts.append(pab.get_center())
			elif grx.search(mname) != null:
				key = "glass"
			elif m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture != null and _is_big_tex(m):
				key = "tex:" + mname
			else:
				key = "solid"
			if not groups.has(key):
				var g := Group.new()
				g.name = key.replace("tex:", "tex_")
				g.use_col = true
				if key == "paint":
					g.mat = _solid_material("paint", 0.45, 0.28)
				elif key == "glass":
					g.mat = _solid_material("glass", 0.2, 0.05, true)
				elif key == "head" or key == "tail" or key == "lens_front":
					g.mat = _solid_material("lamp_" + key, 0.0, 0.2)
				elif key == "solid":
					g.mat = _solid_material("solid", 0.35, 0.5)
				else:
					var sm := StandardMaterial3D.new()
					sm.resource_name = key.replace("tex:", "")
					sm.albedo_texture = _small_tex((m as BaseMaterial3D).albedo_texture, TEX_MAX)
					sm.albedo_color = (m as BaseMaterial3D).albedo_color
					sm.metallic = 0.3
					sm.roughness = 0.5
					if (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
						sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					sm.cull_mode = (m as BaseMaterial3D).cull_mode
					g.mat = sm
					g.textured = true
					g.use_col = false
				groups[key] = g
				order.append(key)
			var gg: Group = groups[key]
			var cc2: Color = Color.WHITE if gg.textured else col
			if key == "glass":
				cc2 = Color(0.05, 0.07, 0.1, 0.55)
			gg.add(d, xf2, cc2)
	# ---- decimate body proportionally
	var total: int = 0
	for k in order:
		total += (groups[k] as Group).idx.size() / 3
	var ratio: float = minf(1.0, float(cfg["budget"]) / maxf(1.0, total))
	for k in order:
		var g2: Group = groups[k]
		if k == "glass" or k == "head" or k == "tail" or k == "lens_front":
			_decimate(g2, int(g2.idx.size() / 3 * minf(1.0, ratio * 2.0)))
		else:
			_decimate(g2, int(g2.idx.size() / 3 * ratio))
	var body_groups: Array = []
	var tris_after: int = 0
	for k in order:
		body_groups.append(groups[k])
		tris_after += (groups[k] as Group).idx.size() / 3
	var body_mesh: ArrayMesh = _commit(body_groups, "Body")
	# ---- wheels
	var wheel_meshes: Array = []
	var wheel_tris: int = 0
	for i in range(4):
		var wc: Vector3 = (wcen[i] as Vector3) - origin
		var wg: Dictionary = {}
		var worder: Array = []
		for p in wh[i]:
			var mi8: MeshInstance3D = p["mi"]
			var xf3: Transform3D = Transform3D(Basis.IDENTITY, -wc) * carxf * (p["xf"] as Transform3D)
			for s in range(mi8.mesh.get_surface_count()):
				var d2: Dictionary = _surf_arrays(mi8, s, xf3)
				var m2: Material = d2["mat"]
				var nm2: String = _mat_name(m2).to_lower()
				var kk: String = "tyre" if (nm2.contains("tire") or nm2.contains("tyre")) else "rim"
				if cfg.get("tall_tyre", false) and ((base * (p["xf"] as Transform3D)) * mi8.get_aabb()).size.y > (wb[i] as AABB).size.y * 0.9:
					kk = "tyre"   # the tallest piece of a wheel is its rubber (models whose tyre has no tyre-named material)
				if not wg.has(kk):
					var g3 := Group.new()
					g3.name = kk
					g3.use_col = true
					g3.mat = _solid_material(kk, 0.1 if kk == "tyre" else 0.7, 0.9 if kk == "tyre" else 0.35)
					wg[kk] = g3
					worder.append(kk)
				var col3: Color = _base_color(m2)
				if kk == "tyre":
					col3 = Color(0.04, 0.04, 0.045)
				var gg: Group = wg[kk]
				var v0: int = gg.v.size()
				if kk == "rim" and col3.get_luminance() > 0.85:
					col3 = Color(0.62, 0.64, 0.68)
				gg.add(d2, xf3, col3)
				if kk == "rim":   # outer band of a wheel that has no separate tyre material = rubber
					for q in range(v0, gg.v.size()):
						if Vector2(gg.v[q].y, gg.v[q].z).length() > 0.76 * wr:
							gg.col[q] = Color(0.04, 0.04, 0.045)
		var tt: int = 0
		for k in worder:
			tt += (wg[k] as Group).idx.size() / 3
		var wratio: float = minf(1.0, float(cfg["wheel_budget"]) / maxf(1.0, tt))
		var wgl: Array = []
		for k in worder:
			_decimate(wg[k], int((wg[k] as Group).idx.size() / 3 * wratio))
			wgl.append(wg[k])
			wheel_tris += (wg[k] as Group).idx.size() / 3
		wheel_meshes.append(_commit(wgl, "Wheel_%d" % i))
	# ---- assemble + export
	var out := Node3D.new()
	out.name = id
	var bmi := MeshInstance3D.new()
	bmi.name = "Body"
	bmi.mesh = body_mesh
	out.add_child(bmi)
	bmi.owner = out
	for i in range(4):
		var wmi := MeshInstance3D.new()
		wmi.name = "Wheel_%d" % i
		wmi.mesh = wheel_meshes[i]
		wmi.position = (wcen[i] as Vector3) - origin
		out.add_child(wmi)
		wmi.owner = out
	var bb: AABB = body_mesh.get_aabb()
	var gd := GLTFDocument.new()
	gd.set_image_format("JPEG")
	gd.lossy_quality = 0.85
	var gs := GLTFState.new()
	gd.append_from_scene(out, gs)
	gd.write_to_filesystem(gs, OUT_DIR + id + ".glb")
	var rep := {
		"zmin": bb.position.z, "zmax": bb.end.z, "width": bb.size.x, "height": bb.size.y,
		"wheel_r": wr, "wheel_y": (wcen[0] as Vector3).y - origin.y,
		"wheel_x": absf((wcen[1] as Vector3).x - (wcen[0] as Vector3).x) * 0.5,
		"front_z": (wcen[0] as Vector3).z - origin.z, "rear_z": (wcen[2] as Vector3).z - origin.z,
		"paint_rgb": [paint_col.r, paint_col.g, paint_col.b],
		"head": _pts_json(head_pts, origin, carxf), "tail": _pts_json(tail_pts, origin, carxf),
		"tris_body": tris_after, "tris_wheels": wheel_tris, "tris_source": total,
	}
	print("  -> %s body %d tris (from %d), wheels %d, size %.2f x %.2f x %.2f, surfaces %d" % [id, tris_after, total, wheel_tris, bb.size.x, bb.size.y, bb.size.z, body_mesh.get_surface_count()])
	root.free()
	return rep

func _is_big_tex(m: Material) -> bool:
	var t: Texture2D = (m as BaseMaterial3D).albedo_texture
	return t != null and t.get_width() >= 256

func _pts_json(pts: Array, origin: Vector3, _x: Transform3D) -> Array:
	var r: Array = []
	for p in pts:
		r.append([p.x, p.y, p.z])
	return r
