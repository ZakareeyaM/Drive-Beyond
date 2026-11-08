extends Node
# Headless collision calibration: godot --headless --path . tests/crash_test.tscn -- [vid]
# For each (obstacle, speed) a car is fired at a solid object; reports tunnelling, speed loss and damage.
var runs: Array = []
var ri := 0
var car: Vehicle
var obs: Node3D
var t := 0.0
var vid := "kestrel_r"
var min_z := 0.0
var cur: Array

func _ready() -> void:
	Engine.physics_ticks_per_second = 60
	var ua := OS.get_cmdline_user_args()
	if ua.size() > 0: vid = ua[0]
	var g := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = Vector3(6000, 2, 6000)
	cs.shape = bs; cs.position = Vector3(0, -1, 0)
	g.add_child(cs); add_child(g)
	for sp in [6.0, 12.0, 20.0, 30.0, 45.0, 60.0]:
		runs.append(["pole", sp])
	for k in ["tree", "building", "rail", "parked_car"]:
		runs.append([k, 25.0])
	_next()

func _make_obstacle(kind: String) -> Node3D:
	var sb: Node3D
	if kind == "parked_car":
		var v := Vehicle.new()
		add_child(v)
		v.configure("strada_s2", Data.default_custom("strada_s2"), Data.default_upgrades())
		v.place_on_ground(Vector3(0, 0, -60), 0.0)
		v.engine_on = false
		return v
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var c := CollisionShape3D.new()
	var b := BoxShape3D.new()
	match kind:
		"pole": b.size = Vector3(0.3, 5.6, 0.3); c.position = Vector3(0, 2.8, 0)
		"tree": b.size = Vector3(0.55, 4.0, 0.55); c.position = Vector3(0, 2.0, 0)
		"building": b.size = Vector3(20, 30, 20); c.position = Vector3(0, 15, 0)
		"rail": b.size = Vector3(0.4, 1.1, 10.0); c.position = Vector3(0, 0.55, 0); body.rotation.y = PI * 0.5
	c.shape = b
	body.add_child(c)
	body.position = Vector3(0, 0, -60)
	add_child(body)
	return body

func _next() -> void:
	if ri >= runs.size():
		print("--- crash test done ---")
		get_tree().quit()
		return
	cur = runs[ri]; ri += 1
	if car: car.queue_free()
	if obs: obs.queue_free()
	await get_tree().physics_frame
	obs = _make_obstacle(cur[0])
	car = Vehicle.new()
	add_child(car)
	car.configure(vid, Data.default_custom(vid), Data.default_upgrades())
	car.place_on_ground(Vector3(0, 0, 0), 0.0)
	car.linear_velocity = Vector3(0, 0, -float(cur[1]))
	car.prev_vel = car.linear_velocity
	car.crash_cd = 0.0
	t = 0.0
	min_z = 0.0

func _physics_process(dt: float) -> void:
	if car == null or not is_instance_valid(car): return
	t += dt
	car.set_inputs(0.0, 0.0, 0.0, false)
	min_z = minf(min_z, car.global_position.z)
	if t > 0.5 and car.linear_velocity.length() < float(cur[1]) * 0.0 + 1e9 and t > 6.0:
		var tunnel: bool = min_z < -64.0 and cur[0] != "building" and cur[0] != "parked_car"
		var pass_b: bool = min_z < -75.0 and cur[0] == "building"
		print("%-10s v0=%4.0f m/s (%3.0f km/h) | impact dv=%5.1f | speed after=%4.1f | damage=%.3f | z_min=%.1f | tunnelled=%s" % [cur[0], cur[1], float(cur[1]) * 3.6, car.last_impact, car.linear_velocity.length(), car.damage, min_z, str(tunnel or pass_b)])
		_next()
