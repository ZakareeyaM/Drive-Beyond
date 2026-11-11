class_name Airport
extends Node3D
## Visual + collision side of the airport (district D of WorldExpansion).  Everything comes from airport_pack_total.glb, converted by
## tools/prepare_world.gd (assets/world/airport/*.tscn + *_col.res, positions in AirportData): runway tiles, terminal modules, control
## tower, hangar, parked airliners, jet bridges, stairs and the apron vehicles keep the relative layout of the pack.  Added here:
## concrete apron / plaza slabs, the parking lot with painted stalls and the free airport shuttle cart parked in front of the terminal.

const ITEM_PATH := "res://assets/world/airport/%s.tscn"
const SHAPE_PATH := "res://assets/world/airport/%s_col.res"
const CAR_ID := "airport_car"
const VIS_BIG := 900.0
const VIS_SMALL := 380.0
const SMALL := ["stairs", "firetruck", "bus", "baggage_1", "baggage_2", "baggage_3", "container_1", "container_2", "container_3", "container_4", "container_5", "jetbridge"]

var car_prop: Node3D = null
var car_spot := Vector3.ZERO
var car_yaw: float = 0.0
var solid: StaticBody3D
var cache: Dictionary = {}
var count: int = 0

func build() -> void:
	name = "Airport"
	solid = StaticBody3D.new()
	solid.collision_layer = 1
	solid.add_to_group("structure")
	add_child(solid)
	var H: float = WorldExpansion.H
	for id in AirportData.ITEMS:
		var it: Dictionary = AirportData.ITEMS[id]
		if id == "runway":
			for k in range(3):
				var wp: Vector3 = WorldExpansion.airport_world(Vector3(WorldExpansion.RUNWAY_X, 0.0, WorldExpansion.RUNWAY_Z0 + float(k - 1) * WorldExpansion.TILE))
				wp.y = H
				_place("runway", wp, 0.0, VIS_BIG * 1.4)
			continue
		var p: Vector3 = WorldExpansion.airport_world(it["pos"])
		p.y = H + float((it["pos"] as Vector3).y)
		_place(id, p, 0.0, VIS_SMALL if SMALL.has(id) else VIS_BIG)
		if bool(it["shape"]):
			var shp: Shape3D = load(SHAPE_PATH % id) as Shape3D
			if shp != null:
				var cs := CollisionShape3D.new()
				cs.shape = shp
				cs.position = p + (it["shape_off"] as Vector3)
				solid.add_child(cs)
	_slab("apron", Vector3(WorldExpansion.AX - 25.0, H, WorldExpansion.AZ + 15.0), Vector2(250.0, 380.0), Color(0.55, 0.55, 0.56), 0.02)
	_slab("plaza", Vector3(1884.0, H, 520.0), Vector2(26.0, 380.0), Color(0.62, 0.61, 0.58), 0.02)
	_parking()
	# the free shuttle cart, parked in front of the terminal
	var cp: Vector3 = WorldExpansion.airport_world(Vector3(-128.0, 0.0, 40.0))
	car_spot = Vector3(cp.x, H + 0.15, cp.z)
	car_yaw = 0.0

func _place(id: String, p: Vector3, yaw: float, vis: float) -> void:
	if not cache.has(id):
		cache[id] = load(ITEM_PATH % id) as PackedScene
	var ps: PackedScene = cache[id]
	if ps == null:
		push_error("Airport: missing " + id)
		return
	var n: Node3D = ps.instantiate() as Node3D
	n.position = p
	n.rotation.y = yaw
	add_child(n)
	for gi in n.find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.visibility_range_end = vis
		g.visibility_range_end_margin = 40.0
	count += 1

func _slab(nm: String, c: Vector3, size: Vector2, col: Color, top: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, 0.3, size.y)
	mi.mesh = bm
	mi.position = Vector3(c.x, c.y + top - 0.15, c.z)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = VIS_BIG * 1.4
	add_child(mi)

func _parking() -> void:
	var H: float = WorldExpansion.H
	var c: Vector3 = WorldExpansion.PARK_C
	_slab("parking", Vector3(c.x, H, c.z), WorldExpansion.PARK_S, Color(0.2, 0.2, 0.22), 0.025)
	# painted stalls: 4 rows (two aisles x 2 sides), stalls 2.7 m wide, 5.5 m deep, skipping the access street at z = 612
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(5.5, 0.02, 0.12)
	mm.mesh = bm
	var tf: Array = []
	for row_x in [1761.25, 1774.75, 1805.25, 1818.75]:
		var z: float = c.z - WorldExpansion.PARK_S.y * 0.5 + 6.0
		while z < c.z + WorldExpansion.PARK_S.y * 0.5 - 4.0:
			if absf(z - c.z) > 8.0:
				tf.append(Transform3D(Basis.IDENTITY, Vector3(row_x, H + 0.045, z)))
			z += 2.7
	mm.instance_count = tf.size()
	for i in range(tf.size()):
		mm.set_instance_transform(i, tf[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.9, 0.9)
	m.roughness = 1.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 260.0
	add_child(mi)

## parked shuttle cart (display copy: the real vehicle is spawned by World.take_airport_car)
func ensure_car_prop() -> void:
	if car_prop != null:
		return
	var vid: String = CAR_ID
	var spec: Dictionary = Data.vehicle(vid)
	var m: Dictionary = CarBuilder.build(vid, Data.default_custom(vid))
	var root: Node3D = m["root"]
	var holder := Node3D.new()
	holder.name = "AirportCarProp"
	holder.add_child(root)
	for fz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			var wv: MeshInstance3D = CarBuilder.make_wheel_visual(m, vid, Data.default_custom(vid), (2 if fz > 0.0 else 0) + (1 if sx > 0.0 else 0))
			wv.position = Vector3(sx * float(spec["track"]) * 0.5, float(spec["wr"]), fz * float(spec["wb"]) * 0.5)
			root.add_child(wv)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(float(spec["W"]) * 0.95, float(spec["roof"]) - 0.2, float(spec["L"]) * 0.95)
	cs.shape = bs
	cs.position = Vector3(0, 0.15 + bs.size.y * 0.5, 0)
	body.add_child(cs)
	body.name = "Body"
	holder.add_child(body)
	holder.position = Vector3(car_spot.x, car_spot.y - 0.15, car_spot.z)
	holder.rotation.y = car_yaw
	add_child(holder)
	car_prop = holder

func set_car_available(on: bool) -> void:
	ensure_car_prop()
	if car_prop.visible == on:
		return
	car_prop.visible = on
	var body: StaticBody3D = car_prop.get_node("Body") as StaticBody3D
	for c in body.get_children():
		(c as CollisionShape3D).set_deferred("disabled", not on)
