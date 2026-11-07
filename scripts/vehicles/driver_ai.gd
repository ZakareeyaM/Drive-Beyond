class_name DriverAI
extends RefCounted
## Path-following driver for race opponents and police. Works on any Vehicle.

var v: Vehicle
var path: PackedVector3Array = PackedVector3Array()
var cum: PackedFloat32Array = PackedFloat32Array()
var idx: int = 0
var skill: float = 0.7            # 0..1 : cornering speed + aggression
var speed_scale: float = 1.0
var direct_target: Vector3 = Vector3.ZERO
var use_direct: bool = false
var stuck_t: float = 0.0
var reverse_t: float = 0.0
var reverse_steer: float = 0.0
var finished: bool = false
var progress: float = 0.0
var avoid_space: PhysicsDirectSpaceState3D
var enabled: bool = true
var yield_to_obstacle: bool = true

func _init(vehicle: Vehicle, p_skill: float = 0.7) -> void:
	v = vehicle
	skill = p_skill

func set_path(p: PackedVector3Array) -> void:
	path = p
	cum = RoadNav.cumulative(p)
	idx = 0
	finished = false

func remaining() -> float:
	if path.size() == 0:
		return 0.0
	return cum[cum.size() - 1] - progress

func _nearest_index(pos: Vector3) -> void:
	var best: float = 1e18
	var bi: int = idx
	var lo: int = maxi(0, idx - 4)
	var hi: int = mini(path.size() - 1, idx + 40)
	for i in range(lo, hi + 1):
		var d: float = (path[i].x - pos.x) * (path[i].x - pos.x) + (path[i].z - pos.z) * (path[i].z - pos.z)
		if d < best:
			best = d
			bi = i
	idx = bi
	progress = cum[idx]

func _curve_speed(from_i: int, ahead: float) -> float:
	# estimate sharpest turn within `ahead` metres from index
	var i0: int = from_i
	var acc: float = 0.0
	var i1: int = i0
	while i1 < path.size() - 1 and acc < ahead:
		acc += path[i1].distance_to(path[i1 + 1])
		i1 += 1
	var imid: int = (i0 + i1) / 2
	if i1 - i0 < 2:
		return 999.0
	var a: Vector2 = Vector2(path[imid].x - path[i0].x, path[imid].z - path[i0].z)
	var b: Vector2 = Vector2(path[i1].x - path[imid].x, path[i1].z - path[imid].z)
	if a.length() < 0.5 or b.length() < 0.5:
		return 999.0
	var ang: float = absf(a.angle_to(b))
	var chord: float = maxf(1.0, a.length() + b.length())
	var radius: float = chord / maxf(0.05, 2.0 * sin(clampf(ang, 0.02, 1.5)))
	var a_lat: float = (7.0 + 8.0 * skill)
	return sqrt(a_lat * radius)

func update(dt: float) -> void:
	if not enabled or not is_instance_valid(v):
		return
	var pos: Vector3 = v.global_position
	var target: Vector3
	var vtarget: float = float(v.stats["top"]) * speed_scale * (0.82 + 0.2 * skill)
	if use_direct or path.size() < 2:
		target = direct_target
		var to_t: Vector3 = target - pos
		if not use_direct and path.size() < 2:
			v.set_inputs(0, 0.6, 0, false)
			return
	else:
		_nearest_index(pos)
		var look: float = clampf(7.0 + v.abs_speed * 0.55, 9.0, 42.0)
		var j: int = idx
		var acc: float = 0.0
		while j < path.size() - 1 and acc < look:
			acc += path[j].distance_to(path[j + 1])
			j += 1
		target = path[j]
		if idx >= path.size() - 2 and pos.distance_to(path[path.size() - 1]) < 12.0:
			finished = true
		vtarget = minf(vtarget, _curve_speed(idx, 14.0 + v.abs_speed * 1.6))
	var local: Vector3 = v.global_transform.affine_inverse() * target
	var ang: float = atan2(local.x, -local.z)
	var steer: float = clampf(ang / maxf(0.12, float(v.stats["steer"]) * (0.6 if v.abs_speed < 12.0 else 0.25)), -1.0, 1.0)
	var throttle: float = 0.0
	var brake_in: float = 0.0
	var spd: float = v.speed
	if use_direct:
		var dist: float = pos.distance_to(target)
		if dist < 6.0:
			vtarget = minf(vtarget, 8.0)
	# obstacle ahead
	if yield_to_obstacle and v.abs_speed > 3.0:
		var fwd: Vector3 = -v.global_transform.basis.z
		var from: Vector3 = pos + Vector3(0, 0.6, 0) + fwd * 2.4
		var to: Vector3 = from + fwd * (6.0 + v.abs_speed * 0.9)
		var space: PhysicsDirectSpaceState3D = v.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2)
		q.exclude = [v.get_rid()]
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty() and not (hit["collider"] is StaticBody3D and hit["collider"].is_in_group("terrain")):
			var d: float = from.distance_to(hit["position"])
			var other_speed: float = 0.0
			if hit["collider"] is Vehicle:
				other_speed = (hit["collider"] as Vehicle).speed
			if d < 5.0 + v.abs_speed * 0.5 and not (is_instance_valid(hit["collider"]) and v.is_police and hit["collider"].is_in_group("player_vehicle")):
				vtarget = minf(vtarget, maxf(other_speed - 1.0, 0.0))
				steer += clampf(-local.x * 0.0, -0.3, 0.3)
	if spd < vtarget - 0.8:
		throttle = clampf((vtarget - spd) / 4.0 + 0.3, 0.0, 1.0)
	elif spd > vtarget + 1.5:
		brake_in = clampf((spd - vtarget) / 8.0, 0.0, 1.0)
	# stuck handling
	if reverse_t > 0.0:
		reverse_t -= dt
		v.set_inputs(0, 1.0, reverse_steer, false)
		return
	if v.abs_speed < 1.0 and throttle > 0.4:
		stuck_t += dt
		if stuck_t > 1.8:
			stuck_t = 0.0
			reverse_t = 1.3
			reverse_steer = -steer
	else:
		stuck_t = maxf(0.0, stuck_t - dt)
	if v.wrecked or v.fuel <= 0.0:
		v.set_inputs(0, 0.5, 0, false)
		return
	v.set_inputs(throttle, brake_in, steer, absf(steer) > 0.9 and v.abs_speed > 25.0 and skill > 0.8)
