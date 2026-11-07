class_name PoliceManager
extends Node
## Wanted system: heat -> 1..5 stars, pursuit units, roadblocks (4+),
## helicopter (5), busted / escape resolution.

signal level_changed(level: int)
signal busted
signal escaped

const MAX_UNITS := [0, 1, 2, 3, 4, 5]

var world: World
var heat: float = 0.0
var level: int = 0
var units: Array = []            # {car, ai, route_t, stuck}
var roadblocks: Array = []       # {nodes:[Node], age}
var heli: Node3D = null
var heli_rotor: Node3D = null
var heli_spot: SpotLight3D = null
var spawn_t: float = 0.0
var busted_t: float = 0.0
var lost_t: float = 0.0
var block_t: float = 20.0
var light_cd: float = 0.0
var flash_t: float = 0.0
var crime_cd: float = 0.0
var heli_ang: float = 0.0
var searching: bool = false
var nearest_cop: float = 9999.0
var immune: float = 0.0

func reset() -> void:
	for u in units:
		if is_instance_valid(u["car"]):
			(u["car"] as Node).queue_free()
	units.clear()
	for rb in roadblocks:
		_free_block(rb)
	roadblocks.clear()
	if heli:
		heli.queue_free()
		heli = null
	heat = 0.0
	_set_level(0)
	busted_t = 0.0
	lost_t = 0.0
	if world and world.traffic:
		world.traffic.others.clear()

func report_crime(amount: float, reason: String) -> void:
	if immune > 0.0:
		return
	if world.missions and world.missions.ignore_police():
		return
	var before: int = level
	heat = minf(heat + amount, 5.0)
	if heat > 0.5 and before == 0:
		Game.notify.emit("Wanted: " + reason, "warn")
	_refresh_level()

func _refresh_level() -> void:
	var l: int = 0
	if heat >= 0.5:
		l = clampi(int(ceil(heat)), 1, 5)
	_set_level(l)

func _set_level(l: int) -> void:
	if l == level:
		return
	level = l
	Game.set_wanted(l)
	level_changed.emit(l)

## Force a specific wanted level (police challenge missions)
func set_heat_level(l: int) -> void:
	heat = float(l) - 0.3
	_refresh_level()

func _max_units() -> int:
	var m: int = MAX_UNITS[level]
	if String(Game.settings.get("quality", "Medium")) == "Low":
		m = mini(m, 3)
	return m

func _physics_process(dt: float) -> void:
	if not world.running:
		return
	immune = maxf(0.0, immune - dt)
	crime_cd -= dt
	var pp: Vector3 = world.player_pos()
	_check_red_light(dt, pp)
	if level == 0:
		heat = maxf(0.0, heat - 0.03 * dt)
		if heat < 0.5 and units.size() == 0:
			return
	_update_units(dt, pp)
	flash_t += dt
	if level > 0:
		_spawn_logic(dt, pp)
		_blocks_logic(dt, pp)
		_heli_logic(dt, pp)
		_resolve(dt, pp)
	else:
		# cool-down: let units drive off and disappear
		for u in units.duplicate():
			var c: Vehicle = u["car"]
			if not is_instance_valid(c) or c.global_position.distance_to(pp) > 130.0:
				_remove_unit(u)
		if heli:
			heli.queue_free()
			heli = null

func _check_red_light(dt: float, pp: Vector3) -> void:
	light_cd -= dt
	if light_cd > 0.0 or world.mode != "drive":
		return
	var car: Vehicle = world.player_car
	if car.abs_speed < 9.0:
		return
	if absf(pp.x) > 520.0 or absf(pp.z) > 520.0:
		return
	var tm: TrafficManager = world.traffic
	for n in tm.light_nodes:
		var np: Vector3 = world.gen.nodes[n]
		var d: float = Vector2(np.x - pp.x, np.z - pp.z).length()
		if d < 9.0:
			var fwd: Vector3 = -car.global_transform.basis.z
			var axis: int = 0 if absf(fwd.z) > absf(fwd.x) else 1
			if tm.light_state(n, axis) == 2:
				light_cd = 8.0
				report_crime(0.22, "Ran a red light")
				return

# ---------------------------------------------------------------- units
func _make_unit(pos: Vector3, yaw: float, skill: float) -> Dictionary:
	var v := Vehicle.new()
	v.is_police = true
	v.add_to_group("police")
	world.add_child(v)
	var cust: Dictionary = Data.default_custom("police_cruiser")
	cust["paint"] = 2
	cust["paint2"] = 1
	cust["two_tone"] = true
	cust["plate"] = "SAPS-%02d" % (randi() % 90 + 10)
	var up: Dictionary = Data.default_upgrades()
	up["engine"] = 1
	up["tyres"] = 1
	v.configure("police_cruiser", cust, up, 0.0, 1.0)
	v.place_on_ground(pos, yaw)
	v.set_headlights(true)
	_add_light_bar(v)
	var ai := DriverAI.new(v, skill)
	ai.avoid_space = null
	v.body_entered.connect(_on_unit_hit.bind(v))
	world.traffic.others.append(v)
	world.audio.attach_siren(v)
	var u: Dictionary = {"car": v, "ai": ai, "route_t": randf() * 1.5, "stuck": 0.0, "bar": v.get_node("LightBar")}
	units.append(u)
	return u

func _on_unit_hit(body: Node, cop: Vehicle) -> void:
	if body == world.player_car and level > 0:
		heat = minf(heat + 0.02, 5.0)
	elif body == world.player_car and level == 0 and cop.abs_speed > 6.0:
		report_crime(0.4, "Hit a police car")

func _add_light_bar(v: Vehicle) -> void:
	var bar := Node3D.new()
	bar.name = "LightBar"
	var top: float = float(v.spec["roof"]) + v.MODEL_Y + 0.05
	bar.position = Vector3(0, top, -0.1)
	for i in 2:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.5, 0.1, 0.22)
		mi.mesh = b
		mi.position = Vector3(-0.28 if i == 0 else 0.28, 0, 0)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1, 0.05, 0.05) if i == 0 else Color(0.1, 0.25, 1.0)
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = 0.2
		mi.material_override = m
		mi.name = "L%d" % i
		bar.add_child(mi)
	var base := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(1.2, 0.05, 0.28)
	base.mesh = bb
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.03, 0.03, 0.03)
	base.material_override = bm
	base.position.y = -0.07
	bar.add_child(base)
	if String(Game.settings.get("quality", "Medium")) != "Low":
		for i in 2:
			var ol := OmniLight3D.new()
			ol.name = "O%d" % i
			ol.omni_range = 11.0
			ol.light_energy = 0.0
			ol.light_color = Color(1, 0.1, 0.1) if i == 0 else Color(0.2, 0.35, 1.0)
			ol.position = Vector3(-0.3 if i == 0 else 0.3, 0.3, 0)
			bar.add_child(ol)
	v.add_child(bar)

func _flash_bar(bar: Node3D, t: float) -> void:
	var ph: bool = int(t * 5.0) % 2 == 0
	var a: MeshInstance3D = bar.get_node("L0")
	var b: MeshInstance3D = bar.get_node("L1")
	(a.material_override as StandardMaterial3D).emission_energy_multiplier = 5.0 if ph else 0.2
	(b.material_override as StandardMaterial3D).emission_energy_multiplier = 0.2 if ph else 5.0
	if bar.has_node("O0"):
		(bar.get_node("O0") as OmniLight3D).light_energy = 3.0 if ph else 0.0
		(bar.get_node("O1") as OmniLight3D).light_energy = 0.0 if ph else 3.0

func _remove_unit(u: Dictionary) -> void:
	units.erase(u)
	var c: Vehicle = u["car"]
	if is_instance_valid(c):
		world.traffic.others.erase(c)
		c.queue_free()

func _spawn_pos(pp: Vector3, rmin: float, rmax: float) -> Dictionary:
	for i in 14:
		var pick: Array = world.traffic._pick_edge_near(pp, rmin, rmax)
		if pick.is_empty():
			continue
		var e: Dictionary = world.gen.edges[pick[0]]
		var pts: PackedVector3Array = e["pts"]
		var i0: int = pick[1]
		var a: Vector3 = pts[maxi(i0 - 1, 0)]
		var b: Vector3 = pts[mini(i0 + 1, pts.size() - 1)]
		var d: Vector3 = b - a
		var p: Vector3 = pts[i0]
		if p.distance_to(pp) < rmin * 0.8:
			continue
		var yaw: float = atan2(-d.x, -d.z)
		return {"pos": p, "yaw": yaw}
	return {}

func _spawn_logic(dt: float, pp: Vector3) -> void:
	spawn_t -= dt
	if spawn_t > 0.0 or units.size() >= _max_units():
		return
	spawn_t = 3.0 if units.size() == 0 else 5.0
	var sp: Dictionary = _spawn_pos(pp, 130.0, 260.0)
	if sp.is_empty():
		return
	var skill: float = 0.5 + 0.1 * float(level)
	_make_unit(sp["pos"], sp["yaw"], clampf(skill, 0.5, 0.95))

func _update_units(dt: float, pp: Vector3) -> void:
	nearest_cop = 9999.0
	var target_car: Vehicle = world.player_car
	for u in units.duplicate():
		var c: Vehicle = u["car"]
		if not is_instance_valid(c):
			units.erase(u)
			continue
		var ai: DriverAI = u["ai"]
		var cp: Vector3 = c.global_position
		var d: float = Vector2(cp.x - pp.x, cp.z - pp.z).length()
		nearest_cop = minf(nearest_cop, d)
		_flash_bar(u["bar"], flash_t + float(c.get_instance_id() % 7))
		if level == 0:
			ai.use_direct = false
			if ai.path.size() < 2:
				c.set_inputs(0, 0.6, 0, false)
			else:
				ai.update(dt)
			continue
		ai.speed_scale = 0.88 + 0.04 * float(level)
		u["route_t"] -= dt
		var close: bool = d < 55.0
		if close:
			ai.use_direct = true
			ai.direct_target = _intercept(pp)
		else:
			ai.use_direct = false
			if u["route_t"] <= 0.0 or ai.path.size() < 2:
				u["route_t"] = 2.5
				ai.set_path(world.nav.route(cp, pp))
		ai.update(dt)
		# flipped or far away units get recycled
		if c.global_transform.basis.y.y < 0.2 and c.abs_speed < 2.0:
			u["stuck"] += dt
			if u["stuck"] > 4.0:
				_remove_unit(u)
		elif d > 520.0:
			_remove_unit(u)

func _intercept(pp: Vector3) -> Vector3:
	if world.mode == "drive" and world.player_car:
		var v: Vector3 = world.player_car.linear_velocity
		return pp + Vector3(v.x, 0, v.z) * 0.6
	return pp

# ---------------------------------------------------------------- road blocks
func _blocks_logic(dt: float, pp: Vector3) -> void:
	for rb in roadblocks.duplicate():
		rb["age"] += dt
		var bp: Vector3 = rb["pos"]
		if rb["age"] > 70.0 or Vector2(bp.x - pp.x, bp.z - pp.z).length() > 420.0 or level < 4:
			_free_block(rb)
			roadblocks.erase(rb)
		else:
			for ln in rb["lights"]:
				_flash_bar(ln, flash_t)
	if level < 4 or world.mode != "drive":
		return
	block_t -= dt
	if block_t > 0.0 or roadblocks.size() >= 1 or world.player_car.abs_speed < 12.0:
		return
	block_t = 28.0
	var fwd: Vector3 = -world.player_car.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var target: Vector3 = pp + fwd * 260.0
	var nr: Dictionary = world.gen.nearest_road(target, 70.0)
	if nr.is_empty():
		return
	var e: Dictionary = world.gen.edges[nr["edge"]]
	if String(e["kind"]) in ["dirt", "track"]:
		return
	var pts: PackedVector3Array = e["pts"]
	var i: int = nr["idx"]
	var p: Vector3 = nr["pos"]
	if p.distance_to(pp) < 150.0:
		return
	var d: Vector3 = pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]
	d.y = 0.0
	d = d.normalized()
	if d.length() < 0.1:
		return
	_make_block(p, d, float(e["width"]))

func _make_block(p: Vector3, along: Vector3, width: float) -> void:
	var rb: Dictionary = {"pos": p, "age": 0.0, "nodes": [], "lights": []}
	var yaw: float = atan2(-along.x, -along.z)
	var across := Vector3(along.z, 0, -along.x)
	var cars_n: int = 2
	for k in cars_n:
		var off: float = (float(k) - 0.5) * width * 0.42
		var cp: Vector3 = p + across * off
		var u: Dictionary = _make_unit(cp, yaw + (PI * 0.5 if k == 0 else -PI * 0.5) + 0.0, 0.5)
		var c: Vehicle = u["car"]
		c.freeze = true
		c.linear_velocity = Vector3.ZERO
		(u["ai"] as DriverAI).enabled = false
		u["static"] = true
		rb["nodes"].append(c)
		rb["lights"].append(u["bar"])
	# barrier (spike strip look-alike): low concrete blocks
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width * 1.1, 0.9, 0.9)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.5, 0.05)
	mat.roughness = 0.8
	mi.material_override = mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	body.add_child(cs)
	world.add_child(body)
	body.global_position = p - along * 4.0 + Vector3(0, 0.45, 0)
	body.rotation.y = yaw
	rb["nodes"].append(body)
	roadblocks.append(rb)
	Game.notify.emit("Roadblock ahead!", "bad")

func _free_block(rb: Dictionary) -> void:
	for n in rb["nodes"]:
		if is_instance_valid(n):
			if n is Vehicle:
				for u in units.duplicate():
					if u["car"] == n:
						_remove_unit(u)
			else:
				(n as Node).queue_free()
	rb["nodes"].clear()

# ---------------------------------------------------------------- helicopter
func _heli_logic(dt: float, pp: Vector3) -> void:
	if level < 5:
		if heli:
			heli.queue_free()
			heli = null
		return
	if heli == null:
		heli = Node3D.new()
		var body := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 1.3
		cm.height = 5.2
		body.mesh = cm
		body.rotation.x = PI * 0.5
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.05, 0.05, 0.07)
		m.metallic = 0.5
		m.roughness = 0.35
		body.material_override = m
		heli.add_child(body)
		var tail := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.3, 0.35, 5.0)
		tail.mesh = tb
		tail.position = Vector3(0, 0.3, 4.2)
		tail.material_override = m
		heli.add_child(tail)
		heli_rotor = Node3D.new()
		heli_rotor.position = Vector3(0, 1.5, 0)
		var blade := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(11.0, 0.05, 0.35)
		blade.mesh = bb
		blade.material_override = m
		heli_rotor.add_child(blade)
		var blade2 := MeshInstance3D.new()
		blade2.mesh = bb
		blade2.rotation.y = PI * 0.5
		blade2.material_override = m
		heli_rotor.add_child(blade2)
		heli.add_child(heli_rotor)
		heli_spot = SpotLight3D.new()
		heli_spot.spot_range = 140.0
		heli_spot.spot_angle = 11.0
		heli_spot.light_energy = 6.0
		heli_spot.light_color = Color(0.9, 0.95, 1.0)
		heli_spot.shadow_enabled = false
		heli.add_child(heli_spot)
		var sp: Dictionary = _spawn_pos(pp, 200.0, 300.0)
		heli.position = pp + Vector3(220, 90, 0)
		world.add_child(heli)
		Game.notify.emit("Police helicopter is tracking you", "bad")
	heli_ang += dt * 0.45
	var tgt: Vector3 = pp + Vector3(cos(heli_ang) * 38.0, 62.0, sin(heli_ang) * 38.0)
	if world.mode == "drive":
		tgt += world.player_car.linear_velocity * 0.7
	heli.global_position = heli.global_position.lerp(tgt, clampf(dt * 0.9, 0.0, 1.0))
	var look: Vector3 = pp
	heli.look_at(Vector3(look.x, heli.global_position.y - 0.0, look.z), Vector3.UP)
	heli_spot.look_at(pp + Vector3(0, 0.5, 0), Vector3.UP)
	heli_rotor.rotate_y(dt * 30.0)

func heli_distance(pp: Vector3) -> float:
	if heli == null:
		return 9999.0
	return heli.global_position.distance_to(pp)

# ---------------------------------------------------------------- bust / escape
func _resolve(dt: float, pp: Vector3) -> void:
	var player_speed: float = world.player_car.abs_speed if world.mode == "drive" else 0.0
	var closest_static: float = 9999.0
	var boxed: int = 0
	for u in units:
		var c: Vehicle = u["car"]
		if not is_instance_valid(c):
			continue
		var d: float = c.global_position.distance_to(pp)
		if d < 11.0 and c.abs_speed < 14.0:
			boxed += 1
		closest_static = minf(closest_static, d)
	if boxed >= 1 and player_speed < 5.0 and nearest_cop < 12.0:
		busted_t += dt * (1.0 + 0.5 * float(boxed - 1))
		if busted_t > 3.2:
			_do_busted()
			return
	else:
		busted_t = maxf(0.0, busted_t - dt * 1.5)
	# escape: nobody close and heli not overhead
	var sighted: bool = nearest_cop < 140.0 or (heli != null and heli_distance(pp) < 110.0)
	if sighted:
		lost_t = 0.0
		heat = minf(heat + 0.002 * dt * float(level), 5.0)
	else:
		lost_t += dt
		if lost_t > 6.0:
			heat = maxf(0.0, heat - (0.25 + 0.1 * float(level)) * dt)
			_refresh_level()
			if level == 0:
				_escaped()

func _escaped() -> void:
	Game.notify.emit("You lost the cops!", "good")
	var bonus: int = 200 * maxi(1, int(ceil(heat)))
	Game.add_money(300, "Escaped")
	Game.add_rep(6)
	lost_t = 0.0
	busted_t = 0.0
	escaped.emit()
	if world.missions:
		world.missions.on_police_escaped()

func _do_busted() -> void:
	var fine: int = clampi(int(float(Game.money) * 0.1), 150, 4000)
	fine = mini(fine, Game.money)
	Game.stats["busted"] = int(Game.stats["busted"]) + 1
	Game.add_money(-fine, "Busted - fine")
	Game.notify.emit("BUSTED", "bad")
	busted.emit()
	heat = 0.0
	busted_t = 0.0
	_set_level(0)
	for u in units.duplicate():
		_remove_unit(u)
	for rb in roadblocks:
		_free_block(rb)
	roadblocks.clear()
	if world.missions:
		world.missions.fail_active("Busted")
	immune = 12.0
	world.send_to_garage("Released near your garage")
