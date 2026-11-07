class_name FootPlayer
extends CharacterBody3D
## On-foot character: walk / sprint / jump, simple procedural humanoid.

const WALK := 3.4
const RUN := 6.8
const JUMP := 5.2

var cam_yaw: float = 0.0
var move_input: Vector2 = Vector2.ZERO
var want_jump: bool = false
var want_sprint: bool = false
var vis: Node3D
var legs: Array = []
var arms: Array = []
var phase: float = 0.0
var enabled: bool = true
var ragdoll_t: float = 0.0
var sink_time: float = 0.0

func _init() -> void:
	collision_layer = 4
	collision_mask = 1 | 2
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(55.0)
	vis = Node3D.new()
	add_child(vis)
	_build()

func _mat(c: Color, r: float = 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = r
	return m

func _box(sz: Vector3, pos: Vector3, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = sz
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _build() -> void:
	var skin: StandardMaterial3D = _mat(Color(0.62, 0.45, 0.34))
	var jacket: StandardMaterial3D = _mat(Color(0.08, 0.08, 0.1), 0.6)
	var accent: StandardMaterial3D = _mat(Color(0.75, 0.05, 0.08), 0.5)
	var pants: StandardMaterial3D = _mat(Color(0.12, 0.14, 0.2))
	var shoe: StandardMaterial3D = _mat(Color(0.9, 0.9, 0.92))
	_box(Vector3(0.48, 0.62, 0.26), Vector3(0, 1.2, 0), jacket, vis)
	_box(Vector3(0.5, 0.08, 0.28), Vector3(0, 1.28, 0), accent, vis)
	var head: MeshInstance3D = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.26
	head.mesh = sm
	head.material_override = skin
	head.position = Vector3(0, 1.66, 0)
	vis.add_child(head)
	_box(Vector3(0.27, 0.09, 0.28), Vector3(0, 1.74, -0.0), jacket, vis)   # cap
	for sx in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(sx * 0.13, 0.86, 0)
		vis.add_child(leg)
		_box(Vector3(0.17, 0.82, 0.2), Vector3(0, -0.4, 0), pants, leg)
		_box(Vector3(0.18, 0.08, 0.3), Vector3(0, -0.8, -0.04), shoe, leg)
		legs.append(leg)
		var arm := Node3D.new()
		arm.position = Vector3(sx * 0.31, 1.46, 0)
		vis.add_child(arm)
		_box(Vector3(0.12, 0.58, 0.14), Vector3(0, -0.28, 0), jacket, arm)
		_box(Vector3(0.1, 0.1, 0.12), Vector3(0, -0.6, 0), skin, arm)
		arms.append(arm)

func place(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation.y = yaw
	vis.rotation.y = 0.0
	velocity = Vector3.ZERO

func _physics_process(dt: float) -> void:
	if not enabled:
		return
	var dirv := Vector3.ZERO
	if move_input.length() > 0.1:
		var f := Vector3(-sin(cam_yaw + PI), 0, -cos(cam_yaw + PI))
		# camera looks along -dir (camera sits behind), forward = away from camera
		f = Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
		var r := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
		dirv = (f * move_input.y + r * move_input.x)
		if dirv.length() > 1.0:
			dirv = dirv.normalized()
	var sp: float = RUN if want_sprint else WALK
	var tv: Vector3 = dirv * sp
	var accel: float = 14.0 if is_on_floor() else 4.0
	velocity.x = move_toward(velocity.x, tv.x, accel * dt)
	velocity.z = move_toward(velocity.z, tv.z, accel * dt)
	if is_on_floor():
		if want_jump:
			velocity.y = JUMP
	else:
		velocity.y -= 16.0 * dt
	want_jump = false
	move_and_slide()
	var hs: float = Vector2(velocity.x, velocity.z).length()
	if hs > 0.3:
		var ty: float = atan2(-velocity.x, -velocity.z)
		vis.rotation.y = lerp_angle(vis.rotation.y, ty - rotation.y, clampf(dt * 12.0, 0.0, 1.0))
	phase += hs * dt * 2.3
	var amp: float = clampf(hs / RUN, 0.0, 1.0) * 0.9
	for i in legs.size():
		var s: float = 1.0 if i == 0 else -1.0
		(legs[i] as Node3D).rotation.x = sin(phase) * amp * s
		(arms[i] as Node3D).rotation.x = -sin(phase) * amp * s * 0.8
	if global_position.y < -3.0:
		sink_time += dt
	else:
		sink_time = 0.0
