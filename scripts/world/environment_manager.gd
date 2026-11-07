class_name EnvironmentManager
extends Node3D
## Time of day, sky, sun, fog, six weather states with smooth transitions,
## rain, lightning/thunder, wet roads and the ocean plane.

signal weather_changed(name: String)
signal thunder(delay: float)

const WEATHERS := ["clear", "cloudy", "light_rain", "heavy_rain", "fog", "storm"]
const WEATHER_LABEL := {"clear": "Clear", "cloudy": "Cloudy", "light_rain": "Light Rain", "heavy_rain": "Heavy Rain", "fog": "Fog", "storm": "Thunderstorm"}
const WPARAM := {
	"clear":      {"cloud": 0.18, "rain": 0.0, "fog": 0.0,  "wet": 0.0, "dark": 0.0,  "grip": 1.0},
	"cloudy":     {"cloud": 0.62, "rain": 0.0, "fog": 0.2,  "wet": 0.0, "dark": 0.18, "grip": 1.0},
	"light_rain": {"cloud": 0.8,  "rain": 0.35, "fog": 0.4, "wet": 0.7, "dark": 0.3,  "grip": 0.84},
	"heavy_rain": {"cloud": 0.95, "rain": 1.0, "fog": 0.7,  "wet": 1.0, "dark": 0.48, "grip": 0.7},
	"fog":        {"cloud": 0.5,  "rain": 0.0, "fog": 2.8,  "wet": 0.25, "dark": 0.2, "grip": 0.92},
	"storm":      {"cloud": 1.0,  "rain": 1.0, "fog": 0.9,  "wet": 1.0, "dark": 0.62, "grip": 0.66},
}
const KEYS := [
	[0.0,  Color(0.01, 0.02, 0.07), Color(0.05, 0.07, 0.17), Color(0.5, 0.6, 1.0), 0.0, Color(0.16, 0.2, 0.36), 0.65, Color(0.04, 0.05, 0.1)],
	[5.0,  Color(0.03, 0.05, 0.16), Color(0.22, 0.18, 0.3), Color(0.6, 0.5, 0.8), 0.0, Color(0.18, 0.2, 0.34), 0.65, Color(0.12, 0.1, 0.18)],
	[6.2,  Color(0.2, 0.3, 0.6), Color(1.0, 0.56, 0.32), Color(1.0, 0.6, 0.35), 0.85, Color(0.55, 0.45, 0.5), 0.7, Color(0.9, 0.6, 0.46)],
	[8.0,  Color(0.15, 0.36, 0.76), Color(0.66, 0.78, 0.95), Color(1.0, 0.93, 0.8), 1.15, Color(0.6, 0.68, 0.8), 0.85, Color(0.7, 0.8, 0.92)],
	[12.0, Color(0.1, 0.3, 0.76), Color(0.6, 0.76, 0.96), Color(1.0, 0.97, 0.9), 1.35, Color(0.65, 0.72, 0.85), 0.95, Color(0.72, 0.83, 0.95)],
	[16.5, Color(0.14, 0.32, 0.72), Color(0.76, 0.8, 0.9), Color(1.0, 0.9, 0.75), 1.2, Color(0.64, 0.66, 0.78), 0.88, Color(0.76, 0.8, 0.9)],
	[18.0, Color(0.18, 0.2, 0.5), Color(1.0, 0.5, 0.2), Color(1.0, 0.5, 0.25), 1.0, Color(0.6, 0.45, 0.45), 0.72, Color(0.95, 0.55, 0.35)],
	[19.1, Color(0.1, 0.12, 0.36), Color(0.85, 0.34, 0.36), Color(0.9, 0.35, 0.25), 0.4, Color(0.35, 0.3, 0.46), 0.62, Color(0.5, 0.3, 0.36)],
	[20.6, Color(0.03, 0.04, 0.16), Color(0.25, 0.15, 0.3), Color(0.5, 0.5, 0.9), 0.0, Color(0.17, 0.19, 0.34), 0.62, Color(0.1, 0.08, 0.16)],
	[24.0, Color(0.01, 0.02, 0.07), Color(0.05, 0.07, 0.17), Color(0.5, 0.6, 1.0), 0.0, Color(0.16, 0.2, 0.36), 0.65, Color(0.04, 0.05, 0.1)],
]

var hour: float = 17.2
var day_speed: float = 1.0 / 60.0      # game hours per real second (24 min / day)
var weather: String = "clear"
var target_weather: String = "clear"
var blend: float = 1.0
var cur: Dictionary = {"cloud": 0.18, "rain": 0.0, "fog": 0.0, "wet": 0.0, "dark": 0.0, "grip": 1.0}
var from_p: Dictionary = {}
var weather_timer: float = 240.0
var auto_weather: bool = true
var night_amt: float = 0.0
var wet_amt: float = 0.0

var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var water: MeshInstance3D
var rain: CPUParticles3D
var cam: Camera3D
var flash: float = 0.0
var next_bolt: float = 6.0
var view_dist: float = 600.0
var _t_acc: float = 0.0

func _ready() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	env.glow_enabled = false
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 160.0
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	# ocean
	water = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(5200, 5200)
	pm.subdivide_width = 64
	pm.subdivide_depth = 64
	water.mesh = pm
	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/water.gdshader")
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	# rain
	rain = CPUParticles3D.new()
	rain.amount = 700
	rain.lifetime = 0.8
	rain.preprocess = 0.8
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(22, 0.2, 22)
	rain.direction = Vector3(0.12, -1, 0.05)
	rain.spread = 3.0
	rain.initial_velocity_min = 28.0
	rain.initial_velocity_max = 36.0
	rain.gravity = Vector3.ZERO
	rain.local_coords = false
	var qm := QuadMesh.new()
	qm.size = Vector2(0.025, 0.9)
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(0.75, 0.82, 0.95, 0.35)
	rmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	rmat.billboard_keep_scale = true
	qm.material = rmat
	rain.mesh = qm
	rain.emitting = false
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)
	hour = Game.time_of_day
	set_weather(Game.weather_state, true)
	Game.settings_changed.connect(_apply_quality)
	_apply_quality()
	_update(0.0)

func _apply_quality() -> void:
	var s: Dictionary = Game.settings
	sun.shadow_enabled = bool(s["shadows"])
	var q: String = String(s["quality"])
	sun.directional_shadow_max_distance = 90.0 if q == "Low" else (140.0 if q == "Medium" else (190.0 if q == "High" else 260.0))
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if q in ["Low", "Medium"] else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	env.glow_enabled = q in ["High", "Ultra"]
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	view_dist = float(int(s["view_distance"])) * WorldGen.CHUNK
	rain.amount = int(700 * (1.0 if q != "Low" else 0.45))

func set_weather(w: String, instant: bool = false) -> void:
	if not WPARAM.has(w):
		return
	target_weather = w
	from_p = cur.duplicate()
	blend = 1.0 if instant else 0.0
	if instant:
		cur = (WPARAM[w] as Dictionary).duplicate()
		weather = w
	else:
		weather_changed.emit(w)
	Game.weather_state = w

func weather_label() -> String:
	return String(WEATHER_LABEL.get(target_weather, "Clear"))

func hour_string() -> String:
	var h: int = int(hour) % 24
	var m: int = int((hour - floor(hour)) * 60.0)
	return "%02d:%02d" % [h, m]

func is_night() -> bool:
	return night_amt > 0.55

func _sample(h: float) -> Dictionary:
	var a: Array = KEYS[0]
	var b: Array = KEYS[KEYS.size() - 1]
	for i in range(1, KEYS.size()):
		if h <= KEYS[i][0]:
			a = KEYS[i - 1]
			b = KEYS[i]
			break
	var t: float = (h - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
	return {"zen": (a[1] as Color).lerp(b[1], t), "hor": (a[2] as Color).lerp(b[2], t), "sun": (a[3] as Color).lerp(b[3], t),
		"sene": lerpf(a[4], b[4], t), "amb": (a[5] as Color).lerp(b[5], t), "aene": lerpf(a[6], b[6], t), "fog": (a[7] as Color).lerp(b[7], t)}

func _process(delta: float) -> void:
	hour = fposmod(hour + delta * day_speed, 24.0)
	Game.time_of_day = hour
	# weather blend
	if blend < 1.0:
		blend = minf(1.0, blend + delta / 18.0)
		var tp: Dictionary = WPARAM[target_weather]
		for k in tp:
			cur[k] = lerpf(from_p.get(k, tp[k]), tp[k], blend)
		if blend >= 1.0:
			weather = target_weather
	elif auto_weather:
		weather_timer -= delta
		if weather_timer <= 0.0:
			weather_timer = randf_range(200.0, 420.0)
			var pool: Array = ["clear", "clear", "cloudy", "cloudy", "light_rain", "heavy_rain", "fog", "storm"]
			var pick: String = pool[randi() % pool.size()]
			if pick == target_weather:
				pick = "clear"
			set_weather(pick)
	_update(delta)

func _update(delta: float) -> void:
	var k: Dictionary = _sample(hour)
	var dark: float = float(cur["dark"])
	var rain_amt: float = float(cur["rain"])
	# night factor for shaders (street lights, windows, neon)
	var target_night: float = 1.0 - smoothstep(4.8, 6.8, hour) + smoothstep(18.8, 20.8, hour)
	night_amt = clampf(target_night + dark * 0.18, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("night", night_amt)
	wet_amt = lerpf(wet_amt, float(cur["wet"]), clampf(delta * 0.15 + 0.0001, 0.0, 1.0)) if delta > 0.0 else float(cur["wet"])
	RenderingServer.global_shader_parameter_set("wet", wet_amt)
	Vehicle.weather_grip = lerpf(1.0, float(cur["grip"]), clampf(wet_amt * 1.2 + 0.0, 0.0, 1.0)) if wet_amt > 0.05 else 1.0
	var grey: Color = Color(0.5, 0.52, 0.56)
	var zen: Color = (k["zen"] as Color).lerp(grey * (0.25 + 0.75 * (1.0 - night_amt)), dark)
	var hor: Color = (k["hor"] as Color).lerp(grey * (0.3 + 0.7 * (1.0 - night_amt)), dark * 0.9)
	var fogc: Color = (k["fog"] as Color).lerp(grey * (0.25 + 0.75 * (1.0 - night_amt)), dark * 0.9)
	# sun / moon position
	var elev: float = 0.0
	var az: float = 0.0
	var is_day: bool = hour >= 5.5 and hour <= 18.7
	if is_day:
		var f: float = clampf((hour - 5.5) / 13.2, 0.0, 1.0)
		elev = sin(f * PI) * 62.0 + 2.0
		az = lerpf(90.0, 270.0, f)
	else:
		var hh: float = hour if hour > 12.0 else hour + 24.0
		var f2: float = clampf((hh - 18.7) / 10.8, 0.0, 1.0)
		elev = sin(f2 * PI) * 50.0 + 4.0
		az = lerpf(100.0, 260.0, f2)
	var el: float = deg_to_rad(elev)
	var azr: float = deg_to_rad(az)
	var sun_dir := Vector3(cos(el) * sin(azr), sin(el), -cos(el) * cos(azr)).normalized()
	sun.global_transform = Transform3D(Basis.looking_at(-sun_dir, Vector3.UP), Vector3.ZERO)
	var sun_e: float = float(k["sene"]) * (1.0 - dark * 0.85)
	sun.light_color = k["sun"]
	if not is_day or sun_e < 0.05:
		sun.light_color = Color(0.55, 0.65, 1.0)
		sun_e = 0.22 * (1.0 - dark * 0.7)
	sun.light_energy = sun_e + flash * 2.5
	sun.shadow_enabled = bool(Game.settings["shadows"]) and sun_e > 0.1
	var real_sun: Vector3 = Vector3(cos(deg_to_rad(sin(clampf((hour - 5.5) / 13.2, 0.0, 1.0) * PI) * 62.0 + 2.0)) * sin(deg_to_rad(lerpf(90.0, 270.0, clampf((hour - 5.5) / 13.2, 0.0, 1.0)))), sin(deg_to_rad(sin(clampf((hour - 5.5) / 13.2, 0.0, 1.0) * PI) * 62.0 + 2.0)), -cos(deg_to_rad(sin(clampf((hour - 5.5) / 13.2, 0.0, 1.0) * PI) * 62.0 + 2.0)) * cos(deg_to_rad(lerpf(90.0, 270.0, clampf((hour - 5.5) / 13.2, 0.0, 1.0)))))
	var vis_sun: Vector3 = real_sun if is_day else Vector3(0, -0.5, -1)
	sky_mat.set_shader_parameter("sun_dir", vis_sun.normalized())
	sky_mat.set_shader_parameter("zenith", zen + Color(flash, flash, flash) * 0.6)
	sky_mat.set_shader_parameter("horizon", hor + Color(flash, flash, flash) * 0.5)
	sky_mat.set_shader_parameter("ground", fogc * 0.6)
	sky_mat.set_shader_parameter("sun_color", k["sun"])
	sky_mat.set_shader_parameter("stars", clampf(night_amt * (1.0 - dark) * 1.1, 0.0, 1.0))
	sky_mat.set_shader_parameter("cloud_cover", float(cur["cloud"]))
	sky_mat.set_shader_parameter("cloud_color", Color(1, 1, 1).lerp(fogc, 0.5) * (0.35 + 0.65 * (1.0 - night_amt)))
	sky_mat.set_shader_parameter("storm", clampf((dark - 0.3) * 2.5, 0.0, 1.0))
	env.ambient_light_color = (k["amb"] as Color).lerp(grey * 0.6, dark * 0.5)
	env.ambient_light_energy = float(k["aene"]) * (1.0 - 0.25 * dark) + flash * 1.2
	env.fog_light_color = fogc
	var base_d: float = 2.4 / maxf(view_dist, 200.0)
	env.fog_density = base_d * (1.0 + float(cur["fog"]) * 2.2) * (0.75 if night_amt > 0.5 else 1.0)
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = 0.0
	if cam == null or not is_instance_valid(cam):
		cam = get_viewport().get_camera_3d()
	if cam:
		water.global_position = Vector3(snappedf(cam.global_position.x, 80.0), 0.0, snappedf(cam.global_position.z, 80.0))
		rain.global_position = cam.global_position + Vector3(0, 14, 0)
		rain.emitting = rain_amt > 0.05
		rain.speed_scale = 1.0
	# lightning
	if target_weather == "storm" and blend > 0.4:
		next_bolt -= delta
		if next_bolt <= 0.0:
			next_bolt = randf_range(5.0, 16.0)
			flash = 1.0
			thunder.emit(randf_range(0.4, 3.2))
	flash = maxf(0.0, flash - delta * 3.5)
	if flash > 0.0 and fmod(flash * 10.0, 1.0) < 0.3:
		flash *= 0.9

func sun_direction() -> Vector3:
	return -sun.global_transform.basis.z * -1.0
