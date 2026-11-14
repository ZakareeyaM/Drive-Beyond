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
	# Layout follows the driving-HUD reference: pedals bottom-right, steering bottom-left,
	# two columns of round icon buttons on the right edge, pause top-centre.
	var cx2: float = w - 56.0      # outer column
	var cx1: float = w - 132.0     # inner column
	var r0: float = 180.0          # first row y (below the money / time block)
	var dy: float = 74.0
	var pw: float = clampf(w * 0.105, 130.0, 170.0)
	btns = [
		# driving: steering pads (hidden while tilt steering is on)
		{"id": "steer_left", "a": "steer_left", "r": Rect2(28, h - 176, 150, 150), "t": "", "mode": "drive", "shape": "rect"},
		{"id": "steer_right", "a": "steer_right", "r": Rect2(196, h - 176, 150, 150), "t": "", "mode": "drive", "shape": "rect"},
		# pedals
		{"id": "brake", "a": "brake", "r": Rect2(w - pw * 2.0 - 52.0, h - 190, pw, 170), "t": "BRAKE", "mode": "drive", "shape": "rect"},
		{"id": "gas", "a": "accelerate", "r": Rect2(w - pw - 28.0, h - 214, pw, 194), "t": "GAS", "mode": "drive", "shape": "rect"},
		# turn indicators: small buttons just above the two steering pads (clear of the pedals, the minimap and the round button columns)
		{"id": "ind_l", "a": "indicator_left", "c": Vector2(103.0, h - 214.0), "rad": 26.0, "t": "", "mode": "drive", "shape": "circle"},
		{"id": "ind_r", "a": "indicator_right", "c": Vector2(271.0, h - 214.0), "rad": 26.0, "t": "", "mode": "drive", "shape": "circle"},
		# round icon buttons (two columns)
		{"id": "cal", "a": "", "c": Vector2(cx1, r0), "rad": 32.0, "t": "CAL", "mode": "drive", "shape": "circle", "tilt_only": true},
		{"id": "tilt", "a": "", "c": Vector2(cx2, r0), "rad": 32.0, "t": "TILT", "mode": "drive", "shape": "circle"},
		{"id": "map", "a": "map", "c": Vector2(cx2, r0 + dy), "rad": 32.0, "t": "MAP", "mode": "both", "shape": "circle"},
		{"id": "cam", "a": "camera", "c": Vector2(cx2, r0 + dy * 2.0), "rad": 32.0, "t": "CAM", "mode": "drive", "shape": "circle"},
		{"id": "lights", "a": "headlights", "c": Vector2(cx1, r0 + dy * 3.0), "rad": 32.0, "t": "LGT", "mode": "drive", "shape": "circle"},
		{"id": "horn", "a": "horn", "c": Vector2(cx2, r0 + dy * 3.0), "rad": 32.0, "t": "HORN", "mode": "drive", "shape": "circle"},
		{"id": "hb", "a": "handbrake", "c": Vector2(cx1, r0 + dy * 4.0), "rad": 32.0, "t": "HB", "mode": "drive", "shape": "circle"},
		{"id": "exit", "a": "exit_vehicle", "c": Vector2(cx2, r0 + dy * 4.0), "rad": 32.0, "t": "EXIT", "mode": "drive", "shape": "circle"},
		{"id": "reset", "a": "reset_car", "c": Vector2(cx1, r0 + dy * 2.0), "rad": 26.0, "t": "RST", "mode": "drive", "shape": "circle"},
		{"id": "nitro", "a": "nitro", "c": Vector2(w - pw * 2.0 - 112.0, h - 110), "rad": 36.0, "t": "N2O", "mode": "drive", "shape": "circle"},
		# on foot
		{"id": "jump", "a": "jump", "c": Vector2(w - 110, h - 130), "rad": 54.0, "t": "JUMP", "mode": "foot", "shape": "circle"},
		{"id": "sprint", "a": "sprint", "c": Vector2(w - 250, h - 100), "rad": 44.0, "t": "RUN", "mode": "foot", "shape": "circle"},
		# both
		{"id": "interact", "a": "interact", "c": Vector2(w - pw * 2.0 - 112.0, h - 215), "rad": 48.0, "t": "USE", "mode": "both", "shape": "circle", "needs_prompt": true},
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
	if b["id"] in ["ind_l", "ind_r"] and not (world.player_car and bool(world.player_car.spec.get("kart", false))):
		return false     # turn indicators exist on the racing go-karts only
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
	for a in ["steer_left", "steer_right", "accelerate", "brake", "handbrake", "nitro", "foot_left", "foot_right", "foot_forward", "foot_back", "sprint", "jump", "horn", "indicator_left", "indicator_right"]:
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

const NAVY := Color(0.04, 0.07, 0.17)
const CYAN := Color(0.25, 0.8, 1.0)
const NEON_RED := Color(1.0, 0.15, 0.2)
const NEON_BLUE := Color(0.2, 0.55, 1.0)
var _sb: Dictionary = {}

func _box(fill: Color, border: Color, radius: int, bw: int, glow: float) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.border_color = border
	b.set_border_width_all(bw)
	b.set_corner_radius_all(radius)
	b.anti_aliasing = true
	if glow > 0.0:
		b.shadow_color = Color(border.r, border.g, border.b, 0.55)
		b.shadow_size = int(glow)
	return b

func _draw() -> void:
	if world == null:
		return
	var op: float = float(Game.settings.get("touch_opacity", 0.75))
	var a: float = clampf(0.45 + op * 0.55, 0.4, 1.0)
	for b in btns:
		if not _active(b):
			continue
		var held: bool = false
		for f in fingers.values():
			if f["kind"] == "btn" and f["action"] == b["a"]:
				held = true
		var id: String = String(b["id"])
		if b["shape"] == "rect":
			var r: Rect2 = b["r"]
			match id:
				"gas", "brake":
					_draw_pedal(r, id == "gas", held, a)
				_:
					_draw_steer_pad(r, id == "steer_left", held, a)
		else:
			var c: Vector2 = b["c"]
			var rad: float = float(b["rad"])
			var on: bool = (id == "tilt" and bool(Game.settings.get("tilt_steer", false))) or (id == "lights" and world.player_car != null and world.player_car.headlights_on) or (id == "ind_l" and world.player_car != null and world.player_car.indicator == 1) or (id == "ind_r" and world.player_car != null and world.player_car.indicator == 2)
			var border: Color = Color(0.9, 0.95, 1.0, 0.9 * a)
			if id == "interact":
				border = Color(1, 1, 1, (0.6 + 0.4 * sin(pulse * 6.0)) * a)
			elif id == "hb":
				border = Color(NEON_RED.r, NEON_RED.g, NEON_RED.b, 0.95 * a)
			elif on:
				border = Color(CYAN.r, CYAN.g, CYAN.b, a)
			var fill: Color = Color(NAVY.r, NAVY.g, NAVY.b, (0.8 if not held else 0.95) * a)
			if held:
				fill = Color(0.12, 0.2, 0.42, 0.95 * a)
			draw_style_box(_get_sb("c_%s_%s_%s" % [id, held, on], fill, border, int(rad), 2, 0.0 if not on else 6.0), Rect2(c - Vector2(rad, rad), Vector2(rad, rad) * 2.0))
			_draw_icon(id, c + Vector2(0, -rad * 0.2), rad * 0.46, Color(1, 1, 1, 0.95 * a), a)
			if id != "pause":
				draw_string(font, c + Vector2(-rad, rad * 0.62), String(b["t"]), HORIZONTAL_ALIGNMENT_CENTER, rad * 2.0, 11 if rad < 40.0 else 14, Color(1, 1, 1, 0.92 * a))
	if bool(Game.settings.get("tilt_steer", false)) and world.mode == "drive":
		_draw_tilt_slider(a)
	if joy_finger >= 0:
		draw_circle(joy_origin, 70.0, Color(1, 1, 1, 0.1 * op))
		draw_arc(joy_origin, 70.0, 0.0, TAU, 40, Color(1, 1, 1, 0.4 * op), 3.0, true)
		draw_circle(joy_origin + joy_vec * 70.0, 28.0, Color(CYAN.r, CYAN.g, CYAN.b, 0.7 * op))
	elif world.mode == "foot":
		draw_string(font, Vector2(40, get_viewport_rect().size.y - 60), "Touch left side to move   |   drag right side to look", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.5 * op))

func _get_sb(key: String, fill: Color, border: Color, radius: int, bw: int, glow: float) -> StyleBoxFlat:
	var k: String = "%s_%.2f" % [key, fill.a]
	if not _sb.has(k):
		_sb[k] = _box(fill, border, radius, bw, glow)
	return _sb[k]

func _draw_pedal(r: Rect2, is_gas: bool, held: bool, a: float) -> void:
	var neon: Color = NEON_BLUE if is_gas else NEON_RED
	var fill: Color = Color(0.05, 0.07, 0.16, (0.85 if not held else 0.98) * a)
	draw_style_box(_get_sb("pedal_%s_%s" % [is_gas, held], fill, Color(neon.r, neon.g, neon.b, a), 22, 3, 10.0 if held else 5.0), r)
	# ridged rubber pad
	var pad := Rect2(r.position + Vector2(r.size.x * 0.16, r.size.y * 0.1), Vector2(r.size.x * 0.68, r.size.y * 0.58))
	var n: int = 6
	for i in n:
		var yy: float = pad.position.y + pad.size.y * float(i) / float(n)
		var hh: float = pad.size.y / float(n) * 0.62
		var shade: float = 0.30 + 0.06 * float(i) + (0.18 if held else 0.0)
		draw_style_box(_get_sb("ridge_%d_%s" % [i, held], Color(shade, shade + 0.02, shade + 0.06, 0.95 * a), Color(0, 0, 0, 0), 4, 0, 0.0), Rect2(Vector2(pad.position.x, yy), Vector2(pad.size.x, hh)))
	draw_string(font, Vector2(r.position.x, r.end.y - r.size.y * 0.12), "GAS" if is_gas else "BRAKE", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, Color(1, 1, 1, a))

func _draw_steer_pad(r: Rect2, left: bool, held: bool, a: float) -> void:
	var fill: Color = Color(NAVY.r, NAVY.g, NAVY.b, (0.8 if not held else 0.97) * a)
	draw_style_box(_get_sb("pad_%s" % held, fill, Color(0.9, 0.95, 1.0, 0.9 * a), 30, 2, 0.0), r)
	var c: Vector2 = r.get_center()
	var d: float = -1.0 if left else 1.0
	var hs: float = r.size.x * 0.2
	var col := Color(1, 1, 1, 0.95 * a) if not held else Color(CYAN.r, CYAN.g, CYAN.b, a)
	draw_colored_polygon(PackedVector2Array([c + Vector2(d * hs, 0), c + Vector2(-d * hs * 0.6, -hs), c + Vector2(-d * hs * 0.6, hs)]), col)

func _draw_tilt_slider(a: float) -> void:
	var vs: Vector2 = get_viewport_rect().size
	var x0: float = 36.0
	var y: float = vs.y - 64.0
	var tw: float = 250.0
	draw_string(font, Vector2(x0 + 30.0, y - 14.0), "TILT STEERING" if world.tilt.has_sensor else "NO TILT SENSOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.9 * a))
	# steering-wheel icon
	var ic: Vector2 = Vector2(x0 + 11.0, y - 19.0)
	draw_arc(ic, 9.0, 0.0, TAU, 20, Color(1, 1, 1, 0.95 * a), 2.0, true)
	draw_line(ic + Vector2(-9, 0), ic + Vector2(9, 0), Color(1, 1, 1, 0.95 * a), 2.0)
	draw_line(ic, ic + Vector2(0, 9), Color(1, 1, 1, 0.95 * a), 2.0)
	draw_style_box(_get_sb("tilt_track", Color(1, 1, 1, 0.22 * a), Color(0, 0, 0, 0), 5, 0, 0.0), Rect2(x0, y - 5.0, tw, 10.0))
	draw_rect(Rect2(x0 + tw * 0.5 - 1.5, y - 11.0, 3.0, 22.0), Color(1, 1, 1, 0.8 * a))
	var tx: float = x0 + tw * 0.5 + world.tilt.output * tw * 0.5
	draw_circle(Vector2(tx, y), 13.0, Color(0.9, 0.92, 1.0, a))
	draw_circle(Vector2(tx, y), 13.0, Color(0, 0, 0, 0.15 * a), false, 1.5)

func _draw_icon(id: String, c: Vector2, s: float, col: Color, a: float) -> void:
	var w: float = 2.2
	match id:
		"ind_l", "ind_r":   # turn arrow
			var dir: float = -1.0 if id == "ind_l" else 1.0
			var amber := Color(1.0, 0.7, 0.1, 0.98 * a)
			var tip: Vector2 = c + Vector2(dir * s * 1.0, s * 0.2)
			draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-dir * s * 0.95, -s * 0.8), tip + Vector2(-dir * s * 0.95, s * 0.8)]), amber)
			draw_line(tip + Vector2(-dir * s * 0.9, 0), tip + Vector2(-dir * s * 1.6, 0), amber, w * 1.6)
		"cal":   # gear
			draw_arc(c, s * 0.62, 0.0, TAU, 20, col, w, true)
			draw_arc(c, s * 0.26, 0.0, TAU, 12, col, w, true)
			for i in 8:
				var an: float = TAU * float(i) / 8.0
				draw_line(c + Vector2(cos(an), sin(an)) * s * 0.62, c + Vector2(cos(an), sin(an)) * s * 0.98, col, w * 1.5)
		"tilt":  # phone tilted with arc
			var rot: float = 0.45
			var pts := PackedVector2Array()
			for q in [Vector2(-0.38, -0.7), Vector2(0.38, -0.7), Vector2(0.38, 0.7), Vector2(-0.38, 0.7), Vector2(-0.38, -0.7)]:
				pts.append(c + (q * s * 1.1).rotated(rot))
			draw_polyline(pts, col, w, true)
			draw_arc(c, s * 1.1, deg_to_rad(200), deg_to_rad(250), 8, col, w * 0.8, true)
		"map":   # pin
			draw_arc(c + Vector2(0, -s * 0.2), s * 0.55, deg_to_rad(-210), deg_to_rad(30), 16, col, w, true)
			draw_line(c + Vector2(-s * 0.48, s * 0.05), c + Vector2(0, s * 0.9), col, w)
			draw_line(c + Vector2(s * 0.48, s * 0.05), c + Vector2(0, s * 0.9), col, w)
			draw_circle(c + Vector2(0, -s * 0.2), s * 0.18, col)
		"cam":   # camera
			draw_rect(Rect2(c + Vector2(-s * 0.9, -s * 0.5), Vector2(s * 1.8, s * 1.15)), col, false, w)
			draw_rect(Rect2(c + Vector2(-s * 0.3, -s * 0.78), Vector2(s * 0.6, s * 0.28)), col, true)
			draw_arc(c + Vector2(0, s * 0.08), s * 0.36, 0.0, TAU, 14, col, w, true)
		"lights": # headlight + beams
			draw_arc(c + Vector2(-s * 0.2, 0), s * 0.62, deg_to_rad(90), deg_to_rad(270), 12, col, w, true)
			draw_line(c + Vector2(-s * 0.2, -s * 0.62), c + Vector2(-s * 0.2, s * 0.62), col, w)
			for i in 3:
				var yy: float = -s * 0.55 + float(i) * s * 0.55
				draw_line(c + Vector2(s * 0.15, yy), c + Vector2(s * 0.95, yy), col, w)
		"horn":  # horn: two arcs
			draw_arc(c + Vector2(0, s * 0.5), s * 0.9, deg_to_rad(205), deg_to_rad(335), 12, col, w * 1.2, true)
			draw_arc(c + Vector2(0, s * 0.5), s * 0.55, deg_to_rad(205), deg_to_rad(335), 10, col, w * 1.2, true)
			draw_line(c + Vector2(-s * 0.75, s * 0.15), c + Vector2(s * 0.75, s * 0.15), col, w)
		"hb":    # (P)
			draw_arc(c, s * 0.82, 0.0, TAU, 20, Color(NEON_RED.r, NEON_RED.g, NEON_RED.b, a), w, true)
			draw_string(font, c + Vector2(-s * 0.8, s * 0.38), "P", HORIZONTAL_ALIGNMENT_CENTER, s * 1.6, int(s * 1.5), Color(NEON_RED.r, NEON_RED.g, NEON_RED.b, a))
		"exit":  # door with arrow
			draw_rect(Rect2(c + Vector2(-s * 0.85, -s * 0.8), Vector2(s * 1.0, s * 1.6)), col, false, w)
			draw_line(c + Vector2(-s * 0.1, 0), c + Vector2(s * 0.95, 0), col, w)
			draw_line(c + Vector2(s * 0.95, 0), c + Vector2(s * 0.6, -s * 0.3), col, w)
			draw_line(c + Vector2(s * 0.95, 0), c + Vector2(s * 0.6, s * 0.3), col, w)
		"pause":
			draw_rect(Rect2(c + Vector2(-s * 0.55, -s * 0.8 + s * 0.2), Vector2(s * 0.4, s * 1.6)), col, true)
			draw_rect(Rect2(c + Vector2(s * 0.15, -s * 0.8 + s * 0.2), Vector2(s * 0.4, s * 1.6)), col, true)
		_:
			pass
