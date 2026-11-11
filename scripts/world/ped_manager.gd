class_name PedManager
extends Node
## Pedestrians.  Kinematic (no physics bodies), no per-ped skeleton: the 8 characters of just_people.glb are baked into 8 stride
## poses each (tools/prepare_world.gd job people) and the pose mesh is swapped by walk phase.
##  - edge walkers follow the sidewalks of the road graph (city, suburbs, business + resort districts, airport roads)
##  - zone walkers wander inside free rectangles (terminal plaza, parking aisles): pick a target, walk, pause, repeat
## Tiers: near (< NEAR_D) animated every frame, mid (< FAR_D) animated + moved at 4 Hz, beyond DESPAWN_D returned to a pool.
## Pedestrians pause when the player stands in their way and dive away when a car hits them.

const NEAR_D := 55.0
const FAR_D := 130.0
const DESPAWN_D := 170.0
const FRAMES := 8
const CYCLE_S := 1.2037          # duration of one baked stride cycle at natural speed
const NATURAL_SPEED := 1.4

var world: World
var peds: Array = []         # {node, mesh, kind, edge, s, dir, off, speed, state, t, ph, frame, ...}
var pool: Array = []         # idle MeshInstance3D roots ready for reuse
var spawn_t: float = 0.0
var mid_t: float = 0.0
var limit_scale: float = 1.0 # lowered by the frame-rate monitor
var fps_lo_t: float = 0.0
var fps_hi_t: float = 0.0
static var frames_cache: Array = []   # [char][frame] -> ArrayMesh
static var idle_frame: Array = []     # per char: the frame with the legs closest together

static func load_frames() -> void:
	if not frames_cache.is_empty():
		return
	for c in range(8):
		var am: ArrayMesh = load("res://assets/world/people/ped_%d.res" % c) as ArrayMesh
		var fr: Array = []
		var best: int = 0
		var best_w: float = INF
		for f in range(am.get_surface_count()):
			var fm := ArrayMesh.new()
			fm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, am.surface_get_arrays(f))
			fm.surface_set_material(0, am.surface_get_material(f))
			fr.append(fm)
			var w: float = fm.get_aabb().size.x
			if w < best_w:
				best_w = w
				best = f
		frames_cache.append(fr)
		idle_frame.append(best)

func clear() -> void:
	for p in peds:
		(p["node"] as Node).queue_free()
	peds.clear()
	for n in pool:
		(n as Node).queue_free()
	pool.clear()

func _max() -> int:
	var base: int = 22
	match String(Game.settings.get("quality", "Medium")):
		"Low": base = 6
		"Medium": base = 10
		"High": base = 16
	return maxi(2, int(round(float(base) * limit_scale)))

func _zone_max() -> int:
	return maxi(1, int(round(float(_max()) * 0.4)))

# ---------------------------------------------------------------------------------------------------- visuals / pool
func _make_visual() -> Dictionary:
	load_frames()
	var root: Node3D
	var mi: MeshInstance3D
	if not pool.is_empty():
		root = pool.pop_back()
		root.visible = true
		root.rotation = Vector3.ZERO
		mi = root.get_child(0) as MeshInstance3D
	else:
		root = Node3D.new()
		mi = MeshInstance3D.new()
		mi.rotation.y = PI * 0.5            # the baked characters face +X, the walker logic faces -Z
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = FAR_D + 40.0
		root.add_child(mi)
		world.add_child(root)
	var ch: int = randi() % 8
	mi.mesh = frames_cache[ch][0]
	return {"root": root, "mesh": mi, "char": ch}

func _release(p: Dictionary) -> void:
	var n: Node3D = p["node"]
	n.visible = false
	n.rotation = Vector3.ZERO
	pool.append(n)

func _set_frame(p: Dictionary, f: int) -> void:
	if int(p["frame"]) != f:
		p["frame"] = f
		(p["mesh"] as MeshInstance3D).mesh = frames_cache[int(p["char"])][f]

# ---------------------------------------------------------------------------------------------------- main loop
func _physics_process(dt: float) -> void:
	if not world.running or world.mode == "menu":
		return
	_monitor(dt)
	var pp: Vector3 = world.player_pos()
	var area: String = WorldExpansion.zone_at(pp.x, pp.z)
	var in_city: bool = area != "" or world.gen.region_at(pp.x, pp.z) in ["city", "suburb", "coast"]
	spawn_t -= dt
	if spawn_t <= 0.0 and in_city:
		spawn_t = 0.6
		if peds.size() < _max():
			_spawn_edge(pp)
		if area == "airport" or pp.distance_to(Vector3(1885.0, pp.y, 520.0)) < 160.0:
			_spawn_zone(pp)
	mid_t += dt
	var mid_tick: bool = mid_t >= 0.25
	var mid_dt: float = mid_t
	if mid_tick:
		mid_t = 0.0
	var car: Vehicle = world.player_car if world.mode == "drive" else null
	var foot: bool = world.mode == "foot"
	for p in peds.duplicate():
		var n: Node3D = p["node"]
		var d: float = n.global_position.distance_to(pp)
		if d > DESPAWN_D:
			peds.erase(p)
			_release(p)
			continue
		if p["state"] == "hit":
			p["t"] += dt
			var k: float = clampf(float(p["t"]) * 3.0, 0.0, 1.0)
			n.rotation.x = lerpf(0.0, -PI * 0.5, k)
			n.position += (p["vel"] as Vector3) * dt
			p["vel"] = (p["vel"] as Vector3) * maxf(0.0, 1.0 - dt * 3.0)
			if p["t"] > 12.0:
				peds.erase(p)
				_release(p)
			continue
		var step: float = dt
		if d > NEAR_D:
			if not mid_tick:
				continue
			step = mid_dt          # simplified tier: 4 Hz decisions + movement
		if foot and d < 1.1 and p["state"] == "walk":
			_pause(p, 1.2)         # someone is standing right in front of me: stop and let them pass
		_step(p, step)
		if car and car.abs_speed > 3.0 and d < 12.0:
			var dd: Vector3 = n.global_position - car.global_position
			dd.y = 0.0
			if dd.length() < 1.9 + float(car.spec["W"]) * 0.4 and absf(n.global_position.y - car.global_position.y) < 2.0:
				_hit(p, car)

func _step(p: Dictionary, dt: float) -> void:
	if p["state"] == "idle":
		p["t"] = float(p["t"]) - dt
		_set_frame(p, int(idle_frame[int(p["char"])]))
		if float(p["t"]) <= 0.0:
			p["state"] = "walk"
		return
	if p["kind"] == "edge":
		_walk_edge(p, dt)
	else:
		_walk_zone(p, dt)
	p["ph"] = fposmod(float(p["ph"]) + dt * float(p["speed"]) / NATURAL_SPEED / CYCLE_S, 1.0)
	_set_frame(p, int(float(p["ph"]) * FRAMES) % FRAMES)
	# random pauses: window shopping, phone, waiting...
	p["next_pause"] = float(p["next_pause"]) - dt
	if float(p["next_pause"]) <= 0.0:
		_pause(p, randf_range(2.0, 6.0))

func _pause(p: Dictionary, secs: float) -> void:
	p["state"] = "idle"
	p["t"] = secs
	p["next_pause"] = randf_range(8.0, 25.0)

func _base_ped(vis: Dictionary, kind: String) -> Dictionary:
	return {"node": vis["root"], "mesh": vis["mesh"], "char": vis["char"], "kind": kind, "state": "walk", "t": 0.0, "ph": randf(), "frame": -1,
		"speed": randf_range(1.0, 1.7), "vel": Vector3.ZERO, "next_pause": randf_range(5.0, 20.0)}

# ---------------------------------------------------------------------------------------------------- edge walkers (sidewalks)
func _spawn_edge(pp: Vector3) -> void:
	var pick: Array = world.traffic._pick_edge_near(pp, 20.0, 90.0)
	if pick.is_empty():
		return
	var e: Dictionary = world.gen.edges[pick[0]]
	if not bool(WorldGen.KINDS[e["kind"]].get("side", false)):
		return
	var vis: Dictionary = _make_visual()
	var cum: PackedFloat32Array = e["cum"]
	var side: float = 1.0 if randf() < 0.5 else -1.0
	var p: Dictionary = _base_ped(vis, "edge")
	p["edge"] = pick[0]
	p["s"] = cum[pick[1]]
	p["dir"] = 1 if randf() < 0.5 else -1
	p["off"] = side * (float(e["width"]) * 0.5 + 1.6)
	peds.append(p)
	_place_edge(p)

func _place_edge(p: Dictionary) -> void:
	var e: Dictionary = world.gen.edges[p["edge"]]
	var smp: Array = world.traffic._edge_sample(e, float(p["s"]))
	var pos: Vector3 = smp[0]
	var tan: Vector3 = smp[1]
	var right := Vector3(-tan.z, 0, tan.x)
	var n: Node3D = p["node"]
	n.global_position = pos + right * float(p["off"])
	n.rotation.y = atan2(-tan.x * float(p["dir"]), -tan.z * float(p["dir"]))

func _walk_edge(p: Dictionary, dt: float) -> void:
	var e: Dictionary = world.gen.edges[p["edge"]]
	p["s"] = float(p["s"]) + float(p["dir"]) * float(p["speed"]) * dt
	if float(p["s"]) < 1.0 or float(p["s"]) > float(e["len"]) - 1.0:
		p["dir"] = -int(p["dir"])
		p["s"] = clampf(float(p["s"]), 1.0, float(e["len"]) - 1.0)
	_place_edge(p)

# ---------------------------------------------------------------------------------------------------- zone walkers (plaza, parking)
func _zone_count(zi: int) -> int:
	var c: int = 0
	for p in peds:
		if p["kind"] == "zone" and int(p["zone"]) == zi:
			c += 1
	return c

func _spawn_zone(pp: Vector3) -> void:
	var total: int = 0
	for p in peds:
		if p["kind"] == "zone":
			total += 1
	if total >= _zone_max():
		return
	for zi in range(WorldExpansion.WALK_ZONES.size()):
		var z: Array = WorldExpansion.WALK_ZONES[zi]
		var r: Rect2 = z[0]
		if r.get_center().distance_to(Vector2(pp.x, pp.z)) > 150.0 or _zone_count(zi) >= int(z[1]):
			continue
		var vis: Dictionary = _make_visual()
		var p: Dictionary = _base_ped(vis, "zone")
		p["zone"] = zi
		var start := Vector2(randf_range(r.position.x, r.end.x), randf_range(r.position.y, r.end.y))
		p["target"] = start
		var n: Node3D = p["node"]
		n.global_position = Vector3(start.x, world.gen.ground_h(start.x, start.y), start.y)
		peds.append(p)
		_pick_target(p)
		return

func _pick_target(p: Dictionary) -> void:
	var r: Rect2 = WorldExpansion.WALK_ZONES[int(p["zone"])][0]
	var n: Node3D = p["node"]
	var cur := Vector2(n.global_position.x, n.global_position.z)
	var t := cur
	for _i in range(6):   # prefer a destination a good walk away (long axis of the zone)
		t = Vector2(randf_range(r.position.x, r.end.x), randf_range(r.position.y, r.end.y))
		if t.distance_to(cur) > minf(r.size.x, r.size.y) * 1.5:
			break
	p["target"] = t

func _walk_zone(p: Dictionary, dt: float) -> void:
	var n: Node3D = p["node"]
	var cur := Vector2(n.global_position.x, n.global_position.z)
	var t: Vector2 = p["target"]
	var to: Vector2 = t - cur
	if to.length() < 0.6:
		_pick_target(p)
		_pause(p, randf_range(2.0, 7.0))      # arrived: stand for a while, then choose a new destination
		return
	var dir: Vector2 = to.normalized()
	var yaw: float = atan2(-dir.x, -dir.y)
	n.rotation.y = lerp_angle(n.rotation.y, yaw, clampf(dt * 5.0, 0.0, 1.0))   # smooth turns, no snapping
	var np: Vector2 = cur + dir * float(p["speed"]) * dt
	n.global_position = Vector3(np.x, world.gen.ground_h(np.x, np.y), np.y)

# ---------------------------------------------------------------------------------------------------- frame-rate monitor
## mobile safeguard: if the frame rate stays low the limits shrink, when it recovers they grow back
func _monitor(dt: float) -> void:
	var fps: float = Engine.get_frames_per_second()
	if fps < 22.0:
		fps_lo_t += dt
		fps_hi_t = 0.0
		if fps_lo_t > 3.0 and limit_scale > 0.4:
			limit_scale = maxf(0.4, limit_scale - 0.2)
			fps_lo_t = 0.0
	elif fps > 45.0:
		fps_hi_t += dt
		fps_lo_t = 0.0
		if fps_hi_t > 8.0 and limit_scale < 1.0:
			limit_scale = minf(1.0, limit_scale + 0.2)
			fps_hi_t = 0.0

func _hit(p: Dictionary, car: Vehicle) -> void:
	p["state"] = "hit"
	p["t"] = 0.0
	p["vel"] = car.linear_velocity * 0.6
	world.police.report_crime(0.7, "Hit a pedestrian")
	Game.notify.emit("Watch the pedestrians!", "warn")
	world.audio.play_crash(0.2)
