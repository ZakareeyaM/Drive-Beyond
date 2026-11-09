class_name GasStation
extends Node3D
## Drive Beyond petrol station + repair bay + dealership entrance, built on the city block (3,4).
##
## The pump canopy is the optimised gas_station_5.glb (tools/optimize_gas_station.py, scaled to real size);
## everything else (forecourt, showroom, workshop, shop, price pylon) is built here from simple shapes so the
## three interaction areas have solid, readable surroundings.  Layout (local metres, +X east, +Z south):
##   canopy / pumps ......... (0, 14)     lanes run east-west, entered from either side road
##   dealership entrance .... door at (0, -23), showroom behind it
##   repair bay ............. pad at (17, 34), workshop at x 26..44
##   shop kiosk, price pylon  west side
## Interaction areas are plain circles used by World._update_poi (id / type / radius), see zone_defs().

const MODEL := "res://assets/locations/gas_station_opt.glb"
const SC := 0.55                       # the source model is ~1.8x real size
const CANOPY := Vector3(0.0, 0.0, 14.0)
const HALF := 54.0
const PUMP_X := [-5.0, -0.28, 5.0]     # model x (-9.1, -0.5, 9.1) * SC
const PUMP_Z := 5.56                   # island centre line (+-10.1 * SC)

var center: Vector3 = Vector3.ZERO     # block centre on the ground
var lights: Array = []

static func zone_defs(c: Vector3) -> Array:
	return [
		{"id": "station_fuel", "type": "fuel", "pos": c + CANOPY, "radius": 12.0, "label": "Fuel Pumps"},
		{"id": "station_repair", "type": "repair", "pos": c + Vector3(17.0, 0.0, 34.0), "radius": 6.5, "label": "Repair Bay"},
		{"id": "station_dealer", "type": "dealership", "pos": c + Vector3(0.0, 0.0, -21.0), "radius": 7.5, "label": "Dealership"},
	]

func build(c: Vector3) -> void:
	center = c
	position = c
	_apron()
	_canopy()
	_dealership()
	_workshop()
	_shop_and_pylon()
	_lamps()

# ------------------------------------------------------------------ helpers
func _mat(col: Color, rough: float = 0.85, metal: float = 0.0, emit: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	return m

func _box(parent: Node, pos: Vector3, size: Vector3, mat: Material, collide: bool = false, shadow: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if collide:
		_solid(pos, size)
	return mi

## static collider box (layer 1 = world, group "structure" so the damage system treats it like a building)
func _solid(pos: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.add_to_group("structure")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = pos
	add_child(sb)

func _label(text: String, pos: Vector3, yaw: float, col: Color, px: float = 0.05, flat: bool = false) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 0
	l.shaded = false
	l.double_sided = true
	l.position = pos
	l.rotation.y = yaw
	if flat:
		l.rotation_degrees.x = -90.0
	add_child(l)

# ------------------------------------------------------------------ forecourt
func _apron() -> void:
	var asphalt := _mat(Color(0.13, 0.135, 0.145), 0.95)
	# one slab for the whole block; its collider lets cars drive across at the same height as the roads
	var slab := _box(self, Vector3(0, -0.05, 0), Vector3(HALF * 2.0, 0.2, HALF * 2.0), asphalt)
	slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(HALF * 2.0, 0.2, HALF * 2.0)
	cs.shape = bs
	sb.add_child(cs)
	sb.position = Vector3(0, -0.05, 0)
	add_child(sb)
	# lighter concrete under the canopy and in the bays
	var conc := _mat(Color(0.33, 0.33, 0.34), 0.9)
	_box(self, CANOPY + Vector3(0, 0.06, 0), Vector3(24.0, 0.02, 21.0), conc)
	_box(self, Vector3(17.0, 0.06, 34.0), Vector3(12.0, 0.02, 8.5), conc)
	# painted borders
	var yellow := _mat(Color(0.95, 0.78, 0.1), 0.7, 0.0, 0.25)
	var white := _mat(Color(0.9, 0.9, 0.9), 0.7)
	for e in [[Vector3(17.0, 0.075, 29.6), Vector3(12.0, 0.01, 0.25)], [Vector3(17.0, 0.075, 38.4), Vector3(12.0, 0.01, 0.25)],
			[Vector3(11.1, 0.075, 34.0), Vector3(0.25, 0.01, 8.5)], [Vector3(22.9, 0.075, 34.0), Vector3(0.25, 0.01, 8.5)]]:
		_box(self, e[0], e[1], yellow)
	_label("REPAIR", Vector3(17.0, 0.1, 34.0), 0.0, Color(1.0, 0.85, 0.2), 0.045, true)
	# lane arrows / edge lines of the pump lanes
	for z in [CANOPY.z - 12.0, CANOPY.z + 12.0]:
		_box(self, Vector3(0, 0.07, z), Vector3(24.0, 0.01, 0.2), white)
	_label("FUEL", Vector3(-17.0, 0.1, CANOPY.z), -PI * 0.5, Color(1, 1, 1, 0.8), 0.06, true)

# ------------------------------------------------------------------ pump canopy (GLB)
func _canopy() -> void:
	var ps: PackedScene = load(MODEL) as PackedScene
	if ps != null:
		var inst: Node3D = ps.instantiate() as Node3D
		inst.position = CANOPY + Vector3(0, 0.07, 0)
		inst.scale = Vector3.ONE * SC
		add_child(inst)
		for gi in inst.find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(gi as GeometryInstance3D).visibility_range_end = 360.0
	else:
		push_error("GasStation: missing " + MODEL)
	# solid pump bodies + canopy supports (the island kerbs themselves are low enough to drive over)
	for sz in [-1.0, 1.0]:
		for px in PUMP_X:
			_solid(CANOPY + Vector3(px, 1.0, sz * PUMP_Z), Vector3(1.4, 2.0, 0.8))
		for ex in [-6.35, 6.35]:
			_solid(CANOPY + Vector3(ex, 1.0, sz * PUMP_Z), Vector3(1.0, 2.0, 0.9))
	# warm lights under the canopy, only lit at night (see _process)
	for lx in [-5.0, 5.0]:
		var o := OmniLight3D.new()
		o.position = CANOPY + Vector3(lx, 4.3, 0.0)
		o.light_color = Color(1.0, 0.92, 0.75)
		o.omni_range = 15.0
		o.light_energy = 0.0
		o.shadow_enabled = false
		add_child(o)
		lights.append(o)

# ------------------------------------------------------------------ dealership showroom
func _dealership() -> void:
	var wall := _mat(Color(0.86, 0.87, 0.9), 0.8)
	var dark := _mat(Color(0.12, 0.13, 0.16), 0.5, 0.2)
	var glass := _mat(Color(0.35, 0.6, 0.85, 0.55), 0.1, 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var blue := _mat(Color(0.12, 0.3, 0.9), 0.6, 0.0, 0.6)
	var cz: float = -34.0
	# shell: back + side walls + roof, glass front
	_box(self, Vector3(0, 4.0, cz - 7.0), Vector3(40.0, 8.0, 0.6), wall, true, true)
	_box(self, Vector3(-19.8, 4.0, cz), Vector3(0.6, 8.0, 14.0), wall, true, true)
	_box(self, Vector3(19.8, 4.0, cz), Vector3(0.6, 8.0, 14.0), wall, true, true)
	_box(self, Vector3(0, 8.2, cz), Vector3(41.0, 0.5, 15.0), dark, false, true)
	_box(self, Vector3(0, 0.1, cz), Vector3(39.0, 0.2, 14.0), _mat(Color(0.55, 0.56, 0.6), 0.35, 0.2))
	# glass front with a central door gap (cars and people can approach, nobody walks through the glass)
	_box(self, Vector3(-10.6, 3.2, cz + 7.0), Vector3(17.8, 6.4, 0.2), glass, true)
	_box(self, Vector3(10.6, 3.2, cz + 7.0), Vector3(17.8, 6.4, 0.2), glass, true)
	_box(self, Vector3(0, 7.0, cz + 7.0), Vector3(40.0, 2.0, 0.5), blue, false, true)
	_box(self, Vector3(0, 3.2, cz + 6.9), Vector3(3.2, 6.4, 0.15), glass, false)
	_label("DRIVE BEYOND AUTO", Vector3(0, 7.0, cz + 7.35), 0.0, Color(1, 1, 1), 0.07)
	_label("DEALERSHIP", Vector3(0, 5.2, cz + 7.35), 0.0, Color(0.7, 0.85, 1.0), 0.04)
	# display plinths with parked showroom cars (simple coloured blocks keep the draw calls down)
	for i in range(3):
		var px: float = -12.0 + float(i) * 12.0
		_box(self, Vector3(px, 0.3, cz), Vector3(5.6, 0.2, 3.2), _mat(Color(0.2, 0.22, 0.28), 0.4, 0.3))
		_box(self, Vector3(px, 0.85, cz), Vector3(4.3, 0.7, 1.8), _mat([Color(0.8, 0.1, 0.1), Color(0.9, 0.9, 0.92), Color(0.1, 0.25, 0.7)][i], 0.35, 0.5))
		_box(self, Vector3(px - 0.2, 1.4, cz), Vector3(2.3, 0.55, 1.6), _mat(Color(0.1, 0.12, 0.16), 0.2, 0.3))
	# forecourt sign at the door
	_label("WELCOME", Vector3(0, 0.1, -21.0), 0.0, Color(0.6, 0.8, 1.0, 0.8), 0.04, true)
	_label("VISIT DEALERSHIP", Vector3(0, 0.1, -19.0), 0.0, Color(0.6, 0.8, 1.0, 0.6), 0.025, true)

# ------------------------------------------------------------------ repair workshop
func _workshop() -> void:
	var wall := _mat(Color(0.62, 0.64, 0.68), 0.85)
	var roof := _mat(Color(0.25, 0.26, 0.3), 0.8)
	var door := _mat(Color(0.2, 0.23, 0.3), 0.5, 0.4)
	var orange := _mat(Color(1.0, 0.45, 0.05), 0.6, 0.0, 0.5)
	var wx: float = 32.0
	var wz: float = 34.0
	# back & side walls + roof; front (west face, towards the pad) has two open roller-door bays
	_box(self, Vector3(wx + 7.7, 3.2, wz), Vector3(0.6, 6.4, 18.0), wall, true, true)
	_box(self, Vector3(wx, 3.2, wz - 8.7), Vector3(15.4, 6.4, 0.6), wall, true, true)
	_box(self, Vector3(wx, 3.2, wz + 8.7), Vector3(15.4, 6.4, 0.6), wall, true, true)
	_box(self, Vector3(wx, 6.55, wz), Vector3(16.0, 0.4, 18.6), roof, false, true)
	_box(self, Vector3(wx - 7.7, 5.6, wz), Vector3(0.6, 1.6, 18.0), wall, true)         # lintel over the bays
	_box(self, Vector3(wx - 7.7, 2.2, wz - 8.0), Vector3(0.6, 4.4, 2.0), wall, true)
	_box(self, Vector3(wx - 7.7, 2.2, wz + 8.0), Vector3(0.6, 4.4, 2.0), wall, true)
	_box(self, Vector3(wx - 7.7, 2.2, wz), Vector3(0.6, 4.4, 2.0), wall, true)
	_box(self, Vector3(wx - 7.9, 5.1, wz - 4.0), Vector3(0.3, 0.7, 5.6), door)
	_box(self, Vector3(wx - 7.9, 5.1, wz + 4.0), Vector3(0.3, 0.7, 5.6), door)
	_box(self, Vector3(wx, 0.08, wz), Vector3(15.0, 0.16, 17.0), _mat(Color(0.3, 0.3, 0.32), 0.7))
	# hydraulic lift prop inside each bay
	for dz in [-4.0, 4.0]:
		_box(self, Vector3(wx + 1.0, 0.45, wz + dz), Vector3(4.2, 0.3, 2.4), orange)
	_label("REPAIR  BAY", Vector3(wx - 8.1, 5.15, wz), -PI * 0.5, Color(1.0, 0.7, 0.2), 0.05)
	_label("REPAIRS", Vector3(wx - 6.0, 6.0, wz - 8.95), PI, Color(1.0, 0.7, 0.2), 0.05)

# ------------------------------------------------------------------ shop kiosk + price pylon
func _shop_and_pylon() -> void:
	var wall := _mat(Color(0.9, 0.9, 0.92), 0.8)
	var blue := _mat(Color(0.1, 0.25, 0.8), 0.6, 0.0, 0.5)
	var glass := _mat(Color(0.35, 0.6, 0.85, 0.55), 0.1, 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_box(self, Vector3(-38.0, 2.0, 38.0), Vector3(12.0, 4.0, 8.0), wall, true, true)
	_box(self, Vector3(-38.0, 4.2, 38.0), Vector3(12.6, 0.4, 8.6), blue, false, true)
	_box(self, Vector3(-38.0, 1.8, 33.9), Vector3(9.0, 2.2, 0.15), glass)
	_label("SHOP", Vector3(-38.0, 3.9, 33.8), 0.0, Color(1, 1, 1), 0.05)
	# price pylon at the street corner
	_box(self, Vector3(-45.0, 4.5, 18.0), Vector3(0.7, 9.0, 0.7), _mat(Color(0.2, 0.2, 0.24), 0.5, 0.5), true)
	_box(self, Vector3(-45.0, 8.2, 18.0), Vector3(0.5, 3.0, 4.6), blue)
	_label("DRIVE BEYOND\nFUEL  &  AUTO", Vector3(-45.3, 8.2, 18.0), -PI * 0.5, Color(1, 1, 1), 0.04)
	_label("DRIVE BEYOND\nFUEL  &  AUTO", Vector3(-44.7, 8.2, 18.0), PI * 0.5, Color(1, 1, 1), 0.04)

func _lamps() -> void:
	for p in [Vector3(-30, 0, 4), Vector3(30, 0, 4), Vector3(-30, 0, 46), Vector3(8, 0, 46), Vector3(46, 0, 12), Vector3(-46, 0, -14), Vector3(46, 0, -14)]:
		_box(self, p + Vector3(0, 3.5, 0), Vector3(0.25, 7.0, 0.25), _mat(Color(0.2, 0.2, 0.22), 0.6, 0.4), true)
		_box(self, p + Vector3(0, 7.1, 0), Vector3(0.9, 0.15, 0.5), _mat(Color(1.0, 0.95, 0.8), 0.5, 0.0, 1.4))

var night_on: bool = false

func set_night(on: bool) -> void:
	night_on = on
	for l in lights:
		(l as OmniLight3D).light_energy = 1.5 if on else 0.0
