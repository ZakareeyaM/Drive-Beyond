extends Node
## Entry point: builds the world, owns every UI layer and screen flow.

var world: World
var hud_layer: CanvasLayer
var ui_layer: CanvasLayer
var hud_root: Control
var ui_root: Control
var hud: Hud
var touch: TouchControls
var theme: Theme
var menu_root: Control = null
var menu_bg: MenuBackground = null
var screen: Control = null
var screen_kind: String = ""
var loading: Menus.LoadingScreen = null
var back_stack: Array = []
var args: PackedStringArray
var in_game: bool = false
var frames: int = 0
var quit_after: int = 0
var script_cmds: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	args = OS.get_cmdline_user_args()
	theme = UIKit.make_theme()
	world = World.new()
	world.name = "World"
	add_child(world)
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	hud_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud_layer)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)
	hud_root = _root_ctrl()
	hud_layer.add_child(hud_root)
	ui_root = _root_ctrl()
	ui_layer.add_child(ui_root)
	world.build_world()
	hud = Hud.new()
	hud.world = world
	hud.visible = false
	hud_root.add_child(hud)
	touch = TouchControls.new()
	touch.world = world
	hud_root.add_child(touch)
	world.ui_hooks = {
		"map": open_map, "pause": open_pause, "garage": open_garage, "dealership": open_dealership, "refuel": open_refuel, "repair": open_repair,
		"flash": func() -> void: hud.flash(),
		"dialog": show_dialog, "mission_result": show_result,
		"mission_hint": func(d: Dictionary) -> void: Game.notify.emit(String(d.get("desc", "")), "info"),
	}
	world.loading_progress.connect(func(f: float, t: String) -> void:
		if loading:
			loading.set_progress(f, t))
	Game.notify.connect(func(_t: String, k: String) -> void:
		if world.audio and k in ["bad", "warn"]:
			pass)
	for a in args:
		if a.begins_with("--quit-after="):
			quit_after = int(a.get_slice("=", 1))
		if a == "--touch":
			Game.settings["show_touch"] = true
		if a.begins_with("--cmd="):
			script_cmds.append(a.get_slice("=", 1))
	world.start_menu()
	if "--autostart" in args or "--continue" in args:
		await get_tree().process_frame
		_start(false if "--autostart" in args else true)
	else:
		show_main_menu()

func _root_ctrl() -> Control:
	var c := Control.new()
	c.theme = theme
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.process_mode = Node.PROCESS_MODE_ALWAYS
	return c

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back_pressed()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if in_game and screen == null and world.running:
			Game.save_game()
			open_pause()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		if in_game:
			Game.save_game()
		get_tree().quit()

func _back_pressed() -> void:
	if screen != null:
		_close_screen()
	elif in_game and world.running:
		open_pause()

# ---------------------------------------------------------------- menu flow
func show_main_menu() -> void:
	in_game = false
	hud.visible = false
	_clear_menu()
	Game.has_save = FileAccess.file_exists(Game.SAVE_PATH) or FileAccess.file_exists(Game.SAVE_BAK)
	_show_menu_bg()
	menu_root = Menus.main_menu(_on_continue, _on_new, _on_settings_from_menu, _on_credits, _on_quit)
	ui_root.add_child(menu_root)
	get_tree().paused = false

func _show_menu_bg() -> void:
	if menu_bg == null:
		menu_bg = MenuBackground.new()
		add_child(menu_bg)
	menu_bg.activate()

func _clear_menu() -> void:
	if menu_root:
		menu_root.queue_free()
		menu_root = null

func _on_continue() -> void:
	_start(true)

func _on_new() -> void:
	_start(false)

func _on_quit() -> void:
	get_tree().quit()

func _on_settings_from_menu() -> void:
	_clear_menu()
	var s := SettingsMenu.new()
	s.closed.connect(func() -> void:
		s.queue_free()
		show_main_menu())
	ui_root.add_child(s)

func _on_credits() -> void:
	_clear_menu()
	var c: Control = Menus.credits(func() -> void: show_main_menu())
	menu_root = c
	ui_root.add_child(c)

func _start(load_save: bool) -> void:
	_clear_menu()
	if menu_bg:
		menu_bg.queue_free()
		menu_bg = null
	loading = Menus.LoadingScreen.new()
	ui_root.add_child(loading)
	await get_tree().process_frame
	await world.start_game(load_save)
	loading.queue_free()
	loading = null
	in_game = true
	hud.visible = true
	_apply_mouse_mode()

func _process(_delta: float) -> void:
	frames += 1
	if frames > 60:
		_ft_max = maxf(_ft_max, _delta * 1000.0)
		if _delta > 0.033:
			_ft_over += 1
		if _log_spikes and _delta > 0.05 and in_game:
			print("SPIKE f=%d %.0fms chunks_inst=%d (+%d) traffic=%d proc=%.1fms phys=%.1fms obj=%d" % [frames, _delta * 1000.0, world.streamer.prof_inst.size(), world.streamer.prof_inst.size() - _last_inst, world.traffic.cars.size(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
		if in_game and _log_spikes:
			var ph: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			if world.streamer.prof_inst.size() != _last_inst:
				_ph_add.append(ph)
			else:
				_ph_idle.append(ph)
		_last_inst = world.streamer.prof_inst.size() if in_game else 0
	if quit_after > 0 and frames >= quit_after:
		get_tree().quit()
	if script_cmds.size() > 0 and ((in_game and world.running) or menu_root != null) and frames % 120 == 0:
		_run_cmd(script_cmds.pop_front())
	_apply_mouse_mode()

func _apply_mouse_mode() -> void:
	if Game.is_mobile or DisplayServer.get_name() == "headless":
		return
	var want: int = Input.MOUSE_MODE_VISIBLE
	if in_game and world.mode == "foot" and screen == null and world.running:
		want = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != want:
		Input.mouse_mode = want as Input.MouseMode

func _run_cmd(c: String) -> void:
	if c == "m_settings_shot":
		_on_settings_from_menu()
		await get_tree().create_timer(1.5).timeout
		get_viewport().get_texture().get_image().save_png("/tmp/gd/ui_b_settings.png")
		return
	if c.begins_with("hl_"):   # test: tune the low beam live, e.g. hl_energy=12 hl_pitch=-9 hl_angle=60 hl_fill=2 hl_range=50
		var kv: PackedStringArray = c.substr(3).split("=")
		var val: float = float(kv[1])
		var car: Vehicle = world.player_car
		for sp in car._spot:
			match kv[0]:
				"energy": (sp as SpotLight3D).light_energy = val
				"angle": (sp as SpotLight3D).spot_angle = val
				"range": (sp as SpotLight3D).spot_range = val
				"pitch": (sp as SpotLight3D).rotation_degrees.x = val
				"atten": (sp as SpotLight3D).spot_attenuation = val
				"aatten": (sp as SpotLight3D).spot_angle_attenuation = val
		if kv[0] == "fill" and car._fill:
			car._fill.light_energy = val
		return
	if c.begins_with("tpx_"):   # test: tpx_<x>_<z>_<yaw deg>_<cam height>  -> teleport the car on the ground, e.g. tpx_1880_520_0
		var tv: PackedStringArray = c.substr(4).split("_")
		var tx: float = float(tv[0])
		var tz: float = float(tv[1])
		var ty: float = world.gen.ground_h(tx, tz)
		world.player_car.place_on_ground(Vector3(tx, ty + 1.0, tz), deg_to_rad(float(tv[2])))
		world.player_car.linear_velocity = Vector3.ZERO
		world.player_car.angular_velocity = Vector3.ZERO
		world.cam.snap()
		return
	if c.begins_with("aerial_"):   # test: aerial_<x>_<y>_<z>_<tx>_<ty>_<tz>  -> free debug camera
		var av: PackedStringArray = c.substr(7).split("_")
		var ac := get_node_or_null("DebugCam") as Camera3D
		if ac == null:
			ac = Camera3D.new()
			ac.name = "DebugCam"
			ac.far = 6000.0
			add_child(ac)
		ac.global_position = Vector3(float(av[0]), float(av[1]), float(av[2]))
		ac.look_at(Vector3(float(av[3]), float(av[4]), float(av[5])), Vector3.UP)
		ac.current = true
		return
	if c.begins_with("shot_"):
		get_viewport().get_texture().get_image().save_png("/tmp/gd/ui_%s.png" % c.substr(5))
		return
	if c.begins_with("hero_"):
		var hid: String = c.substr(5)
		Game.money = 900000
		Game.rep = 5000
		Game.garage_slots = maxi(Game.garage_slots, 12)
		Game.buy_vehicle(hid)
		Game.selected = hid
		world.apply_custom_to_car()
		print("HERO ", world.player_car.vid)
		return
	match c:
		"tp_fuel": world.test_teleport("station_fuel", -PI * 0.5)
		"tp_fuel2": world.test_teleport("station_fuel", PI * 0.5, Vector3(0, 0, -5.8))
		"tp_repair": world.test_teleport("station_repair", PI * 0.5)
		"tp_dealer": world.test_teleport("station_dealer", PI, Vector3(0, 0, 3.0))
		"tp_stationview": world.test_teleport("station_fuel", -PI * 0.5, Vector3(-30, 0, 4))
		"damage": 
			world.player_car.damage = 0.6
			world.player_car.apply_damage_visuals()
		"fuel_low": world.player_car.fuel = 0.15
		"refuel_ui": open_refuel()
		"repair_ui": open_repair()
		"fill_start": (screen as RefuelUI)._toggle()
		"fill_stop": (screen as RefuelUI)._stop()
		"repair_go": (screen as RepairUI)._repair()
		"fly": world.test_fly = Vector3(0, 0, 45)
		"fly_stop": world.test_fly = Vector3.ZERO
		"prof_reset":
			world.streamer.prof_inst.clear()
			world.streamer.prof_build.clear()
			_ft_max = 0.0
			_ft_over = 0
		"prof_report":
			var pa: Array = _ph_add.duplicate()
			pa.sort()
			var pi: Array = _ph_idle.duplicate()
			pi.sort()
			print("PHYS frames with chunk add: n=%d avg=%.2f max=%.2f | idle frames: n=%d avg=%.2f p99=%.2f max=%.2f" % [pa.size(), _avg(pa), (pa.back() if pa.size() > 0 else 0.0), pi.size(), _avg(pi), (pi[int(pi.size() * 0.99)] if pi.size() > 0 else 0.0), (pi.back() if pi.size() > 0 else 0.0)])
			var a: Array = world.streamer.prof_inst
			var b: Array = world.streamer.prof_build
			var sa: Array = a.duplicate()
			sa.sort()
			print("PROF chunks=%d inst avg=%.2f p95=%.2f max=%.2f | build avg=%.1f max=%.1f | worst frame=%.1f ms frames>33ms=%d" % [a.size(), _avg(a), (sa[int(sa.size() * 0.95)] if sa.size() > 0 else 0.0), (sa.back() if sa.size() > 0 else 0.0), _avg(b), (b.max() if b.size() > 0 else 0.0), _ft_max, _ft_over])
		"m_settings": _on_settings_from_menu()
		"m_credits": _on_credits()
		"m_new": _on_new()
		"quit_menu": _quit_to_menu()
		"m_back": show_main_menu()
		"close": _close_screen()
		"buy_try": (screen as DealershipUI)._ask_buy()
		"buy_go": (screen as DealershipUI)._buy()
		"dsel": (screen as DealershipUI)._select("countach")
		"poor": Game.money = 20
		"rich": Game.money = 900000
		"garage": open_garage()
		"dealer": open_dealership()
		"map": open_map()
		"pause": open_pause()
		"settings": open_settings()
		"exit": world.try_exit_vehicle()
		"close": _close_screen()
		"wanted3": world.police.set_heat_level(3)
		"wanted5": world.police.set_heat_level(5)
		"storm": world.env.set_weather("storm", true)
		"lightcount":
			var cnt: Dictionary = {}
			for l in get_tree().root.find_children("*", "Light3D", true, false):
				if (l as Light3D).is_visible_in_tree() and (l as Light3D).light_energy > 0.0:
					var dd: float = (l as Node3D).global_position.distance_to(world.player_car.global_position)
					if dd < 80.0:
						var k: String = "%s %s" % [l.get_class(), str(l.get_parent().name)]
						cnt[k] = int(cnt.get(k, 0)) + 1
			print("LIGHTS ", cnt)
		"rain": world.env.set_weather("heavy_rain", true)
		"night": world.env.hour = 22.0
		"lights": world.player_car.set_headlights(true)
		"lights_off": world.player_car.set_headlights(false)
		"dry": world.env.set_weather("clear", true)
		"mission": world.missions.begin(world.missions.defs[0])
		"race": world.missions._launch(world.missions.def_by_id("s2_first_race"))
		"drag": world.missions._launch(world.missions.def_by_id("s4_kane_drag"))
		"deliv": world.missions._launch(world.missions.def_by_id("s1_parts_run"))
		"escape": world.missions._launch(world.missions.def_by_id("p1_escape"))
		"mreport": print("MISSION ", world.missions.hud_info(), " opp=", world.missions.opp.size(), " route=", world.missions.route.size())
		"preport": print("POLICE lvl=%d units=%d heat=%.2f near=%.0f heli=%s blocks=%d" % [world.police.level, world.police.units.size(), world.police.heat, world.police.nearest_cop, world.police.heli != null, world.police.roadblocks.size()])
		"cam": world.cam.cycle_mode()
		"crash_pole": _crash_test("pole", 25.0)
		"crash_tree": _crash_test("tree", 25.0)
		"crash_building": _crash_test("building", 25.0)
		"crash_rail": _crash_test("rail", 20.0)
		"crash_slow": _crash_test("pole", 6.0)
		"crash_fast": _crash_test("pole", 45.0)
		"crash_traffic": _crash_test_traffic(25.0)
		"crash_report": _crash_report()
		"tilt_on": Game.settings["tilt_steer"] = true
		"tilt_off": Game.settings["tilt_steer"] = false
		"tilt_cal":
			world.tilt.override_gravity = Vector3(0, -9.8, 0)
			world.tilt_recalibrate()
		"tilt_r": world.tilt.override_gravity = Vector3(9.8 * sin(deg_to_rad(20)), -9.8 * cos(deg_to_rad(20)), 0)
		"tilt_l": world.tilt.override_gravity = Vector3(-9.8 * sin(deg_to_rad(20)), -9.8 * cos(deg_to_rad(20)), 0)
		"tilt_n": world.tilt.override_gravity = Vector3(0, -9.8, 0)
		"tilt_flat": world.tilt.override_gravity = Vector3(0, -0.3, -9.8)
		"restart":
			world.shutdown_session()
			_start(false)
		"tilt_report": print("TILT out=%.3f car_steer_cur=%.3f car_steering=%.3f active=%s" % [world.tilt.output, world.player_car.steer_cur, world.player_car.steering, world.tilt_active()])
		"wheel_report": _wheel_report()
		"brake": Input.action_press("brake")
		"nobrake": Input.action_release("brake")
		"right": Input.action_press("steer_right", 0.4)
		"nosteer":
			Input.action_release("steer_left")
			Input.action_release("steer_right")
		"gas": Input.action_press("accelerate")
		"left": Input.action_press("steer_left", 0.4)
		"nogas": Input.action_release("accelerate")
		"interact": world.do_interact()
		"takecar":
			world.take_airport_car()
			print("TAKECAR mode=%s vid=%s pos=%s" % [world.mode, world.player_car.vid if world.player_car else "-", str(world.player_car.global_position) if world.player_car else "-"])
		"npcreport":
			print("NPC peds=%d (edge=%d zone=%d pool=%d) dogs=%d birds=%d scale=%.1f/%.1f" % [world.peds.peds.size(), world.peds.peds.filter(func(q): return q["kind"] == "edge").size(), world.peds.peds.filter(func(q): return q["kind"] == "zone").size(), world.peds.pool.size(), world.fauna.dogs.size(), world.fauna.birds.size(), world.peds.limit_scale, world.fauna.limit_scale])
		"sigreport":
			var tm: TrafficManager = world.traffic
			var ln: Array = tm.light_nodes.keys()
			print("SIGNALS nodes=%d poles=%d first=%s" % [ln.size(), tm.lens_map.size(), str(world.gen.nodes[ln[0]]) if ln.size() > 0 else "-"])
			var near: Array = []
			for nid in ln:
				var q: Vector3 = world.gen.nodes[nid]
				if absf(q.x) < 200.0 and absf(q.z) < 200.0:
					near.append(q)
			print("SIGNEAR ", near)
		"report": _report()
		"save": Game.save_game()
		"econ":
			Game.money = 900000
			Game.rep = 2000
			print("BUY ", Game.buy_vehicle("apex_z"), " ", Game.buy_vehicle("dune_runner"))
			print("UPG ", Game.buy_upgrade("apex_z", "engine"), " ", Game.buy_custom("apex_z", "paint", 5))
			Game.selected = "apex_z"
			world.apply_custom_to_car()
			print("SEL ", world.player_car.vid, " top=", world.player_car.stats["top"])
			Game.sell_vehicle("dune_runner")
		"tpcp": world.player_car.global_position = world.missions.active["cps"][world.missions.active["cp"]] + Vector3(0, 1.5, 0)
		"stats": print("STATS money=%d rep=%d story=%d done=%s" % [Game.money, Game.rep, Game.story_stage, Game.missions_done.keys()])

# ---------------------------------------------------------------- screens
func _set_screen(c: Control, kind: String) -> void:
	if screen:
		screen.queue_free()
	screen = c
	screen_kind = kind
	ui_root.add_child(c)
	get_tree().paused = true
	hud.hud_visible = kind in ["dialog"]
	world.ui_blocking(true)
	if touch:
		touch._release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _close_screen() -> void:
	if screen:
		screen.queue_free()
		screen = null
	screen_kind = ""
	if not back_stack.is_empty():
		var cb: Callable = back_stack.pop_back()
		cb.call()
		return
	get_tree().paused = false
	hud.hud_visible = true
	world.ui_blocking(false)
	_apply_mouse_mode()

func _close_all() -> void:
	back_stack.clear()
	_close_screen()

func open_pause() -> void:
	if screen != null or not world.running:
		return
	var p: Control = Menus.pause_menu(world, _close_all, func() -> void:
		back_stack.append(open_pause)
		open_map(), func() -> void:
		back_stack.append(open_pause)
		open_settings(), func() -> void:
		Game.save_game()
		Game.notify.emit("Game saved", "good"), func() -> void:
		world.missions.abandon()
		_close_all(), _quit_to_menu)
	_set_screen(p, "pause")

func _quit_to_menu() -> void:
	Game.save_game()
	_close_all()
	world.shutdown_session()
	in_game = false
	hud.visible = false
	show_main_menu()

func open_map() -> void:
	if screen != null and screen_kind != "pause":
		return
	var m := MapScreen.new()
	m.world = world
	m.closed.connect(_close_screen)
	_set_screen(m, "map")

func open_settings() -> void:
	var s := SettingsMenu.new()
	s.closed.connect(_close_screen)
	_set_screen(s, "settings")

func open_garage() -> void:
	if screen != null:
		return
	world._sync_state()
	var g := GarageUI.new()
	g.world = world
	g.closed.connect(func() -> void:
		var changed: bool = Game.selected != world.player_car.vid or true
		_close_all()
		world.apply_custom_to_car())
	_set_screen(g, "garage")
	Game.save_game()

func open_dealership() -> void:
	if screen != null:
		return
	world._sync_state()
	var d := DealershipUI.new()
	d.world = world
	d.closed.connect(func() -> void:
		_close_all()
		world.apply_custom_to_car())
	_set_screen(d, "dealership")

func open_refuel() -> void:
	if screen != null or world.player_car == null:
		return
	var d := RefuelUI.new()
	d.world = world
	d.closed.connect(_close_all)
	_set_screen(d, "refuel")

func open_repair() -> void:
	if screen != null or world.player_car == null:
		return
	var d := RepairUI.new()
	d.world = world
	d.closed.connect(_close_all)
	_set_screen(d, "repair")

func show_dialog(char_id: String, lines: Array, on_done: Callable) -> void:
	var d: Control = Menus.dialog(char_id, lines, func() -> void:
		get_tree().paused = false
		hud.hud_visible = true
		world.ui_blocking(false)
		screen = null
		screen_kind = ""
		if on_done.is_valid():
			on_done.call())
	_set_screen(d, "dialog")

func show_result(success: bool, title: String, lines: Array, giver: String, outro: Array) -> void:
	var r: Control = Menus.result(success, title, lines, func() -> void:
		_close_all()
		if outro.size() > 0:
			show_dialog(giver, outro, Callable()))
	_set_screen(r, "result")

func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("pause") and screen != null and screen_kind in ["pause", "map", "settings"]:
		_close_screen()
		get_viewport().set_input_as_handled()

func _wheel_report() -> void:
	var car: Vehicle = world.player_car
	var names: Array = ["FL", "FR", "RL", "RR"]
	var parts: Array = []
	for i in range(car.wheels.size()):
		var w: VehicleWheel3D = car.wheels[i]
		var vis: Node3D = car.wheel_visuals[i]
		var local: Vector3 = car.global_transform.affine_inverse() * vis.global_position
		var q := PhysicsRayQueryParameters3D.create(vis.global_position + Vector3(0, 0.2, 0), vis.global_position + Vector3(0, -3.0, 0), 1)
		var hit: Dictionary = car.get_world_3d().direct_space_state.intersect_ray(q)
		var gap: float = (vis.global_position.y - float(car.spec["wr"])) - float(hit["position"].y) if not hit.is_empty() else 99.0
		parts.append("%s rpm=%.0f steer=%.2f contact=%s tyre-to-road gap=%.3f m vis_local=(%.2f,%.2f,%.2f)" % [names[i], w.get_rpm(), w.steering, w.is_in_contact(), gap, local.x, local.y, local.z])
	print("WHEELS vid=%s speed=%.1f km/h y=%.2f | %s" % [car.vid, car.abs_speed * 3.6, car.global_position.y, " | ".join(parts)])

func _report() -> void:
	if screen is GarageUI:
		var sr: Showroom = (screen as GarageUI).showroom
		print("SHOWROOM size=%s vp=%s car=%s visible=%s cam=%s" % [sr.size, sr.vp.size, sr.car_root, sr.visible, sr.cam.global_position])
	var v: Vehicle = world.player_car
	print("REPORT mode=%s running=%s pos=%s speed=%.1f kmh chunks=%d traffic=%d police=%d peds=%d fps=%d" % [world.mode, world.running, world.player_pos().snapped(Vector3.ONE), (v.abs_speed * 3.6 if v else 0.0), world.streamer.get_child_count(), world.traffic.cars.size(), world.police.units.size(), world.peds.peds.size(), Engine.get_frames_per_second()])

# ---------------------------------------------------------------- crash test hooks (automated testing)
var _ct_target: Vector3 = Vector3.ZERO
var _ct_start_dmg: float = 0.0
var _ct_kind: String = ""
var _ct_v0: float = 0.0

func _crash_test(kind: String, speed: float) -> void:
	var car: Vehicle = world.player_car
	var best: Vector3 = Vector3.ZERO
	var bd: float = 1e9
	var pp: Vector3 = car.global_position
	for body in get_tree().get_nodes_in_group("structure"):
		for c in body.get_children():
			if not (c is CollisionShape3D) or not (c.shape is BoxShape3D):
				continue
			var sz: Vector3 = (c.shape as BoxShape3D).size
			var ok: bool = false
			match kind:
				"pole": ok = sz.x < 0.4 and sz.y > 5.0 and sz.y < 6.0
				"tree": ok = sz.x > 0.4 and sz.x < 2.5 and sz.y > 3.5 and sz.y < 8.0 and absf(sz.x - sz.z) < 0.01
				"building": ok = sz.x > 8.0 and sz.z > 8.0 and sz.y > 10.0
				"rail": ok = sz.y < 1.5 and sz.x < 0.5
			if ok:
				var gp: Vector3 = (c as CollisionShape3D).global_position
				var d: float = gp.distance_to(pp)
				if d < bd and d > 20.0:
					bd = d
					best = gp
	if bd > 1e8:
		print("CRASHTEST %s: no target found" % kind)
		return
	_ct_target = best
	_ct_kind = kind
	var start: Vector3 = best + Vector3(0, 0, 40.0)
	var gy: float = world.gen.ground_h(start.x, start.z)
	car.place_on_ground(Vector3(start.x, gy, start.z), 0.0)
	car.linear_velocity = Vector3(0, 0, -speed)
	car.prev_vel = car.linear_velocity
	car.repair_full()
	_ct_start_dmg = 0.0
	_ct_v0 = speed
	Input.action_press("accelerate")
	print("CRASHTEST %s at %s start speed %.0f m/s" % [kind, best.snapped(Vector3.ONE * 0.1), speed])

func _crash_test_traffic(speed: float) -> void:
	var car: Vehicle = world.player_car
	if world.traffic.cars.is_empty():
		print("CRASHTEST traffic: no traffic cars")
		return
	var tc: Node3D = world.traffic.cars[0]
	var behind: Vector3 = tc.global_position + tc.global_transform.basis.z * 30.0
	car.place_on_ground(behind, tc.rotation.y)
	car.linear_velocity = -car.global_transform.basis.z * speed
	car.prev_vel = car.linear_velocity
	car.repair_full()
	_ct_kind = "traffic"
	_ct_v0 = speed
	print("CRASHTEST traffic start")

func _crash_report() -> void:
	var car: Vehicle = world.player_car
	var d: float = car.global_position.distance_to(_ct_target) if _ct_target != Vector3.ZERO else -1.0
	print("CRASHRESULT kind=%s v0=%.0f speed_now=%.1f dmg=%.3f last_impact=%.1f dist_to_target=%.1f lamps_broken=%s wrecked=%s" % [_ct_kind, _ct_v0, car.abs_speed, car.damage, car.last_impact, d, car.lamps_broken, car.wrecked])
	Input.action_release("accelerate")

var _ft_max: float = 0.0
var _last_inst: int = 0
var _ph_add: Array = []
var _ph_idle: Array = []
var _log_spikes: bool = OS.get_cmdline_user_args().has("--spikes")
var _ft_over: int = 0

func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t: float = 0.0
	for x in a:
		t += float(x)
	return t / float(a.size())
