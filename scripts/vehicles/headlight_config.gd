class_name HeadlightConfig
extends RefCounted
## Per-vehicle headlight set-up.  Lamp positions come from the model's own lamp geometry (model["head_pos"], measured in
## GlbVehicle._split_lamps for the collection cars, VehicleModels head_spots for the BMW); everything else is a shared
## default that a vehicle can override with a "headlight" dictionary in its config (FleetVehicles / VehicleModels):
##   pitch      degrees the low beam is aimed below horizontal  (-7 = slightly down, covers the road in front)
##   splay      degrees each beam turns outward from the centre line (widens the lit area sideways)
##   angle      spot half-angle in degrees (wide low beam)       range  metres        energy  light energy
##   y_off / z_off   nudge of the light relative to the lamp centre (metres, car space)
##   high       high-beam spots {pitch, angle, range, energy} (optional; toggled with Vehicle.set_high_beam)
##   fill       near-fill omni light {range, energy, ahead, height}: lights the road right in front of the bumper
const DEFAULT := {
	"pitch": -6.0, "splay": 8.0, "angle": 60.0, "range": 50.0, "energy": 16.0,
	"atten": 0.9, "angle_atten": 0.9, "y_off": 0.0, "z_off": -0.04,
	"fill": {"range": 10.0, "energy": 1.6, "ahead": 1.8, "height": 0.35},
	"high": {"pitch": -1.5, "angle": 26.0, "range": 85.0, "energy": 5.0},
}

static func for_vehicle(vid: String) -> Dictionary:
	var cfg: Dictionary = DEFAULT.duplicate(true)
	var ov: Dictionary = VehicleModels.cfg(vid).get("headlight", {})
	for k in ov:
		if cfg.has(k) and cfg[k] is Dictionary and ov[k] is Dictionary:
			(cfg[k] as Dictionary).merge(ov[k], true)
		else:
			cfg[k] = ov[k]
	return cfg

## Left / right light positions (car space, model root space). Two positions required.
static func positions(model: Dictionary) -> Array:
	var hp: Array = model["head_pos"]
	if hp.size() == 1:
		var p: Vector3 = hp[0]
		return [Vector3(-absf(p.x), p.y, p.z), Vector3(absf(p.x), p.y, p.z)]
	return hp
