extends Node
# renders every assets/buildings/pack/*.glb in a row from the front (+Z) side: godot ... res://tests/bld_sheet.tscn -- <out name> [yaw_deg]
var frames := 0
func _ready() -> void:
	var ua := OS.get_cmdline_user_args()
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.6, 0.75, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.9)
	env.ambient_light_energy = 0.9
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	add_child(sun)
	var dir := DirAccess.open("res://assets/buildings/pack")
	var names: Array = []
	for f in dir.get_files():
		if f.ends_with(".glb"):
			names.append(f)
	names.sort()
	var x := 0.0
	for f in names:
		var n: Node3D = (load("res://assets/buildings/pack/" + f) as PackedScene).instantiate()
		var bb := AABB()
		var first := true
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var a: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).mesh.get_aabb()
			bb = a if first else bb.merge(a)
			first = false
		n.position = Vector3(x + bb.size.x * 0.5, 0, 0)
		add_child(n)
		var l := Label3D.new()
		l.text = f.replace(".glb", "")
		l.position = Vector3(x + bb.size.x * 0.5, -1.2, 12)
		l.pixel_size = 0.03
		add_child(l)
		x += bb.size.x + 3.0
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(x + 40, 60)
	fl.mesh = pm; fl.position = Vector3(x * 0.5, -0.02, 0)
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.3, 0.32, 0.3)
	fl.material_override = m
	add_child(fl)
	var cam := Camera3D.new()
	cam.fov = 40.0; cam.far = 1000.0
	add_child(cam)
	var yaw: float = deg_to_rad(float(ua[1])) if ua.size() > 1 else 0.0
	cam.position = Vector3(x * 0.5 + sin(yaw) * x * 0.55, 22, cos(yaw) * x * 0.55)
	cam.look_at(Vector3(x * 0.5, 10, 0))
	cam.current = true
func _process(_d: float) -> void:
	frames += 1
	if frames == 15:
		get_viewport().get_texture().get_image().save_png("/tmp/gd/bs_%s.png" % OS.get_cmdline_user_args()[0])
		get_tree().quit()
