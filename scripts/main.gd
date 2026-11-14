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
	if c.begins_with("lapsim_"):   # test: lapsim_<a|b>_<ok|reverse|skip|stand|twice>  - simulates a car passing the gates, prints money before/after
		var lv: PackedStringArray = c.substr(7).split("_")
		_lap_sim(lv[0], lv[1])
		return
	if c.begins_with("rayprobe_"):   # test: rayprobe_<x>_<z>  prints every collision hit below y+10 at a 2 m grid (5x5)
		var rv: PackedStringArray = c.substr(9).split("_")
		var ss: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
		for ix in range(-2, 3):
			var line: String = ""
			for iz in range(-2, 3):
				var o := Vector3(float(rv[0]) + ix * 2.0, 30.0, float(rv[1]) + iz * 2.0)
				var excl: Array = []
				var hs: String = ""
				for k in range(4):
					var rq2 := PhysicsRayQueryParameters3D.create(o, o + Vector3(0, -40, 0), 1, excl)
					var h2: Dictionary = ss.intersect_ray(rq2)
					if h2.is_empty():
						break
					hs += "%.2f(%s) " % [(h2["position"] as Vector3).y, str(h2["collider"].name).left(6)]
					excl.append(h2["rid"])
				line += "[" + hs + "] "
			print("RAYP ", line)
		return
	if c.begins_with("hray_"):   # test: hray_<x0>_<z>_<y>  horizontal rays towards +X from x0 (lists up to 6 hits: x, collider, normal)
		var hv: PackedStringArray = c.substr(5).split("_")
		var sp3: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
		var org := Vector3(float(hv[0]), float(hv[2]), float(hv[1]))
		var ex2: Array = []
		for k in range(6):
			var q3 := PhysicsRayQueryParameters3D.create(org, org + Vector3(60, 0, 0), 0xFFFFFFFF, ex2)
			var h3: Dictionary = sp3.intersect_ray(q3)
			if h3.is_empty():
				break
			print("HRAY z=%s y=%s hit x=%.2f %s n=%s" % [hv[1], hv[2], (h3["position"] as Vector3).x, str(h3["collider"].name), str(h3["normal"])])
			ex2.append(h3["rid"])
		return
	if c.begins_with("dropcar_"):   # test: dropcar_<x>_<z>  lowers the player car from 3 m above the circuit and prints where it settles
		var dv: PackedStringArray = c.substr(8).split("_")
		world.player_car.place_on_ground(Vector3(float(dv[0]), 13.5, float(dv[1])), 0.0)
		for k in range(6):
			await get_tree().create_timer(0.4).timeout
			print("DROPCAR t=%.1f y=%.2f vy=%.2f" % [0.4 * (k + 1), world.player_car.global_position.y, world.player_car.linear_velocity.y])
		return
	if c.begins_with("indshot_"):   # test: indshot_<l|r>_<name>_<dx>_<dy>_<dz>  indicator on (lit phase), debug camera at car-local offset looking at the car, screenshot
		var iv: PackedStringArray = c.substr(8).split("_")
		var ic: Vehicle = world.player_car
		ic.set_indicator(1 if iv[0] == "l" else 2)
		var cam3 := get_node_or_null("DebugCam") as Camera3D
		if cam3 == null:
			cam3 = Camera3D.new()
			cam3.name = "DebugCam"
			cam3.far = 3000.0
			add_child(cam3)
		cam3.global_position = ic.global_transform * Vector3(float(iv[2]), float(iv[3]), float(iv[4]))
		cam3.look_at(ic.global_transform * Vector3(0, 0.5, 0), Vector3.UP)
		cam3.fov = 40.0
		cam3.current = true
		await get_tree().process_frame
		ic._ind_t = 0.0
		ic._refresh_indicator()
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("/tmp/gd/ind_%s.png" % iv[1])
		return
	if c == "camtest":   # test: drives the car through speed camera 0 twice at 45 m/s and prints the money change
		var sc0: Vector3 = world.gen.speed_cameras[0]
		var m0: int = Game.money
		var cv: Vehicle = world.player_car
		for pass_i in range(2):
			cv.place_on_ground(Vector3(sc0.x - 8.0, sc0.y + 0.5, sc0.z), -PI * 0.5)
			cv.linear_velocity = Vector3(45.0, 0, 0)
			await get_tree().create_timer(0.35).timeout
			print("CAMTEST pass %d: money %d -> %d (delta %d) latched=%s" % [pass_i + 1, m0, Game.money, Game.money - m0, str(world.speed_cam_latched.keys())])
			cv.linear_velocity = Vector3(45.0, 0, 0)
			await get_tree().create_timer(0.3).timeout
			print("CAMTEST still inside: delta %d" % (Game.money - m0))
			cv.place_on_ground(Vector3(sc0.x + 60.0, sc0.y + 0.5, sc0.z), -PI * 0.5)
			await get_tree().create_timer(0.6).timeout
		return
	if c == "revgo":
		Input.action_press("brake")
	if c == "revdbg" or c == "revgo":   # test: prints reverse-beep player state (playing?, signed speed, number of beeper nodes in the tree) 16 times
		for k in range(16):
			await get_tree().create_timer(0.5).timeout
			var rv: Vehicle = world.player_car
			if c == "revgo" and k == 10:
				Input.action_release("brake")
				Input.action_press("accelerate")
			if c == "revgo" and k == 13:
				Input.action_release("accelerate")
			print("REV t=%.1f in_brake=%.2f act=%.2f rvsng=%s speed=%.2f playing=%s beepers=%d mode=%s" % [0.5 * (k + 1), rv.in_brake, Input.get_action_strength("brake"), str(rv.reversing), rv.speed, str(world.audio.rev_player != null and world.audio.rev_player.playing), get_tree().root.find_children("ReverseBeep", "AudioStreamPlayer3D", true, false).size(), world.mode])
		return
	if c.begins_with("surf_"):   # test: surf_<x>_<z>_<yawdeg>  teleports the car, full throttle for 6 s, prints surface / speed / grip / drag every second
		var sv: PackedStringArray = c.substr(5).split("_")
		var sx: float = float(sv[0])
		var sz: float = float(sv[1])
		world.player_car.place_on_ground(Vector3(sx, world.gen.ground_h(sx, sz) + 1.0, sz), deg_to_rad(float(sv[2])))
		world.player_car.linear_velocity = Vector3.ZERO
		world.cam.snap()
		Input.action_press("accelerate")
		for k in range(6):
			await get_tree().create_timer(1.0).timeout
			var sc2: Vehicle = world.player_car
			print("SURF t=%d pos=(%.0f,%.0f) surface=%s on_road=%s speed=%.1f grip=%.2f drag=%.2f dmg=%.2f air=%.2f" % [k + 1, sc2.global_position.x, sc2.global_position.z, sc2.surface, str(sc2.on_road), sc2.abs_speed, sc2.surf_grip, sc2.surf_drag, sc2.damage, sc2.airborne_time])
		Input.action_release("accelerate")
		return
	if c == "hltest":   # test: headlight state across the day, manual toggle, rain, vehicle switch; prints HL lines
		var pc: Vehicle = world.player_car
		var rep := func(tag: String) -> void:
			var v: Vehicle = world.player_car
			var vis: int = 0
			var en: float = -1.0
			for sp in v._spot:
				if (sp as SpotLight3D).visible:
					vis += 1
				en = (sp as SpotLight3D).light_energy
			print("HL %-22s hour=%5.2f night=%s on=%s user=%d spots=%d energy=%.1f fill=%s head_mat=%.2f veh=%s" % [tag, world.env.hour, str(world.env.is_night()), str(v.headlights_on), v.headlights_user, vis, en, str(v._fill != null and v._fill.visible), (v.model.get("head_mat") as StandardMaterial3D).emission_energy_multiplier if v.model.get("head_mat") else -1.0, v.vid])
		for h in [9.0, 18.0, 18.9, 19.7, 20.9, 21.2, 22.0, 23.5, 1.0, 4.5, 6.2, 7.0]:
			world.env.hour = h
			await get_tree().create_timer(0.4).timeout
			rep.call("auto h=%.1f" % h)
		world.env.hour = 22.0
		await get_tree().create_timer(0.4).timeout
		Input.action_press("headlights"); await get_tree().create_timer(0.1).timeout; Input.action_release("headlights")
		await get_tree().create_timer(0.4).timeout
		rep.call("manual OFF at 22h")
		Input.action_press("headlights"); await get_tree().create_timer(0.1).timeout; Input.action_release("headlights")
		await get_tree().create_timer(0.4).timeout
		rep.call("manual ON at 22h")
		world.env.set_weather("heavy_rain", true)
		await get_tree().create_timer(0.6).timeout
		rep.call("heavy rain 22h")
		world.env.hour = 12.0
		await get_tree().create_timer(0.5).timeout
		rep.call("noon (rain, flip day)")
		world.env.hour = 21.5
		await get_tree().create_timer(0.5).timeout
		rep.call("21.5 rain")
		world.player_car.damage = 0.0
		return
	if c.begins_with("gtest_"):   # test: gtest_<x>_<z>_<yaw>  drive from there with full throttle, 0.15 s log of position / speed / touched bodies until it stops
		var gv: PackedStringArray = c.substr(6).split("_")
		var gx: float = float(gv[0])
		var gz: float = float(gv[1])
		world.player_car.place_on_ground(Vector3(gx, world.gen.ground_h(gx, gz) + 1.0, gz), deg_to_rad(float(gv[2])))
		world.player_car.linear_velocity = Vector3.ZERO
		world.cam.snap()
		Input.action_press("accelerate")
		var stopped: int = 0
		for k in range(90):
			await get_tree().create_timer(0.15).timeout
			var gc: Vehicle = world.player_car
			var names: String = ""
			for b in gc.get_colliding_bodies():
				names += "%s(%s) " % [str(b.name), str((b as Node3D).global_position.snapped(Vector3.ONE * 0.1)) if b is Node3D else ""]
			if gc.abs_speed > 1.5 or names != "":
				print("GT t=%.2f pos=(%.2f,%.2f,%.2f) speed=%.1f dmg=%.2f touch=%s" % [0.15 * (k + 1), gc.global_position.x, gc.global_position.y, gc.global_position.z, gc.abs_speed, gc.damage, names])
			if gc.abs_speed < 0.3 and k > 8:
				stopped += 1
				if stopped > 3:
					break
		Input.action_release("accelerate")
		return
	if c.begins_with("perf_"):   # test: perf_<fwd|rev|idle|map>[_seconds]  frame-cost profile (script process / physics ms, frame ms, nodes, draw calls) printed per second
		var pv: PackedStringArray = c.substr(5).split("_")
		var pmode: String = pv[0]
		var psec: int = int(pv[1]) if pv.size() > 1 else 6
		var pcar: Vehicle = world.player_car
		if pmode == "fwd":
			Input.action_press("accelerate")
		elif pmode == "rev":
			Input.action_press("brake")
		for sec in range(psec):
			var n: int = 0
			var tp_sum: float = 0.0
			var tp_max: float = 0.0
			var ph_sum: float = 0.0
			var ph_max: float = 0.0
			var fr_max: float = 0.0
			var t_end: int = Time.get_ticks_usec() + 1000000
			var t_prev: int = Time.get_ticks_usec()
			while Time.get_ticks_usec() < t_end:
				await get_tree().process_frame
				var tn: int = Time.get_ticks_usec()
				fr_max = maxf(fr_max, float(tn - t_prev) / 1000.0)
				t_prev = tn
				var tp: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
				var ph: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
				tp_sum += tp; tp_max = maxf(tp_max, tp)
				ph_sum += ph; ph_max = maxf(ph_max, ph)
				n += 1
			print("PERF %s t=%d frames=%d process avg=%.2f max=%.2f ms | physics avg=%.2f max=%.2f ms | frame max=%.1f ms | nodes=%d objects=%d draws=%d prims=%d bodies=%d spd=%.1f" % [pmode, sec + 1, n, tp_sum / maxf(1.0, n), tp_max, ph_sum / maxf(1.0, n), ph_max, fr_max, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_COUNT)), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)), world.player_car.speed])
		Input.action_release("accelerate")
		Input.action_release("brake")
		return
	if c == "mapperf":   # test: opens / closes the map 5 times and prints the cost of each open (call ms), first draw, steady redraw cost (script ms) and node / object counts
		for i in range(5):
			var t0: int = Time.get_ticks_usec()
			var nodes0: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			open_map()
			var t1: int = Time.get_ticks_usec()
			await get_tree().process_frame
			var t2: int = Time.get_ticks_usec()
			# steady cost of one redraw of the map (what a pan / zoom pays per frame)
			var rd: float = 0.0
			var mp: MapScreen = screen as MapScreen
			for k in range(10):
				var t3: int = Time.get_ticks_usec()
				mp.notification(CanvasItem.NOTIFICATION_DRAW)
				rd += float(Time.get_ticks_usec() - t3) / 1000.0
			var t4: int = Time.get_ticks_usec()
			_close_screen()
			await get_tree().process_frame
			print("MAPPERF open#%d call=%.1f ms first_frame=%.1f ms redraw(script only)=%.2f ms close=%.1f ms nodes +%d objects=%d" % [i + 1, float(t1 - t0) / 1000.0, float(t2 - t1) / 1000.0, rd / 10.0, float(Time.get_ticks_usec() - t4) / 1000.0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - nodes0, int(Performance.get_monitor(Performance.OBJECT_COUNT))])
		return
	if c == "streamprof":   # test: drives 12 s at full throttle from the current spot and prints chunk build (worker) / instantiate (main thread) cost
		var st: TerrainStreamer = world.streamer
		st.prof_inst.clear()
		st.prof_build.clear()
		Input.action_press("accelerate")
		await get_tree().create_timer(12.0).timeout
		Input.action_release("accelerate")
		var pi: Array = st.prof_inst.duplicate()
		var pb: Array = st.prof_build.duplicate()
		pi.sort()
		pb.sort()
		if pi.is_empty():
			print("STREAM no chunks loaded")
		else:
			print("STREAM chunks=%d  main-thread instantiate ms: avg=%.2f median=%.2f p90=%.2f max=%.2f | worker build ms: avg=%.1f max=%.1f" % [pi.size(), _avg(pi), pi[pi.size() / 2], pi[int(pi.size() * 0.9)], pi[pi.size() - 1], _avg(pb), pb[pb.size() - 1]])
		return
	if c == "buytest":   # test: sci-fi buggy purchase rules (insufficient funds, success, repeated press, persistence)
		var id2: String = "scifi_buggy"
		var price: int = int(Data.vehicle(id2)["price"])
		Game.owned.erase(id2)
		Game.money = price - 1
		var r1: bool = Game.buy_vehicle(id2)
		print("BUY insufficient: result=%s money=%d owned=%s (expect false, %d, false)" % [str(r1), Game.money, str(Game.owned.has(id2)), price - 1])
		Game.money = price + 5000
		var r2: bool = Game.buy_vehicle(id2)
		var r3: bool = Game.buy_vehicle(id2)
		print("BUY success+repeat: first=%s repeat=%s money=%d owned=%s (expect true,false,5000,true)" % [str(r2), str(r3), Game.money, str(Game.owned.has(id2))])
		print("BUY dune owned from start=%s free=%s sell dune=%s sell scifi=%s" % [str(Game.owned.has("dune_buggy")), str(Data.is_free_vehicle("dune_buggy")), str(Game.sell_vehicle("dune_buggy")), str(Game.sell_vehicle(id2))])
		Game.save_game()
		Game.owned.clear()
		Game.load_game()
		print("BUY after save/load: scifi=%s dune=%s money=%d" % [str(Game.owned.has(id2)), str(Game.owned.has("dune_buggy")), Game.money])
		return
	if c == "kdbg":   # test: print the player car state 20 times, 0.25 s apart
		for k in range(20):
			await get_tree().create_timer(0.25).timeout
			var vv: Vehicle = world.player_car
			print("KD t=%.2f pos=%s speed=%.2f rot=%s fuel=%.2f" % [0.25 * (k + 1), str(vv.global_position), vv.speed, str(vv.rotation_degrees.snapped(Vector3.ONE * 0.1)), vv.fuel])
		return
	if c == "dropball":   # test: sphere + box dropped on track A near the kart spot; prints resting heights
		for kind in ["sphere", "box"]:
			var rb := RigidBody3D.new()
			rb.collision_layer = 2
			rb.collision_mask = 1 | 2
			var csn := CollisionShape3D.new()
			if kind == "sphere":
				var sh := SphereShape3D.new()
				sh.radius = 0.3
				csn.shape = sh
			else:
				var bx := BoxShape3D.new()
				bx.size = Vector3(1.2, 0.3, 1.6)
				csn.shape = bx
			rb.add_child(csn)
			world.add_child(rb)
			rb.global_position = Vector3(1770.0 if kind == "sphere" else 1790.0, 14.0, 1498.6)
			await get_tree().create_timer(2.0).timeout
			print("DROP %s rests at y=%.2f" % [kind, rb.global_position.y])
		return
	if c.begins_with("kart_"):     # test: kart_<take|return>_<a|b>
		var kv2: PackedStringArray = c.substr(5).split("_")
		var rt: RaceTracks = world.race_tracks
		if kv2[0] == "take":
			var ks: Dictionary = rt.kart_spot(kv2[1])
			var hp: Vector3 = ks["pos"] + Vector3(-4.0, 0.0, 12.0)
			world.player_car.place_on_ground(Vector3(hp.x, ks["pos"].y + 0.3, hp.z), 0.0)
			world.player_car.linear_velocity = Vector3.ZERO
			await get_tree().create_timer(1.0).timeout
			var home_id: String = world.player_car.vid
			var hf: float = world.player_car.fuel
			world.take_kart(kv2[1])
			for dbg in range(24):
				await get_tree().create_timer(0.15).timeout
				var kc: Vehicle = world.player_car
				var rq := PhysicsRayQueryParameters3D.create(kc.global_position + Vector3(0, 8, 0), kc.global_position + Vector3(0, -8, 0), 1, [kc.get_rid()])
				var rh: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(rq)
				print("KDBG pos=%s vel=%s rot=%s speed=%.2f" % [str(kc.global_position), str(kc.linear_velocity), str(kc.rotation_degrees), kc.abs_speed])
			print("KART take: mode=%s car=%s kart_pos=%s home=%s fuel=%.2f loan=%s" % [world.mode, world.player_car.vid, str(world.player_car.global_position), home_id, hf, str(not world.kart_loan.is_empty())])
		else:
			var hm: Vehicle = world.kart_loan["home"]
			var hdm: float = hm.damage
			var hfl: float = hm.fuel
			var hps: Vector3 = hm.global_position
			world.return_kart()
			await get_tree().create_timer(0.5).timeout
			print("KART return: car=%s same=%s pos_moved=%.2f fuel_same=%s dmg_same=%s loan=%s players=%d" % [world.player_car.vid, str(world.player_car == hm), world.player_car.global_position.distance_to(hps), str(is_equal_approx(hfl, world.player_car.fuel)), str(is_equal_approx(hdm, world.player_car.damage)), str(not world.kart_loan.is_empty()), get_tree().get_nodes_in_group("player_vehicle").size()])
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


func _lap_sim(id: String, mode: String) -> void:
	var rt: RaceTracks = world.race_tracks
	var n: int = int(rt.tracks[id]["gates"])
	var m0: int = Game.money
	var car: Vehicle = world.player_car
	var order: Array = range(n)
	var seq: Array = []        # sequence of gate indices passed, forward direction
	match mode:
		"ok": seq = order + [0]
		"twice": seq = order + [0] + range(1, n) + [0]
		"skip": seq = [0, 1] + range(3, n) + [0]
		"reverse": seq = [0] + range(1, n) + [0]
		"stand": seq = [0]
	rt._have_prev = false
	var t_orig: float = 0.0
	# start the run away from the line so the first update only records the position
	var pos_prev := Vector3.ZERO
	for gi in seq:
		var g: Dictionary = rt._gate_world(id, gi)
		var gp: Vector3 = g["p"]
		var d: Vector2 = g["d"]
		var dir := Vector3(d.x, 0.0, d.y)
		if mode == "reverse":
			dir = -dir
		# approach 6 m before, cross to 6 m after in 2 m steps
		var q0: Vector3 = gp + dir * -6.0
		q0.y = world.gen.ground_h(q0.x, q0.z) + 0.6
		rt._prev_pos = q0     # the car drove the stretch between gates (no jump): only the gate crossing itself is simulated
		rt._have_prev = true
		for k in range(-2, 4):
			var q: Vector3 = gp + dir * (float(k) * 2.0)
			q.y = world.gen.ground_h(q.x, q.z) + 0.6
			rt.update(0.016, q, true)
		if mode == "stand":
			for k in range(40):
				rt.update(0.016, gp - dir * 0.2, true)
		rt.tracks[id]["t0"] = float(Time.get_ticks_msec()) / 1000.0 - 100.0 if gi != 0 else rt.tracks[id]["t0"]
	print("LAPSIM %s %s: laps=%d money %d -> %d (delta %d)" % [id, mode, int(rt.tracks[id]["laps"]), m0, Game.money, Game.money - m0])
