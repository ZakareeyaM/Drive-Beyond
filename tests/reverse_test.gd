extends Node
# godot --headless --path . tests/reverse_test.tscn -- [vid ...]   : reverse <-> forward transition test
var car: Vehicle
var ids: Array = []
var idx := 0
var phase := 0
var t := 0.0
var prev := 0.0
var max_jump := 0.0
var t_zero := -1.0
var t_fwd := -1.0
var t_rev := -1.0
var t_stop := -1.0
var res := {}

func _ready() -> void:
	Engine.physics_ticks_per_second = 60
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = Vector3(6000, 2, 6000)
	cs.shape = bs; cs.position = Vector3(0, -1, 0)
	ground.add_child(cs)
	add_child(ground)
	var ua := OS.get_cmdline_user_args()
	ids = ua if ua.size() > 0 else Data.vehicle_ids()
	_next()

func _next() -> void:
	if idx >= ids.size():
		print("--- reverse test done ---")
		get_tree().quit()
		return
	if car: car.queue_free()
	var vid: String = ids[idx]; idx += 1
	car = Vehicle.new()
	add_child(car)
	car.configure(vid, Data.default_custom(vid), Data.default_upgrades())
	car.place_on_ground(Vector3.ZERO, 0.0)
	phase = 0; t = 0.0; max_jump = 0.0; t_zero = -1.0; t_fwd = -1.0; t_rev = -1.0; t_stop = -1.0

func _physics_process(dt: float) -> void:
	t += dt
	var sp: float = car.speed
	match phase:
		0: # settle then drive forward 4 s
			if t > 1.5:
				phase = 1; t = 0.0
		1: # accelerate forward
			car.set_inputs(1, 0, 0, false)
			if t > 3.5:
				res["v_fwd"] = sp
				phase = 2; t = 0.0
		2: # forward -> reverse: release throttle, hold brake only
			car.set_inputs(0, 1, 0, false)
			if t_rev < 0 and sp < -4.0:
				t_rev = t
			if t > 12.0 or sp < -9.0:
				res["fwd_to_rev_s"] = t_rev
				res["v_rev"] = sp
				phase = 3; t = 0.0; prev = sp
		3: # reverse -> forward: release brake, press accelerator only
			car.set_inputs(1, 0, 0, false)
			max_jump = maxf(max_jump, absf(sp - prev))
			prev = sp
			if t_zero < 0 and sp >= 0.0:
				t_zero = t
			if t_fwd < 0 and sp >= 5.0:
				t_fwd = t
			if t > 10.0 or t_fwd > 0:
				var vid: String = ids[idx - 1]
				print("REVTEST %-14s v_fwd=%5.1f  fwd->rev(-4m/s)=%5.2fs v_rev=%5.1f | rev->fwd: zero=%5.2fs  +5m/s=%5.2fs  max dv/tick=%.2f m/s" % [vid, res["v_fwd"], res["fwd_to_rev_s"], res["v_rev"], t_zero, t_fwd, max_jump])
				_next()
