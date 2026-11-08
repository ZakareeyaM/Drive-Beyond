extends Node
# usage: godot --path . tests/glb_view.tscn -- <glb path> <yaw_deg> <name> [hide_wheels 0/1]
var frames := 0
func _ready() -> void:
	var ua := OS.get_cmdline_user_args()
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.62, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.9)
	env.ambient_light_energy = 0.9
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	add_child(sun)
	var ps: PackedScene = load(ua[0])
	var n: Node3D = ps.instantiate()
	add_child(n)
	var cam := Camera3D.new()
	cam.fov = 38.0
	add_child(cam)
	var a: float = deg_to_rad(float(ua[1]))
	cam.position = Vector3(0.5 + sin(a) * 3.6, 1.2, 0.5 + cos(a) * 3.6)
	cam.look_at(Vector3(0.5, 0.3, 0.5))
	cam.current = true
func _process(_d: float) -> void:
	frames += 1
	if frames == 15:
		var ua := OS.get_cmdline_user_args()
		get_viewport().get_texture().get_image().save_png("/tmp/gd/gv_%s.png" % ua[2])
		get_tree().quit()
