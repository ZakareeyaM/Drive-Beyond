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
static var _tex_task: int = -1                   # WorkerThreadPool task id of the background terrain-image build (-1 = none)
static var _tex_img: Image = null
static var _road_cache: Dictionary = {}          # lod ("far" / "near") -> {kind: PackedVector2Array of segment pairs, world x/z}
static var _road_edges: int = -1
var _markers: Array = []                         # mission markers, read once per open (the world is paused while the map is shown)
var _lbl_w: Dictionary = {}                      # "text|size" -> measured string width
var _prev_3d_disabled: bool = false

const MAP_N := 200

## Starts the terrain image of the map on a worker thread (called once when the world is ready), so the first map open no longer
## pays ~0.5 s of noise sampling on the main thread.  The texture itself is created on the main thread when it is first needed.
static func prewarm(gen: WorldGen) -> void:
	if cached_tex != null or _tex_task != -1:
		return
	_tex_task = WorkerThreadPool.add_task(func() -> void: _tex_img = _render_image(gen), false, "map terrain image")

static func _render_image(gen: WorldGen) -> Image:
	var n: int = MAP_N
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
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
	return img

## All roads as segment pairs in world x/z, one array per road kind and level of detail (built once, drawn with a single call per kind)
static func _roads(gen: WorldGen, lod: String) -> Dictionary:
	if _road_edges != gen.edges.size():
		_road_cache.clear()
		_road_edges = gen.edges.size()
	if _road_cache.has(lod):
		return _road_cache[lod]
	var step: int = 4 if lod == "far" else 2
	var out: Dictionary = {}
	for e in gen.edges:
		var pts: PackedVector3Array = e["pts"]
		var k: String = e["kind"]
		if not out.has(k):
			out[k] = PackedVector2Array()
		var arr: PackedVector2Array = out[k]
		var prev: Vector2 = Vector2(pts[0].x, pts[0].z)
		var i: int = step
		while true:
			var idx: int = mini(i, pts.size() - 1)
			var cur := Vector2(pts[idx].x, pts[idx].z)
			arr.append(prev)
			arr.append(cur)
			prev = cur
			if idx >= pts.size() - 1:
				break
			i += step
		out[k] = arr
	_road_cache[lod] = out
	return out

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	var pp: Vector3 = world.player_pos()
	center = Vector2(pp.x, pp.z)
	tex = _build_tex()
	_markers = world.missions.all_markers()
	# the map covers the whole screen: skip rendering the 3D world behind it while it is open (restored in _exit_tree)
	var vp: Viewport = get_viewport()
	_prev_3d_disabled = vp.disable_3d
	vp.disable_3d = true
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

func _exit_tree() -> void:
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.disable_3d = _prev_3d_disabled

func _recenter() -> void:
	var pp: Vector3 = world.player_pos()
	center = Vector2(pp.x, pp.z)
	queue_redraw()

func _zoom(k: float) -> void:
	zoom = clampf(zoom * k, 0.07, 1.2)
	queue_redraw()

func _fill_list() -> void:
	UIKit.clear(list_box)
	var items: Array = _markers.duplicate()
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
	var img: Image
	if _tex_task != -1:
		WorkerThreadPool.wait_for_task_completion(_tex_task)     # already finished in the background in the normal case
		_tex_task = -1
		img = _tex_img
		_tex_img = null
	if img == null:
		img = _render_image(world.gen)
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
	_draw_zones(gen)
	# roads: pre-baked segment lists, ONE draw call per road kind, drawn through a world->screen transform (line width compensated)
	var roads: Dictionary = _roads(gen, "far" if zoom < 0.5 else "near")
	draw_set_transform(vs * 0.5 - center * zoom, 0.0, Vector2(zoom, zoom))
	for k in roads:
		var big: bool = k in ["avenue", "highway", "track"]
		var col: Color = Hud.ROAD_COL.get(k, Color(0.5, 0.5, 0.55))
		draw_multiline(roads[k], col, (3.0 if big else 1.5) * clampf(zoom * 4.0, 0.7, 2.0) / zoom, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# route
	var rt: PackedVector3Array = world.active_route()
	if rt.size() > 1:
		var arr2 := PackedVector2Array()
		for i in range(0, rt.size(), 2):
			arr2.append(_w2s(rt[i]))
		draw_polyline(arr2, Color(1.0, 0.2, 0.3), 4.0, true)
	_draw_district_labels(gen)
	# POIs
	for poi in world.pois:
		var s: Vector2 = _w2s(poi["pos"])
		match poi["type"]:
			"kart":
				_flag_icon(s)
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
	for m in _markers:
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
	_draw_legend(vs)
	_draw_compass(vs)
	info_lbl.text = hover_id if hover_id != "" else "Coordinates  %d, %d" % [int(_s2w(mp).x), int(_s2w(mp).z)]

# ---------------------------------------------------------------- districts, legend, compass
func _label(p: Vector2, t: String, size: int, col: Color) -> void:
	draw_string(font, p + Vector2(1.5, 1.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.9))
	draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _label_c(p: Vector2, t: String, size: int, col: Color) -> void:
	var key: String = "%s|%d" % [t, size]
	if not _lbl_w.has(key):
		_lbl_w[key] = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_label(p - Vector2(float(_lbl_w[key]) * 0.5, 0), t, size, col)

## translucent district footprints on top of the terrain texture (world rectangles / circles)
func _draw_zones(gen: WorldGen) -> void:
	var zones: Array = [
		[Rect2(1795.0, 45.0, 440.0, 910.0), Color(0.55, 0.7, 0.9, 0.16)],       # airport
		[Rect2(1560.0, 860.0, 270.0, 280.0), Color(0.95, 0.75, 0.3, 0.16)],     # business district
		[Rect2(1890.0, 960.0, 240.0, 220.0), Color(0.75, 0.5, 0.9, 0.16)],      # accommodation district
	]
	for id in RaceTracks.ORDER:
		var c: Vector2 = RaceTracks.DEF[id]["c"]
		var h: Vector2 = (TracksData.DATA[id]["half"] as Vector2) + Vector2(10, 10)
		zones.append([Rect2(c.x - h.x, c.y - h.y, h.x * 2.0, h.y * 2.0), Color(0.95, 0.35, 0.3, 0.2)])
	for z in zones:
		var r: Rect2 = z[0]
		draw_rect(Rect2(_w2s(Vector3(r.position.x, 0, r.position.y)), r.size * zoom), z[1])
	if gen.landmarks.has("city_center"):
		var cc: Vector3 = gen.landmarks["city_center"]
		draw_arc(_w2s(cc), 520.0 * zoom, 0.0, TAU, 64, Color(0.7, 0.75, 0.9, 0.35), 2.0, true)

func _draw_district_labels(gen: WorldGen) -> void:
	var L: Dictionary = gen.landmarks
	var names: Array = [["city_center", "CITY CENTER"], ["port", "PORT"], ["industrial", "INDUSTRIAL AREA"], ["business_district", "BUSINESS DISTRICT"],
		["resort_district", "ACCOMMODATION DISTRICT"], ["airport", "AIRPORT"], ["circuit", "RACE CIRCUIT"], ["track_a", "RIVERSIDE RACEWAY"], ["track_b", "GRAND PRIX CIRCUIT"]]
	for n in names:
		if not L.has(n[0]):
			continue
		var s: Vector2 = _w2s(L[n[0]])
		var size: int = clampi(int(11.0 + zoom * 30.0), 12, 22)
		if n[0] == "airport":
			s += Vector2(0, 26)
		var tw: float = font.get_string_size(String(n[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		match String(n[0]):
			"business_district":
				_label(s - Vector2(tw + 14.0, 0), String(n[1]), size, Color(1, 0.9, 0.6, 0.95))      # to the left of its block
			"resort_district":
				_label(s + Vector2(14.0, 0), String(n[1]), size, Color(0.9, 0.75, 1.0, 0.95))        # to the right of its block
			"track_a", "track_b":
				_label_c(s - Vector2(0, 22), String(n[1]), size, Color(1.0, 0.85, 0.3, 0.97))
			_:
				_label_c(s - Vector2(0, 14), String(n[1]), size, Color(1, 1, 1, 0.92))

func _flag_icon(s: Vector2) -> void:
	draw_rect(Rect2(s - Vector2(10, 10), Vector2(20, 20)), Color(0, 0, 0, 0.9))
	for iy in range(4):
		for ix in range(4):
			draw_rect(Rect2(s + Vector2(-8 + ix * 4, -8 + iy * 4), Vector2(4, 4)), Color.WHITE if (ix + iy) % 2 == 0 else Color(0.1, 0.1, 0.1))

func _plane_icon(s: Vector2) -> void:
	draw_rect(Rect2(s - Vector2(10, 10), Vector2(20, 20)), Color(0, 0, 0, 0.9))
	var col := Color(0.55, 0.8, 1.0)
	draw_line(s + Vector2(0, -8), s + Vector2(0, 8), col, 3.0)
	draw_line(s + Vector2(-8, 1), s + Vector2(8, 1), col, 3.0)
	draw_line(s + Vector2(-4, 7), s + Vector2(4, 7), col, 2.0)

func _draw_legend(vs: Vector2) -> void:
	var items: Array = [["G", UIKit.RED, "Home Garage"], ["D", Color(0.3, 0.6, 1.0), "Dealership"], ["M", Color(1.0, 0.8, 0.2), "Mission"], ["F", UIKit.GOLD, "Fuel Station"], ["A", Color(0.55, 0.8, 1.0), "Airport"], ["C", Color.WHITE, "Race Circuit"]]
	var x0: float = vs.x - 232.0
	var y0: float = vs.y - 100.0 - float(items.size()) * 26.0 - 34.0
	draw_rect(Rect2(x0 - 12, y0 - 10, 224, float(items.size()) * 26.0 + 48.0), Color(0.03, 0.04, 0.07, 0.82))
	draw_rect(Rect2(x0 - 12, y0 - 10, 224, float(items.size()) * 26.0 + 48.0), UIKit.RED, false, 1.5)
	_label(Vector2(x0, y0 + 12), "LEGEND", 16, Color(1, 1, 1))
	for i in range(items.size()):
		var it: Array = items[i]
		var c: Vector2 = Vector2(x0 + 11, y0 + 38.0 + float(i) * 26.0)
		match String(it[0]):
			"M":
				draw_circle(c, 9.0, Color(0, 0, 0, 0.85))
				draw_circle(c, 6.5, it[1])
			"C":
				_flag_icon(c)
			"A":
				_plane_icon(c)
			_:
				_icon(c, it[1], String(it[0]))
		_label(Vector2(x0 + 30, y0 + 44.0 + float(i) * 26.0), String(it[2]), 16, Color(0.92, 0.92, 0.96))

func _draw_compass(vs: Vector2) -> void:
	var c: Vector2 = Vector2(vs.x - 52.0, 262.0)
	draw_circle(c, 30.0, Color(0.03, 0.04, 0.07, 0.82))
	draw_arc(c, 30.0, 0.0, TAU, 32, UIKit.RED, 2.0, true)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -24), c + Vector2(7, 4), c + Vector2(-7, 4)]), UIKit.RED)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, 24), c + Vector2(7, 4), c + Vector2(-7, 4)]), Color(0.7, 0.7, 0.75))
	_label_c(c + Vector2(0, -33), "N", 16, Color.WHITE)

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
