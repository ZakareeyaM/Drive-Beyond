class_name AudioManager
extends Node
## Fully procedural audio: engine loops, tyres, wind, rain, thunder, sirens,
## horn, impacts, UI sounds and two synthesised music tracks. Nothing is loaded
## from disk. Buses: Music / Engine / Environment / Effects (created by Game).

const SR := 22050

var world: World
var sounds: Dictionary = {}
var ready_flag: bool = false
var _thread: Thread
var _mutex := Mutex.new()
var _built: Dictionary = {}

var music_player: AudioStreamPlayer
var wind_player: AudioStreamPlayer
var rain_player: AudioStreamPlayer
var tyre_player: AudioStreamPlayer
var horn_player: AudioStreamPlayer
var heli_player: AudioStreamPlayer
var ui_players: Array = []
var fx_players: Array = []
var ai_engines: Array = []      # {car, player}
var sirens: Array = []          # {car, player}
var pl_engine: AudioStreamPlayer3D
var rev_player: AudioStreamPlayer3D        # ONE reverse-beep player, owned by the player's current vehicle (never overlaps)
var rev_stream: AudioStreamMP3
var rev_hold: float = 0.0
const REVERSE_BEEP := "res://assets/audio/Reverse_Beeping.mp3"
var pl_car: Vehicle
var music_want: String = ""
var music_cur: String = ""
var horn_on: bool = false
var thunder_q: Array = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_thread = Thread.new()
	_thread.start(_generate_all)

func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()

# ---------------------------------------------------------------- synthesis
static func _to_wav(data: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size()
	return w

static func _engine(kind: String) -> PackedFloat32Array:
	var n: int = 8820
	var out := PackedFloat32Array()
	out.resize(n)
	var k: float = 28.0            # cycles per loop -> 70 Hz fundamental
	var hmax: int = 16
	var decay: float = 0.9
	var grit: float = 1.8
	var pulse: float = 0.35
	match kind:
		"low":
			hmax = 12; decay = 1.1; grit = 2.2; pulse = 0.5; k = 20.0
		"mid":
			hmax = 20; decay = 0.95; grit = 2.0; pulse = 0.3
		"high":
			hmax = 30; decay = 0.65; grit = 2.4; pulse = 0.18; k = 36.0
		"electric":
			hmax = 5; decay = 0.8; grit = 1.0; pulse = 0.0; k = 80.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var nz: float = 0.0
	for i in n:
		var ph: float = TAU * k * float(i) / float(n)
		var s: float = 0.0
		for h in range(1, hmax + 1):
			var a: float = 1.0 / pow(float(h), decay)
			if kind == "high" and h % 2 == 1:
				a *= 1.3
			s += a * sin(ph * float(h) + float(h) * 0.7)
		s *= 0.22
		nz = nz * 0.9 + rng.randf_range(-1.0, 1.0) * 0.1
		s += nz * (0.12 if kind != "electric" else 0.02)
		s *= 1.0 + pulse * sin(ph * 0.5)
		out[i] = tanh(s * grit) * 0.6
	return out

static func _noise(seconds: float, lp: float, hp: float, gain: float, seed_v: int) -> PackedFloat32Array:
	var n: int = int(SR * seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var a: float = 0.0
	var b: float = 0.0
	for i in n:
		var x: float = rng.randf_range(-1.0, 1.0)
		a += (x - a) * lp
		b += (a - b) * hp
		out[i] = (a - b) * gain
	# crossfade the end into the start so the loop is seamless
	var fade: int = 1500
	for i in fade:
		var t: float = float(i) / float(fade)
		out[i] = out[i] * t + out[n - fade + i] * (1.0 - t) * 0.0 + out[n - fade + i] * (1.0 - t)
	var res := out.slice(0, n - fade)
	return res

static func _tone_env(freqs: Array, dur: float, gain: float, wave: String = "sine", attack: float = 0.005, decay_pow: float = 2.0) -> PackedFloat32Array:
	var n: int = int(SR * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t: float = float(i) / float(SR)
		var env: float = pow(1.0 - float(i) / float(n), decay_pow) * minf(1.0, t / attack)
		var s: float = 0.0
		for f in freqs:
			var ph: float = TAU * float(f) * t
			match wave:
				"square": s += signf(sin(ph)) * 0.6
				"saw": s += (fposmod(float(f) * t, 1.0) * 2.0 - 1.0) * 0.7
				_: s += sin(ph)
		out[i] = s / float(freqs.size()) * env * gain
	return out

static func _seq(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in parts:
		out.append_array(p)
	return out

static func _siren() -> PackedFloat32Array:
	var n: int = SR * 3
	var out := PackedFloat32Array()
	out.resize(n)
	var ph: float = 0.0
	for i in n:
		var t: float = float(i) / float(n)
		var f: float = 650.0 + 450.0 * (0.5 - 0.5 * cos(TAU * t))
		ph += TAU * f / float(SR)
		var s: float = sin(ph) + 0.35 * sin(ph * 2.0) + 0.15 * sin(ph * 3.0)
		out[i] = tanh(s * 1.4) * 0.35
	# the phase at the end differs from start; ensure loop by fading
	var fade: int = 400
	for i in fade:
		var k: float = float(i) / float(fade)
		out[n - fade + i] *= (1.0 - k)
	return out

static func _horn() -> PackedFloat32Array:
	var n: int = SR
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t: float = float(i) / float(SR)
		var s: float = 0.0
		for f in [400.0, 500.0]:
			for h in [1.0, 2.0, 3.0]:
				s += sin(TAU * f * h * t) / h
		out[i] = tanh(s * 0.5) * 0.4
	return out

static func _thunder() -> PackedFloat32Array:
	var n: int = SR * 4
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var a: float = 0.0
	for i in n:
		var t: float = float(i) / float(n)
		var x: float = rng.randf_range(-1.0, 1.0)
		a += (x - a) * (0.03 + 0.05 * (1.0 - t))
		var env: float = pow(1.0 - t, 2.0) * (0.6 + 0.4 * sin(t * 40.0) * (1.0 - t))
		out[i] = a * env * 5.0
	return out

static func _crash() -> PackedFloat32Array:
	var n: int = int(SR * 0.7)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var a: float = 0.0
	for i in n:
		var t: float = float(i) / float(n)
		var x: float = rng.randf_range(-1.0, 1.0)
		a += (x - a) * (0.35 * (1.0 - t) + 0.05)
		var thump: float = sin(TAU * 60.0 * float(i) / float(SR)) * pow(1.0 - t, 4.0) * 0.9
		out[i] = tanh((a * 3.0 + thump) * pow(1.0 - t, 1.5))
	return out

static func _heli() -> PackedFloat32Array:
	var n: int = int(SR * 0.5)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var a: float = 0.0
	for i in n:
		var t: float = float(i) / float(n)
		a += (rng.randf_range(-1.0, 1.0) - a) * 0.08
		var chop: float = pow(0.5 + 0.5 * sin(TAU * 10.0 * t), 3.0)
		out[i] = a * chop * 2.2 + sin(TAU * 90.0 * t * 5.0 / 5.0) * 0.1 * chop
	return out

static func _music(kind: String) -> PackedFloat32Array:
	var bpm: float = 104.0 if kind == "drive" else 78.0
	var beat: int = int(SR * 60.0 / bpm)
	var bars: int = 8
	var n: int = beat * 4 * bars
	var out := PackedFloat32Array()
	out.resize(n)
	var prog: Array = [[57, 60, 64], [53, 57, 60], [60, 64, 67], [55, 59, 62]]   # Am F C G
	var bass_root: Array = [33, 29, 36, 31]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var lead_notes: Array = [69, 72, 76, 72, 69, 67, 71, 74]
	var hat_env: float = 0.0
	var nz: float = 0.0
	for i in n:
		var beat_i: float = float(i) / float(beat)
		var bar: int = int(beat_i / 4.0) % bars
		var chord: int = (bar / 2) % 4
		var t_s: float = float(i) / float(SR)
		var s: float = 0.0
		# pad
		var pad: float = 0.0
		for note in prog[chord]:
			var f: float = 440.0 * pow(2.0, (float(note) - 69.0) / 12.0)
			pad += sin(TAU * f * t_s) + 0.5 * sin(TAU * f * 2.003 * t_s) * 0.5 + sin(TAU * f * 1.004 * t_s) * 0.6
		var bar_pos: float = fposmod(beat_i, 8.0) / 8.0
		var swell: float = 0.55 + 0.45 * sin(PI * bar_pos)
		s += pad * 0.045 * swell
		# bass (drive only is punchy, menu is soft)
		var bf: float = 440.0 * pow(2.0, (float(bass_root[chord]) - 69.0) / 12.0)
		var eighth: float = fposmod(beat_i * 2.0, 1.0)
		var benv: float = pow(1.0 - eighth, 1.4)
		var bwave: float = fposmod(bf * t_s, 1.0) * 2.0 - 1.0
		if kind == "drive":
			s += tanh(bwave * 2.0 * (0.4 + benv)) * 0.18 * (0.35 + benv)
		else:
			s += sin(TAU * bf * t_s) * 0.16
		if kind == "drive":
			# drums
			var in_beat: float = fposmod(beat_i, 1.0)
			var bi: int = int(beat_i) % 4
			if bi == 0 or bi == 2:
				var kt: float = in_beat * 60.0 / bpm
				s += sin(TAU * (45.0 + 80.0 * exp(-kt * 30.0)) * kt) * exp(-kt * 9.0) * 0.55
			if bi == 1 or bi == 3:
				var st: float = in_beat * 60.0 / bpm
				nz = rng.randf_range(-1.0, 1.0)
				s += nz * exp(-st * 16.0) * 0.22
			var off: float = fposmod(beat_i + 0.5, 1.0)
			var ht: float = off * 60.0 / bpm
			s += rng.randf_range(-1.0, 1.0) * exp(-ht * 55.0) * 0.07
			# lead arpeggio
			var sixt: int = int(beat_i * 4.0) % 8
			var ln: int = lead_notes[sixt] + (chord - 0) * 0 - (0 if chord % 2 == 0 else 2)
			var lf: float = 440.0 * pow(2.0, (float(ln) - 69.0) / 12.0)
			var lt: float = fposmod(beat_i * 4.0, 1.0)
			var lenv: float = pow(1.0 - lt, 2.0)
			s += (sin(TAU * lf * t_s) + 0.4 * sin(TAU * lf * 2.0 * t_s)) * lenv * 0.05 * (1.0 if bar >= 2 else 0.0)
		else:
			var sl: float = fposmod(beat_i * 0.5, 1.0)
			var f2: float = 440.0 * pow(2.0, (float(lead_notes[int(beat_i * 0.5) % 8]) - 81.0) / 12.0)
			s += sin(TAU * f2 * t_s) * pow(1.0 - sl, 2.0) * 0.06
		out[i] = tanh(s * 1.1) * 0.8
	return out

func _generate_all() -> void:
	var b: Dictionary = {}
	b["eng_low"] = _to_wav(_engine("low"), true)
	b["eng_mid"] = _to_wav(_engine("mid"), true)
	b["eng_high"] = _to_wav(_engine("high"), true)
	b["eng_electric"] = _to_wav(_engine("electric"), true)
	b["tyre"] = _to_wav(_noise(1.2, 0.35, 0.02, 3.0, 3), true)
	b["wind"] = _to_wav(_noise(2.5, 0.1, 0.004, 5.0, 4), true)
	b["rain"] = _to_wav(_noise(2.5, 0.55, 0.15, 2.4, 6), true)
	b["siren"] = _to_wav(_siren(), true)
	b["horn"] = _to_wav(_horn(), true)
	b["heli"] = _to_wav(_heli(), true)
	b["thunder"] = _to_wav(_thunder(), false)
	b["crash"] = _to_wav(_crash(), false)
	b["shift"] = _to_wav(_tone_env([180.0], 0.07, 0.4, "square", 0.002, 3.0), false)
	b["click"] = _to_wav(_tone_env([1200.0], 0.05, 0.35, "sine", 0.001, 3.0), false)
	b["beep"] = _to_wav(_tone_env([880.0], 0.16, 0.5, "sine", 0.004, 1.2), false)
	b["go"] = _to_wav(_tone_env([1320.0], 0.45, 0.5, "square", 0.004, 1.5), false)
	b["checkpoint"] = _to_wav(_seq([_tone_env([784.0], 0.1, 0.45), _tone_env([1175.0], 0.22, 0.45)]), false)
	b["pickup"] = _to_wav(_seq([_tone_env([988.0], 0.08, 0.4), _tone_env([1319.0], 0.08, 0.4), _tone_env([1760.0], 0.2, 0.4)]), false)
	b["win"] = _to_wav(_seq([_tone_env([523.0], 0.12, 0.45), _tone_env([659.0], 0.12, 0.45), _tone_env([784.0], 0.12, 0.45), _tone_env([1047.0, 784.0], 0.5, 0.5)]), false)
	b["fail"] = _to_wav(_seq([_tone_env([392.0], 0.18, 0.45, "saw"), _tone_env([311.0], 0.18, 0.45, "saw"), _tone_env([233.0], 0.5, 0.45, "saw")]), false)
	b["camera"] = _to_wav(_noise(0.18, 0.7, 0.2, 2.0, 8).slice(0, 3000), false)
	b["music_menu"] = _to_wav(_music("menu"), true)
	b["music_drive"] = _to_wav(_music("drive"), true)
	_mutex.lock()
	_built = b
	_mutex.unlock()

func _poll_ready() -> void:
	if ready_flag:
		return
	_mutex.lock()
	var b: Dictionary = _built
	_mutex.unlock()
	if b.is_empty():
		return
	if _thread.is_started():
		_thread.wait_to_finish()
	sounds = b
	ready_flag = true
	_build_players()
	if world and world.env and not world.env.thunder.is_connected(_on_thunder):
		world.env.thunder.connect(_on_thunder)
	if music_want != "":
		set_music(music_want)

func _mk(stream: AudioStream, bus: String, vol_db: float = 0.0, autoplay: bool = true) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = bus
	p.volume_db = vol_db
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	if autoplay:
		p.play()
	return p

func _build_players() -> void:
	music_player = _mk(sounds["music_menu"], "Music", -8.0, false)
	wind_player = _mk(sounds["wind"], "Environment", -60.0)
	rain_player = _mk(sounds["rain"], "Environment", -60.0)
	tyre_player = _mk(sounds["tyre"], "Effects", -60.0)
	horn_player = _mk(sounds["horn"], "Effects", -6.0, false)
	heli_player = _mk(sounds["heli"], "Environment", -60.0)
	for i in 6:
		ui_players.append(_mk(null, "Effects", -4.0, false))
		fx_players.append(_mk(null, "Effects", -2.0, false))

func _on_thunder(delay: float) -> void:
	thunder_q.append(delay)

# ---------------------------------------------------------------- API
func set_music(kind: String) -> void:
	music_want = kind
	if not ready_flag:
		return
	if music_cur == kind and music_player.playing:
		return
	music_cur = kind
	music_player.stream = sounds["music_" + kind]
	music_player.play()

func set_horn(on: bool) -> void:
	horn_on = on

func _engine_kind(vid: String) -> String:
	var eng: String = String(Data.vehicle(vid).get("engine", "v6"))
	if eng == "electric":
		return "eng_electric"
	if eng in ["v8", "v10", "v12"]:
		return "eng_low"
	if eng in ["rotary", "i4", "flat6", "i4t"]:
		return "eng_high"
	return "eng_mid"

var _custom_engine_streams: Dictionary = {}

## Per-vehicle recorded engine loop (VehicleModels "engine_sound"); falls back to the procedural loops.
func _engine_stream(vid: String) -> AudioStream:
	var cfg: Dictionary = VehicleModels.cfg(vid)
	if cfg.has("engine_sound") and ResourceLoader.exists(String(cfg["engine_sound"])):
		if not _custom_engine_streams.has(vid):
			var st: AudioStream = load(String(cfg["engine_sound"]))
			if st is AudioStreamMP3:
				(st as AudioStreamMP3).loop = true
				(st as AudioStreamMP3).loop_offset = float(cfg.get("engine_loop_offset", 0.0))
			_custom_engine_streams[vid] = st
		return _custom_engine_streams[vid]
	return sounds[_engine_kind(vid)]

func _engine3d(v: Vehicle, vol: float, dist: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _engine_stream(v.vid)
	p.bus = "Engine"
	p.unit_size = 6.0
	p.max_distance = dist
	p.volume_db = vol
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	v.add_child(p)
	p.play()
	return p

func attach_vehicle(v: Vehicle) -> void:
	pl_car = v
	if not ready_flag:
		_poll_ready()
	if ready_flag:
		if pl_engine and is_instance_valid(pl_engine):
			pl_engine.queue_free()
		pl_engine = _engine3d(v, -3.0, 160.0)
	_attach_reverse(v)

## Reverse warning beeper: a looping 3D player on the player's vehicle (cars and go-karts alike).  The previous one is freed when the
## vehicle changes, so vehicle switches / exits can never leave a beeper running or stack two.
func _attach_reverse(v: Vehicle) -> void:
	if rev_player != null and is_instance_valid(rev_player):
		rev_player.stop()
		rev_player.queue_free()
	rev_player = null
	rev_hold = 0.0
	if not ResourceLoader.exists(REVERSE_BEEP):
		return
	if rev_stream == null:
		rev_stream = load(REVERSE_BEEP) as AudioStreamMP3
		if rev_stream != null:
			rev_stream.loop = true
	var p := AudioStreamPlayer3D.new()
	p.name = "ReverseBeep"
	p.stream = rev_stream
	p.bus = "Effects"
	p.unit_size = 5.0
	p.max_distance = 70.0
	p.volume_db = -6.0
	v.add_child(p)
	rev_player = p

func _update_reverse(v: Vehicle, delta: float) -> void:
	if rev_player == null or not is_instance_valid(rev_player):
		return
	# actual reverse motion only: signed forward speed < 0 while the player is driving this vehicle
	var driving: bool = world != null and world.mode == "drive" and world.player_car == v
	var backing: bool = driving and not v.wrecked and v.engine_on and v.speed < -0.7
	if backing:
		rev_hold = 0.0
		if not rev_player.playing:
			rev_player.play()
	elif rev_player.playing:
		rev_hold += delta
		if rev_hold > 0.2 or not driving or v.wrecked:     # tiny grace so a speed wobble does not chop the loop
			rev_player.stop()

func attach_ai_engine(v: Vehicle) -> void:
	if not ready_flag:
		return
	var p: AudioStreamPlayer3D = _engine3d(v, -6.0, 110.0)
	ai_engines.append({"car": v, "player": p})

func attach_siren(v: Vehicle) -> void:
	if not ready_flag:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = sounds["siren"]
	p.bus = "Effects"
	p.unit_size = 14.0
	p.max_distance = 260.0
	p.volume_db = -4.0
	v.add_child(p)
	p.play()
	sirens.append({"car": v, "player": p})
	var e3: AudioStreamPlayer3D = _engine3d(v, -7.0, 120.0)
	ai_engines.append({"car": v, "player": e3})

func _one_shot(name: String, bus_players: Array, vol: float = 0.0, pitch: float = 1.0) -> void:
	if not ready_flag or not sounds.has(name):
		return
	for p in bus_players:
		var pl: AudioStreamPlayer = p
		if not pl.playing:
			pl.stream = sounds[name]
			pl.volume_db = vol
			pl.pitch_scale = pitch
			pl.play()
			return

func play_ui(name: String) -> void:
	_one_shot("click" if name == "click" else name, ui_players)

func play_shift() -> void:
	_one_shot("shift", fx_players, -8.0, randf_range(0.9, 1.1))

func play_crash(sev: float) -> void:
	_one_shot("crash", fx_players, linear_to_db(clampf(0.4 + sev, 0.2, 1.4)), randf_range(0.85, 1.15))

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	if not ready_flag:
		_poll_ready()
		return
	if world == null or not world.running:
		wind_player.volume_db = -60.0
		rain_player.volume_db = -60.0
		tyre_player.volume_db = -60.0
		heli_player.volume_db = -60.0
		if rev_player != null and is_instance_valid(rev_player) and rev_player.playing:
			rev_player.stop()
		return
	var v: Vehicle = pl_car if is_instance_valid(pl_car) else null
	if v and is_instance_valid(v):
		_update_reverse(v, delta)
		if pl_engine and is_instance_valid(pl_engine):
			var rn: float = clampf(v.rpm_norm, 0.0, 1.2)
			var elec: bool = String(v.spec.get("engine", "")) == "electric"
			pl_engine.pitch_scale = (0.5 + rn * 2.4) if not elec else (0.4 + rn * 2.8)
			var ecfg: Dictionary = VehicleModels.cfg(v.vid)
			if ecfg.has("engine_pitch"):
				var ep: Array = ecfg["engine_pitch"]
				pl_engine.pitch_scale = lerpf(float(ep[0]), float(ep[1]), clampf(rn, 0.0, 1.0))
			var ld: float = 0.55 + 0.45 * v.in_throttle
			var drive_mode: bool = world.mode == "drive"
			pl_engine.volume_db = linear_to_db(maxf(0.001, ld * (1.0 if drive_mode else 0.45) * (0.0 if not v.engine_on else 1.0))) - 2.0
			if v.fuel <= 0.0:
				pl_engine.volume_db = -60.0
		var sp: float = v.abs_speed
		var wind_v: float = clampf(sp / 60.0, 0.0, 1.0)
		wind_player.volume_db = linear_to_db(maxf(0.001, wind_v * wind_v * 0.8)) - 3.0
		wind_player.pitch_scale = 0.8 + wind_v * 0.5
		var slip_v: float = clampf((v.slip - 0.25) * 1.6, 0.0, 1.0) * clampf(sp / 6.0, 0.0, 1.0)
		if v.braking_now and sp > 12.0:
			slip_v = maxf(slip_v, 0.2)
		tyre_player.volume_db = linear_to_db(maxf(0.001, slip_v)) - 5.0
		tyre_player.pitch_scale = 0.85 + slip_v * 0.35
	var rain: float = world.env.cur["rain"] if world.env else 0.0
	rain_player.volume_db = linear_to_db(maxf(0.001, rain * 0.9)) - 6.0
	# horn
	if horn_on and not horn_player.playing:
		horn_player.play()
	elif not horn_on and horn_player.playing:
		horn_player.stop()
	# thunder
	for i in range(thunder_q.size() - 1, -1, -1):
		thunder_q[i] -= delta
		if thunder_q[i] <= 0.0:
			thunder_q.remove_at(i)
			_one_shot("thunder", fx_players, -2.0, randf_range(0.8, 1.1))
	# ai engines
	for e in ai_engines.duplicate():
		var cv: Variant = e["car"]       # untyped: a freed car cannot be assigned to a typed Vehicle variable (that raised an error EVERY frame)
		if not is_instance_valid(cv) or not is_instance_valid(e["player"]) or (cv as Node).is_queued_for_deletion():
			ai_engines.erase(e)
			continue
		var c: Vehicle = cv
		var p: AudioStreamPlayer3D = e["player"]
		p.pitch_scale = 0.5 + clampf(c.rpm_norm, 0.0, 1.2) * 2.4
		p.volume_db = -4.0 + linear_to_db(0.4 + 0.6 * c.in_throttle)
	for s in sirens.duplicate():
		if not is_instance_valid(s["car"]) or not is_instance_valid(s["player"]) or (s["car"] as Node).is_queued_for_deletion():
			sirens.erase(s)
			continue
		(s["player"] as AudioStreamPlayer3D).stream_paused = world.police.level == 0
	# helicopter
	if world.police and world.police.heli:
		var d: float = world.police.heli_distance(world.player_pos())
		heli_player.volume_db = linear_to_db(clampf(1.0 - d / 260.0, 0.0, 1.0) + 0.001) - 4.0
	else:
		heli_player.volume_db = -60.0
	# music ducking in pause / volume
	music_player.volume_db = -9.0 if world.mode == "drive" else -6.0
