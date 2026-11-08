class_name Vehicle
extends VehicleBody3D
## Drivable car. Uses Godot's raycast vehicle for suspension/tyre contact and a
## custom engine, gearbox, steering, drift, damage and fuel model on top.
## Handling differs per vehicle through Data.VEHICLES + upgrades.

signal crashed(severity: float, world_pos: Vector3)
signal shifted(up: bool)
signal destroyed

# --- tuning constants (calibrated with tests/physics_test.gd) -----------------
const ENGINE_K: float = 1.0
const BRAKE_K: float = 1.0
const FRICTION_K: float = 1.0
const MODEL_Y: float = 0.16   # static suspension sag compensation

static var surface_world: WorldGen = null
static var weather_grip: float = 1.0

var vid: String = "pico_h1"
var spec: Dictionary = {}
var stats: Dictionary = {}
var custom: Dictionary = {}
var upg: Dictionary = {}
var model: Dictionary = {}
var wheels: Array = []
var wheel_visuals: Array = []
var is_player: bool = false
var is_police: bool = false
var is_traffic: bool = false
var handling_arcade: bool = true

# inputs (-1..1 steer, 0..1 others)
var in_throttle: float = 0.0
var in_brake: float = 0.0
var in_steer: float = 0.0
var in_handbrake: bool = false
var in_nitro: bool = false

# state
var gear: int = 1
var rpm: float = 900.0
var rpm_norm: float = 0.0
var speed: float = 0.0            # forward speed m/s (signed)
var abs_speed: float = 0.0
var slip: float = 0.0             # 0 grip .. 1 full slide
var slip_angle: float = 0.0
var drifting: bool = false
var drift_time: float = 0.0
var drift_points: float = 0.0
var damage: float = 0.0
var last_impact: float = 0.0
var lamps_broken: bool = false
var fuel: float = 1.0
var nitro: float = 1.0
var has_nitro: bool = false
var braking_now: bool = false
var reversing: bool = false
var headlights_on: bool = false
var engine_on: bool = true
var wrecked: bool = false
var on_road: bool = true
var shift_timer: float = 0.0
var steer_cur: float = 0.0
var _thr_s: float = 0.0
var _brk_s: float = 0.0
var prev_vel: Vector3 = Vector3.ZERO
var crash_cd: float = 0.0
var dent_i: int = 0
var dents: Array = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
var vmax_gear: Array = []
var _spot: Array = []
var _smoke: CPUParticles3D
var _tire_smoke: Array = []
var _model_root: Node3D
var _last_gear_change: float = 0.0
var airborne_time: float = 0.0
var distance_driven: float = 0.0
var respawn_hold: float = 0.0

func configure(p_vid: String, p_custom: Dictionary, p_upg: Dictionary, p_damage: float = 0.0, p_fuel: float = 1.0) -> void:
	vid = p_vid
	spec = Data.vehicle(vid)
	custom = p_custom.duplicate(true)
	upg = Data.default_upgrades()
	upg.merge(p_upg, true)
	custom["exhaust_level"] = int(upg.get("exhaust", 0))
	stats = Data.final_stats(vid, upg)
	damage = p_damage
	fuel = p_fuel
	has_nitro = int(upg.get("turbo", 0)) >= 2
	handling_arcade = String(Game.settings.get("handling", "arcade")) == "arcade"
	mass = float(stats["mass"])
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.32 + (0.06 if spec["cat"] in ["SUV", "Off-Road", "Pickup Truck"] else 0.0), 0.0)
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.02
	angular_damp = 1.4 if handling_arcade else 0.9
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 6
	can_sleep = false
	collision_layer = 2
	collision_mask = 1 | 2
	_build_visual()
	_build_collision()
	_build_wheels()
	_build_lights_and_fx()
	# gear tables
	var gears: Array = spec["gears"]
	vmax_gear = []
	for g in range(gears.size()):
		vmax_gear.append(float(stats["top"]) * 1.05 * float(gears[gears.size() - 1]) / float(gears[g]))
	apply_damage_visuals()
	set_headlights(false)

func _build_visual() -> void:
	if _model_root:
		_model_root.queue_free()
	model = CarBuilder.build(vid, custom)
	_model_root = model["root"]
	_model_root.position = Vector3(0, MODEL_Y, 0)
	add_child(_model_root)

func _build_collision() -> void:
	for c in get_children():
		if c is CollisionShape3D:
			c.queue_free()
	var L: float = float(spec["L"])
	var W: float = float(spec["W"])
	var belly: float = float(spec["belly"])
	var belt: float = float(spec["belt"])
	var roof: float = float(spec["roof"])
	var lower := CollisionShape3D.new()
	var lb := BoxShape3D.new()
	lb.size = Vector3(W * 0.96, belt - belly - 0.02, L * 0.97)
	lower.shape = lb
	lower.position = Vector3(0, MODEL_Y + belly + (belt - belly - 0.02) * 0.5 + 0.06, 0)
	add_child(lower)
	var upper := CollisionShape3D.new()
	var ub := BoxShape3D.new()
	var c0: float = float(spec["cab0"])
	var c1: float = float(spec["cab1"])
	ub.size = Vector3(W * 0.78, roof - belt, (c1 - c0) * L * 0.9)
	upper.shape = ub
	upper.position = Vector3(0, MODEL_Y + belt + (roof - belt) * 0.5, -L * 0.5 + (c0 + c1) * 0.5 * L)
	add_child(upper)

func _build_wheels() -> void:
	for w in wheels:
		if is_instance_valid(w):
			w.queue_free()
	wheels.clear()
	wheel_visuals.clear()
	var track: float = float(spec["track"])
	var wb: float = float(spec["wb"])
	var wr: float = float(spec["wr"])
	var rest: float = float(spec.get("susp", 0.16))
	var travel: float = 0.22 if not bool(spec.get("offroad", false)) else 0.4
	var drive: String = spec["drive"]
	for fz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			var w := VehicleWheel3D.new()
			var front: bool = fz < 0.0
			w.position = Vector3(sx * track * 0.5, wr + rest + MODEL_Y - 0.09, fz * wb * 0.5)
			w.wheel_radius = wr
			w.wheel_rest_length = rest
			w.suspension_travel = travel
			w.suspension_stiffness = float(stats["stiff"])
			w.suspension_max_force = mass * 14.0
			w.damping_compression = 0.9
			w.damping_relaxation = 1.1
			w.wheel_roll_influence = clampf(1.0 - float(stats["roll"]) * 1.6, 0.3, 1.0)
			w.wheel_friction_slip = float(stats["grip"]) * 2.4 * FRICTION_K
			w.use_as_steering = front
			w.use_as_traction = (drive == "AWD") or (drive == "FWD" and front) or (drive == "RWD" and not front)
			var vis: MeshInstance3D = CarBuilder.build_wheel(vid, custom)
			w.add_child(vis)
			add_child(w)
			wheels.append(w)
			wheel_visuals.append(vis)

func _build_lights_and_fx() -> void:
	_spot.clear()
	var hp: Array = model["head_pos"]
	for p in hp:
		var sp := SpotLight3D.new()
		sp.position = (p as Vector3) + Vector3(0, 0.07, -0.05)
		sp.rotation_degrees = Vector3(-4, 0, 0)
		sp.spot_range = 55.0
		sp.spot_angle = 34.0
		sp.spot_attenuation = 0.8
		sp.light_energy = 2.4
		sp.light_color = model["head_color"]
		sp.shadow_enabled = false
		sp.visible = false
		add_child(sp)
		_spot.append(sp)
	_smoke = CPUParticles3D.new()
	_smoke.position = Vector3(0, float(spec["hood"]) + 0.05, -float(spec["L"]) * 0.3)
	_smoke.amount = 24
	_smoke.lifetime = 1.6
	_smoke.direction = Vector3(0, 1, 0)
	_smoke.spread = 22.0
	_smoke.initial_velocity_min = 1.0
	_smoke.initial_velocity_max = 2.2
	_smoke.gravity = Vector3(0, 0.6, 0)
	_smoke.scale_amount_min = 0.5
	_smoke.scale_amount_max = 1.4
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	sm.radial_segments = 6
	sm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.2, 0.2, 0.2, 0.55)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = smat
	_smoke.mesh = sm
	_smoke.emitting = false
	add_child(_smoke)
	_tire_smoke.clear()
	for sx in [-1.0, 1.0]:
		var ts := CPUParticles3D.new()
		ts.position = Vector3(sx * float(spec["track"]) * 0.5, 0.15, float(spec["wb"]) * 0.5)
		ts.amount = 20
		ts.lifetime = 1.2
		ts.direction = Vector3(0, 1, 0)
		ts.spread = 35.0
		ts.initial_velocity_min = 0.6
		ts.initial_velocity_max = 1.6
		ts.gravity = Vector3(0, 0.3, 0)
		ts.scale_amount_min = 0.6
		ts.scale_amount_max = 1.6
		var tm := SphereMesh.new()
		tm.radius = 0.3
		tm.height = 0.6
		tm.radial_segments = 6
		tm.rings = 3
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color(0.85, 0.85, 0.88, 0.4)
		tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.material = tmat
		ts.mesh = tm
		ts.emitting = false
		add_child(ts)
		_tire_smoke.append(ts)

func set_headlights(on: bool) -> void:
	headlights_on = on
	for s in _spot:
		(s as SpotLight3D).visible = on and not (damage > 0.7) and not lamps_broken
	var hm: StandardMaterial3D = model.get("head_mat")
	if hm and not lamps_broken:
		hm.emission_energy_multiplier = 3.0 if on else 0.35

func set_inputs(throttle: float, brake: float, steer: float, handbrake: bool, nitro_btn: bool = false) -> void:
	in_throttle = clampf(throttle, 0.0, 1.0)
	in_brake = clampf(brake, 0.0, 1.0)
	in_steer = clampf(steer, -1.0, 1.0)
	in_handbrake = handbrake
	in_nitro = nitro_btn

func clear_inputs() -> void:
	set_inputs(0, 0, 0, false, false)

# ----------------------------------------------------------------------------
func _surface_mult(p: Vector3) -> float:
	var m: float = 1.0
	if surface_world != null:
		if not surface_world.on_road(p.x, p.z):
			var reg: String = surface_world.region_at(p.x, p.z)
			var off: float = 0.74
			if reg == "desert":
				off = 0.66
			elif reg == "mountain":
				off = 0.7
			if bool(spec.get("offroad", false)):
				off = minf(off + 0.2, 1.0)
			m = off
			on_road = false
		else:
			on_road = true
	return m * weather_grip

func _physics_process(dt: float) -> void:
	var fwd: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x
	var vel: Vector3 = linear_velocity
	speed = vel.dot(fwd)
	abs_speed = vel.length()
	var lat: float = vel.dot(right)
	slip_angle = atan2(lat, maxf(absf(speed), 0.5)) if abs_speed > 2.0 else 0.0
	crash_cd = maxf(0.0, crash_cd - dt)
	shift_timer = maxf(0.0, shift_timer - dt)
	# --- crash detection (sudden velocity change) --------------------------------
	var dv: Vector3 = vel - prev_vel
	if crash_cd <= 0.0 and prev_vel.length() > 4.0:
		var imp: float = dv.length()
		var thr: float = 5.5 if handling_arcade else 4.5
		if imp > thr and dv.dot(prev_vel) < 0.0 or imp > thr * 1.6:
			_on_impact(imp, dv)
	prev_vel = vel
	var contact_n: int = 0
	var min_skid: float = 1.0
	for w in wheels:
		var wh: VehicleWheel3D = w
		if wh.is_in_contact():
			contact_n += 1
			min_skid = minf(min_skid, wh.get_skidinfo())
	airborne_time = airborne_time + dt if contact_n == 0 else 0.0
	slip = clampf(1.0 - min_skid, 0.0, 1.0) if contact_n > 0 else 0.0
	var alive: bool = engine_on and not wrecked and fuel > 0.0
	# --- engine / gearbox -----------------------------------------------------------
	var top: float = float(stats["top"])
	var accel: float = float(stats["accel"])
	var dmg_pow: float = 1.0 - 0.5 * clampf((damage - 0.4) / 0.6, 0.0, 1.0)
	var boost: float = 1.0
	var topm: float = 1.0
	if has_nitro and in_nitro and nitro > 0.02 and speed > 3.0 and alive:
		boost = 1.55
		topm = 1.12
		nitro = maxf(0.0, nitro - dt / 5.0)
	else:
		nitro = minf(1.0, nitro + dt / 25.0)
	var gears: Array = spec["gears"]
	var ng: int = gears.size()
	braking_now = false
	reversing = false
	# progressive pedal response: throttle builds up, lifts quicker; brake bites progressively
	_thr_s = move_toward(_thr_s, in_throttle, dt * (3.2 if in_throttle > _thr_s else 7.0))
	_brk_s = move_toward(_brk_s, in_brake, dt * (5.0 if in_brake > _brk_s else 9.0))
	var throttle_cmd: float = _thr_s if in_throttle > 0.0 else 0.0
	var brake_cmd: float = _brk_s if in_brake > 0.0 else 0.0
	# S key semantics: brake while moving forward, reverse when (nearly) stopped
	if in_brake > 0.05 and in_throttle < 0.05 and speed < 1.2 and not in_handbrake:
		reversing = true
	elif in_throttle > 0.05 and speed < -1.5:
		brake_cmd = maxf(brake_cmd, in_throttle)
		throttle_cmd = 0.0
	var engine_f: float = 0.0
	var brake_f: float = 0.0
	if reversing:
		var rv: float = 1.0 - clampf(absf(speed) / 13.0, 0.0, 1.0)
		engine_f = -accel * 0.45 * rv * in_brake
		gear = -1
	else:
		if gear < 1:
			gear = 1
		var sp: float = maxf(speed, 0.0)
		var thrust: float = accel * boost * (1.0 - pow(clampf(sp / (top * topm), 0.0, 1.0), 2.2))
		var shift_cut: float = 0.25 if shift_timer > 0.0 else 1.0
		var launch: float = 1.0
		if not handling_arcade:
			launch = 1.0 - 0.18 * throttle_cmd * (1.0 - clampf(sp / 18.0, 0.0, 1.0))
		engine_f = thrust * throttle_cmd * shift_cut * dmg_pow * launch
		if throttle_cmd < 0.05 and sp > 1.0:
			brake_f += 0.06 * mass * 0.0035   # engine braking
		if brake_cmd > 0.05 and speed > -0.5:
			braking_now = true
			brake_f += brake_cmd * float(stats["brake"]) * mass * 0.0034 * BRAKE_K * (1.0 if handling_arcade else 0.88)
	if not alive:
		engine_f = 0.0
	# traction wheels count
	var ntrac: int = 0
	for w in wheels:
		if (w as VehicleWheel3D).use_as_traction:
			ntrac += 1
	engine_force = -(engine_f * mass / float(maxi(ntrac, 1))) * ENGINE_K   # Godot raycast vehicles drive toward +Z, models face -Z
	brake = brake_f
	# --- gearbox simulation --------------------------------------------------------------
	var sp2: float = maxf(speed, 0.0)
	var redline: float = float(spec["redline"])
	var idle: float = 850.0 if spec["engine"] != "electric" else 0.0
	if not reversing:
		var gi: int = clampi(gear - 1, 0, ng - 1)
		var frac: float = sp2 / maxf(0.1, float(vmax_gear[gi]))
		var now: float = Time.get_ticks_msec() / 1000.0
		if frac > 0.93 and gear < ng and now - _last_gear_change > 0.35 and throttle_cmd > 0.2:
			gear += 1
			_last_gear_change = now
			shift_timer = 0.16
			shifted.emit(true)
		elif frac < 0.42 and gear > 1 and now - _last_gear_change > 0.35:
			gear -= 1
			_last_gear_change = now
			shifted.emit(false)
		gi = clampi(gear - 1, 0, ng - 1)
		frac = sp2 / maxf(0.1, float(vmax_gear[gi]))
		var target_rpm: float = idle + (redline - idle) * clampf(frac, 0.0, 1.02)
		if sp2 < 4.0:
			target_rpm = maxf(target_rpm, idle + (redline - idle) * 0.55 * throttle_cmd)
		if shift_timer > 0.0:
			target_rpm *= 0.82
		rpm = lerpf(rpm, target_rpm, clampf(dt * 12.0, 0.0, 1.0))
	else:
		rpm = lerpf(rpm, idle + (redline - idle) * (absf(speed) / 14.0) * 0.8, clampf(dt * 8.0, 0.0, 1.0))
	rpm_norm = clampf((rpm - idle) / maxf(1.0, redline - idle), 0.0, 1.0)
	# --- surface-based grip ------------------------------------------------------------------
	var gm: float = _surface_mult(global_position)
	var dmg_grip: float = 1.0 - 0.15 * clampf(damage, 0.0, 1.0)
	var base_grip: float = float(stats["grip"]) * 2.4 * FRICTION_K * gm * dmg_grip
	if not handling_arcade:
		base_grip *= 0.92
	for i in range(wheels.size()):
		var w: VehicleWheel3D = wheels[i]
		var is_rear: bool = i >= 2
		var g: float = base_grip
		if in_handbrake and is_rear:
			g *= 0.32 if handling_arcade else 0.45
		elif is_rear and handling_arcade and in_throttle > 0.8 and abs_speed < 10.0 and String(spec["cat"]) == "Muscle Car":
			g *= 0.78
		if not handling_arcade and w.use_as_traction and throttle_cmd > 0.9 and abs_speed < 14.0:
			g *= 0.86
		w.wheel_friction_slip = lerpf(w.wheel_friction_slip, g, clampf(dt * 10.0, 0.0, 1.0))
	# --- steering ---------------------------------------------------------------------------------
	var max_s: float = float(stats["steer"])
	var a_lat: float = float(stats["grip"]) * 0.3 * 9.81 * (1.25 if handling_arcade else 1.0) * clampf(gm, 0.5, 1.0)
	var v2: float = maxf(abs_speed * abs_speed, 4.0)
	max_s = minf(max_s, atan(a_lat * float(spec["wb"]) / v2))
	var target: float = -in_steer * max_s * (float(Game.settings.get("steer_sens", 1.0)) ** 0.5)
	var rate: float = (7.0 if handling_arcade else 4.0) * (1.4 if absf(target) < absf(steer_cur) else 1.0)
	steer_cur = move_toward(steer_cur, target, rate * dt * max_s * 2.0)
	# counter-steer assist while drifting (arcade)
	if handling_arcade and abs_speed > 6.0:
		var cs: float = clampf(-slip_angle * 0.55, -0.35, 0.35)
		if absf(slip_angle) > 0.12 and signf(target) != signf(slip_angle) * -1.0 or absf(in_steer) < 0.1:
			steer_cur = clampf(steer_cur + cs * dt * 3.0, -float(stats["steer"]), float(stats["steer"]))
	steering = steer_cur
	# --- stabilising forces --------------------------------------------------------------------------
	var up: Vector3 = global_transform.basis.y
	if contact_n >= 2:
		# anti-roll (stop easy rollovers)
		var roll: float = asin(clampf(global_transform.basis.x.y, -1.0, 1.0))
		apply_torque(fwd * roll * mass * (18.0 if handling_arcade else 9.0))
		# downforce
		var df: float = float(spec["grip"]) * 0.00022 * abs_speed * abs_speed * (1.0 if String(spec["cat"]) in ["Supercar", "Hypercar", "Sports Car"] else 0.45)
		apply_central_force(-up * mass * df * 0.3)
		# arcade lateral grip assist
		if handling_arcade and not in_handbrake and abs_speed > 3.0:
			var assist: float = 2.6 * clampf(1.0 - absf(slip_angle) * 1.4, 0.0, 1.0) * gm
			apply_central_force(-right * lat * mass * assist)
		# drift initiation help
		if in_handbrake and abs_speed > 8.0 and handling_arcade:
			apply_torque(up * -in_steer * mass * 6.5 * clampf(abs_speed / 30.0, 0.0, 1.0))
		elif handling_arcade and absf(slip_angle) > 0.2 and in_throttle > 0.3 and abs_speed > 9.0:
			apply_torque(up * signf(slip_angle) * -mass * 1.8)
	elif contact_n == 0 and airborne_time > 0.2:
		# gentle self-righting in the air
		var tilt: Vector3 = up.cross(Vector3.UP)
		apply_torque(tilt * mass * 1.5)
	if in_handbrake and abs_speed > 1.0:
		apply_central_force(-vel.normalized() * mass * 3.0)
	# off-road penalty
	if not on_road and not bool(spec.get("offroad", false)):
		apply_central_force(-vel * mass * 0.18)
	# --- drift scoring -----------------------------------------------------------------------------------
	var was: bool = drifting
	drifting = abs_speed > 9.0 and absf(slip_angle) > 0.26 and contact_n >= 2
	if drifting:
		drift_time += dt
		drift_points += dt * abs_speed * absf(slip_angle) * 3.0
	elif was:
		drift_time = 0.0
	# --- fuel ---------------------------------------------------------------------------------------------------
	if alive:
		var burn: float = (0.00005 + 0.00018 * in_throttle * (accel / 8.0)) * (1.0 + 0.5 * float(boost > 1.0))
		fuel = maxf(0.0, fuel - burn * dt * (1.0 if abs_speed > 0.5 or in_throttle > 0.1 else 0.3))
	distance_driven += abs_speed * dt
	# --- visual fx ---------------------------------------------------------------------------------------------------
	var skid_emit: bool = (slip > 0.35 or drifting or (in_handbrake and abs_speed > 6.0)) and abs_speed > 5.0 and contact_n >= 2
	for ts in _tire_smoke:
		(ts as CPUParticles3D).emitting = skid_emit
	_smoke.emitting = damage > 0.55 and not wrecked or wrecked
	_smoke.amount = 24 if damage < 0.85 else 40
	var tmat: StandardMaterial3D = model.get("tail_mat")
	if tmat:
		tmat.emission_energy_multiplier = 3.5 if (braking_now or in_handbrake) else (1.4 if headlights_on else 0.4)
	# unflip if stuck on roof for a while (player can also press R)
	if up.y < 0.25 and abs_speed < 2.5:
		respawn_hold += dt
	else:
		respawn_hold = 0.0

func _on_impact(imp: float, dv: Vector3) -> void:
	crash_cd = 0.25
	last_impact = imp
	# Damage scales with the square of the speed lost (kinetic energy), e.g.
	#  6 m/s (~22 km/h) -> ~2%   12 m/s -> ~8%   20 m/s -> ~22%   30 m/s -> ~50%   40+ m/s -> wreck range
	var sev: float = clampf(0.00055 * imp * imp, 0.005, 0.9)
	if handling_arcade:
		sev *= 0.8
	damage = clampf(damage + sev, 0.0, 1.0)
	sev = clampf(sev * 3.0, 0.05, 1.5)   # audio/shake/dent scale (0..1.5)
	var ldir: Vector3 = global_transform.basis.inverse() * (-dv).normalized()
	if ldir.z < -0.35 and damage > 0.2:
		lamps_broken = true
		var hm0: StandardMaterial3D = model.get("head_mat")
		if hm0:
			hm0.emission_energy_multiplier = 0.0
			hm0.albedo_color = Color(0.1, 0.1, 0.1)
		for sp in _spot:
			(sp as SpotLight3D).visible = false
	# dent at impact point
	var local_dir: Vector3 = global_transform.basis.inverse() * (-dv).normalized()
	var L: float = float(spec["L"])
	var W: float = float(spec["W"])
	var pt := Vector3(clampf(local_dir.x * W * 0.6, -W * 0.5, W * 0.5), clampf(0.55 + local_dir.y * 0.3, 0.3, 0.95), clampf(local_dir.z * L * 0.6, -L * 0.5, L * 0.5))
	dents[dent_i] = Vector4(pt.x, pt.y, pt.z, clampf(0.45 + sev * 0.8, 0.0, 1.6))
	dent_i = (dent_i + 1) % 4
	apply_damage_visuals()
	crashed.emit(sev, global_position)
	if damage >= 0.999 and not wrecked:
		wrecked = true
		destroyed.emit()

func apply_damage_visuals() -> void:
	var paint: ShaderMaterial = model.get("paint")
	if paint:
		paint.set_shader_parameter("damage", damage)
		paint.set_shader_parameter("dents", dents)
	var glass: StandardMaterial3D = model.get("glass")
	if glass:
		if damage > 0.5:
			glass.albedo_color = Color(0.55, 0.6, 0.65, 0.85)
		else:
			var ti: int = clampi(int(custom.get("tint", 1)), 0, 3)
			glass.albedo_color = Color(0.04, 0.06, 0.09, [0.35, 0.55, 0.78, 0.94][ti])
	if damage > 0.35 and _spot.size() > 0:
		(_spot[0] as SpotLight3D).visible = false
	if damage > 0.7:
		var hm: StandardMaterial3D = model.get("head_mat")
		if hm:
			hm.emission_energy_multiplier = 0.0

func repair_full() -> void:
	damage = 0.0
	lamps_broken = false
	var hm1: StandardMaterial3D = model.get("head_mat")
	if hm1:
		hm1.albedo_color = (model.get("head_color") as Color) * 0.4
	wrecked = false
	dents = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
	apply_damage_visuals()
	set_headlights(headlights_on)

func door_position(side: float = -1.0) -> Vector3:
	return global_transform * Vector3(side * (float(spec["W"]) * 0.5 + 0.9), 0.2, -float(spec["L"]) * 0.1)

func place_on_ground(pos: Vector3, yaw: float) -> void:
	global_transform = Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, 0.55, 0))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	prev_vel = Vector3.ZERO

func speed_kmh() -> float:
	return abs_speed * 3.6

func set_traffic_look() -> void:
	pass
