class_name Menus
extends RefCounted
## Builders for the small full-screen overlays: main menu, pause, credits,
## dialogue, mission result and loading screen. Each returns a Control.

static func _center_panel(min_w: float) -> Array:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(cc)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(min_w, 0)
	cc.add_child(pc)
	var v := VBoxContainer.new()
	pc.add_child(v)
	return [bg, v]

# ---------------------------------------------------------------- main menu
static func main_menu(on_continue: Callable, on_new: Callable, on_settings: Callable, on_credits: Callable, on_quit: Callable) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.0)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var grad := TextureRect.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0, 0, 0, 0.88), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.45, 0.85])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	gt.width = 256
	gt.height = 4
	grad.texture = gt
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(grad)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 70)
	m.add_theme_constant_override("margin_top", 36)
	m.add_theme_constant_override("margin_bottom", 24)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(420, 0)
	v.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	m.add_child(v)
	# landscape: one-line title so the button stack fits on a 16:9 / 20:9 screen
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 16)
	title_row.add_child(UIKit.label("DRIVE", 64, Color.WHITE))
	title_row.add_child(UIKit.label("BEYOND", 64, UIKit.RED))
	v.add_child(title_row)
	v.add_child(UIKit.label("Explore. Drive. Survive.", 26, UIKit.MUTED))
	v.add_child(UIKit.spacer(8))
	if Game.has_save:
		v.add_child(UIKit.accent_button("Continue", on_continue, 52, 400))
	v.add_child(UIKit.accent_button("New Game" if not Game.has_save else "New Game (overwrites save)", on_new, 52, 400) if not Game.has_save else UIKit.button("New Game", on_new, 52, 400))
	v.add_child(UIKit.button("Settings", on_settings, 52, 400))
	v.add_child(UIKit.button("Credits", on_credits, 52, 400))
	if not Game.is_mobile and not OS.has_feature("web"):
		v.add_child(UIKit.button("Quit", on_quit, 52, 400))
	var ver := UIKit.label("v1.0   |   Godot 4  |  all assets procedural", 15, UIKit.MUTED)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	v.add_child(ver)
	return root

# ---------------------------------------------------------------- pause
static func pause_menu(world: World, on_resume: Callable, on_map: Callable, on_settings: Callable, on_save: Callable, on_abandon: Callable, on_quit: Callable) -> Control:
	var arr: Array = _center_panel(520)
	var bg: Control = arr[0]
	var v: VBoxContainer = arr[1]
	v.add_child(UIKit.title_bar("PAUSED"))
	v.add_child(UIKit.accent_button("Resume", on_resume, 58))
	v.add_child(UIKit.button("Map & Missions", on_map, 54))
	v.add_child(UIKit.button("Settings", on_settings, 54))
	v.add_child(UIKit.button("Save Game", on_save, 54))
	if world.missions and not world.missions.active.is_empty():
		v.add_child(UIKit.button("Abandon Mission", on_abandon, 54))
	v.add_child(UIKit.button("Quit to Main Menu", on_quit, 54))
	v.add_child(UIKit.spacer(6))
	var st: Dictionary = Game.stats
	var mins: int = int(float(st["play_time"]) / 60.0)
	v.add_child(UIKit.label("Played %dh %02dm   |   Driven %s   |   Races won %d" % [mins / 60, mins % 60, Game.dist_label(float(st["distance"])), int(st["races_won"])], 16, UIKit.MUTED))
	v.add_child(UIKit.label("Missions completed %d   |   Packages %d / 20   |   Discovered %d" % [Game.missions_done.size(), Game.collectibles.size(), Game.discovered.size()], 16, UIKit.MUTED))
	return bg

static func credits(on_back: Callable) -> Control:
	var arr: Array = _center_panel(760)
	var v: VBoxContainer = arr[1]
	v.add_child(UIKit.title_bar("CREDITS"))
	var txt: Array = ["DRIVE BEYOND", "Design, code and every asset generated procedurally in Godot 4 (GDScript).",
		"No third-party art, audio or models are used: vehicles, world, textures, shaders and music are created in code.",
		"", "Built for Zak (ZakareeyaM)", "", "Explore. Drive. Survive."]
	for t in txt:
		v.add_child(UIKit.label(t, 20, UIKit.TEXT if t != "" else UIKit.MUTED, 1))
	v.add_child(UIKit.accent_button("Back", on_back, 56))
	return arr[0]

# ---------------------------------------------------------------- dialogue
class DialogBox extends Control:
	var lines: Array = []
	var idx: int = 0
	var char_id: String = "rico"
	var on_done: Callable
	var name_l: Label
	var role_l: Label
	var text_l: Label
	var shown: float = 0.0
	var finished: bool = false

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		process_mode = Node.PROCESS_MODE_ALWAYS
		var p := PanelContainer.new()
		p.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		p.offset_left = 120
		p.offset_right = -120
		p.offset_top = -230
		p.offset_bottom = -30
		var ch: Dictionary = Data.CHARACTERS.get(char_id, Data.CHARACTERS["rico"])
		var col: Color = ch["color"]
		p.add_theme_stylebox_override("panel", UIKit.box(Color(0.03, 0.03, 0.05, 0.96), 12, col, 3, 22))
		add_child(p)
		var v := VBoxContainer.new()
		p.add_child(v)
		name_l = UIKit.label(String(ch["name"]).to_upper(), 28, col)
		v.add_child(name_l)
		role_l = UIKit.label(String(ch["role"]), 16, UIKit.MUTED)
		v.add_child(role_l)
		text_l = UIKit.label("", 24)
		text_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_l.custom_minimum_size = Vector2(900, 70)
		v.add_child(text_l)
		var hint := UIKit.label("Tap / press E to continue", 15, UIKit.MUTED, 2)
		v.add_child(hint)
		_show_line()

	func _show_line() -> void:
		text_l.text = String(lines[idx])
		text_l.visible_characters = 0
		shown = 0.0

	func _process(delta: float) -> void:
		shown += delta * 55.0
		text_l.visible_characters = int(shown)

	func _advance() -> void:
		if text_l.visible_characters < text_l.text.length():
			shown = 9999.0
			return
		idx += 1
		if idx >= lines.size():
			if not finished:
				finished = true
				queue_free()
				if on_done.is_valid():
					on_done.call()
			return
		_show_line()

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_advance()
			accept_event()

	func _unhandled_key_input(ev: InputEvent) -> void:
		if ev.is_action_pressed("interact") or (ev is InputEventKey and ev.pressed and ev.physical_keycode == KEY_ENTER):
			_advance()
			get_viewport().set_input_as_handled()

static func dialog(char_id: String, lines: Array, on_done: Callable) -> Control:
	var d := DialogBox.new()
	d.char_id = char_id
	d.lines = lines
	d.on_done = on_done
	d.mouse_filter = Control.MOUSE_FILTER_STOP
	return d

static func result(success: bool, title: String, lines: Array, on_ok: Callable) -> Control:
	var arr: Array = _center_panel(620)
	var v: VBoxContainer = arr[1]
	var head: Label = UIKit.label("MISSION COMPLETE" if success else "MISSION FAILED", 44, UIKit.GREEN if success else Color(1, 0.3, 0.3), 1)
	v.add_child(head)
	v.add_child(UIKit.label(title, 26, UIKit.TEXT, 1))
	v.add_child(UIKit.spacer(8))
	for l in lines:
		v.add_child(UIKit.label(String(l), 22, UIKit.GOLD if String(l).begins_with("Reward") else UIKit.TEXT, 1))
	v.add_child(UIKit.spacer(10))
	v.add_child(UIKit.accent_button("Continue", on_ok, 58))
	return arr[0]

# ---------------------------------------------------------------- loading
class LoadingScreen extends Control:
	var bar: ProgressBar
	var lbl: Label
	var tip: Label
	const TIPS := ["Hold the handbrake into corners to start a drift.", "Rain and gravel reduce grip - brake earlier.",
		"Fill up at yellow gas station beacons.", "Escape the police by breaking line of sight.",
		"Upgrades in the garage change your real stats.", "Red beacons mark the garage; blue marks the dealership.",
		"Hidden packages are scattered around the map.", "Press the map button to set a GPS route."]

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var bg := ColorRect.new()
		bg.color = Color(0.02, 0.02, 0.03)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
		var cc := CenterContainer.new()
		cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(cc)
		var v := VBoxContainer.new()
		v.custom_minimum_size = Vector2(620, 0)
		cc.add_child(v)
		v.add_child(UIKit.label("DRIVE BEYOND", 64, Color.WHITE, 1))
		v.add_child(UIKit.label("Explore. Drive. Survive.", 22, UIKit.RED, 1))
		v.add_child(UIKit.spacer(20))
		bar = UIKit.bar(0.0, UIKit.RED, 620.0, 10.0)
		v.add_child(bar)
		lbl = UIKit.label("Loading", 20, UIKit.MUTED, 1)
		v.add_child(lbl)
		tip = UIKit.label(TIPS[randi() % TIPS.size()], 18, UIKit.TEXT, 1)
		v.add_child(UIKit.spacer(14))
		v.add_child(tip)

	func set_progress(f: float, text: String) -> void:
		bar.value = f * 100.0
		lbl.text = text
