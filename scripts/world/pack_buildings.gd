class_name PackBuildings
extends RefCounted
## GENERATED from tools/buildings_report.json (tools/extract_buildings.py). Footprints in metres, origin = footprint centre on the ground.

const SIZES := {
	"city_block_a": {"w": 21.17, "h": 23.67, "d": 17.68},
	"city_block_b": {"w": 9.95, "h": 23.24, "d": 13.15},
	"city_block_c": {"w": 10.28, "h": 25.22, "d": 12.99},
	"city_mid_a": {"w": 12.66, "h": 18.73, "d": 10.9},
	"city_mid_b": {"w": 9.6, "h": 18.58, "d": 9.6},
	"city_mid_c": {"w": 8.61, "h": 15.54, "d": 10.54},
	"city_low_a": {"w": 9.9, "h": 10.83, "d": 8.74},
	"city_tower_a": {"w": 12.53, "h": 45.16, "d": 18.55},
	"city_tower_b": {"w": 13.66, "h": 45.92, "d": 17.23},
	"city_tower_c": {"w": 13.19, "h": 28.12, "d": 7.03},
	"city_tower_d": {"w": 10.62, "h": 31.04, "d": 6.65},
	"soviet_panelka": {"w": 13.1, "h": 13.31, "d": 42.74},
	# business + accommodation districts (tools/prepare_world.gd jobs biz / acc -> assets/world/bld/<id>.tscn)
	"biz_restaurant": {"w": 12.36, "h": 5.9, "d": 6.55},
	"biz_shop": {"w": 8.48, "h": 6.07, "d": 5.71},
	"biz_pizza": {"w": 13.87, "h": 7.53, "d": 6.7},
	"biz_burger": {"w": 15.12, "h": 8.58, "d": 9.69},
	"biz_cafe": {"w": 13.83, "h": 6.6, "d": 13.57},
	"biz_mall": {"w": 41.65, "h": 9.92, "d": 20.07},
	"biz_cinema": {"w": 21.23, "h": 12.79, "d": 12.23},
	"acc_1": {"w": 15.19, "h": 22.18, "d": 14.67},
	"acc_2": {"w": 13.95, "h": 20.0, "d": 21.82},
	"acc_3": {"w": 8.09, "h": 7.46, "d": 8.12},
	"acc_4": {"w": 6.45, "h": 7.56, "d": 10.94},
	"acc_5": {"w": 8.1, "h": 5.84, "d": 10.58},
	"acc_6": {"w": 6.04, "h": 7.11, "d": 9.16},
	"acc_7": {"w": 7.12, "h": 6.79, "d": 10.54},
	"acc_8": {"w": 12.03, "h": 14.79, "d": 11.39},
	"acc_9": {"w": 7.72, "h": 14.05, "d": 13.65},
	"acc_10": {"w": 9.26, "h": 12.14, "d": 16.13},
}

const PATH := "res://assets/buildings/pack/%s.glb"

const PATH_WORLD := "res://assets/world/bld/%s.tscn"

## scene path of a pack building (old pack = .glb under assets/buildings/pack, district buildings = baked .tscn)
static func path_of(id: String) -> String:
	return PATH_WORLD % id if id.begins_with("biz_") or id.begins_with("acc_") else PATH % id
