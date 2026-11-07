extends SceneTree
# usage: godot --path . -s tests/visual_test.gd -- x y z yaw pitch outname
var frames := 0
var world: WorldGen
var streamer: TerrainStreamer
var cam: Camera3D
var shots: Array = []
var shot_i := 0
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	world = WorldGen.new()
	world.build_all()
	var assets := WorldAssets.create()
	streamer = TerrainStreamer.new()
	streamer.setup(world, assets)
	streamer.builds_per_frame = 4
	streamer.max_inflight = 4
	streamer.set_radius(3)
	root.add_child(streamer)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
	sm.set_shader_parameter("sun_dir", Vector3(0.3, 0.6, -0.7))
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.65)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.78, 0.88)
	env.fog_density = 0.0012
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.shadow_enabled = false
	root.add_child(sun)
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	water.mesh = pm
	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/water.gdshader")
	water.material_override = wm
	root.add_child(water)
	cam = Camera3D.new()
	cam.far = 2500
	root.add_child(cam)
	cam.current = true
	# shots: [x,y,z, yaw_deg, pitch_deg, name]
	if args.size() >= 6:
		shots.append([float(args[0]), float(args[1]), float(args[2]), float(args[3]), float(args[4]), args[5]])
	else:
		shots = [[0, 40, 60, 0, -20, "city"]]
	RenderingServer.global_shader_parameter_set("night", 0.0)
	RenderingServer.global_shader_parameter_set("wet", 0.0)
	_goto()

func _goto() -> void:
	var s: Array = shots[shot_i]
	cam.position = Vector3(s[0], s[1], s[2])
	cam.rotation_degrees = Vector3(s[4], s[3], 0)
	streamer.focus = cam.position

func _process(delta: float) -> bool:
	frames += 1
	if frames == 150:
		var img := root.get_viewport().get_texture().get_image()
		var s: Array = shots[shot_i]
		img.save_png("/tmp/gd/shot_%s.png" % s[5])
		print("saved ", s[5], " chunks ", streamer.chunks.size(), " fps ", Engine.get_frames_per_second())
		shot_i += 1
		if shot_i >= shots.size():
			quit()
		else:
			frames = 100
			_goto()
	return false
