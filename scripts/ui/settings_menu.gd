class_name SettingsMenu
extends Control
## Graphics presets + individual options, audio mixer, key remapping, gameplay.

signal closed

var tab: String = "graphics"
var content: VBoxContainer
var tab_btns: Dictionary = {}
var waiting_action: String = ""
var wait_btn: Button = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.82)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 620)
	center.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	v.add_child(UIKit.title_bar("SETTINGS"))
	var tabs := HBoxContainer.new()
	v.add_child(tabs)
	for t in [["graphics", "Graphics"], ["audio", "Audio"], ["controls", "Controls"], ["gameplay", "Gameplay"]]:
		var b: Button = UIKit.button(t[1], _set_tab.bind(t[0]), 50)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
		tab_btns[t[0]] = b
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sc: ScrollContainer = UIKit.scroll(content, Vector2(860, 400))
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	v.add_child(UIKit.accent_button("Back", _close, 56))
	_build()

func _close() -> void:
	Game.save_settings_only()
	closed.emit()

func _set_tab(t: String) -> void:
	tab = t
	_build()

func _build() -> void:
	waiting_action = ""
	for k in tab_btns:
		(tab_btns[k] as Button).disabled = k == tab
	UIKit.clear(content)
	match tab:
		"graphics": _graphics()
		"audio": _audio()
		"controls": _controls()
		"gameplay": _gameplay()

func _row(label: String, ctrl: Control, hint: String = "") -> void:
	var h := HBoxContainer.new()
	var l: Label = UIKit.label(label, 21)
	l.custom_minimum_size = Vector2(300, 0)
	h.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctrl)
	if hint != "":
		var hl: Label = UIKit.label(hint, 15, UIKit.MUTED)
		hl.custom_minimum_size = Vector2(160, 0)
		h.add_child(hl)
	content.add_child(h)

func _slider(key: String, lo: float, hi: float, step: float, as_pct: bool = false) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Game.settings.get(key, lo))
	s.custom_minimum_size = Vector2(300, 40)
	s.value_changed.connect(func(v: float) -> void: Game.set_setting(key, v))
	return s

func _toggle(key: String) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = bool(Game.settings.get(key, false))
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(on: bool) -> void: Game.set_setting(key, on))
	return c

func _choice(key: String, options: Array, labels: Array) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(240, 46)
	for i in options.size():
		o.add_item(labels[i], i)
		if options[i] == Game.settings.get(key):
			o.select(i)
	o.item_selected.connect(func(i: int) -> void: Game.set_setting(key, options[i]))
	return o

func _graphics() -> void:
	var q := OptionButton.new()
	q.custom_minimum_size = Vector2(240, 46)
	var presets: Array = ["Low", "Medium", "High", "Ultra"]
	for i in presets.size():
		q.add_item(presets[i], i)
	q.add_item("Custom", 4)
	var cur: int = presets.find(String(Game.settings.get("quality", "Medium")))
	q.select(cur if cur >= 0 else 4)
	q.item_selected.connect(func(i: int) -> void:
		if i < 4:
			Game.set_quality(presets[i])
			_build())
	_row("Quality preset", q, "Low is best for phones")
	_row("Shadows", _toggle("shadows"))
	_row("Reflections / glow", _toggle("reflections"))
	_row("Anti-aliasing (0 / 2 / 4)", _slider("aa", 0, 4, 2))
	_row("View distance (chunks)", _slider("view_distance", 2, 5, 1), "More = slower")
	_row("Render scale", _slider("res_scale", 0.5, 1.0, 0.05), "Lower = faster")
	_row("Traffic density", _slider("traffic_density", 0.0, 1.4, 0.1))
	_row("VSync", _toggle("vsync"))
	if not Game.is_mobile:
		_row("Fullscreen", _toggle("fullscreen"))

func _audio() -> void:
	_row("Master", _slider("master", 0.0, 1.0, 0.05))
	_row("Music", _slider("music", 0.0, 1.0, 0.05))
	_row("Engine", _slider("engine", 0.0, 1.0, 0.05))
	_row("Environment", _slider("environment", 0.0, 1.0, 0.05))
	_row("Effects", _slider("effects", 0.0, 1.0, 0.05))

func _controls() -> void:
	_row("Steering sensitivity", _slider("steer_sens", 0.5, 1.5, 0.05))
	_row("Camera sensitivity", _slider("camera_sens", 0.3, 2.0, 0.1))
	_row("Mouse sensitivity (on foot)", _slider("mouse_sens", 0.3, 2.0, 0.1))
	if Game.is_mobile or true:
		_row("Tilt steering (phone)", _toggle("tilt_steer"))
		_row("Invert tilt", _toggle("tilt_invert"))
		_row("Touch button opacity", _slider("touch_opacity", 0.2, 1.0, 0.05))
		_row("Show touch controls", _toggle("show_touch"), "for desktop testing")
		_row("Vibration", _toggle("haptics"))
	content.add_child(UIKit.spacer(6))
	content.add_child(UIKit.label("Key bindings - click a button, then press a key", 18, UIKit.MUTED))
	for a in Game.REMAPPABLE:
		var b: Button = UIKit.button(Game.key_name(a), Callable(), 44, 200)
		b.pressed.connect(_begin_remap.bind(a, b))
		_row(String(a).replace("_", " ").capitalize(), b)
	content.add_child(UIKit.button("Reset keys to defaults", func() -> void:
		Game.settings["keys"] = {}
		Game._setup_input()
		_build(), 46))

func _begin_remap(a: String, b: Button) -> void:
	waiting_action = a
	wait_btn = b
	b.text = "Press a key..."

func _input(ev: InputEvent) -> void:
	if waiting_action == "" or not (ev is InputEventKey) or not ev.pressed:
		return
	var k: InputEventKey = ev
	get_viewport().set_input_as_handled()
	if k.physical_keycode == KEY_ESCAPE:
		waiting_action = ""
		_build()
		return
	Game.remap(waiting_action, k.physical_keycode)
	waiting_action = ""
	_build()

func _gameplay() -> void:
	_row("Handling model", _choice("handling", ["arcade", "sim"], ["Arcade (assists on)", "Simulation"]))
	_row("Speed units", _choice("units", ["kmh", "mph"], ["km/h", "mph"]))
	_row("Minimap size", _slider("minimap_size", 0.7, 1.4, 0.1))
	_row("Minimap rotates with camera", _toggle("minimap_rotate"))
	_row("Camera distance", _slider("cam_distance", 0.7, 1.5, 0.1))
	_row("Camera shake", _toggle("cam_shake"))
	_row("Auto headlights at night", _toggle("headlights_auto"))
