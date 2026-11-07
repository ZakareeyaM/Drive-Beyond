class_name TerrainStreamer
extends Node3D
## Streams 128 m chunks around a focus point. Chunk data is generated on worker
## threads, nodes are created on the main thread (max a couple per frame).

signal chunk_loaded(cx: int, cz: int)

var world: WorldGen
var assets: Dictionary
var quality: Dictionary = {"detail_range": 500.0, "tree_range": 300.0, "tree_shadows": false}
var radius: int = 3
var chunks: Dictionary = {}
var pending: Dictionary = {}
var finished: Array = []
var mutex := Mutex.new()
var max_inflight: int = 2
var builds_per_frame: int = 1
var focus: Vector3 = Vector3.ZERO
var _last_center: Vector2i = Vector2i(-999, -999)
var _timer: float = 0.0

func setup(w: WorldGen, a: Dictionary) -> void:
	world = w
	assets = a

func set_radius(r: int) -> void:
	radius = r
	var vr: float = float(r) * WorldGen.CHUNK
	quality["detail_range"] = vr + 150.0
	quality["tree_range"] = clampf(vr * 0.8, 200.0, 420.0)
	_last_center = Vector2i(-999, -999)

func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.15
		_request()
	_collect()

func _wanted(center: Vector2i) -> Array:
	var list: Array = []
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dz * dz > radius * radius + 1:
				continue
			var cx: int = center.x + dx
			var cz: int = center.y + dz
			if cx < 0 or cz < 0 or cx >= WorldGen.CHUNKS or cz >= WorldGen.CHUNKS:
				continue
			list.append([dx * dx + dz * dz, cx, cz])
	list.sort_custom(func(a, b): return a[0] < b[0])
	return list

func _request() -> void:
	var c: Vector2i = world.chunk_of(focus.x, focus.z)
	var list: Array = _wanted(c)
	var want_keys: Dictionary = {}
	for it in list:
		want_keys[world.key(it[1], it[2])] = true
	# unload far chunks
	var drop: Array = []
	for k in chunks:
		var node: Node3D = chunks[k]
		var cx: int = int(k) / 1000
		var cz: int = int(k) % 1000
		if (cx - c.x) * (cx - c.x) + (cz - c.y) * (cz - c.y) > (radius + 1) * (radius + 1) + 2:
			drop.append(k)
	for k in drop:
		(chunks[k] as Node3D).queue_free()
		chunks.erase(k)
	# request missing in priority order
	for it in list:
		if pending.size() >= max_inflight:
			break
		var k: int = world.key(it[1], it[2])
		if chunks.has(k) or pending.has(k):
			continue
		pending[k] = true
		var cx2: int = it[1]
		var cz2: int = it[2]
		WorkerThreadPool.add_task(_work.bind(cx2, cz2))

func _work(cx: int, cz: int) -> void:
	var d: Dictionary = ChunkBuilder.build(world, cx, cz)
	mutex.lock()
	finished.append(d)
	mutex.unlock()

func _collect() -> void:
	var n: int = 0
	while n < builds_per_frame:
		mutex.lock()
		var d: Dictionary = {}
		if finished.size() > 0:
			d = finished.pop_front()
		mutex.unlock()
		if d.is_empty():
			return
		var k: int = world.key(d["cx"], d["cz"])
		pending.erase(k)
		var c: Vector2i = world.chunk_of(focus.x, focus.z)
		var cx: int = d["cx"]
		var cz: int = d["cz"]
		if (cx - c.x) * (cx - c.x) + (cz - c.y) * (cz - c.y) > (radius + 1) * (radius + 1) + 2 or chunks.has(k):
			n += 1
			continue
		var node: Node3D = ChunkBuilder.instantiate(d, assets, quality)
		add_child(node)
		chunks[k] = node
		chunk_loaded.emit(cx, cz)
		n += 1

func loaded_at(p: Vector3) -> bool:
	var c: Vector2i = world.chunk_of(p.x, p.z)
	return chunks.has(world.key(c.x, c.y))

func loaded_ring(p: Vector3, r: int) -> bool:
	var c: Vector2i = world.chunk_of(p.x, p.z)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cx: int = c.x + dx
			var cz: int = c.y + dz
			if cx < 0 or cz < 0 or cx >= WorldGen.CHUNKS or cz >= WorldGen.CHUNKS:
				continue
			if not chunks.has(world.key(cx, cz)):
				return false
	return true

func loading_fraction(p: Vector3) -> float:
	var c: Vector2i = world.chunk_of(p.x, p.z)
	var need: int = 0
	var have: int = 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var cx: int = c.x + dx
			var cz: int = c.y + dz
			if cx < 0 or cz < 0 or cx >= WorldGen.CHUNKS or cz >= WorldGen.CHUNKS:
				continue
			need += 1
			if chunks.has(world.key(cx, cz)):
				have += 1
	return float(have) / float(maxi(need, 1))
