class_name PedManager
extends Node
## Lightweight pedestrians that walk along city sidewalks. Kinematic, no physics
## bodies; they dive away / fall when the player's car hits them.

var world: World
var peds: Array = []        # {node, edge, s, dir, off, speed, state, t, legs}
var spawn_t: float = 0.0
var mat_cache: Array = []

func clear() -> void:
	for p in peds:
		(p["node"] as Node).queue_free()
	peds.clear()

func _max() -> int:
	match String(Game.settings.get("quality", "Medium")):
		"Low": return 6
		"Medium": return 10
		"High": return 16
	return 22

func _make_visual() -> Dictionary:
	if mat_cache.is_empty():
		for c in [Color(0.8, 0.2, 0.2), Color(0.2, 0.3, 0.7), Color(0.15, 0.5, 0.3), Color(0.8, 0.7, 0.2), Color(0.3, 0.3, 0.35), Color(0.7, 0.4, 0.7), Color(0.9, 0.9, 0.9)]:
			var m := StandardMaterial3D.new()
			m.albedo_color = c
			m.roughness = 0.8
			mat_cache.append(m)
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.45, 0.65, 0.25)
	body.mesh = b
	body.material_override = mat_cache[randi() % mat_cache.size()]
	body.position.y = 1.18
	root.add_child(body)
	var head := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.12
	s.height = 0.24
	s.radial_segments = 8
	s.rings = 4
	head.mesh = s
	var sk := StandardMaterial3D.new()
	sk.albedo_color = [Color(0.85, 0.65, 0.5), Color(0.55, 0.38, 0.28), Color(0.35, 0.24, 0.18)][randi() % 3]
	head.material_override = sk
	head.position.y = 1.64
	root.add_child(head)
	var legs: Array = []
	for sx in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(sx * 0.12, 0.86, 0)
		var lm := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.16, 0.84, 0.18)
		lm.mesh = lb
		lm.position.y = -0.42
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.12, 0.13, 0.18)
		lm.material_override = pm
		leg.add_child(lm)
		root.add_child(leg)
		legs.append(leg)
	return {"root": root, "legs": legs}

func _physics_process(dt: float) -> void:
	if not world.running or world.mode == "menu":
		return
	var pp: Vector3 = world.player_pos()
	var in_city: bool = world.gen.region_at(pp.x, pp.z) in ["city", "suburb", "coast"]
	spawn_t -= dt
	if spawn_t <= 0.0 and peds.size() < _max() and in_city:
		spawn_t = 0.6
		_spawn(pp)
	var car: Vehicle = world.player_car if world.mode == "drive" else null
	for p in peds.duplicate():
		var n: Node3D = p["node"]
		if n.global_position.distance_to(pp) > 150.0:
			peds.erase(p)
			n.queue_free()
			continue
		if p["state"] == "walk":
			_walk(p, dt)
			if car and car.abs_speed > 3.0:
				var d: Vector3 = n.global_position - car.global_position
				d.y = 0.0
				if d.length() < 1.9 + float(car.spec["W"]) * 0.4 and absf(n.global_position.y - car.global_position.y) < 2.0:
					_hit(p, car)
		else:
			p["t"] += dt
			var k: float = clampf(float(p["t"]) * 3.0, 0.0, 1.0)
			n.rotation.x = lerpf(0.0, -PI * 0.5, k)
			n.position += (p["vel"] as Vector3) * dt
			p["vel"] = (p["vel"] as Vector3) * maxf(0.0, 1.0 - dt * 3.0)
			if p["t"] > 12.0:
				peds.erase(p)
				n.queue_free()

func _spawn(pp: Vector3) -> void:
	var pick: Array = world.traffic._pick_edge_near(pp, 20.0, 90.0)
	if pick.is_empty():
		return
	var e: Dictionary = world.gen.edges[pick[0]]
	if not bool(WorldGen.KINDS[e["kind"]].get("side", false)):
		return
	var vis: Dictionary = _make_visual()
	var n: Node3D = vis["root"]
	world.add_child(n)
	var cum: PackedFloat32Array = e["cum"]
	var side: float = 1.0 if randf() < 0.5 else -1.0
	var p: Dictionary = {"node": n, "edge": pick[0], "s": cum[pick[1]], "dir": 1 if randf() < 0.5 else -1,
		"off": side * (float(e["width"]) * 0.5 + 1.6), "speed": randf_range(1.0, 1.7), "state": "walk", "t": 0.0, "legs": vis["legs"], "ph": randf() * 6.0, "vel": Vector3.ZERO}
	peds.append(p)
	_place(p)

func _place(p: Dictionary) -> void:
	var e: Dictionary = world.gen.edges[p["edge"]]
	var smp: Array = world.traffic._edge_sample(e, float(p["s"]))
	var pos: Vector3 = smp[0]
	var tan: Vector3 = smp[1]
	var right := Vector3(-tan.z, 0, tan.x)
	var n: Node3D = p["node"]
	n.global_position = pos + right * float(p["off"])
	n.rotation.y = atan2(-tan.x * float(p["dir"]), -tan.z * float(p["dir"]))

func _walk(p: Dictionary, dt: float) -> void:
	var e: Dictionary = world.gen.edges[p["edge"]]
	p["s"] = float(p["s"]) + float(p["dir"]) * float(p["speed"]) * dt
	if float(p["s"]) < 1.0 or float(p["s"]) > float(e["len"]) - 1.0:
		p["dir"] = -int(p["dir"])
		p["s"] = clampf(float(p["s"]), 1.0, float(e["len"]) - 1.0)
	_place(p)
	p["ph"] = float(p["ph"]) + dt * float(p["speed"]) * 5.0
	var l: Array = p["legs"]
	(l[0] as Node3D).rotation.x = sin(float(p["ph"])) * 0.6
	(l[1] as Node3D).rotation.x = -sin(float(p["ph"])) * 0.6

func _hit(p: Dictionary, car: Vehicle) -> void:
	p["state"] = "hit"
	p["t"] = 0.0
	p["vel"] = car.linear_velocity * 0.6 + Vector3(0, 0.0, 0)
	world.police.report_crime(0.7, "Hit a pedestrian")
	Game.notify.emit("Watch the pedestrians!", "warn")
	world.audio.play_crash(0.2)
