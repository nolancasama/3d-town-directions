class_name CameraFocusManager
extends Node3D
# =============================================================================
# CameraFocusManager.gd
# -----------------------------------------------------------------------------
# Owns a dedicated "focus" Camera3D. When the NPC points, focus_on():
#   1. Snaps the focus camera to wherever the player's camera currently is.
#   2. Makes the focus camera the active camera (current = true). Godot
#      automatically deactivates the previous camera.
#   3. Smoothly interpolates the focus camera (position + rotation) to a
#      vantage point that looks at the target building.
#   4. Holds there for `hold_seconds` so the player can see the building.
#   5. Smoothly pans back to the player's view, then re-activates the player
#      camera (no jump, since the views match by then).
#
# Because we start from the player's exact view and blend with quaternion
# slerp + position lerp, the transition reads as a smooth pan rather than a cut.
# =============================================================================

var _camera: Camera3D
var _player_camera: Camera3D

# Endpoints of the current blend, cached for the per-frame interpolation.
var _start_transform: Transform3D
var _end_transform: Transform3D

const BLEND_SECONDS := 1.0


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.current = false
	add_child(_camera)


func setup(player_camera: Camera3D) -> void:
	_player_camera = player_camera


# Pan from the player's view to a shot of `target`, hold, then return control.
# `from_pos` is the NPC's world position (the origin of the pointing). Split into
# pan_to / pan_back so the caller can sync other animations (e.g. the NPC lowering
# its arm) to the return leg.
func focus_on(target: Node3D, from_pos: Vector3, hold_seconds: float) -> void:
	await pan_to(target, from_pos)
	await pan_to_roof(target)
	await get_tree().create_timer(hold_seconds).timeout
	await pan_back()


# Blend from the player's current view to a raised shot looking at the building.
func pan_to(target: Node3D, from_pos: Vector3) -> void:
	# Start exactly where the player is looking now.
	_start_transform = _player_camera.global_transform
	_camera.global_transform = _start_transform
	_camera.current = true

	# Compute a vantage point: slightly behind the NPC (relative to the
	# building) and raised up, looking straight at the building.
	var to_target := target.global_position - from_pos
	to_target.y = 0
	if to_target.length() < 0.01:
		to_target = Vector3.FORWARD
	to_target = to_target.normalized()

	var end_pos := from_pos - to_target * 3.0 + Vector3(0, 5, 0)
	_end_transform = Transform3D(Basis(), end_pos).looking_at(
			target.global_position, Vector3.UP)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(_apply_blend, 0.0, 1.0, BLEND_SECONDS)
	await tween.finished


# Tilt up from the current vantage to look at the roofline of the target building.
# Called after pan_to so the camera is already positioned; this just arcs the gaze upward.
func pan_to_roof(target: Node3D) -> void:
	_start_transform = _camera.global_transform
	var roof_y: float
	if target.has_meta("label_pos"):
		roof_y = (target.get_meta("label_pos") as Vector3).y
	else:
		roof_y = target.global_position.y + 10.0
	var look_pos := Vector3(target.global_position.x, roof_y, target.global_position.z)
	_end_transform = Transform3D(Basis(), _start_transform.origin).looking_at(look_pos, Vector3.UP)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(_apply_blend, 0.0, 1.0, BLEND_SECONDS)
	await tween.finished


# Smoothly pan back to the player's view, then hand control back (the player
# hasn't moved, so the views match by the end and there's no jump).
func pan_back() -> void:
	_start_transform = _end_transform
	_end_transform = _player_camera.global_transform
	var back := create_tween()
	back.set_trans(Tween.TRANS_SINE)
	back.set_ease(Tween.EASE_IN_OUT)
	back.tween_method(_apply_blend, 0.0, 1.0, BLEND_SECONDS)
	await back.finished
	_player_camera.current = true


func _apply_blend(t: float) -> void:
	var origin := _start_transform.origin.lerp(_end_transform.origin, t)
	var rot := _start_transform.basis.get_rotation_quaternion().slerp(
			_end_transform.basis.get_rotation_quaternion(), t)
	_camera.global_transform = Transform3D(Basis(rot), origin)
