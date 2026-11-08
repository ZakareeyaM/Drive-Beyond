class_name CameraRig
extends Node3D
## Chase / close / cockpit / hood / cinematic cameras for the vehicle plus a
## third-person orbit camera for the on-foot player.

const MODES := ["chase", "close", "cockpit", "hood", "cinematic"]
const MODE_LABEL := {"chase": "Chase", "close": "Close", "cockpit": "Cockpit", "hood": "Hood", "cinematic": "Cinematic"}

var cam: Camera3D
var target: Node3D = null
var on_foot: bool = false
var mode_i: int = 0
var yaw: float = 0.0              # smoothed world yaw of camera
var look_yaw: float = 0.0         # user free-look offset
var look_pitch: float = 0.0
var look_hold: float = 0.0
var foot_yaw: float = 0.0
var foot_pitch: float = -0.25
var shake: float = 0.0
var fov_cur: float = 68.0
var cine_t: float = 0.0
var cine_seed: int = 0
var cur_pos: Vector3 = Vector3.ZERO
var orbit_mode: bool = false      # menu / garage cinematic orbit
var orbit_center: Vector3 = Vector3.ZERO
var orbit_t: float = 0.0
var orbit_radius: float = 60.0
var orbit_height: float = 25.0
var world_ref: Node = null
var _prev_vel: Vector3 = Vector3.ZERO

func _init() -> void:
	cam = Camera3D.new()
	cam.current = true
	cam.far = 1500.0
	cam.near = 0.12
	cam.fov = 68.0
	add_child(cam)

func mode() -> String:
	return MODES[mode_i]

func cycle_mode() -> void:
	mode_i = (mode_i + 1) % MODES.size()
	cine_t = 0.0
	Game.notify.emit("Camera: %s" % MODE_LABEL[MODES[mode_i]], "info")

func add_look(dx: float, dy: float) -> void:
	var s: float = float(Game.settings.get("camera_sens", 1.0))
	if on_foot:
		foot_yaw -= dx * 0.006 * s
		foot_pitch = clampf(foot_pitch - dy * 0.005 * s, -1.2, 0.5)
	else:
		look_yaw -= dx * 0.006 * s
		look_pitch = clampf(look_pitch - dy * 0.004 * s, -0.5, 0.8)
		look_hold = 1.6

func add_shake(a: float) -> void:
	if bool(Game.settings.get("cam_shake", true)):
		shake = minf(shake + a, 1.2)

func snap() -> void:
	if target == null:
		return
	if on_foot:
		foot_yaw = target.rotation.y
	else:
		yaw = _vehicle_yaw()
	look_yaw = 0.0
	look_pitch = 0.0
	_update(1.0, 1.0)

func _vehicle_yaw() -> float:
	var f: Vector3 = -target.global_transform.basis.z
	return atan2(-f.x, -f.z)

func _process(delta: float) -> void:
	if orbit_mode:
		orbit_t += delta * 0.07
		var p: Vector3 = orbit_center + Vector3(sin(orbit_t) * orbit_radius, orbit_height + sin(orbit_t * 0.7) * 6.0, cos(orbit_t) * orbit_radius)
		global_position = p
		look_at(orbit_center + Vector3(0, 12, 0), Vector3.UP)
		cam.position = Vector3.ZERO
		cam.rotation = Vector3.ZERO
		cam.fov = 62.0
		return
	if target == null or not is_instance_valid(target):
		return
	_update(delta, 0.0)

func _ray_clip(from: Vector3, to: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return to
	return from + (hit["position"] - from) * 0.9 - (to - from).normalized() * 0.15

func _update(delta: float, snap_f: float) -> void:
	var cd: float = float(Game.settings.get("cam_distance", 1.0))
	if on_foot:
		var p: Vector3 = target.global_position + Vector3(0, 1.5, 0)
		var dir := Vector3(sin(foot_yaw) * cos(foot_pitch), -sin(foot_pitch), cos(foot_yaw) * cos(foot_pitch))
		var want: Vector3 = p + dir * 4.2 * cd + Vector3(0, 0.5, 0)
		want = _ray_clip(p, want)
		cur_pos = cur_pos.lerp(want, clampf(delta * 14.0, 0.0, 1.0)) if snap_f < 0.5 else want
		cam.global_position = cur_pos
		cam.look_at(p + Vector3(0, 0.1, 0), Vector3.UP)
		cam.fov = lerpf(cam.fov, 66.0, clampf(delta * 5.0, 0.0, 1.0))
		return
	var v: Vehicle = target as Vehicle
	var vel: Vector3 = v.linear_velocity if v else Vector3.ZERO
	var spd: float = vel.length()
	var fwd: Vector3 = -target.global_transform.basis.z
	var body_yaw: float = atan2(-fwd.x, -fwd.z)
	var m: String = MODES[mode_i]
	# free look decays back
	if look_hold > 0.0:
		look_hold -= delta
	else:
		look_yaw = lerpf(look_yaw, 0.0, clampf(delta * 3.0, 0.0, 1.0))
		look_pitch = lerpf(look_pitch, 0.0, clampf(delta * 3.0, 0.0, 1.0))
	var fov_t: float = 66.0 + clampf(spd * 0.32, 0.0, 22.0)
	var shake_off := Vector3.ZERO
	var sh: float = shake + clampf((spd - 30.0) / 120.0, 0.0, 0.15) * (0.4 if m == "chase" else 1.0)
	if sh > 0.001:
		shake_off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * sh * 0.05
	shake = maxf(0.0, shake - delta * 2.2)
	match m:
		"chase", "close":
			var dist: float = (6.4 if m == "chase" else 4.3) * cd
			var h: float = (2.3 if m == "chase" else 1.55) * (0.8 + 0.2 * cd)
			if v:
				var L: float = float(v.spec["L"])
				dist += (L - 4.3) * 0.5
				h += float(v.spec["roof"]) - 1.4
				var vcam: Dictionary = VehicleModels.cfg(v.vid).get("cam", {})   # optional per-model camera tweak
				dist *= float(vcam.get("dist", 1.0))
				h += float(vcam.get("height", 0.0))
			var follow_yaw: float = body_yaw
			if spd > 6.0 and v and v.speed > 0.0:
				var vy: float = atan2(-vel.x, -vel.z)
				follow_yaw = lerp_angle(body_yaw, vy, 0.35)
			var rate: float = clampf(delta * (5.5 - clampf(spd * 0.03, 0.0, 2.0)), 0.0, 1.0)
			yaw = follow_yaw if snap_f > 0.5 else lerp_angle(yaw, follow_yaw, rate)
			var ay: float = yaw + look_yaw
			var back := Vector3(sin(ay), 0, cos(ay))
			var focus: Vector3 = target.global_position + Vector3(0, 1.0, 0)
			var want: Vector3 = focus + back * dist * cos(look_pitch) + Vector3(0, h - 1.0 + sin(look_pitch) * dist, 0)
			want = _ray_clip(focus, want)
			cur_pos = want if snap_f > 0.5 else cur_pos.lerp(want, clampf(delta * 12.0, 0.0, 1.0))
			cam.global_position = cur_pos + shake_off
			cam.look_at(focus + Vector3(0, 0.45, 0), Vector3.UP)
			cam.fov = lerpf(cam.fov, fov_t + (6.0 if v and v.in_nitro and v.nitro > 0.0 else 0.0), clampf(delta * 4.0, 0.0, 1.0))
		"cockpit":
			var bs: Basis = target.global_transform.basis
			var sp := Vector3(0.38, float(v.spec["belt"]) + 0.36, -float(v.spec["L"]) * 0.03) if v else Vector3(0, 1.2, 0)
			var base_pos: Vector3 = target.global_transform * sp
			var lb: Basis = bs * Basis(Vector3.UP, look_yaw) * Basis(Vector3.RIGHT, look_pitch)
			cam.global_transform = Transform3D(lb, base_pos + shake_off * 0.4)
			cam.fov = lerpf(cam.fov, 74.0 + clampf(spd * 0.1, 0.0, 10.0), clampf(delta * 4.0, 0.0, 1.0))
		"hood":
			var sp2 := Vector3(0, float(v.spec["hood"]) + 0.28, -float(v.spec["L"]) * 0.18) if v else Vector3(0, 1.2, 0)
			var bs2: Basis = target.global_transform.basis * Basis(Vector3.UP, look_yaw) * Basis(Vector3.RIGHT, look_pitch)
			cam.global_transform = Transform3D(bs2, target.global_transform * sp2 + shake_off * 0.6)
			cam.fov = lerpf(cam.fov, 72.0 + clampf(spd * 0.15, 0.0, 14.0), clampf(delta * 4.0, 0.0, 1.0))
		"cinematic":
			cine_t -= delta
			if cine_t <= 0.0:
				cine_t = randf_range(4.0, 7.0)
				cine_seed = randi() % 4
			var t: float = Time.get_ticks_msec() * 0.001
			var off := Vector3.ZERO
			match cine_seed:
				0: off = Vector3(sin(t * 0.3) * 6.5, 1.0, -5.0 + cos(t * 0.3) * 3.0)
				1: off = Vector3(3.2, 0.5, 4.5)
				2: off = Vector3(-4.0, 1.4, -3.2)
				3: off = Vector3(0.0, 3.4, 7.0)
			var target_xf: Transform3D = target.global_transform
			var want2: Vector3 = target.global_position + (target_xf.basis * off)
			want2.y = maxf(want2.y, target.global_position.y + 0.5)
			want2 = _ray_clip(target.global_position + Vector3(0, 1.0, 0), want2)
			cur_pos = cur_pos.lerp(want2, clampf(delta * 3.0, 0.0, 1.0))
			cam.global_position = cur_pos
			cam.look_at(target.global_position + Vector3(0, 0.8, 0) + vel * 0.05, Vector3.UP)
			cam.fov = lerpf(cam.fov, 52.0, clampf(delta * 3.0, 0.0, 1.0))
