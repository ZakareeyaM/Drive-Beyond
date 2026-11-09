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
## Main menu: centred title / subtitle / button stack over the MenuBackground scene.  Everything is laid out with
## containers and sized from the viewport (re-laid-out on resize), so it adapts to any landscape resolution.
static func main_menu(on_continue: Callable, on_new: Callable, on_settings: Callable, on_credits: Callable, on_quit: Callable) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# soft darkening at the top/bottom so the white title and the footer stay readable on the bright sky/water
	var tint := TextureRect.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.02, 0.06, 0.14, 0.38), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0.0, 0.04, 0.1, 0.35)])
	g.offsets = PackedFloat32Array([0.0, 0.28, 0.72, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 128
	tint.texture = gt
	tint.stretch_mode = TextureRect.STRETCH_SCALE
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tint)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(v)
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t1: Label = UIKit.label("DRIVE", 64, Color.WHITE)
	var t2: Label = UIKit.label("BEYOND", 64, Color(0.88, 0.12, 0.2))
	for t in [t1, t2]:
		t.add_theme_constant_override("outline_size", 6)
		t.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.12, 0.55))
		t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
		t.add_theme_constant_override("shadow_offset_y", 3)
		title_row.add_child(t)
	v.add_child(title_row)
	var sub: Label = UIKit.label("Explore. Drive. Survive.", 26, Color(0.93, 0.95, 1.0, 0.9), 1)
	sub.add_theme_constant_override("outline_size", 5)
	sub.add_theme_color_override("font_outline_color", Color(0.02, 0.06, 0.14, 0.6))
	v.add_child(sub)
	var gap := Control.new()
	v.add_child(gap)
	var buttons: Array = []
	if Game.has_save:
		buttons.append(_menu_button("Continue", on_continue, true))
		buttons.append(_menu_button("New Game", on_new, false))
	else:
		buttons.append(_menu_button("New Game", on_new, true))
	buttons.append(_menu_button("Settings", on_settings, false))
	buttons.append(_menu_button("Credits", on_credits, false))
	if not Game.is_mobile and not OS.has_feature("web"):
		buttons.append(_menu_button("Quit", on_quit, false))
	for b in buttons:
		v.add_child(b)
	var ver := UIKit.label("Drive Beyond  |  Godot 4", 15, Color(0.92, 0.95, 1.0, 0.6), 1)
	ver.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	ver.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.offset_bottom = -10
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ver)
	# responsive sizing: everything derives from the viewport height / width
	var relayout := func() -> void:
		var sz: Vector2 = root.size
		if sz.x < 10.0 or sz.y < 10.0:
			return
		var h: float = sz.y
		var tsize: int = int(clampf(h * 0.105, 34.0, 92.0))
		t1.add_theme_font_size_override("font_size", tsize)
		t2.add_theme_font_size_override("font_size", tsize)
		title_row.add_theme_constant_override("separation", int(tsize * 0.28))
		sub.add_theme_font_size_override("font_size", int(clampf(h * 0.04, 16.0, 34.0)))
		var bw: float = clampf(sz.x * 0.29, 250.0, 520.0)
		var bh: float = clampf(h * 0.085, 46.0, 72.0)
		var fs: int = int(clampf(bh * 0.4, 18.0, 28.0))
		var sep: int = int(bh * 0.14)
		v.add_theme_constant_override("separation", sep)
		gap.custom_minimum_size = Vector2(0, h * 0.02)
		for b2 in buttons:
			var bb: Button = b2
			bb.custom_minimum_size = Vector2(bw, bh)
			bb.add_theme_font_size_override("font_size", fs)
		ver.add_theme_font_size_override("font_size", int(clampf(h * 0.028, 12.0, 18.0)))
	root.resized.connect(relayout)
	root.ready.connect(relayout)
	return root

static func _menu_button(text: String, cb: Callable, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if cb.is_valid():
		b.pressed.connect(cb)
	var base: Color = Color(0.54, 0.03, 0.08, 0.97) if primary else Color(0.09, 0.09, 0.14, 0.93)
	var hover: Color = Color(0.72, 0.06, 0.12, 1.0) if primary else Color(0.17, 0.18, 0.26, 0.97)
	var pressed: Color = Color(0.4, 0.02, 0.06, 1.0) if primary else Color(0.05, 0.05, 0.09, 1.0)
	var rim: Color = Color(1, 1, 1, 0.85) if primary else Color(1, 1, 1, 0.12)
	b.add_theme_stylebox_override("normal", UIKit.box(base, 9, rim, 1, 18))
	b.add_theme_stylebox_override("hover", UIKit.box(hover, 9, Color(1, 1, 1, 0.9) if primary else Color(1, 1, 1, 0.35), 2 if not primary else 1, 18))
	b.add_theme_stylebox_override("pressed", UIKit.box(pressed, 9, Color(1, 1, 1, 0.7), 1, 18))
	b.add_theme_stylebox_override("focus", UIKit.box(Color(0, 0, 0, 0), 9, Color(1, 1, 1, 0.8), 2, 18))
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.85))
	return b

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
	var txt: Array = ["DRIVE BEYOND", "Design and code in Godot 4 (GDScript). World, many vehicles, shaders and music are generated in code.",
		"Imported 3D models: BMW M6, traffic-pack cars, city/apartment buildings and the petrol station (see assets/).",
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
