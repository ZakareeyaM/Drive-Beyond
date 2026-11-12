extends Node
# usage: godot --path . res://tests/top_view.tscn --resolution 1200x1200 -- <res path> <out name> <cx> <cz> <size_m> [scale] [ymin_cut]
# orthographic top-down render (north = -Z up the image) of a GLB/scene, for laying out tracks / checking maps
var frames := 0
func _ready() -> void:
	var ua := OS.get_cmdline_user_args()
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.7, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	we.environment = env
	add_child(we)
	var n: Node3D = (load(ua[0]) as PackedScene).instantiate()
	if ua.size() > 5:
		n.scale = Vector3.ONE * float(ua[5])
	add_child(n)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = float(ua[4])
	cam.far = 2000.0
	add_child(cam)
	cam.position = Vector3(float(ua[2]), 800.0, float(ua[3]))
	cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.current = true
func _process(_d: float) -> void:
	frames += 1
	if frames == 14:
		var ua := OS.get_cmdline_user_args()
		get_viewport().get_texture().get_image().save_png("/tmp/gd/tv_%s.png" % ua[1])
		get_tree().quit()
