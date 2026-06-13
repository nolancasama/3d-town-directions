class_name PlayerController
extends CharacterBody3D
# =============================================================================
# PlayerController.gd
# -----------------------------------------------------------------------------
# Keyboard-only third-person controller (no mouse required):
#   * W / Up    -> walk forward      S / Down -> walk back
#   * A / Left  -> turn left         D / Right -> turn right
#
# The camera is rigidly parented behind the avatar at a fixed downward pitch,
# so it always stays directly behind the player as they turn.
#
# While the NPC is talking, set_input_enabled(false) freezes movement so the
# CameraFocusManager can take over the view.
# =============================================================================

@export var move_speed: float = 6.0
@export var turn_speed: float = 2.6    # radians / second
@export var gravity: float = 20.0
@export var camera_pitch: float = -0.30  # fixed downward tilt (radians)

# The camera the rest of the game treats as the "player camera".
var camera: Camera3D

var _camera_pivot: Node3D
var _input_enabled: bool = true
var _body: Humanoid         # the visible figure, for walk animation

signal walk_done
var _walk_active: bool = false
var _walk_target: Vector3
var _walk_speed: float


func _ready() -> void:
	_build_collider()
	_build_body()
	_build_camera_rig()


func _build_collider() -> void:
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	col.shape = shape
	col.position.y = 0.9
	add_child(col)


func _build_body() -> void:
	# A full humanoid figure instead of a plain capsule.
	var body := Humanoid.new()
	body.shirt_color = Color(0.15, 0.35, 0.75)
	body.pants_color = Color(0.20, 0.20, 0.24)
	body.hair_color = Color(0.20, 0.13, 0.08)
	body.walk_enabled = true     # swing arms/legs while moving
	add_child(body)
	_body = body


func _build_camera_rig() -> void:
	# Pivot at head height with a FIXED downward pitch. The camera sits behind
	# the pivot (+Z is behind a -Z-facing body), so it always trails the avatar.
	# Because the rig is parented to the body, turning the body turns the camera
	# with it — the view stays locked behind the player without any mouse input.
	_camera_pivot = Node3D.new()
	_camera_pivot.position.y = 1.7
	_camera_pivot.rotation.x = camera_pitch
	add_child(_camera_pivot)

	camera = Camera3D.new()
	camera.position = Vector3(0, 0, 5.5)   # +Z is behind the player
	_camera_pivot.add_child(camera)
	camera.current = true                  # active view at start


func _physics_process(delta: float) -> void:
	if _walk_active:
		var to := _walk_target - global_position
		to.y = 0.0
		var dist := to.length()
		if dist < 0.25:
			velocity.x = 0.0
			velocity.z = 0.0
			global_position.x = _walk_target.x
			global_position.z = _walk_target.z
			_walk_active = false
			walk_done.emit()
		else:
			var dir := to.normalized()
			velocity.x = dir.x * _walk_speed
			velocity.z = dir.z * _walk_speed
	else:
		var focused := get_viewport().gui_get_focus_owner()
		var typing := focused != null and focused is LineEdit

		if _input_enabled and not typing:
			var turn := Input.get_action_strength("turn_left") \
					- Input.get_action_strength("turn_right")
			rotate_y(turn * turn_speed * delta)

		var fwd := 0.0
		if _input_enabled and not typing:
			fwd = Input.get_action_strength("move_forward") \
					- Input.get_action_strength("move_back")
		var direction := -transform.basis.z * fwd
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	move_and_slide()
	_body.walk_speed = Vector2(velocity.x, velocity.z).length()


# Called by NPCInteraction to freeze/unfreeze the player during dialogue.
func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if not enabled:
		velocity = Vector3.ZERO


func walk_to(target: Vector3, speed: float = -1.0) -> void:
	_walk_target = target
	_walk_speed = speed if speed > 0.0 else move_speed
	_walk_active = true


func stop_walk() -> void:
	_walk_active = false
	velocity.x = 0.0
	velocity.z = 0.0
