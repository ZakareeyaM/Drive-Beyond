class_name VehicleModels
extends RefCounted
## Registry of externally-sourced (GLB) vehicle models.
## To add another car: drop its .glb into assets/vehicles/, add one entry here (units are the
## GLB's own units; "scale" converts to metres) and a matching entry in Data.VEHICLES
## (same id) whose L/W/wb/track/wr match the scaled model.  Nothing else needs to change.
##
##  glb          res:// path of the model
##  scale        model units -> metres
##  yaw_deg      extra rotation so that the car's nose points to -Z (Godot forward)
##  wheel_seeds  approximate wheel centres (model units). Every mesh piece that lies fully inside a
##               cylinder (axis = X) of wheel_radius / wheel_half_width around a seed belongs to that wheel.
##               Order: front -X, front +X, rear -X, rear +X  (front = nose side, i.e. smaller z).
##  origin       model-space point that becomes the car origin (x/z centre between the axles, y = ground)
##  head / tail  light overlay shapes (model units); used for emissive head/brake lights
##  glass        quads (4 corners, model units) for tinted window glass
##  collision    boxes {min,max} in model units -> physics shapes (kept separate from the visual mesh)
##  cam          optional camera tweak {dist: multiplier, height: metres added}
##  engine_sound optional res:// sound loop used instead of the procedural engine
const REGISTRY := {
	"bmw_m6": {
		"glb": "res://assets/vehicles/bmw_m6_1988_custom.glb",
		"scale": 2.0,
		"yaw_deg": 0.0,
		"wheel_seeds": [Vector3(0.11, 0.155, -0.2), Vector3(0.89, 0.155, -0.2), Vector3(0.11, 0.155, 1.13), Vector3(0.89, 0.155, 1.13)],
		"wheel_radius": 0.17,
		"wheel_half_width": 0.1,
		"head_lamps": [Vector3(0.22, 0.28, -0.518), Vector3(0.32, 0.28, -0.518), Vector3(0.68, 0.28, -0.518), Vector3(0.78, 0.28, -0.518)],
		"head_lamp_radius": 0.04,
		"head_spots": [Vector3(0.27, 0.28, -0.53), Vector3(0.73, 0.28, -0.53)],
		"tail_lamps": [{"pos": Vector3(0.2, 0.3, 1.566), "size": Vector3(0.19, 0.075, 0.008)}, {"pos": Vector3(0.8, 0.3, 1.566), "size": Vector3(0.19, 0.075, 0.008)}],
		"glass": [
			[Vector3(0.17, 0.405, 0.085), Vector3(0.83, 0.405, 0.085), Vector3(0.83, 0.64, 0.345), Vector3(0.17, 0.64, 0.345)],
			[Vector3(0.21, 0.6, 0.86), Vector3(0.79, 0.6, 0.86), Vector3(0.79, 0.41, 1.3), Vector3(0.21, 0.41, 1.3)],
			[Vector3(0.18, 0.648, 0.345), Vector3(0.82, 0.648, 0.345), Vector3(0.82, 0.648, 0.86), Vector3(0.18, 0.648, 0.86)],
			[Vector3(0.105, 0.42, 0.16), Vector3(0.105, 0.64, 0.36), Vector3(0.105, 0.64, 0.7), Vector3(0.105, 0.42, 1.28)],
			[Vector3(0.895, 0.42, 0.16), Vector3(0.895, 0.64, 0.36), Vector3(0.895, 0.64, 0.7), Vector3(0.895, 0.42, 1.28)],
		],
		"collision": [
			{"min": Vector3(0.05, 0.06, -0.5), "max": Vector3(0.95, 0.42, 1.5)},      # main body + side panels
			{"min": Vector3(0.07, 0.05, -0.576), "max": Vector3(0.93, 0.3, -0.46)},    # front bumper
			{"min": Vector3(0.07, 0.05, 1.45), "max": Vector3(0.93, 0.3, 1.576)},      # rear bumper
			{"min": Vector3(0.12, 0.42, 0.08), "max": Vector3(0.88, 0.7, 1.3)},        # cabin
		],
		"cam": {"dist": 1.0, "height": 0.0},
		"engine_sound": "res://assets/audio/Car_Engine.mp3",
		"engine_loop_offset": 4.0,
		"engine_pitch": [0.75, 1.9],
	},
}

static var _pack_cache: Dictionary = {}

static func has(vid: String) -> bool:
	return REGISTRY.has(vid) or is_pack(vid) or is_fleet(vid)

static var _fleet_cache: Dictionary = {}

static func is_fleet(vid: String) -> bool:
	return _fleet(vid).size() > 0

static func _fleet(vid: String) -> Dictionary:
	if _fleet_cache.is_empty():
		for e in FleetVehicles.LIST:
			_fleet_cache[e["spec"]["id"]] = e
		_fleet_cache["_"] = {}
	return _fleet_cache.get(vid, {})

## Config of a collection car (assets/vehicles/fleet/<id>.glb: Body + Wheel_0..3, metres, origin on the ground between
## the axles, nose = -Z).  Collision = 3 boxes derived from the measured model; lamps come from the model's own lamp
## surfaces (see GlbVehicle._split_lamps); "headlight" = optional per-vehicle overrides for HeadlightConfig.
static func _fleet_cfg(vid: String) -> Dictionary:
	var e: Dictionary = _fleet(vid)
	var m: Dictionary = e["model"]
	var sp: Dictionary = e["spec"]
	var H: float = float(m["height"])
	var zmin: float = float(m["zmin"])
	var zmax: float = float(m["zmax"])
	var L: float = zmax - zmin
	var W: float = float(sp["W"])
	var lo_h: float = H * 0.55
	var pc: Array = m["paint_rgb"]
	return {
		"fleet": true, "glb": "res://assets/vehicles/fleet/%s.glb" % vid, "scale": 1.0,
		"paint_rgb": Color(pc[0], pc[1], pc[2]),
		"headlight": e.get("headlight", {}),
		"collision_pack": [
			{"pos": Vector3(0, 0.2 + (lo_h - 0.2) * 0.5, (zmin + zmax) * 0.5), "size": Vector3(W * 0.94, lo_h - 0.2, L * 0.97)},
			{"pos": Vector3(0, lo_h + (H * 0.95 - lo_h) * 0.5, zmin + L * 0.55), "size": Vector3(W * 0.7, H * 0.95 - lo_h, L * 0.42)},
		],
		"cam": {"dist": 1.0, "height": maxf(0.0, H - 1.3) * 0.8},
	}

static func is_pack(vid: String) -> bool:
	return _pack(vid).size() > 0

static func _pack(vid: String) -> Dictionary:
	if _pack_cache.is_empty():
		for e in PackVehicles.LIST:
			_pack_cache[e["spec"]["id"]] = e
		_pack_cache["_"] = {}
	return _pack_cache.get(vid, {})

## Config of a traffic-pack car (assets/vehicles/pack/<id>.glb, already in metres / car space).
## Lamp, glass and collision data are derived from the measured model dimensions.
static func _pack_cfg(vid: String) -> Dictionary:
	var e: Dictionary = _pack(vid)
	var m: Dictionary = e["model"]
	var sp: Dictionary = e["spec"]
	var H: float = float(m["height"])
	var W: float = float(sp["W"])
	var zmin: float = float(m["zmin"])
	var zmax: float = float(m["zmax"])
	var hw: float = float(m["width"]) * 0.5
	var L: float = zmax - zmin
	var hy: float = H * 0.45
	var ty: float = H * 0.52
	var lx: float = hw * 0.62
	var lo_h: float = H * 0.58
	var cfgd: Dictionary = {
		"pack": true, "glb": "res://assets/vehicles/pack/%s.glb" % vid, "scale": 1.0,
		"paint_rgb": Color(m["paint_rgb"][0], m["paint_rgb"][1], m["paint_rgb"][2]),
		"head_spots": [Vector3(-lx, hy, zmin), Vector3(lx, hy, zmin)],
		"tail_lamps": [{"pos": Vector3(-lx, ty, zmax), "size": Vector3(0.28, 0.1, 0.02)}, {"pos": Vector3(lx, ty, zmax), "size": Vector3(0.28, 0.1, 0.02)}],
		"head_lamps": [Vector3(-lx, hy, zmin), Vector3(lx, hy, zmin)],
		"glass": [],
		"collision_pack": [
			{"pos": Vector3(0, 0.22 + (lo_h - 0.22) * 0.5, (zmin + zmax) * 0.5), "size": Vector3(W, lo_h - 0.22, L * 0.98)},
			{"pos": Vector3(0, lo_h + (H * 0.97 - lo_h) * 0.5, zmin + L * 0.52), "size": Vector3(W * 0.88, H * 0.97 - lo_h, L * 0.46)},
		],
		"cam": {"dist": 1.0, "height": maxf(0.0, H - 1.5) * 0.8},
	}
	return cfgd

static func cfg(vid: String) -> Dictionary:
	if REGISTRY.has(vid):
		return REGISTRY[vid]
	if is_fleet(vid):
		if not _fleet_cache.has("cfg_" + vid):
			_fleet_cache["cfg_" + vid] = _fleet_cfg(vid)
		return _fleet_cache["cfg_" + vid]
	if is_pack(vid):
		if not _pack_cache.has("cfg_" + vid):
			_pack_cache["cfg_" + vid] = _pack_cfg(vid)
		return _pack_cache["cfg_" + vid]
	return {}
