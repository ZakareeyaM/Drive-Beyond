class_name WorldGen
extends RefCounted
## Pure data: terrain height function, road graph, city layout, landmarks.
## Everything here is deterministic and read-only after build(), so chunk
## builders can safely run on worker threads.

const HALF := 2368.0                # 37 chunks of 128 m (was 25 chunks / 3.2 km: the east band holds the airport + 2 districts)
const CELL := 4.0
const GRID_N := 1184
const CHUNK := 128.0
const CHUNKS := 37
const VERTS := 33
const SEA := 0.0
const CITY_H := 6.0
const GRID_STEP := 125.0
const GRID_START := -500.0

const KINDS := {
	"street":     {"w": 11.0, "lanes": 1, "limit": 14.0, "side": true,  "tw": 1.0, "fall": 8.0},
	"avenue":     {"w": 17.0, "lanes": 2, "limit": 19.0, "side": true,  "tw": 1.6, "fall": 8.0},
	"highway":    {"w": 19.0, "lanes": 2, "limit": 33.0, "side": false, "tw": 2.0, "fall": 12.0},
	"country":    {"w": 9.0,  "lanes": 1, "limit": 22.0, "side": false, "tw": 0.6, "fall": 10.0},
	"mountain":   {"w": 8.5,  "lanes": 1, "limit": 16.0, "side": false, "tw": 0.4, "fall": 14.0},
	"coastal":    {"w": 10.0, "lanes": 1, "limit": 25.0, "side": false, "tw": 1.0, "fall": 10.0},
	"dirt":       {"w": 6.5,  "lanes": 1, "limit": 13.0, "side": false, "tw": 0.15, "fall": 7.0},
	"track":      {"w": 15.0, "lanes": 2, "limit": 60.0, "side": false, "tw": 0.0, "fall": 10.0},
	"suburb":     {"w": 9.5,  "lanes": 1, "limit": 12.0, "side": true,  "tw": 0.6, "fall": 8.0},
	"industrial": {"w": 12.0, "lanes": 1, "limit": 15.0, "side": false, "tw": 0.6, "fall": 8.0},
}

var seed_value: int = 20260611
var n_hill := FastNoiseLite.new()
var n_ridge := FastNoiseLite.new()
var n_dune := FastNoiseLite.new()
var n_forest := FastNoiseLite.new()
var n_detail := FastNoiseLite.new()

var nodes: Array = []              # Vector3 (x, h, z)
var node_adj: Array = []           # Array of Array[int] edge ids
var edges: Array = []              # Dictionary
var infl := PackedFloat32Array()
var rh := PackedFloat32Array()
var pads: Array = []
var rect_pads: Array = []          # {r: Rect2, h, b}: flat rectangles (airport) blended into the terrain over b metres
var landmarks: Dictionary = {}
var keepouts: Array = []           # Rect2 (x,z) areas where no trees/houses may be generated (petrol station, ...)
var city_light_nodes: Array = []   # intersections that have traffic lights (node ids)
var buildings: Dictionary = {}     # chunk key -> Array of building dicts
var structures: Array = []         # special landmark structures (dealership, garage, etc.)
var seg_index: Dictionary = {}     # chunk key -> PackedInt32Array [edge, idx, edge, idx ...]
var snap_grid: Dictionary = {}     # 32 m cell -> PackedInt32Array [edge, idx ...]
var bridges: Array = []            # {edge, i0, i1}
var tunnels: Array = []            # {edge, i0, i1}
var speed_cameras: Array = []      # Vector3 + dir
var inlet_a := Vector2(-1100.0, 440.0)
var inlet_b := Vector2(-330.0, 440.0)
var ready_flag: bool = false

func _init() -> void:
	n_hill.seed = seed_value
	n_hill.frequency = 0.0022
	n_hill.fractal_octaves = 3
	n_ridge.seed = seed_value + 1
	n_ridge.frequency = 0.0036
	n_ridge.fractal_octaves = 4
	n_dune.seed = seed_value + 2
	n_dune.frequency = 0.0075
	n_dune.fractal_octaves = 2
	n_forest.seed = seed_value + 3
	n_forest.frequency = 0.009
	n_detail.seed = seed_value + 4
	n_detail.frequency = 0.06

# ----------------------------------------------------------------- terrain
func key(cx: int, cz: int) -> int:
	return cx * 1000 + cz

func chunk_of(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int(floor((x + HALF) / CHUNK)), 0, CHUNKS - 1), clampi(int(floor((z + HALF) / CHUNK)), 0, CHUNKS - 1))

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var t: float = clampf((p - a).dot(ab) / maxf(0.001, ab.length_squared()), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func nat_h(x: float, z: float) -> float:
	var r: float = sqrt(x * x + z * z)
	var h: float = CITY_H + n_hill.get_noise_2d(x, z) * 5.0
	h = lerpf(h, CITY_H, 1.0 - smoothstep(520.0, 760.0, r))
	var m: float = smoothstep(-640.0, -1150.0, z)
	var d: float = smoothstep(760.0, 1000.0, x) * smoothstep(-760.0, -420.0, z)
	if m > 0.0:
		var rd: float = 1.0 - absf(n_ridge.get_noise_2d(x, z))
		h += m * (32.0 + rd * rd * 150.0 + n_hill.get_noise_2d(x * 2.0 + 300.0, z * 2.0) * 22.0)
	if d > 0.0:
		var dune: float = n_dune.get_noise_2d(x, z)
		h = lerpf(h, 10.0 + dune * 9.0 + n_hill.get_noise_2d(x, z) * 6.0, d)
	# south: gentle rolling hills (forest + countryside)
	var sh: float = smoothstep(650.0, 950.0, z) * (1.0 - d)
	if sh > 0.0:
		h += sh * (n_hill.get_noise_2d(x * 1.7, z * 1.7 + 55.0) * 14.0 + 6.0)
	# coastal cliffs in the north-west, beaches elsewhere
	var cliff: float = smoothstep(-90.0, -230.0, z) * smoothstep(-640.0, -500.0, z)
	h += cliff * 26.0 * smoothstep(-600.0, -780.0, x)
	var s0: float = lerpf(-840.0, -885.0, cliff)
	var s1: float = lerpf(-1000.0, -915.0, cliff)
	h = lerpf(h, -22.0, smoothstep(s0, s1, x))
	# harbour inlet
	var p := Vector2(x, z)
	var di: float = _seg_dist(p, inlet_a, inlet_b)
	var hw: float = lerpf(44.0, 62.0, smoothstep(-330.0, -700.0, x))
	if di < hw + 30.0:
		h = lerpf(-9.0, h, smoothstep(hw * 0.55, hw + 8.0, di))
		h = minf(h, lerpf(-9.0, 40.0, smoothstep(hw * 0.55, hw + 8.0, di)))
	# flat pads for landmarks
	for pd in pads:
		var dx: float = x - float(pd["x"])
		var dz: float = z - float(pd["z"])
		var dd: float = sqrt(dx * dx + dz * dz)
		var rad: float = float(pd["r"])
		if dd < rad + float(pd["b"]):
			var w: float = 1.0 - smoothstep(rad, rad + float(pd["b"]), dd)
			h = lerpf(h, float(pd["h"]), w)
	for rp in rect_pads:
		var rr: Rect2 = rp["r"]
		var ddx: float = maxf(maxf(rr.position.x - x, x - rr.end.x), 0.0)
		var ddz: float = maxf(maxf(rr.position.y - z, z - rr.end.y), 0.0)
		var rd: float = sqrt(ddx * ddx + ddz * ddz)
		if rd < float(rp["b"]):
			h = lerpf(h, float(rp["h"]), 1.0 - smoothstep(0.0, float(rp["b"]), rd))
	return h

func grid_index(ix: int, iz: int) -> int:
	return iz * (GRID_N + 1) + ix

func ground_h_ix(ix: int, iz: int) -> float:
	var x: float = -HALF + float(ix) * CELL
	var z: float = -HALF + float(iz) * CELL
	var h: float = nat_h(x, z)
	if ix >= 0 and iz >= 0 and ix <= GRID_N and iz <= GRID_N:
		var gi: int = grid_index(ix, iz)
		var w: float = infl[gi]
		if w > 0.0:
			h = lerpf(h, rh[gi] - 0.04, w)
	return h

func ground_h(x: float, z: float) -> float:
	# bilinear of the exact vertex heights the terrain mesh uses
	var fx: float = (x + HALF) / CELL
	var fz: float = (z + HALF) / CELL
	var ix: int = int(floor(fx))
	var iz: int = int(floor(fz))
	var tx: float = fx - float(ix)
	var tz: float = fz - float(iz)
	var h00: float = ground_h_ix(ix, iz)
	var h10: float = ground_h_ix(ix + 1, iz)
	var h01: float = ground_h_ix(ix, iz + 1)
	var h11: float = ground_h_ix(ix + 1, iz + 1)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

func road_weight(x: float, z: float) -> float:
	var ix: int = int(round((x + HALF) / CELL))
	var iz: int = int(round((z + HALF) / CELL))
	if ix < 0 or iz < 0 or ix > GRID_N or iz > GRID_N:
		return 0.0
	return infl[grid_index(ix, iz)]

func on_road(x: float, z: float) -> bool:
	return road_weight(x, z) > 0.6

func region_at(x: float, z: float) -> String:
	var r: float = sqrt(x * x + z * z)
	if x < -880.0: return "ocean"
	if x < -700.0 and z > -250.0 and z < 400.0: return "coast"
	if r < 560.0: return "city"
	if z < -640.0: return "mountain"
	if x > 760.0 and z > -760.0: return "desert"
	if x < -600.0 and z > 560.0: return "industrial" if z < 880.0 else "countryside"
	if z > 650.0 and x > 150.0: return "forest"
	if z > 650.0: return "countryside"
	return "suburb"

func tree_density(x: float, z: float, h: float) -> float:
	var reg: String = region_at(x, z)
	if h < 1.5 or reg == "city" or reg == "desert" or reg == "ocean":
		return 0.0
	var f: float = n_forest.get_noise_2d(x, z) * 0.5 + 0.5
	match reg:
		"forest": return clampf((f - 0.25) * 2.2, 0.0, 0.95)
		"mountain": return clampf((f - 0.35) * 1.6, 0.0, 0.7) * (1.0 - smoothstep(60.0, 130.0, h))
		"countryside": return clampf((f - 0.55) * 1.5, 0.0, 0.5)
		"suburb": return clampf((f - 0.5) * 1.4, 0.0, 0.4)
		"coast": return 0.05
		_: return clampf((f - 0.6) * 1.2, 0.0, 0.25)

func terrain_color(x: float, z: float, h: float, ny: float) -> Color:
	var reg: String = region_at(x, z)
	var n: float = n_detail.get_noise_2d(x, z) * 0.5 + 0.5
	var c: Color
	if h < -0.4:
		return Color(0.30, 0.32, 0.27).lerp(Color(0.12, 0.2, 0.25), clampf(-h / 18.0, 0.0, 1.0))
	if (reg == "coast" or reg == "ocean" or h < 2.4) and x < -700.0:
		c = Color(0.80, 0.72, 0.52).lerp(Color(0.72, 0.64, 0.46), n)
	elif reg == "desert" or (x > 700.0 and z > -760.0):
		var dn: float = n_dune.get_noise_2d(x, z) * 0.5 + 0.5
		c = Color(0.82, 0.62, 0.36).lerp(Color(0.9, 0.72, 0.45), dn).lerp(Color(0.7, 0.52, 0.3), n * 0.4)
		var dw: float = smoothstep(700.0, 860.0, x)
		c = Color(0.3, 0.4, 0.17).lerp(c, dw)
	elif reg == "mountain" or h > 40.0:
		var g: Color = Color(0.2, 0.32, 0.13).lerp(Color(0.15, 0.27, 0.11), n)
		var rock: Color = Color(0.43, 0.4, 0.37).lerp(Color(0.36, 0.34, 0.33), n)
		c = g.lerp(rock, smoothstep(30.0, 90.0, h))
		c = c.lerp(rock, smoothstep(0.82, 0.6, ny))
		c = c.lerp(Color(0.88, 0.9, 0.94), smoothstep(150.0, 185.0, h) * smoothstep(0.55, 0.85, ny))
	elif reg == "city":
		c = Color(0.34, 0.35, 0.36).lerp(Color(0.3, 0.31, 0.32), n)
		var rr: float = sqrt(x * x + z * z)
		c = c.lerp(Color(0.26, 0.4, 0.17).lerp(Color(0.2, 0.34, 0.14), n), smoothstep(480.0, 560.0, rr))
	elif reg == "forest":
		c = Color(0.14, 0.27, 0.1).lerp(Color(0.2, 0.33, 0.12), n)
	elif reg == "industrial":
		c = Color(0.35, 0.34, 0.31).lerp(Color(0.28, 0.3, 0.24), n)
	else:
		c = Color(0.3, 0.45, 0.16).lerp(Color(0.38, 0.5, 0.2), n)
		if reg == "countryside" and n_forest.get_noise_2d(x * 0.5 + 99.0, z * 0.5) > 0.2:
			c = Color(0.62, 0.55, 0.22).lerp(Color(0.5, 0.42, 0.18), n)
	return c

# ----------------------------------------------------------------- road graph
func _node(x: float, z: float) -> int:
	for i in nodes.size():
		var p: Vector3 = nodes[i]
		if absf(p.x - x) < 9.0 and absf(p.z - z) < 9.0:
			return i
	nodes.append(Vector3(x, NAN, z))
	node_adj.append([])
	return nodes.size() - 1

func _cr(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

func add_road(kind: String, ctrl: Array, smooth: bool = true, closed: bool = false, name: String = "") -> void:
	var n: int = ctrl.size()
	var segs: int = n if closed else n - 1
	var prev_node: int = _node(ctrl[0].x, ctrl[0].y)
	for i in range(segs):
		var i1: int = (i + 1) % n
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i1]
		var p0: Vector2 = ctrl[(i - 1 + n) % n] if (i > 0 or closed) else p1
		var p3: Vector2 = ctrl[(i + 2) % n] if (i + 2 < n or closed) else p2
		var len: float = p1.distance_to(p2)
		var steps: int = maxi(1, int(ceil(len / 5.0)))
		var pts := PackedVector3Array()
		for s in range(steps + 1):
			var t: float = float(s) / float(steps)
			var q: Vector2 = _cr(p0, p1, p2, p3, t) if smooth else p1.lerp(p2, t)
			pts.append(Vector3(q.x, 0.0, q.y))
		var a: int = prev_node
		var b: int = _node(p2.x, p2.y)
		if a == b:
			continue
		var info: Dictionary = KINDS[kind]
		var e: Dictionary = {"a": a, "b": b, "pts": pts, "kind": kind, "width": float(info["w"]), "lanes": int(info["lanes"]),
			"limit": float(info["limit"]), "name": name, "light_a": false, "light_b": false}
		edges.append(e)
		var ei: int = edges.size() - 1
		node_adj[a].append(ei)
		node_adj[b].append(ei)
		prev_node = b

func _build_layout() -> void:
	# --- pads (flat areas) --------------------------------------------------
	_pad(-35.0, -35.0, 40.0, CITY_H, 20.0)       # home garage area
	_pad(-810.0, 200.0, 95.0, 5.0, 60.0)         # Marlin Bay seaside town + beach parking
	_pad(-835.0, -372.0, 30.0, 32.0, 30.0)       # lighthouse headland
	_pad(-930.0, 760.0, 110.0, 3.5, 45.0)        # port
	_pad(-40.0, 1250.0, 260.0, 12.0, 80.0)       # racing circuit infield
	_pad(1430.0, 205.0, 70.0, 10.0, 50.0)        # desert outpost
	_pad(1250.0, -390.0, 90.0, 11.0, 50.0)       # ghost town
	_pad_auto(60.0, -1335.0, 34.0, 28.0)         # summit lookout (height from terrain)
	_pad(-360.0, 760.0, 130.0, 7.0, 60.0)        # industrial district
	_pad(720.0, 0.0, 190.0, 7.5, 70.0)           # Eastwood suburbs
	# --- city grid ---------------------------------------------------------------
	for j in range(9):
		var pts_h: Array = []
		for i in range(9):
			pts_h.append(Vector2(GRID_START + GRID_STEP * i, GRID_START + GRID_STEP * j))
		add_road("avenue" if j in [0, 4, 8] else "street", pts_h, false, false, "Row %d" % j)
	for i in range(9):
		var pts_v: Array = []
		for j in range(9):
			pts_v.append(Vector2(GRID_START + GRID_STEP * i, GRID_START + GRID_STEP * j))
		add_road("avenue" if i in [0, 4, 8] else "street", pts_v, false, false, "Col %d" % i)
	# --- East interstate to the desert ------------------------------------------
	add_road("highway", [Vector2(500, 0), Vector2(650, 0), Vector2(800, 0), Vector2(1000, 0), Vector2(1150, 60), Vector2(1300, 140), Vector2(1430, 205)], true, false, "East Interstate")
	# Eastwood suburbs
	add_road("suburb", [Vector2(500, -250), Vector2(650, -250), Vector2(800, -250)], false, false, "Maple Drive")
	add_road("suburb", [Vector2(500, 250), Vector2(650, 250), Vector2(800, 250)], false, false, "Cedar Drive")
	add_road("suburb", [Vector2(650, -250), Vector2(650, -125), Vector2(650, 0), Vector2(650, 125), Vector2(650, 250)], false, false, "Oak Lane")
	add_road("suburb", [Vector2(800, -250), Vector2(800, -125), Vector2(800, 0), Vector2(800, 125), Vector2(800, 250)], false, false, "Elm Lane")
	# Drag strip + link
	add_road("highway", [Vector2(800, 250), Vector2(850, 380), Vector2(920, 520), Vector2(1100, 520), Vector2(1300, 520), Vector2(1500, 520)], true, false, "Quarter Mile Road")
	# Desert dirt tracks
	add_road("dirt", [Vector2(1430, 205), Vector2(1330, 310), Vector2(1190, 340), Vector2(1060, 270), Vector2(1000, 150), Vector2(1000, 0)], true, false, "Dune Track A")
	add_road("dirt", [Vector2(1430, 205), Vector2(1500, 60), Vector2(1470, -150), Vector2(1380, -300), Vector2(1250, -390), Vector2(1110, -300), Vector2(1030, -150), Vector2(1000, 0)], true, false, "Dune Track B")
	add_road("dirt", [Vector2(1250, -390), Vector2(1200, -520), Vector2(1100, -600)], true, false, "Dune Track C")
	add_road("dirt", [Vector2(1190, 340), Vector2(1250, 430), Vector2(1300, 520)], true, false, "Dune Track D")
	# --- North pass + mountain switchbacks -------------------------------------
	add_road("highway", [Vector2(0, -500), Vector2(0, -580), Vector2(10, -650), Vector2(30, -710)], true, false, "North Pass")
	add_road("mountain", [Vector2(30, -710), Vector2(150, -760), Vector2(260, -835), Vector2(150, -900), Vector2(10, -940), Vector2(-120, -1005), Vector2(-20, -1075), Vector2(120, -1105), Vector2(250, -1170), Vector2(190, -1250), Vector2(60, -1335)], true, false, "Summit Road")
	add_road("mountain", [Vector2(-120, -1005), Vector2(-260, -990), Vector2(-390, -940), Vector2(-500, -880), Vector2(-610, -790), Vector2(-700, -700), Vector2(-748, -640)], true, false, "Ridge Road")
	# --- coastal highway ------------------------------------------------------------
	add_road("coastal", [Vector2(-748, -640), Vector2(-770, -560), Vector2(-780, -470), Vector2(-780, -350), Vector2(-775, -230), Vector2(-780, -100), Vector2(-790, 0), Vector2(-790, 120), Vector2(-785, 240), Vector2(-790, 360)], true, false, "Coast Highway")
	add_road("coastal", [Vector2(-790, 360), Vector2(-795, 520), Vector2(-800, 640), Vector2(-800, 760), Vector2(-795, 900), Vector2(-790, 1050), Vector2(-780, 1200), Vector2(-770, 1330)], true, false, "Coast Highway South")
	add_road("coastal", [Vector2(-500, 0), Vector2(-640, 0), Vector2(-790, 0)], false, false, "Marlin Link")
	add_road("coastal", [Vector2(-500, -500), Vector2(-620, -540), Vector2(-748, -640)], true, false, "Cliff Link")
	# Marlin Bay town street
	add_road("suburb", [Vector2(-790, 120), Vector2(-720, 130), Vector2(-690, 200), Vector2(-720, 270), Vector2(-785, 240)], true, false, "Bay Street")
	# --- Port + industrial --------------------------------------------------------
	add_road("industrial", [Vector2(-250, 500), Vector2(-250, 640), Vector2(-250, 760), Vector2(-250, 900)], false, false, "Foundry Road")
	add_road("industrial", [Vector2(-500, 500), Vector2(-500, 640), Vector2(-500, 760), Vector2(-650, 760), Vector2(-800, 760)], false, false, "Dock Road")
	add_road("industrial", [Vector2(-500, 760), Vector2(-375, 760), Vector2(-250, 760), Vector2(-100, 760)], false, false, "Works Avenue")
	add_road("industrial", [Vector2(-800, 760), Vector2(-900, 760), Vector2(-980, 760)], false, false, "Quay Road")
	add_road("industrial", [Vector2(-900, 760), Vector2(-900, 680)], false, false, "Quay Spur A")
	add_road("industrial", [Vector2(-900, 760), Vector2(-900, 840)], false, false, "Quay Spur B")
	# --- Forest roads (south-east) ------------------------------------------------
	add_road("country", [Vector2(500, 500), Vector2(540, 620), Vector2(500, 760), Vector2(430, 900), Vector2(470, 1040), Vector2(580, 1150), Vector2(720, 1230), Vector2(830, 1330), Vector2(900, 1450)], true, false, "Pine Ridge Road")
	add_road("country", [Vector2(430, 900), Vector2(320, 960), Vector2(200, 1010), Vector2(110, 1090)], true, false, "Logging Road")
	add_road("country", [Vector2(0, 500), Vector2(10, 640), Vector2(-20, 780), Vector2(-60, 900), Vector2(-100, 1010)], true, false, "South Road")
	# --- Countryside + circuit --------------------------------------------------------
	add_road("country", [Vector2(-250, 900), Vector2(-250, 1000), Vector2(-190, 1110), Vector2(-120, 1170)], true, false, "Farm Road")
	add_road("country", [Vector2(-100, 1010), Vector2(-120, 1090), Vector2(-120, 1170)], true, false, "Circuit Access")
	add_road("country", [Vector2(-250, 1000), Vector2(-420, 1060), Vector2(-600, 1150), Vector2(-780, 1200)], true, false, "Barn Road")
	var circ: Array = []
	var cpts: Array = [Vector2(-120, 1170), Vector2(-20, 1130), Vector2(90, 1150), Vector2(170, 1215), Vector2(180, 1290), Vector2(110, 1345), Vector2(10, 1340), Vector2(-60, 1300), Vector2(-130, 1350), Vector2(-210, 1320), Vector2(-240, 1240)]
	for q in cpts: circ.append(q)
	add_road("track", circ, true, true, "Apex Speedway")
	# --- east expansion: airport, business + accommodation districts ---------------------------------
	WorldExpansion.add_terrain(self)
	WorldExpansion.add_roads(self)
	RaceTracks.add_terrain(self)
	RaceTracks.add_roads(self)
	# --- finalize heights -------------------------------------------------------
	_finalize_heights()

func _pad(x: float, z: float, r: float, h: float, b: float) -> void:
	pads.append({"x": x, "z": z, "r": r, "h": h, "b": b})

func _pad_auto(x: float, z: float, r: float, b: float) -> void:
	var h: float = nat_h(x, z)
	pads.append({"x": x, "z": z, "r": r, "h": h, "b": b})

func _finalize_heights() -> void:
	var nn: int = nodes.size()
	var pinned: Array = []
	for i in range(nn):
		var p: Vector3 = nodes[i]
		var r: float = sqrt(p.x * p.x + p.z * p.z)
		var h: float = 0.0
		var cnt: int = 0
		for ox in [-10.0, 0.0, 10.0]:
			for oz in [-10.0, 0.0, 10.0]:
				h += nat_h(p.x + ox, p.z + oz)
				cnt += 1
		h /= float(cnt)
		var pin: bool = r < 505.0
		if pin:
			h = CITY_H
		# nodes standing in water (bridge approaches) are lifted to a deck level
		h = maxf(h, 4.5)
		nodes[i] = Vector3(p.x, h, p.z)
		pinned.append(pin)
	# relax heights so slopes stay drivable
	for it in range(14):
		for i in range(nn):
			if pinned[i]:
				continue
			var s: float = 0.0
			var c: int = 0
			for ei in node_adj[i]:
				var e: Dictionary = edges[ei]
				var o: int = int(e["b"]) if int(e["a"]) == i else int(e["a"])
				s += (nodes[o] as Vector3).y
				c += 1
			if c > 0:
				var p2: Vector3 = nodes[i]
				p2.y = p2.y * 0.55 + (s / float(c)) * 0.45
				nodes[i] = p2
	# grade limiting
	for it in range(10):
		for e in edges:
			var a: int = int(e["a"])
			var b: int = int(e["b"])
			var pa: Vector3 = nodes[a]
			var pb: Vector3 = nodes[b]
			var d: float = Vector2(pa.x - pb.x, pa.z - pb.z).length()
			var maxdh: float = d * (0.13 if e["kind"] != "highway" else 0.07)
			var dh: float = pb.y - pa.y
			if absf(dh) > maxdh:
				var excess: float = (absf(dh) - maxdh) * 0.5
				var sgn: float = signf(dh)
				if not pinned[a]:
					pa.y += sgn * excess
					nodes[a] = pa
				if not pinned[b]:
					pb.y -= sgn * excess
					nodes[b] = pb
	# per-edge sample heights, lengths, bridge flags
	for ei in edges.size():
		var e: Dictionary = edges[ei]
		var pts: PackedVector3Array = e["pts"]
		var ha: float = (nodes[int(e["a"])] as Vector3).y
		var hb: float = (nodes[int(e["b"])] as Vector3).y
		var cum := PackedFloat32Array()
		var tot: float = 0.0
		cum.append(0.0)
		for k in range(1, pts.size()):
			tot += Vector2(pts[k].x - pts[k - 1].x, pts[k].z - pts[k - 1].z).length()
			cum.append(tot)
		var br := PackedByteArray()
		br.resize(pts.size())
		for k in range(pts.size()):
			var t: float = cum[k] / maxf(0.001, tot)
			var tt: float = t * t * (3.0 - 2.0 * t)
			var y: float = lerpf(ha, hb, tt)
			pts[k] = Vector3(pts[k].x, y, pts[k].z)
			var nh: float = nat_h(pts[k].x, pts[k].z)
			br[k] = 1 if (nh < 0.4 and nh < y - 2.6) else 0
		e["pts"] = pts
		e["cum"] = cum
		e["len"] = tot
		e["bridge"] = br
		# bridge runs: pad by one sample each side so ends meet cleanly
		var k2: int = 0
		while k2 < pts.size():
			if br[k2] == 1:
				var k3: int = k2
				while k3 + 1 < pts.size() and br[k3 + 1] == 1:
					k3 += 1
				bridges.append({"edge": ei, "i0": maxi(0, k2 - 1), "i1": mini(pts.size() - 1, k3 + 1)})
				k2 = k3 + 1
			else:
				k2 += 1

func _rasterize() -> void:
	var total: int = (GRID_N + 1) * (GRID_N + 1)
	infl.resize(total)
	rh.resize(total)
	for ei in edges.size():
		var e: Dictionary = edges[ei]
		var info: Dictionary = KINDS[e["kind"]]
		var hw: float = float(e["width"]) * 0.5 + (3.6 if info["side"] else 1.8)
		var fall: float = float(info["fall"])
		var R: float = hw + fall
		var rc: int = int(ceil(R / CELL))
		var pts: PackedVector3Array = e["pts"]
		var br: PackedByteArray = e["bridge"]
		for k in range(pts.size()):
			if br[k] == 1:
				continue
			var p: Vector3 = pts[k]
			var cx: int = int(round((p.x + HALF) / CELL))
			var cz: int = int(round((p.z + HALF) / CELL))
			for dz in range(-rc, rc + 1):
				var iz: int = cz + dz
				if iz < 0 or iz > GRID_N:
					continue
				for dx in range(-rc, rc + 1):
					var ix: int = cx + dx
					if ix < 0 or ix > GRID_N:
						continue
					var wx: float = -HALF + float(ix) * CELL - p.x
					var wz: float = -HALF + float(iz) * CELL - p.z
					var d: float = sqrt(wx * wx + wz * wz)
					if d > R:
						continue
					var w: float = 1.0 if d <= hw else 1.0 - smoothstep(hw, R, d)
					var gi: int = iz * (GRID_N + 1) + ix
					if w > infl[gi]:
						infl[gi] = w
						rh[gi] = p.y

func _index_roads() -> void:
	for ei in edges.size():
		var e: Dictionary = edges[ei]
		var pts: PackedVector3Array = e["pts"]
		for k in range(pts.size()):
			var sk: Vector2i = Vector2i(int(floor(pts[k].x / 32.0)), int(floor(pts[k].z / 32.0)))
			var kk: int = sk.x * 100000 + sk.y
			if not snap_grid.has(kk):
				snap_grid[kk] = PackedInt32Array()
			var arr: PackedInt32Array = snap_grid[kk]
			arr.append(ei)
			arr.append(k)
			snap_grid[kk] = arr
			if k < pts.size() - 1:
				var mid: Vector3 = (pts[k] + pts[k + 1]) * 0.5
				var ck: Vector2i = chunk_of(mid.x, mid.z)
				var key2: int = key(ck.x, ck.y)
				if not seg_index.has(key2):
					seg_index[key2] = PackedInt32Array()
				var a2: PackedInt32Array = seg_index[key2]
				a2.append(ei)
				a2.append(k)
				seg_index[key2] = a2

## nearest road sample: returns {edge, idx, pos, dist}
func nearest_road(p: Vector3, max_r: float = 400.0) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = max_r * max_r
	var cx: int = int(floor(p.x / 32.0))
	var cz: int = int(floor(p.z / 32.0))
	var rr: int = int(ceil(max_r / 32.0))
	rr = mini(rr, 14)
	for dz in range(-rr, rr + 1):
		for dx in range(-rr, rr + 1):
			var kk: int = (cx + dx) * 100000 + (cz + dz)
			if not snap_grid.has(kk):
				continue
			var arr: PackedInt32Array = snap_grid[kk]
			for q in range(0, arr.size(), 2):
				var e: Dictionary = edges[arr[q]]
				var pt: Vector3 = (e["pts"] as PackedVector3Array)[arr[q + 1]]
				var d2: float = (pt.x - p.x) * (pt.x - p.x) + (pt.z - p.z) * (pt.z - p.z)
				if d2 < bd:
					bd = d2
					best = {"edge": arr[q], "idx": arr[q + 1], "pos": pt, "dist": sqrt(d2)}
	return best

func nearest_node(p: Vector3) -> int:
	var bi: int = 0
	var bd: float = 1e18
	for i in nodes.size():
		var n: Vector3 = nodes[i]
		var d: float = (n.x - p.x) * (n.x - p.x) + (n.z - p.z) * (n.z - p.z)
		if d < bd:
			bd = d
			bi = i
	return bi

# ----------------------------------------------------------------- city & structures
func _hash2(a: int, b: int) -> float:
	var h: int = (a * 73856093) ^ (b * 19349663) ^ seed_value
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0

func _add_building(p: Vector3, size: Vector3, col: Color, kind: String, extra: Dictionary = {}) -> void:
	var ck: Vector2i = chunk_of(p.x, p.z)
	var k: int = key(ck.x, ck.y)
	if not buildings.has(k):
		buildings[k] = []
	var d: Dictionary = {"p": p, "s": size, "c": col, "kind": kind}
	d.merge(extra, true)
	buildings[k].append(d)

func _building_palette(rng: RandomNumberGenerator, downtown: bool) -> Color:
	var palette: Array = [Color(0.55, 0.57, 0.6), Color(0.42, 0.45, 0.5), Color(0.7, 0.68, 0.62), Color(0.33, 0.36, 0.42),
		Color(0.62, 0.5, 0.42), Color(0.5, 0.55, 0.58), Color(0.75, 0.75, 0.78), Color(0.38, 0.4, 0.45)]
	if downtown:
		palette = [Color(0.3, 0.38, 0.5), Color(0.25, 0.3, 0.38), Color(0.5, 0.55, 0.62), Color(0.2, 0.25, 0.32), Color(0.4, 0.5, 0.55)]
	return palette[rng.randi() % palette.size()]

const STATION_BLOCK := Vector2i(3, 4)
## extracted from the two building packs by tools/extract_buildings.py (assets/buildings/pack/<id>.glb)
const PACK_TOWERS := ["city_tower_a", "city_tower_b", "city_tower_c", "city_tower_d"]
const PACK_MID := ["city_block_a", "city_block_b", "city_block_c", "city_mid_a", "city_mid_b", "city_mid_c", "city_low_a"]

## Residential blocks (south-east of the centre) are filled with Soviet apartment slabs, the mid ring with the
## stylised mid-rise buildings, the centre alternates pack towers with the existing procedural skyscrapers.
## Returns true when the lot was filled (or deliberately left empty).
func _place_pack_lot(rng: RandomNumberGenerator, bi: int, bj: int, li: int, lj: int, p: Vector3, lot: float, dist: float) -> bool:
	var residential: bool = bi >= 5 and bj >= 4 and dist < 760.0
	if residential:
		if li == 0:       # one long slab per lot row, running east-west, set back from the street
			_add_pack(p + Vector3(lot * 0.5, 0.0, 0.0), "soviet_panelka", PI * 0.5, Vector3(13.1, 13.3, 42.7))
		return true
	if dist < 200.0:
		if (li + lj + bi + bj) % 2 == 0:
			_add_pack(p, PACK_TOWERS[rng.randi() % PACK_TOWERS.size()], float(rng.randi() % 4) * PI * 0.5, Vector3.ZERO)
			return true
		return false
	if dist < 440.0 and rng.randf() < 0.7:
		_add_pack(p, PACK_MID[rng.randi() % PACK_MID.size()], float(rng.randi() % 4) * PI * 0.5, Vector3.ZERO)
		return true
	return false

func _add_pack(p: Vector3, id: String, yaw: float, size: Vector3) -> void:
	var sz: Vector3 = size
	if sz == Vector3.ZERO:
		var r: Dictionary = (PackBuildings.SIZES.get(id, {}) as Dictionary)
		sz = Vector3(float(r.get("w", 10.0)), float(r.get("h", 20.0)), float(r.get("d", 10.0)))
	_add_building(p, sz, Color.WHITE, "pack", {"yaw": yaw, "pack": id})

func _build_city() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var special: Dictionary = {}
	# special blocks (i, j) -> type
	special[Vector2i(3, 3)] = "garage"
	special[Vector2i(4, 4)] = "plaza"
	special[Vector2i(4, 3)] = "dealership"
	special[Vector2i(6, 6)] = "parking"
	special[Vector2i(1, 2)] = "park"
	special[Vector2i(6, 1)] = "park"
	special[Vector2i(2, 6)] = "gas"
	special[Vector2i(7, 3)] = "gas"
	special[Vector2i(0, 4)] = "stadium"
	special[STATION_BLOCK] = "station"
	for bj in range(8):
		for bi in range(8):
			var cx: float = GRID_START + GRID_STEP * (bi + 0.5)
			var cz: float = GRID_START + GRID_STEP * (bj + 0.5)
			var gh: float = nat_h(cx, cz)
			if gh < 3.5:
				continue
			var dist: float = Vector2(cx, cz).length()
			var sp: String = special.get(Vector2i(bi, bj), "")
			var half: float = GRID_STEP * 0.5 - 15.0
			match sp:
				"garage":
					structures.append({"type": "garage", "pos": Vector3(cx, gh, cz), "size": Vector3(34, 9, 26)})
					landmarks["home_garage"] = Vector3(cx, gh, cz + 16.0)
					continue
				"dealership":
					structures.append({"type": "dealership", "pos": Vector3(cx, gh, cz), "size": Vector3(44, 10, 30)})
					landmarks["dealership"] = Vector3(cx, gh, cz + 20.0)
					continue
				"plaza":
					structures.append({"type": "plaza", "pos": Vector3(cx, gh, cz), "size": Vector3(70, 1, 70)})
					landmarks["city_center"] = Vector3(cx, gh, cz)
					continue
				"parking":
					structures.append({"type": "parking", "pos": Vector3(cx, gh, cz), "size": Vector3(60, 24, 50)})
					landmarks["rooftop_parking"] = Vector3(cx, gh + 22.0, cz)
					landmarks["parking_ramp"] = Vector3(cx + 36.0, gh, cz)
					continue
				"park":
					structures.append({"type": "park", "pos": Vector3(cx, gh, cz), "size": Vector3(95, 1, 95)})
					continue
				"gas":
					structures.append({"type": "gas", "pos": Vector3(cx, gh, cz), "size": Vector3(40, 6, 30)})
					landmarks["gas_%d_%d" % [bi, bj]] = Vector3(cx, gh, cz)
					continue
				"station":
					structures.append({"type": "station", "pos": Vector3(cx, gh, cz), "size": Vector3(108, 1, 108)})
					landmarks["station"] = Vector3(cx, gh, cz)
					keepouts.append(Rect2(cx - 54.0, cz - 54.0, 108.0, 108.0))
					continue
				"stadium":
					structures.append({"type": "stadium", "pos": Vector3(cx, gh, cz), "size": Vector3(80, 18, 96)})
					landmarks["stadium"] = Vector3(cx, gh, cz)
					continue
			# regular lots
			var lots: int = 2 if dist < 330.0 else 2
			var lot_size: float = (half * 2.0) / float(lots)
			for lj in range(lots):
				for li in range(lots):
					var lx: float = cx - half + lot_size * (li + 0.5)
					var lz: float = cz - half + lot_size * (lj + 0.5)
					var jitter: float = rng.randf()
					var down: bool = dist < 260.0
					var h: float
					var fw: float = lot_size * rng.randf_range(0.62, 0.85)
					var fd: float = lot_size * rng.randf_range(0.62, 0.85)
					var kind: String = "apartment"
					if _place_pack_lot(rng, bi, bj, li, lj, Vector3(lx, gh, lz), lot_size, dist):
						continue
					if down:
						h = rng.randf_range(55.0, 190.0) * (1.25 - dist / 520.0)
						kind = "tower"
					elif dist < 400.0:
						h = rng.randf_range(24.0, 62.0)
					else:
						h = rng.randf_range(8.0, 26.0)
						kind = "shop"
					if jitter < 0.07 and not down:
						continue
					_add_building(Vector3(lx, gh, lz), Vector3(fw, h, fd), _building_palette(rng, down), kind, {"lit": rng.randf_range(0.25, 0.8), "win": 1.0, "seed": rng.randf() * 100.0})
	# --- suburbs: houses along suburb roads ------------------------------------
	for e in edges:
		if e["kind"] != "suburb":
			continue
		var pts: PackedVector3Array = e["pts"]
		var cum: PackedFloat32Array = e["cum"]
		var s: float = 10.0
		var tot: float = float(e["len"])
		while s < tot - 10.0:
			var k: int = 0
			while k < cum.size() - 2 and cum[k + 1] < s:
				k += 1
			var p: Vector3 = pts[k]
			var q: Vector3 = pts[mini(k + 1, pts.size() - 1)]
			var dir := Vector2(q.x - p.x, q.z - p.z).normalized()
			if dir.length() < 0.1:
				s += 22.0
				continue
			var nrm := Vector2(-dir.y, dir.x)
			for side in [-1.0, 1.0]:
				var off: float = float(e["width"]) * 0.5 + 12.0 + rng.randf_range(0.0, 4.0)
				var hx: float = p.x + nrm.x * off * side
				var hz: float = p.z + nrm.y * off * side
				if road_weight(hx, hz) > 0.05 or not _free_of_roads(hx, hz, 9.0):
					continue
				var gh2: float = nat_h(hx, hz)
				if gh2 < 2.5:
					continue
				var yaw: float = atan2(-nrm.x * side, -nrm.y * side)
				var hc: Color = [Color(0.85, 0.8, 0.7), Color(0.75, 0.82, 0.88), Color(0.88, 0.72, 0.62), Color(0.8, 0.85, 0.72), Color(0.9, 0.9, 0.86), Color(0.7, 0.62, 0.55)][rng.randi() % 6]
				_add_building(Vector3(hx, gh2, hz), Vector3(rng.randf_range(8.0, 11.0), rng.randf_range(4.2, 6.0), rng.randf_range(7.0, 9.5)), hc, "house", {"yaw": yaw, "lit": 0.5, "win": 1.0, "seed": rng.randf() * 100.0})
			s += rng.randf_range(20.0, 28.0)
	# --- Marlin Bay seaside town ----------------------------------------------------
	for q in range(14):
		var t: float = float(q) / 13.0
		var tz: float = lerpf(95.0, 330.0, t)
		var side: float = -1.0 if q % 2 == 0 else 1.0
		var bx: float = -790.0 + side * rng.randf_range(24.0, 34.0)
		var gh3: float = nat_h(bx, tz)
		if gh3 < 2.0 or not _free_of_roads(bx, tz, 12.0):
			continue
		var tc: Color = [Color(0.95, 0.85, 0.7), Color(0.6, 0.8, 0.88), Color(0.95, 0.6, 0.55), Color(0.9, 0.9, 0.82), Color(0.55, 0.78, 0.7)][rng.randi() % 5]
		_add_building(Vector3(bx, gh3, tz), Vector3(rng.randf_range(10.0, 15.0), rng.randf_range(7.0, 13.0), rng.randf_range(10.0, 14.0)), tc, "shop", {"lit": 0.5, "win": 1.0, "seed": rng.randf() * 100.0})
	# --- industrial warehouses -------------------------------------------------------
	for e in edges:
		if e["kind"] != "industrial":
			continue
		var pts2: PackedVector3Array = e["pts"]
		var cum2: PackedFloat32Array = e["cum"]
		var tot2: float = float(e["len"])
		var s2: float = 30.0
		while s2 < tot2 - 30.0:
			var k2: int = 0
			while k2 < cum2.size() - 2 and cum2[k2 + 1] < s2:
				k2 += 1
			var p2: Vector3 = pts2[k2]
			var q2: Vector3 = pts2[mini(k2 + 1, pts2.size() - 1)]
			var d2 := Vector2(q2.x - p2.x, q2.z - p2.z).normalized()
			var n2 := Vector2(-d2.y, d2.x)
			for side2 in [-1.0, 1.0]:
				var off2: float = 22.0 + rng.randf_range(0.0, 8.0)
				var wx: float = p2.x + n2.x * off2 * side2
				var wz: float = p2.z + n2.y * off2 * side2
				if not _free_of_roads(wx, wz, 22.0):
					continue
				var gh4: float = nat_h(wx, wz)
				if gh4 < 2.5 or rng.randf() < 0.25:
					continue
				var yaw2: float = atan2(d2.x, d2.y)
				var big: float = rng.randf_range(24.0, 42.0)
				var is_chimney: bool = rng.randf() < 0.12
				if is_chimney:
					_add_building(Vector3(wx, gh4, wz), Vector3(5.0, 55.0, 5.0), Color(0.5, 0.35, 0.3), "chimney", {"yaw": yaw2, "win": 0.0, "lit": 0.0, "seed": 1.0})
				else:
					_add_building(Vector3(wx, gh4, wz), Vector3(big, rng.randf_range(8.0, 15.0), rng.randf_range(24.0, 40.0)), [Color(0.55, 0.57, 0.55), Color(0.5, 0.42, 0.38), Color(0.4, 0.5, 0.55), Color(0.6, 0.6, 0.5)][rng.randi() % 4], "warehouse", {"yaw": yaw2, "win": 0.0, "lit": 0.0, "seed": rng.randf() * 100.0})
			s2 += rng.randf_range(38.0, 52.0)
	# --- port containers -------------------------------------------------------------
	for cxr in range(10):
		for czr in range(5):
			var px: float = -985.0 + float(cxr) * 8.0 + (0.0 if czr < 3 else 6.0)
			var pz: float = 700.0 + float(czr) * 40.0 - 60.0
			if absf(pz - 760.0) < 12.0 or absf(px + 900.0) < 12.0:
				continue
			var stack: int = 1 + rng.randi() % 3
			for sy in range(stack):
				var cc: Color = [Color(0.7, 0.15, 0.1), Color(0.1, 0.3, 0.6), Color(0.85, 0.65, 0.1), Color(0.15, 0.5, 0.3), Color(0.5, 0.5, 0.55)][rng.randi() % 5]
				_add_building(Vector3(px, 3.5 + float(sy) * 2.6, pz), Vector3(2.5, 2.6, 12.0), cc, "container", {"win": 0.0, "lit": 0.0, "seed": 1.0})
	# --- mountain cabins ---------------------------------------------------------------
	for q in range(9):
		var ang: float = rng.randf() * TAU
		var rad: float = rng.randf_range(20.0, 85.0)
		var cabx: float = -250.0 + cos(ang) * rad
		var cabz: float = -985.0 + sin(ang) * rad
		if not _free_of_roads(cabx, cabz, 16.0):
			continue
		_add_building(Vector3(cabx, nat_h(cabx, cabz), cabz), Vector3(7.5, 3.6, 6.5), Color(0.45, 0.3, 0.2), "house", {"yaw": rng.randf() * TAU, "lit": 0.6, "win": 1.0, "seed": rng.randf() * 100.0})
	landmarks["pinecrest"] = Vector3(-250.0, nat_h(-250.0, -985.0), -985.0)
	# --- desert outposts and ghost town --------------------------------------------------
	for q in range(8):
		var gx: float = 1250.0 + rng.randf_range(-70.0, 70.0)
		var gz: float = -390.0 + rng.randf_range(-70.0, 70.0)
		if not _free_of_roads(gx, gz, 14.0):
			continue
		_add_building(Vector3(gx, nat_h(gx, gz), gz), Vector3(rng.randf_range(6.0, 12.0), rng.randf_range(3.5, 7.0), rng.randf_range(6.0, 10.0)), Color(0.6, 0.5, 0.38), "ruin", {"yaw": rng.randf() * TAU, "win": 0.0, "lit": 0.0, "seed": 3.0})
	for q in range(6):
		var ox: float = 1430.0 + rng.randf_range(-45.0, 45.0)
		var oz: float = 205.0 + rng.randf_range(-45.0, 45.0)
		if not _free_of_roads(ox, oz, 14.0):
			continue
		_add_building(Vector3(ox, nat_h(ox, oz), oz), Vector3(rng.randf_range(7.0, 11.0), rng.randf_range(3.5, 5.0), rng.randf_range(7.0, 10.0)), Color(0.75, 0.68, 0.55), "shop", {"lit": 0.5, "win": 1.0, "seed": rng.randf() * 100.0})
	# --- farms ---------------------------------------------------------------------------
	for q in range(7):
		var fx: float = rng.randf_range(-700.0, -100.0)
		var fz: float = rng.randf_range(930.0, 1500.0)
		if not _free_of_roads(fx, fz, 40.0) or nat_h(fx, fz) < 3.0 or (fx > -330.0 and fz > 1100.0 and fz < 1420.0):
			continue
		_add_building(Vector3(fx, nat_h(fx, fz), fz), Vector3(14.0, 8.0, 22.0), Color(0.6, 0.15, 0.1), "barn", {"yaw": rng.randf() * TAU, "win": 0.0, "lit": 0.0, "seed": 2.0})
		_add_building(Vector3(fx + 18.0, nat_h(fx + 18.0, fz), fz), Vector3(5.0, 14.0, 5.0), Color(0.75, 0.75, 0.72), "chimney", {"win": 0.0, "lit": 0.0, "seed": 1.0})
	# --- circuit grandstands + pit building --------------------------------------------------
	structures.append({"type": "grandstand", "pos": Vector3(-20.0, nat_h(-20.0, 1105.0), 1105.0), "size": Vector3(70, 9, 14)})
	structures.append({"type": "pit", "pos": Vector3(-60.0, nat_h(-60.0, 1195.0), 1195.0), "size": Vector3(50, 6, 14)})
	structures.append({"type": "tower", "pos": Vector3(150.0, nat_h(150.0, 1180.0), 1180.0), "size": Vector3(8, 22, 8)})
	# --- gas stations at roadsides ----------------------------------------------------------------
	structures.append({"type": "gas", "pos": Vector3(-770.0, nat_h(-770.0, 460.0), 460.0), "size": Vector3(36, 6, 24), "facing": 0.0})
	landmarks["gas_coast"] = Vector3(-770.0, nat_h(-770.0, 460.0), 460.0)
	structures.append({"type": "gas", "pos": Vector3(860.0, nat_h(860.0, -30.0), -30.0), "size": Vector3(36, 6, 24), "facing": 0.0})
	landmarks["gas_east"] = Vector3(860.0, nat_h(860.0, -30.0), -30.0)
	structures.append({"type": "gas", "pos": Vector3(1405.0, nat_h(1405.0, 175.0), 175.0), "size": Vector3(36, 6, 24), "facing": 0.0})
	landmarks["gas_desert"] = Vector3(1405.0, nat_h(1405.0, 175.0), 175.0)
	structures.append({"type": "gas", "pos": Vector3(40.0, nat_h(40.0, -610.0), -610.0), "size": Vector3(36, 6, 24), "facing": 0.0})
	landmarks["gas_north"] = Vector3(40.0, nat_h(40.0, -610.0), -610.0)
	structures.append({"type": "gas", "pos": Vector3(30.0, nat_h(30.0, 720.0), 720.0), "size": Vector3(36, 6, 24), "facing": 0.0})
	landmarks["gas_south"] = Vector3(30.0, nat_h(30.0, 720.0), 720.0)
	# --- lighthouse, port cranes, summit ---------------------------------------------------------------
	structures.append({"type": "lighthouse", "pos": Vector3(-835.0, nat_h(-835.0, -372.0), -372.0), "size": Vector3(8, 32, 8)})
	landmarks["lighthouse"] = Vector3(-818.0, nat_h(-818.0, -372.0), -372.0)
	for cr in range(3):
		structures.append({"type": "crane", "pos": Vector3(-960.0, 3.5, 700.0 + float(cr) * 60.0), "size": Vector3(6, 34, 6)})
	structures.append({"type": "lookout", "pos": Vector3(60.0, nat_h(60.0, -1335.0), -1335.0), "size": Vector3(14, 3, 14)})
	landmarks["summit"] = Vector3(60.0, nat_h(60.0, -1335.0), -1335.0)
	landmarks["port"] = Vector3(-930.0, 3.5, 760.0)
	landmarks["marlin_bay"] = Vector3(-790.0, 5.0, 200.0)
	landmarks["desert_outpost"] = Vector3(1430.0, 10.0, 205.0)
	landmarks["ghost_town"] = Vector3(1250.0, 11.0, -390.0)
	landmarks["circuit"] = Vector3(-120.0, 12.0, 1170.0)
	landmarks["dragstrip_start"] = Vector3(950.0, nat_h(950.0, 520.0), 520.0)
	landmarks["dragstrip_end"] = Vector3(1500.0, nat_h(1500.0, 520.0), 520.0)
	landmarks["beach"] = Vector3(-830.0, 5.0, 150.0)
	landmarks["marina"] = Vector3(-375.0, CITY_H, 375.0)
	landmarks["industrial"] = Vector3(-250.0, 7.0, 760.0)
	landmarks["eastwood"] = Vector3(650.0, 7.5, 0.0)
	landmarks["pine_ridge"] = Vector3(430.0, nat_h(430.0, 900.0), 900.0)
	landmarks["north_pass"] = Vector3(10.0, nat_h(10.0, -650.0), -650.0)
	landmarks["farm"] = Vector3(-420.0, nat_h(-420.0, 1060.0), 1060.0)
	# cut-and-cover tunnel on Ridge Road
	_register_tunnel()
	# speed cameras
	speed_cameras = [Vector3(300, CITY_H, 0), Vector3(850, 7.5, 0), Vector3(0, CITY_H, -300), Vector3(-790, 5.0, 60), Vector3(1100, 20.0, 40)]
	ready_flag = true

func _free_of_roads(x: float, z: float, r: float) -> bool:
	for k in keepouts:
		if (k as Rect2).grow(r).has_point(Vector2(x, z)):
			return false
	var ix: int = int(round((x + HALF) / CELL))
	var iz: int = int(round((z + HALF) / CELL))
	var rc: int = int(ceil(r / CELL))
	for dz in range(-rc, rc + 1, 2):
		for dx in range(-rc, rc + 1, 2):
			var a: int = ix + dx
			var b: int = iz + dz
			if a < 0 or b < 0 or a > GRID_N or b > GRID_N:
				continue
			if infl[grid_index(a, b)] > 0.02:
				return false
	return true

func _register_tunnel() -> void:
	# find Ridge Road edge covering about (-500,-880)
	var best: Dictionary = nearest_road(Vector3(-500, 0, -880), 120.0)
	if best.is_empty():
		return
	var ei: int = int(best["edge"])
	var e: Dictionary = edges[ei]
	var pts: PackedVector3Array = e["pts"]
	var i0: int = maxi(0, int(best["idx"]) - 8)
	var i1: int = mini(pts.size() - 1, int(best["idx"]) + 8)
	tunnels.append({"edge": ei, "i0": i0, "i1": i1})
	landmarks["tunnel"] = pts[int(best["idx"])]

func build_all() -> void:
	_build_layout()
	# raster is expensive: run after layout
	_rasterize()
	_index_roads()
	_build_city()
	WorldExpansion.build(self)
	RaceTracks.register(self)

func edge_other(ei: int, node: int) -> int:
	var e: Dictionary = edges[ei]
	return int(e["b"]) if int(e["a"]) == node else int(e["a"])

func resolve_point(v: Variant) -> Vector3:
	## mission data helper: accepts "@landmark" or [x, z]
	if v is String and String(v).begins_with("@"):
		var nm: String = String(v).substr(1)
		if landmarks.has(nm):
			return landmarks[nm]
		return Vector3.ZERO
	if v is Array and v.size() >= 2:
		var x: float = float(v[0])
		var z: float = float(v[1])
		return Vector3(x, ground_h(x, z), z)
	return Vector3.ZERO
