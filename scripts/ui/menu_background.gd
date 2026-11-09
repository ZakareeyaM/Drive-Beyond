class_name MenuBackground
extends Node3D
## Dedicated main-menu scene: sky + one ocean quad + a static camera.  Completely separate from the gameplay world
## (no chunks, no physics bodies, no vehicles), so the menu opens instantly and costs almost nothing to render.
## Composition follows the reference: horizon about a quarter of the way down the screen, ocean below.

const HORIZON_FRAC := 0.27     # horizon height as a fraction of the screen from the top
const FOV := 50.0

var cam: Camera3D
var env: Environment

func _ready() -> void:
	name = "MenuBackground"
	# sky
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.50, 0.84)
	sky_mat.sky_horizon_color = Color(0.68, 0.78, 0.90)
	sky_mat.ground_horizon_color = Color(0.64, 0.74, 0.86)
	sky_mat.ground_bottom_color = Color(0.30, 0.50, 0.62)
	sky_mat.sky_curve = 0.18
	sky_mat.sun_angle_max = 0.0
	sky_mat.sun_curve = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.8, 0.95)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(_make_camera())
	# ocean: a single flat quad, big enough to reach the horizon
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	water.mesh = pm
	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/menu_water.gdshader")
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

func _make_camera() -> Camera3D:
	cam = Camera3D.new()
	cam.environment = env
	cam.fov = FOV
	cam.near = 0.5
	cam.far = 5000.0
	cam.position = Vector3(0, 2.6, 0)
	# pitch so that the horizon lands at HORIZON_FRAC of the screen height
	var off: float = (0.5 - HORIZON_FRAC) * 2.0 * tan(deg_to_rad(FOV * 0.5))
	cam.rotation.x = -atan(off)
	return cam

func activate() -> void:
	cam.make_current()
