extends Node
func _ready() -> void:
	for vid in ["pico_h1", "strada_s2", "titan_x", "hauler_r", "brawler_69", "vela_gt", "dune_runner", "kestrel_r", "bmw_m6", "kia_ceed"]:
		var c: Dictionary = Data.default_custom(vid)
		var t0: int = Time.get_ticks_usec()
		var m: Dictionary = CarBuilder.build(vid, c)
		var t1: int = Time.get_ticks_usec()
		var m2: Dictionary = CarBuilder.build(vid, c)
		var t2: int = Time.get_ticks_usec()
		print("BUILD %s first=%.1f ms second=%.1f ms" % [vid, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
	get_tree().quit()
