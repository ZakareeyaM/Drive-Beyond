class_name Hud
extends Control
## In-game HUD: speedometer / gear / RPM / fuel / damage, minimap, money,
## wanted stars, mission panel, prompts, toasts and time/weather.

var world: World
var font: Font
var toasts: Array = []
var flash_a: float = 0.0
var prompt_label: Label
var msg_big: Label
var banner_t: float = 0.0
var star_blink: float = 0.0
var last_wanted: int = 0
var show_speedo: bool = true
var region_name: String = ""
var _mm_cache_t: float = 0.0
var mm_center: Vector2 = Vector2(118, 138)
var mm_radius: float = 92.0
var hud_visible: bool = true
var photo_mode: bool = false

const KIND_COLOR := {"info": Color(0.85, 0.85, 0.9), "money": Color(0.4, 1.0, 0.5), "warn": Color(1.0, 0.8, 0.2), "bad": Color(1.0, 0.3, 0.3), "good": Color(0.4, 1.0, 0.6)}
const ROAD_COL := {"street": Color(0.55, 0.55, 0.6), "avenue": Color(0.85, 0.85, 0.9), "highway": Color(1.0, 0.75, 0.3), "country": Color(0.62, 0.6, 0.55),
	"mountain": Color(0.62, 0.58, 0.5), "coastal": Color(0.5, 0.75, 0.95), "dirt": Color(0.6, 0.45, 0.3), "track": Color(0.9, 0.5, 0.5)}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = ThemeDB.fallback_font
	Game.notify.connect(_on_notify)
	prompt_label = UIKit.label("", 28, Color.WHITE, 1)
	prompt_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.position = Vector2(-300, -250)
	prompt_label.size = Vector2(600, 40)
	prompt_label.add_theme_stylebox_override("normal", UIKit.box(Color(0, 0, 0, 0.6), 8, UIKit.RED, 2, 14))
	prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt_label.visible = false
	add_child(prompt_label)
	msg_big = UIKit.label("", 110, Color.WHITE, 1)
	msg_big.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	msg_big.position = Vector2(-300, -170)
	msg_big.size = Vector2(600, 140)
	msg_big.add_theme_color_override("font_outline_color", UIKit.RED)
	msg_big.add_theme_constant_override("outline_size", 10)
	msg_big.visible = false
	add_child(msg_big)

func _on_notify(text: String, kind: String) -> void:
	if text == "GO!":
		msg_big.text = "GO!"
		msg_big.visible = true
		banner_t = 0.8
		return
	toasts.append({"text": text, "kind": kind, "t": 4.0})
	if toasts.size() > 5:
		toasts.pop_front()

func flash() -> void:
	flash_a = 0.9

func _process(delta: float) -> void:
	visible = world != null and world.running and hud_visible
	if not visible:
		return
	for t in toasts:
		t["t"] -= delta
	while toasts.size() > 0 and toasts[0]["t"] <= 0.0:
		toasts.pop_front()
	flash_a = maxf(0.0, flash_a - delta * 1.6)
	star_blink += delta
	if banner_t > 0.0:
		banner_t -= delta
		if banner_t <= 0.0 and world.missions.countdown <= 0.0:
			msg_big.visible = false
	var info: Dictionary = world.missions.hud_info() if world.missions else {}
	if not info.is_empty() and info.get("big", false):
		msg_big.text = String(info["line"])
		msg_big.visible = true
	elif banner_t <= 0.0:
		msg_big.visible = false
	var pt: String = world.prompt_text
	prompt_label.visible = pt != "" and not world.ui_open
	prompt_label.text = pt
	if world.mode == "drive":
		prompt_label.position = Vector2(-300, -210)
	var pp: Vector3 = world.player_pos()
	region_name = _region_label(pp)
	queue_redraw()

func _region_label(p: Vector3) -> String:
	var r: String = world.gen.region_at(p.x, p.z)
	var nr: Dictionary = world.gen.nearest_road(p, 14.0)
	if not nr.is_empty():
		var e: Dictionary = world.gen.edges[nr["edge"]]
		var nm: String = String(e.get("name", ""))
		if nm != "":
			return nm
	return r.capitalize()

# ---------------------------------------------------------------- drawing
func _txt(text: String, pos: Vector2, size: int, col: Color = Color.WHITE, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	draw_string(font, pos + Vector2(1.5, 1.5), text, align as HorizontalAlignment, width, size, Color(0, 0, 0, 0.7))
	draw_string(font, pos, text, align as HorizontalAlignment, width, size, col)

func _draw() -> void:
	if world == null or not world.running:
		return
	var vs: Vector2 = get_viewport_rect().size
	var car: Vehicle = world.player_car
	var driving: bool = world.mode == "drive" and car != null
	_draw_minimap(vs)
	_draw_top_right(vs)
	if driving:
		_draw_speedo(Vector2(vs.x * 0.5, vs.y - 100.0), car)
	_draw_mission(vs)
	_draw_toasts(vs)
	_draw_wanted(vs)
	if world.has_waypoint or (world.missions and world.missions.route.size() > 1):
		_draw_nav(vs)
	if flash_a > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 1, 1, flash_a * 0.8))

func _draw_speedo(c: Vector2, car: Vehicle) -> void:
	var r: float = 78.0
	draw_circle(c, r + 8.0, Color(0, 0, 0, 0.55))
	draw_arc(c, r, deg_to_rad(150), deg_to_rad(390), 48, Color(1, 1, 1, 0.12), 8.0, true)
	var rn: float = clampf(car.rpm_norm, 0.0, 1.0)
	var col: Color = UIKit.RED if rn > 0.88 else Color(0.95, 0.95, 1.0)
	if rn > 0.01:
		draw_arc(c, r, deg_to_rad(150), deg_to_rad(150 + 240.0 * rn), 40, col, 8.0, true)
	var red0: float = 150.0 + 240.0 * 0.88
	draw_arc(c, r + 9.0, deg_to_rad(red0), deg_to_rad(390), 10, Color(1, 0.1, 0.1, 0.7), 3.0, true)
	var sp: float = Game.speed_to_display(car.abs_speed)
	_txt("%d" % int(round(sp)), c + Vector2(-60, 14), 52, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 120.0)
	_txt(Game.unit_label(), c + Vector2(-40, 38), 18, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 80.0)
	var g: String = "R" if car.reversing else ("N" if car.abs_speed < 0.6 and car.in_throttle < 0.05 else str(car.gear))
	_txt(g, c + Vector2(-20, -40), 36, UIKit.RED if car.reversing else Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 40.0)
	# fuel (left) + damage (right)
	var bw: float = 120.0
	var by: float = c.y + 52.0
	var fx: float = c.x - r - 140.0
	var fcol: Color = UIKit.GOLD if car.fuel > 0.2 else Color(1, 0.2, 0.2)
	if car.fuel < 0.2 and int(star_blink * 3.0) % 2 == 0:
		fcol = Color(1, 0.6, 0.6)
	_txt("FUEL", Vector2(fx, by - 22.0), 16, UIKit.MUTED)
	draw_rect(Rect2(fx, by - 14.0, bw, 10), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(fx, by - 14.0, bw * car.fuel, 10), fcol)
	var dx2: float = c.x + r + 20.0
	_txt("DAMAGE", Vector2(dx2, by - 22.0), 16, UIKit.MUTED)
	draw_rect(Rect2(dx2, by - 14.0, bw, 10), Color(0, 0, 0, 0.6))
	var dcol: Color = Color(0.4, 0.9, 0.5).lerp(Color(1, 0.15, 0.1), car.damage)
	draw_rect(Rect2(dx2, by - 14.0, bw * car.damage, 10), dcol)
	if car.has_nitro:
		_txt("NITRO", Vector2(dx2, by + 8.0), 16, UIKit.MUTED)
		draw_rect(Rect2(dx2, by + 16.0, bw, 8), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(dx2, by + 16.0, bw * car.nitro, 8), Color(0.3, 0.7, 1.0))
	if car.headlights_on:
		_txt("LIGHTS", Vector2(fx, by + 8.0), 16, Color(0.9, 0.9, 0.6))
	if car.drifting and car.drift_time > 0.4:
		_txt("DRIFT %d" % int(car.drift_points), Vector2(c.x - 100, c.y - r - 22.0), 28, Color(0.8, 0.5, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 200.0)

func _draw_top_right(vs: Vector2) -> void:
	var x: float = vs.x - 24.0
	_txt(Game.fmt_money(Game.money), Vector2(x - 300, 44), 36, UIKit.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	_txt("REP %d" % Game.rep, Vector2(x - 300, 72), 20, UIKit.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	var env: EnvironmentManager = world.env
	_txt("%s  |  %s" % [env.hour_string(), env.weather_label()], Vector2(x - 300, 98), 20, Color(0.9, 0.9, 0.95), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	_txt(region_name, Vector2(x - 300, 124), 18, UIKit.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 300.0)

func _draw_wanted(vs: Vector2) -> void:
	var lvl: int = world.police.level if world.police else 0
	if lvl <= 0:
		return
	var x0: float = vs.x - 24.0 - 5.0 * 34.0
	var blink: bool = world.police.nearest_cop < 120.0 and int(star_blink * 4.0) % 2 == 0
	for i in 5:
		var on: bool = i < lvl
		var col: Color = Color(1.0, 0.85, 0.15) if on else Color(1, 1, 1, 0.18)
		if on and blink:
			col = Color(1.0, 0.25, 0.25)
		_txt("★", Vector2(x0 + i * 34.0, 170), 34, col)
	var st: String = "POLICE CLOSING IN" if world.police.nearest_cop < 90.0 else "SEARCHING"
	if world.police.busted_t > 0.1:
		st = "BUSTING... %d%%" % int(world.police.busted_t / 3.2 * 100.0)
	_txt(st, Vector2(vs.x - 324, 196), 16, Color(1.0, 0.5, 0.5), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)

func _draw_mission(vs: Vector2) -> void:
	var info: Dictionary = world.missions.hud_info() if world.missions else {}
	if info.is_empty() or info.get("big", false):
		return
	var w: float = 380.0
	var x: float = vs.x * 0.5 - w * 0.5
	draw_rect(Rect2(x, 16, w, 92), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(x, 16, 4, 92), UIKit.RED)
	_txt(String(info["title"]).to_upper(), Vector2(x + 14, 40), 22, Color.WHITE)
	_txt(String(info["line"]), Vector2(x + 14, 66), 20, Color(0.95, 0.9, 0.7))
	if String(info.get("sub", "")) != "":
		_txt(String(info["sub"]), Vector2(x + 14, 92), 17, UIKit.MUTED)
	var t: float = float(info["timer"])
	if t >= 0.0:
		var col: Color = Color.WHITE
		if not info.get("count_up", false) and t < 15.0:
			col = Color(1, 0.3, 0.3)
		_txt(UIKit.fmt_time(t), Vector2(x + w - 110, 52), 34, col, HORIZONTAL_ALIGNMENT_RIGHT, 100.0)

func _draw_toasts(vs: Vector2) -> void:
	var y: float = vs.y * 0.42
	for i in range(toasts.size() - 1, -1, -1):
		var t: Dictionary = toasts[i]
		var a: float = clampf(float(t["t"]) / 0.6, 0.0, 1.0)
		var col: Color = KIND_COLOR.get(t["kind"], Color.WHITE)
		col.a = a
		var tw: float = font.get_string_size(String(t["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 28.0
		draw_rect(Rect2(vs.x - 24.0 - tw, y - 24, tw, 34), Color(0, 0, 0, 0.5 * a))
		draw_rect(Rect2(vs.x - 24.0 - 4, y - 24, 4, 34), Color(col.r, col.g, col.b, a))
		draw_string(font, Vector2(vs.x - 24.0 - tw + 12, y), String(t["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
		y += 40.0

func _mm_point(p: Vector3, center: Vector3, f: Vector2, scale_px: float, rot: bool) -> Vector2:
	var dx: float = p.x - center.x
	var dz: float = p.z - center.z
	if rot:
		var r := Vector2(-f.y, f.x)
		return mm_center + Vector2(dx * r.x + dz * r.y, -(dx * f.x + dz * f.y)) * scale_px
	return mm_center + Vector2(dx, dz) * scale_px

func _draw_minimap(vs: Vector2) -> void:
	var size_k: float = float(Game.settings.get("minimap_size", 1.0))
	var rad: float = mm_radius * size_k
	mm_center = Vector2(rad + 22.0, rad + 36.0)
	var pp: Vector3 = world.player_pos()
	var rot: bool = bool(Game.settings.get("minimap_rotate", true))
	var cf: Vector3 = -world.cam.cam.global_transform.basis.z
	var f := Vector2(cf.x, cf.z)
	if f.length() < 0.01:
		f = Vector2(0, -1)
	f = f.normalized()
	var zoom_m: float = 150.0
	if world.mode == "drive":
		zoom_m = 130.0 + clampf(world.player_car.abs_speed * 2.2, 0.0, 130.0)
	var sc: float = rad / zoom_m
	draw_circle(mm_center, rad + 6.0, Color(0, 0, 0, 0.7))
	draw_circle(mm_center, rad, Color(0.07, 0.08, 0.1, 0.95))
	var gen: WorldGen = world.gen
	var cx: int = int(floor(pp.x / 32.0))
	var cz: int = int(floor(pp.z / 32.0))
	var rr: int = int(ceil(zoom_m / 32.0)) + 1
	var lim2: float = (zoom_m * 0.98) * (zoom_m * 0.98)
	for dz in range(-rr, rr + 1):
		for dx in range(-rr, rr + 1):
			var kk: int = (cx + dx) * 100000 + (cz + dz)
			if not gen.snap_grid.has(kk):
				continue
			var arr: PackedInt32Array = gen.snap_grid[kk]
			for q in range(0, arr.size(), 2):
				var e: Dictionary = gen.edges[arr[q]]
				var pts: PackedVector3Array = e["pts"]
				var i: int = arr[q + 1]
				if i + 1 >= pts.size():
					continue
				var a: Vector3 = pts[i]
				var b: Vector3 = pts[i + 1]
				if (a.x - pp.x) * (a.x - pp.x) + (a.z - pp.z) * (a.z - pp.z) > lim2:
					continue
				if (b.x - pp.x) * (b.x - pp.x) + (b.z - pp.z) * (b.z - pp.z) > lim2:
					continue
				var k: String = e["kind"]
				var w: float = 1.5 if k in ["street", "dirt", "country", "mountain"] else 3.0
				draw_line(_mm_point(a, pp, f, sc, rot), _mm_point(b, pp, f, sc, rot), ROAD_COL.get(k, Color.GRAY), w * size_k, true)
	# route line
	var rt: PackedVector3Array = world.active_route()
	if rt.size() > 1:
		var pts2 := PackedVector2Array()
		for i in range(0, rt.size(), 2):
			var p: Vector3 = rt[i]
			if (p.x - pp.x) * (p.x - pp.x) + (p.z - pp.z) * (p.z - pp.z) < lim2:
				pts2.append(_mm_point(p, pp, f, sc, rot))
			elif pts2.size() > 1:
				draw_polyline(pts2, Color(1.0, 0.2, 0.3), 4.0, true)
				pts2.clear()
		if pts2.size() > 1:
			draw_polyline(pts2, Color(1.0, 0.2, 0.3), 4.0, true)
	# markers
	if world.missions:
		for m in world.missions.markers:
			if (m["beacon"] as Node3D).visible:
				_mm_icon(m["pos"], TYPE_COL(m["def"]["type"]), pp, f, sc, rot, rad, 5.0)
	for poi in world.pois:
		if poi["type"] in ["garage", "dealership", "gas"]:
			var col: Color = Color(1, 0.2, 0.2) if poi["type"] == "garage" else (Color(0.3, 0.6, 1.0) if poi["type"] == "dealership" else UIKit.GOLD)
			_mm_icon(poi["pos"], col, pp, f, sc, rot, rad, 4.0)
	if world.has_waypoint:
		_mm_icon(world.waypoint, Color(1, 1, 1), pp, f, sc, rot, rad, 6.0)
	if world.police:
		for u in world.police.units:
			if is_instance_valid(u["car"]):
				var blink: bool = int(star_blink * 4.0) % 2 == 0
				_mm_icon((u["car"] as Node3D).global_position, Color(1, 0.2, 0.2) if blink else Color(0.2, 0.4, 1.0), pp, f, sc, rot, rad * 0.97, 4.0)
	# player arrow
	var ang: float = 0.0
	if world.mode == "drive" and world.player_car:
		var pf: Vector3 = -world.player_car.global_transform.basis.z
		var fb: Vector2 = f if rot else Vector2(0, -1)
		var rb := Vector2(-fb.y, fb.x)
		var p2 := Vector2(pf.x, pf.z)
		ang = atan2(p2.dot(rb), p2.dot(fb))
	elif world.mode == "foot":
		var cfy: Vector3 = world.foot.vis.global_transform.basis.z * -1.0
		var fb2: Vector2 = f if rot else Vector2(0, -1)
		var rb2 := Vector2(-fb2.y, fb2.x)
		var q2 := Vector2(cfy.x, cfy.z)
		ang = atan2(q2.dot(rb2), q2.dot(fb2))
	var ar := PackedVector2Array([Vector2(0, -9), Vector2(6, 7), Vector2(0, 3), Vector2(-6, 7)])
	for i in ar.size():
		ar[i] = mm_center + ar[i].rotated(ang)
	draw_colored_polygon(ar, Color(1, 1, 1))
	draw_arc(mm_center, rad, 0.0, TAU, 64, UIKit.RED, 4.0, true)
	if rot:
		_txt("N", mm_center + _north_offset(f, rad) + Vector2(-6, 0), 16, UIKit.RED)

func _north_offset(f: Vector2, rad: float) -> Vector2:
	# north is world -Z; project onto the rotated minimap
	var r := Vector2(-f.y, f.x)
	var n := Vector2(0, -1)
	var v := Vector2(n.x * r.x + n.y * r.y, -(n.x * f.x + n.y * f.y))
	return v * (rad - 12.0) + Vector2(0, 6)

func TYPE_COL(t: String) -> Color:
	return MissionManager.TYPE_COLOR.get(t, Color.WHITE)

func _mm_icon(p: Vector3, col: Color, center: Vector3, f: Vector2, sc: float, rot: bool, rad: float, sz: float) -> void:
	var q: Vector2 = _mm_point(p, center, f, sc, rot)
	var off: Vector2 = q - mm_center
	var edge: bool = false
	if off.length() > rad - 8.0:
		off = off.normalized() * (rad - 8.0)
		q = mm_center + off
		edge = true
	draw_circle(q, sz + 1.5, Color(0, 0, 0, 0.8))
	draw_circle(q, sz * (0.75 if edge else 1.0), col)

func _draw_nav(vs: Vector2) -> void:
	var target: Vector3
	var rt: PackedVector3Array = world.active_route()
	var pp: Vector3 = world.player_pos()
	if rt.size() > 1:
		# aim at a point ~40 m along the route
		var acc: float = 0.0
		var idx: int = 0
		var best: float = 1e9
		for i in rt.size():
			var d: float = Vector2(rt[i].x - pp.x, rt[i].z - pp.z).length()
			if d < best:
				best = d
				idx = i
		var j: int = idx
		while j < rt.size() - 1 and acc < 45.0:
			acc += rt[j].distance_to(rt[j + 1])
			j += 1
		target = rt[j]
	else:
		target = world.waypoint
	var cf: Vector3 = -world.cam.cam.global_transform.basis.z
	var fa: float = atan2(cf.x, -cf.z)
	var to: Vector3 = target - pp
	var ta: float = atan2(to.x, -to.z)
	var rel: float = wrapf(ta - fa, -PI, PI)
	var c := Vector2(mm_center.x, mm_center.y + mm_radius * float(Game.settings.get("minimap_size", 1.0)) + 44.0)
	var tri := PackedVector2Array([Vector2(0, -16), Vector2(12, 12), Vector2(0, 6), Vector2(-12, 12)])
	for i in tri.size():
		tri[i] = c + tri[i].rotated(rel)
	draw_colored_polygon(tri, Color(1.0, 0.25, 0.3))
	var dist: float = pp.distance_to(world.waypoint if world.has_waypoint else (rt[rt.size() - 1] if rt.size() > 0 else pp))
	_txt(Game.dist_label(dist), c + Vector2(24, 8), 22)
