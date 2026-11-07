class_name Showroom
extends SubViewportContainer
## Isolated 3D garage showroom (own World3D) with a turntable car and orbit camera.

var vp: SubViewport
var cam: Camera3D
var pivot: Node3D
var car_root: Node3D = null
var yaw: float = 0.6
var pitch: float = 0.18
var dist: float = 7.2
var idle: float = 0.0
var dragging: bool = false
var cur_vid: String = ""
var head_mat: StandardMaterial3D = null
var lights_on: bool = true
var target_center: Vector3 = Vector3(0, 0.7, 0)

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X if String(Game.settings.get("quality", "Medium")) != "Low" else Viewport.MSAA_DISABLED
	vp.handle_input_locally = false
	add_child(vp)
	_build_scene()

func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.015, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.26, 0.35)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.03, 0.02, 0.04)
	env.fog_density = 0.02
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	# floor
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.03, 0.03, 0.04)
	fm.roughness = 0.35
	fm.metallic = 0.4
	floor_mi.material_override = fm
	vp.add_child(floor_mi)
	# turntable
	var tt := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.6
	cm.bottom_radius = 3.7
	cm.height = 0.1
	tt.mesh = cm
	tt.position.y = -0.05
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.07, 0.07, 0.09)
	tm.roughness = 0.5
	tm.metallic = 0.3
	tt.material_override = tm
	vp.add_child(tt)
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 3.62
	rm.outer_radius = 3.78
	ring.mesh = rm
	ring.position.y = 0.02
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = UIKit.RED
	rmat.emission_enabled = true
	rmat.emission = UIKit.RED
	rmat.emission_energy_multiplier = 3.0
	ring.material_override = rmat
	vp.add_child(ring)
	# back wall + sign
	var wall := MeshInstance3D.new()
	var wmesh := BoxMesh.new()
	wmesh.size = Vector3(40, 12, 0.5)
	wall.mesh = wmesh
	wall.position = Vector3(0, 6, -9)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.04, 0.04, 0.055)
	wmat.roughness = 0.8
	wall.material_override = wmat
	vp.add_child(wall)
	var sign := Label3D.new()
	sign.text = "DRIVE BEYOND"
	sign.font_size = 140
	sign.pixel_size = 0.018
	sign.modulate = Color(1.0, 0.1, 0.15)
	sign.shaded = false
	sign.position = Vector3(0, 5.2, -8.6)
	vp.add_child(sign)
	for x in [-14.0, 14.0]:
		var bar := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(0.2, 9, 0.2)
		bar.mesh = bb
		bar.position = Vector3(x, 4.5, -8.5)
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.1, 0.3, 1.0) if x < 0.0 else UIKit.RED
		bm.emission_enabled = true
		bm.emission = bm.albedo_color
		bm.emission_energy_multiplier = 3.0
		bar.material_override = bm
		vp.add_child(bar)
	# lights
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, 35, 0)
	key.light_energy = 0.9
	key.light_color = Color(1.0, 0.95, 0.9)
	key.shadow_enabled = false
	vp.add_child(key)
	for sp in [[Vector3(-6, 5, 5), Color(1.0, 0.15, 0.2)], [Vector3(6, 5, 4), Color(0.25, 0.45, 1.0)], [Vector3(0, 7, -3), Color(1, 1, 1)]]:
		var ol := OmniLight3D.new()
		ol.position = sp[0]
		ol.light_color = sp[1]
		ol.light_energy = 3.0
		ol.omni_range = 16.0
		vp.add_child(ol)
	pivot = Node3D.new()
	vp.add_child(pivot)
	cam = Camera3D.new()
	cam.fov = 45.0
	cam.h_offset = -0.5
	cam.current = true
	vp.add_child(cam)
	_update_cam()

func show_car(vid: String, custom: Dictionary, upg: Dictionary = {}) -> void:
	cur_vid = vid
	if car_root and is_instance_valid(car_root):
		car_root.queue_free()
	var spec: Dictionary = Data.vehicle(vid)
	var c: Dictionary = custom.duplicate(true)
	c["exhaust_level"] = int(upg.get("exhaust", 0))
	var m: Dictionary = CarBuilder.build(vid, c)
	var root: Node3D = m["root"]
	pivot.add_child(root)
	for fz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			var wv: MeshInstance3D = CarBuilder.build_wheel(vid, c)
			wv.position = Vector3(sx * float(spec["track"]) * 0.5, float(spec["wr"]), fz * float(spec["wb"]) * 0.5)
			root.add_child(wv)
	car_root = root
	head_mat = m["head_mat"]
	head_mat.emission_energy_multiplier = 3.0 if lights_on else 0.35
	dist = 9.6 + float(spec["L"]) * 0.7
	target_center = Vector3(0, float(spec["roof"]) * 0.45, 0)
	_update_cam()

func _update_cam() -> void:
	if cam == null:
		return
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.position = target_center + off
	cam.look_at(target_center, Vector3.UP)

func _process(delta: float) -> void:
	if not visible:
		return
	idle += delta
	if not dragging and idle > 2.5:
		yaw += delta * 0.35
	_update_cam()

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb: InputEventMouseButton = ev
		if mb.button_index == MOUSE_BUTTON_LEFT:
			dragging = mb.pressed
			idle = 0.0
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = maxf(3.5, dist - 0.4)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = minf(14.0, dist + 0.4)
	elif ev is InputEventMouseMotion and dragging:
		var mm: InputEventMouseMotion = ev
		yaw -= mm.relative.x * 0.008
		pitch = clampf(pitch + mm.relative.y * 0.005, -0.05, 0.9)
		idle = 0.0
