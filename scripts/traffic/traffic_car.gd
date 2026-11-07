class_name TrafficCar
extends RigidBody3D
## A background-traffic vehicle. Frozen/kinematic while it follows the road
## graph; becomes a real physics body (wreck) when the player hits it.

var vid: String = "strada_s2"
var spec: Dictionary = {}
var edge: int = 0
var dir: int = 1
var s: float = 0.0
var lane: int = 0
var lane_off: float = 2.0
var lane_timer: float = 0.0
var speed: float = 0.0
var pref_speed: float = 14.0
var state: String = "drive"
var wreck_time: float = 0.0
var wheels: Array = []
var tail_mat: StandardMaterial3D
var head_mat: StandardMaterial3D
var model: Dictionary = {}

func setup(p_vid: String, custom: Dictionary) -> void:
	vid = p_vid
	spec = Data.vehicle(vid)
	mass = float(spec["mass"])
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	collision_layer = 2
	collision_mask = 1 | 2
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.3
	angular_damp = 1.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.4, 0)
	add_to_group("traffic")
	model = CarBuilder.build(vid, custom)
	var m: Node3D = model["root"]
	m.position = Vector3(0, 0.0, 0)
	add_child(m)
	tail_mat = model["tail_mat"]
	head_mat = model["head_mat"]
	var L: float = float(spec["L"])
	var W: float = float(spec["W"])
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(W * 0.96, float(spec["roof"]) - float(spec["belly"]) - 0.1, L * 0.97)
	cs.shape = bs
	cs.position = Vector3(0, float(spec["belly"]) + bs.size.y * 0.5, 0)
	add_child(cs)
	for fz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			var wv: MeshInstance3D = CarBuilder.build_wheel(vid, custom)
			wv.position = Vector3(sx * float(spec["track"]) * 0.5, float(spec["wr"]), fz * float(spec["wb"]) * 0.5)
			m.add_child(wv)
			wheels.append(wv)
	m.position = Vector3(0, 0.0, 0)

func spin_wheels(dist: float) -> void:
	var r: float = float(spec["wr"])
	for wv in wheels:
		(wv as Node3D).rotation.x -= dist / r

func set_brake_light(on: bool) -> void:
	tail_mat.emission_energy_multiplier = 3.5 if on else 0.6

func set_night(night: bool) -> void:
	head_mat.emission_energy_multiplier = 2.5 if night else 0.35

func wreck(impact_vel: Vector3) -> void:
	if state == "wreck":
		return
	state = "wreck"
	freeze = false
	linear_velocity = Vector3.ZERO
	apply_central_impulse(impact_vel * mass * 0.8 + Vector3(0, mass * 0.6, 0))
	apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * mass * 0.5)
	var paint: ShaderMaterial = model.get("paint")
	if paint:
		paint.set_shader_parameter("damage", 0.8)
		paint.set_shader_parameter("dents", [Vector4(0, 0.6, -float(spec["L"]) * 0.4, 1.2), Vector4(0.6, 0.6, 0.3, 0.8), Vector4.ZERO, Vector4.ZERO])
	var hm: StandardMaterial3D = model.get("head_mat")
	if hm:
		hm.emission_energy_multiplier = 0.0
