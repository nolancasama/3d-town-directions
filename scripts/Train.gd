class_name Train
extends Node3D
# =============================================================================
# Train.gd — a simple east-to-west passenger train that passes through town
# along the existing track at z = -150.  No collision (the TrackBarrier already
# keeps the player off the tracks).  Audio is generated procedurally via
# AudioStreamWAV, matching the same approach used by the bus engine.
# =============================================================================

const SPEED      := 26.0    # world units per second
const START_X    := 240.0   # spawn well east of the map edge
const END_X      := -240.0  # despawn well west of the map edge
const TRACK_Z    := -150.0

var _mats: Dictionary = {}
var _whistled_a  := false   # approaching platform whistle (~x = +80)
var _whistled_b  := false   # departing whistle            (~x = -20)
var _rumble:  AudioStreamPlayer3D
var _whistle: AudioStreamPlayer3D


func _ready() -> void:
	position = Vector3(START_X, 0.0, TRACK_Z)
	_build()
	_setup_audio()


# ---------------------------------------------------------------------------
# Audio
# ---------------------------------------------------------------------------
func _setup_audio() -> void:
	_rumble = AudioStreamPlayer3D.new()
	_rumble.stream       = _make_rumble()
	_rumble.unit_size    = 22.0
	_rumble.max_distance = 150.0
	_rumble.volume_db    = 2.0
	_rumble.autoplay     = true
	add_child(_rumble)

	_whistle = AudioStreamPlayer3D.new()
	_whistle.stream       = _make_whistle()
	_whistle.unit_size    = 40.0
	_whistle.max_distance = 200.0
	_whistle.volume_db    = 6.0
	add_child(_whistle)


func _make_rumble() -> AudioStreamWAV:
	# Matches the Web Audio version: 50 Hz base oscillator with a square-wave
	# LFO at 7.5 Hz modulating the FREQUENCY by ±22 Hz (FM, not AM).
	# Loop = 3 LFO cycles (4410 samples). Over that span the oscillator
	# completes exactly 20 cycles (integral of inst_freq = 20), so both the
	# main phase and all integer/half-integer harmonics return to their
	# starting value — no click at the loop point.
	var rate      := 11025
	var n         := 4410            # 3 × (11025 / 7.5) = 3 × 1470
	var base_freq := 50.0
	var lfo_freq  := 7.5
	var lfo_depth := 22.0            # Hz deviation (same as Web Audio gainNode)

	var data := PackedByteArray()
	data.resize(n * 2)

	var phase := 0.0
	for s in n:
		var t         := float(s) / float(rate)
		var lfo       := 1.0 if fmod(t * lfo_freq, 1.0) < 0.5 else -1.0
		var inst_freq := base_freq + lfo_depth * lfo
		phase         += TAU * inst_freq / float(rate)

		var v  := sin(phase)       * 0.26   # fundamental (FM-modulated)
		v      += sin(phase * 2.0) * 0.11   # 2nd harmonic
		v      += sin(phase * 3.0) * 0.07   # 3rd harmonic
		v      += sin(phase * 0.5) * 0.10   # sub-harmonic (~25 Hz)

		var iv := int(clampf(v, -1.0, 1.0) * 32767.0)
		data[s * 2]     = iv & 0xFF
		data[s * 2 + 1] = (iv >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.format     = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate   = rate
	wav.stereo     = false
	wav.data       = data
	wav.loop_mode  = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end   = n - 1
	return wav


func _make_whistle() -> AudioStreamWAV:
	# Two-tone chord (root + fifth: 880 Hz + 1320 Hz), 1.6 s one-shot.
	var rate        := 11025
	var num_samples := int(1.6 * rate)

	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for s in num_samples:
		var t   := float(s) / float(rate)
		var env := 0.0
		if t < 0.09:
			env = t / 0.09
		elif t < 1.1:
			env = 1.0
		else:
			env = 1.0 - (t - 1.1) / 0.5
		env     = clampf(env, 0.0, 1.0)
		var v   := sin(TAU * 880.0  * t) * 0.13
		v       += sin(TAU * 1320.0 * t) * 0.13
		v       *= env
		var iv  := int(clampf(v, -1.0, 1.0) * 32767.0)
		data[s * 2]     = iv & 0xFF
		data[s * 2 + 1] = (iv >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.format   = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo   = false
	wav.data     = data
	return wav


# ---------------------------------------------------------------------------
# Movement & lifecycle
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	position.x -= SPEED * delta

	if not _whistled_a and position.x < 80.0:
		_whistled_a = true
		_whistle.play()

	if not _whistled_b and position.x < -20.0:
		_whistled_b = true
		_whistle.play()

	if position.x < END_X:
		queue_free()


# ---------------------------------------------------------------------------
# Visuals
# ---------------------------------------------------------------------------
func _build() -> void:
	if randi() % 2 == 0:
		_build_classic()
	else:
		_build_commuter()


func _build_classic() -> void:
	_loco()
	_car(Color(0.55, 0.12, 0.10), 11.0)
	_car(Color(0.18, 0.36, 0.22), 23.0)
	_car(Color(0.15, 0.22, 0.48), 35.0)
	_car(Color(0.55, 0.12, 0.10), 47.0)
	_car(Color(0.18, 0.36, 0.22), 59.0)


func _build_commuter() -> void:
	_loco_commuter()
	var stripe := Color(0.08, 0.32, 0.72)
	_car_commuter(stripe, 11.0, true)
	_car_commuter(stripe, 23.0)
	_car_commuter(stripe, 35.0)
	_car_commuter(stripe, 47.0)
	_car_commuter(stripe, 59.0)


func _loco() -> void:
	var navy   := Color(0.10, 0.15, 0.30)
	var yellow := Color(0.90, 0.78, 0.12)
	var chrome := Color(0.72, 0.72, 0.76)
	var glass  := Color(0.58, 0.76, 0.88)
	var dark   := Color(0.20, 0.20, 0.23)

	var n := Node3D.new()
	add_child(n)

	_bx(n, Vector3(9.5, 4.2, 3.2), Vector3(0.0,  2.1,  0.0), navy)
	_bx(n, Vector3(9.5, 0.4, 3.5), Vector3(0.0,  0.55, 0.0), yellow)
	_bx(n, Vector3(4.5, 2.2, 3.1), Vector3(1.5,  5.3,  0.0), navy)
	_bx(n, Vector3(0.9, 1.8, 0.9), Vector3(3.5,  7.2,  0.0), dark)
	_bx(n, Vector3(0.5, 3.8, 3.2), Vector3(-5.2, 1.9,  0.0), navy)
	_bx(n, Vector3(0.8, 0.4, 3.4), Vector3(-5.3, 0.4,  0.0), yellow)
	_bx(n, Vector3(0.3, 0.5, 0.6), Vector3(-5.6, 3.0,  0.0), chrome)
	for wz in [-1.48, 1.48]:
		_bx(n, Vector3(0.1, 1.1, 1.2), Vector3(2.8, 5.1, wz), glass)
	for wx in [-3.2, 0.0, 3.2]:
		for wz2 in [-1.72, 1.72]:
			_bx(n, Vector3(0.5, 1.4, 0.38), Vector3(wx, 0.7, wz2), dark)


func _car(color: Color, offset_x: float) -> void:
	var glass := Color(0.58, 0.76, 0.88)
	var roof  := Color(0.28, 0.28, 0.30)
	var dark  := Color(0.20, 0.20, 0.23)

	var n := Node3D.new()
	n.position.x = offset_x
	add_child(n)

	_bx(n, Vector3(11.5, 3.6, 3.0), Vector3(0.0, 1.8,  0.0), color)
	_bx(n, Vector3(11.0, 0.3, 2.8), Vector3(0.0, 3.75, 0.0), roof)
	_bx(n, Vector3(11.5, 0.35, 3.2), Vector3(0.0, 0.5, 0.0), roof)
	for wx in [-4.0, -1.6, 0.8, 3.2]:
		for wz in [-1.53, 1.53]:
			_bx(n, Vector3(1.7, 0.95, 0.1), Vector3(wx, 2.4, wz), glass)
	for wx2 in [-4.1, 4.1]:
		for wz2 in [-1.62, 1.62]:
			_bx(n, Vector3(0.5, 1.1, 0.38), Vector3(wx2, 0.55, wz2), dark)


func _loco_commuter() -> void:
	var silver := Color(0.90, 0.91, 0.93)
	var stripe := Color(0.08, 0.32, 0.72)
	var glass  := Color(0.62, 0.78, 0.92)
	var roof   := Color(0.72, 0.73, 0.76)
	var dark   := Color(0.20, 0.20, 0.24)
	var light  := Color(1.00, 0.98, 0.85)

	var n := Node3D.new()
	add_child(n)

	_bx(n, Vector3(9.5, 3.6, 3.0),  Vector3(0.0,   1.80,  0.0), silver)
	_bx(n, Vector3(9.2, 0.25, 2.8), Vector3(0.0,   3.725, 0.0), roof)
	_bx(n, Vector3(9.5, 0.55, 3.02),Vector3(0.0,   0.55,  0.0), stripe)
	_bx(n, Vector3(8.8, 0.30, 2.8), Vector3(0.0,   0.15,  0.0), dark)
	_bx(n, Vector3(0.9, 3.4, 2.8),  Vector3(-5.2,  1.70,  0.0), silver)
	_bx(n, Vector3(0.7, 2.8, 2.2),  Vector3(-5.95, 1.40,  0.0), silver)
	_bx(n, Vector3(0.9, 0.55, 2.9), Vector3(-5.2,  0.55,  0.0), stripe)
	_bx(n, Vector3(0.7, 0.55, 2.3), Vector3(-5.95, 0.55,  0.0), stripe)
	_bx(n, Vector3(0.12, 1.1, 1.4), Vector3(-6.56, 2.2,   0.0), glass)
	for hz in [-0.7, 0.7]:
		_bx(n, Vector3(0.1, 0.28, 0.38), Vector3(-6.56, 1.0, hz), light)
	for wz in [-1.52, 1.52]:
		for i in 3:
			_bx(n, Vector3(2.0, 1.1, 0.08), Vector3(-2.5 + float(i) * 2.8, 2.4, wz), glass)
	for wx in [-3.0, 3.0]:
		for wz in [-1.62, 1.62]:
			_bx(n, Vector3(0.55, 0.95, 0.32), Vector3(wx, 0.475, wz), dark)


func _car_commuter(stripe: Color, offset_x: float, has_flag: bool = false) -> void:
	var silver := Color(0.90, 0.91, 0.93)
	var glass  := Color(0.62, 0.78, 0.92)
	var roof   := Color(0.72, 0.73, 0.76)
	var dark   := Color(0.20, 0.20, 0.24)

	var n := Node3D.new()
	n.position.x = offset_x
	add_child(n)

	_bx(n, Vector3(11.5, 3.6, 3.0),  Vector3(0.0, 1.80,  0.0), silver)
	_bx(n, Vector3(11.2, 0.25, 2.8), Vector3(0.0, 3.725, 0.0), roof)
	_bx(n, Vector3(11.5, 0.55, 3.02),Vector3(0.0, 0.55,  0.0), stripe)
	_bx(n, Vector3(10.8, 0.30, 2.8), Vector3(0.0, 0.15,  0.0), dark)
	for wz in [-1.52, 1.52]:
		for i in 5:
			_bx(n, Vector3(1.7, 1.1, 0.08), Vector3(-4.6 + float(i) * 2.3, 2.4, wz), glass)
	for wx in [-4.0, 4.0]:
		for wz in [-1.62, 1.62]:
			_bx(n, Vector3(0.55, 0.95, 0.32), Vector3(wx, 0.475, wz), dark)
	if has_flag:
		for face in [-1.0, 1.0]:
			_american_flag(n, 0.0, 1.35, face)


func _american_flag(parent: Node3D, x: float, y: float, z_face: float) -> void:
	var flag_red   := Color(0.73, 0.09, 0.13)
	var flag_white := Color(0.95, 0.95, 0.95)
	var flag_blue  := Color(0.10, 0.24, 0.56)
	var z0 := z_face * 1.53
	var z1 := z_face * 1.57
	_bx(parent, Vector3(1.8, 0.76, 0.04), Vector3(x, y, z0), flag_red)
	for i in 3:
		var wy := y - 0.22 + float(i) * 0.22
		_bx(parent, Vector3(1.8, 0.07, 0.04), Vector3(x, wy, z1), flag_white)
	var canton_x := x - 0.575 * z_face
	_bx(parent, Vector3(0.65, 0.38, 0.04), Vector3(canton_x, y + 0.19, z1), flag_blue)


func _bx(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	if not _mats.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		_mats[color] = mat
	mi.material_override = _mats[color]
	mi.position = pos
	parent.add_child(mi)
