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
	# hour, zenith, horizon, sun colour, sun energy, ambient colour, ambient energy, fog colour
	[0.0,  Color(0.0, 0.0, 0.006), Color(0.01, 0.012, 0.03), Color(0.55, 0.65, 1.0), 0.0, Color(0.12, 0.14, 0.27), 0.6, Color(0.008, 0.01, 0.022)],
	[4.9,  Color(0.0, 0.0, 0.006), Color(0.01, 0.012, 0.03), Color(0.55, 0.65, 1.0), 0.0, Color(0.12, 0.14, 0.27), 0.6, Color(0.008, 0.01, 0.022)],
	[5.7,  Color(0.04, 0.06, 0.2), Color(0.55, 0.35, 0.3), Color(1.0, 0.6, 0.35), 0.5, Color(0.35, 0.35, 0.5), 0.6, Color(0.4, 0.3, 0.3)],
	[6.7,  Color(0.18, 0.38, 0.8), Color(0.85, 0.76, 0.7), Color(1.0, 0.86, 0.66), 1.0, Color(0.55, 0.62, 0.8), 0.8, Color(0.7, 0.76, 0.86)],
	[8.5,  Color(0.1, 0.32, 0.82), Color(0.6, 0.78, 0.97), Color(1.0, 0.95, 0.85), 1.3, Color(0.6, 0.68, 0.85), 0.95, Color(0.68, 0.8, 0.95)],
	[12.0, Color(0.08, 0.28, 0.85), Color(0.55, 0.75, 0.98), Color(1.0, 0.98, 0.92), 1.45, Color(0.62, 0.7, 0.88), 1.0, Color(0.68, 0.8, 0.96)],
	[16.3, Color(0.1, 0.3, 0.8), Color(0.62, 0.76, 0.95), Color(1.0, 0.93, 0.8), 1.3, Color(0.6, 0.66, 0.82), 0.95, Color(0.7, 0.78, 0.92)],
	[17.8, Color(0.14, 0.25, 0.6), Color(1.0, 0.62, 0.35), Color(1.0, 0.55, 0.3), 1.0, Color(0.55, 0.45, 0.5), 0.75, Color(0.9, 0.6, 0.45)],
	[18.6, Color(0.05, 0.06, 0.2), Color(0.6, 0.25, 0.25), Color(0.9, 0.35, 0.25), 0.3, Color(0.25, 0.22, 0.35), 0.55, Color(0.3, 0.18, 0.2)],
	[19.5, Color(0.0, 0.0, 0.006), Color(0.01, 0.012, 0.03), Color(0.55, 0.65, 1.0), 0.0, Color(0.12, 0.14, 0.27), 0.6, Color(0.008, 0.01, 0.022)],
	[24.0, Color(0.0, 0.0, 0.006), Color(0.01, 0.012, 0.03), Color(0.55, 0.65, 1.0), 0.0, Color(0.12, 0.14, 0.27), 0.6, Color(0.008, 0.01, 0.022)],
]

var hour: float = 9.0
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
	var target_night: float = 1.0 - smoothstep(5.0, 6.6, hour) + smoothstep(18.2, 19.6, hour)
	night_amt = clampf(target_night + dark * 0.18, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("night", night_amt)
	wet_amt = lerpf(wet_amt, float(cur["wet"]), clampf(delta * 0.15 + 0.0001, 0.0, 1.0)) if delta > 0.0 else float(cur["wet"])
	RenderingServer.global_shader_parameter_set("wet", wet_amt)
	Vehicle.weather_grip = lerpf(1.0, float(cur["grip"]), clampf(wet_amt * 1.2 + 0.0, 0.0, 1.0)) if wet_amt > 0.05 else 1.0
	var grey: Color = Color(0.5, 0.52, 0.56)
	var zen: Color = (k["zen"] as Color).lerp(grey * (0.25 + 0.75 * (1.0 - night_amt)), dark)
	var hor: Color = (k["hor"] as Color).lerp(grey * (0.3 + 0.7 * (1.0 - night_amt)), dark * 0.9)
	var fogc: Color = (k["fog"] as Color).lerp(grey * (0.25 + 0.75 * (1.0 - night_amt)), dark * 0.9)
	# sun (06:00-18:00) and moon (18:00-06:00) travel east -> west across the sky
	var sun_dir: Vector3 = _arc_dir(hour, 6.0, 70.0)
	var moon_hour: float = hour if hour >= 12.0 else hour + 24.0
	var moon_dir: Vector3 = _arc_dir(moon_hour, 18.0, 62.0)
	var sun_up: float = smoothstep(-0.02, 0.16, sun_dir.y)
	var moon_up: float = smoothstep(-0.02, 0.16, moon_dir.y)
	var use_sun: bool = sun_dir.y > moon_dir.y
	var ldir: Vector3 = sun_dir if use_sun else moon_dir
	sun.global_transform = Transform3D(Basis.looking_at(-ldir, Vector3.UP), Vector3.ZERO)
	var sun_e: float = float(k["sene"]) * (1.0 - dark * 0.85) * maxf(sun_up, 0.15 if sun_dir.y > 0.0 else 0.0)
	sun.light_color = k["sun"]
	if not use_sun or sun_e < 0.05:
		sun.light_color = Color(0.62, 0.72, 1.0)
		sun_e = 0.42 * moon_up * (1.0 - dark * 0.7)
	sun.light_energy = sun_e + flash * 2.5
	sun.shadow_enabled = bool(Game.settings["shadows"]) and sun_e > 0.1
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("moon_dir", moon_dir)
	sky_mat.set_shader_parameter("moon_amt", moon_up * clampf(1.0 - dark * 1.2, 0.0, 1.0) * night_amt)
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
	env.fog_density = base_d * (1.0 + float(cur["fog"]) * 2.2) * (0.5 if night_amt < 0.5 and dark < 0.1 else 0.8)
	env.fog_sky_affect = 0.12 if night_amt < 0.5 else 0.0
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

func _arc_dir(h: float, h0: float, max_elev: float) -> Vector3:
	var f: float = (h - h0) / 12.0
	var elev: float = sin(f * PI) * max_elev
	var az: float = lerpf(90.0, 270.0, clampf(f, -0.2, 1.2))
	var el: float = deg_to_rad(elev)
	var azr: float = deg_to_rad(az)
	return Vector3(cos(el) * sin(azr), sin(el), -cos(el) * cos(azr)).normalized()

func sun_direction() -> Vector3:
	return -sun.global_transform.basis.z * -1.0
