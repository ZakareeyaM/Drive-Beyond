class_name RaceTracks
extends Node3D
## The two race circuits south of the accommodation district, plus their go-karts and the lap system.
##   Track 1  "Riverside Raceway"  - low_poly_race_track.glb (scaled x4.5: a figure-of-eight style circuit with an at-grade crossing,
##                                   two rivers, pit lot with grid)
##   Track 2  "Grand Prix Circuit" - lowpoly_racetrack.glb  (full size: long circuit with a bridge crossing)
## The meshes / trimesh collision come from tools/prepare_tracks.gd (assets/tracks/*.res, gates in tracks_data.gd).
## Lap rule (per track): the lap is armed by crossing the start/finish gate (gate 0) in the driving direction; then every gate has to be
## crossed IN ORDER and IN THE DRIVING DIRECTION; crossing gate 0 again after the last gate pays LAP_REWARD.  Standing on the line, reversing
## over it, skipping gates or teleporting never pays (see update()).

const LAP_REWARD := 250
const DEF := {
	"a": {"name": "Riverside Raceway", "short": "Track 1", "c": Vector2(1800.0, 1560.0), "gy": 11.05, "pad": 10.95,
		"paddock": [Vector2(-114.0, -72.0), Vector2(-94.0, -72.0)], "entry": Vector2(-112.0, -72.0)},
	"b": {"name": "Grand Prix Circuit", "short": "Track 2", "c": Vector2(2100.0, 2000.0), "gy": 11.0, "pad": 10.92,
		"paddock": [], "entry": Vector2(-45.0, 66.0)},
}
const ORDER := ["a", "b"]
const ROAD_KIND := "country"
const VIS_FAR := 700.0           # track visuals + collision are only active within (half-diagonal + this) of the player

var tracks: Dictionary = {}      # id -> {root, body, trees, kart_prop, kart_pos, kart_yaw, state...}
var world = null
var _t_acc: float = 0.0
var _prev_pos := Vector3.ZERO
var _have_prev: bool = false
var laps_total: int = 0
var last_lap_time: float = 0.0
var best_lap: Dictionary = {}    # id -> seconds (this session)

# ------------------------------------------------------------------ world-gen hooks
static func world_of(id: String, local: Vector2) -> Vector2:
	return (DEF[id]["c"] as Vector2) + local

static func add_terrain(g: WorldGen) -> void:
	for id in ORDER:
		var d: Dictionary = TracksData.DATA[id]
		var half: Vector2 = d["half"] + Vector2(14.0, 14.0)
		var c: Vector2 = DEF[id]["c"]
		g.rect_pads.append({"r": Rect2(c.x - half.x, c.y - half.y, half.x * 2.0, half.y * 2.0), "h": float(DEF[id]["pad"]), "b": 60.0})
		for cv in d["carve"]:   # river beds of track 1 are cut below the tile's grass level
			var lo: float = float(DEF[id]["pad"]) - 2.1
			g.rect_pads.append({"r": Rect2(c.x + float(cv[0]), c.y + float(cv[1]), float(cv[2]), float(cv[3])), "h": lo, "b": 3.0})
		g.keepouts.append(Rect2(c.x - half.x - 30.0, c.y - half.y - 30.0, half.x * 2.0 + 60.0, half.y * 2.0 + 60.0))
	# flat corridor for the access road (dunes would otherwise roller-coaster it)
	for p in [Vector2(1695, 1180), Vector2(1685, 1290), Vector2(1675, 1400), Vector2(1665, 1700), Vector2(1700, 1800), Vector2(1790, 1895), Vector2(1900, 1960)]:
		g._pad(p.x, p.y, 22.0, 11.0, 40.0)

static func add_roads(g: WorldGen) -> void:
	var a: Vector2 = world_of("a", DEF["a"]["entry"])
	var b: Vector2 = world_of("b", DEF["b"]["entry"])
	g.add_road("avenue", [Vector2(1700, 1100), Vector2(1695, 1180), Vector2(1685, 1290), Vector2(1675, 1400), a], true, false, "Speedway Road")
	g.add_road("avenue", [a, Vector2(1665, 1590), Vector2(1665, 1700), Vector2(1700, 1800), Vector2(1790, 1895), Vector2(1900, 1960), Vector2(1990, 2030), b], true, false, "Speedway Road")

static func register(g: WorldGen) -> void:
	for id in ORDER:
		var c: Vector2 = DEF[id]["c"]
		g.landmarks["track_" + id] = Vector3(c.x, float(DEF[id]["gy"]), c.y)
	g.structures.append({"type": "raceway", "pos": Vector3((DEF["a"]["c"] as Vector2).x, 11.0, (DEF["a"]["c"] as Vector2).y), "size": Vector3(210.0, 20.0, 210.0)})
	g.structures.append({"type": "raceway", "pos": Vector3((DEF["b"]["c"] as Vector2).x, 11.0, (DEF["b"]["c"] as Vector2).y), "size": Vector3(250.0, 20.0, 240.0)})

# ------------------------------------------------------------------ build
func build(w) -> void:
	world = w
	name = "RaceTracks"
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for id in ORDER:
		_build_track(id, mat)

func _gate_world(id: String, i: int) -> Dictionary:
	var gt: Array = (TracksData.DATA[id]["gates"] as Array)[i]
	var c: Vector2 = DEF[id]["c"]
	var gp := Vector3(c.x + float(gt[0]), float(DEF[id]["gy"]), c.y + float(gt[1]))
	return {"p": gp, "d": Vector2(float(gt[2]), float(gt[3]))}

func _build_track(id: String, mat: Material) -> void:
	var def: Dictionary = DEF[id]
	var data: Dictionary = TracksData.DATA[id]
	var c: Vector2 = def["c"]
	var root := Node3D.new()
	root.name = "Track_" + id
	root.position = Vector3(c.x, float(def["gy"]), c.y)
	add_child(root)
	var mi := MeshInstance3D.new()
	mi.name = "Surface"
	mi.mesh = load("res://assets/tracks/track_%s.res" % id) as Mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var trees: MeshInstance3D = null
	if ResourceLoader.exists("res://assets/tracks/track_%s_trees.res" % id):
		trees = MeshInstance3D.new()
		trees.name = "Trees"
		trees.mesh = load("res://assets/tracks/track_%s_trees.res" % id) as Mesh
		trees.material_override = mat
		trees.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		trees.visibility_range_end = 520.0
		trees.visibility_range_end_margin = 40.0
		root.add_child(trees)
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.add_to_group("structure")
	var cs := CollisionShape3D.new()
	cs.shape = load("res://assets/tracks/track_%s_col.res" % id) as Shape3D
	body.add_child(cs)
	root.add_child(body)
	# paddock apron connecting the access road to the circuit
	if id == "b":
		_slab(root, Vector3(-37.5, 0.0, 61.5), Vector2(36.0, 34.0), Color(0.2, 0.2, 0.22))
	else:
		_slab(root, Vector3(-104.0, 0.0, -72.0), Vector2(24.0, 13.0), Color(0.2, 0.2, 0.22))
	# kart spot
	var kt: Array = data["kart"]
	var kpos := Vector3(c.x + float(kt[0]), float(def["gy"]) + 0.05, c.y + float(kt[1]))
	var kyaw: float = atan2(-float(kt[2]), -float(kt[3]))
	_start_arch(root, id)
	_sign(root, id, Vector3(float(kt[0]), 0.0, float(kt[1])) + Vector3(-float(kt[3]), 0, float(kt[2])) * 5.0)
	tracks[id] = {"root": root, "body": body, "cs": cs, "trees": trees, "kart_pos": kpos, "kart_yaw": kyaw, "kart_prop": null, "active": true,
		"armed": false, "next": 1, "t0": 0.0, "laps": 0, "gates": data["gates"].size()}
	world.pois.append({"id": "kart_" + id, "type": "kart", "track": id, "pos": kpos, "radius": 5.5, "label": "Go-Kart - " + String(def["name"])})
	world.make_beacon(kpos, Color(1.0, 0.75, 0.1), 12.0, 0.8)
	var kg: Vector3 = Vector3(kpos.x, kpos.y, kpos.z)
	set_kart_available(id, true)
	# the whole thing is only simulated/drawn near the player
	_set_active(id, false)

func _slab(root: Node3D, c: Vector3, size: Vector2, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, 0.3, size.y)
	mi.mesh = bm
	mi.position = Vector3(c.x, c.y - 0.18, c.z)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size.x, 0.3, size.y)
	cs.shape = bs
	cs.position = mi.position
	sb.add_child(cs)
	root.add_child(sb)

## start / finish arch over gate 0: two posts and a chequered banner
func _start_arch(root: Node3D, id: String) -> void:
	var gt: Array = (TracksData.DATA[id]["gates"] as Array)[0]
	var d := Vector2(float(gt[2]), float(gt[3]))
	var hw: float = float(TracksData.DATA[id]["road_w"]) * 0.5 + 1.5
	var yaw: float = atan2(-d.x, -d.y)
	var arch := Node3D.new()
	arch.position = Vector3(float(gt[0]), 0.0, float(gt[1]))
	arch.rotation.y = yaw
	root.add_child(arch)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.9, 0.9, 0.92)
	for sx in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, 7.0, 0.7)
		post.mesh = bm
		post.position = Vector3(sx * hw, 3.5, 0.0)
		post.material_override = pm
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arch.add_child(post)
	var ban := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(hw * 2.0, 1.6, 0.4)
	ban.mesh = bb
	ban.position = Vector3(0.0, 6.4, 0.0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.08, 0.08, 0.1)
	ban.material_override = bmat
	ban.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arch.add_child(ban)
	for side in [-1.0, 1.0]:
		var lb := Label3D.new()
		lb.text = "START / FINISH   $%d / LAP" % LAP_REWARD
		lb.font_size = 72
		lb.pixel_size = 0.012
		lb.modulate = Color(1.0, 0.85, 0.2)
		lb.outline_size = 8
		lb.position = Vector3(0.0, 6.4, side * 0.25)
		lb.rotation.y = 0.0 if side > 0.0 else PI
		lb.double_sided = false
		arch.add_child(lb)
	# gate-0 checker strip on the asphalt
	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(hw * 2.0 - 3.0, 0.03, 1.6)
	strip.mesh = sm
	strip.position = Vector3(0.0, 0.45, 0.0)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.95, 0.95, 0.95)
	smat.roughness = 1.0
	strip.material_override = smat
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	strip.visible = false      # the models already carry their own finish-line texture
	arch.add_child(strip)

func _sign(root: Node3D, id: String, local: Vector3) -> void:
	var lb := Label3D.new()
	lb.text = "%s\n%s\nGo-kart available here  -  $%d per lap" % [String(DEF[id]["short"]).to_upper(), DEF[id]["name"], LAP_REWARD]
	lb.font_size = 56
	lb.pixel_size = 0.01
	lb.modulate = Color(1.0, 0.9, 0.3)
	lb.outline_size = 10
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.position = local + Vector3(0, 4.2, 0)
	lb.visibility_range_end = 160.0
	root.add_child(lb)

# ------------------------------------------------------------------ kart prop (stationary go-kart at each track)
func kart_spot(id: String) -> Dictionary:
	return {"pos": tracks[id]["kart_pos"], "yaw": tracks[id]["kart_yaw"]}

func set_kart_available(id: String, on: bool) -> void:
	var t: Dictionary = tracks[id]
	if t["kart_prop"] == null:
		var vid: String = Data.KART_ID
		var spec: Dictionary = Data.vehicle(vid)
		var m: Dictionary = CarBuilder.build(vid, Data.default_custom(vid))
		var root: Node3D = m["root"]
		var holder := Node3D.new()
		holder.name = "KartProp_" + id
		holder.add_child(root)
		for fz in [-1.0, 1.0]:
			for sx in [-1.0, 1.0]:
				var wv: MeshInstance3D = CarBuilder.make_wheel_visual(m, vid, Data.default_custom(vid), (2 if fz > 0.0 else 0) + (1 if sx > 0.0 else 0))
				wv.position = Vector3(sx * float(spec["track"]) * 0.5, float(spec["wr"]), fz * float(spec["wb"]) * 0.5)
				root.add_child(wv)
		var body := StaticBody3D.new()
		body.name = "Body"
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(float(spec["W"]) * 0.95, float(spec["roof"]) - 0.1, float(spec["L"]) * 0.95)
		cs.shape = bs
		cs.position = Vector3(0, 0.1 + bs.size.y * 0.5, 0)
		body.add_child(cs)
		holder.add_child(body)
		holder.position = t["kart_pos"]
		holder.rotation.y = t["kart_yaw"]
		add_child(holder)
		t["kart_prop"] = holder
		_settle_kart(id)
	var prop: Node3D = t["kart_prop"]
	prop.visible = on
	for c in (prop.get_node("Body") as StaticBody3D).get_children():
		(c as CollisionShape3D).disabled = not on
	t["kart_free"] = on

## drop the parked kart onto the real surface once the track collision exists (no floating / buried kart)
func _settle_kart(id: String) -> void:
	await get_tree().create_timer(1.5).timeout
	var t: Dictionary = tracks[id]
	var prop: Node3D = t["kart_prop"]
	if prop == null or not is_inside_tree():
		return
	var p: Vector3 = t["kart_pos"]
	_set_active(id, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var pbody: StaticBody3D = prop.get_node("Body") as StaticBody3D
	pbody.collision_layer = 0          # the ray must hit the circuit, not the kart's own body
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 6.0, p.z), Vector3(p.x, p.y - 8.0, p.z), 1)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	pbody.collision_layer = 1
	if not hit.is_empty():
		t["kart_pos"] = Vector3(p.x, (hit["position"] as Vector3).y, p.z)
		prop.position = t["kart_pos"]
		for poi in world.pois:
			if poi.get("id", "") == "kart_" + id:
				poi["pos"] = t["kart_pos"]

# ------------------------------------------------------------------ streaming-ish activation
func _set_active(id: String, on: bool) -> void:
	var t: Dictionary = tracks[id]
	if bool(t["active"]) == on:
		return
	t["active"] = on
	(t["root"] as Node3D).visible = on
	(t["cs"] as CollisionShape3D).set_deferred("disabled", not on)
	if t["kart_prop"] != null:
		(t["kart_prop"] as Node3D).visible = on and bool(t.get("kart_free", true))

func track_at(p: Vector3, margin: float = 0.0) -> String:
	for id in ORDER:
		var c: Vector2 = DEF[id]["c"]
		var h: Vector2 = (TracksData.DATA[id]["half"] as Vector2) + Vector2(margin, margin)
		if absf(p.x - c.x) < h.x and absf(p.z - c.y) < h.y:
			return id
	return ""

# ------------------------------------------------------------------ lap system
func update(dt: float, p: Vector3, driving: bool) -> void:
	_t_acc += dt
	if _t_acc >= 0.5:
		_t_acc = 0.0
		for id in ORDER:
			var c: Vector2 = DEF[id]["c"]
			var far: float = (TracksData.DATA[id]["half"] as Vector2).length() + VIS_FAR
			var near: bool = Vector2(p.x - c.x, p.z - c.y).length() < far
			if near != bool(tracks[id]["active"]):
				if near:
					tracks[id]["root"].visible = true
				_set_active(id, near)
	if not driving:
		_have_prev = false
		for id in ORDER:
			tracks[id]["armed"] = false
		return
	if not _have_prev or p.distance_to(_prev_pos) > 60.0:     # first frame / teleport / respawn: nothing may count
		_prev_pos = p
		_have_prev = true
		for id in ORDER:
			tracks[id]["armed"] = false
		return
	var id2: String = track_at(p, 40.0)
	for id in ORDER:
		if id != id2:
			tracks[id]["armed"] = false
	if id2 != "":
		_check_gates(id2, _prev_pos, p)
	_prev_pos = p

func _check_gates(id: String, a: Vector3, b: Vector3) -> void:
	var t: Dictionary = tracks[id]
	var n: int = int(t["gates"])
	var gw: float = float(TracksData.DATA[id]["gate_w"]) * 0.5
	for gi in range(n):
		var g: Dictionary = _gate_world(id, gi)
		var gp: Vector3 = g["p"]
		var d: Vector2 = g["d"]
		var sa: float = (a.x - gp.x) * d.x + (a.z - gp.z) * d.y
		var sb: float = (b.x - gp.x) * d.x + (b.z - gp.z) * d.y
		if not (sa < 0.0 and sb >= 0.0):          # must cross the line in the driving direction
			continue
		var k: float = sa / (sa - sb)
		var cx: float = lerpf(a.x, b.x, k)
		var cz: float = lerpf(a.z, b.z, k)
		var lat: float = (cx - gp.x) * -d.y + (cz - gp.z) * d.x
		if absf(lat) > gw:
			continue
		var cy: float = lerpf(a.y, b.y, k)
		if absf(cy - _ground_ref(id, gi, gp)) > 5.5:   # e.g. on the bridge above a gate that lies under it
			continue
		_gate_crossed(id, gi)

func _ground_ref(id: String, gi: int, gp: Vector3) -> float:
	return world.gen.ground_h(gp.x, gp.z) + 0.6 if gi >= 0 else gp.y

func _gate_crossed(id: String, gi: int) -> void:
	var t: Dictionary = tracks[id]
	var n: int = int(t["gates"])
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if gi == 0:
		if bool(t["armed"]) and int(t["next"]) == 0:
			var lt: float = now - float(t["t0"])
			if lt >= min_lap_time(id):
				_award(id, lt)
			else:
				Game.notify.emit("Lap not counted (too fast - keep to the circuit)", "warn")
		elif bool(t["armed"]) and int(t["next"]) != 0:
			Game.notify.emit("Lap restarted - checkpoints %d/%d" % [int(t["next"]) - 1, n - 1], "info")
		else:
			Game.notify.emit("Lap started - %s" % DEF[id]["name"], "info")
		t["armed"] = true
		t["next"] = 1
		t["t0"] = now
		return
	if not bool(t["armed"]):
		return
	if gi == int(t["next"]):
		t["next"] = (gi + 1) % n        # after the last gate the next one is the finish line (index 0)
		if int(t["next"]) != 0:
			Game.notify.emit("Checkpoint %d / %d" % [gi, n - 1], "info")
		else:
			Game.notify.emit("Final checkpoint - cross the finish line", "info")

func min_lap_time(id: String) -> float:
	return 14.0 if id == "a" else 28.0

func _award(id: String, lt: float) -> void:
	laps_total += 1
	tracks[id]["laps"] = int(tracks[id]["laps"]) + 1
	last_lap_time = lt
	if not best_lap.has(id) or lt < float(best_lap[id]):
		best_lap[id] = lt
	Game.add_money(LAP_REWARD, "Lap complete")
	Game.notify.emit("%s  lap %d  -  %s  (best %s)" % [DEF[id]["name"], int(tracks[id]["laps"]), _fmt_t(lt), _fmt_t(float(best_lap[id]))], "info")
	Game.save_game()

static func _fmt_t(s: float) -> String:
	return "%d:%04.1f" % [int(s) / 60, fmod(s, 60.0)]

## chronometer for the HUD / tests: [track name, current lap seconds, next gate, gates] or [] when not on a lap
func hud_info() -> Array:
	for id in ORDER:
		var t: Dictionary = tracks[id]
		if bool(t["armed"]):
			return [DEF[id]["name"], float(Time.get_ticks_msec()) / 1000.0 - float(t["t0"]), int(t["next"]), int(t["gates"])]
	return []
