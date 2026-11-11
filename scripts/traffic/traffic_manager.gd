class_name TrafficManager
extends Node3D
## AI traffic that drives along the road graph: lanes, junction choices, safe
## following distance, lane changes, traffic lights and crash reactions.

signal car_wrecked(car: Node3D, by: Node3D)

const CYCLE := 26.0

var w: WorldGen
var cars: Array = []
var player: Node3D
var player_vehicle: Vehicle
var others: Array = []             # extra vehicles to avoid (police, rivals)
var light_nodes: Dictionary = {}   # node id -> phase offset
var spawn_timer: float = 0.0
var clock: float = 0.0
var enabled: bool = true
var density: float = 1.0
var base_cars: int = 16
var light_state_cache: Dictionary = {}
var _last_phase: int = -1
var lit_cars: int = 0
const VIDS := ["pico_h1", "pico_h1", "strada_s2", "strada_s2", "strada_s2", "titan_x", "titan_x", "hauler_r", "hauler_r", "brawler_69", "vela_gt", "dune_runner", "kestrel_r"]

func setup(world: WorldGen) -> void:
	w = world
	for i in w.nodes.size():
		var p: Vector3 = w.nodes[i]
		if absf(p.x) <= 500.5 and absf(p.z) <= 500.5 and (w.node_adj[i] as Array).size() >= 3:
			light_nodes[i] = float((int(p.x) * 7 + int(p.z) * 13) % 26)
	_build_light_visuals()
	Game.settings_changed.connect(_on_settings)
	_on_settings()

func _on_settings() -> void:
	density = float(Game.settings["traffic_density"])

func max_cars() -> int:
	return int(round(float(base_cars) * density))

# ---------------------------------------------------------------- lights
func light_phase(node: int) -> float:
	return fposmod(clock + float(light_nodes.get(node, 0.0)), CYCLE)

## 0 green, 1 yellow, 2 red  (axis 0 = north/south travel, 1 = east/west)
func light_state(node: int, axis: int) -> int:
	if not light_nodes.has(node):
		return 0
	var t: float = light_phase(node)
	if axis == 0:
		if t < 10.0: return 0
		if t < 12.0: return 1
		return 2
	if t >= 13.0 and t < 23.0: return 0
	if t >= 23.0 and t < 25.0: return 1
	return 2

const SIGNAL_SCALE := 0.9
const LENS_DARK := Color(0.07, 0.07, 0.07)
var lens_mms: Array = []           # [red, amber, green] MultiMeshInstance3D (one disc pair per pole, colour = lit / dark)
var lens_map: Array = []           # per pole: [node id, axis]

## Traffic_signals.glb (prepared by tools/prepare_world.gd): mast pole + arm + horizontal head + vertical head + street lamp.
## Every corner pole serves ONE axis; its heads face the approaching traffic and its arm reaches over the carriageway.
## (corner cx,cz) -> yaw: (+,+) 0 and (-,-) PI serve north/south traffic (axis 0); (+,-) PI/2 and (-,+) -PI/2 serve axis 1.
func _build_light_visuals() -> void:
	var body_mesh: Mesh = load("res://assets/world/signal_body.res")
	var n_poles: int = light_nodes.size() * 4
	var bm := MultiMesh.new()
	bm.transform_format = MultiMesh.TRANSFORM_3D
	bm.mesh = body_mesh
	bm.instance_count = n_poles
	var lens_multi: Array = []
	for k in ["r", "y", "g"]:
		var m := MultiMesh.new()
		m.transform_format = MultiMesh.TRANSFORM_3D
		m.use_colors = true
		m.mesh = load("res://assets/world/signal_lens_%s.res" % k)
		m.instance_count = n_poles
		lens_multi.append(m)
	var pole_body := StaticBody3D.new()   # solid pole bases (layer 1: cars + pedestrians collide)
	pole_body.collision_layer = 1
	pole_body.add_to_group("structure")
	add_child(pole_body)
	var pi: int = 0
	lens_map.clear()
	var hw: float = 9.5
	for nid in light_nodes:
		var p: Vector3 = w.nodes[nid]
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				var yaw: float = 0.0
				var axis: int = 0
				if cx > 0.0 and cz > 0.0: yaw = 0.0
				elif cx < 0.0 and cz < 0.0: yaw = PI
				elif cx > 0.0: yaw = PI * 0.5; axis = 1
				else: yaw = -PI * 0.5; axis = 1
				var pos := Vector3(p.x + cx * hw, p.y + 0.04, p.z + cz * hw)
				var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * SIGNAL_SCALE), pos)
				bm.set_instance_transform(pi, xf)
				for m in lens_multi:
					(m as MultiMesh).set_instance_transform(pi, xf)
				lens_map.append([nid, axis])
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(0.45, 8.5, 0.45)
				cs.shape = bs
				cs.position = pos + Vector3(0, 4.25, 0)
				pole_body.add_child(cs)
				pi += 1
	var bmi := MultiMeshInstance3D.new()
	bmi.multimesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	bmat.roughness = 0.6
	bmi.material_override = bmat
	bmi.visibility_range_end = 300.0
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bmi)
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.vertex_color_use_as_albedo = true
	lens_mms.clear()
	for m in lens_multi:
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = m
		mi.material_override = lmat
		mi.visibility_range_end = 300.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		lens_mms.append(mi)
	_update_light_colors(true)

func _update_light_colors(force: bool = false) -> void:
	var ph: int = int(clock * 2.0)
	if ph == _last_phase and not force:
		return
	_last_phase = ph
	var lit: Array = [Color(1.0, 0.08, 0.05), Color(1.0, 0.75, 0.05), Color(0.1, 1.0, 0.25)]   # red, amber, green
	for i in range(lens_map.size()):
		var st: int = light_state(lens_map[i][0], lens_map[i][1])   # 0 green, 1 amber, 2 red
		(lens_mms[0].multimesh as MultiMesh).set_instance_color(i, lit[0] if st == 2 else LENS_DARK)
		(lens_mms[1].multimesh as MultiMesh).set_instance_color(i, lit[1] if st == 1 else LENS_DARK)
		(lens_mms[2].multimesh as MultiMesh).set_instance_color(i, lit[2] if st == 0 else LENS_DARK)

# ---------------------------------------------------------------- cars
func _edge_sample(e: Dictionary, s: float) -> Array:
	var cum: PackedFloat32Array = e["cum"]
	var pts: PackedVector3Array = e["pts"]
	s = clampf(s, 0.0, float(e["len"]))
	var lo: int = 0
	var hi: int = cum.size() - 1
	while hi - lo > 1:
		var mid: int = (lo + hi) / 2
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg: float = maxf(0.001, cum[hi] - cum[lo])
	var t: float = (s - cum[lo]) / seg
	var pos: Vector3 = pts[lo].lerp(pts[hi], t)
	var tan: Vector3 = pts[hi] - pts[lo]
	return [pos, Vector3(tan.x, 0, tan.z).normalized(), lo]

func _pick_edge_near(center: Vector3, rmin: float, rmax: float) -> Array:
	var tries: int = 14
	while tries > 0:
		tries -= 1
		var ang: float = randf() * TAU
		var r: float = randf_range(rmin, rmax)
		var p := Vector3(center.x + cos(ang) * r, 0, center.z + sin(ang) * r)
		var near: Dictionary = w.nearest_road(p, 60.0)
		if near.is_empty():
			continue
		var e: Dictionary = w.edges[near["edge"]]
		var tw: float = float(WorldGen.KINDS[e["kind"]]["tw"])
		if tw <= 0.0 or randf() > tw * 0.7:
			continue
		var br: PackedByteArray = e["bridge"]
		return [near["edge"], near["idx"]]
	return []

func _spawn(center: Vector3) -> void:
	var pick: Array = _pick_edge_near(center, 110.0, 300.0)
	if pick.is_empty():
		return
	var ei: int = pick[0]
	var e: Dictionary = w.edges[ei]
	var pts: PackedVector3Array = e["pts"]
	var cum: PackedFloat32Array = e["cum"]
	var s: float = cum[pick[1]]
	var dir: int = 1 if randf() < 0.5 else -1
	var lane: int = randi() % int(e["lanes"])
	# don't spawn on top of another car or too close to the player
	var smp: Array = _edge_sample(e, s)
	var gp: Vector3 = smp[0]
	if gp.distance_to(center) < 100.0:
		return
	for c in cars:
		if (c as Node3D).global_position.distance_to(gp) < 22.0:
			return
	var car := TrafficCar.new()
	var vid: String = VIDS[randi() % VIDS.size()]
	var custom: Dictionary = Data.default_custom(vid)
	custom["paint"] = randi() % Data.PAINTS.size()
	custom["plate"] = "%s-%03d" % [["KZN", "GP", "WC", "DB"][randi() % 4], randi() % 1000]
	car.setup(vid, custom)
	car.edge = ei
	car.dir = dir
	car.s = s
	car.lane = lane
	car.lane_off = _lane_offset(e, lane)
	car.pref_speed = float(e["limit"]) * randf_range(0.8, 1.02)
	car.speed = car.pref_speed * 0.6
	add_child(car)
	car.global_transform = _car_transform(car, e)
	cars.append(car)

func _lane_offset(e: Dictionary, lane: int) -> float:
	var w2: float = float(e["width"])
	if int(e["lanes"]) <= 1:
		return w2 * 0.25
	return w2 * (0.125 + 0.25 * float(lane))

func _car_transform(car: TrafficCar, e: Dictionary) -> Transform3D:
	var smp: Array = _edge_sample(e, car.s)
	var pos: Vector3 = smp[0]
	var tan: Vector3 = smp[1] * float(car.dir)
	var right := Vector3(-tan.z, 0, tan.x)
	pos += right * car.lane_off
	var pts: PackedVector3Array = e["pts"]
	var look: Array = _edge_sample(e, car.s + 3.0 * float(car.dir))
	var tgt: Vector3 = (look[0] as Vector3) + right * car.lane_off
	var fwd: Vector3 = (tgt - pos)
	if fwd.length() < 0.1:
		fwd = tan
	fwd = fwd.normalized()
	var up := Vector3.UP
	var basis := Basis.looking_at(fwd, up)
	pos.y += 0.16 + 0.0
	return Transform3D(basis, pos)

func _node_end(car: TrafficCar) -> int:
	var e: Dictionary = w.edges[car.edge]
	return int(e["b"]) if car.dir > 0 else int(e["a"])

func _choose_next(car: TrafficCar, node: int) -> void:
	var adj: Array = w.node_adj[node]
	var opts: Array = []
	var weights: Array = []
	var cur_e: Dictionary = w.edges[car.edge]
	var cur_dir := Vector3.ZERO
	var smp: Array = _edge_sample(cur_e, float(cur_e["len"]) if car.dir > 0 else 0.0)
	cur_dir = (smp[1] as Vector3) * float(car.dir)
	for ei in adj:
		if ei == car.edge:
			continue
		var e: Dictionary = w.edges[ei]
		var tw: float = float(WorldGen.KINDS[e["kind"]]["tw"])
		if tw <= 0.0:
			continue
		var d2: int = 1 if int(e["a"]) == node else -1
		var s0: float = 0.0 if d2 > 0 else float(e["len"])
		var sm2: Array = _edge_sample(e, s0 + 2.0 * float(d2))
		var nd: Vector3 = (sm2[1] as Vector3) * float(d2)
		var straight: float = cur_dir.dot(nd)
		opts.append([ei, d2])
		weights.append(tw * (1.6 if straight > 0.8 else 1.0) * (0.0 if straight < -0.9 else 1.0))
	if opts.is_empty():
		car.dir = -car.dir      # dead end: turn around
		return
	var total: float = 0.0
	for x in weights:
		total += x
	if total <= 0.0:
		car.dir = -car.dir
		return
	var r: float = randf() * total
	var acc: float = 0.0
	for i in range(opts.size()):
		acc += weights[i]
		if r <= acc:
			var o: Array = opts[i]
			car.edge = o[0]
			car.dir = o[1]
			car.s = 0.0 if car.dir > 0 else float(w.edges[car.edge]["len"])
			var ne: Dictionary = w.edges[car.edge]
			car.lane = mini(car.lane, int(ne["lanes"]) - 1)
			car.lane_off = _lane_offset(ne, car.lane)
			car.pref_speed = float(ne["limit"]) * randf_range(0.8, 1.02)
			return

func _physics_process(dt: float) -> void:
	clock += dt
	_update_light_colors()
	if not enabled or player == null:
		return
	var pp: Vector3 = player.global_position
	spawn_timer -= dt
	if spawn_timer <= 0.0 and cars.size() < max_cars():
		spawn_timer = 0.35
		_spawn(pp)
	# gather potential leaders
	var obstacles: Array = []
	for c in cars:
		obstacles.append(c)
	if player_vehicle:
		obstacles.append(player_vehicle)
	for o in others:
		if is_instance_valid(o):
			obstacles.append(o)
	var to_remove: Array = []
	for c in cars:
		var car: TrafficCar = c
		if car.state == "wreck":
			car.wreck_time += dt
			if car.wreck_time > 22.0 or car.global_position.distance_to(pp) > 450.0:
				to_remove.append(car)
			continue
		if car.global_position.distance_to(pp) > 480.0 or cars.size() > max_cars() + 3:
			if car.global_position.distance_to(pp) > 320.0:
				to_remove.append(car)
				continue
		_drive(car, dt, obstacles)
	for c in to_remove:
		cars.erase(c)
		c.queue_free()

func _drive(car: TrafficCar, dt: float, obstacles: Array) -> void:
	var e: Dictionary = w.edges[car.edge]
	var length: float = float(e["len"])
	var xf: Transform3D = car.global_transform
	var fwd: Vector3 = -xf.basis.z
	var right: Vector3 = xf.basis.x
	var vt: float = car.pref_speed
	# curvature ahead
	var a1: Array = _edge_sample(e, car.s + 8.0 * float(car.dir))
	var a2: Array = _edge_sample(e, car.s + 28.0 * float(car.dir))
	var h1: Vector3 = (a1[1] as Vector3) * float(car.dir)
	var h2: Vector3 = (a2[1] as Vector3) * float(car.dir)
	var turn: float = acos(clampf(h1.dot(h2), -1.0, 1.0))
	if turn > 0.12:
		vt = minf(vt, maxf(5.0, 20.0 / (turn * 3.0)))
	# traffic light / junction
	var node: int = _node_end(car)
	var dist_end: float = length - car.s if car.dir > 0 else car.s
	if light_nodes.has(node) and dist_end < 55.0:
		var axis: int = 0 if absf(fwd.z) > absf(fwd.x) else 1
		var st: int = light_state(node, axis)
		if st == 2 or (st == 1 and dist_end > 9.0 + car.speed * 0.5):
			var stop_d: float = dist_end - 10.5
			if stop_d > -1.0:
				var allowed: float = sqrt(maxf(0.0, 2.0 * 3.8 * maxf(stop_d, 0.0)))
				vt = minf(vt, allowed)
	elif dist_end < 22.0 and (w.node_adj[node] as Array).size() >= 3:
		vt = minf(vt, 8.0)
	# leader following + lane change
	var block_speed: float = 99.0
	var block_gap: float = 99.0
	var other_lane_free: bool = true
	var my_pos: Vector3 = car.global_position
	for o in obstacles:
		if o == car:
			continue
		var op: Vector3 = (o as Node3D).global_position
		var rel: Vector3 = op - my_pos
		if absf(rel.x) > 50.0 or absf(rel.z) > 50.0:
			continue
		var ahead: float = rel.dot(fwd)
		var lat: float = rel.dot(right)
		var ospeed: float = 0.0
		if o is TrafficCar:
			ospeed = (o as TrafficCar).speed if (o as TrafficCar).state == "drive" else 0.0
		elif o is Vehicle:
			ospeed = maxf((o as Vehicle).speed, 0.0)
		if ahead > 1.0 and ahead < 38.0 and absf(lat) < 2.3:
			var gap: float = ahead - 4.4
			if gap < block_gap:
				block_gap = gap
				block_speed = ospeed
		# is the neighbouring lane occupied alongside
		if absf(ahead) < 12.0 and absf(lat - (car.lane_off - _lane_offset(e, 1 - car.lane) if int(e["lanes"]) > 1 else 99.0)) < 2.2 and int(e["lanes"]) > 1:
			other_lane_free = false
	if block_gap < 90.0:
		var safe: float = 5.0 + car.speed * 0.9
		if block_gap < safe:
			vt = minf(vt, maxf(0.0, block_speed - (safe - block_gap) * 0.45))
		else:
			vt = minf(vt, block_speed + (block_gap - safe) * 0.35)
		# overtake on multi-lane roads
		if int(e["lanes"]) > 1 and block_speed < car.pref_speed - 2.5 and other_lane_free and car.lane_timer <= 0.0:
			car.lane = 1 - car.lane
			car.lane_timer = 8.0
	car.lane_timer = maxf(0.0, car.lane_timer - dt)
	var target_off: float = _lane_offset(e, car.lane)
	car.lane_off = move_toward(car.lane_off, target_off, dt * 1.6)
	# speed update
	var acc: float = 2.8 if vt > car.speed else -7.5
	car.speed = maxf(0.0, car.speed + clampf((vt - car.speed) * 2.0, -7.5, 2.8) * dt) if absf(vt - car.speed) > 0.05 else vt
	car.s += car.speed * dt * float(car.dir)
	if car.s > length and car.dir > 0:
		var over: float = car.s - length
		_choose_next(car, int(e["b"]))
		if car.dir > 0 and car.edge == car.edge:
			car.s = over if car.s == 0.0 else car.s
		e = w.edges[car.edge]
		car.s = clampf(over, 0.0, float(e["len"])) if car.dir > 0 else float(e["len"]) - over
	elif car.s < 0.0 and car.dir < 0:
		var over2: float = -car.s
		_choose_next(car, int(e["a"]))
		e = w.edges[car.edge]
		car.s = clampf(over2, 0.0, float(e["len"])) if car.dir > 0 else float(e["len"]) - over2
	var target_xf: Transform3D = _car_transform(car, e)
	var cur: Transform3D = car.global_transform
	var nb: Basis = cur.basis.slerp(target_xf.basis, clampf(dt * 8.0, 0.0, 1.0))
	car.global_transform = Transform3D(nb, target_xf.origin)
	car.spin_wheels(car.speed * dt)
	car.set_brake_light(vt < car.speed - 0.5)
	car.set_night(Game.time_of_day < 6.0 or Game.time_of_day > 19.0)

func on_player_hit(body: Node, speed: float) -> void:
	if body is TrafficCar:
		var tc: TrafficCar = body
		if tc.state == "drive":
			tc.wreck(player_vehicle.linear_velocity if player_vehicle else Vector3.ZERO)
			car_wrecked.emit(tc, player_vehicle)

func clear_all() -> void:
	for c in cars:
		(c as Node3D).queue_free()
	cars.clear()
