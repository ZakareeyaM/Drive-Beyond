extends Node
var frames := 0
var cam: Camera3D
var idx := 0
func _ready() -> void:
	var root = get_tree().root
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.6, 0.72)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -40, 0)
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(200, 200)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.25, 0.25, 0.27)
	floor_mi.material_override = fm
	add_child(floor_mi)
	var ids: Array = Data.vehicle_ids()
	for i in ids.size():
		var vid: String = ids[i]
		var custom: Dictionary = Data.default_custom(vid)
		var b: Dictionary = CarBuilder.build(vid, custom)
		var n: Node3D = b["root"]
		n.position = Vector3((i % 5) * 7.0 - 14.0, 0, (i / 5) * 8.0)
		n.rotation.y = deg_to_rad(-35)
		add_child(n)
		var v: Dictionary = Data.vehicle(vid)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var w := CarBuilder.build_wheel(vid, custom)
				w.position = Vector3(sx * float(v["track"]) * 0.5, float(v["wr"]), sz * float(v["wb"]) * 0.5)
				n.add_child(w)
	RenderingServer.global_shader_parameter_set("night", 0.0)
	RenderingServer.global_shader_parameter_set("wet", 0.0)
	cam = Camera3D.new()
	var ua := OS.get_cmdline_user_args()
	cam.position = Vector3(0, 9, 22)
	var look := Vector3(0, 0.5, 3)
	if ua.size() >= 1:
		var k: int = int(ua[0])
		var c: Vector3 = Vector3((k % 5) * 7.0 - 14.0, 0.6, (k / 5) * 8.0)
		cam.position = c + Vector3(5.2, 1.9, 5.2)
		look = c
	add_child(cam)
	cam.look_at(look)
	cam.current = true
func _process(_d: float) -> void:
	frames += 1
	if frames == 30:
		get_viewport().get_texture().get_image().save_png("/tmp/gd/car_%s.png" % (OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "all"))
		get_tree().quit()
