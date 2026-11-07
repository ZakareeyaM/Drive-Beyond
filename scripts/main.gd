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
		"map": open_map, "pause": open_pause, "garage": open_garage, "dealership": open_dealership,
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
	menu_root = Menus.main_menu(_on_continue, _on_new, _on_settings_from_menu, _on_credits, _on_quit)
	ui_root.add_child(menu_root)
	get_tree().paused = false

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
	if c.begins_with("shot_"):
		get_viewport().get_texture().get_image().save_png("/tmp/gd/ui_%s.png" % c.substr(5))
		return
	match c:
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
		"rain": world.env.set_weather("heavy_rain", true)
		"night": world.env.hour = 22.0
		"mission": world.missions.begin(world.missions.defs[0])
		"race": world.missions._launch(world.missions.def_by_id("s2_first_race"))
		"drag": world.missions._launch(world.missions.def_by_id("s4_kane_drag"))
		"deliv": world.missions._launch(world.missions.def_by_id("s1_parts_run"))
		"escape": world.missions._launch(world.missions.def_by_id("p1_escape"))
		"mreport": print("MISSION ", world.missions.hud_info(), " opp=", world.missions.opp.size(), " route=", world.missions.route.size())
		"preport": print("POLICE lvl=%d units=%d heat=%.2f near=%.0f heli=%s blocks=%d" % [world.police.level, world.police.units.size(), world.police.heat, world.police.nearest_cop, world.police.heli != null, world.police.roadblocks.size()])
		"cam": world.cam.cycle_mode()
		"gas": Input.action_press("accelerate")
		"left": Input.action_press("steer_left", 0.4)
		"nogas": Input.action_release("accelerate")
		"interact": world.do_interact()
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

func _report() -> void:
	if screen is GarageUI:
		var sr: Showroom = (screen as GarageUI).showroom
		print("SHOWROOM size=%s vp=%s car=%s visible=%s cam=%s" % [sr.size, sr.vp.size, sr.car_root, sr.visible, sr.cam.global_position])
	var v: Vehicle = world.player_car
	print("REPORT mode=%s running=%s pos=%s speed=%.1f kmh chunks=%d traffic=%d police=%d peds=%d fps=%d" % [world.mode, world.running, world.player_pos().snapped(Vector3.ONE), (v.abs_speed * 3.6 if v else 0.0), world.streamer.get_child_count(), world.traffic.cars.size(), world.police.units.size(), world.peds.peds.size(), Engine.get_frames_per_second()])
