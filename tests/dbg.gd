extends Node
var car: Vehicle
var t := 0.0
func _ready() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = Vector3(6000, 2, 6000)
	cs.shape = bs; cs.position = Vector3(0, -1, 0)
	ground.add_child(cs)
	add_child(ground)
	car = Vehicle.new()
	add_child(car)
	car.configure("vela_gt", Data.default_custom("vela_gt"), Data.default_upgrades())
	car.place_on_ground(Vector3.ZERO, 0.0)
func _physics_process(dt: float) -> void:
	t += dt
	if t > 2.0:
		car.set_inputs(1, 0, 1.0 if t > 5.0 else 0.0, false)
	if int(t * 60) % 30 == 0:
		var c := 0
		for w in car.wheels: if w.is_in_contact(): c += 1
		print("yawrate %.3f t %.2f y %.3f speed %.2f ef %.1f brake %.2f contact %d gear %d rpm %.0f fric %.2f" % [car.angular_velocity.y, t, car.global_position.y, car.speed, car.engine_force, car.brake, c, car.gear, car.rpm, car.wheels[2].wheel_friction_slip])
	if t > 8.0: get_tree().quit()
