class_name World
extends Node3D
## Orchestrates the open world: terrain streaming, environment, traffic, the
## player (in a car or on foot), points of interest and the managers that hang
## off them (police, missions, pedestrians, audio).

signal loading_progress(fraction: float, text: String)
signal mode_changed(mode: String)
signal prompt_changed

var gen: WorldGen
var assets: Dictionary
var streamer: TerrainStreamer
var env: EnvironmentManager
var traffic: TrafficManager
var nav: RoadNav
var cam: CameraRig
var police: PoliceManager
var missions: MissionManager
var peds: PedManager
var fauna: FaunaManager
var audio: AudioManager

var player_car: Vehicle = null
var foot: FootPlayer = null
var menu_dummy: Node3D
var mode: String = "menu"          # menu | drive | foot | ui
var ui_open: bool = false
var running: bool = false

var prompt_text: String = ""
var prompt_action: Callable = Callable()
var waypoint: Vector3 = Vector3.ZERO
var has_waypoint: bool = false
var route: PackedVector3Array = PackedVector3Array()
var route_timer: float = 0.0
var pois: Array = []               # {id,type,pos,radius,label}
var collectibles: Array = []       # {id,pos,node}
var beacons: Node3D
var last_road_pos: Vector3 = Vector3.ZERO
var last_road_yaw: float = 0.0
var water_time: float = 0.0
var sync_timer: float = 0.0
var exit_cooldown: float = 0.0
var flip_timer: float = 0.0
var near_poi: Dictionary = {}
var cam_flash: ColorRect = null
var ui_hooks: Dictionary = {}      # name -> Callable (set by main to open screens)
var speed_cam_cd: float = 0.0
var speed_cam_latched: Dictionary = {}
var near_miss_cd: float = 0.0
var session_distance: float = 0.0
var stats_top: float = 0.0
var look_drag: bool = false
var was_night: bool = false

# ---------------------------------------------------------------- setup
func build_world() -> void:
	add_to_group("world")
	gen = WorldGen.new()
	gen.build_all()
	Vehicle.surface_world = gen
	assets = WorldAssets.create()
	nav = RoadNav.new(gen)
	streamer = TerrainStreamer.new()
	streamer.name = "Streamer"
	streamer.setup(gen, assets)
	add_child(streamer)
	_apply_quality()
	Game.settings_changed.connect(_apply_quality)
	env = EnvironmentManager.new()
	env.name = "Env"
	add_child(env)
	cam = CameraRig.new()
	cam.name = "Camera"
	add_child(cam)
	env.cam = cam.cam
	menu_dummy = Node3D.new()
	add_child(menu_dummy)
	beacons = Node3D.new()
	beacons.name = "Beacons"
	add_child(beacons)
	traffic = TrafficManager.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.setup(gen)
	traffic.player = menu_dummy
	audio = AudioManager.new()
	audio.name = "Audio"
	audio.world = self
	add_child(audio)
	_build_boundary()
	_build_pois()

func _apply_quality() -> void:
	if streamer == null:
		return
	streamer.set_radius(clampi(int(Game.settings.get("view_distance", 3)), 2, 5))
	streamer.quality["tree_shadows"] = String(Game.settings.get("quality", "Medium")) in ["High", "Ultra"]

func _build_boundary() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var h: float = WorldGen.HALF
	for d in [Vector3(h + 2, 0, 0), Vector3(-h - 2, 0, 0), Vector3(0, 0, h + 2), Vector3(0, 0, -h - 2)]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var horiz: bool = absf(d.x) > 1.0
		bs.size = Vector3(4, 400, h * 2 + 20) if horiz else Vector3(h * 2 + 20, 400, 4)
		cs.shape = bs
		cs.position = d + Vector3(0, 150, 0)
		body.add_child(cs)
	add_child(body)

func _sign_label(text: String, pos: Vector3, yaw: float, col: Color, size: float = 0.06) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = size
	l.modulate = col
	l.outline_size = 0
	l.shaded = false
	l.double_sided = true
	l.position = pos
	l.rotation.y = yaw
	l.no_depth_test = false
	beacons.add_child(l)
	var lamp := OmniLight3D.new()
	lamp.light_color = col
	lamp.light_energy = 1.4
	lamp.omni_range = 18.0
	lamp.position = pos + Vector3(0, -0.5, 1.5).rotated(Vector3.UP, yaw)
	lamp.shadow_enabled = false
	beacons.add_child(lamp)

func make_beacon(pos: Vector3, col: Color, height: float = 38.0, radius: float = 1.6) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshLib.beam_mesh(radius, height)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/beam.gdshader")
	sm.set_shader_parameter("beam_color", Vector3(col.r, col.g, col.b))
	sm.set_shader_parameter("strength", 0.7)
	mi.material_override = sm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacons.add_child(mi)
	return mi

func _build_pois() -> void:
	var L: Dictionary = gen.landmarks
	pois.clear()
	if L.has("home_garage"):
		pois.append({"id": "home_garage", "type": "garage", "pos": L["home_garage"], "radius": 10.0, "label": "Garage"})
		make_beacon(L["home_garage"], Color(1.0, 0.1, 0.12), 34.0, 1.4)
		var s: Dictionary = _structure("garage")
		if not s.is_empty():
			var sp: Vector3 = s["pos"]
			_sign_label("DRIVE BEYOND\nGARAGE", Vector3(sp.x, sp.y + 8.2, sp.z + float(s["size"].z) * 0.5 + 0.3), 0.0, Color(1.0, 0.12, 0.16))
	if L.has("dealership"):
		pois.append({"id": "dealership", "type": "dealership", "pos": L["dealership"], "radius": 13.0, "label": "Dealership"})
		make_beacon(L["dealership"], Color(0.2, 0.55, 1.0), 34.0, 1.4)
		var s2: Dictionary = _structure("dealership")
		if not s2.is_empty():
			var sp2: Vector3 = s2["pos"]
			_sign_label("MARCUS MOTORS", Vector3(sp2.x, sp2.y + 9.0, sp2.z + float(s2["size"].z) * 0.5 + 0.3), 0.0, Color(0.3, 0.65, 1.0))
	if L.has("station"):
		_build_station(L["station"])
	for k in L:
		if String(k).begins_with("gas_"):
			pois.append({"id": k, "type": "gas", "pos": L[k], "radius": 14.0, "label": "Gas Station"})
			make_beacon(L[k], Color(1.0, 0.8, 0.1), 22.0, 1.0)
			if k in ["gas_airport_road", "gas_commerce", "gas_resort", "gas_speedway_n", "gas_speedway_s"]:
				_build_roadside_pumps(L[k])
	for k in ["lighthouse", "summit", "port", "marlin_bay", "desert_outpost", "ghost_town", "circuit", "marina", "pinecrest", "beach", "stadium", "rooftop_parking", "tunnel", "eastwood", "industrial", "pine_ridge", "farm", "city_center", "north_pass", "airport", "business_district", "resort_district"]:
		if L.has(k):
			pois.append({"id": k, "type": "discover", "pos": L[k], "radius": 55.0 if k != "city_center" else 90.0, "label": String(k).capitalize().replace("_", " ")})
	_build_airport()
	_build_race_tracks()
	_place_collectibles()

var station: GasStation = null
var district: PackDistrict = null
var airport: Airport = null
var race_tracks: RaceTracks = null
const SPEED_CAM_REWARD := 100
var kart_loan: Dictionary = {}      # {"home": Vehicle (parked original car), "track": id} while a go-kart is borrowed

func _build_race_tracks() -> void:
	var t0: int = Time.get_ticks_msec()
	race_tracks = RaceTracks.new()
	add_child(race_tracks)
	race_tracks.build(self)
	print("RACE TRACKS built in %d ms" % [Time.get_ticks_msec() - t0])

## Borrow the go-kart of a track.  The car the player was in is parked (frozen, untouched: position, fuel and damage are kept) and
## comes back, unchanged, when the kart is returned.
func take_kart(id: String) -> void:
	if race_tracks == null or not kart_loan.is_empty() or player_car == null:
		return
	if missions and missions.blocks_exit():
		Game.notify.emit("Finish or abandon the mission first", "warn")
		return
	var home: Vehicle = player_car
	var spot: Dictionary = race_tracks.kart_spot(id)
	home.clear_inputs()
	home.is_player = false
	home.engine_on = false
	home.set_headlights(false)
	home.set_indicator(0)
	home.set_inputs(0.0, 1.0, 0.0, true)   # parked: held by the handbrake (a frozen VehicleBody3D produced NaN transforms)
	for pair in [["body_entered", "_on_car_body_entered"], ["crashed", "_on_car_crashed"], ["destroyed", "_on_car_destroyed"]]:
		var cb := Callable(self, pair[1])
		if home.is_connected(pair[0], cb):
			home.disconnect(pair[0], cb)
	kart_loan = {"home": home, "track": id}
	player_car = null
	race_tracks.set_kart_available(id, false)
	spawn_player_car((spot["pos"] as Vector3) + Vector3(0, 0.25, 0), spot["yaw"], Data.KART_ID)
	enter_drive_mode()
	Game.notify.emit("Go-Kart taken - your %s waits here. Cross the start/finish line for $%d per lap" % [Data.vehicle(home.vid)["name"], RaceTracks.LAP_REWARD], "info")

## Give the kart back and get into the original car again (also used when the kart is wrecked).
func return_kart(reason: String = "") -> void:
	if kart_loan.is_empty():
		return
	var home: Vehicle = kart_loan["home"]
	var id: String = kart_loan["track"]
	var kart: Vehicle = player_car
	kart_loan = {}
	if kart != null and is_instance_valid(kart):
		kart.queue_free()
	player_car = home
	home.clear_inputs()
	home.is_player = true
	home.engine_on = true
	home.body_entered.connect(_on_car_body_entered)
	home.crashed.connect(_on_car_crashed)
	home.destroyed.connect(_on_car_destroyed)
	traffic.player = home
	traffic.player_vehicle = home
	audio.attach_vehicle(home)
	cam.target = home
	race_tracks.set_kart_available(id, true)
	enter_drive_mode()
	if bool(Game.settings.get("headlights_auto", true)):
		home.set_headlights(env.is_night())
	Game.notify.emit(reason if reason != "" else "Go-Kart returned - back in your %s" % Data.vehicle(home.vid)["name"], "info")
	Game.save_game()

func _build_airport() -> void:
	var t0: int = Time.get_ticks_msec()
	airport = Airport.new()
	add_child(airport)
	airport.build()
	airport.set_car_available(not (Game.selected == Airport.CAR_ID))
	pois.append({"id": "airport_car", "type": "airport_car", "pos": airport.car_spot, "radius": 5.5, "label": "Airport Shuttle Cart"})
	make_beacon(airport.car_spot, Color(0.3, 0.8, 1.0), 14.0, 0.9)
	print("AIRPORT %d pieces built in %d ms" % [airport.count, Time.get_ticks_msec() - t0])

## Free pick-up of the airport shuttle cart: adds it to the garage (no cost) and puts the player in it at the airport.
func take_airport_car() -> void:
	if airport == null:
		return
	if missions and missions.blocks_exit():
		Game.notify.emit("Finish or abandon the mission first", "warn")
		return
	if mode == "drive" and player_car != null and player_car.vid == Airport.CAR_ID:
		return
	Game.claim_free_vehicle(Airport.CAR_ID)
	if player_car != null:
		player_car.queue_free()
		player_car = null
	spawn_player_car(airport.car_spot, airport.car_yaw)
	enter_drive_mode()
	airport.set_car_available(false)

func _build_station(c: Vector3) -> void:
	station = GasStation.new()
	station.name = "GasStation"
	add_child(station)
	station.build(c)
	for z in GasStation.zone_defs(c):
		pois.append(z)
		var col: Color = Color(1.0, 0.8, 0.1) if z["type"] == "fuel" else (Color(1.0, 0.5, 0.1) if z["type"] == "repair" else Color(0.2, 0.55, 1.0))
		make_beacon(z["pos"], col, 18.0, 0.9)
	district = PackDistrict.new()
	district.name = "PackDistrict"
	add_child(district)
	var t_d: int = Time.get_ticks_msec()
	district.build(gen)
	print("DISTRICT %d pack buildings, %d nodes, built in %d ms" % [district.count, district.get_child_count(), Time.get_ticks_msec() - t_d])

## Small roadside fuel stop (canopy, two pump islands, price pylon) for the stations added along the expansion roads.
## Drive-in from any side: the interaction circle (14 m) covers the whole forecourt.
func _build_roadside_pumps(c: Vector3) -> void:
	var root := Node3D.new()
	root.name = "RoadsideStation"
	root.position = c
	add_child(root)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.9, 0.9, 0.92)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.12, 0.1)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.2, 0.2, 0.24)
	var slab := StandardMaterial3D.new()
	slab.albedo_color = Color(0.3, 0.3, 0.33)
	var parts: Array = [
		[Vector3(30, 0.2, 18), Vector3(0, 0.1, 0), slab, true],
		[Vector3(16, 0.5, 9), Vector3(0, 5.4, 0), white, false],
		[Vector3(16.2, 0.25, 9.2), Vector3(0, 5.1, 0), red, false],
		[Vector3(0.5, 5.2, 0.5), Vector3(-7.5, 2.6, -3.8), dark, true], [Vector3(0.5, 5.2, 0.5), Vector3(7.5, 2.6, -3.8), dark, true],
		[Vector3(0.5, 5.2, 0.5), Vector3(-7.5, 2.6, 3.8), dark, true], [Vector3(0.5, 5.2, 0.5), Vector3(7.5, 2.6, 3.8), dark, true],
		[Vector3(1.0, 1.5, 0.6), Vector3(-3.0, 0.95, 0), red, true], [Vector3(1.0, 1.5, 0.6), Vector3(3.0, 0.95, 0), red, true],
		[Vector3(0.6, 7.0, 0.6), Vector3(-13.0, 3.5, -7.0), dark, true],
		[Vector3(2.6, 1.6, 0.4), Vector3(-13.0, 7.3, -7.0), red, false],
	]
	for pr in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = pr[0]
		mi.mesh = bm
		mi.position = pr[1]
		mi.material_override = pr[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		if pr[3]:
			var sb := StaticBody3D.new()
			sb.collision_layer = 1
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = pr[0]
			cs.shape = bs
			sb.position = pr[1]
			sb.add_child(cs)
			root.add_child(sb)
	var lb := Label3D.new()
	lb.text = "FUEL"
	lb.font_size = 64
	lb.pixel_size = 0.012
	lb.modulate = Color(1, 1, 1)
	lb.outline_size = 8
	lb.position = Vector3(-13.0, 7.3, -6.75)
	root.add_child(lb)

func _structure(t: String) -> Dictionary:
	for s in gen.structures:
		if s["type"] == t:
			return s
	return {}

const COLLECTIBLE_SPOTS := ["@lighthouse", "@summit", "@port", "@marlin_bay", "@desert_outpost", "@ghost_town", "@circuit", "@marina",
	"@pinecrest", "@beach", "@rooftop_parking", "@tunnel", "@dragstrip_end", "@farm", "@pine_ridge", "@north_pass", "@industrial",
	"@eastwood", "@stadium", "@city_center"]

func _place_collectibles() -> void:
	for i in COLLECTIBLE_SPOTS.size():
		var p: Vector3 = gen.resolve_point(COLLECTIBLE_SPOTS[i])
		if p == Vector3.ZERO:
			continue
		var off := Vector3(7.0 * cos(float(i) * 2.1), 0.0, 7.0 * sin(float(i) * 2.1))
		var rp: Dictionary = gen.nearest_road(p + off, 120.0)
		var pos: Vector3 = p + off
		if not rp.is_empty():
			var rpos: Vector3 = rp["pos"]
			pos = rpos + Vector3(3.5, 0, 3.5)
		pos.y = maxf(gen.ground_h(pos.x, pos.z), 0.3) if gen.ground_h(pos.x, pos.z) > 0.0 else p.y
		if i == 10:
			pos.y = p.y
		var id: String = "pkg_%02d" % i
		if Game.collectibles.has(id):
			continue
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.55
		sm.height = 1.1
		sm.radial_segments = 12
		sm.rings = 6
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.15, 0.2)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.1, 0.15)
		m.emission_energy_multiplier = 2.2
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		mi.position = pos + Vector3(0, 1.4, 0)
		beacons.add_child(mi)
		var bm: MeshInstance3D = make_beacon(pos, Color(1.0, 0.15, 0.2), 14.0, 0.5)
		collectibles.append({"id": id, "pos": pos, "node": mi, "beam": bm})

# ---------------------------------------------------------------- game flow
func _process(delta: float) -> void:
	if gen == null:
		return
	if not running and mode == "menu":
		streamer.focus = menu_dummy.global_position
	if env and cam:
		env.cam = cam.cam

func start_menu() -> void:
	mode = "menu"
	## The menu has its own tiny background scene (MenuBackground); the gameplay world is neither streamed nor
	## rendered while it is showing.
	visible = false
	streamer.set_process(false)
	traffic.enabled = false
	traffic.player = menu_dummy
	traffic.player_vehicle = null
	audio.set_music("menu")

var tilt: TiltSteer = TiltSteer.new()

func start_game(load_save: bool) -> void:
	if load_save:
		if not Game.load_game():
			Game.new_game()
	else:
		Game.new_game()
	await _begin_session()

func _begin_session() -> void:
	running = false
	visible = true
	streamer.set_process(true)
	traffic.enabled = true
	cam.cam.make_current()
	cam.orbit_mode = false
	Game.in_world = false
	if player_car and is_instance_valid(player_car):
		player_car.queue_free()
		player_car = null
	traffic.clear_all()
	env.hour = Game.time_of_day
	env.set_weather(Game.weather_state, true)
	var start_pos: Vector3 = Game.player_pos
	var yaw: float = Game.player_rot
	if start_pos == Vector3.ZERO or start_pos.length() < 1.0:
		var gp: Vector3 = gen.landmarks.get("home_garage", Vector3(0, 6, 20))
		var pose: Dictionary = road_pose(gp)
		start_pos = pose["pos"]
		yaw = pose["yaw"]
	loading_progress.emit(0.0, "Streaming world")
	streamer.focus = start_pos
	streamer.builds_per_frame = 4
	streamer.max_inflight = 4
	var t0: int = Time.get_ticks_msec()
	while not streamer.loaded_ring(start_pos, 1) and Time.get_ticks_msec() - t0 < 20000:
		loading_progress.emit(streamer.loading_fraction(start_pos) * 0.9, "Streaming world")
		await get_tree().process_frame
	streamer.builds_per_frame = 1
	streamer.max_inflight = 2
	if not warmed:
		warmed = true
		loading_progress.emit(0.9, "Preparing shaders")
		var passes: int = 2 if OS.get_cmdline_user_args().has("--warmprof") else 1
		for pass_i in range(passes):
			var wu := WarmUp.new()
			wu.profile = passes > 1
			add_child(wu)
			var t_w: int = Time.get_ticks_msec()
			await wu.run(self)
			print("WARMUP pass %d done in %d ms" % [pass_i + 1, Time.get_ticks_msec() - t_w])
	loading_progress.emit(0.95, "Preparing vehicle")
	await get_tree().process_frame
	if police == null:
		police = PoliceManager.new()
		police.name = "Police"
		police.world = self
		add_child(police)
		peds = PedManager.new()
		peds.name = "Peds"
		peds.world = self
		add_child(peds)
		fauna = FaunaManager.new()
		fauna.name = "Fauna"
		fauna.world = self
		add_child(fauna)
		missions = MissionManager.new()
		missions.name = "Missions"
		missions.world = self
		add_child(missions)
		missions.setup()
		foot = FootPlayer.new()
		foot.name = "Foot"
		add_child(foot)
		foot.enabled = false
		foot.visible = false
		foot.process_mode = Node.PROCESS_MODE_DISABLED
	police.reset()
	missions.reset()
	spawn_player_car(start_pos, yaw)
	enter_drive_mode()
	Game.in_world = true
	Game.autosave_timer = 0.0
	loading_progress.emit(1.0, "Ready")
	running = true
	tilt_recalibrate()
	audio.set_music("drive")
	Game.notify.emit("Welcome to Drive Beyond", "info")

func road_pose(pos: Vector3) -> Dictionary:
	var nr: Dictionary = gen.nearest_road(pos, 120.0)
	if nr.is_empty():
		return {"pos": pos, "yaw": 0.0}
	var e: Dictionary = gen.edges[nr["edge"]]
	var pts: PackedVector3Array = e["pts"]
	var i: int = nr["idx"]
	var a: Vector3 = pts[maxi(i - 1, 0)]
	var b: Vector3 = pts[mini(i + 1, pts.size() - 1)]
	var d: Vector3 = b - a
	var yaw: float = atan2(-d.x, -d.z)
	var p: Vector3 = nr["pos"]
	var right := Vector3(d.z, 0, -d.x).normalized()
	p += right * (float(e["width"]) * 0.25)
	return {"pos": p, "yaw": yaw}

func spawn_player_car(pos: Vector3, yaw: float, vid_override: String = "") -> void:
	var vid: String = Game.selected if vid_override == "" else vid_override
	var rec: Dictionary = Game.owned[vid] if vid_override == "" else {"custom": Data.default_custom(vid), "upg": Data.default_upgrades(), "damage": 0.0, "fuel": 1.0}
	var v := Vehicle.new()
	v.name = "PlayerCar"
	v.is_player = true
	v.add_to_group("player_vehicle")
	add_child(v)
	v.configure(vid, rec["custom"], rec["upg"], float(rec["damage"]), float(rec["fuel"]))
	var gy: float = gen.ground_h(pos.x, pos.z)
	var py: float = maxf(pos.y, gy)
	v.place_on_ground(Vector3(pos.x, py, pos.z), yaw)
	player_car = v
	v.body_entered.connect(_on_car_body_entered)
	v.crashed.connect(_on_car_crashed)
	v.destroyed.connect(_on_car_destroyed)
	v.shifted.connect(func(up: bool) -> void: audio.play_shift())
	traffic.player = v
	traffic.player_vehicle = v
	audio.attach_vehicle(v)
	last_road_pos = pos
	last_road_yaw = yaw
	cam.target = v
	cam.on_foot = false
	cam.snap()
	if Game.settings.get("headlights_auto", true):
		v.set_headlights(env.is_night())

func enter_drive_mode() -> void:
	mode = "drive"
	cam.on_foot = false
	cam.target = player_car
	cam.snap()
	foot.enabled = false
	foot.visible = false
	foot.process_mode = Node.PROCESS_MODE_DISABLED
	player_car.engine_on = true
	traffic.player = player_car
	mode_changed.emit(mode)

func enter_foot_mode(pos: Vector3, yaw: float) -> void:
	mode = "foot"
	foot.process_mode = Node.PROCESS_MODE_INHERIT
	foot.enabled = true
	foot.visible = true
	foot.place(pos, yaw)
	foot.cam_yaw = yaw
	cam.foot_yaw = yaw + PI
	cam.on_foot = true
	cam.target = foot
	cam.snap()
	traffic.player = foot
	player_car.clear_inputs()
	mode_changed.emit(mode)

func try_exit_vehicle() -> void:
	if mode != "drive" or player_car == null:
		return
	if player_car.abs_speed > 4.0:
		Game.notify.emit("Slow down to exit the vehicle", "warn")
		return
	if missions and missions.blocks_exit():
		Game.notify.emit("Finish or abandon the mission first", "warn")
		return
	var side: float = -1.0
	var dp: Vector3 = player_car.door_position(side)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(dp + Vector3(0, 3, 0), dp + Vector3(0, -4, 0), 1)
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		side = 1.0
		dp = player_car.door_position(side)
		q = PhysicsRayQueryParameters3D.create(dp + Vector3(0, 3, 0), dp + Vector3(0, -4, 0), 1)
		hit = space.intersect_ray(q)
	if hit.is_empty():
		Game.notify.emit("No room to exit here", "warn")
		return
	player_car.clear_inputs()
	player_car.set_indicator(0)
	player_car.set_headlights(player_car.headlights_on)
	enter_foot_mode(hit["position"] + Vector3(0, 0.1, 0), player_car.rotation.y)
	exit_cooldown = 0.5

func try_enter_vehicle() -> void:
	if mode != "foot" or player_car == null:
		return
	if foot.global_position.distance_to(player_car.global_position) > 4.8:
		return
	enter_drive_mode()

func respawn_car_at(pos: Vector3, yaw: float) -> void:
	if player_car == null:
		return
	player_car.place_on_ground(Vector3(pos.x, maxf(pos.y, gen.ground_h(pos.x, pos.z)), pos.z), yaw)
	player_car.wrecked = false
	cam.snap()

func respawn_on_road() -> void:
	var p: Vector3 = last_road_pos
	var pose: Dictionary = road_pose(player_pos())
	if not pose.is_empty() and gen.nearest_road(player_pos(), 300.0).size() > 0:
		p = pose["pos"]
		last_road_yaw = pose["yaw"]
	if mode == "foot":
		foot.place(p + Vector3(0, 1, 0), 0.0)
		return
	respawn_car_at(p, last_road_yaw)

func send_to_garage(reason: String) -> void:
	if not kart_loan.is_empty():
		return_kart()
	var gp: Vector3 = gen.landmarks.get("home_garage", Vector3(0, 6, 20))
	var pose: Dictionary = road_pose(gp)
	if mode == "foot":
		enter_drive_mode()
	player_car.damage = 0.0
	player_car.repair_full()
	player_car.fuel = maxf(player_car.fuel, 0.4)
	respawn_car_at(pose["pos"], pose["yaw"])
	Game.notify.emit(reason, "warn")

func player_pos() -> Vector3:
	if mode == "foot" and foot:
		return foot.global_position
	if player_car:
		return player_car.global_position
	return menu_dummy.global_position

func current_vehicle() -> Vehicle:
	return player_car if mode == "drive" else null

func focus_node() -> Node3D:
	return foot if mode == "foot" else player_car

# ---------------------------------------------------------------- waypoint / route
func set_waypoint(p: Vector3) -> void:
	waypoint = p
	has_waypoint = true
	_rebuild_route()
	Game.notify.emit("Waypoint set", "info")

func clear_waypoint() -> void:
	has_waypoint = false
	route = PackedVector3Array()

func _rebuild_route() -> void:
	if not has_waypoint:
		route = PackedVector3Array()
		return
	route = nav.route(player_pos(), waypoint)

func active_route() -> PackedVector3Array:
	if missions and missions.route.size() > 1:
		return missions.route
	return route

# ---------------------------------------------------------------- input / physics
func ui_blocking(b: bool) -> void:
	var was: bool = ui_open
	ui_open = b
	if was and not b:
		tilt_recalibrate()   # resume from pause/menu: current pose becomes neutral

## True when tilt steering should drive the car (setting on and a sensor, or a test override).
func tilt_active() -> bool:
	if not bool(Game.settings.get("tilt_steer", false)):
		return false
	return Game.is_mobile or tilt.override_gravity != null

func tilt_recalibrate() -> void:
	tilt.calibrate()
	tilt.reset()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		tilt_recalibrate()

func _input(ev: InputEvent) -> void:
	if not running or ui_open:
		return
	if ev is InputEventMouseMotion:
		var mm: InputEventMouseMotion = ev
		if mode == "foot" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			cam.add_look(mm.relative.x * float(Game.settings.get("mouse_sens", 1.0)), mm.relative.y * float(Game.settings.get("mouse_sens", 1.0)))
		elif (mm.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0 and not Game.is_mobile:
			cam.add_look(mm.relative.x, mm.relative.y)
	elif ev is InputEventScreenDrag:
		pass

func apply_look(dx: float, dy: float) -> void:
	cam.add_look(dx, dy)

var warmed: bool = false
var test_fly: Vector3 = Vector3.ZERO

func _physics_process(dt: float) -> void:
	if not running:
		return
	if test_fly != Vector3.ZERO and player_car:
		player_car.global_position += test_fly * dt
		player_car.linear_velocity = test_fly
	var fnode: Node3D = focus_node()
	streamer.focus = fnode.global_position
	var fv: Vector3 = Vector3.ZERO
	if player_car and fnode == player_car:
		fv = player_car.linear_velocity
		fv.y = 0.0
	var lead_v: Vector3 = fv * 1.6
	if lead_v.length() > 160.0:
		lead_v = lead_v.normalized() * 160.0
	streamer.lead = streamer.lead.lerp(lead_v, clampf(dt * 1.5, 0.0, 1.0))
	exit_cooldown = maxf(0.0, exit_cooldown - dt)
	if not ui_open:
		_handle_input(dt)
	_hazards(dt)
	_update_poi(dt)
	if race_tracks != null:
		race_tracks.update(dt, player_pos(), mode == "drive")
	_update_prompt()
	sync_timer -= dt
	if sync_timer <= 0.0:
		sync_timer = 0.5
		_sync_state()
	route_timer -= dt
	if route_timer <= 0.0:
		route_timer = 4.0
		if has_waypoint:
			_rebuild_route()
			if player_pos().distance_to(waypoint) < 25.0:
				has_waypoint = false
				route = PackedVector3Array()
				Game.notify.emit("Destination reached", "info")

func _handle_input(dt: float) -> void:
	if Input.is_action_just_pressed("camera") and mode == "drive":
		cam.cycle_mode()
	if Input.is_action_just_pressed("exit_vehicle") and mode == "drive":
		try_exit_vehicle()
	if mode == "drive" and player_car:
		var steer: float = Input.get_axis("steer_left", "steer_right")
		if tilt_active():
			# Tilt mode: gravity-vector roll -> smoothed [-1,1]; own sensitivity (not steer_sens)
			steer = tilt.update(dt, float(Game.settings.get("tilt_sens", 1.0)), float(Game.settings.get("tilt_dead", 3.0)), bool(Game.settings.get("tilt_invert", false)))
		else:
			steer = clampf(steer * float(Game.settings.get("steer_sens", 1.0)), -1.0, 1.0)
		var thr: float = Input.get_action_strength("accelerate")
		var brk: float = Input.get_action_strength("brake")
		var hb: bool = Input.is_action_pressed("handbrake")
		var nit: bool = Input.is_action_pressed("nitro")
		if player_car.wrecked or player_car.fuel <= 0.0:
			thr = 0.0
		player_car.set_inputs(thr, brk, steer, hb, nit)
		if Input.is_action_just_pressed("headlights"):
			player_car.set_headlights(not player_car.headlights_on)
		if Input.is_action_just_pressed("indicator_left"):
			player_car.toggle_indicator(1)
		if Input.is_action_just_pressed("indicator_right"):
			player_car.toggle_indicator(2)
		if Input.is_action_just_pressed("reset_car"):
			_reset_car()
		audio.set_horn(Input.is_action_pressed("horn"))
		if player_car.respawn_hold > 3.0:
			_reset_car()
	elif mode == "foot":
		foot.cam_yaw = cam.foot_yaw + PI
		foot.move_input = Vector2(Input.get_axis("foot_left", "foot_right"), Input.get_axis("foot_back", "foot_forward"))
		foot.want_sprint = Input.is_action_pressed("sprint")
		if Input.is_action_just_pressed("jump"):
			foot.want_jump = true
		audio.set_horn(false)
	if Input.is_action_just_pressed("map"):
		_open("map")
	if Input.is_action_just_pressed("pause"):
		_open("pause")
	if Input.is_action_just_pressed("interact") and exit_cooldown <= 0.0:
		do_interact()
	if env.is_night() != was_night:
		was_night = env.is_night()
		if station:
			station.set_night(was_night)
		if player_car and bool(Game.settings.get("headlights_auto", true)):
			player_car.set_headlights(was_night)

## test helper: put the player's car on a POI (id), heading yaw, with an optional local offset
func test_teleport(poi_id: String, yaw: float, off: Vector3 = Vector3.ZERO) -> void:
	for poi in pois:
		if poi["id"] == poi_id and player_car:
			var p: Vector3 = poi["pos"] + off
			player_car.place_on_ground(Vector3(p.x, p.y + 1.0, p.z), yaw)
			player_car.linear_velocity = Vector3.ZERO
			player_car.angular_velocity = Vector3.ZERO
			return

func _open(screen: String) -> void:
	if ui_hooks.has(screen):
		(ui_hooks[screen] as Callable).call()

func _reset_car() -> void:
	var pose: Dictionary = road_pose(player_car.global_position)
	var nr: Dictionary = gen.nearest_road(player_car.global_position, 40.0)
	if nr.is_empty():
		pose = {"pos": player_car.global_position + Vector3(0, 1.5, 0), "yaw": player_car.rotation.y}
	respawn_car_at(pose["pos"], pose["yaw"])
	Game.notify.emit("Vehicle reset", "info")

func _hazards(dt: float) -> void:
	var p: Vector3 = player_pos()
	var nr_dist: float = 9999.0
	if mode == "drive" and player_car:
		var pc: Vector3 = player_car.global_position
		if player_car.on_road and gen.on_road(pc.x, pc.z) and pc.y > 0.5:
			last_road_pos = pc
			last_road_yaw = player_car.rotation.y
		Game.stats["distance"] = float(Game.stats["distance"]) + player_car.abs_speed * dt
		Game.stats["top_speed"] = maxf(float(Game.stats["top_speed"]), player_car.abs_speed)
		if player_car.drift_points > float(Game.stats["drift_best"]):
			Game.stats["drift_best"] = player_car.drift_points
	# water / void
	var wl: float = -0.6
	if p.y < wl and gen.region_at(p.x, p.z) in ["ocean", "coast"] or p.y < -6.0:
		water_time += dt
		if water_time > 2.2:
			water_time = 0.0
			if mode == "foot":
				Game.notify.emit("You fell in the water", "warn")
				respawn_on_road()
			else:
				Game.notify.emit("Vehicle lost in the water - recovered", "warn")
				if player_car:
					player_car.damage = minf(player_car.damage + 0.2, 0.95)
					player_car.apply_damage_visuals()
				respawn_on_road()
	else:
		water_time = 0.0
	# near miss with traffic gives rep + minor cash combo
	near_miss_cd -= dt
	if mode == "drive" and player_car.abs_speed > 22.0 and near_miss_cd <= 0.0:
		for c in traffic.cars:
			if not is_instance_valid(c):
				continue
			var tc: TrafficCar = c
			if tc.state != "drive":
				continue
			var d: Vector3 = tc.global_position - player_car.global_position
			if absf(d.y) < 2.0 and d.length() < 3.6 and d.length() > 1.8:
				near_miss_cd = 2.0
				Game.add_money(20, "Near miss")
				break

func _on_car_body_entered(body: Node) -> void:
	if body is TrafficCar and player_car:
		var sp: float = player_car.abs_speed
		traffic.on_player_hit(body, sp)
		if sp > 6.0 and police:
			police.report_crime(0.18 + sp * 0.01, "Hit-and-run")
	elif body is Vehicle and (body as Vehicle).is_police:
		pass

func _on_car_crashed(sev: float, wpos: Vector3) -> void:
	cam.add_shake(clampf(sev * 1.2, 0.1, 1.0))
	audio.play_crash(sev)
	if Game.settings.get("haptics", true) and Game.is_mobile:
		Input.vibrate_handheld(int(60 + sev * 160))

func _on_car_destroyed() -> void:
	if not kart_loan.is_empty():
		return_kart("Go-Kart wrecked - back in your car")
		return
	Game.notify.emit("Your car is wrecked", "bad")
	await get_tree().create_timer(2.2).timeout
	if player_car and player_car.wrecked:
		var cost: int = mini(Game.money, 500 + int(float(Data.vehicle(player_car.vid)["price"]) * 0.02))
		Game.add_money(-cost, "Tow & repair")
		if missions:
			missions.fail_active("Vehicle wrecked")
		send_to_garage("Towed back to the garage")

# ---------------------------------------------------------------- POIs & prompts
func _update_poi(dt: float) -> void:
	var p: Vector3 = player_pos()
	near_poi = {}
	var best: float = 1e9
	for poi in pois:
		var pp: Vector3 = poi["pos"]
		var d: float = Vector2(pp.x - p.x, pp.z - p.z).length()
		if poi["type"] == "discover":
			if d < float(poi["radius"]) and not Game.discovered.has(poi["id"]):
				Game.discover(poi["id"])
				Game.add_money(250, "Discovered " + String(poi["label"]))
				Game.add_rep(8)
				Game.location_discovered.emit(poi["id"])
			continue
		if d < float(poi["radius"]) and absf(pp.y - p.y) < 12.0 and d < best:
			best = d
			near_poi = poi
	for c in collectibles.duplicate():
		var cp: Vector3 = c["pos"]
		if Vector2(cp.x - p.x, cp.z - p.z).length() < 3.6 and absf(cp.y - p.y) < 4.0:
			if Game.add_collectible(c["id"]):
				Game.add_money(400, "Hidden package")
				Game.add_rep(5)
				audio.play_ui("pickup")
			(c["node"] as Node).queue_free()
			(c["beam"] as Node).queue_free()
			collectibles.erase(c)
	for c in collectibles:
		(c["node"] as Node3D).rotation.y += dt * 2.0
		(c["node"] as Node3D).position.y = float((c["pos"] as Vector3).y) + 1.4 + sin(Time.get_ticks_msec() * 0.003) * 0.15
	# speed cameras
	speed_cam_cd -= dt
	if mode == "drive":
		for ci in range(gen.speed_cameras.size()):
			var s3: Vector3 = gen.speed_cameras[ci]
			var inside: bool = Vector2(s3.x - p.x, s3.z - p.z).length() < 16.0
			if not inside:
				speed_cam_latched.erase(ci)         # must leave the camera's area before it can pay again
			elif speed_cam_cd <= 0.0 and not speed_cam_latched.has(ci) and player_car.abs_speed > 36.0:
				speed_cam_latched[ci] = true
				speed_cam_cd = 6.0
				Game.add_money(SPEED_CAM_REWARD, "Speed camera bonus")
				Game.notify.emit("Speed camera flash!  +$%d bonus" % SPEED_CAM_REWARD, "info")
				Game.save_game()
				audio.play_ui("camera")
				_flash_screen()
				break

func _flash_screen() -> void:
	if ui_hooks.has("flash"):
		(ui_hooks["flash"] as Callable).call()

func _update_prompt() -> void:
	var t: String = ""
	var act := Callable()
	var key: String = Game.key_name("interact")
	if airport != null:
		airport.set_car_available(player_car == null or player_car.vid != Airport.CAR_ID)
	if mode == "foot":
		if player_car and foot.global_position.distance_to(player_car.global_position) < 4.8:
			t = "[%s] Enter Vehicle" % key
			act = try_enter_vehicle
		elif not near_poi.is_empty():
			var pr: Array = _poi_prompt(near_poi)
			t = pr[0]
			act = pr[1]
	elif mode == "drive":
		var ms: Dictionary = missions.start_prompt() if missions else {}
		if not ms.is_empty():
			t = ms["text"]
			act = ms["action"]
		elif not near_poi.is_empty() and player_car.abs_speed < 6.0:
			var pr2: Array = _poi_prompt(near_poi)
			t = pr2[0]
			act = pr2[1]
		elif player_car.abs_speed < 3.0 and not (missions and missions.blocks_exit()):
			t = "[%s] Exit Vehicle" % key
			act = try_exit_vehicle
	if t != prompt_text:
		prompt_text = t
		prompt_changed.emit()
	prompt_action = act

func _poi_prompt(poi: Dictionary) -> Array:
	var key: String = Game.key_name("interact")
	match poi["type"]:
		"airport_car":
			return ["[%s] Take the Airport Shuttle Cart  (free)" % key, take_airport_car]
		"kart":
			if not kart_loan.is_empty():
				if kart_loan["track"] == poi["track"]:
					return ["[%s] Return the Go-Kart and get back in your %s" % [key, Data.vehicle((kart_loan["home"] as Vehicle).vid)["name"]], return_kart]
				return ["Return the go-kart at its own track first", Callable()]
			if mode != "drive" and mode != "foot":
				return ["", Callable()]
			return ["[%s] Drive the Go-Kart  (free, $%d per lap)" % [key, RaceTracks.LAP_REWARD], take_kart.bind(String(poi["track"]))]
		"garage":
			return ["[%s] Open Garage" % key, _open.bind("garage")]
		"dealership":
			return ["[%s] Visit Dealership" % key, _open.bind("dealership")]
		"fuel":
			if mode != "drive" or player_car == null:
				return ["Bring a vehicle to the pumps to refuel", Callable()]
			if player_car.abs_speed > 1.0:
				return ["Stop the vehicle to refuel", Callable()]
			if player_car.fuel >= 0.995:
				return ["Tank is full", Callable()]
			return ["[%s] Refuel" % key, _open.bind("refuel")]
		"repair":
			if mode != "drive" or player_car == null:
				return ["Bring a vehicle into the repair bay", Callable()]
			if player_car.abs_speed > 1.0:
				return ["Stop the vehicle to repair", Callable()]
			if player_car.damage < 0.01:
				return ["Vehicle is in perfect condition", Callable()]
			return ["[%s] Repair  (%s)" % [key, Game.fmt_money(repair_fee())], _open.bind("repair")]
		"gas":
			var cost: int = refuel_cost()
			if cost <= 0:
				return ["Tank is full", Callable()]
			return ["[%s] Refuel  ($%d)" % [key, cost], refuel]
	return ["", Callable()]

func do_interact() -> void:
	if prompt_action.is_valid():
		prompt_action.call()

const FUEL_PRICE := 1.8   # $ per litre

func repair_fee() -> int:
	if player_car == null:
		return 0
	var d: float = clampf(player_car.damage, 0.0, 1.5)
	return int(ceil(d * 900.0 / 10.0)) * 10

func refuel_cost() -> int:
	if player_car == null:
		return 0
	return int(ceil((1.0 - player_car.fuel) * 90.0))

func refuel() -> void:
	if player_car == null:
		return
	var c: int = refuel_cost()
	if c <= 0:
		return
	if Game.money < c:
		var frac: float = float(Game.money) / 90.0
		if frac <= 0.0:
			Game.notify.emit("Not enough money for fuel", "warn")
			return
		player_car.fuel = minf(1.0, player_car.fuel + frac)
		Game.add_money(-Game.money, "Fuel")
		return
	Game.add_money(-c, "Fuel")
	player_car.fuel = 1.0
	audio.play_ui("pickup")

func _sync_state() -> void:
	if player_car == null or (ui_open and not Game.in_world):
		return
	var vid: String = player_car.vid
	if Game.owned.has(vid):
		Game.owned[vid]["damage"] = player_car.damage
		Game.owned[vid]["fuel"] = player_car.fuel
	var p: Vector3 = player_pos()
	if not kart_loan.is_empty():
		var hc: Vehicle = kart_loan["home"]
		Game.player_pos = hc.global_position
		Game.player_rot = hc.rotation.y
		Game.owned[hc.vid]["damage"] = hc.damage
		Game.owned[hc.vid]["fuel"] = hc.fuel
		return
	if mode == "drive":
		Game.player_pos = p
		Game.player_rot = player_car.rotation.y
	elif mode == "foot":
		Game.player_pos = player_car.global_position
		Game.player_rot = player_car.rotation.y

## Replace the active car with the currently selected one (after garage use)
func swap_player_car() -> void:
	if not kart_loan.is_empty():
		return_kart()
	var old: Vehicle = player_car
	var pos: Vector3 = old.global_position
	var yaw: float = old.rotation.y
	old.queue_free()
	player_car = null
	spawn_player_car(pos, yaw)
	enter_drive_mode()

func apply_custom_to_car() -> void:
	if player_car == null:
		return
	var vid: String = Game.selected
	var rec: Dictionary = Game.owned[vid]
	if player_car.vid != vid:
		swap_player_car()
		return
	var pos: Vector3 = player_car.global_position
	var yaw: float = player_car.rotation.y
	player_car.queue_free()
	player_car = null
	spawn_player_car(pos, yaw)
	enter_drive_mode()

func shutdown_session() -> void:
	running = false
	if not kart_loan.is_empty():
		var hv: Vehicle = kart_loan["home"]
		kart_loan = {}
		if is_instance_valid(hv):
			hv.queue_free()
	Game.in_world = false
	if player_car:
		player_car.queue_free()
		player_car = null
	traffic.clear_all()
	if police:
		police.reset()
	if missions:
		missions.reset()
	if fauna:
		fauna.clear()
	if peds:
		peds.clear()
	mode = "menu"
	start_menu()
