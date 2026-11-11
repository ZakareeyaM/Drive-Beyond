class_name FaunaManager
extends Node
## Dogs and birds.
##  Dogs  (dog.glb, one static mesh without skeleton or animation -> decimated to ~1.5k tris and animated by a small vertex shader:
##        trotting legs, body bob and tail wag): idle -> choose a destination -> walk -> pause, with varied timing.  They roam the
##        sidewalks of residential roads (suburbs, resort district, business district) and the airport plaza.
##  Birds (birds.glb, 5 skinned birds with a 0.667 s flap loop -> baked to 6 wing poses per bird): circle and glide over the city,
##        open land and the airport at heights that clear the buildings, bank into turns, flap, and are recycled when far away.
## Counts are configurable per quality level and the same frame-rate monitor as the pedestrians scales them down on slow devices.

const DOG_MAX := {"Low": 1, "Medium": 2, "High": 3, "Ultra": 4}
const BIRD_MAX := {"Low": 5, "Medium": 8, "High": 12, "Ultra": 16}
const DOG_DESPAWN := 150.0
const BIRD_DESPAWN := 520.0
const BIRD_FRAMES := 6
const BIRD_CYCLE := 0.6667

const DOG_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float moving = 0.0;
uniform float phase = 0.0;
uniform float wag = 1.0;
void vertex() {
	float legw = smoothstep(0.26, 0.0, VERTEX.y);
	float side = VERTEX.x >= 0.0 ? 1.0 : -1.0;
	float fore = VERTEX.z >= 0.0 ? 1.0 : -1.0;
	float ph = phase + (side * fore > 0.0 ? 0.0 : 3.14159);
	VERTEX.z += sin(ph) * 0.075 * legw * moving;
	VERTEX.y += max(0.0, cos(ph)) * 0.035 * legw * moving;
	float tail = smoothstep(0.25, 0.42, -VERTEX.z) * smoothstep(0.15, 0.3, VERTEX.y);
	VERTEX.x += sin(phase * 1.7 + 1.0) * 0.045 * tail * wag;
	VERTEX.y += sin(phase * 2.0) * 0.008 * moving;
}
void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb;
	ROUGHNESS = 1.0;
}
"""

var world: World
var dogs: Array = []
var birds: Array = []
var bird_frames: Array = []     # [variant][frame] -> ArrayMesh
var dog_mesh: Mesh = null
var dog_shader: Shader = null
var limit_scale: float = 1.0
var fps_lo_t: float = 0.0
var fps_hi_t: float = 0.0
var spawn_t: float = 1.0
var bird_t: float = 0.0

func _quality() -> String:
	return String(Game.settings.get("quality", "Medium"))

func _dog_limit() -> int:
	return maxi(1, int(round(float(DOG_MAX.get(_quality(), 2)) * limit_scale)))

func _bird_limit() -> int:
	return maxi(3, int(round(float(BIRD_MAX.get(_quality(), 8)) * limit_scale)))

func clear() -> void:
	for d in dogs:
		(d["node"] as Node).queue_free()
	for b in birds:
		(b["node"] as Node).queue_free()
	dogs.clear()
	birds.clear()

func _ready() -> void:
	dog_shader = Shader.new()
	dog_shader.code = DOG_SHADER

func _load_birds() -> void:
	if not bird_frames.is_empty():
		return
	for v in range(5):
		var am: ArrayMesh = load("res://assets/world/people/bird_%d.res" % v) as ArrayMesh
		var fr: Array = []
		for f in range(am.get_surface_count()):
			var fm := ArrayMesh.new()
			fm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, am.surface_get_arrays(f))
			var m: Material = am.surface_get_material(f)
			var tinted: StandardMaterial3D = (m.duplicate() as StandardMaterial3D) if m is StandardMaterial3D else StandardMaterial3D.new()
			tinted.albedo_color = [Color(0.16, 0.16, 0.18), Color(0.55, 0.55, 0.58), Color(0.35, 0.3, 0.25), Color(0.85, 0.85, 0.88), Color(0.22, 0.2, 0.3)][v]
			tinted.cull_mode = BaseMaterial3D.CULL_DISABLED
			fm.surface_set_material(0, tinted)
			fr.append(fm)
		bird_frames.append(fr)

func _physics_process(dt: float) -> void:
	if not world.running or world.mode == "menu":
		return
	_monitor(dt)
	var pp: Vector3 = world.player_pos()
	spawn_t -= dt
	if spawn_t <= 0.0:
		spawn_t = 1.5
		if dogs.size() < _dog_limit():
			_spawn_dog(pp)
		if birds.size() < _bird_limit():
			_spawn_bird(pp)
	_update_dogs(dt, pp)
	_update_birds(dt, pp)

func _monitor(dt: float) -> void:
	var fps: float = Engine.get_frames_per_second()
	if fps < 22.0:
		fps_lo_t += dt
		fps_hi_t = 0.0
		if fps_lo_t > 3.0 and limit_scale > 0.4:
			limit_scale = maxf(0.4, limit_scale - 0.2)
			fps_lo_t = 0.0
	elif fps > 45.0:
		fps_hi_t += dt
		fps_lo_t = 0.0
		if fps_hi_t > 8.0 and limit_scale < 1.0:
			limit_scale = minf(1.0, limit_scale + 0.2)
			fps_hi_t = 0.0

# ------------------------------------------------------------------------------------------------------------------- dogs
func _spawn_dog(pp: Vector3) -> void:
	var pick: Array = world.traffic._pick_edge_near(pp, 25.0, 100.0)
	if pick.is_empty():
		return
	var e: Dictionary = world.gen.edges[pick[0]]
	var kind: String = String(e["kind"])
	var cum: PackedFloat32Array = e["cum"]
	var smp: Array = world.traffic._edge_sample(e, cum[pick[1]])
	var p3: Vector3 = smp[0]
	# residential / quiet places only: suburbs, the new districts, the airport plaza, never the busy highways
	var zone: String = WorldExpansion.zone_at(p3.x, p3.z)
	if not (kind in ["suburb", "street"] or zone != ""):
		return
	if not bool(WorldGen.KINDS[kind].get("side", false)):
		return
	if dog_mesh == null:
		dog_mesh = load("res://assets/world/people/dog.res") as Mesh
	var mi := MeshInstance3D.new()
	mi.mesh = dog_mesh
	var sm := ShaderMaterial.new()
	sm.shader = dog_shader
	var src: Material = dog_mesh.surface_get_material(0)
	if src is BaseMaterial3D:
		sm.set_shader_parameter("albedo_tex", (src as BaseMaterial3D).albedo_texture)
	mi.material_override = sm
	mi.scale = Vector3.ONE * randf_range(0.9, 1.25)
	mi.rotation.y = PI                    # the dog model's nose is +Z; the walker logic faces -Z
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 120.0
	var root := Node3D.new()
	root.add_child(mi)
	world.add_child(root)
	var d := {"node": root, "mat": sm, "edge": pick[0], "s": cum[pick[1]], "dir": 1 if randf() < 0.5 else -1,
		"off": (1.0 if randf() < 0.5 else -1.0) * (float(e["width"]) * 0.5 + 2.2), "state": "idle", "t": randf_range(1.0, 4.0),
		"speed": randf_range(0.9, 1.8), "gait": randf() * 6.0, "goal": 0.0}
	dogs.append(d)
	_place_dog(d)

func _place_dog(d: Dictionary) -> void:
	var e: Dictionary = world.gen.edges[d["edge"]]
	var smp: Array = world.traffic._edge_sample(e, float(d["s"]))
	var pos: Vector3 = smp[0]
	var tan: Vector3 = smp[1]
	var right := Vector3(-tan.z, 0, tan.x)
	var n: Node3D = d["node"]
	var tgt: Vector3 = pos + right * float(d["off"])
	n.global_position = Vector3(tgt.x, world.gen.ground_h(tgt.x, tgt.z) + 0.02, tgt.z)
	var yaw: float = atan2(-tan.x * float(d["dir"]), -tan.z * float(d["dir"]))
	n.rotation.y = lerp_angle(n.rotation.y, yaw, 0.2)

## idle -> pick destination (a stretch of sidewalk 6-25 m away) -> walk (or trot) -> pause, forever
func _update_dogs(dt: float, pp: Vector3) -> void:
	for d in dogs.duplicate():
		var n: Node3D = d["node"]
		var dist: float = n.global_position.distance_to(pp)
		if dist > DOG_DESPAWN:
			dogs.erase(d)
			n.queue_free()
			continue
		if dist > 90.0:
			continue                           # simplified tier: frozen while far, resumes when the player is near again
		var sm: ShaderMaterial = d["mat"]
		if d["state"] == "idle":
			d["t"] = float(d["t"]) - dt
			sm.set_shader_parameter("moving", 0.0)
			sm.set_shader_parameter("phase", float(d["gait"]))
			d["gait"] = float(d["gait"]) + dt * 1.2     # tail keeps wagging
			if float(d["t"]) <= 0.0:
				var e: Dictionary = world.gen.edges[d["edge"]]
				d["dir"] = 1 if randf() < 0.5 else -1
				var goal: float = float(d["s"]) + float(d["dir"]) * randf_range(6.0, 25.0)
				if goal < 2.0 or goal > float(e["len"]) - 2.0:
					d["dir"] = -int(d["dir"])
					goal = clampf(float(d["s"]) + float(d["dir"]) * randf_range(6.0, 25.0), 2.0, float(e["len"]) - 2.0)
				d["goal"] = goal
				d["speed"] = randf_range(0.9, 2.4)
				d["state"] = "walk"
		else:
			d["s"] = float(d["s"]) + float(d["dir"]) * float(d["speed"]) * dt
			d["gait"] = float(d["gait"]) + dt * (4.0 + float(d["speed"]) * 4.2)
			sm.set_shader_parameter("moving", 1.0)
			sm.set_shader_parameter("phase", float(d["gait"]))
			if (int(d["dir"]) > 0 and float(d["s"]) >= float(d["goal"])) or (int(d["dir"]) < 0 and float(d["s"]) <= float(d["goal"])):
				d["state"] = "idle"
				d["t"] = randf_range(2.0, 8.0)         # sniff around / sit for a while
			_place_dog(d)

# ------------------------------------------------------------------------------------------------------------------- birds
func _spawn_bird(pp: Vector3) -> void:
	_load_birds()
	# pick a circling centre 120-420 m from the player: over the airport 30%, over the city 30%, open land otherwise
	var c := Vector2.ZERO
	var roll: float = randf()
	if roll < 0.3 and pp.distance_to(Vector3(2000.0, pp.y, 500.0)) < 900.0:
		c = Vector2(randf_range(1850.0, 2200.0), randf_range(150.0, 900.0))
	else:
		var a: float = randf() * TAU
		var r: float = randf_range(120.0, 420.0)
		c = Vector2(pp.x + cos(a) * r, pp.z + sin(a) * r)
	var lim: float = WorldGen.HALF - 60.0
	c = Vector2(clampf(c.x, -lim, lim), clampf(c.y, -lim, lim))
	var gh: float = world.gen.ground_h(c.x, c.y)
	if gh < -2.0:
		gh = 0.0                                  # over water: fly above sea level
	var over_city: bool = Vector2(c.x, c.y).length() < 560.0 and absf(c.x) < 560.0 and absf(c.y) < 560.0
	var h: float = gh + (randf_range(110.0, 170.0) if over_city else randf_range(28.0, 70.0))   # clears the tallest towers
	var v: int = randi() % 5
	var mi := MeshInstance3D.new()
	mi.mesh = bird_frames[v][0]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 380.0
	world.add_child(mi)
	mi.global_position = Vector3(c.x, h, c.y)   # placed before the first update so the despawn distance test is valid
	var b := {"node": mi, "var": v, "c": c, "r": randf_range(35.0, 110.0), "ang": randf() * TAU, "h": h, "gh": gh,
		"w": randf_range(0.18, 0.34) * (1.0 if randf() < 0.5 else -1.0), "fp": randf() * BIRD_CYCLE, "frame": 0, "bob": randf() * 6.0,
		"glide": 0.0, "roll": 0.0, "drift": Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(0.5, 3.0)}
	birds.append(b)

func _update_birds(dt: float, pp: Vector3) -> void:
	for b in birds.duplicate():
		var n: MeshInstance3D = b["node"]
		var dist: float = Vector2(n.global_position.x - pp.x, n.global_position.z - pp.z).length()
		if dist > BIRD_DESPAWN:
			birds.erase(b)
			n.queue_free()
			continue
		# gentle direction changes: the angular speed drifts slowly, the circle centre wanders
		var wv: float = clampf(float(b["w"]) + randf_range(-0.03, 0.03) * dt, -0.4, 0.4)
		if absf(wv) < 0.12:
			wv = 0.12 * signf(wv if wv != 0.0 else 1.0)
		b["w"] = wv
		b["ang"] = float(b["ang"]) + float(b["w"]) * dt
		b["c"] = (b["c"] as Vector2) + (b["drift"] as Vector2) * dt
		b["bob"] = float(b["bob"]) + dt * 0.7
		var c: Vector2 = b["c"]
		var r: float = float(b["r"])
		var pos := Vector3(c.x + cos(float(b["ang"])) * r, 0.0, c.y + sin(float(b["ang"])) * r)
		pos.y = float(b["h"]) + sin(float(b["bob"])) * 4.0
		var prev: Vector3 = n.global_position
		n.global_position = pos
		var vel: Vector3 = pos - prev
		if vel.length() > 0.001 and prev != Vector3.ZERO:
			var yaw: float = atan2(-vel.x, -vel.z)
			n.rotation.y = lerp_angle(n.rotation.y, yaw, clampf(dt * 3.0, 0.0, 1.0))
		var bank: float = clampf(-float(b["w"]) * 2.2, -0.5, 0.5)
		b["roll"] = lerpf(float(b["roll"]), bank, clampf(dt * 2.0, 0.0, 1.0))
		n.rotation.z = float(b["roll"])
		# flap, with occasional glides (wings held in the first pose)
		b["glide"] = float(b["glide"]) - dt
		if float(b["glide"]) < -randf_range(4.0, 9.0):
			b["glide"] = randf_range(1.0, 2.5)
		var f: int = 0
		if float(b["glide"]) <= 0.0:
			b["fp"] = fposmod(float(b["fp"]) + dt, BIRD_CYCLE)
			f = int(float(b["fp"]) / BIRD_CYCLE * float(BIRD_FRAMES)) % BIRD_FRAMES
		if f != int(b["frame"]):
			b["frame"] = f
			n.mesh = bird_frames[int(b["var"])][f]
