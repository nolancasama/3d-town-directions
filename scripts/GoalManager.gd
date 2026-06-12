class_name GoalManager
extends Node
# =============================================================================
# GoalManager.gd
# -----------------------------------------------------------------------------
# Tracks the ONE destination the player most recently asked the NPC about.
# The goal is the patch of ground right in FRONT OF THE DOOR (a "goal_spot"
# stored on each building in Main). The player has to walk into that spot.
#
# While a goal is active a glowing ring is drawn on that spot; it only shows
# once the player is within 15 m so it reads as "you've arrived, step in here".
# Reaching the spot:
#   * Awards 1 point and updates the score in the UI.
#   * Flashes "Correct! You found the <name>." on screen.
#   * Clears the target, so the player can return to an NPC for a new one.
# =============================================================================

var _player: Node3D
var _dialogue: DialogueManager
var _camera_focus: CameraFocusManager
var _audio: AudioStreamPlayer
var _chime: AudioStreamWAV
var _named: Dictionary = {}   # buildings that already have a floating name label

var _target: Node3D = null
var _target_name: String = ""
var _goal_spot: Vector3 = Vector3.ZERO
var _target_reach: float = 4.0
var _street_axis_x: bool = false   # goal fronts a street running along Z (line is an X)
var _street_line: float = 0.0
var _seg_half: float = 24.0        # how far along the street still counts as "in front"
var _score: int = 0
var _elapsed: float = 0.0          # time since this goal was given
var _budget: float = 0.0           # time bonus window (depends on distance)

const STREET_PERP := 9.0   # within this of the street line counts as "on the street"

var _marker: MeshInstance3D
var _time: float = 0.0

const SHOW_DIST := 15.0   # the ring only appears within this many metres


func setup(player: Node3D, dialogue: DialogueManager, camera_focus: CameraFocusManager = null) -> void:
	_player = player
	_dialogue = dialogue
	_camera_focus = camera_focus
	_build_marker()
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	_chime = _make_chime()


# A flat glowing ring laid on the ground to mark "stand here".
func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 2.2
	ring.outer_radius = 3.0
	ring.rings = 24
	ring.ring_segments = 24
	_marker.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.82, 0.15)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker.material_override = mat
	_marker.visible = false
	add_child(_marker)


# Called by the NPC once it has pointed the player toward a building.
func set_target(dest_name: String, target: Node3D) -> void:
	_target = target
	_target_name = dest_name
	_goal_spot = target.get_meta("goal_spot", target.global_position)
	_target_reach = target.get_meta("goal_reach", 4.0)
	_street_axis_x = target.get_meta("goal_street_axis_x", false)
	_street_line = target.get_meta("goal_street_line", 0.0)
	_seg_half = target.get_meta("goal_seg_half", 24.0)
	_marker.global_position = Vector3(_goal_spot.x, 0.12, _goal_spot.z)
	# Start the time-bonus clock. The window scales with the walking distance so
	# far goals aren't unfairly penalised.
	_elapsed = 0.0
	var d := _player.global_position.distance_to(_goal_spot)
	_budget = d * 0.30 + 8.0


func _process(delta: float) -> void:
	if _target == null or _player == null:
		_marker.visible = false
		return
	# Compare on the horizontal plane so building height doesn't matter.
	var a := _player.global_position
	a.y = 0
	var dist := a.distance_to(Vector3(_goal_spot.x, 0, _goal_spot.z))
	if dist <= _target_reach:
		_on_reached()
		return
	# Count up the elapsed time and show the (decreasing) time bonus.
	_elapsed += delta
	_dialogue.set_timer(maxf(0.0, _budget - _elapsed))
	# Live turn-by-turn directions toward the door. Once the player has turned
	# onto the street the goal is on (and is near it), just say it's here.
	if _on_goal_street():
		_dialogue.set_directions(_target_name, "It is here!")
	else:
		_dialogue.set_directions(_target_name, _directions())
	# The glowing ring fades in (just shows) once the player is close, and pulses.
	_marker.visible = dist <= SHOW_DIST
	if _marker.visible:
		_time += delta
		var pulse := 1.0 + 0.08 * sin(_time * 5.0)
		_marker.scale = Vector3(pulse, 1.0, pulse)


func _on_reached() -> void:
	# Capture the goal, then clear it immediately so _process won't re-trigger
	# while the celebration plays out.
	var dest_name := _target_name
	var node := _target
	var spot := _goal_spot
	_target = null
	_target_name = ""
	_marker.visible = false
	# Award points: a base for finding it plus a time bonus for getting there fast.
	var bonus := int(round(maxf(0.0, _budget - _elapsed) * 5.0))
	var award := 10 + bonus
	_score += award
	_dialogue.set_score(_score)
	_dialogue.clear_directions()
	_dialogue.clear_timer()
	_celebrate(dest_name, node, spot, award)


# Sound + confetti + a floating name over the door, then a camera reveal.
func _celebrate(dest_name: String, node: Node3D, spot: Vector3, award: int) -> void:
	if _chime != null:
		_audio.stream = _chime
		_audio.play()
	_spawn_confetti(spot)
	_add_name_label(dest_name, node)
	_dialogue.show_center_message("Correct! You found the %s.  +%d" % [dest_name, award])
	if _camera_focus != null and _player != null:
		if _player.has_method("set_input_enabled"):
			_player.call("set_input_enabled", false)
		await _camera_focus.focus_on(node, _player.global_position, 2.0)
		if _player.has_method("set_input_enabled"):
			_player.call("set_input_enabled", true)


# A burst of multi-coloured confetti at the goal spot (CPUParticles works on the
# Compatibility/WebGL renderer; GPUParticles would not).
func _spawn_confetti(spot: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.position = spot + Vector3(0, 1.0, 0)
	p.one_shot = true
	p.emitting = true
	p.amount = 90
	p.lifetime = 1.8
	p.explosiveness = 0.95
	p.direction = Vector3(0, 1, 0)
	p.spread = 50.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 11.0
	p.gravity = Vector3(0, -12.0, 0)
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.scale_amount_min = 0.16
	p.scale_amount_max = 0.30
	var bit := BoxMesh.new()
	bit.size = Vector3(0.5, 0.5, 0.08)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bit.material = mat
	p.mesh = bit
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	grad.colors = PackedColorArray([
		Color(0.95, 0.25, 0.25), Color(0.98, 0.80, 0.20), Color(0.30, 0.80, 0.35),
		Color(0.25, 0.55, 0.95), Color(0.80, 0.35, 0.85)])
	p.color_initial_ramp = grad
	add_child(p)
	await get_tree().create_timer(p.lifetime + 0.5).timeout
	p.queue_free()


# Permanent floating label with the building's name above its door, added once.
func _add_name_label(dest_name: String, node: Node3D) -> void:
	if _named.has(dest_name):
		return
	_named[dest_name] = true
	var lbl := Label3D.new()
	lbl.text = dest_name
	lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lbl.font_size = 110
	lbl.pixel_size = 0.013
	lbl.modulate = Color(1, 1, 1)
	lbl.outline_size = 14
	lbl.outline_modulate = Color(0.05, 0.05, 0.05)
	lbl.no_depth_test = false
	add_child(lbl)
	var label_pos: Vector3 = node.get_meta("label_pos", node.global_position + Vector3(0, 9, 0))
	lbl.global_position = label_pos
	var goal_spot: Vector3 = node.get_meta("goal_spot", node.global_position)
	var outward := goal_spot - node.global_position
	outward.y = 0.0
	if outward.length_squared() > 0.01:
		lbl.look_at(label_pos - outward.normalized(), Vector3.UP)


# Build a short ascending chime (C-E-G-C) as PCM, so we need no audio asset.
func _make_chime() -> AudioStreamWAV:
	var rate := 22050
	var notes := [523.25, 659.25, 783.99, 1046.50]   # C5 E5 G5 C6
	var note_dur := 0.16
	var per := int(rate * note_dur)
	var data := PackedByteArray()
	data.resize(per * notes.size() * 2)
	var idx := 0
	for n in notes.size():
		var freq: float = notes[n]
		for s in per:
			var t := float(s) / float(rate)
			var env: float = exp(-t * 5.5)
			var v: float = sin(TAU * freq * t) * env * 0.5
			var iv := int(clampf(v, -1.0, 1.0) * 32767.0)
			data[idx * 2] = iv & 0xFF
			data[idx * 2 + 1] = (iv >> 8) & 0xFF
			idx += 1
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


# True when the player is on the street segment DIRECTLY in front of the goal:
# on the goal's street (small perpendicular distance) and between the two
# intersections that flank the goal's block.
func _on_goal_street() -> bool:
	var p := _player.global_position
	var perp: float = absf(p.x - _street_line) if _street_axis_x else absf(p.z - _street_line)
	var along: float = absf(p.z - _goal_spot.z) if _street_axis_x else absf(p.x - _goal_spot.x)
	return perp < STREET_PERP and along < _seg_half


# ONE instruction at a time. The route is two legs tied to the goal's street:
# first close the distance TO that street, then head ALONG it to the goal. Each
# leg's instruction is the original style ("Go straight down the street", "Turn
# left/right", "Turn around"), relative to the player's current facing; it
# switches to the next leg once the current one is done.
func _directions() -> String:
	var p := _player.global_position
	var fwd := -_player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := _player.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()

	var perp_delta: float    # distance to the goal's street (close this first)
	var to_street: Vector3   # direction toward the goal's street
	var along_street: Vector3 # direction along the street toward the goal
	if _street_axis_x:
		perp_delta = _street_line - p.x
		to_street = Vector3(signf(perp_delta), 0, 0)
		along_street = Vector3(0, 0, signf(_goal_spot.z - p.z))
	else:
		perp_delta = _street_line - p.z
		to_street = Vector3(0, 0, signf(perp_delta))
		along_street = Vector3(signf(_goal_spot.x - p.x), 0, 0)

	# Leg 1 until we're basically on the goal's street, then leg 2 along it.
	var want := to_street if absf(perp_delta) > 5.0 else along_street
	return _step(fwd, right, want)


# The single immediate instruction for heading `want` given the current facing.
func _step(fwd: Vector3, right: Vector3, want: Vector3) -> String:
	var df := want.dot(fwd)
	if df > 0.7:
		return "Go straight down the street"
	if df < -0.7:
		return "Turn around"
	return "Turn right" if want.dot(right) > 0.0 else "Turn left"
