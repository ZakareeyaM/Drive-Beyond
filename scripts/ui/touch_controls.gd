class_name TouchControls
extends Control
## Multitouch on-screen controls for Android. Hit-tests in _input so several
## fingers (steer + gas + handbrake ...) work at once, and feeds the normal
## InputMap actions so the rest of the game needs no touch-specific code.

var world: World
var font: Font
var fingers: Dictionary = {}       # index -> {kind, action, origin, pos}
var btns: Array = []
var joy_origin: Vector2 = Vector2.ZERO
var joy_vec: Vector2 = Vector2.ZERO
var joy_finger: int = -1
var look_last: Dictionary = {}
var pulse: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = ThemeDB.fallback_font
	_layout()
	get_viewport().size_changed.connect(_layout)

func enabled() -> bool:
	return Game.is_mobile or bool(Game.settings.get("show_touch", false))

func _layout() -> void:
	var vs: Vector2 = get_viewport_rect().size
	var w: float = vs.x
	var h: float = vs.y
	btns = [
		# driving
		{"id": "steer_left", "a": "steer_left", "r": Rect2(24, h - 190, 160, 170), "t": "◀", "mode": "drive", "shape": "rect"},
		{"id": "steer_right", "a": "steer_right", "r": Rect2(196, h - 190, 160, 170), "t": "▶", "mode": "drive", "shape": "rect"},
		{"id": "gas", "a": "accelerate", "r": Rect2(w - 200, h - 250, 176, 230), "t": "GAS", "mode": "drive", "shape": "rect"},
		{"id": "brake", "a": "brake", "r": Rect2(w - 380, h - 190, 168, 170), "t": "BRAKE", "mode": "drive", "shape": "rect"},
		{"id": "hb", "a": "handbrake", "c": Vector2(w - 330, h - 250), "rad": 46.0, "t": "HB", "mode": "drive", "shape": "circle"},
		{"id": "nitro", "a": "nitro", "c": Vector2(w - 440, h - 235), "rad": 42.0, "t": "N2O", "mode": "drive", "shape": "circle"},
		{"id": "cam", "a": "camera", "c": Vector2(w - 52, 300), "rad": 34.0, "t": "CAM", "mode": "drive", "shape": "circle"},
		{"id": "lights", "a": "headlights", "c": Vector2(w - 52, 372), "rad": 34.0, "t": "LGT", "mode": "drive", "shape": "circle"},
		{"id": "horn", "a": "horn", "c": Vector2(w - 52, 444), "rad": 34.0, "t": "HORN", "mode": "drive", "shape": "circle"},
		{"id": "reset", "a": "reset_car", "c": Vector2(w - 130, 444), "rad": 30.0, "t": "RST", "mode": "drive", "shape": "circle"},
		{"id": "tilt", "a": "", "c": Vector2(w - 52, 156), "rad": 30.0, "t": "TILT", "mode": "drive", "shape": "circle"},
		{"id": "cal", "a": "", "c": Vector2(w - 130, 156), "rad": 30.0, "t": "CAL", "mode": "drive", "shape": "circle", "tilt_only": true},
		{"id": "exit", "a": "exit_vehicle", "c": Vector2(w - 130, 372), "rad": 30.0, "t": "EXIT", "mode": "drive", "shape": "circle"},
		# on foot
		{"id": "jump", "a": "jump", "c": Vector2(w - 110, h - 130), "rad": 54.0, "t": "JUMP", "mode": "foot", "shape": "circle"},
		{"id": "sprint", "a": "sprint", "c": Vector2(w - 250, h - 100), "rad": 44.0, "t": "RUN", "mode": "foot", "shape": "circle"},
		# both
		{"id": "interact", "a": "interact", "c": Vector2(w - 270, 290), "rad": 52.0, "t": "USE", "mode": "both", "shape": "circle", "needs_prompt": true},
		{"id": "map", "a": "map", "c": Vector2(w - 52, 228), "rad": 30.0, "t": "MAP", "mode": "both", "shape": "circle"},
		{"id": "pause", "a": "pause", "c": Vector2(w * 0.5 - 250, 40), "rad": 28.0, "t": "II", "mode": "both", "shape": "circle"},
	]

func _active(b: Dictionary) -> bool:
	var m: String = String(b["mode"])
	if m == "drive" and world.mode != "drive":
		return false
	if m == "foot" and world.mode != "foot":
		return false
	if b.get("needs_prompt", false) and world.prompt_text == "":
		return false
	if b["id"] == "nitro" and not (world.player_car and world.player_car.has_nitro):
		return false
	if b["id"] == "exit" and world.player_car and world.player_car.abs_speed > 4.0:
		return false
	if bool(Game.settings.get("tilt_steer", false)) and b["id"] in ["steer_left", "steer_right"]:
		return false
	if b.get("tilt_only", false) and not bool(Game.settings.get("tilt_steer", false)):
		return false
	return true

func _hit(b: Dictionary, p: Vector2) -> bool:
	if b["shape"] == "rect":
		return (b["r"] as Rect2).grow(10.0).has_point(p)
	return p.distance_to(b["c"]) < float(b["rad"]) + 14.0

func _release_all() -> void:
	for k in fingers.keys():
		_release(k)
	for a in ["steer_left", "steer_right", "accelerate", "brake", "handbrake", "nitro", "foot_left", "foot_right", "foot_forward", "foot_back", "sprint", "jump", "horn"]:
		Input.action_release(a)
	joy_finger = -1
	joy_vec = Vector2.ZERO

func _release(idx: int) -> void:
	var f: Dictionary = fingers.get(idx, {})
	if f.is_empty():
		return
	if f["kind"] == "btn":
		Input.action_release(f["action"])
	elif f["kind"] == "joy":
		for a in ["foot_left", "foot_right", "foot_forward", "foot_back", "sprint"]:
			Input.action_release(a)
		joy_finger = -1
		joy_vec = Vector2.ZERO
	fingers.erase(idx)

func _input(ev: InputEvent) -> void:
	if not enabled() or world == null or not world.running or world.ui_open:
		return
	if ev is InputEventScreenTouch:
		var t: InputEventScreenTouch = ev
		if t.pressed:
			_press(t.index, t.position)
		else:
			_release(t.index)
	elif ev is InputEventScreenDrag:
		var d: InputEventScreenDrag = ev
		var f: Dictionary = fingers.get(d.index, {})
		if f.is_empty():
			return
		if f["kind"] == "joy":
			var v: Vector2 = (d.position - f["origin"]) / 70.0
			if v.length() > 1.0:
				v = v.normalized()
			joy_vec = v
			_apply_joy()
		elif f["kind"] == "look":
			world.apply_look(d.relative.x * 1.3, d.relative.y * 1.3)

func _press(idx: int, p: Vector2) -> void:
	for b in btns:
		if not _active(b):
			continue
		if _hit(b, p):
			if b["id"] == "tilt":
				Game.set_setting("tilt_steer", not bool(Game.settings.get("tilt_steer", false)))
				world.tilt_recalibrate()
				Input.action_release("steer_left")
				Input.action_release("steer_right")
				Game.notify.emit("Tilt steering " + ("ON" if bool(Game.settings.get("tilt_steer", false)) else "OFF"), "info")
				fingers[idx] = {"kind": "tap"}
				return
			if b["id"] == "cal":
				world.tilt_recalibrate()
				Game.notify.emit("Tilt calibrated - hold phone as you want 'straight'", "good")
				fingers[idx] = {"kind": "tap"}
				return
			fingers[idx] = {"kind": "btn", "action": b["a"]}
			Input.action_press(b["a"], 1.0)
			if b["id"] == "interact":
				pass
			return
	if world.mode == "foot" and p.x < get_viewport_rect().size.x * 0.45 and p.y > 160.0:
		fingers[idx] = {"kind": "joy", "origin": p}
		joy_origin = p
		joy_finger = idx
		joy_vec = Vector2.ZERO
		return
	if p.y < get_viewport_rect().size.y * 0.62:
		fingers[idx] = {"kind": "look"}

func _apply_joy() -> void:
	var v: Vector2 = joy_vec
	Input.action_press("foot_right" if v.x > 0.0 else "foot_left", absf(v.x))
	Input.action_release("foot_left" if v.x > 0.0 else "foot_right")
	Input.action_press("foot_back" if v.y > 0.0 else "foot_forward", absf(v.y))
	Input.action_release("foot_forward" if v.y > 0.0 else "foot_back")
	if v.length() > 0.95:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")

func _process(delta: float) -> void:
	pulse += delta
	var show: bool = enabled() and world != null and world.running and not world.ui_open
	if visible != show:
		visible = show
		if not show:
			_release_all()
	if show:
		queue_redraw()

func _draw() -> void:
	if world == null:
		return
	var op: float = float(Game.settings.get("touch_opacity", 0.75))
	for b in btns:
		if not _active(b):
			continue
		var held: bool = false
		for f in fingers.values():
			if f["kind"] == "btn" and f["action"] == b["a"]:
				held = true
		var base: Color = Color(1, 1, 1, 0.14 * op + (0.18 if held else 0.0))
		var border: Color = Color(UIKit.RED.r, UIKit.RED.g, UIKit.RED.b, 0.8 * op)
		if b["id"] == "interact":
			border = Color(1, 1, 1, (0.6 + 0.4 * sin(pulse * 6.0)) * op)
		var label_col := Color(1, 1, 1, 0.9 * op)
		if b["shape"] == "rect":
			var r: Rect2 = b["r"]
			draw_rect(r, base)
			draw_rect(r, border, false, 3.0)
			draw_string(font, r.position + Vector2(0, r.size.y * 0.5 + 12), String(b["t"]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 34 if b["id"] in ["steer_left", "steer_right"] else 26, label_col)
		else:
			var c: Vector2 = b["c"]
			draw_circle(c, float(b["rad"]), base)
			draw_arc(c, float(b["rad"]), 0.0, TAU, 32, border, 3.0, true)
			draw_string(font, c + Vector2(-float(b["rad"]), 7), String(b["t"]), HORIZONTAL_ALIGNMENT_CENTER, float(b["rad"]) * 2.0, 18, label_col)
	if bool(Game.settings.get("tilt_steer", false)) and world.mode == "drive":
		var by: float = get_viewport_rect().size.y - 60.0
		var bx: float = 190.0
		draw_rect(Rect2(bx - 140, by - 6, 280, 12), Color(1, 1, 1, 0.14 * op))
		draw_rect(Rect2(bx - 2, by - 14, 4, 28), Color(1, 1, 1, 0.5 * op))
		draw_circle(Vector2(bx + world.tilt.output * 140.0, by), 14.0, Color(UIKit.RED.r, UIKit.RED.g, UIKit.RED.b, 0.85 * op))
		draw_string(font, Vector2(bx - 140, by - 24), "TILT STEERING" if world.tilt.has_sensor else "NO TILT SENSOR", HORIZONTAL_ALIGNMENT_LEFT, 280, 16, Color(1, 1, 1, 0.6 * op))
	if joy_finger >= 0:
		draw_circle(joy_origin, 70.0, Color(1, 1, 1, 0.1 * op))
		draw_arc(joy_origin, 70.0, 0.0, TAU, 40, Color(1, 1, 1, 0.4 * op), 3.0, true)
		draw_circle(joy_origin + joy_vec * 70.0, 28.0, Color(UIKit.RED.r, UIKit.RED.g, UIKit.RED.b, 0.7 * op))
	elif world.mode == "foot":
		draw_string(font, Vector2(40, get_viewport_rect().size.y - 60), "Touch left side to move   |   drag right side to look", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.5 * op))
