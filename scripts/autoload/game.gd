extends Node
## Global game state: money, reputation, garage, settings, saving, input map.
## Everything else talks to this through signals so systems stay independent.

signal money_changed(amount: int)
signal rep_changed(amount: int)
signal notify(text: String, kind: String)
signal settings_changed
signal garage_changed
signal wanted_changed(level: int)
signal mission_state_changed
signal collectible_found(id: String, total: int)
signal location_discovered(id: String)

const SAVE_PATH := "user://save.json"
const SAVE_BAK := "user://save.bak"
const SAVE_TMP := "user://save.tmp"
const SAVE_VERSION := 1
const START_MONEY := 3000
const START_VEHICLE := "bmw_m6"

var money: int = START_MONEY
var rep: int = 0
var retired_refund: int = 0           # money refunded for cars of the retired collection (shown once after loading)
var owned: Dictionary = {}              # vid -> {upg:{}, custom:{}, damage:float, fuel:float}
var selected: String = START_VEHICLE
var missions_done: Dictionary = {}      # id -> {count:int, best:float}
var collectibles: Array = []            # ids found
var discovered: Array = []              # location ids discovered
var story_stage: int = 0
var garage_slots: int = 4
var player_pos: Vector3 = Vector3.ZERO
var player_rot: float = 0.0
var time_of_day: float = 9.0           # hours
var weather_state: String = "clear"
var stats: Dictionary = {"distance": 0.0, "races_won": 0, "drift_best": 0.0, "top_speed": 0.0, "play_time": 0.0, "busted": 0}
var has_save: bool = false
var in_world: bool = false
var autosave_timer: float = 0.0
var wanted_level: int = 0

var settings: Dictionary = {}
const DEFAULT_SETTINGS := {
	"quality": "Medium", "shadows": true, "reflections": true, "aa": 0, "view_distance": 3, "texture_quality": 1,
	"traffic_density": 1.0, "vsync": true, "fullscreen": false, "res_scale": 1.0,
	"master": 0.9, "music": 0.55, "engine": 0.8, "environment": 0.7, "effects": 0.8,
	"mouse_sens": 1.0, "steer_sens": 1.0, "camera_sens": 1.0, "tilt_steer": false, "touch_opacity": 0.75,
	"handling": "arcade", "units": "kmh", "minimap_size": 1.0, "minimap_rotate": true, "cam_distance": 1.0,
	"cam_shake": true, "haptics": true, "keys": {}, "headlights_auto": true, "tilt_invert": false, "tilt_sens": 1.0, "tilt_dead": 3.0, "show_touch": false,
}
const QUALITY_PRESETS := {
	"Low":    {"shadows": false, "aa": 0, "view_distance": 2, "texture_quality": 0, "traffic_density": 0.5, "reflections": false, "res_scale": 0.7},
	"Medium": {"shadows": true, "aa": 0, "view_distance": 3, "texture_quality": 1, "traffic_density": 0.8, "reflections": false, "res_scale": 0.85},
	"High":   {"shadows": true, "aa": 2, "view_distance": 4, "texture_quality": 2, "traffic_density": 1.0, "reflections": true, "res_scale": 1.0},
	"Ultra":  {"shadows": true, "aa": 4, "view_distance": 5, "texture_quality": 2, "traffic_density": 1.4, "reflections": true, "res_scale": 1.0},
}

var is_mobile: bool = false

func _ready() -> void:
	is_mobile = OS.has_feature("android") or OS.has_feature("ios") or DisplayServer.is_touchscreen_available()
	settings = DEFAULT_SETTINGS.duplicate(true)
	if is_mobile:
		settings["quality"] = "Low"
		_apply_preset_values("Low")
	_load_settings_only()
	_setup_input()
	reset_progress()
	has_save = FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(SAVE_BAK)
	apply_display_settings()

func reset_progress() -> void:
	money = START_MONEY
	rep = 0
	owned = {}
	grant_starters()
	selected = START_VEHICLE
	missions_done = {}
	collectibles = []
	discovered = []
	story_stage = 0
	garage_slots = 4
	player_pos = Vector3.ZERO
	player_rot = 0.0
	time_of_day = 9.0
	weather_state = "clear"
	stats = {"distance": 0.0, "races_won": 0, "drift_best": 0.0, "top_speed": 0.0, "play_time": 0.0, "busted": 0}
	wanted_level = 0

func new_vehicle_record(vid: String) -> Dictionary:
	return {"upg": Data.default_upgrades(), "custom": Data.default_custom(vid), "damage": 0.0, "fuel": 1.0}

# ---------------------------------------------------------------- economy
func add_money(n: int, reason: String = "") -> void:
	money = maxi(0, money + n)
	money_changed.emit(money)
	if reason != "" and n != 0:
		notify.emit("%s%s $%s" % ["+" if n > 0 else "-", reason + "  ", _fmt(absi(n))], "money" if n > 0 else "warn")

func spend(n: int) -> bool:
	if money < n:
		notify.emit("Not enough money", "warn")
		return false
	money -= n
	money_changed.emit(money)
	return true

func add_rep(n: int) -> void:
	rep += n
	rep_changed.emit(rep)

func rep_level() -> int:
	return int(floor(sqrt(float(rep) / 25.0))) + 1

func rep_required(vid: String) -> int:
	if Data.PERMANENT_VEHICLES.has(vid):
		return 0          # money is the only requirement of the sci-fi buggy
	var p: int = int(Data.vehicle(vid)["price"])
	if p < 20000: return 0
	if p < 45000: return 100
	if p < 80000: return 300
	if p < 150000: return 700
	return 1500

func _fmt(n: int) -> String:
	var s: String = str(n)
	var out: String = ""
	var c: int = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out

func fmt_money(n: int) -> String:
	return "$" + _fmt(n)

## The four free starting cars (Data.STARTER_VEHICLES): added when missing (new game, and old saves on load). Never touches
## money, REP, damage / fuel of cars the player already owns, or the selected car.
func grant_starters() -> void:
	for sid in Data.STARTER_VEHICLES:
		if not owned.has(sid):
			owned[sid] = new_vehicle_record(sid)

## Garage slots in use: starters and free pick-ups (airport cart) are always kept and never take a slot.
func slots_used() -> int:
	var n: int = 0
	for oid in owned:
		if not Data.is_permanent(String(oid)):
			n += 1
	return n

func buy_vehicle(vid: String) -> bool:
	if owned.has(vid):
		return false
	if slots_used() >= garage_slots and not Data.PERMANENT_VEHICLES.has(vid):
		notify.emit("Garage full - sell a car or expand the garage", "warn")
		return false
	if rep < rep_required(vid):
		notify.emit("Need %d reputation" % rep_required(vid), "warn")
		return false
	var price: int = int(Data.vehicle(vid)["price"])
	if not spend(price):
		return false
	owned[vid] = new_vehicle_record(vid)
	selected = vid
	garage_changed.emit()
	notify.emit("Purchased %s" % Data.vehicle(vid)["name"], "money")
	save_game()
	return true

## Free world pick-up (the airport shuttle cart): no money, REP, mission or garage-slot cost. Returns true when newly added.
func claim_free_vehicle(vid: String) -> bool:
	if not Data.is_free_vehicle(vid):
		return false
	var added: bool = false
	if not owned.has(vid):
		owned[vid] = new_vehicle_record(vid)
		added = true
	selected = vid
	garage_changed.emit()
	if added:
		notify.emit("%s added to your garage - free" % Data.vehicle(vid)["name"], "info")
	save_game()
	return added

func sell_vehicle(vid: String) -> bool:
	if Data.is_permanent(vid):
		notify.emit("This vehicle cannot be sold", "warn")
		return false
	if not owned.has(vid) or owned.size() <= 1:
		notify.emit("You must keep at least one car", "warn")
		return false
	var val: int = Data.sell_value(vid, owned[vid]["upg"])
	owned.erase(vid)
	if selected == vid:
		selected = owned.keys()[0]
	add_money(val, "Sold")
	garage_changed.emit()
	save_game()
	return true

func expand_garage() -> bool:
	var cost: int = 8000 * (garage_slots - 3)
	if garage_slots >= 12:
		notify.emit("Garage is at maximum size", "warn")
		return false
	if not spend(cost):
		return false
	garage_slots += 1
	garage_changed.emit()
	return true

func expand_cost() -> int:
	return 8000 * (garage_slots - 3)

func buy_upgrade(vid: String, part: String) -> bool:
	var rec: Dictionary = owned[vid]
	var lvl: int = int(rec["upg"].get(part, 0))
	if lvl >= Data.MAX_UPGRADE_LEVEL:
		return false
	var cost: int = Data.upgrade_cost(vid, part, lvl + 1)
	if not spend(cost):
		return false
	rec["upg"][part] = lvl + 1
	garage_changed.emit()
	return true

func buy_custom(vid: String, key: String, value: Variant) -> bool:
	var rec: Dictionary = owned[vid]
	if rec["custom"].get(key) == value:
		return true
	var cost: int = int(Data.CUSTOM_COST.get(key, 100))
	if key == "plate":
		cost = 100
	if not spend(cost):
		return false
	rec["custom"][key] = value
	garage_changed.emit()
	return true

func repair_cost(vid: String) -> int:
	var d: float = float(owned[vid].get("damage", 0.0))
	return int(d * 900.0 / 10.0) * 10

func repair(vid: String) -> bool:
	var c: int = repair_cost(vid)
	if c <= 0:
		return true
	if not spend(c):
		return false
	owned[vid]["damage"] = 0.0
	garage_changed.emit()
	return true

# ---------------------------------------------------------------- missions
func mission_completed(id: String) -> bool:
	return missions_done.has(id)

func record_mission(id: String, score: float, better_is_lower: bool) -> void:
	var r: Dictionary = missions_done.get(id, {"count": 0, "best": -1.0})
	r["count"] = int(r["count"]) + 1
	var b: float = float(r["best"])
	if b < 0.0 or (better_is_lower and score < b) or (not better_is_lower and score > b):
		r["best"] = score
	missions_done[id] = r
	mission_state_changed.emit()

func add_collectible(id: String) -> bool:
	if id in collectibles:
		return false
	collectibles.append(id)
	collectible_found.emit(id, collectibles.size())
	return true

func discover(id: String) -> void:
	if id in discovered:
		return
	discovered.append(id)
	location_discovered.emit(id)

func set_wanted(l: int) -> void:
	if l != wanted_level:
		wanted_level = l
		wanted_changed.emit(l)

# ---------------------------------------------------------------- settings
func _apply_preset_values(q: String) -> void:
	var p: Dictionary = QUALITY_PRESETS[q]
	for k in p:
		settings[k] = p[k]

func set_quality(q: String) -> void:
	settings["quality"] = q
	_apply_preset_values(q)
	apply_display_settings()
	settings_changed.emit()
	save_settings_only()

func set_setting(k: String, v: Variant) -> void:
	settings[k] = v
	if k in ["shadows", "aa", "view_distance", "texture_quality", "traffic_density", "reflections", "res_scale"]:
		settings["quality"] = "Custom"
	apply_display_settings()
	settings_changed.emit()

func apply_display_settings() -> void:
	if not is_inside_tree():
		return
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(int(settings["aa"]) / 2, 0, 2)] if int(settings["aa"]) in [0, 2, 4] else Viewport.MSAA_DISABLED
	vp.scaling_3d_scale = clampf(float(settings["res_scale"]), 0.5, 1.0)
	if not DisplayServer.get_name() == "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(settings["vsync"]) else DisplayServer.VSYNC_DISABLED)
		if not is_mobile:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(settings["fullscreen"]) else DisplayServer.WINDOW_MODE_WINDOWED)
	_apply_audio_buses()

func _apply_audio_buses() -> void:
	for b in ["Music", "Engine", "Environment", "Effects"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var idx: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	var map: Dictionary = {"Master": "master", "Music": "music", "Engine": "engine", "Environment": "environment", "Effects": "effects"}
	for b in map:
		var i: int = AudioServer.get_bus_index(b)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(0.0001, float(settings[map[b]]))))

func speed_to_display(ms: float) -> float:
	return ms * (3.6 if settings["units"] == "kmh" else 2.23694)

func unit_label() -> String:
	return "KM/H" if settings["units"] == "kmh" else "MPH"

func dist_label(m: float) -> String:
	if settings["units"] == "kmh":
		return "%d m" % int(m) if m < 1000.0 else "%.1f km" % (m / 1000.0)
	var ft: float = m * 3.28084
	return "%d ft" % int(ft) if m < 500.0 else "%.1f mi" % (m / 1609.34)

# ---------------------------------------------------------------- input map
const DEFAULT_KEYS := {
	"accelerate": KEY_W, "brake": KEY_S, "steer_left": KEY_A, "steer_right": KEY_D, "handbrake": KEY_SPACE,
	"interact": KEY_E, "camera": KEY_C, "pause": KEY_ESCAPE, "map": KEY_M, "headlights": KEY_L,
	"horn": KEY_H, "nitro": KEY_SHIFT, "reset_car": KEY_R, "foot_forward": KEY_W, "foot_back": KEY_S,
	"foot_left": KEY_A, "foot_right": KEY_D, "sprint": KEY_SHIFT, "jump": KEY_SPACE, "exit_vehicle": KEY_F,
	"indicator_left": KEY_Z, "indicator_right": KEY_X,
}
const REMAPPABLE := ["accelerate", "brake", "steer_left", "steer_right", "handbrake", "interact", "camera", "map", "headlights", "horn", "nitro", "reset_car", "exit_vehicle", "indicator_left", "indicator_right"]

func _setup_input() -> void:
	for a in DEFAULT_KEYS:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.2)
		InputMap.action_erase_events(a)
		var code: int = int(settings["keys"].get(a, DEFAULT_KEYS[a]))
		var ev := InputEventKey.new()
		ev.physical_keycode = code as Key
		InputMap.action_add_event(a, ev)
	# arrow keys as secondary bindings
	_add_key("accelerate", KEY_UP); _add_key("brake", KEY_DOWN); _add_key("steer_left", KEY_LEFT); _add_key("steer_right", KEY_RIGHT)
	_add_key("foot_forward", KEY_UP); _add_key("foot_back", KEY_DOWN); _add_key("foot_left", KEY_LEFT); _add_key("foot_right", KEY_RIGHT)
	# gamepad
	_add_axis("accelerate", JOY_AXIS_TRIGGER_RIGHT, 1.0); _add_axis("brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_axis("steer_left", JOY_AXIS_LEFT_X, -1.0); _add_axis("steer_right", JOY_AXIS_LEFT_X, 1.0)
	_add_axis("foot_left", JOY_AXIS_LEFT_X, -1.0); _add_axis("foot_right", JOY_AXIS_LEFT_X, 1.0)
	_add_axis("foot_forward", JOY_AXIS_LEFT_Y, -1.0); _add_axis("foot_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_btn("handbrake", JOY_BUTTON_B); _add_btn("interact", JOY_BUTTON_Y); _add_btn("camera", JOY_BUTTON_RIGHT_STICK)
	_add_btn("pause", JOY_BUTTON_START); _add_btn("map", JOY_BUTTON_BACK); _add_btn("headlights", JOY_BUTTON_LEFT_SHOULDER)
	_add_btn("horn", JOY_BUTTON_RIGHT_SHOULDER); _add_btn("nitro", JOY_BUTTON_X); _add_btn("jump", JOY_BUTTON_A)
	_add_btn("reset_car", JOY_BUTTON_DPAD_DOWN); _add_btn("indicator_left", JOY_BUTTON_DPAD_LEFT); _add_btn("indicator_right", JOY_BUTTON_DPAD_RIGHT); _add_btn("sprint", JOY_BUTTON_LEFT_STICK)

func _add_key(a: String, k: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k as Key
	InputMap.action_add_event(a, ev)

func _add_axis(a: String, axis: int, dir: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis as JoyAxis
	ev.axis_value = dir
	InputMap.action_add_event(a, ev)

func _add_btn(a: String, b: int) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = b as JoyButton
	InputMap.action_add_event(a, ev)

func remap(action: String, keycode: int) -> void:
	settings["keys"][action] = keycode
	if action == "accelerate": settings["keys"]["foot_forward"] = keycode
	if action == "brake": settings["keys"]["foot_back"] = keycode
	if action == "steer_left": settings["keys"]["foot_left"] = keycode
	if action == "steer_right": settings["keys"]["foot_right"] = keycode
	_setup_input()
	save_settings_only()

func key_name(action: String) -> String:
	var code: int = int(settings["keys"].get(action, DEFAULT_KEYS.get(action, 0)))
	return OS.get_keycode_string(code as Key)

# ---------------------------------------------------------------- save / load
func _process(delta: float) -> void:
	if in_world:
		autosave_timer += delta
		stats["play_time"] = float(stats["play_time"]) + delta
		if autosave_timer > 90.0:
			autosave_timer = 0.0
			save_game()
			notify.emit("Autosaved", "info")

func _snapshot() -> Dictionary:
	return {
		"money": money, "rep": rep, "owned": owned, "selected": selected, "missions_done": missions_done,
		"collectibles": collectibles, "discovered": discovered, "story_stage": story_stage, "garage_slots": garage_slots,
		"player_pos": [player_pos.x, player_pos.y, player_pos.z], "player_rot": player_rot,
		"time_of_day": time_of_day, "weather": weather_state, "stats": stats, "settings": settings,
	}

func save_game() -> bool:
	var body: String = JSON.stringify({"v": SAVE_VERSION, "data": _snapshot()})
	var wrapped: String = JSON.stringify({"sum": body.hash(), "len": body.length(), "body": body})
	return _write_safely(wrapped)

func save_settings_only() -> void:
	# settings live inside the save; when no save exists yet, keep a standalone copy
	var f := FileAccess.open("user://settings.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))
		f.close()

func _load_settings_only() -> void:
	if FileAccess.file_exists("user://settings.json"):
		var f := FileAccess.open("user://settings.json", FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				_merge_settings(parsed)

func _merge_settings(d: Dictionary) -> void:
	for k in d:
		if DEFAULT_SETTINGS.has(k):
			settings[k] = d[k]
	if not (settings["keys"] is Dictionary):
		settings["keys"] = {}

func _write_safely(text: String) -> bool:
	var f := FileAccess.open(SAVE_TMP, FileAccess.WRITE)
	if f == null:
		push_warning("Cannot open save temp file")
		return false
	f.store_string(text)
	f.close()
	# verify what we wrote before replacing the good save
	var chk := FileAccess.open(SAVE_TMP, FileAccess.READ)
	if chk == null or chk.get_as_text() != text:
		return false
	chk.close()
	var da := DirAccess.open("user://")
	if da == null:
		return false
	if FileAccess.file_exists(SAVE_PATH):
		if FileAccess.file_exists(SAVE_BAK):
			da.remove("save.bak")
		da.rename("save.json", "save.bak")
	var err: int = da.rename("save.tmp", "save.json")
	has_save = err == OK
	save_settings_only()
	return err == OK

func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt: String = f.get_as_text()
	f.close()
	var outer: Variant = JSON.parse_string(txt)
	if not (outer is Dictionary) or not outer.has("body") or not outer.has("sum"):
		return {}
	var body: String = String(outer["body"])
	if int(outer["sum"]) != body.hash() or int(outer.get("len", -1)) != body.length():
		return {}
	var inner: Variant = JSON.parse_string(body)
	if inner is Dictionary and inner.has("data") and inner["data"] is Dictionary:
		return inner["data"]
	return {}

func load_game() -> bool:
	var d: Dictionary = _read_save(SAVE_PATH)
	if d.is_empty():
		d = _read_save(SAVE_BAK)
		if not d.is_empty():
			notify.emit("Save was damaged - restored backup", "warn")
	if d.is_empty():
		return false
	reset_progress()
	money = int(d.get("money", START_MONEY))
	rep = int(d.get("rep", 0))
	var o: Variant = d.get("owned", {})
	if o is Dictionary and not o.is_empty():
		owned = {}
		for vid in o:
			if Data.vehicle_ids().has(vid):
				var rec: Dictionary = new_vehicle_record(vid)
				var src: Dictionary = o[vid]
				rec["upg"].merge(src.get("upg", {}), true)
				rec["custom"].merge(src.get("custom", {}), true)
				rec["damage"] = float(src.get("damage", 0.0))
				rec["fuel"] = float(src.get("fuel", 1.0))
				owned[vid] = rec
	# cars of the retired collection: refund their sale value (they can no longer be driven or bought)
	if o is Dictionary:
		for old_vid in o:
			if not Data.in_collection(String(old_vid)) and Data.vehicle(String(old_vid))["id"] == String(old_vid):
				var osrc: Dictionary = o[old_vid]
				var oupg: Dictionary = Data.default_upgrades()
				oupg.merge(osrc.get("upg", {}), true)
				money += Data.sell_value(String(old_vid), oupg)
				retired_refund += Data.sell_value(String(old_vid), oupg)
	grant_starters()   # old saves (and saves that sold the BMW) always own the four free starting cars
	selected = String(d.get("selected", START_VEHICLE))
	if not owned.has(selected):
		selected = START_VEHICLE if owned.has(START_VEHICLE) else owned.keys()[0]
	if not owned.has(START_VEHICLE):
		# older saves: the imported BMW M6 is the new primary car - grant it, and switch only players still on the old starter
		owned[START_VEHICLE] = new_vehicle_record(START_VEHICLE)
		if selected == "pico_h1":
			selected = START_VEHICLE
	missions_done = d.get("missions_done", {})
	collectibles = d.get("collectibles", [])
	discovered = d.get("discovered", [])
	story_stage = int(d.get("story_stage", 0))
	garage_slots = int(d.get("garage_slots", 4))
	var pp: Variant = d.get("player_pos", [0, 0, 0])
	if pp is Array and pp.size() == 3:
		player_pos = Vector3(float(pp[0]), float(pp[1]), float(pp[2]))
	player_rot = float(d.get("player_rot", 0.0))
	time_of_day = float(d.get("time_of_day", 9.0))
	weather_state = String(d.get("weather", "clear"))
	var st: Variant = d.get("stats", {})
	if st is Dictionary:
		stats.merge(st, true)
	var s: Variant = d.get("settings", {})
	if s is Dictionary:
		_merge_settings(s)
	_setup_input()
	apply_display_settings()
	money_changed.emit(money)
	rep_changed.emit(rep)
	garage_changed.emit()
	return true

func new_game() -> void:
	reset_progress()
	garage_changed.emit()
	money_changed.emit(money)
	rep_changed.emit(rep)
