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
	if _input_enabled:
		# A/Left and D/Right turn the whole body (the camera follows).
		var turn := Input.get_action_strength("turn_left") \
				- Input.get_action_strength("turn_right")
		rotate_y(turn * turn_speed * delta)

	# W/Up and S/Down move along the body's facing direction (forward is -Z).
	var fwd := 0.0
	if _input_enabled:
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

	# Drive the walk animation from the actual horizontal speed.
	_body.walk_speed = Vector2(velocity.x, velocity.z).length()


# Called by NPCInteraction to freeze/unfreeze the player during dialogue.
func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if not enabled:
		velocity = Vector3.ZERO
