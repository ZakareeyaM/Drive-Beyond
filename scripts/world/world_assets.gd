class_name WorldAssets
extends RefCounted
## Shared meshes + materials for the streamed world.

static func shader_mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m

static func plain(rough: float = 0.9, double_sided: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic_specular = 0.25
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

static func create() -> Dictionary:
	var a: Dictionary = {}
	a["mat_terrain"] = shader_mat("res://shaders/terrain.gdshader")
	a["mat_road"] = shader_mat("res://shaders/road.gdshader")
	a["mat_plain"] = plain()
	a["mesh_bld"] = MeshLib.unit_box()
	a["mat_bld"] = shader_mat("res://shaders/building.gdshader")
	a["mesh_roof"] = MeshLib.roof_prism()
	a["mat_roof"] = a["mat_plain"]
	a["mesh_struct"] = MeshLib.unit_box()
	a["mat_struct"] = a["mat_plain"]
	# every tree uses the one shared stylized palm mesh (assets/world/palm.res); the old procedural trees remain only as fallback
	var palm: Mesh = load("res://assets/world/palm.res") as Mesh
	a["mesh_pine"] = palm if palm != null else MeshLib.pine_tree()
	a["mesh_oak"] = palm if palm != null else MeshLib.oak_tree()
	a["mesh_palm"] = palm if palm != null else MeshLib.palm_tree()
	a["mesh_cactus"] = MeshLib.cactus()
	a["mesh_rock"] = MeshLib.rock()
	var veg: StandardMaterial3D = plain(0.95, true)
	a["mat_pine"] = veg
	a["mat_oak"] = veg
	a["mat_palm"] = veg
	a["mat_cactus"] = veg
	a["mat_rock"] = plain(0.98)
	a["mesh_lamp"] = MeshLib.street_lamp()
	var lamp_mat: StandardMaterial3D = plain(0.5)
	lamp_mat.metallic = 0.3
	a["mat_lamp"] = lamp_mat
	a["mesh_pool"] = MeshLib.glow_quad(22.0)
	a["mat_pool"] = shader_mat("res://shaders/glow.gdshader")
	return a
