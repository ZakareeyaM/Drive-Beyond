extends Node
## Static game data: vehicles, upgrades, customisation options, characters.
## Add a new vehicle by appending one Dictionary to VEHICLES - everything else
## (dealership, garage, traffic, physics, audio) reads from it.

const PERF_PARTS: Array = ["engine", "turbo", "transmission", "brakes", "tyres", "suspension", "exhaust", "weight"]
const PART_LABEL: Dictionary = {
	"engine": "Engine", "turbo": "Turbocharger", "transmission": "Transmission", "brakes": "Brakes",
	"tyres": "Tyres", "suspension": "Suspension", "exhaust": "Exhaust", "weight": "Weight Reduction",
}
const PART_DESC: Dictionary = {
	"engine": "+ acceleration, + top speed", "turbo": "+ acceleration (boost whistle)",
	"transmission": "+ acceleration, + top speed", "brakes": "+ braking power",
	"tyres": "+ grip, + cornering", "suspension": "+ stability, + handling",
	"exhaust": "+ power, louder note", "weight": "- mass, + agility",
}
const PART_COST_FACTOR: Dictionary = {
	"engine": 0.09, "turbo": 0.08, "transmission": 0.06, "brakes": 0.04,
	"tyres": 0.04, "suspension": 0.05, "exhaust": 0.03, "weight": 0.05,
}
const MAX_UPGRADE_LEVEL: int = 3

var PAINTS: Array = [
	{"n": "Crimson", "c": Color(0.78, 0.05, 0.08)}, {"n": "Midnight", "c": Color(0.03, 0.03, 0.05)},
	{"n": "Pearl", "c": Color(0.9, 0.9, 0.92)}, {"n": "Cobalt", "c": Color(0.05, 0.18, 0.75)},
	{"n": "Racing Green", "c": Color(0.02, 0.28, 0.14)}, {"n": "Sunset", "c": Color(0.95, 0.4, 0.05)},
	{"n": "Lemon", "c": Color(0.95, 0.82, 0.05)}, {"n": "Violet", "c": Color(0.35, 0.08, 0.6)},
	{"n": "Gunmetal", "c": Color(0.22, 0.24, 0.27)}, {"n": "Silver", "c": Color(0.62, 0.64, 0.68)},
	{"n": "Teal", "c": Color(0.0, 0.5, 0.5)}, {"n": "Hot Pink", "c": Color(0.95, 0.1, 0.5)},
	{"n": "Sand", "c": Color(0.76, 0.65, 0.45)}, {"n": "Ice", "c": Color(0.5, 0.78, 0.95)},
	{"n": "Burgundy", "c": Color(0.32, 0.03, 0.08)}, {"n": "Olive", "c": Color(0.28, 0.32, 0.12)},
]
var UNDERGLOWS: Array = [
	{"n": "None", "c": Color(0, 0, 0)}, {"n": "Red", "c": Color(1.0, 0.1, 0.1)}, {"n": "Blue", "c": Color(0.1, 0.3, 1.0)},
	{"n": "Green", "c": Color(0.1, 1.0, 0.3)}, {"n": "Purple", "c": Color(0.7, 0.1, 1.0)},
	{"n": "Cyan", "c": Color(0.1, 0.9, 1.0)}, {"n": "White", "c": Color(1, 1, 1)},
]
var HEADLIGHTS: Array = [
	{"n": "Halogen", "c": Color(1.0, 0.9, 0.7)}, {"n": "Xenon", "c": Color(0.9, 0.95, 1.0)},
	{"n": "Blue LED", "c": Color(0.6, 0.75, 1.0)},
]
const RIM_NAMES: Array = ["Stock", "Five-Spoke", "Mesh", "Turbine"]
const SPOILER_NAMES: Array = ["None", "Lip", "Wing", "GT Wing"]
const BUMPER_NAMES: Array = ["Stock", "Sport", "Aggressive"]
const BODYKIT_NAMES: Array = ["None", "Side Skirts", "Widebody"]
const TINT_NAMES: Array = ["Light", "Medium", "Dark", "Limo"]
const CUSTOM_COST: Dictionary = {
	"paint": 300, "paint2": 250, "wheel_color": 150, "tint": 200, "rims": 600, "spoiler": 750,
	"bumper": 500, "bodykit": 900, "headlights": 350, "underglow": 400, "plate": 100,
}

## Characters used by the story missions.
var CHARACTERS: Dictionary = {
	"rico": {"name": "Rico", "role": "Mechanic", "color": Color(1.0, 0.6, 0.1)},
	"vera": {"name": "Vera Cole", "role": "Race Organiser", "color": Color(0.3, 0.8, 1.0)},
	"marcus": {"name": "Marcus Hale", "role": "Dealership Owner", "color": Color(0.5, 1.0, 0.5)},
	"kane": {"name": "Kane Voss", "role": "Rival Driver", "color": Color(1.0, 0.2, 0.2)},
	"ghost": {"name": "Ghost", "role": "Mysterious Contact", "color": Color(0.8, 0.5, 1.0)},
}

## id, name, category, price, mass(kg), accel (m/s2 at standstill), top (m/s), brake (m/s2), steer (rad),
## grip (friction_slip), stiff, drive, gears, final, engine sound type, dims...
var VEHICLES: Array = [
	{"id": "pico_h1", "name": "Pico H1", "cat": "Hatchback", "price": 6500, "mass": 1050.0, "accel": 4.2, "top": 44.0,
	 "brake": 9.0, "steer": 0.62, "grip": 3.0, "stiff": 38.0, "drive": "FWD", "gears": [3.6, 2.2, 1.5, 1.1, 0.85], "final": 3.9,
	 "engine": "i4", "redline": 6800.0, "turbo": false, "roll": 0.2, "wr": 0.30, "ww": 0.19, "L": 3.75, "W": 1.68, "belly": 0.15,
	 "hood": 0.86, "belt": 0.98, "trunk": 1.12, "roof": 1.46, "cab0": 0.28, "cab1": 0.96, "roof0": 0.40, "roof1": 0.90,
	 "wb": 2.4, "track": 1.46, "paint": 2, "offroad": false, "ai": 8.0},
	{"id": "strada_s2", "name": "Strada S2", "cat": "Sedan", "price": 18500, "mass": 1450.0, "accel": 4.8, "top": 55.0,
	 "brake": 9.5, "steer": 0.56, "grip": 3.2, "stiff": 42.0, "drive": "RWD", "gears": [3.4, 2.1, 1.45, 1.05, 0.8, 0.65], "final": 3.5,
	 "engine": "v6", "redline": 6600.0, "turbo": false, "roll": 0.18, "wr": 0.33, "ww": 0.21, "L": 4.75, "W": 1.82, "belly": 0.14,
	 "hood": 0.9, "belt": 1.0, "trunk": 1.0, "roof": 1.42, "cab0": 0.33, "cab1": 0.80, "roof0": 0.43, "roof1": 0.70,
	 "wb": 2.8, "track": 1.55, "paint": 8, "offroad": false, "ai": 10.0},
	{"id": "bmw_m6", "name": "BMW M6 1988", "cat": "Sports Car", "price": 38000, "mass": 1430.0, "accel": 5.8, "top": 66.0,
	 "brake": 10.5, "steer": 0.58, "grip": 3.6, "stiff": 46.0, "drive": "RWD", "gears": [3.5, 2.1, 1.4, 1.05, 0.82], "final": 3.6,
	 "engine": "i6", "redline": 6800.0, "turbo": false, "roll": 0.15, "wr": 0.31, "ww": 0.30, "L": 4.30, "W": 1.88, "belly": 0.12,
	 "hood": 0.74, "belt": 0.82, "trunk": 0.80, "roof": 1.40, "cab0": 0.30, "cab1": 0.86, "roof0": 0.48, "roof1": 0.70,
	 "wb": 2.625, "track": 1.56, "paint": 0, "offroad": false, "ai": 11.0},
	{"id": "vela_gt", "name": "Vela GT", "cat": "Sports Car", "price": 42000, "mass": 1380.0, "accel": 7.2, "top": 72.0,
	 "brake": 11.5, "steer": 0.60, "grip": 3.9, "stiff": 52.0, "drive": "RWD", "gears": [3.2, 2.1, 1.55, 1.2, 0.95, 0.75], "final": 3.7,
	 "engine": "v6", "redline": 7600.0, "turbo": true, "roll": 0.12, "wr": 0.34, "ww": 0.25, "L": 4.45, "W": 1.9, "belly": 0.11,
	 "hood": 0.78, "belt": 0.9, "trunk": 0.98, "roof": 1.25, "cab0": 0.38, "cab1": 0.76, "roof0": 0.46, "roof1": 0.68,
	 "wb": 2.65, "track": 1.6, "paint": 2, "offroad": false, "ai": 14.0},
	{"id": "kestrel_r", "name": "Kestrel R", "cat": "Sports Car", "price": 76000, "mass": 1500.0, "accel": 8.0, "top": 80.0,
	 "brake": 12.0, "steer": 0.58, "grip": 4.2, "stiff": 54.0, "drive": "AWD", "gears": [3.1, 2.0, 1.5, 1.18, 0.95, 0.78], "final": 3.6,
	 "engine": "rotary", "redline": 9000.0, "turbo": true, "roll": 0.12, "wr": 0.34, "ww": 0.26, "L": 4.55, "W": 1.92, "belly": 0.11,
	 "hood": 0.80, "belt": 0.92, "trunk": 1.0, "roof": 1.28, "cab0": 0.36, "cab1": 0.78, "roof0": 0.45, "roof1": 0.70,
	 "wb": 2.7, "track": 1.62, "paint": 0, "offroad": false, "ai": 18.0},
	{"id": "brawler_69", "name": "Brawler 69", "cat": "Muscle Car", "price": 55000, "mass": 1750.0, "accel": 8.6, "top": 74.0,
	 "brake": 9.0, "steer": 0.52, "grip": 3.0, "stiff": 46.0, "drive": "RWD", "gears": [2.9, 1.9, 1.4, 1.0, 0.75], "final": 3.4,
	 "engine": "v8", "redline": 6200.0, "turbo": false, "roll": 0.2, "wr": 0.35, "ww": 0.27, "L": 4.95, "W": 1.95, "belly": 0.14,
	 "hood": 0.95, "belt": 1.02, "trunk": 1.05, "roof": 1.35, "cab0": 0.42, "cab1": 0.80, "roof0": 0.50, "roof1": 0.72,
	 "wb": 2.85, "track": 1.62, "paint": 3, "offroad": false, "ai": 12.0},
	{"id": "titan_x", "name": "Titan X", "cat": "SUV", "price": 48000, "mass": 2250.0, "accel": 5.2, "top": 60.0,
	 "brake": 8.5, "steer": 0.50, "grip": 3.5, "stiff": 56.0, "drive": "AWD", "gears": [3.5, 2.2, 1.5, 1.05, 0.8, 0.65], "final": 3.6,
	 "engine": "v8", "redline": 6000.0, "turbo": false, "roll": 0.26, "wr": 0.40, "ww": 0.26, "L": 5.0, "W": 2.0, "belly": 0.26,
	 "hood": 1.12, "belt": 1.28, "trunk": 1.4, "roof": 1.85, "cab0": 0.30, "cab1": 0.98, "roof0": 0.36, "roof1": 0.94,
	 "wb": 3.0, "track": 1.7, "paint": 8, "offroad": false, "ai": 9.0},
	{"id": "dune_runner", "name": "Dune Runner", "cat": "Off-Road", "price": 38000, "mass": 1700.0, "accel": 5.6, "top": 52.0,
	 "brake": 8.5, "steer": 0.58, "grip": 3.8, "stiff": 38.0, "drive": "AWD", "gears": [3.8, 2.4, 1.6, 1.15, 0.85], "final": 4.0,
	 "engine": "diesel", "redline": 5200.0, "turbo": true, "roll": 0.22, "wr": 0.44, "ww": 0.30, "L": 4.2, "W": 1.95, "belly": 0.34,
	 "hood": 1.12, "belt": 1.24, "trunk": 1.35, "roof": 1.8, "cab0": 0.34, "cab1": 0.96, "roof0": 0.40, "roof1": 0.94,
	 "wb": 2.6, "track": 1.72, "paint": 11, "offroad": true, "susp": 0.45, "ai": 8.0},
	{"id": "hauler_r", "name": "Hauler R", "cat": "Pickup Truck", "price": 34000, "mass": 2050.0, "accel": 4.6, "top": 52.0,
	 "brake": 8.5, "steer": 0.50, "grip": 3.3, "stiff": 52.0, "drive": "RWD", "gears": [3.6, 2.2, 1.5, 1.05, 0.8], "final": 3.7,
	 "engine": "diesel", "redline": 5000.0, "turbo": true, "roll": 0.24, "wr": 0.40, "ww": 0.27, "L": 5.4, "W": 2.0, "belly": 0.26,
	 "hood": 1.08, "belt": 1.22, "trunk": 1.18, "roof": 1.78, "cab0": 0.28, "cab1": 0.60, "roof0": 0.33, "roof1": 0.56,
	 "wb": 3.3, "track": 1.7, "paint": 1, "offroad": true, "susp": 0.36, "ai": 9.0},
	{"id": "apex_z", "name": "Apex Z", "cat": "Supercar", "price": 140000, "mass": 1450.0, "accel": 10.0, "top": 92.0,
	 "brake": 14.0, "steer": 0.55, "grip": 4.8, "stiff": 60.0, "drive": "AWD", "gears": [3.0, 2.0, 1.5, 1.2, 0.98, 0.8, 0.66], "final": 3.5,
	 "engine": "v8", "redline": 8500.0, "turbo": true, "roll": 0.1, "wr": 0.35, "ww": 0.30, "L": 4.6, "W": 2.0, "belly": 0.09,
	 "hood": 0.7, "belt": 0.84, "trunk": 0.95, "roof": 1.12, "cab0": 0.40, "cab1": 0.74, "roof0": 0.47, "roof1": 0.67,
	 "wb": 2.7, "track": 1.7, "paint": 0, "offroad": false, "ai": 22.0},
	{"id": "phantom_one", "name": "Phantom One", "cat": "Hypercar", "price": 420000, "mass": 1350.0, "accel": 12.5, "top": 108.0,
	 "brake": 16.0, "steer": 0.5, "grip": 5.4, "stiff": 66.0, "drive": "AWD", "gears": [2.9, 2.0, 1.55, 1.25, 1.02, 0.85, 0.7], "final": 3.4,
	 "engine": "electric", "redline": 12000.0, "turbo": false, "roll": 0.08, "wr": 0.35, "ww": 0.31, "L": 4.7, "W": 2.04, "belly": 0.08,
	 "hood": 0.66, "belt": 0.8, "trunk": 0.9, "roof": 1.08, "cab0": 0.42, "cab1": 0.72, "roof0": 0.48, "roof1": 0.66,
	 "wb": 2.75, "track": 1.74, "paint": 9, "offroad": false, "ai": 26.0},
	{"id": "police_cruiser", "name": "Interceptor", "cat": "Sedan", "price": 0, "mass": 1700.0, "accel": 7.4, "top": 62.0, "hidden": true,
	 "brake": 11.0, "steer": 0.56, "grip": 3.6, "stiff": 46.0, "drive": "RWD", "gears": [3.2, 2.0, 1.45, 1.1, 0.88, 0.7], "final": 3.5,
	 "engine": "v8", "redline": 6800.0, "turbo": false, "roll": 0.18, "wr": 0.34, "ww": 0.22, "L": 4.9, "W": 1.86, "belly": 0.15,
	 "hood": 0.92, "belt": 1.0, "trunk": 1.0, "roof": 1.44, "cab0": 0.33, "cab1": 0.80, "roof0": 0.43, "roof1": 0.70,
	 "wb": 2.85, "track": 1.58, "paint": 2, "offroad": false, "ai": 12.0},
]

func _init() -> void:
	# cars split from the traffic pack (see PackVehicles / tools/gen_pack_vehicles.py)
	for e in PackVehicles.LIST:
		VEHICLES.append((e["spec"] as Dictionary).duplicate(true))
	# the collection cars (assets/vehicles/fleet, see FleetVehicles)
	for e in FleetVehicles.LIST:
		VEHICLES.append((e["spec"] as Dictionary).duplicate(true))

## Fuel tank size in litres (spec "tank", else by category).
func tank_litres(id: String) -> float:
	var v: Dictionary = vehicle(id)
	if v.has("tank"):
		return float(v["tank"])
	match String(v["cat"]):
		"Hatchback": return 42.0
		"Sedan": return 55.0
		"Sports Car", "Muscle Car": return 62.0
		"SUV", "Off-Road": return 85.0
		"Pickup Truck": return 90.0
		"Supercar", "Hypercar": return 70.0
	return 50.0

func vehicle(id: String) -> Dictionary:
	for v in VEHICLES:
		if v["id"] == id:
			return v
	return VEHICLES[0]

## The player-facing collection (dealership / garage / saves): the BMW M6 starter + the 7 fleet cars.
## Every other entry of VEHICLES (the old procedural cars, the traffic pack, the police cruiser) is kept only for
## traffic / police / AI use and is never offered to the player.
const COLLECTION := ["bmw_m6", "civic", "camaro", "c63", "countach", "m3_gtr", "sesto", "nsx", "gclass", "mustang", "amg_one", "airport_car"]
## The four cars every player owns from the very first launch (free, no mission / unlock): BMW M6 + Civic Type R + Camaro SS + AMG C 63 DTM.
const STARTER_VEHICLES := ["bmw_m6", "civic", "camaro", "c63"]
## Vehicles that cost nothing and are NOT sold in the dealership: the three extra starters and the airport shuttle cart
## (picked up in the world). The BMW M6 is also free but stays listed so the dealership / old saves behave as before.
const FREE_VEHICLES := ["civic", "camaro", "c63", "airport_car"]
## Track go-karts: drivable, free, never owned / listed in the garage - borrowed at the race circuits (World.take_kart).
const KART_ID := "go_kart"

func vehicle_ids() -> Array:
	return COLLECTION.duplicate()

## What the dealership offers (the collection minus the free world pick-ups)
func shop_ids() -> Array:
	var out: Array = []
	for id in COLLECTION:
		if not FREE_VEHICLES.has(id):
			out.append(id)
	return out

func is_free_vehicle(id: String) -> bool:
	return FREE_VEHICLES.has(id) or id == "bmw_m6"

func is_starter(id: String) -> bool:
	return STARTER_VEHICLES.has(id)

func in_collection(id: String) -> bool:
	return COLLECTION.has(id)

func upgrade_cost(vid: String, part: String, next_level: int) -> int:
	var v: Dictionary = vehicle(vid)
	var base: float = maxf(500.0, float(v["price"]) * float(PART_COST_FACTOR[part]))
	return int(round(base * float(next_level) / 10.0)) * 10

func default_custom(vid: String) -> Dictionary:
	var v: Dictionary = vehicle(vid)
	return {"paint": int(v.get("paint", 0)), "paint2": 1, "wheel_color": 8, "tint": 1, "rims": 0, "spoiler": 0, "bumper": 0,
			"bodykit": 0, "headlights": 0, "underglow": 0, "plate": "DB-%03d" % (hash(vid) % 900 + 100)}

func default_upgrades() -> Dictionary:
	var d: Dictionary = {}
	for p in PERF_PARTS:
		d[p] = 0
	return d

## Applies upgrades to base stats and returns the effective stats used by the physics.
func final_stats(vid: String, upg: Dictionary) -> Dictionary:
	var v: Dictionary = vehicle(vid)
	var u: Dictionary = default_upgrades()
	u.merge(upg, true)
	var s: Dictionary = {}
	var accel: float = float(v["accel"])
	var top: float = float(v["top"])
	accel *= 1.0 + 0.07 * u["engine"] + 0.06 * u["turbo"] + 0.04 * u["transmission"] + 0.02 * u["exhaust"]
	top *= 1.0 + 0.035 * u["engine"] + 0.02 * u["turbo"] + 0.03 * u["transmission"] + 0.01 * u["exhaust"]
	s["accel"] = accel
	s["top"] = top
	s["brake"] = float(v["brake"]) * (1.0 + 0.14 * u["brakes"])
	s["grip"] = float(v["grip"]) * (1.0 + 0.09 * u["tyres"])
	s["mass"] = float(v["mass"]) * (1.0 - 0.045 * u["weight"])
	s["stiff"] = float(v["stiff"]) * (1.0 + 0.08 * u["suspension"])
	s["roll"] = float(v["roll"]) * (1.0 - 0.15 * u["suspension"])
	s["steer"] = float(v["steer"]) * (1.0 + 0.02 * u["tyres"] + 0.02 * u["suspension"])
	s["turbo_level"] = u["turbo"] + (1 if v["turbo"] else 0)
	s["exhaust_level"] = u["exhaust"]
	return s

## 0..100 performance rating for bars in dealership/garage.
func rating(vid: String, upg: Dictionary) -> Dictionary:
	var s: Dictionary = final_stats(vid, upg)
	return {
		"speed": clampf(float(s["top"]) / 115.0 * 100.0, 5, 100),
		"accel": clampf(float(s["accel"]) / 13.0 * 100.0, 5, 100),
		"braking": clampf(float(s["brake"]) / 17.0 * 100.0, 5, 100),
		"handling": clampf((float(s["grip"]) / 5.6 * 0.6 + float(s["steer"]) / 0.7 * 0.4) * 100.0, 5, 100),
	}

func sell_value(vid: String, upg: Dictionary) -> int:
	var v: Dictionary = vehicle(vid)
	var total: float = float(v["price"]) * 0.55
	for p in PERF_PARTS:
		var lvl: int = int(upg.get(p, 0))
		for l in range(1, lvl + 1):
			total += float(upgrade_cost(vid, p, l)) * 0.4
	return int(total / 10.0) * 10
