class_name WorldExpansion
extends RefCounted
## The east/south-east world expansion (world grows from 3.2 km to 4.7 km):
##   D  International airport  - runway + apron + terminal complex from airport_pack_total, forecourt, parking
##   B  Business district     - 12 shops/restaurants/cinema/mall (low_poly_business_buildings_pack) on a street grid
##   C  Accommodation district - 10 residential/hotel buildings (low_poly_accommodations_buildings) on a ring road
## All three are reached from the old map by the "Airport Expressway", an extension of Quarter Mile Road.
## WorldGen calls add_terrain() / add_roads() while it lays the map out and build() once the city is built.

const H := 11.0                         # common ground height of the three districts
# airport: pack frame origin in the world.  Terminal front faces west (-X), runway runs north-south on the east side.
const AX := 2010.0
const AZ := 480.0
const RUNWAY_X := 140.0                 # runway centre, pack frame
const RUNWAY_Z0 := 17.0                 # centre of the middle runway tile, pack frame
const TILE := 269.29
const DRIVE_X := 1860.0                 # Terminal Drive (north-south avenue in front of the terminal)
const PARK_C := Vector3(1790.0, 0.0, 612.0)
const PARK_S := Vector2(92.0, 150.0)
const B_C := Vector2(1700.0, 1000.0)
const C_C := Vector2(2010.0, 1070.0)

static func airport_world(p: Vector3) -> Vector3:
	return Vector3(AX + p.x, H, AZ + p.z)

static func add_terrain(g: WorldGen) -> void:
	# flat rectangle covering runway + apron + forecourt (x 1790..2240, z 40..960) with a 70 m blend
	g.rect_pads.append({"r": Rect2(1795.0, 45.0, 440.0, 910.0), "h": H, "b": 70.0})
	g._pad(B_C.x, B_C.y, 150.0, H, 60.0)
	g._pad(C_C.x, C_C.y, 120.0, H, 60.0)
	# commerce boulevard corridor (so the road is not cut through dunes)
	g._pad(1700.0, 640.0, 40.0, H, 60.0)
	g._pad(1700.0, 780.0, 40.0, H, 60.0)

static func add_roads(g: WorldGen) -> void:
	g.add_road("highway", [Vector2(1500, 520), Vector2(1600, 505), Vector2(1700, 480), Vector2(1780, 450), Vector2(1860, 430)], true, false, "Airport Expressway")
	g.add_road("avenue", [Vector2(DRIVE_X, 340), Vector2(DRIVE_X, 430), Vector2(DRIVE_X, 520), Vector2(DRIVE_X, 610), Vector2(DRIVE_X, 700)], false, false, "Terminal Drive")
	g.add_road("street", [Vector2(DRIVE_X, 612), Vector2(1820, 612), Vector2(1790, 612)], false, false, "Parking Access")
	g.add_road("avenue", [Vector2(1700, 480), Vector2(1700, 620), Vector2(1700, 760), Vector2(1700, 900)], true, false, "Commerce Boulevard")
	# business district street grid (3 x 3 streets, 2 x 2 blocks of 100 m)
	for z in [900.0, 1000.0, 1100.0]:
		g.add_road("street", [Vector2(1600, z), Vector2(1700, z), Vector2(1800, z)], false, false, "Market Street")
	for x in [1600.0, 1800.0]:
		g.add_road("street", [Vector2(x, 900), Vector2(x, 1000), Vector2(x, 1100)], false, false, "Trade Street")
	g.add_road("street", [Vector2(1700, 1000), Vector2(1700, 1100)], false, false, "Trade Street")
	# resort road + ring road of the accommodation district
	g.add_road("suburb", [Vector2(1800, 1000), Vector2(1865, 1000), Vector2(1930, 1000)], false, false, "Resort Road")
	g.add_road("suburb", [Vector2(1930, 1000), Vector2(1930, 1140), Vector2(2090, 1140), Vector2(2090, 1000), Vector2(1930, 1000)], false, false, "Resort Loop")

# (id, dx, dz, yaw) relative to the block centre; fronts face +Z at yaw 0
const BIZ_PLAN := [
	[Vector2(1650, 950), [["biz_mall", 0, 25, 0.0], ["biz_pizza", -20, -27, PI], ["biz_shop", 22, -27, PI]]],
	[Vector2(1750, 950), [["biz_cinema", 0, 27, 0.0], ["biz_burger", -22, -26, PI], ["biz_cafe", 24, -24, PI]]],
	[Vector2(1650, 1050), [["biz_restaurant", -22, -27, PI], ["biz_cafe", 22, -26, PI], ["biz_burger", 0, 26, 0.0]]],
	[Vector2(1750, 1050), [["biz_shop", -22, -27, PI], ["biz_pizza", 20, -27, PI], ["biz_restaurant", 0, 27, 0.0]]],
]
# accommodation: [id, x, z, yaw]
const ACC_PLAN := [
	["acc_1", 1962, 1032, PI], ["acc_9", 2010, 1032, PI], ["acc_10", 2060, 1032, PI],
	["acc_4", 1972, 1070, 0.0], ["acc_5", 1998, 1070, 0.0], ["acc_6", 2028, 1070, 0.0], ["acc_7", 2054, 1070, 0.0],
	["acc_2", 1966, 1108, 0.0], ["acc_8", 2020, 1108, 0.0], ["acc_3", 2066, 1108, 0.0],
]

static func build(g: WorldGen) -> void:
	for blk in BIZ_PLAN:
		var c: Vector2 = blk[0]
		for b in blk[1]:
			var p := Vector3(c.x + float(b[1]), 0, c.y + float(b[2]))
			p.y = g.ground_h(p.x, p.z)
			g._add_pack(p, String(b[0]), float(b[3]), Vector3.ZERO)
	for b in ACC_PLAN:
		var p := Vector3(float(b[1]), 0, float(b[2]))
		p.y = g.ground_h(p.x, p.z)
		g._add_pack(p, String(b[0]), float(b[3]), Vector3.ZERO)
	# nothing random (rocks, cacti, houses) may be generated inside the districts
	g.keepouts.append(Rect2(1785.0, 30.0, 460.0, 930.0))     # airport
	g.keepouts.append(Rect2(1560.0, 860.0, 270.0, 280.0))    # business district
	g.keepouts.append(Rect2(1890.0, 960.0, 240.0, 220.0))    # accommodation district
	g.keepouts.append(Rect2(1650.0, 440.0, 100.0, 480.0))    # commerce boulevard corridor
	var term: Vector3 = airport_world(Vector3(-128.0, 0.0, 40.0))
	g.landmarks["airport"] = Vector3(AX - 150.0, H, AZ + 30.0)
	g.landmarks["airport_car"] = Vector3(term.x, H, term.z)
	g.landmarks["business_district"] = Vector3(B_C.x, H, B_C.y)
	g.landmarks["resort_district"] = Vector3(C_C.x, H, C_C.y)
	g.structures.append({"type": "airport", "pos": Vector3(AX, H, AZ), "size": Vector3(450.0, 30.0, 900.0)})

## which expansion district a world position belongs to ("" = none); used by the NPC managers
static func zone_at(x: float, z: float) -> String:
	if x > 1785.0 and x < 2245.0 and z > 30.0 and z < 960.0:
		return "airport"
	if x > 1560.0 and x < 1830.0 and z > 860.0 and z < 1140.0:
		return "business"
	if x > 1890.0 and x < 2130.0 and z > 960.0 and z < 1180.0:
		return "resort"
	return ""

## free walking areas for wandering pedestrians (no buildings / vehicles inside): [rect, max peds]
const WALK_ZONES := [
	[Rect2(1874.0, 350.0, 22.0, 340.0), 4],      # terminal plaza (between Terminal Drive and the terminal front)
	[Rect2(1764.5, 548.0, 7.0, 128.0), 1],       # parking lot aisle west
	[Rect2(1808.5, 548.0, 7.0, 128.0), 1],       # parking lot aisle east
]
