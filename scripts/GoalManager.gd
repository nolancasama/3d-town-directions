class_name GoalManager
extends Node
# =============================================================================
# GoalManager.gd
# =============================================================================

var _player: Node3D
var _dialogue: DialogueManager
var _camera_focus: CameraFocusManager
var _audio: AudioStreamPlayer
var _chime: AudioStreamWAV
var _named: Dictionary = {}    # name -> true (discovered buildings)
var _times: Dictionary = {}    # name -> "m:ss" string
var _icons: Dictionary = {}    # name -> Node3D (hidden until discovered)
var _total: int = 0

var _target: Node3D = null
var _target_name: String = ""
var _goal_spot: Vector3 = Vector3.ZERO
var _target_reach: float = 4.0
var _street_axis_x: bool = false
var _street_line: float = 0.0
var _seg_half: float = 24.0
var _elapsed: float = 0.0
var _revisit: bool = false     # true when navigating to an already-discovered building

const STREET_PERP := 9.0

var _marker: MeshInstance3D
var _time: float = 0.0

const SHOW_DIST := 15.0


func setup(player: Node3D, dialogue: DialogueManager,
		camera_focus: CameraFocusManager = null, icons: Dictionary = {}) -> void:
	_player = player
	_dialogue = dialogue
	_camera_focus = camera_focus
	_icons = icons
	_build_marker()
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	_chime = _make_chime()


func set_total(n: int) -> void:
	_total = n


func is_discovered(name: String) -> bool:
	return _named.has(name)


# Called by the NPC once it has pointed the player toward a building.
func set_target(dest_name: String, target: Node3D) -> void:
	_target = target
	_target_name = dest_name
	_goal_spot = target.get_meta("goal_spot", target.global_position)
	_target_reach = target.get_meta("goal_reach", 4.0)
	_street_axis_x = target.get_meta("goal_street_axis_x", false)
	_street_line = target.get_meta("goal_street_line", 0.0)
	_seg_half = target.get_meta("goal_seg_half", 24.0)
	_revisit = _named.has(dest_name)
	_elapsed = 0.0
	if not _revisit:
		_marker.global_position = Vector3(_goal_spot.x, 0.12, _goal_spot.z)


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


func _process(delta: float) -> void:
	if _target == null or _player == null:
		_marker.visible = false
		return

	var a := _player.global_position
	a.y = 0
	var dist := a.distance_to(Vector3(_goal_spot.x, 0, _goal_spot.z))

	if dist <= _target_reach:
		_on_reached()
		return

	_elapsed += delta

	if _revisit:
		# Give turn-by-turn directions back to an already-found building, but no
		# ring and no timer — the player is just getting their bearings again.
		if _on_goal_street():
			_dialogue.set_directions(_target_name, "It is here!")
		else:
			_dialogue.set_directions(_target_name, _directions())
		_marker.visible = false
	else:
		_dialogue.update_elapsed(_elapsed)
		if _on_goal_street():
			_dialogue.set_directions(_target_name, "It is here!")
		else:
			_dialogue.set_directions(_target_name, _directions())
		_marker.visible = dist <= SHOW_DIST
		if _marker.visible:
			_time += delta
			var pulse := 1.0 + 0.08 * sin(_time * 5.0)
			_marker.scale = Vector3(pulse, 1.0, pulse)


func _on_reached() -> void:
	var dest_name := _target_name
	var node := _target
	var spot := _goal_spot
	_target = null
	_target_name = ""
	_marker.visible = false
	_dialogue.clear_directions()

	if _revisit or _named.has(dest_name):
		_dialogue.show_center_message("You've already found the %s!" % dest_name)
		_revisit = false
		return

	# First discovery — record time, award credit, celebrate.
	var time_str := _fmt(_elapsed)
	_named[dest_name] = true
	_times[dest_name] = time_str
	_dialogue.mark_discovered(dest_name, time_str)

	if _icons.has(dest_name):
		_icons[dest_name].visible = true

	_revisit = false
	_celebrate(dest_name, node, spot)


func _celebrate(dest_name: String, node: Node3D, spot: Vector3) -> void:
	if _chime != null:
		_audio.stream = _chime
		_audio.play()
	_spawn_confetti(spot)
	_add_name_label(dest_name, node)
	_dialogue.show_center_message("You found the %s!" % dest_name)
	if _camera_focus != null and _player != null:
		if _player.has_method("set_input_enabled"):
			_player.call("set_input_enabled", false)
		await _camera_focus.focus_on(node, _player.global_position, 2.0)
		if _player.has_method("set_input_enabled"):
			_player.call("set_input_enabled", true)


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


func _add_name_label(dest_name: String, node: Node3D) -> void:
	var lbl := Label3D.new()
	lbl.text = dest_name
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 128
	lbl.pixel_size = 0.013
	lbl.modulate = Color(1, 1, 1)
	lbl.outline_size = 16
	lbl.outline_modulate = Color(0.05, 0.05, 0.05)
	lbl.no_depth_test = false
	add_child(lbl)
	lbl.global_position = node.get_meta("label_pos",
			node.global_position + Vector3(0, 9, 0))


func _fmt(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]


func _make_chime() -> AudioStreamWAV:
	var rate := 22050
	var notes := [523.25, 659.25, 783.99, 1046.50]
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


func _on_goal_street() -> bool:
	var p := _player.global_position
	var perp: float = absf(p.x - _street_line) if _street_axis_x else absf(p.z - _street_line)
	var along: float = absf(p.z - _goal_spot.z) if _street_axis_x else absf(p.x - _goal_spot.x)
	return perp < STREET_PERP and along < _seg_half


func _directions() -> String:
	var p := _player.global_position
	var fwd := -_player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := _player.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()

	var perp_delta: float
	var to_street: Vector3
	var along_street: Vector3
	if _street_axis_x:
		perp_delta = _street_line - p.x
		to_street = Vector3(signf(perp_delta), 0, 0)
		along_street = Vector3(0, 0, signf(_goal_spot.z - p.z))
	else:
		perp_delta = _street_line - p.z
		to_street = Vector3(0, 0, signf(perp_delta))
		along_street = Vector3(signf(_goal_spot.x - p.x), 0, 0)

	var want := to_street if absf(perp_delta) > 5.0 else along_street
	return _step(fwd, right, want)


func _step(fwd: Vector3, right: Vector3, want: Vector3) -> String:
	var df := want.dot(fwd)
	if df > 0.7:
		return "Go straight down the street"
	if df < -0.7:
		return "Turn around"
	return "Turn right" if want.dot(right) > 0.0 else "Turn left"
