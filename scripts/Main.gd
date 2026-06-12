extends Node3D
# =============================================================================
# Main.gd  -  Bootstrap / TownBuilder
# -----------------------------------------------------------------------------
# Builds a small North-American-style town on a STREET GRID, then populates it:
#   * A central green (the Park) ringed by civic buildings (town-square logic).
#   * 19 "goal" buildings dispersed across town following loose city logic
#     (civic core downtown, commercial frontage on main streets, services to
#     one side, transport toward the edge, recreation/landmark toward the
#     outskirts).
#   * The remaining lots filled with miscellaneous buildings a US town has
#     (houses, church, gas station, diner, motel, office...).
#
# Everything is primitive geometry. Buildings are authored in LOCAL space with
# their front on +Z, then rotated so the front faces the nearest street.
# =============================================================================

# --- Street grid -------------------------------------------------------------
# 5x5 blocks of 64 units. Buildings are packed into each block (see
# _layout_buildings), and the street grid between blocks is the "maze".
const GRID := [-135.0, -81.0, -27.0, 27.0, 81.0, 135.0]   # x/z positions of street lines (54-unit spacing)
const ROAD_W := 9.0
const HALF := 4.5                          # road half width
const SW_W := 2.2                          # sidewalk width
const SW_OFF := HALF + 1.1                  # sidewalk center offset from road line (5.6)
const EXT := 150.0                          # how far roads/sidewalks run from origin
const HALF_BLOCK := 27.0                    # block centre -> inner street line (= spacing / 2)

const PLAYER_SPAWN := Vector3(0, 1, 16)
const NPC_SPAWN := Vector3(0, 0, 9)

# --- Palette -----------------------------------------------------------------
const ASPHALT := Color(0.17, 0.17, 0.20)
const SIDEWALK := Color(0.66, 0.66, 0.69)
const LINE := Color(0.90, 0.88, 0.66)

# Each building: name, lot position (y=0), footprint size, base color, style,
# and whether it is a navigable goal. `accent` tints trims/awnings/roofs.
const GOAL_DEFS := {
	"Library": {"style": "civic", "size": Vector3(16, 11, 13), "color": Color(0.80, 0.73, 0.55)},
	"Bank": {"style": "civic", "size": Vector3(16, 10, 13), "color": Color(0.82, 0.81, 0.77), "accent": Color(0.80, 0.66, 0.18)},
	"Post Office": {"style": "civic", "size": Vector3(16, 9, 13), "color": Color(0.74, 0.70, 0.62)},
	"Museum": {"style": "civic", "size": Vector3(18, 12, 15), "color": Color(0.86, 0.84, 0.78)},
	"City Hall": {"style": "civic", "size": Vector3(16, 12, 14), "color": Color(0.85, 0.82, 0.74), "accent": Color(0.70, 0.60, 0.20)},
	"Town Office": {"style": "office", "size": Vector3(14, 12, 12), "color": Color(0.56, 0.63, 0.71)},
	"Police Station": {"style": "police", "size": Vector3(14, 8, 13), "color": Color(0.32, 0.38, 0.52), "accent": Color(0.15, 0.20, 0.35)},
	"Fire Station": {"style": "firehouse", "size": Vector3(15, 9, 15), "color": Color(0.66, 0.13, 0.11), "accent": Color(0.20, 0.20, 0.22)},
	"Hospital": {"style": "hospital", "size": Vector3(18, 13, 16), "color": Color(0.93, 0.95, 0.97)},
	"Drugstore": {"style": "shop", "size": Vector3(13, 7, 12), "color": Color(0.30, 0.55, 0.45), "accent": Color(0.85, 0.85, 0.88)},
	"Bakery": {"style": "shop", "size": Vector3(12, 7, 11), "color": Color(0.86, 0.72, 0.55), "accent": Color(0.75, 0.45, 0.30)},
	"Bookstore": {"style": "shop", "size": Vector3(12, 7, 11), "color": Color(0.45, 0.36, 0.55), "accent": Color(0.30, 0.22, 0.40)},
	"Starbucks": {"style": "shop", "size": Vector3(11, 6, 11), "color": Color(0.10, 0.42, 0.27), "accent": Color(0.05, 0.30, 0.18)},
	"McDonald's": {"style": "shop", "size": Vector3(12, 6, 11), "color": Color(0.74, 0.13, 0.11), "accent": Color(0.95, 0.78, 0.10)},
	"Supermarket": {"style": "market", "size": Vector3(20, 7, 18), "color": Color(0.80, 0.34, 0.26), "accent": Color(0.55, 0.20, 0.15)},
	"Convenience Store": {"style": "shop", "size": Vector3(12, 6, 11), "color": Color(0.90, 0.55, 0.20), "accent": Color(0.55, 0.30, 0.10)},
	"Diner": {"style": "diner", "size": Vector3(12, 5, 11), "color": Color(0.80, 0.82, 0.85), "accent": Color(0.80, 0.20, 0.20)},
	"Gas Station": {"style": "gas", "size": Vector3(14, 4, 11)},
	"School": {"style": "brick", "size": Vector3(18, 8, 14), "color": Color(0.68, 0.27, 0.22)},
	"Swimming Pool": {"style": "pool", "size": Vector3(20, 3, 16), "color": Color(0.80, 0.80, 0.82), "accent": Color(0.25, 0.55, 0.85)},
	"Church": {"style": "church", "size": Vector3(14, 9, 16), "color": Color(0.95, 0.95, 0.93)},
	"Shrine": {"style": "shrine", "size": Vector3(12, 6, 12), "color": Color(0.78, 0.22, 0.12), "accent": Color(0.45, 0.30, 0.18)},
	"Train Station": {"style": "station", "size": Vector3(20, 7, 12), "color": Color(0.72, 0.58, 0.45), "accent": Color(0.25, 0.40, 0.30)},
	"Motel": {"style": "motel", "size": Vector3(18, 5, 12), "color": Color(0.85, 0.78, 0.62), "accent": Color(0.55, 0.30, 0.20)},
}

# One goal per block across the 5x5 grid (rows north->south, cols west->east).
# The central block is the Park (town green).
const GOAL_GRID := [
	["Train Station", "School", "Convenience Store", "Diner", "Motel"],
	["Hospital", "Library", "Bakery", "Bank", "Police Station"],
	["Drugstore", "Museum", "Park", "Post Office", "Fire Station"],
	["Church", "Starbucks", "McDonald's", "City Hall", "Town Office"],
	["Shrine", "Swimming Pool", "Supermarket", "Bookstore", "Gas Station"],
]

const BLOCK_CENTERS := [-108.0, -54.0, 0.0, 54.0, 108.0]   # world block centres

# Palettes for the procedural filler buildings, so the streets look varied.
const HOUSE_COLORS := [
	Color(0.85, 0.80, 0.70), Color(0.70, 0.78, 0.82), Color(0.82, 0.72, 0.68),
	Color(0.75, 0.80, 0.72), Color(0.88, 0.84, 0.74), Color(0.78, 0.74, 0.80),
	Color(0.66, 0.74, 0.66), Color(0.86, 0.78, 0.66), Color(0.62, 0.66, 0.72),
	Color(0.80, 0.66, 0.60), Color(0.74, 0.82, 0.84), Color(0.90, 0.86, 0.80),
]
const ROOF_COLORS := [
	Color(0.45, 0.28, 0.22), Color(0.30, 0.34, 0.40), Color(0.55, 0.42, 0.30),
	Color(0.35, 0.30, 0.32), Color(0.50, 0.30, 0.28), Color(0.32, 0.40, 0.36),
]
const SHOP_COLORS := [
	Color(0.62, 0.55, 0.45), Color(0.50, 0.58, 0.62), Color(0.68, 0.50, 0.45),
	Color(0.55, 0.62, 0.52), Color(0.66, 0.60, 0.50),
]
const OFFICE_COLORS := [
	Color(0.55, 0.60, 0.66), Color(0.60, 0.64, 0.62), Color(0.52, 0.58, 0.64),
]

var _mat_cache := {}   # color -> StandardMaterial3D (shared to cut resource churn)
var _glass_mat: StandardMaterial3D
var _house_i := 0
var _props: StaticBody3D   # holds collision shapes for lampposts / trees
var _roads: Node3D         # parent for road geometry + lampposts (baked)

# Intro-cinematic scratch state (used by the camera tween callbacks).
var _intro_cam: Camera3D
var _intro_title: CanvasLayer
var _io_center: Vector3
var _io_radius: float
var _io_height: float
var _im_p0: Vector3
var _im_p1: Vector3
var _im_l0: Vector3
var _im_l1: Vector3

var _dialogue: DialogueManager
var _greeter_npc: NPCInteraction
var _bgm_player: AudioStreamPlayer
var _bus_ref: Node3D
var _bus_origin_x: float


func _ready() -> void:
	_setup_input()

	_build_environment()
	_build_ground()
	_build_bounds()
	# Collision-only body that props (lampposts, trees) add their colliders to,
	# so the player can't walk through them even though their meshes get baked.
	_props = StaticBody3D.new()
	_props.name = "Props"
	add_child(_props)
	_build_roads()
	var goals: Dictionary = {}
	var goal_names: Array = []
	var layout := _layout_buildings()
	_build_town(layout, goals, goal_names)
	# Lampposts go in after the buildings so they can be placed in the gaps
	# between the frontage buildings rather than in front of a door.
	_build_lampposts(layout)

	# Merge all the static road + building geometry into one mesh grouped by
	# material. This turns ~1000+ draw calls into a few dozen so the WebGL2
	# (Compatibility) build runs smoothly on low-power devices like Chromebooks.
	_bake_static_meshes()

	# --- Spawn actors and managers -------------------------------------------
	_dialogue = DialogueManager.new()
	add_child(_dialogue)

	var player := PlayerController.new()
	player.position = PLAYER_SPAWN
	add_child(player)

	var camera_focus := CameraFocusManager.new()
	add_child(camera_focus)

	var goal := GoalManager.new()
	add_child(goal)

	# One shared microphone/recognizer for every NPC (only the nearest listens).
	var speech := SpeechInput.new()
	add_child(speech)

	camera_focus.setup(player.camera)
	goal.setup(player, _dialogue, camera_focus)
	_dialogue.set_score(0)

	_spawn_npcs(_dialogue, camera_focus, player, goal, goals, goal_names, speech)
	_play_intro(player)


# -----------------------------------------------------------------------------
# Opening cinematic: orbit the player from a high angle, hold a high-angle shot,
# then low pans across the buildings ringing the park, then hand over control.
# -----------------------------------------------------------------------------
func _play_intro(player: PlayerController) -> void:
	# Block all NPC interaction for the entire cinematic so NPCs can't overwrite
	# Matsubara's dialogue lines or hijack the dialogue panel.
	NPCInteraction._cinematic = true

	player.set_input_enabled(false)
	_intro_cam = Camera3D.new()
	add_child(_intro_cam)
	_intro_cam.current = true

	var player_start := player.global_position
	# Player faces north (toward town) from the moment he steps off the bus.
	player.rotation.y = 0.0
	# Hide player for the orbital shot; they step off the bus at the midpoint.
	player.visible = false
	# Hide the greeter NPC so it doesn't walk through the cinematic frame.
	if _greeter_npc != null:
		_greeter_npc.visible = false

	var focus := player.global_position + Vector3(0, 1.2, 0)

	# Bus parked at the curb: north face (z-1.25) flush with the curb at z=22.5,
	# so the bus centre sits at z=23.75, entirely on the road.
	var bus := _build_intro_bus()
	bus.position = Vector3(0, 0, 23.75)

	# Title card fades in 2 s into the orbit (fire-and-forget coroutine).
	_show_intro_title()

	# BGM starts with the title card and loops for the rest of the game.
	_bgm_player = AudioStreamPlayer.new()
	add_child(_bgm_player)
	_bgm_player.stream = _make_bgm()
	_bgm_player.volume_db = -10.0
	_bgm_player.play()

	# 1) High-angle orbit — continuous half-turn over 11 s (runs in background).
	_intro_orbit(focus, 14.0, 26.0, -PI * 0.5, PI * 0.5, 11.0)
	# At the midpoint the player steps off the bus and walks to their start position.
	await get_tree().create_timer(5.5).timeout
	player.global_position = Vector3(bus.position.x + 2.5, 0.0, bus.position.z - 1.5)
	player.rotation.y = 0.0
	player.visible = true
	var wt := create_tween()
	wt.set_trans(Tween.TRANS_LINEAR)
	wt.tween_property(player, "global_position", player_start, 5.0)
	await get_tree().create_timer(5.5).timeout
	player.rotation.y = PI  # face south — toward the camera for his introduction

	# 2) Hard cut to side bus shot.
	_intro_cam.position = Vector3(0, 2.0, 32)
	_intro_cam.look_at(Vector3(0, 1.5, 23.75), Vector3.UP)
	await get_tree().create_timer(0.6).timeout

	# 3) Engine starts, bus rumbles for 1 s, then drives off camera-left.
	_bus_ref = bus
	_bus_origin_x = bus.position.x
	var engine := AudioStreamPlayer.new()
	add_child(engine)
	engine.stream = _make_engine_sound()
	engine.volume_db = -4.0
	engine.play()

	var rt := create_tween()
	rt.tween_method(_apply_bus_rumble, 0.0, 0.5, 0.5)
	await rt.finished
	bus.position = Vector3(_bus_origin_x, 0.0, bus.position.z)

	var bt := create_tween()
	bt.set_ease(Tween.EASE_IN)
	bt.set_trans(Tween.TRANS_SINE)
	bt.tween_property(bus, "position:x", -55.0, 4.5)
	# Engine pitch rises as the bus accelerates away.
	var rv := create_tween()
	rv.tween_property(engine, "pitch_scale", 2.2, 4.0)
	await bt.finished

	var ef := create_tween()
	ef.tween_property(engine, "volume_db", -60.0, 0.8)
	await ef.finished
	engine.queue_free()
	bus.queue_free()

	# 4) Slow push-in to the player's face (5 s) — Matsubara introduces himself.
	var face_pos := Vector3(0, 2.5, 24)
	_dialogue.show_text("Matsubara kun", "Hi! I'm Matsubara kun! This is my first time in America.")
	await _intro_move(Vector3(0, 2.0, 32), face_pos, focus, focus, 5.0)
	await get_tree().create_timer(5.0).timeout

	# 5) Town pan shots — keep Matsubara south so he still faces camera when it returns in step 6.
	player.rotation.y = PI
	_dialogue.show_text("Matsubara kun", "Wow! America is so big!")
	await _intro_move(Vector3(0, 4, -12), Vector3(0, 4, -12),
			Vector3(-35, 5, -54), Vector3(35, 5, -54), 3.8)
	await _intro_move(Vector3(12, 4, 0), Vector3(12, 4, 0),
			Vector3(54, 5, -35), Vector3(54, 5, 35), 3.8)

	# 6) Smooth move to a tight close-up of Matsubara kun's face.
	var close_pos := Vector3(0, 1.7, 19.5)
	var close_look := player.global_position + Vector3(0, 0.8, 0)
	await _intro_move(Vector3(12, 4, 0), close_pos,
			Vector3(54, 5, 35), close_look, 2.0)

	# Matsubara asks for help — buttons appear alongside the question.
	var idx: int = await _dialogue.show_options("Matsubara kun",
			"I don't know where anything is! Will you help me?",
			["Help him", "Don't help him"])

	if idx != 0:
		# "Don't help him" — show "Please?" then give one more chance.
		_dialogue.show_text("Matsubara kun", "Please?")
		await get_tree().create_timer(2.0).timeout
		idx = await _dialogue.show_options(
				"Matsubara kun", "Please?", ["Help him", "Don't help him"])
		if idx != 0:
			# Refused twice — Matsubara says goodbye and the game ends.
			_dialogue.show_text("Matsubara kun", "Oh that's too bad. Bye.")
			await get_tree().create_timer(3.0).timeout
			_dialogue.hide_dialogue()
			_fade_out_intro_title()
			NPCInteraction._cinematic = false
			player.visible = false
			_intro_cam.queue_free()
			_intro_cam = null
			get_tree().quit()
			return

	# Player agreed (first try or after "Please?").
	# 7) Matsubara thanks the player and hints at what to do next.
	_dialogue.show_text("Matsubara kun", "Thank you! Maybe I should ask somebody for directions.")
	await get_tree().create_timer(3.5).timeout
	_dialogue.hide_dialogue()

	# 8) Greeter NPC re-appears and resumes patrolling; camera pans to reveal them.
	if _greeter_npc != null:
		_greeter_npc.visible = true
	# Keep facing south — the tween at handoff will rotate him north.
	player.rotation.y = PI
	await _intro_move(close_pos, Vector3(12, 3, 26),
			close_look, Vector3(5, 1.5, 18), 2.5)
	await get_tree().create_timer(2.0).timeout

	# Unblock NPCs and hand control back to the player.
	NPCInteraction._cinematic = false
	_fade_out_intro_title()
	player.visible = true
	_intro_cam.queue_free()
	_intro_cam = null
	player.camera.current = true
	player.set_input_enabled(true)
	_fade_out_bgm()


func _fade_out_bgm() -> void:
	await get_tree().create_timer(3.0).timeout
	if not is_instance_valid(_bgm_player):
		return
	var ft := create_tween()
	ft.tween_property(_bgm_player, "volume_db", -60.0, 2.0)
	await ft.finished
	if is_instance_valid(_bgm_player):
		_bgm_player.stop()
	_start_ambient()


func _start_ambient() -> void:
	var hum := AudioStreamPlayer.new()
	add_child(hum)
	hum.stream = _make_ambient_hum()
	hum.volume_db = -30.0
	hum.play()
	_ambient_bird_loop()
	_ambient_traffic_loop()


func _ambient_bird_loop() -> void:
	while is_inside_tree():
		await get_tree().create_timer(randf_range(14.0, 25.0)).timeout
		if not is_inside_tree():
			return
		var chirp := AudioStreamPlayer.new()
		add_child(chirp)
		chirp.stream = _make_bird_chirp()
		chirp.volume_db = randf_range(-28.0, -20.0)
		chirp.play()
		await chirp.finished
		chirp.queue_free()


func _ambient_traffic_loop() -> void:
	while is_inside_tree():
		await get_tree().create_timer(randf_range(8.0, 20.0)).timeout
		if not is_inside_tree():
			return
		var car := AudioStreamPlayer.new()
		add_child(car)
		car.stream = _make_traffic_whoosh()
		car.volume_db = -22.0
		car.play()
		await car.finished
		car.queue_free()




func _make_ambient_hum() -> AudioStreamWAV:
	var rate := 11025
	var num_samples := int(4.0 * rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var prev := 0.0
	for s in num_samples:
		prev = prev * 0.93 + randf_range(-1.0, 1.0) * 0.07
		var iv := int(clampf(prev, -1.0, 1.0) * 32767.0)
		data[s * 2]     = iv & 0xFF
		data[s * 2 + 1] = (iv >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format     = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate   = rate
	wav.stereo     = false
	wav.data       = data
	wav.loop_mode  = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end   = num_samples - 1
	return wav


func _make_bird_chirp() -> AudioStreamWAV:
	var rate      := 11025
	var base_freq := randf_range(1800.0, 3000.0)
	var num_notes := randi_range(3, 6)
	var note_s    := int(0.07 * rate)
	var gap_s     := int(0.03 * rate)
	var freqs: Array[float] = []
	var f := base_freq
	for _i in num_notes:
		freqs.append(f)
		f += randf_range(-350.0, 500.0)
		f = clampf(f, 1400.0, 4200.0)
	var num_samples := num_notes * note_s + (num_notes - 1) * gap_s
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var phase := 0.0
	var s := 0
	for ni in num_notes:
		var freq: float = freqs[ni]
		var peak := freq + randf_range(200.0, 600.0)
		for ns in note_s:
			var p := float(ns) / float(note_s)
			var cur_freq := freq + (peak - freq) * sin(p * PI)
			var env := sin(p * PI)
			var iv := int(clampf(sin(phase) * env * 0.65, -1.0, 1.0) * 32767.0)
			data[s * 2]     = iv & 0xFF
			data[s * 2 + 1] = (iv >> 8) & 0xFF
			phase += TAU * cur_freq / float(rate)
			s += 1
		if ni < num_notes - 1:
			for _g in gap_s:
				data[s * 2]     = 0
				data[s * 2 + 1] = 0
				phase += TAU * freq / float(rate)
				s += 1
	var wav := AudioStreamWAV.new()
	wav.format   = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo   = false
	wav.data     = data
	return wav


func _make_traffic_whoosh() -> AudioStreamWAV:
	var rate := 11025
	var num_samples := int(2.0 * rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var prev := 0.0
	for s in num_samples:
		var env := sin(float(s) / float(num_samples) * PI)
		prev = prev * 0.85 + randf_range(-1.0, 1.0) * 0.15
		var iv := int(clampf(prev * env, -1.0, 1.0) * 32767.0)
		data[s * 2]     = iv & 0xFF
		data[s * 2 + 1] = (iv >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format   = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo   = false
	wav.data     = data
	return wav


# Orbit the intro camera around `center` at the given radius/height, sweeping the
# angle a0 -> a1 while always looking at the centre.
func _intro_orbit(center: Vector3, radius: float, height: float,
		a0: float, a1: float, dur: float) -> void:
	_io_center = center
	_io_radius = radius
	_io_height = height
	_apply_intro_orbit(a0)
	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE)
	t.set_ease(Tween.EASE_IN_OUT)
	t.tween_method(_apply_intro_orbit, a0, a1, dur)
	await t.finished


func _apply_intro_orbit(a: float) -> void:
	if _intro_cam == null:
		return
	_intro_cam.position = _io_center + Vector3(cos(a) * _io_radius, _io_height, sin(a) * _io_radius)
	_intro_cam.look_at(_io_center, Vector3.UP)


# Slide the intro camera from p0->p1 while its look target slides l0->l1.
func _intro_move(p0: Vector3, p1: Vector3, l0: Vector3, l1: Vector3, dur: float) -> void:
	_im_p0 = p0
	_im_p1 = p1
	_im_l0 = l0
	_im_l1 = l1
	_apply_intro_move(0.0)
	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE)
	t.set_ease(Tween.EASE_IN_OUT)
	t.tween_method(_apply_intro_move, 0.0, 1.0, dur)
	await t.finished


func _apply_intro_move(f: float) -> void:
	if _intro_cam == null:
		return
	_intro_cam.position = _im_p0.lerp(_im_p1, f)
	_intro_cam.look_at(_im_l0.lerp(_im_l1, f), Vector3.UP)


# Oscillate the bus around its parked position to simulate engine vibration.
func _apply_bus_rumble(t: float) -> void:
	if not is_instance_valid(_bus_ref):
		return
	_bus_ref.position.x = _bus_origin_x + sin(t * 48.0) * 0.025
	_bus_ref.position.y = absf(sin(t * 67.0)) * 0.01


# Happy whimsical background music, procedurally synthesised as a looping WAV.
# Bell/xylophone timbre (decaying sine + 2nd harmonic). Loops seamlessly because
# all notes decay to silence well before the loop point.
func _make_bgm() -> AudioStreamWAV:
	var rate := 11025
	var beat := 0.25   # eighth note at 120 BPM

	# [frequency_hz, eighth_note_count]  — 0.0 = rest
	# Four 16-beat phrases = 64 eighth notes = 16 s at 120 BPM before looping.
	var seq: Array = [
		# Phrase A — bright opening
		[659.25, 1], [783.99, 1], [880.00, 2], [783.99, 1], [659.25, 1], [523.25, 2],
		[587.33, 1], [659.25, 1], [783.99, 2], [659.25, 2], [0.0, 2],
		# Phrase B — stepwise climb and fall
		[523.25, 1], [587.33, 1], [659.25, 1], [698.46, 1], [783.99, 4],
		[698.46, 1], [659.25, 1], [587.33, 1], [523.25, 1], [659.25, 2], [0.0, 2],
		# Phrase C — soar into upper register
		[659.25, 1], [783.99, 1], [880.00, 1], [987.77, 1], [1046.50, 2], [880.00, 2],
		[783.99, 1], [880.00, 1], [783.99, 1], [698.46, 1], [659.25, 2], [523.25, 2],
		# Phrase D — triumphant finish, land on long tonic
		[523.25, 1], [659.25, 1], [783.99, 1], [880.00, 1], [987.77, 2], [1046.50, 2],
		[880.00, 1], [783.99, 1], [698.46, 1], [659.25, 1], [523.25, 4],
	]

	var total_beats := 0
	for entry in seq:
		total_beats += int(entry[1])
	var total_samples := int(total_beats * beat * rate)

	var data := PackedByteArray()
	data.resize(total_samples * 2)
	data.fill(0)

	var pos := 0
	for entry in seq:
		var freq: float = entry[0]
		var beats: int   = int(entry[1])
		var note_samples := int(beats * beat * rate)
		if freq > 0.0:
			var decay := 5.0 + freq * 0.006
			var play_samples := mini(note_samples, int((beats * beat - 0.018) * rate))
			for s in play_samples:
				if pos + s >= total_samples:
					break
				var t := float(s) / float(rate)
				var env := exp(-t * decay)
				var v := sin(TAU * freq * t) * env * 0.32
				v += sin(TAU * freq * 2.0 * t) * env * 0.09
				var iv := int(clampf(v, -1.0, 1.0) * 32767.0)
				var si := (pos + s) * 2
				data[si]     = iv & 0xFF
				data[si + 1] = (iv >> 8) & 0xFF
		pos += note_samples

	var wav := AudioStreamWAV.new()
	wav.format   = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo   = false
	wav.data     = data
	wav.loop_mode  = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end   = total_samples - 1
	return wav


# Low-frequency engine idle loop. Period = 150 samples at 11025 Hz → 73.5 Hz
# fundamental. All harmonics used (×0.5, ×1, ×2, ×3) divide evenly into the
# 1500-sample loop so there is no click at the loop point.
func _make_engine_sound() -> AudioStreamWAV:
	var rate    := 11025
	var period  := 150                  # samples per fundamental cycle
	var fund    := float(rate) / float(period)   # 73.5 Hz
	var num_samples := period * 10      # 10 cycles = 1500 samples

	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for s in num_samples:
		var t := float(s) / float(rate)
		var v := sin(TAU * fund * t)       * 0.28
		v += sin(TAU * fund * 2.0 * t)    * 0.12
		v += sin(TAU * fund * 3.0 * t)    * 0.07
		v += sin(TAU * fund * 0.5 * t)    * 0.06
		var iv := int(clampf(v, -1.0, 1.0) * 32767.0)
		data[s * 2]     = iv & 0xFF
		data[s * 2 + 1] = (iv >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.format   = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo   = false
	wav.data     = data
	wav.loop_mode  = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end   = num_samples - 1
	return wav


# Spawn a CanvasLayer title card ("matsubara kun") and start fading it in after
# 2 seconds. Returns immediately; the fade runs as a fire-and-forget coroutine.
func _show_intro_title() -> void:
	_intro_title = CanvasLayer.new()
	add_child(_intro_title)
	var lbl := Label.new()
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 128)
	lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	lbl.add_theme_constant_override("outline_size", 28)
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.05))
	lbl.text = "Matsubara kun"
	lbl.modulate.a = 0.0
	_intro_title.add_child(lbl)
	_fade_in_title_async(lbl)


func _fade_in_title_async(lbl: Label) -> void:
	await get_tree().create_timer(2.0).timeout
	if not is_instance_valid(lbl):
		return
	var t := create_tween()
	t.set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "modulate:a", 1.0, 1.5)
	await t.finished
	# Hold for 3 seconds then fade out automatically.
	await get_tree().create_timer(3.0).timeout
	if not is_instance_valid(lbl):
		return
	var t2 := create_tween()
	t2.tween_property(lbl, "modulate:a", 0.0, 1.0)


func _fade_out_intro_title() -> void:
	if _intro_title == null:
		return
	var layer := _intro_title
	_intro_title = null
	if layer.get_child_count() == 0:
		layer.queue_free()
		return
	var lbl := layer.get_child(0)
	var t := create_tween()
	t.tween_property(lbl, "modulate:a", 0.0, 0.8)
	t.tween_callback(layer.queue_free)


# Procedural city bus for the opening cinematic.
# Oriented east-west (long axis = X). South face (local +Z) faces the camera.
# Windows are semi-transparent so the park and player show through.
func _build_intro_bus() -> Node3D:
	var b := Node3D.new()
	add_child(b)

	var green  := Color(0.14, 0.48, 0.22)
	var dark_g := Color(0.08, 0.30, 0.13)
	var black  := Color(0.12, 0.12, 0.14)
	var chrome := Color(0.80, 0.80, 0.82)

	# == Structural frame (no solid south or north wall — park visible through) ==
	# Roof slab
	_box(b, Vector3(8.0, 0.22, 2.5), Vector3(0, 2.62, 0), dark_g)
	# Roof-mounted AC unit
	_box(b, Vector3(1.8, 0.30, 0.9), Vector3(-1.0, 2.90, -0.2), dark_g)
	# Floor / underbody slab
	_box(b, Vector3(8.0, 0.32, 2.5), Vector3(0, 0.56, 0), green)
	# East end wall + dark destination-sign band above
	_box(b, Vector3(0.32, 2.06, 2.5), Vector3(4.16, 1.39, 0), green)
	_box(b, Vector3(0.32, 0.38, 2.5), Vector3(4.16, 2.61, 0), dark_g)
	# West end wall
	_box(b, Vector3(0.32, 2.44, 2.5), Vector3(-4.16, 1.58, 0), green)

	# == South face: lower body strip (tall), three pillars, small windows, header ==
	# Windows: 1.0 × 0.80, centre y=1.75  →  bottom y=1.35, top y=2.15
	# Lower strip: floor top (y=0.72) to window bottom (y=1.35), h=0.63, cy=1.035
	_box(b, Vector3(7.4, 0.63, 0.14), Vector3(0, 1.035, 1.26), green)
	# Upper header: window top (y=2.15) to roof bottom (y=2.51), h=0.36, cy=2.33
	_box(b, Vector3(7.4, 0.36, 0.14), Vector3(0, 2.33, 1.26), dark_g)
	# Three vertical A-pillars (match window height)
	for px in [-2.0, 0.0, 2.0]:
		_box(b, Vector3(0.18, 0.80, 0.14), Vector3(px, 1.75, 1.27), black)
	# Four small window panes — semi-transparent so park and player show through
	var win_mat := StandardMaterial3D.new()
	win_mat.albedo_color = Color(0.38, 0.58, 0.82, 0.22)
	win_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	win_mat.metallic = 0.25
	win_mat.roughness = 0.12
	for wx in [-3.0, -1.0, 1.0, 3.0]:
		_box_mat(b, Vector3(1.0, 0.80, 0.08), Vector3(wx, 1.75, 1.27), win_mat)
	# Bumper along south face base
	_box(b, Vector3(7.6, 0.20, 0.22), Vector3(0, 0.38, 1.30), chrome)
	# White decorative stripe just below windows
	_box(b, Vector3(7.4, 0.10, 0.12), Vector3(0, 1.30, 1.27), Color(0.92, 0.92, 0.92))

	# == North face (park-facing): mirrors south face so bus is solid from all angles ==
	_box(b, Vector3(7.4, 0.63, 0.14), Vector3(0, 1.035, -1.26), green)
	_box(b, Vector3(7.4, 0.36, 0.14), Vector3(0, 2.33, -1.26), dark_g)
	for px in [-2.0, 0.0, 2.0]:
		_box(b, Vector3(0.18, 0.80, 0.14), Vector3(px, 1.75, -1.27), black)
	for wx in [-3.0, -1.0, 1.0, 3.0]:
		_box_mat(b, Vector3(1.0, 0.80, 0.08), Vector3(wx, 1.75, -1.27), win_mat)
	_box(b, Vector3(7.6, 0.20, 0.22), Vector3(0, 0.38, -1.30), chrome)
	_box(b, Vector3(7.4, 0.10, 0.12), Vector3(0, 1.30, -1.27), Color(0.92, 0.92, 0.92))

	# == Wheels (long axis = X, so axle runs along Z; rotation.x = PI/2) ==
	for wv in [Vector3(-3.1, 0.44, -0.92), Vector3(3.1, 0.44, -0.92),
			   Vector3(-3.1, 0.44,  0.92), Vector3(3.1, 0.44,  0.92)]:
		var w := _cylinder(b, 0.44, 0.32, wv, black)
		w.rotation.x = PI * 0.5

	# == Passengers — one per window, seated, visible through south glass ==
	var shirts := [Color(0.20, 0.25, 0.62), Color(0.70, 0.28, 0.22),
				   Color(0.26, 0.58, 0.30), Color(0.58, 0.34, 0.64)]
	var skins  := [Color(0.90, 0.75, 0.60), Color(0.55, 0.42, 0.32),
				   Color(0.88, 0.72, 0.58), Color(0.40, 0.30, 0.25)]
	for i in range(4):
		var px: float = [-3.0, -1.0, 1.0, 3.0][i]
		_box(b, Vector3(0.46, 0.56, 0.24), Vector3(px, 1.15, 0.0), shirts[i])
		_sphere(b, 0.19, Vector3(px, 1.82, 0.0), skins[i])

	return b


# Place at least one talkable NPC on every street (each grid line), most of them
# patrolling a short stretch of that street's sidewalk. Each gives directions
# from its own position; they share the one microphone.
func _spawn_npcs(dialogue: DialogueManager, camera_focus: CameraFocusManager,
		player: PlayerController, goal: GoalManager,
		goals: Dictionary, goal_names: Array, speech: SpeechInput) -> void:
	var palette := [
		[Color(0.80, 0.30, 0.25), Color(0.20, 0.20, 0.25), Color(0.10, 0.08, 0.05)],
		[Color(0.20, 0.45, 0.65), Color(0.30, 0.28, 0.25), Color(0.35, 0.22, 0.10)],
		[Color(0.30, 0.55, 0.35), Color(0.20, 0.20, 0.22), Color(0.15, 0.12, 0.08)],
		[Color(0.70, 0.60, 0.20), Color(0.25, 0.25, 0.30), Color(0.45, 0.30, 0.18)],
		[Color(0.55, 0.35, 0.60), Color(0.22, 0.22, 0.26), Color(0.10, 0.08, 0.06)],
		[Color(0.85, 0.55, 0.25), Color(0.28, 0.26, 0.24), Color(0.12, 0.10, 0.07)],
	]
	var k := 0
	# One NPC in front of every block (on the inner-street sidewalk, where the
	# block's frontage is) so at least one townsperson is within visual range of
	# every building. Each patrols a short stretch of that sidewalk.
	for j in BLOCK_CENTERS.size():
		for i in BLOCK_CENTERS.size():
			var cx: float = BLOCK_CENTERS[i]
			var cz: float = BLOCK_CENTERS[j]
			if cx == 0.0 and cz == 0.0:
				continue   # the Park itself; covered by the spawn greeter below
			var npos: Vector3
			var p: PackedVector3Array
			if absf(cx) >= absf(cz):
				# Frontage faces a N-S street: stand on its sidewalk, patrol along z.
				var sx: float = cx - signf(cx) * (HALF_BLOCK - SW_OFF)
				npos = Vector3(sx, 0, cz)
				p = PackedVector3Array([Vector3(sx, 0, cz - 12), Vector3(sx, 0, cz + 12)])
			else:
				# Frontage faces an E-W street: stand on its sidewalk, patrol along x.
				var sz: float = cz - signf(cz) * (HALF_BLOCK - SW_OFF)
				npos = Vector3(cx, 0, sz)
				p = PackedVector3Array([Vector3(cx - 12, 0, sz), Vector3(cx + 12, 0, sz)])
			_make_npc(npos, p, palette[k % palette.size()],
					dialogue, camera_focus, player, goal, goals, goal_names, speech)
			k += 1
	# A greeter by the Park, near where the player spawns.
	_greeter_npc = _make_npc(Vector3(5, 0, 18),
			PackedVector3Array([Vector3(-6, 0, 18), Vector3(8, 0, 18)]),
			palette[k % palette.size()],
			dialogue, camera_focus, player, goal, goals, goal_names, speech)


func _make_npc(pos: Vector3, p: PackedVector3Array, c: Array,
		dialogue: DialogueManager, camera_focus: CameraFocusManager,
		player: PlayerController, goal: GoalManager,
		goals: Dictionary, goal_names: Array, speech: SpeechInput) -> NPCInteraction:
	var npc := NPCInteraction.new()
	npc.shirt_color = c[0]
	npc.pants_color = c[1]
	npc.hair_color = c[2]
	npc.speed = 1.8
	npc.path = p
	npc.position = pos
	add_child(npc)
	npc.setup(dialogue, camera_focus, player, goal, goals, goal_names, speech)
	return npc


# -----------------------------------------------------------------------------
# Static-geometry baking: collect every MeshInstance3D under Roads + Town and
# merge them into a single MeshInstance3D with one surface per material. The
# building collision boxes (CollisionShape3D) and name signs (Label3D) are left
# untouched, and the player/NPC (under their own nodes) are not baked.
# -----------------------------------------------------------------------------
func _bake_static_meshes() -> void:
	var tools := {}        # Material -> SurfaceTool
	var order := []        # keep a stable material order
	for root_name in ["Roads", "Town"]:
		var root := get_node_or_null(NodePath(root_name))
		if root == null:
			continue
		var meshes: Array = []
		_collect_mesh_instances(root, meshes)
		for mi in meshes:
			var mat: Material = mi.material_override
			var mesh: Mesh = mi.mesh
			if mat == null or mesh == null:
				continue
			if not tools.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[mat] = st
				order.append(mat)
			tools[mat].append_from(mesh, 0, mi.global_transform)
			mi.queue_free()

	var arr := ArrayMesh.new()
	for mat in order:
		tools[mat].commit(arr)
		arr.surface_set_material(arr.get_surface_count() - 1, mat)
	var inst := MeshInstance3D.new()
	inst.name = "WorldMesh"
	inst.mesh = arr
	add_child(inst)


func _collect_mesh_instances(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is MeshInstance3D:
			out.append(c)
		else:
			_collect_mesh_instances(c, out)


# -----------------------------------------------------------------------------
# Input
# -----------------------------------------------------------------------------
func _setup_input() -> void:
	# Keyboard only — WASD or the arrow keys. No mouse needed anywhere.
	_add_key_action("move_forward", [KEY_W, KEY_UP])
	_add_key_action("move_back", [KEY_S, KEY_DOWN])
	_add_key_action("turn_left", [KEY_A, KEY_LEFT])
	_add_key_action("turn_right", [KEY_D, KEY_RIGHT])
	_add_key_action("interact", [KEY_E, KEY_SPACE])


func _add_key_action(action_name: String, keys: Array) -> void:
	if InputMap.has_action(action_name):
		InputMap.erase_action(action_name)
	InputMap.add_action(action_name)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action_name, ev)


# -----------------------------------------------------------------------------
# Environment + ground
# -----------------------------------------------------------------------------
func _build_environment() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -35, 0)
	light.shadow_enabled = false   # off for cheap rendering on low-power web devices
	add_child(light)

	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	mesh.mesh = plane
	mesh.material_override = _mat(Color(0.40, 0.58, 0.33))
	ground.add_child(mesh)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	col.shape = box
	col.position.y = -0.5
	ground.add_child(col)
	add_child(ground)


# Invisible walls ringing the town so the player can't walk off the edge.
func _build_bounds() -> void:
	var bounds := StaticBody3D.new()
	bounds.name = "Bounds"
	var b := EXT + 8.0      # just outside the outermost street
	var h := 12.0
	for spec in [
		[Vector3(0, h * 0.5, -b), Vector3(b * 2, h, 3)],   # north
		[Vector3(0, h * 0.5, b), Vector3(b * 2, h, 3)],    # south
		[Vector3(-b, h * 0.5, 0), Vector3(3, h, b * 2)],   # west
		[Vector3(b, h * 0.5, 0), Vector3(3, h, b * 2)],    # east
	]:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = spec[1]
		col.shape = shape
		col.position = spec[0]
		bounds.add_child(col)
	add_child(bounds)


# Add a vertical collision cylinder to the shared Props body (for a lamppost or
# tree trunk) so the player bumps into it instead of passing through.
func _prop_collider(pos: Vector3, radius: float, height: float) -> void:
	if _props == null:
		return
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	col.position = pos + Vector3(0, height * 0.5, 0)
	_props.add_child(col)


# Add a box collider (for benches etc.) to the shared Props body.
func _prop_box(center: Vector3, size: Vector3, yaw: float) -> void:
	if _props == null:
		return
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = center
	col.rotation.y = yaw
	_props.add_child(col)


# -----------------------------------------------------------------------------
# Roads: full grid of asphalt, with sidewalks that run along the streets but
# STOP at each intersection (replaced there by crosswalks), lampposts out on the
# sidewalks (never on the road), and stop signs at the downtown intersections.
# -----------------------------------------------------------------------------
func _build_roads() -> void:
	var roads := Node3D.new()
	roads.name = "Roads"
	add_child(roads)
	_roads = roads

	# Asphalt grid (the crossing slabs simply overlap at intersections). Kept
	# nearly flush with the ground so the player walks on it without sinking in.
	for gx in GRID:
		_slab(roads, Vector3(ROAD_W, 0.06, EXT * 2), Vector3(gx, 0.0, 0), ASPHALT)
	for gz in GRID:
		_slab(roads, Vector3(EXT * 2, 0.06, ROAD_W), Vector3(0, 0.0, gz), ASPHALT)

	_build_sidewalks(roads)
	_build_lane_lines(roads)
	for gx in GRID:
		for gz in GRID:
			_build_crosswalks(roads, gx, gz)

	_build_stop_signs(roads)


# Sidewalk strips flanking every street, split into segments so they never run
# across the road at an intersection. The gap left at each crossing is exactly
# the road, where a crosswalk goes instead.
func _build_sidewalks(roads: Node3D) -> void:
	for gx in GRID:
		for side in [-1.0, 1.0]:
			var x: float = gx + side * SW_OFF
			for seg in _segments():
				_slab(roads, Vector3(SW_W, 0.10, seg.y - seg.x),
						Vector3(x, 0.0, (seg.x + seg.y) * 0.5), SIDEWALK)
	for gz in GRID:
		for side in [-1.0, 1.0]:
			var z: float = gz + side * SW_OFF
			for seg in _segments():
				_slab(roads, Vector3(seg.y - seg.x, 0.10, SW_W),
						Vector3((seg.x + seg.y) * 0.5, 0.0, z), SIDEWALK)


# The runs of clear pavement between the road crossings, as [start, end] pairs.
func _segments() -> Array:
	var bounds := [-EXT]
	for line in GRID:
		bounds.append(line - HALF)
		bounds.append(line + HALF)
	bounds.append(EXT)
	var segs := []
	var i := 0
	while i + 1 < bounds.size():
		if bounds[i + 1] - bounds[i] > 0.5:
			segs.append(Vector2(bounds[i], bounds[i + 1]))
		i += 2
	return segs


# Dashed center lines on the four downtown "main streets" (±32), broken at
# intersections.
func _build_lane_lines(roads: Node3D) -> void:
	for line in [-HALF_BLOCK, HALF_BLOCK]:
		var p := -EXT + 4.0
		while p < EXT:
			if not _near_grid(p, HALF + 2.0):
				_slab(roads, Vector3(0.35, 0.04, 2.4), Vector3(line, 0.06, p), LINE)
				_slab(roads, Vector3(2.4, 0.04, 0.35), Vector3(p, 0.06, line), LINE)
			p += 5.0


# Four zebra crosswalks (one per arm) painted on the road at an intersection.
func _build_crosswalks(roads: Node3D, gx: float, gz: float) -> void:
	for sx in [-1.0, 1.0]:
		_crosswalk(roads, Vector3(gx + sx * SW_OFF, 0.06, gz), true)   # across the E-W road
	for sz in [-1.0, 1.0]:
		_crosswalk(roads, Vector3(gx, 0.06, gz + sz * SW_OFF), false)  # across the N-S road


func _crosswalk(roads: Node3D, pos: Vector3, along_z: bool) -> void:
	var span := ROAD_W - 1.0
	for i in 4:
		var o := -1.65 + 1.1 * float(i)
		if along_z:
			_slab(roads, Vector3(0.45, 0.04, span), pos + Vector3(o, 0, 0), LINE)
		else:
			_slab(roads, Vector3(span, 0.04, 0.45), pos + Vector3(0, 0, o), LINE)


# Lampposts on the GRASSY edge of the sidewalk, placed in the GAPS between the
# frontage buildings (never in front of a door). For each interior street we scan
# along it and drop a lamp wherever the frontage has an opening, spaced out and
# kept off the intersections.
func _build_lampposts(layout: Array) -> void:
	var edge := HALF + SW_W + 0.3   # outer (grass) edge of the sidewalk = 7.0
	for line in [-81.0, -HALF_BLOCK, HALF_BLOCK, 81.0]:
		var s := 1.0 if line > 0.0 else -1.0          # build on the outer side
		_lamps_in_gaps(layout, true, line, s, line + s * edge)   # N-S street (runs along z)
		_lamps_in_gaps(layout, false, line, s, line + s * edge)  # E-W street (runs along x)


# Walk a single street edge and place lamps where the frontage is open.
#   vertical=true  -> street is the line x=`line`, lamps sit at x=`perp`, vary z.
#   vertical=false -> street is the line z=`line`, lamps sit at z=`perp`, vary x.
func _lamps_in_gaps(layout: Array, vertical: bool, line: float, s: float, perp: float) -> void:
	# Collect the along-axis intervals occupied by the frontage buildings.
	var blocked := []
	for cfg in layout:
		if cfg.has("prop"):
			continue
		var fp := _footprint(cfg)
		var bperp: float = fp.x if vertical else fp.z
		var hperp: float = fp.hx if vertical else fp.hz
		if signf(bperp - line) != s:
			continue
		# Only the front row: its near edge is just past the sidewalk.
		var near := absf(bperp - s * hperp - line)
		if near < 5.0 or near > 13.0:
			continue
		var along: float = fp.z if vertical else fp.x
		var halong: float = fp.hz if vertical else fp.hx
		blocked.append(Vector2(along - halong - 0.8, along + halong + 0.8))

	# March along the street at a regular spacing, nudging each lamp to the
	# nearest opening so it lands in a gap, never in front of a door. Skip it if
	# the frontage is solid nearby or the spot falls in an intersection.
	var t := -EXT + 14.0
	while t <= EXT - 14.0:
		var spot := _nearest_open(blocked, t, 7.0)
		if spot < 1.0e8 and not _near_grid(spot, 7.0):
			if vertical:
				_add_lamppost(_roads, Vector3(perp, 0, spot))
			else:
				_add_lamppost(_roads, Vector3(spot, 0, perp))
		t += 24.0


func _covered(intervals: Array, v: float) -> bool:
	for iv in intervals:
		if v >= iv.x and v <= iv.y:
			return true
	return false


# Nearest along-axis position to `t` (within +/- maxshift) that no frontage
# building covers, or a huge number if the frontage is solid there.
func _nearest_open(intervals: Array, t: float, maxshift: float) -> float:
	var d := 0.0
	while d <= maxshift:
		if not _covered(intervals, t + d):
			return t + d
		if not _covered(intervals, t - d):
			return t - d
		d += 1.0
	return 1.0e9


# Stop signs on the corners of the four busy downtown intersections (the green's
# corners). Each is a pole topped with a red octagon.
func _build_stop_signs(roads: Node3D) -> void:
	for gx in [-HALF_BLOCK, HALF_BLOCK]:
		for gz in [-HALF_BLOCK, HALF_BLOCK]:
			# Inner corner (green side) of the intersection, on the sidewalk.
			var x: float = gx - signf(gx) * SW_OFF
			var z: float = gz - signf(gz) * SW_OFF
			_add_stop_sign(roads, Vector3(x, 0, z))


func _add_stop_sign(parent: Node3D, pos: Vector3) -> void:
	_cylinder(parent, 0.1, 3.0, pos + Vector3(0, 1.5, 0), Color(0.55, 0.55, 0.58))  # pole
	var sign := MeshInstance3D.new()
	var oct := CylinderMesh.new()
	oct.top_radius = 0.65
	oct.bottom_radius = 0.65
	oct.height = 0.12
	oct.radial_segments = 8          # octagon
	sign.mesh = oct
	sign.material_override = _mat(Color(0.80, 0.08, 0.08))
	sign.position = pos + Vector3(0, 2.8, 0)
	sign.rotation = Vector3(PI * 0.5, PI / 8.0, 0)  # face outward, flats level
	parent.add_child(sign)
	_prop_collider(pos, 0.18, 3.0)   # solid pole


func _near_grid(v: float, r: float) -> bool:
	for line in GRID:
		if absf(v - line) < r:
			return true
	return false


# -----------------------------------------------------------------------------
# Town: spawn every building, collecting the goals into a name->node dictionary.
# -----------------------------------------------------------------------------
func _build_town(layout: Array, goals: Dictionary, goal_names: Array) -> void:
	var town := Node3D.new()
	town.name = "Town"
	add_child(town)

	for cfg in layout:
		# Courtyard greenery placed in the (road-less) centre of a block instead
		# of a landlocked building.
		if cfg.has("prop"):
			if cfg.prop == "tree":
				_tree(town, cfg.pos)
			else:
				_bench(town, cfg.pos, cfg.yaw)
			continue
		var node := _spawn_building(cfg)
		node.position = cfg.pos
		# Park stays unrotated so its tree/bench/fountain colliders (added to the
		# Props body in world space) line up with the meshes.
		node.rotation.y = 0.0 if cfg.style == "park" else _park_or_street_facing(cfg.pos)
		town.add_child(node)
		_merge_meshes(node)
		if cfg.get("goal", false):
			var size: Vector3 = cfg.size
			# The goal is the patch of ground right in front of the door (building
			# front is local +Z, rotated by the node's facing). The Park has no
			# door, so its goal is simply standing on the green.
			var spot: Vector3
			var reach: float
			if cfg.style == "park":
				spot = node.global_position
				reach = 14.0
			else:
				var fwd := node.global_transform.basis.z   # door direction in world
				spot = node.global_position + fwd * (size.z * 0.5 + 3.5)
				reach = 4.0
			spot.y = 0.0
			node.set_meta("goal_spot", spot)
			node.set_meta("goal_reach", reach)
			# Which street the goal fronts: the door faces it, so the street line is
			# the nearest grid line along the door axis. Used for the "It is here!"
			# hint once the player turns onto that street.
			var fwd := node.global_transform.basis.z
			var axis_x: bool = absf(fwd.x) > absf(fwd.z)
			node.set_meta("goal_street_axis_x", axis_x)
			node.set_meta("goal_street_line", _nearest(spot.x if axis_x else spot.z))
			# How far along the street (each way from the goal) still counts as
			# "directly in front" — the block frontage between the two flanking
			# intersections, minus the road at each so it stays on the segment.
			node.set_meta("goal_seg_half", HALF_BLOCK - HALF)
			# Where the building's name label floats once it's been found: a sign
			# just above the door, on the front face.
			node.set_meta("label_pos", node.global_position
					+ Vector3(0, 4.6, 0) + fwd * (size.z * 0.5 + 0.4))
			goals[cfg.name] = node
			goal_names.append(cfg.name)


# Pack each block with buildings to create a dense "city maze": the goal sits at
# the block centre and houses/shops/offices fill a ring of slots around it (any
# that would overlap the goal are skipped). The street grid between blocks is
# what you navigate. All positions are final (no setback) — the slot spacing is
# pre-chosen so nothing spills onto a road. Coordinates are in world units.
const SLOT := 13.0              # ring offset from block centre (tight packing)
const CORE := 9.0               # central courtyard half-size kept clear of buildings
const SB := HALF + SW_W + 2.0   # building face clearance from a road line (8.7)
# Max distance a building face may sit from its block centre before it would
# touch the sidewalk: (HALF_BLOCK - SW_OFF - SW_W/2) minus a 0.5 grass strip.
const BUILDABLE := HALF_BLOCK - SW_OFF - SW_W * 0.5 - 0.5

func _layout_buildings() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 71
	var out := []
	for j in BLOCK_CENTERS.size():
		for i in BLOCK_CENTERS.size():
			var cx: float = BLOCK_CENTERS[i]
			var cz: float = BLOCK_CENTERS[j]
			var gname: String = GOAL_GRID[j][i]
			if gname == "Park":
				out.append({"name": "Park", "pos": Vector3(0, 0, 0), "size": Vector3(40, 0.08, 40),
						"color": Color(0.30, 0.55, 0.27), "style": "park", "goal": true})
				continue
			# Goal fronts the inner street (toward downtown); block centre stays
			# open so nothing is landlocked without road access.
			var d: Dictionary = GOAL_DEFS[gname]
			var gcfg := {"name": gname, "pos": _front_inner(cx, cz, d.size),
					"size": d.size, "style": d.style, "goal": true}
			if d.has("color"):
				gcfg["color"] = d.color
			if d.has("accent"):
				gcfg["accent"] = d.accent
			out.append(gcfg)
			var placed := [_footprint(gcfg)]
			# Main ring of houses around the goal.
			for ox in [-SLOT, 0.0, SLOT]:
				for oz in [-SLOT, 0.0, SLOT]:
					if ox == 0.0 and oz == 0.0:
						continue
					_try_place(_house_cfg(Vector3(cx + ox, 0, cz + oz), rng), placed, out)
			# Fill pass: squeeze small fillers into whatever gaps remain so blocks
			# read as solid city blocks instead of a sparse ring.
			_fill_block(cx, cz, placed, out, rng)
			# The road-less block centre is left open and dressed with a little
			# greenery (trees + the odd bench) instead of a landlocked building.
			out.append_array(_courtyard_props(cx, cz, placed, rng))
	return out


# Try to add `cfg` to the block if it doesn't overlap anything already placed
# (and stays off the sidewalk). `gap` is the alley left around it. Returns true
# on success.
func _try_place(cfg: Dictionary, placed: Array, out: Array, gap: float = 1.0) -> bool:
	var fp := _footprint(cfg)
	# Keep the footprint clear of the sidewalk on all four sides.
	if absf(fp.x - _block_center(fp.x)) + fp.hx > BUILDABLE:
		return false
	if absf(fp.z - _block_center(fp.z)) + fp.hz > BUILDABLE:
		return false
	for f in placed:
		if _overlaps(f, fp, gap):
			return false
	out.append(cfg)
	placed.append(fp)
	return true


# Greedily drop filler houses across a fine grid inside the block, but leave the
# central core (CORE x CORE) clear (that pocket becomes a courtyard). At each
# spot we try the largest filler that fits down to a small one, with a tight
# alley, so even the slivers right beside the big goal buildings get filled.
func _fill_block(cx: float, cz: float, placed: Array, out: Array, rng: RandomNumberGenerator) -> void:
	var offs := [-15.0, -12.0, -9.0, -6.0, -3.0, 0.0, 3.0, 6.0, 9.0, 12.0, 15.0]
	for ox in offs:
		for oz in offs:
			if absf(ox) < CORE and absf(oz) < CORE:
				continue
			var pos := Vector3(cx + ox, 0, cz + oz)
			# Largest-first so big lots stay roomy but tight gaps still get a small one.
			for w in [8.5, 7.0, 5.5]:
				var cfg := _storeyed_house(pos, rng, 4, w, w * rng.randf_range(0.85, 1.0))
				if _try_place(cfg, placed, out, 0.4):
					break


# Trees (1-2) and the occasional bench (0-2) for the open courtyard at a block's
# road-less centre. Positions are overlap-checked against the block's buildings.
func _courtyard_props(cx: float, cz: float, placed: Array, rng: RandomNumberGenerator) -> Array:
	var out := []
	var spots := []
	for ox in [-5.0, -2.5, 0.0, 2.5, 5.0]:
		for oz in [-5.0, -2.5, 0.0, 2.5, 5.0]:
			spots.append(Vector3(cx + ox, 0, cz + oz))
	# Deterministic shuffle (Fisher-Yates) using our seeded rng.
	for i in range(spots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Vector3 = spots[i]
		spots[i] = spots[j]
		spots[j] = tmp

	var trees_left := rng.randi_range(1, 2)
	var benches_left := rng.randi_range(0, 2)
	var used := []
	for s in spots:
		if trees_left <= 0 and benches_left <= 0:
			break
		var is_tree := trees_left > 0
		var fp := {"x": s.x, "z": s.z,
				"hx": 0.6 if is_tree else 1.3, "hz": 0.6 if is_tree else 0.9}
		var clash := false
		for f in placed:
			if _overlaps(f, fp):
				clash = true
				break
		if not clash:
			for f in used:
				if _overlaps(f, fp):
					clash = true
					break
		if clash:
			continue
		if is_tree:
			out.append({"prop": "tree", "pos": s})
			trees_left -= 1
		else:
			out.append({"prop": "bench", "pos": s, "yaw": rng.randf() * TAU})
			benches_left -= 1
		used.append(fp)
	return out


# Nearest block centre to a world coordinate (for the sidewalk-clearance check).
func _block_center(v: float) -> float:
	var best: float = BLOCK_CENTERS[0]
	for c in BLOCK_CENTERS:
		if absf(c - v) < absf(best - v):
			best = c
	return best


# Position a goal so it fronts the inner street (the block edge nearest the town
# centre), set back to clear the road. The block centre is left empty.
func _front_inner(cx: float, cz: float, size: Vector3) -> Vector3:
	if absf(cx) >= absf(cz):
		var line: float = cx - signf(cx) * HALF_BLOCK
		return Vector3(line + signf(cx) * (SB + size.z * 0.5), 0, cz)
	var zline: float = cz - signf(cz) * HALF_BLOCK
	return Vector3(cx, 0, zline + signf(cz) * (SB + size.z * 0.5))


# A ring-slot building. Mostly multi-storey houses/apartments (3-5 floors are
# common, single-storey is rare) so the blocks rise into tall maze walls; a few
# low shops add variety.
func _house_cfg(pos: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	var r := rng.randf()
	if r < 0.72:
		return _storeyed_house(pos, rng, 5, rng.randf_range(9, 12), rng.randf_range(9, 12))
	if r < 0.88:
		return {"name": "Office", "pos": pos, "style": "office",
				"size": Vector3(10, rng.randf_range(12, 18), 10),
				"color": OFFICE_COLORS[rng.randi() % OFFICE_COLORS.size()]}
	return {"name": "Store", "pos": pos, "style": "shop", "size": Vector3(11, 6, 11),
			"color": SHOP_COLORS[rng.randi() % SHOP_COLORS.size()], "accent": Color(0.38, 0.34, 0.30)}


# Build a multi-storey house config of the given footprint, picking a floor count
# weighted toward the taller end (single-storey rare). Tall ones get flat roofs
# (apartment/tower look); short ones keep pitched roofs + chimneys.
func _storeyed_house(pos: Vector3, rng: RandomNumberGenerator, hi: int, w: float, d: float) -> Dictionary:
	var floors := _pick_floors(rng, hi)
	var tall := floors >= 3
	return {
		"name": "House", "pos": pos, "style": "house",
		"size": Vector3(w, 2.0 + floors * 3.0 + rng.randf_range(-0.3, 0.5), d),
		"color": HOUSE_COLORS[rng.randi() % HOUSE_COLORS.size()],
		"accent": ROOF_COLORS[rng.randi() % ROOF_COLORS.size()],   # roof colour
		"floors": floors,
		"flat_roof": tall or rng.randf() < 0.30,
		"chimney": (not tall) and rng.randf() < 0.6,
	}


# Floor count weighted toward mid/tall buildings; single-storey is rare. `hi`
# caps the count (5 for full lots, 4 for the narrow fillers).
func _pick_floors(rng: RandomNumberGenerator, hi: int) -> int:
	var r := rng.randf()
	if hi >= 5:
		if r < 0.08: return 1
		if r < 0.30: return 2
		if r < 0.60: return 3
		if r < 0.85: return 4
		return 5
	if r < 0.12: return 1
	if r < 0.45: return 2
	if r < 0.80: return 3
	return 4


# World footprint (axis-aligned half extents) of a building at its final pos,
# using the SAME facing it will be rotated to (so the overlap check is accurate).
func _footprint(cfg: Dictionary) -> Dictionary:
	var s: Vector3 = cfg.size
	var yaw := _park_or_street_facing(cfg.pos)
	# yaw of ±PI/2 turns the depth (z) along world X; yaw of 0/PI keeps it along Z.
	var faces_x: bool = absf(yaw) > 0.01 and absf(absf(yaw) - PI) > 0.01
	return {"x": cfg.pos.x, "z": cfg.pos.z,
			"hx": (s.z if faces_x else s.x) * 0.5, "hz": (s.x if faces_x else s.z) * 0.5}


# True if two footprints are closer than `gap` (the alley left between buildings).
func _overlaps(a: Dictionary, b: Dictionary, gap: float = 1.0) -> bool:
	return (a.hx + b.hx + gap) > absf(a.x - b.x) and (a.hz + b.hz + gap) > absf(a.z - b.z)


# Face the building's front (+Z) toward the nearest street.
func _facing(pos: Vector3) -> float:
	var nx := _nearest(pos.x)
	var nz := _nearest(pos.z)
	if absf(pos.x - nx) <= absf(pos.z - nz):
		return PI * 0.5 if nx > pos.x else -PI * 0.5
	return 0.0 if nz > pos.z else PI


# Buildings in the row directly fronting the central Park face the Park (so the
# green has a consistent storefront) instead of being turned toward a side street
# by the nearest-street tie-break. Everything else just faces its street.
const PARK_LAT := 20.0   # Park half-width: how far a frontage can sit off-axis
func _park_or_street_facing(pos: Vector3) -> float:
	# South / north blocks (Park lies along the z axis from them).
	if absf(pos.x) <= PARK_LAT:
		if pos.z > HALF_BLOCK and pos.z < 54.0:
			return PI            # south block -> face north toward the Park
		if pos.z < -HALF_BLOCK and pos.z > -54.0:
			return 0.0           # north block -> face south toward the Park
	# East / west blocks (Park lies along the x axis from them).
	if absf(pos.z) <= PARK_LAT:
		if pos.x > HALF_BLOCK and pos.x < 54.0:
			return -PI * 0.5     # east block -> face west toward the Park
		if pos.x < -HALF_BLOCK and pos.x > -54.0:
			return PI * 0.5      # west block -> face east toward the Park
	return _facing(pos)


func _nearest(v: float) -> float:
	var best := GRID[0]
	for g in GRID:
		if absf(g - v) < absf(best - v):
			best = g
	return best


# =============================================================================
# Building factory
# =============================================================================
func _spawn_building(cfg: Dictionary) -> Node3D:
	var style: String = cfg.style
	var size: Vector3 = cfg.size
	var color: Color = cfg.get("color", Color(0.8, 0.8, 0.8))
	var accent: Color = cfg.get("accent", Color(0.4, 0.4, 0.4))
	if style == "house" and not cfg.has("color"):
		color = HOUSE_COLORS[_house_i % HOUSE_COLORS.size()]
		_house_i += 1
	var body := StaticBody3D.new()
	body.name = cfg.name

	match style:
		"park":
			_build_park(body, size, color)
		"pool":
			_build_pool(body, size, color, accent)
		"station":
			_build_station(body, size, color, accent)
		"shrine":
			_build_shrine(body, size, color, accent)
		"gas":
			_build_gas(body, size)
		_:
			_build_structure(body, cfg, size, color, accent)

	# Most styles want a solid collision box (park stays walkable; gas uses a smaller footprint).
	if style != "park" and style != "gas":
		_collide(body, size)
	elif style == "gas":
		_collide(body, Vector3(size.x * 0.4, size.y, size.z * 0.4))
	return body


# A generic structure: mass + windows + door + a roof/accent per style.
func _build_structure(body: Node3D, cfg: Dictionary, size: Vector3, color: Color, accent: Color) -> void:
	var style: String = cfg.style
	_box(body, size, Vector3(0, size.y * 0.5, 0), color)
	var rows := 2
	var cols := int(clampf(size.x / 7.0, 1, 3))
	match style:
		"civic":
			_columns(body, size)
			_pediment(body, size, color)
			rows = 2
		"hospital":
			_flat_roof(body, size, Color(0.72, 0.74, 0.77))
			_cross(body, size)
			rows = 3
		"brick":
			_flat_roof(body, size, Color(0.30, 0.16, 0.13))
			_flagpole(body, size)
		"police":
			_flat_roof(body, size, accent)
			_band(body, size, accent)
		"firehouse":
			_flat_roof(body, size, accent)
			_garage_doors(body, size, accent)
			_cylinder(body, 0.9, size.y + 5.0, Vector3(size.x * 0.5 - 1.0, (size.y + 5.0) * 0.5, 0), Color(0.5, 0.12, 0.10))
			rows = 1
		"shop", "market", "diner":
			_flat_roof(body, size, accent.darkened(0.1))
			_awning(body, size, accent)
			_storefront(body, size)
			rows = 0   # storefront replaces the window grid on the ground floor
			if style == "market":
				rows = 1   # a strip of clerestory windows above the storefront
			if cfg.name == "McDonald's":
				_burger(body, size)
		"office":
			_flat_roof(body, size, color.darkened(0.2))
			rows = 4
		"house":
			if cfg.get("flat_roof", false):
				_flat_roof(body, size, accent)
			else:
				_pitched_roof(body, size, accent)
			if cfg.get("chimney", true):
				_chimney(body, size)
			rows = cfg.get("floors", 1)
			cols = int(clampf(size.x / 3.5, 2, 4))
		"church":
			_pitched_roof(body, size, Color(0.45, 0.30, 0.35))
			_steeple(body, size)
			rows = 2
			cols = 2
		"motel":
			_flat_roof(body, size, accent)
			_motel_doors(body, size)
			rows = 0
		_:
			_flat_roof(body, size, accent)

	if rows > 0:
		_windows(body, size, rows, cols)
	# Shop styles get their door from the storefront; firehouse/motel have none.
	if style not in ["firehouse", "motel", "shop", "market", "diner"]:
		_door(body, size)


# -----------------------------------------------------------------------------
# Shared facade parts (front is +Z)
# -----------------------------------------------------------------------------
func _windows(body: Node3D, size: Vector3, rows: int, cols: int) -> void:
	var z := size.z * 0.5
	var col_gap := size.x / float(cols + 1)
	var row_gap := size.y / float(rows + 1)
	var frame := _mat(Color(0.20, 0.20, 0.22))
	var glass := _glass()
	for r in rows:
		var wy := size.y - row_gap * float(r + 1)
		for c in cols:
			var wx := -size.x * 0.5 + col_gap * float(c + 1)
			# Skip any window that would sit over / touch the door (centre, low).
			if absf(wx) < 2.4 and wy < 3.8:
				continue
			_box_mat(body, Vector3(1.25, 1.6, 0.06), Vector3(wx, wy, z + 0.04), frame)
			_box_mat(body, Vector3(1.0, 1.35, 0.12), Vector3(wx, wy, z + 0.08), glass)


func _door(body: Node3D, size: Vector3) -> void:
	var z := size.z * 0.5
	_box(body, Vector3(2.2, 2.7, 0.1), Vector3(0, 1.35, z + 0.04), Color(0.28, 0.20, 0.13))
	_box(body, Vector3(1.8, 2.4, 0.14), Vector3(0, 1.2, z + 0.08), Color(0.45, 0.32, 0.20))
	# Flat threshold (kept low so the player doesn't sink into a raised step).
	_box(body, Vector3(3.0, 0.06, 1.2), Vector3(0, 0.03, z + 0.6), Color(0.75, 0.74, 0.72))


func _storefront(body: Node3D, size: Vector3) -> void:
	var z := size.z * 0.5
	_box_mat(body, Vector3(size.x - 1.4, 2.4, 0.12), Vector3(0, 1.6, z + 0.07), _glass())
	_box(body, Vector3(1.6, 2.4, 0.16), Vector3(0, 1.4, z + 0.1), Color(0.30, 0.22, 0.16))  # door


func _awning(body: Node3D, size: Vector3, accent: Color) -> void:
	_box(body, Vector3(size.x + 0.4, 0.3, 1.6), Vector3(0, 3.0, size.z * 0.5 + 0.7), accent)


# A hamburger icon on the front wall (for McDonald's).
func _burger(body: Node3D, size: Vector3) -> void:
	var z := size.z * 0.5 + 0.12
	var bun := Color(0.86, 0.62, 0.33)
	var patty := Color(0.34, 0.18, 0.10)
	var cheese := Color(0.96, 0.74, 0.16)
	_box(body, Vector3(1.7, 0.28, 0.25), Vector3(0, 4.2, z), bun)       # bottom bun
	_box(body, Vector3(1.85, 0.30, 0.27), Vector3(0, 4.5, z), patty)    # patty
	_box(body, Vector3(1.95, 0.12, 0.29), Vector3(0, 4.7, z), cheese)   # cheese
	# Top bun: a HEMISPHERE (flat bottom on the cheese, domed top) so it reads as
	# a half-ellipse rather than a full ball poking out below the patty.
	var top := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 0.98
	dome.height = 0.98             # hemisphere -> dome rises 0.49 above its flat base
	dome.is_hemisphere = true
	top.mesh = dome
	top.material_override = _mat(bun)
	top.position = Vector3(0, 4.76, z)        # flat base sits on the cheese top
	top.scale = Vector3(1.0, 1.0, 0.30)       # thin in depth (a wall relief)
	body.add_child(top)
	for sx in [-0.45, 0.0, 0.45]:                                       # sesame seeds
		_sphere(body, 0.05, Vector3(sx, 4.98, z + 0.14), Color(0.97, 0.93, 0.80))


func _flat_roof(body: Node3D, size: Vector3, color: Color) -> void:
	_box(body, Vector3(size.x + 0.6, 0.5, size.z + 0.6), Vector3(0, size.y + 0.25, 0), color)


func _pitched_roof(body: Node3D, size: Vector3, color: Color) -> void:
	# Prism ridge runs along Z, giving a front-gabled roof.
	_prism(body, Vector3(size.x + 0.6, size.y * 0.45, size.z + 0.6),
			Vector3(0, size.y + size.y * 0.225, 0), color)


func _columns(body: Node3D, size: Vector3) -> void:
	var z := size.z * 0.5 + 0.7
	var stone := Color(0.90, 0.88, 0.82)
	var n := int(clampf(size.x / 4.0, 3, 5))
	var span := size.x - 2.0
	for i in n:
		var x := -span * 0.5 + span * float(i) / float(n - 1)
		_cylinder(body, 0.35, size.y, Vector3(x, size.y * 0.5, z), stone)
		var col := CollisionShape3D.new()
		var cshape := CylinderShape3D.new()
		cshape.radius = 0.35
		cshape.height = size.y
		col.shape = cshape
		col.position = Vector3(x, size.y * 0.5, z)
		body.add_child(col)
	_box(body, Vector3(size.x + 0.8, 0.08, 1.8), Vector3(0, 0.04, z), Color(0.82, 0.80, 0.74))  # flush base
	_box(body, Vector3(size.x + 0.8, 0.7, 2.0), Vector3(0, size.y + 0.35, z - 0.1), stone)


func _pediment(body: Node3D, size: Vector3, _color: Color) -> void:
	_prism(body, Vector3(size.x + 0.9, 1.7, 2.0), Vector3(0, size.y + 1.55, size.z * 0.5 + 0.6), Color(0.88, 0.86, 0.80))


func _cross(body: Node3D, size: Vector3) -> void:
	var z := size.z * 0.5 + 0.1
	var y := size.y - 1.3        # high on the wall, above the top row of windows
	var red := Color(0.85, 0.12, 0.12)
	_box(body, Vector3(0.55, 1.8, 0.2), Vector3(0, y, z), red)
	_box(body, Vector3(1.7, 0.55, 0.2), Vector3(0, y, z), red)


func _band(body: Node3D, size: Vector3, accent: Color) -> void:
	_box(body, Vector3(size.x + 0.1, 0.6, size.z + 0.1), Vector3(0, size.y - 1.5, 0), accent)


func _garage_doors(body: Node3D, size: Vector3, accent: Color) -> void:
	var z := size.z * 0.5
	var w := size.x / 2.4
	for sx in [-1.0, 1.0]:
		_box(body, Vector3(w, 3.6, 0.2), Vector3(sx * w * 0.62, 1.9, z + 0.06), accent.lightened(0.1))


func _flagpole(body: Node3D, size: Vector3) -> void:
	_cylinder(body, 0.1, 7.0, Vector3(-size.x * 0.5 - 1.5, 3.5, size.z * 0.5), Color(0.8, 0.8, 0.82))
	_box(body, Vector3(0.05, 0.9, 1.4), Vector3(-size.x * 0.5 - 1.5, 6.4, size.z * 0.5 + 0.7), Color(0.8, 0.2, 0.2))


func _chimney(body: Node3D, size: Vector3) -> void:
	_box(body, Vector3(0.8, size.y * 0.7, 0.8), Vector3(size.x * 0.3, size.y + size.y * 0.2, -size.z * 0.2), Color(0.4, 0.3, 0.28))


func _steeple(body: Node3D, size: Vector3) -> void:
	var x := 0.0
	var z := -size.z * 0.5 + 1.5
	_box(body, Vector3(3.0, size.y + 4.0, 3.0), Vector3(x, (size.y + 4.0) * 0.5, z), Color(0.92, 0.92, 0.90))
	_prism(body, Vector3(3.2, 4.0, 3.2), Vector3(x, size.y + 6.0, z), Color(0.45, 0.30, 0.35))


func _motel_doors(body: Node3D, size: Vector3) -> void:
	var z := size.z * 0.5
	var n := 4
	for i in n:
		var x := -size.x * 0.5 + size.x * (float(i) + 0.5) / float(n)
		_box(body, Vector3(1.4, 2.3, 0.14), Vector3(x, 1.15, z + 0.08), Color(0.30, 0.25, 0.40))
		_box_mat(body, Vector3(0.9, 1.1, 0.1), Vector3(x + 1.4, 1.7, z + 0.08), _glass())


# -----------------------------------------------------------------------------
# Bespoke styles
# -----------------------------------------------------------------------------
func _build_park(body: Node3D, size: Vector3, color: Color) -> void:
	_box(body, size, Vector3(0, size.y * 0.5, 0), color)            # grass (no collision)
	_box(body, Vector3(3, 0.08, size.z), Vector3(0, size.y, 0), Color(0.72, 0.68, 0.60))
	_box(body, Vector3(size.x, 0.08, 3), Vector3(0, size.y, 0), Color(0.72, 0.68, 0.60))
	_cylinder(body, 2.2, 0.6, Vector3(0, size.y + 0.3, 0), Color(0.70, 0.70, 0.72))
	_cylinder(body, 1.9, 0.5, Vector3(0, size.y + 0.55, 0), Color(0.40, 0.65, 0.85))
	_cylinder(body, 0.25, 1.6, Vector3(0, size.y + 1.0, 0), Color(0.70, 0.70, 0.72))
	_prop_collider(Vector3(0, 0, 0), 2.3, 1.2)   # solid fountain
	for off in [Vector3(-11, 0, -8), Vector3(11, 0, -8), Vector3(-11, 0, 8), Vector3(11, 0, 8)]:
		_tree(body, off + Vector3(0, size.y, 0))
	_bench(body, Vector3(-5, size.y, 0), PI * 0.5)
	_bench(body, Vector3(5, size.y, 0), -PI * 0.5)


func _build_pool(body: Node3D, size: Vector3, deck: Color, water: Color) -> void:
	# Deck bottom pushed to y=-0.15 so it never sits coplanar with the ground plane (y=0),
	# which would cause z-fighting / shimmering on the deck surface.
	_box(body, Vector3(size.x, 0.4, size.z), Vector3(0, 0.05, 0), deck)
	_box(body, Vector3(size.x - 5, 0.25, size.z - 5), Vector3(0, 0.13, 1), water)   # water top at y=0.255, just above deck rim
	_box(body, Vector3(size.x * 0.4, 3.0, 4), Vector3(-size.x * 0.25, 1.5, -size.z * 0.5 + 2), Color(0.85, 0.86, 0.88))  # changing rooms
	# A simple fence of posts around the deck.
	for i in 10:
		var t := float(i) / 9.0
		_cylinder(body, 0.1, 1.4, Vector3(-size.x * 0.5 + size.x * t, 0.7, size.z * 0.5), Color(0.7, 0.7, 0.72))


func _build_station(body: Node3D, size: Vector3, color: Color, roof: Color) -> void:
	_box(body, size, Vector3(0, size.y * 0.5, 0), color)
	_box(body, Vector3(size.x + 1.0, 0.5, size.z + 1.0), Vector3(0, size.y + 0.25, 0), roof)  # overhang roof
	# Clock tower (kept within the footprint so nothing pokes over a sidewalk).
	_box(body, Vector3(4, size.y + 6, 4), Vector3(-size.x * 0.5 + 2.5, (size.y + 6) * 0.5, 0), color.lightened(0.05))
	_cylinder(body, 1.1, 0.3, Vector3(-size.x * 0.5 + 2.5, size.y + 5.2, size.z * 0.5 - 0.6), Color(0.95, 0.95, 0.90)).rotation.x = PI * 0.5
	_windows(body, size, 1, 2)
	_door(body, size)


func _build_shrine(body: Node3D, size: Vector3, vermilion: Color, wood: Color) -> void:
	var stone := Color(0.72, 0.72, 0.70)
	# Stepped stone base.
	_box(body, Vector3(size.x, 0.6, size.z), Vector3(0, 0.3, 0), stone)
	_box(body, Vector3(size.x - 2, 0.6, size.z - 2), Vector3(0, 0.9, 0), stone.lightened(0.05))
	# Shrine hall: wooden body with a big overhanging vermilion roof.
	_box(body, Vector3(size.x - 4, 3.2, size.z - 5), Vector3(0, 2.8, -0.5), wood)
	_prism(body, Vector3(size.x - 1, 2.8, size.z - 3), Vector3(0, 5.8, -0.5), vermilion)
	# Torii gate at the front.
	var z := size.z * 0.5 + 1.0
	for sx in [-1.0, 1.0]:
		_cylinder(body, 0.3, 5.5, Vector3(sx * (size.x * 0.5 - 1.0), 2.75, z), vermilion)
		var tcol := CollisionShape3D.new()
		var tshape := CylinderShape3D.new()
		tshape.radius = 0.3
		tshape.height = 5.5
		tcol.shape = tshape
		tcol.position = Vector3(sx * (size.x * 0.5 - 1.0), 2.75, z)
		body.add_child(tcol)
	_box(body, Vector3(size.x + 1.0, 0.6, 0.6), Vector3(0, 5.4, z), vermilion)
	_box(body, Vector3(size.x - 1.0, 0.4, 0.4), Vector3(0, 4.6, z), vermilion)


func _build_gas(body: Node3D, size: Vector3) -> void:
	# Canopy on four posts.
	var canopy_h := 4.2
	_box(body, Vector3(size.x, 0.5, size.z), Vector3(0, canopy_h, 0), Color(0.90, 0.90, 0.92))
	_box(body, Vector3(size.x, 0.25, size.z), Vector3(0, canopy_h - 0.3, 0), Color(0.80, 0.20, 0.20))  # trim
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cylinder(body, 0.2, canopy_h, Vector3(sx * (size.x * 0.5 - 1), canopy_h * 0.5, sz * (size.z * 0.5 - 1)), Color(0.7, 0.7, 0.72))
	# Kiosk + two pumps.
	_box(body, Vector3(size.x * 0.4, 3.0, size.z * 0.4), Vector3(0, 1.5, -size.z * 0.2), Color(0.85, 0.85, 0.88))
	for sx2 in [-1.0, 1.0]:
		_box(body, Vector3(1.0, 1.6, 0.8), Vector3(sx2 * 2.5, 0.8, size.z * 0.2), Color(0.5, 0.5, 0.55))


# -----------------------------------------------------------------------------
# Little props
# -----------------------------------------------------------------------------
func _tree(parent: Node3D, base: Vector3) -> void:
	_cylinder(parent, 0.3, 2.0, base + Vector3(0, 1.0, 0), Color(0.45, 0.30, 0.15))
	var leaves := _sphere(parent, 1.3, base + Vector3(0, 3.0, 0), Color(0.16, 0.50, 0.17))
	leaves.scale = Vector3(1.0, 1.1, 1.0)
	_prop_collider(base, 0.45, 3.0)


func _bench(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var bench := Node3D.new()
	bench.position = pos
	bench.rotation.y = yaw
	parent.add_child(bench)
	var wood := Color(0.45, 0.30, 0.18)
	_box(bench, Vector3(2.4, 0.15, 0.7), Vector3(0, 0.5, 0), wood)
	_box(bench, Vector3(2.4, 0.6, 0.12), Vector3(0, 0.85, -0.3), wood)
	_box(bench, Vector3(0.12, 0.5, 0.6), Vector3(-1.0, 0.25, 0), wood)
	_box(bench, Vector3(0.12, 0.5, 0.6), Vector3(1.0, 0.25, 0), wood)
	_prop_box(pos + Vector3(0, 0.55, 0), Vector3(2.4, 1.1, 0.8), yaw)   # solid bench


func _add_lamppost(parent: Node3D, pos: Vector3) -> void:
	_cylinder(parent, 0.12, 4.0, pos + Vector3(0, 2.0, 0), Color(0.18, 0.18, 0.20))
	var bulb := _sphere(parent, 0.28, pos + Vector3(0, 4.1, 0), Color(1.0, 0.95, 0.7))
	var m := bulb.material_override as StandardMaterial3D
	m.emission_enabled = true
	m.emission = Color(1.0, 0.92, 0.6)
	m.emission_energy_multiplier = 2.0
	_prop_collider(pos, 0.25, 4.0)


# -----------------------------------------------------------------------------
# Primitive + material helpers (shared materials via _mat cache)
# -----------------------------------------------------------------------------
func _collide(body: Node3D, size: Vector3) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position.y = size.y * 0.5
	body.add_child(col)


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	return _box_mat(parent, size, pos, _mat(color))


func _box_mat(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.position = pos
	m.material_override = material
	parent.add_child(m)
	return m


func _cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	m.mesh = mesh
	m.position = pos
	m.material_override = _mat(color)
	parent.add_child(m)
	return m


func _sphere(parent: Node3D, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	m.mesh = mesh
	m.position = pos
	m.material_override = _mat(color)
	parent.add_child(m)
	return m


func _prism(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.position = pos
	m.material_override = _mat(color)
	parent.add_child(m)
	return m


func _slab(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	return _box(parent, size, pos, color)


func _glass() -> StandardMaterial3D:
	if _glass_mat == null:
		_glass_mat = StandardMaterial3D.new()
		_glass_mat.albedo_color = Color(0.55, 0.72, 0.90)
		_glass_mat.metallic = 0.5
		_glass_mat.roughness = 0.08
		_glass_mat.emission_enabled = true
		_glass_mat.emission = Color(0.30, 0.45, 0.65)
		_glass_mat.emission_energy_multiplier = 0.35
	return _glass_mat


func _mat(color: Color) -> StandardMaterial3D:
	if not _mat_cache.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		_mat_cache[color] = mat
	return _mat_cache[color]


# Merge all MeshInstance3D descendants of root into a single MeshInstance3D
# (one surface per unique material). Reduces per-building draw calls from
# 15-45 down to ~6-8. CollisionShape3D nodes are left untouched.
func _merge_meshes(root: Node3D) -> void:
	var by_mat: Dictionary = {}
	var to_free: Array = []
	_collect_for_merge(root, Transform3D.IDENTITY, by_mat, to_free)
	if by_mat.is_empty():
		return
	var arr_mesh := ArrayMesh.new()
	for mat in by_mat:
		var st: SurfaceTool = by_mat[mat]
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
		arr_mesh.surface_set_material(arr_mesh.get_surface_count() - 1, mat)
	var merged := MeshInstance3D.new()
	merged.mesh = arr_mesh
	root.add_child(merged)
	for node in to_free:
		node.queue_free()


func _collect_for_merge(node: Node3D, xform: Transform3D, by_mat: Dictionary, to_free: Array) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child
			if mi.mesh == null or mi.material_override == null:
				continue
			var local_xform := xform * mi.transform
			var mat: Material = mi.material_override
			if not by_mat.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_mat[mat] = st
			(by_mat[mat] as SurfaceTool).append_from(mi.mesh, 0, local_xform)
			to_free.append(mi)
		elif child is Node3D:
			_collect_for_merge(child, xform * child.transform, by_mat, to_free)
