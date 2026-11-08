extends Node
# usage: godot --path . tests/car_close.tscn -- <vid> <yaw_deg> <name>
var frames := 0
func _ready() -> void:
	var ua := OS.get_cmdline_user_args()
	var vid: String = ua[0]
	var yaw: float = float(ua[1])
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.62, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.68, 0.85)
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(80, 80)
	fl.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.22, 0.22, 0.24)
	fl.material_override = fm
	add_child(fl)
	RenderingServer.global_shader_parameter_set("night", float(ua[3]) if ua.size() > 3 else 0.0)
	RenderingServer.global_shader_parameter_set("wet", 0.0)
	var custom: Dictionary = Data.default_custom(vid)
	var b: Dictionary = CarBuilder.build(vid, custom)
	var n: Node3D = b["root"]
	add_child(n)
	if ua.size() > 3 and float(ua[3]) > 0.5:
		(b["head_mat"] as StandardMaterial3D).emission_energy_multiplier = 3.0
		(b["tail_mat"] as StandardMaterial3D).emission_energy_multiplier = 1.5
	var v: Dictionary = Data.vehicle(vid)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var w := CarBuilder.make_wheel_visual(b, vid, custom, (2 if sz > 0.0 else 0) + (1 if sx > 0.0 else 0))
			w.position = Vector3(sx * float(v["track"]) * 0.5, float(v["wr"]), sz * float(v["wb"]) * 0.5)
			n.add_child(w)
	var cam := Camera3D.new()
	cam.fov = 38.0
	add_child(cam)
	var d: float = 4.2 + float(v["L"]) * 0.55
	var a: float = deg_to_rad(yaw)
	cam.position = Vector3(sin(a) * d, 1.35, cos(a) * d)
	cam.look_at(Vector3(0, 0.75, 0))
	cam.current = true
func _process(_d: float) -> void:
	frames += 1
	if frames == 20:
		var ua := OS.get_cmdline_user_args()
		get_viewport().get_texture().get_image().save_png("/tmp/gd/cc_%s.png" % ua[2])
		get_tree().quit()
