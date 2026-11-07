extends Node
# headless physics calibration: godot --headless --path . tests/physics_test.tscn -- [vid]
var car: Vehicle
var phase := 0
var t := 0.0
var vid := "vela_gt"
var results := {}
var ids: Array = []
var idx := 0
var t100 := -1.0
var topv := 0.0
var brake_start_pos := Vector3.ZERO
var maxlat := 0.0
var sag := 0.0

func _ready() -> void:
	Engine.physics_ticks_per_second = 60
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = Vector3(6000, 2, 6000)
	cs.shape = bs; cs.position = Vector3(0, -1, 0)
	ground.add_child(cs)
	add_child(ground)
	var ua := OS.get_cmdline_user_args()
	if ua.size() > 0: ids = [ua[0]]
	else: ids = Data.vehicle_ids()
	_next()

func _next() -> void:
	if idx >= ids.size():
		print("--- done ---")
		get_tree().quit()
		return
	if car: car.queue_free()
	vid = ids[idx]; idx += 1
	car = Vehicle.new()
	add_child(car)
	car.configure(vid, Data.default_custom(vid), Data.default_upgrades())
	car.place_on_ground(Vector3(0, 0, 0), 0.0)
	phase = 0; t = 0.0; t100 = -1.0; topv = 0.0; maxlat = 0.0

func _physics_process(dt: float) -> void:
	t += dt
	match phase:
		0: # settle
			if t > 2.0:
				sag = car.global_position.y
				phase = 1; t = 0.0
		1: # accelerate
			car.set_inputs(1, 0, 0, false)
			if t100 < 0 and car.abs_speed >= 27.78:
				t100 = t
			topv = max(topv, car.abs_speed)
			if t > 32.0 or (t > 6.0 and t100 > 0 and car.abs_speed >= car.stats["top"] * 0.97):
				phase = 2; t = 0.0
		2: # brake from current speed
			if t < 0.02:
				brake_start_pos = car.global_position
				results["v0"] = car.abs_speed
			car.set_inputs(0, 1, 0, false)
			if car.abs_speed < 0.4 or t > 12.0:
				results["brake_dist"] = (car.global_position - brake_start_pos).length()
				results["brake_t"] = t
				phase = 3; t = 0.0
		3: # re-launch to 22 m/s then steer full for lateral g
			if car.abs_speed < 22.0:
				car.set_inputs(1, 0, 0, false)
			else:
				car.set_inputs(0.35, 0, 1.0, false)
				var latv: float = abs(car.linear_velocity.dot(car.global_transform.basis.x))
				var r: float = car.angular_velocity.y * car.abs_speed
				maxlat = max(maxlat, abs(r))
			if t > 7.0:
				print("%-12s stat acc %.1f top %.0f km/h | 0-100: %.2fs  top: %.0f km/h | brake from %.0f km/h: %.1f m (%.2fg) | lat %.2fg | ride y %.3f | gear %d dmg %.2f up %.2f" % [vid, car.stats["accel"], car.stats["top"]*3.6, t100, topv*3.6, results["v0"]*3.6, results["brake_dist"], results["v0"]*results["v0"]/(2*max(results["brake_dist"],0.1))/9.81, maxlat/9.81, sag, car.gear, car.damage, car.global_transform.basis.y.y])
				_next()
