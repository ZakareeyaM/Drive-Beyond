extends Node
## Save migration: a save that owns retired cars (pico_h1 selected) loads with the BMW selected, retired cars removed + refunded.
func _ready() -> void:
	Game.reset_progress()
	Game.owned["pico_h1"] = Game.new_vehicle_record("pico_h1")
	Game.owned["kia_ceed"] = Game.new_vehicle_record("kia_ceed")
	Game.owned["countach"] = Game.new_vehicle_record("countach")
	Game.owned.erase("bmw_m6")
	Game.selected = "pico_h1"
	Game.money = 1000
	Game.save_game()
	var ok: bool = Game.load_game()
	print("MIGRATE loaded=", ok, " owned=", Game.owned.keys(), " selected=", Game.selected, " money=", Game.money, " refund=", Game.retired_refund)
	var pass_ := ok and Game.owned.has("bmw_m6") and Game.owned.has("countach") and not Game.owned.has("pico_h1") and not Game.owned.has("kia_ceed") and Data.in_collection(Game.selected) and Game.owned.has(Game.selected) and Game.money > 1000
	print("MIGRATE ", "PASS" if pass_ else "FAIL")
	print("COLLECTION ", Data.vehicle_ids())
	var bad := 0
	for vid in Data.vehicle_ids():
		if Data.vehicle(vid)["id"] != vid or not ResourceLoader.exists("res://assets/vehicles/fleet/%s.glb" % vid if vid != "bmw_m6" else "res://assets/vehicles/bmw_m6_1988_custom.glb"):
			bad += 1
	print("REFS missing=", bad)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://savegame.json")) if false else null
	get_tree().quit()
