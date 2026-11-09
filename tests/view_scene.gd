extends Node
# usage: godot --path . res://tests/view_scene.tscn -- <res path> <out name> <cx> <cy> <cz> <tx> <ty> <tz> [fov]
var frames := 0
func _ready() -> void:
	var ua := OS.get_cmdline_user_args()
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.7, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.9)
	env.ambient_light_energy = 0.8
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	add_child(sun)
	var n: Node3D = (load(ua[0]) as PackedScene).instantiate()
	add_child(n)
	var cam := Camera3D.new()
	cam.fov = float(ua[8]) if ua.size() > 8 else 50.0
	cam.far = 2000.0
	add_child(cam)
	cam.position = Vector3(float(ua[2]), float(ua[3]), float(ua[4]))
	cam.look_at(Vector3(float(ua[5]), float(ua[6]), float(ua[7])))
	cam.current = true
func _process(_d: float) -> void:
	frames += 1
	if frames == 12:
		var ua := OS.get_cmdline_user_args()
		get_viewport().get_texture().get_image().save_png("/tmp/gd/vs_%s.png" % ua[1])
		get_tree().quit()
