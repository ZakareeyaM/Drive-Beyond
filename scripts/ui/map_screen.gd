class_name MapScreen
extends Control
## Full-screen world map: pan, zoom, mission/POI markers, GPS waypoint + route.

signal closed

var world: World
var center: Vector2 = Vector2.ZERO   # world x,z at screen centre
var zoom: float = 0.22               # px per metre
var tex: ImageTexture
var drag: bool = false
var drag_moved: float = 0.0
var font: Font
var list_box: VBoxContainer
var info_lbl: Label
var hover_id: String = ""
var pinch_base: float = 0.0

static var cached_tex: ImageTexture = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	var pp: Vector3 = world.player_pos()
	center = Vector2(pp.x, pp.z)
	tex = _build_tex()
	var left := PanelContainer.new()
	left.position = Vector2(16, 16)
	left.custom_minimum_size = Vector2(360, 0)
	add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	lv.add_child(UIKit.title_bar("MAP", "Tap the map to set a GPS waypoint"))
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sc: ScrollContainer = UIKit.scroll(list_box, Vector2(330, 360))
	lv.add_child(sc)
	var bh := HBoxContainer.new()
	lv.add_child(bh)
	bh.add_child(UIKit.button("My position", _recenter, 48))
	bh.add_child(UIKit.button("Clear GPS", func() -> void: world.clear_waypoint(), 48))
	var vs: Vector2 = get_viewport_rect().size
	var cl: Button = UIKit.accent_button("Close", func() -> void: closed.emit(), 56, 160)
	cl.position = Vector2(vs.x - 190, vs.y - 80)
	add_child(cl)
	var zin: Button = UIKit.button("+", func() -> void: _zoom(1.3), 56, 56)
	zin.position = Vector2(vs.x - 80, 90)
	add_child(zin)
	var zout: Button = UIKit.button("−", func() -> void: _zoom(1.0 / 1.3), 56, 56)
	zout.position = Vector2(vs.x - 80, 154)
	add_child(zout)
	info_lbl = UIKit.label("", 20, UIKit.TEXT)
	info_lbl.position = Vector2(400, vs.y - 50)
	add_child(info_lbl)
	_fill_list()

func _recenter() -> void:
	var pp: Vector3 = world.player_pos()
	center = Vector2(pp.x, pp.z)
	queue_redraw()

func _zoom(k: float) -> void:
	zoom = clampf(zoom * k, 0.07, 1.2)
	queue_redraw()

func _fill_list() -> void:
	UIKit.clear(list_box)
	var items: Array = world.missions.all_markers()
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["story"] != b["story"]:
			return a["story"]
		return a["locked"] != b["locked"] and not a["locked"])
	for it in items:
		var col: Color = MissionManager.TYPE_COLOR.get(it["type"], Color.WHITE)
		var txt: String = "%s%s" % ["★ " if it["story"] else "", it["title"]]
		if it["done"]:
			txt += "  ✓"
		var b: Button = UIKit.button(txt, _goto.bind(it["pos"]), 44)
		b.add_theme_font_size_override("font_size", 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", col if not it["locked"] else UIKit.MUTED)
		if it["locked"]:
			b.tooltip_text = it["reason"]
			b.text += "  🔒" if false else "  (locked)"
		list_box.add_child(b)

func _goto(p: Vector3) -> void:
	center = Vector2(p.x, p.z)
	world.set_waypoint(p)
	queue_redraw()

func _build_tex() -> ImageTexture:
	if cached_tex != null:
		return cached_tex
	var n: int = 200
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var gen: WorldGen = world.gen
	var step: float = WorldGen.HALF * 2.0 / float(n)
	for j in n:
		for i in n:
			var x: float = -WorldGen.HALF + (float(i) + 0.5) * step
			var z: float = -WorldGen.HALF + (float(j) + 0.5) * step
			var h: float = gen.nat_h(x, z)
			var reg: String = gen.region_at(x, z)
			var c: Color
			if h < 0.0:
				c = Color(0.05, 0.12, 0.2).lerp(Color(0.1, 0.22, 0.34), clampf(1.0 + h / 30.0, 0.0, 1.0))
			elif h < 1.5:
				c = Color(0.55, 0.5, 0.38)
			else:
				match reg:
					"city": c = Color(0.16, 0.17, 0.2)
					"desert": c = Color(0.45, 0.38, 0.24)
					"mountain": c = Color(0.28, 0.3, 0.28).lerp(Color(0.6, 0.6, 0.62), clampf(h / 160.0, 0.0, 1.0))
					"forest": c = Color(0.1, 0.24, 0.12)
					"industrial": c = Color(0.2, 0.2, 0.22)
					_: c = Color(0.16, 0.28, 0.15)
				c = c.lightened(clampf(h / 400.0, 0.0, 0.2))
			img.set_pixel(i, j, c)
	cached_tex = ImageTexture.create_from_image(img)
	return cached_tex

func _w2s(p: Vector3) -> Vector2:
	return get_viewport_rect().size * 0.5 + (Vector2(p.x, p.z) - center) * zoom

func _s2w(s: Vector2) -> Vector3:
	var w: Vector2 = center + (s - get_viewport_rect().size * 0.5) / zoom
	return Vector3(w.x, 0.0, w.y)

func _draw() -> void:
	var vs: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.03, 0.05))
	var tl: Vector2 = _w2s(Vector3(-WorldGen.HALF, 0, -WorldGen.HALF))
	var sz: float = WorldGen.HALF * 2.0 * zoom
	draw_texture_rect(tex, Rect2(tl, Vector2(sz, sz)), false)
	draw_rect(Rect2(tl, Vector2(sz, sz)), UIKit.RED, false, 2.0)
	var gen: WorldGen = world.gen
	for e in gen.edges:
		var pts: PackedVector3Array = e["pts"]
		var k: String = e["kind"]
		var step: int = 4 if zoom < 0.5 else 2
		var arr := PackedVector2Array()
		for i in range(0, pts.size(), step):
			arr.append(_w2s(pts[i]))
		arr.append(_w2s(pts[pts.size() - 1]))
		var big: bool = k in ["avenue", "highway", "track"]
		var col: Color = Hud.ROAD_COL.get(k, Color(0.5, 0.5, 0.55))
		draw_polyline(arr, col, (3.0 if big else 1.5) * clampf(zoom * 4.0, 0.7, 2.0), true)
	# route
	var rt: PackedVector3Array = world.active_route()
	if rt.size() > 1:
		var arr2 := PackedVector2Array()
		for i in range(0, rt.size(), 2):
			arr2.append(_w2s(rt[i]))
		draw_polyline(arr2, Color(1.0, 0.2, 0.3), 4.0, true)
	# POIs
	for poi in world.pois:
		var s: Vector2 = _w2s(poi["pos"])
		match poi["type"]:
			"garage":
				_icon(s, UIKit.RED, "G")
			"dealership":
				_icon(s, Color(0.3, 0.6, 1.0), "D")
			"gas", "fuel":
				_icon(s, UIKit.GOLD, "F")
			"repair":
				_icon(s, Color(1.0, 0.5, 0.1), "R")
			"discover":
				if Game.discovered.has(poi["id"]) and zoom > 0.16:
					draw_string(font, s + Vector2(8, 4), String(poi["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.85, 0.9, 0.8))
					draw_circle(s, 3.0, Color(0.85, 0.85, 0.9))
	hover_id = ""
	var mp: Vector2 = get_local_mouse_position()
	for m in world.missions.all_markers():
		var s2: Vector2 = _w2s(m["pos"])
		var col2: Color = MissionManager.TYPE_COLOR.get(m["type"], Color.WHITE)
		if m["locked"]:
			col2 = Color(0.45, 0.45, 0.5)
		draw_circle(s2, 9.0, Color(0, 0, 0, 0.85))
		draw_circle(s2, 6.5, col2)
		if m["story"]:
			draw_string(font, s2 + Vector2(-5, 5), "★", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.BLACK)
		if s2.distance_to(mp) < 14.0:
			hover_id = m["title"] + ("  -  " + m["reason"] if m["locked"] else "")
	if world.has_waypoint:
		var ws: Vector2 = _w2s(world.waypoint)
		draw_circle(ws, 9.0, Color.WHITE)
		draw_circle(ws, 5.0, UIKit.RED)
	# player
	var pp: Vector3 = world.player_pos()
	var ps: Vector2 = _w2s(pp)
	var ang: float = 0.0
	if world.player_car:
		var f: Vector3 = -world.player_car.global_transform.basis.z
		ang = atan2(f.x, -f.z)
	var ar := PackedVector2Array([Vector2(0, -12), Vector2(8, 10), Vector2(0, 5), Vector2(-8, 10)])
	for i in ar.size():
		ar[i] = ps + ar[i].rotated(ang)
	draw_colored_polygon(ar, Color.WHITE)
	draw_polyline(PackedVector2Array([ar[0], ar[1], ar[2], ar[3], ar[0]]), UIKit.RED, 2.0)
	info_lbl.text = hover_id if hover_id != "" else "Coordinates  %d, %d" % [int(_s2w(mp).x), int(_s2w(mp).z)]

func _icon(s: Vector2, col: Color, t: String) -> void:
	draw_rect(Rect2(s - Vector2(9, 9), Vector2(18, 18)), Color(0, 0, 0, 0.85))
	draw_rect(Rect2(s - Vector2(7, 7), Vector2(14, 14)), col)
	draw_string(font, s + Vector2(-4.5, 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.BLACK)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb: InputEventMouseButton = ev
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				drag = true
				drag_moved = 0.0
			else:
				if drag and drag_moved < 8.0:
					var w: Vector3 = _s2w(mb.position)
					if absf(w.x) < WorldGen.HALF and absf(w.z) < WorldGen.HALF:
						w.y = world.gen.ground_h(w.x, w.z)
						world.set_waypoint(w)
				drag = false
				queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0 / 1.15)
	elif ev is InputEventMouseMotion:
		var mm: InputEventMouseMotion = ev
		if drag:
			drag_moved += mm.relative.length()
			center -= mm.relative / zoom
		queue_redraw()
	elif ev is InputEventMagnifyGesture:
		_zoom((ev as InputEventMagnifyGesture).factor)

func _unhandled_key_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("map") or ev.is_action_pressed("pause"):
		closed.emit()
		get_viewport().set_input_as_handled()
