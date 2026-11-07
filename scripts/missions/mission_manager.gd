class_name MissionManager
extends Node
## Data-driven missions: street races, time trials, drag, drift, deliveries,
## driving challenges, police escapes and off-road runs, plus the story chain.

signal mission_started(id: String)
signal mission_finished(id: String, success: bool)

const TYPE_COLOR := {
	"race": Color(1.0, 0.15, 0.15), "time_trial": Color(1.0, 0.65, 0.1), "drag": Color(1.0, 0.3, 0.6), "drift": Color(0.7, 0.3, 1.0),
	"delivery": Color(0.2, 0.9, 0.4), "challenge": Color(0.2, 0.8, 1.0), "police": Color(0.3, 0.4, 1.0), "offroad": Color(0.9, 0.7, 0.3),
}
const TYPE_LABEL := {
	"race": "Street Race", "time_trial": "Time Trial", "drag": "Drag Race", "drift": "Drift Challenge", "delivery": "Delivery",
	"challenge": "Driving Challenge", "police": "Police Challenge", "offroad": "Off-Road",
}

var world: World
var defs: Array = []
var markers: Array = []          # {def, pos, beacon}
var active: Dictionary = {}      # runtime state; empty when idle
var route: PackedVector3Array = PackedVector3Array()
var route_t: float = 0.0
var countdown: float = 0.0
var cp_nodes: Array = []
var opp: Array = []              # {car, ai, finished, time}
var event_def: Dictionary = {}
var event_timer: float = 0.0
var event_next: float = 280.0
var _dialog_busy: bool = false

func setup() -> void:
	var f := FileAccess.open("res://data/missions/missions.json", FileAccess.READ)
	if f:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Array:
			defs = parsed
	for d in defs:
		var p: Vector3 = world.gen.resolve_point(d["start"])
		var rp: Dictionary = world.gen.nearest_road(p, 90.0)
		if not rp.is_empty() and p.distance_to(rp["pos"]) > 6.0 and not (d["start"] is String and d["start"] == "@dragstrip_start"):
			p = rp["pos"]
		var col: Color = TYPE_COLOR.get(d["type"], Color.WHITE)
		var bm: MeshInstance3D = world.make_beacon(p, col, 40.0, 1.5)
		markers.append({"def": d, "pos": p, "beacon": bm})
	Game.mission_state_changed.connect(_refresh_markers)
	Game.rep_changed.connect(func(_r: int) -> void: _refresh_markers())
	_refresh_markers()

func reset() -> void:
	_cleanup()
	active = {}
	route = PackedVector3Array()
	event_def = {}
	event_next = 240.0
	event_timer = 0.0
	_refresh_markers()

func def_by_id(id: String) -> Dictionary:
	for d in defs:
		if d["id"] == id:
			return d
	return {}

func lock_reason(d: Dictionary) -> String:
	if bool(d.get("story", false)) and Game.story_stage < int(d.get("story_stage", 0)):
		return "Complete the previous story mission first"
	if Game.rep < int(d.get("req_rep", 0)):
		return "Requires %d reputation" % int(d.get("req_rep", 0))
	return ""

func is_done(d: Dictionary) -> bool:
	return Game.mission_completed(d["id"])

func _refresh_markers() -> void:
	for m in markers:
		var d: Dictionary = m["def"]
		(m["beacon"] as Node3D).visible = lock_reason(d) == "" and active.is_empty()

func all_markers() -> Array:
	var out: Array = []
	for m in markers:
		var d: Dictionary = m["def"]
		out.append({"id": d["id"], "pos": m["pos"], "title": d["title"], "type": d["type"], "locked": lock_reason(d) != "",
			"reason": lock_reason(d), "done": is_done(d), "story": bool(d.get("story", false))})
	return out

func blocks_exit() -> bool:
	return not active.is_empty()

func ignore_police() -> bool:
	return not active.is_empty() and active["def"]["type"] in ["race", "time_trial", "drag", "drift", "challenge", "offroad"] and int(active["def"].get("wanted", 0)) == 0

func start_prompt() -> Dictionary:
	if not active.is_empty() or world.mode != "drive" or _dialog_busy:
		return {}
	var pp: Vector3 = world.player_pos()
	var key: String = Game.key_name("interact")
	if not event_def.is_empty():
		return {"text": "[%s] Accept: %s" % [key, event_def["title"]], "action": _accept_event}
	for m in markers:
		var mp: Vector3 = m["pos"]
		if Vector2(mp.x - pp.x, mp.z - pp.z).length() < 9.0 and absf(mp.y - pp.y) < 10.0:
			var d: Dictionary = m["def"]
			var lr: String = lock_reason(d)
			if lr != "":
				return {"text": "%s - %s" % [d["title"], lr], "action": Callable()}
			return {"text": "[%s] %s: %s" % [key, TYPE_LABEL.get(d["type"], "Mission"), d["title"]], "action": begin.bind(d)}
	return {}

# ---------------------------------------------------------------- start / stop
func begin(d: Dictionary) -> void:
	if not active.is_empty() or _dialog_busy:
		return
	var intro: Array = d.get("intro", [])
	if intro.size() > 0 and world.ui_hooks.has("dialog") and not is_done(d):
		_dialog_busy = true
		world.ui_hooks["dialog"].call(d.get("giver", "rico"), intro, _launch.bind(d))
	else:
		_launch(d)

func _launch(d: Dictionary) -> void:
	_dialog_busy = false
	if world.player_car == null or world.mode != "drive":
		return
	var typ: String = d["type"]
	var st: Dictionary = {"def": d, "time": 0.0, "cp": 0, "score": 0.0, "lap": 0, "extra": 0.0, "last_drift": 0.0, "dmg0": world.player_car.damage,
		"done": false, "elapsed": 0.0, "limit": float(d.get("time_limit", 0.0)), "dist_total": 0.0, "pts": []}
	var start: Vector3 = _start_pos(d)
	var cps: Array = []
	for c in d.get("checkpoints", []):
		var p: Vector3 = world.gen.resolve_point(c)
		var rp: Dictionary = world.gen.nearest_road(p, 60.0)
		if not rp.is_empty():
			p = rp["pos"]
		cps.append(p)
	var laps: int = maxi(1, int(d.get("laps", 1)))
	var all_cps: Array = []
	for l in laps:
		all_cps.append_array(cps)
	st["cps"] = all_cps
	# build the full path used for time limits and opponents
	var full := PackedVector3Array()
	var prev: Vector3 = start
	for c in all_cps:
		var seg: PackedVector3Array = world.nav.route(prev, c)
		if seg.size() > 0:
			full.append_array(seg)
		prev = c
	st["path"] = full
	var total_len: float = 0.0
	for i in range(1, full.size()):
		total_len += full[i].distance_to(full[i - 1])
	st["total_len"] = total_len
	if d.has("pace") and st["limit"] <= 0.0:
		st["limit"] = total_len / float(d["pace"]) + 14.0
	active = st
	if typ in ["race", "drag"]:
		_grid_start(d, start, full)
		countdown = 3.4
	else:
		countdown = 0.0
	if typ == "delivery":
		Game.notify.emit("Cargo loaded - head to the drop-off", "info")
	if d.has("wanted"):
		world.police.set_heat_level(int(d["wanted"]))
	_spawn_checkpoints()
	_refresh_markers()
	Game.notify.emit("Mission started: " + String(d["title"]), "info")
	mission_started.emit(d["id"])
	route_t = 0.0
	if world.ui_hooks.has("mission_hint"):
		world.ui_hooks["mission_hint"].call(d)

func _start_pos(d: Dictionary) -> Vector3:
	if d.get("dynamic", false):
		return d["start_pos"]
	for m in markers:
		if m["def"] == d:
			return m["pos"]
	return world.player_pos()

func _grid_start(d: Dictionary, start: Vector3, path: PackedVector3Array) -> void:
	if path.size() < 3:
		return
	var dir: Vector3 = path[mini(4, path.size() - 1)] - path[0]
	dir.y = 0.0
	dir = dir.normalized()
	var yaw: float = atan2(-dir.x, -dir.z)
	var right := Vector3(-dir.z, 0, dir.x) * -1.0
	right = Vector3(dir.z, 0, -dir.x)
	world.respawn_car_at(path[0] + right * 2.4, yaw)
	var ids: Array = d.get("opp_vehicles", ["strada_s2"])
	var n: int = int(d.get("opponents", 0))
	for i in n:
		var slot: int = i + 1
		var side: float = -1.0 if slot % 2 == 1 else 1.0
		var row: int = (slot + 1) / 2
		var pos: Vector3 = path[0] + right * (2.4 * 0.0 - side * 2.6 + (2.4 if side > 0 else 0.0)) - dir * (6.0 * float(row))
		if side < 0.0:
			pos = path[0] + right * (-2.4) - dir * (7.0 * float(row))
		else:
			pos = path[0] + right * 2.4 - dir * (7.0 * float(row)) + right * 0.0
		if i == 0:
			pos = path[0] - right * 2.4
		elif i == 1:
			pos = path[0] - dir * 7.0 - right * 2.4 if d["type"] != "drag" else path[0] + right * 7.0
		var v := Vehicle.new()
		v.is_police = false
		world.add_child(v)
		var vid: String = ids[i % ids.size()]
		var cust: Dictionary = Data.default_custom(vid)
		cust["paint"] = [0, 3, 5, 7, 10, 11][(i + 2) % 6]
		cust["plate"] = "RIV-%02d" % (i + 11)
		var up: Dictionary = Data.default_upgrades()
		up["engine"] = 1
		up["tyres"] = 1
		v.configure(vid, cust, up, 0.0, 1.0)
		v.place_on_ground(pos, yaw)
		v.set_headlights(world.env.is_night())
		var ai := DriverAI.new(v, float(d.get("opp_skill", 0.6)) + randf_range(-0.05, 0.05))
		ai.set_path(path)
		ai.enabled = false
		world.traffic.others.append(v)
		world.audio.attach_ai_engine(v)
		opp.append({"car": v, "ai": ai, "finished": false, "time": 0.0, "name": Data.vehicle(vid)["name"]})

func _spawn_checkpoints() -> void:
	_clear_cp_nodes()
	var cps: Array = active.get("cps", [])
	for i in cps.size():
		var node := Node3D.new()
		node.position = cps[i]
		world.add_child(node)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 5.2
		tm.outer_radius = 6.2
		tm.rings = 24
		tm.ring_segments = 8
		ring.mesh = tm
		ring.rotation.x = PI * 0.5
		ring.position.y = 6.0
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.85, 0.1)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		ring.material_override = m
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(ring)
		var beam: MeshInstance3D = MeshLib_beam(Color(1.0, 0.85, 0.1))
		node.add_child(beam)
		node.visible = false
		cp_nodes.append({"node": node, "ring": ring, "mat": m})
	_update_cp_visibility()

func MeshLib_beam(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshLib.beam_mesh(1.2, 30.0)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/beam.gdshader")
	sm.set_shader_parameter("beam_color", Vector3(col.r, col.g, col.b))
	sm.set_shader_parameter("strength", 0.6)
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _update_cp_visibility() -> void:
	var cur: int = int(active.get("cp", 0))
	var cps: Array = active.get("cps", [])
	for i in cp_nodes.size():
		var n: Node3D = cp_nodes[i]["node"]
		n.visible = i == cur or i == cur + 1
		var m: StandardMaterial3D = cp_nodes[i]["mat"]
		m.albedo_color = Color(1.0, 0.85, 0.1) if i == cur else Color(0.6, 0.6, 0.65, 1.0)
		if i < cps.size() - 1 or true:
			var nxt: Vector3 = cps[mini(i + 1, cps.size() - 1)]
			var cp: Vector3 = cps[i]
			var d: Vector3 = (nxt - cp) if i < cps.size() - 1 else (cp - (cps[i - 1] if i > 0 else active.get("path", PackedVector3Array([cp - Vector3(0, 0, 1)]))[0]))
			if d.length() > 0.1:
				(cp_nodes[i]["ring"] as Node3D).rotation = Vector3(PI * 0.5, 0, 0)
				n.rotation.y = atan2(-d.x, -d.z)

func _clear_cp_nodes() -> void:
	for c in cp_nodes:
		(c["node"] as Node).queue_free()
	cp_nodes.clear()

func _cleanup() -> void:
	_clear_cp_nodes()
	for o in opp:
		var c: Vehicle = o["car"]
		if is_instance_valid(c):
			world.traffic.others.erase(c)
			c.queue_free()
	opp.clear()
	countdown = 0.0

# ---------------------------------------------------------------- per frame
func _physics_process(dt: float) -> void:
	if not world.running:
		return
	_random_events(dt)
	if active.is_empty():
		return
	var car: Vehicle = world.player_car
	if car == null:
		return
	var d: Dictionary = active["def"]
	var typ: String = d["type"]
	if countdown > 0.0:
		var before: int = int(ceil(countdown))
		countdown -= dt
		if int(ceil(countdown)) != before and countdown > 0.0:
			world.audio.play_ui("beep")
		if countdown <= 0.0:
			world.audio.play_ui("go")
			for o in opp:
				(o["ai"] as DriverAI).enabled = true
			Game.notify.emit("GO!", "good")
		return
	active["elapsed"] += dt
	var limit: float = float(active["limit"])
	if limit > 0.0 and active["elapsed"] > limit:
		if typ == "police":
			_finish(false, "Time ran out - the police still have you")
		elif typ in ["drift", "challenge"]:
			_finish(false, "Time's up")
		else:
			_finish(false, "You ran out of time")
		return
	if car.wrecked:
		return
	var pp: Vector3 = car.global_position
	match typ:
		"race", "time_trial", "drag", "offroad", "delivery":
			_do_checkpoints(dt, pp, d)
			if active.is_empty():
				return
			if typ == "delivery":
				if car.damage - float(active["dmg0"]) > float(d.get("damage_limit", 1.0)):
					_finish(false, "The cargo was damaged")
					return
			if typ in ["race", "drag"]:
				_update_opponents(dt, pp)
		"drift":
			var sp: Vector3 = _start_pos(d)
			if Vector2(sp.x - pp.x, sp.z - pp.z).length() < float(d.get("radius", 120)):
				var dp: float = car.drift_points
				var delta: float = dp - float(active["last_drift"])
				if delta > 0.0 and delta < 400.0:
					active["score"] += delta
				active["last_drift"] = dp
			else:
				active["last_drift"] = car.drift_points
			if active["score"] >= float(d["target"]):
				_finish(true, "Drift score %d" % int(active["score"]))
		"challenge":
			match String(d.get("metric", "speed")):
				"speed":
					active["score"] = maxf(active["score"], car.abs_speed * 3.6)
					if active["score"] >= float(d["target"]):
						_finish(true, "Reached %d km/h" % int(active["score"]))
				"near_miss":
					if active["score"] >= float(d["target"]):
						_finish(true, "%d near misses" % int(active["score"]))
				"air":
					if car.airborne_time > 0.2:
						active["score"] += dt
					if active["score"] >= float(d["target"]):
						_finish(true, "%.1f s of air time" % active["score"])
		"police":
			pass
	route_t -= dt
	if route_t <= 0.0:
		route_t = 2.0
		_update_route(pp)

func on_near_miss() -> void:
	if not active.is_empty() and active["def"]["type"] == "challenge" and active["def"].get("metric", "") == "near_miss":
		active["score"] += 1.0
		Game.notify.emit("Near miss %d / %d" % [int(active["score"]), int(active["def"]["target"])], "good")

func on_police_escaped() -> void:
	if not active.is_empty() and active["def"]["type"] == "police":
		_finish(true, "You lost the police")

func _update_route(pp: Vector3) -> void:
	var cps: Array = active.get("cps", [])
	var cur: int = int(active.get("cp", 0))
	if cur < cps.size():
		route = world.nav.route(pp, cps[cur])
	else:
		route = PackedVector3Array()

func _do_checkpoints(dt: float, pp: Vector3, d: Dictionary) -> void:
	var cps: Array = active["cps"]
	var cur: int = active["cp"]
	if cur >= cps.size():
		return
	var cp: Vector3 = cps[cur]
	if Vector2(cp.x - pp.x, cp.z - pp.z).length() < 11.5 and absf(cp.y - pp.y) < 9.0:
		active["cp"] = cur + 1
		world.audio.play_ui("checkpoint")
		if active["cp"] >= cps.size():
			_complete_course(d)
			return
		Game.notify.emit("Checkpoint %d / %d" % [active["cp"], cps.size()], "info")
		_update_cp_visibility()
		_update_route(pp)

func _complete_course(d: Dictionary) -> void:
	var typ: String = d["type"]
	if typ in ["race", "drag"]:
		var place: int = 1
		for o in opp:
			if o["finished"]:
				place += 1
		active["place"] = place
		if place == 1:
			_finish(true, "1st place - %s" % _fmt_time(active["elapsed"]))
		else:
			_finish(false, "You finished %s" % _ordinal(place))
	else:
		_finish(true, "Time %s" % _fmt_time(active["elapsed"]))

func _update_opponents(dt: float, pp: Vector3) -> void:
	var cps: Array = active["cps"]
	var player_rem: float = _player_remaining(pp)
	for o in opp:
		var ai: DriverAI = o["ai"]
		var c: Vehicle = o["car"]
		if not is_instance_valid(c):
			continue
		if o["finished"]:
			c.set_inputs(0, 0.4, 0, false)
			continue
		var rem: float = ai.remaining()
		var diff: float = rem - player_rem
		ai.speed_scale = clampf(1.0 + diff * 0.0012, 0.9, 1.1)
		ai.update(dt)
		if ai.finished or rem < 14.0:
			o["finished"] = true
			o["time"] = active["elapsed"]

func _player_remaining(pp: Vector3) -> float:
	var cps: Array = active["cps"]
	var cur: int = active["cp"]
	if cur >= cps.size():
		return 0.0
	var r: float = Vector2(cps[cur].x - pp.x, cps[cur].z - pp.z).length()
	for i in range(cur, cps.size() - 1):
		r += Vector2(cps[i].x - cps[i + 1].x, cps[i].z - cps[i + 1].z).length()
	return r

func place_now() -> int:
	if active.is_empty() or opp.is_empty():
		return 0
	var pr: float = _player_remaining(world.player_pos())
	var p: int = 1
	for o in opp:
		if o["finished"] or (is_instance_valid(o["car"]) and (o["ai"] as DriverAI).remaining() < pr):
			p += 1
	return p

func _ordinal(n: int) -> String:
	match n:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
	return "%dth" % n

func _fmt_time(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]

func fail_active(reason: String) -> void:
	if not active.is_empty():
		_finish(false, reason)

func abandon() -> void:
	if not active.is_empty():
		_finish(false, "Mission abandoned")

func _finish(success: bool, text: String) -> void:
	if active.is_empty() or active.get("done", false):
		return
	active["done"] = true
	var d: Dictionary = active["def"]
	var reward: int = int(d.get("reward", 0))
	var rep: int = int(d.get("rep", 0))
	var lines: Array = [text]
	var first: bool = not is_done(d)
	if success:
		if not first:
			reward = reward / 2
			rep = rep / 3
		Game.add_money(reward, "Mission reward")
		Game.add_rep(rep)
		var score: float = float(active["elapsed"])
		var lower: bool = d["type"] in ["time_trial", "offroad", "race", "drag", "delivery"]
		if d["type"] in ["drift", "challenge"]:
			score = float(active["score"])
			lower = false
		Game.record_mission(d["id"], score, lower)
		if d["type"] in ["race", "drag"]:
			Game.stats["races_won"] = int(Game.stats["races_won"]) + 1
		if bool(d.get("story", false)) and Game.story_stage == int(d.get("story_stage", 0)):
			Game.story_stage = int(d.get("story_next", Game.story_stage + 1))
		lines.append("Reward: " + Game.fmt_money(reward) + "   Rep +" + str(rep))
		if first and bool(d.get("story", false)):
			lines.append("Story progress updated")
		world.audio.play_ui("win")
	else:
		world.audio.play_ui("fail")
		if d["type"] in ["race", "drag"] and active.get("place", 0) > 1:
			var cons: int = int(float(d.get("reward", 0)) * 0.05)
			lines.append("No prize this time")
	var outro: Array = d.get("outro", [])
	var giver: String = d.get("giver", "rico")
	_cleanup()
	var was_dynamic: bool = d.get("dynamic", false)
	active = {}
	route = PackedVector3Array()
	if d.has("wanted") or d["type"] == "police":
		if not success and world.police.level > 0:
			pass
	_refresh_markers()
	mission_finished.emit(d["id"], success)
	if world.ui_hooks.has("mission_result"):
		world.ui_hooks["mission_result"].call(success, String(d["title"]), lines, giver, outro if success else [])
	Game.save_game()

# ---------------------------------------------------------------- HUD info
func hud_info() -> Dictionary:
	if active.is_empty():
		return {}
	var d: Dictionary = active["def"]
	var info: Dictionary = {"title": d["title"], "type": d["type"], "line": "", "timer": -1.0, "sub": ""}
	var lim: float = float(active["limit"])
	if lim > 0.0:
		info["timer"] = maxf(0.0, lim - float(active["elapsed"]))
	else:
		info["timer"] = float(active["elapsed"])
		info["count_up"] = true
	if countdown > 0.0:
		info["line"] = str(int(ceil(countdown)))
		info["big"] = true
		return info
	match d["type"]:
		"race", "drag":
			info["line"] = "Position %s / %d" % [_ordinal(place_now()), opp.size() + 1]
			info["sub"] = "Checkpoint %d / %d" % [mini(int(active["cp"]) + 1, (active["cps"] as Array).size()), (active["cps"] as Array).size()]
		"time_trial", "offroad":
			info["line"] = "Checkpoint %d / %d" % [mini(int(active["cp"]) + 1, (active["cps"] as Array).size()), (active["cps"] as Array).size()]
		"delivery":
			info["line"] = "Deliver the cargo"
			var dl: float = world.player_pos().distance_to(active["cps"][active["cp"]]) if int(active["cp"]) < (active["cps"] as Array).size() else 0.0
			info["sub"] = "%s to go   Cargo damage %d%%" % [Game.dist_label(dl), int(maxf(0.0, world.player_car.damage - float(active["dmg0"])) * 100.0)]
		"drift":
			info["line"] = "Drift %d / %d" % [int(active["score"]), int(d["target"])]
		"challenge":
			var mt: String = String(d.get("metric", "speed"))
			if mt == "speed":
				info["line"] = "Speed %d / %d km/h" % [int(world.player_car.abs_speed * 3.6), int(d["target"])]
			elif mt == "near_miss":
				info["line"] = "Near misses %d / %d" % [int(active["score"]), int(d["target"])]
			else:
				info["line"] = "Air time %.1f / %.1f s" % [active["score"], float(d["target"])]
		"police":
			info["line"] = "Lose the police"
			info["sub"] = "Wanted level %d" % world.police.level
	return info

# ---------------------------------------------------------------- random events
func _random_events(dt: float) -> void:
	if not event_def.is_empty():
		event_timer -= dt
		if event_timer <= 0.0 or not active.is_empty():
			event_def = {}
			if not active.is_empty():
				return
			Game.notify.emit("The challenge expired", "info")
		return
	if not active.is_empty() or world.mode != "drive" or world.police.level > 0:
		return
	event_next -= dt
	if event_next > 0.0:
		return
	event_next = randf_range(300.0, 520.0)
	var pp: Vector3 = world.player_pos()
	var rp: Dictionary = world.gen.nearest_road(pp, 30.0)
	if rp.is_empty() or world.player_car.abs_speed < 5.0:
		event_next = 40.0
		return
	var fwd: Vector3 = -world.player_car.global_transform.basis.z
	var tgt: Vector3 = pp + fwd * 650.0
	var tr: Dictionary = world.gen.nearest_road(tgt, 150.0)
	if tr.is_empty():
		event_next = 40.0
		return
	var dest: Vector3 = tr["pos"]
	event_def = {"id": "ev_rival_%d" % randi(), "type": "race", "dynamic": true, "title": "Kane's Street Sprint", "giver": "kane",
		"start_pos": rp["pos"], "checkpoints": [[dest.x, dest.z]], "opponents": 1, "opp_skill": 0.65, "opp_vehicles": ["brawler_69"],
		"reward": 1800, "rep": 10, "desc": "A rival flashes his lights. Beat him to the marker.", "intro": [], "outro": ["Not bad. See you around."]}
	event_timer = 18.0
	Game.notify.emit("A rival challenges you to a sprint!", "warn")

func _accept_event() -> void:
	var d: Dictionary = event_def
	event_def = {}
	_launch(d)
