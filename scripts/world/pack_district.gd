class_name PackDistrict
extends Node3D
## Visual side of the building-pack expansion: one scene instance per placed building (kind "pack" in
## WorldGen.buildings; the colliders come from the streamed chunks).  Meshes/materials are shared between
## instances, shadows are off and everything fades out by distance (visibility_range) to keep draw calls low.

const VIS_END := 420.0
var cache: Dictionary = {}
var count: int = 0

func build(gen: WorldGen) -> void:
	for k in gen.buildings:
		for b in gen.buildings[k]:
			if String(b["kind"]) != "pack":
				continue
			_place(String(b["pack"]), b["p"], float(b.get("yaw", 0.0)))

func _place(id: String, p: Vector3, yaw: float) -> void:
	if not cache.has(id):
		cache[id] = load(PackBuildings.PATH % id) as PackedScene
	var ps: PackedScene = cache[id]
	if ps == null:
		push_error("PackDistrict: missing building " + id)
		return
	var n: Node3D = ps.instantiate() as Node3D
	n.position = p - Vector3(0, 0.3, 0)
	n.rotation.y = yaw
	add_child(n)
	for gi in n.find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.visibility_range_end = VIS_END
		g.visibility_range_end_margin = 30.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	count += 1
