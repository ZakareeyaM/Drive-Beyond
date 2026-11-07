class_name TiltSteer
extends RefCounted
## Tilt steering from the gravity vector (accelerometer), NOT the raw gyroscope
## (gyro = angular velocity, which drifts and cannot give a held steering angle).
##
## Godot already rotates sensor values into the current screen orientation, so in
## landscape the vector is expressed in screen axes: x = screen right, y = screen up,
## gravity points toward "down" => upright phone reads y ~ -9.8. The steering wheel
## angle is the roll of the phone around the axis pointing at the player:
##     roll = atan2(g.x, -g.y)     (positive = right edge dips = steer right)
## Pipeline: roll -> minus calibrated neutral -> dead zone -> scale by range*sens
##           -> clamp -> low-pass smoothing.

const MAX_ROLL_DEG := 30.0   # roll that gives full lock at sensitivity 1.0
const FLAT_LIMIT := 4.5      # |g.y| below this (m/s^2): phone lying flat, roll undefined -> neutral

var neutral_roll: float = 0.0     # radians, set by calibrate()
var smoothed: float = 0.0
var raw_roll: float = 0.0         # radians, last measured (uncalibrated)
var output: float = 0.0
var has_sensor: bool = false
var calibrated: bool = false
var flat: bool = false
## Test hook: when not null it replaces the hardware reading (screen-space gravity).
var override_gravity = null

static func sensor_present() -> bool:
	var g: Vector3 = Input.get_gravity()
	var a: Vector3 = Input.get_accelerometer()
	return g.length() > 1.0 or a.length() > 1.0

func read_gravity() -> Vector3:
	if override_gravity != null:
		return override_gravity
	var g: Vector3 = Input.get_gravity()
	if g.length() < 1.0:
		g = Input.get_accelerometer()   # fallback for devices without a fused gravity sensor
	return g

## Roll in radians from a screen-space gravity vector; sets `flat`.
func roll_of(g: Vector3) -> float:
	flat = absf(g.y) < FLAT_LIMIT and absf(g.z) > absf(g.y) * 2.0
	return atan2(g.x, -g.y)

## Take the current pose as neutral (call at session start / resume / on CAL button).
func calibrate() -> void:
	var g: Vector3 = read_gravity()
	has_sensor = g.length() > 1.0
	if not has_sensor:
		return
	roll_of(g)
	if flat:
		# Phone is lying flat: assume a natural driving pose (upright) rather than a random angle.
		neutral_roll = 0.0
	else:
		neutral_roll = atan2(g.x, -g.y)
	smoothed = 0.0
	output = 0.0
	calibrated = true

func reset() -> void:
	smoothed = 0.0
	output = 0.0

## Returns steering in [-1, 1]. sens: 0.3..2.5, dead_deg: degrees, invert: flip sign.
func update(delta: float, sens: float, dead_deg: float, invert: bool) -> float:
	var g: Vector3 = read_gravity()
	has_sensor = g.length() > 1.0
	if not has_sensor:
		output = 0.0
		smoothed = lerpf(smoothed, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		return 0.0
	if not calibrated:
		calibrate()
	raw_roll = roll_of(g)
	var target: float = 0.0
	if not flat:
		var d: float = wrapf(raw_roll - neutral_roll, -PI, PI)
		var deg: float = rad_to_deg(d)
		var dz: float = maxf(dead_deg, 0.0)
		if absf(deg) > dz:
			deg = signf(deg) * (absf(deg) - dz)      # continuous: no jump at the dead-zone edge
			var span: float = maxf(MAX_ROLL_DEG - dz, 5.0) / maxf(sens, 0.1)
			target = clampf(deg / span, -1.0, 1.0)
	if invert:
		target = -target
	# critically-damped-ish low pass; faster when returning to centre so it never feels stuck
	var rate: float = 14.0 if absf(target) < absf(smoothed) else 9.0
	smoothed = lerpf(smoothed, target, 1.0 - exp(-rate * delta))
	output = clampf(smoothed, -1.0, 1.0)
	return output
