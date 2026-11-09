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
}

const PATH := "res://assets/buildings/pack/%s.glb"
