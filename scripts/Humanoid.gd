class_name Humanoid
extends Node3D
# =============================================================================
# Humanoid.gd
# -----------------------------------------------------------------------------
# A simple person built entirely from primitive meshes (head, torso, arms,
# legs, hair, eyes, shoes). Used for BOTH the player and the NPC so we only
# describe a body once.
#
# The figure faces local -Z (Godot's "forward"), so the face/eyes are on the
# -Z side. The right arm hangs from `right_arm_pivot`; rotating that pivot
# +90deg on X swings the arm forward (pointing), which the NPC uses.
#
# Colors are exported so each character can look different — set them BEFORE
# adding the node to the tree (the body is built in _ready()).
# =============================================================================

@export var skin_color: Color = Color(0.95, 0.78, 0.62)
@export var shirt_color: Color = Color(0.20, 0.45, 0.80)
@export var pants_color: Color = Color(0.25, 0.25, 0.30)
@export var hair_color: Color = Color(0.25, 0.16, 0.10)
@export var shoe_color: Color = Color(0.12, 0.12, 0.12)

# Limb pivots. Legs hang from the hips, arms from the shoulders; rotating a
# pivot on X swings that limb forward/back. right_arm_pivot is also used by the
# NPC for the pointing gesture (only when walk animation is OFF).
var left_leg_pivot: Node3D
var right_leg_pivot: Node3D
var left_arm_pivot: Node3D
var right_arm_pivot: Node3D

# --- Walk animation ----------------------------------------------------------
# Enable on characters that walk (the player). The controller feeds in the
# current planar speed each frame via `walk_speed`; the limbs swing accordingly
# and ease back to rest when stopped. Left OFF for the stationary NPC so its
# pointing arm is never overwritten.
@export var walk_enabled: bool = false
var walk_speed: float = 0.0
var _phase: float = 0.0


func _ready() -> void:
	_build()


func _build() -> void:
	# --- Legs (on hip pivots) ----------------------------------------------
	left_leg_pivot = _pivot(Vector3(-0.13, 0.92, 0))
	right_leg_pivot = _pivot(Vector3(0.13, 0.92, 0))
	_leg_limb(left_leg_pivot)
	_leg_limb(right_leg_pivot)

	# --- Pelvis / torso ----------------------------------------------------
	_box(Vector3(0.42, 0.25, 0.26), Vector3(0, 0.92, 0), pants_color)        # hips
	_box(Vector3(0.46, 0.62, 0.28), Vector3(0, 1.32, 0), shirt_color)        # chest

	# --- Arms (on shoulder pivots) -----------------------------------------
	# Shoulders are level with the TOP of the torso (chest top = 1.32 + 0.62/2).
	left_arm_pivot = _pivot(Vector3(-0.30, 1.63, 0))
	right_arm_pivot = _pivot(Vector3(0.30, 1.63, 0))
	_arm_limb(left_arm_pivot)
	_arm_limb(right_arm_pivot)

	# --- Neck + head -------------------------------------------------------
	_box(Vector3(0.12, 0.1, 0.12), Vector3(0, 1.68, 0), skin_color)          # neck
	_sphere(0.16, Vector3(0, 1.84, 0), skin_color)                           # head

	# Hair: a cap on the top/back of the head, with the hairline raised above the
	# eyes (pulled up and back so it doesn't hang over the brow).
	var hair := _sphere(0.17, Vector3(0, 1.95, 0.02), hair_color)
	hair.scale = Vector3(1.0, 0.8, 0.95)

	# Eyes (white with a smaller dark pupil) set into the -Z front face — small
	# enough that they sit on the head instead of bulging out.
	for ex in [-0.06, 0.06]:
		_sphere(0.034, Vector3(ex, 1.86, -0.135), Color(0.97, 0.97, 0.97))  # white
		_sphere(0.018, Vector3(ex, 1.86, -0.155), Color(0.05, 0.05, 0.08))  # pupil


func _process(delta: float) -> void:
	if not walk_enabled:
		return
	# Advance the stride phase based on speed; scale the swing so a slow walk
	# has a smaller stride. When stopped, the target is 0 (limbs ease to rest).
	var amp := 0.0
	if walk_speed > 0.5:
		_phase += delta * (walk_speed * 1.6 + 2.0)
		amp = clampf(walk_speed / 6.0, 0.0, 1.0) * 0.5
	var swing := sin(_phase) * amp
	# Smoothly track the target so start/stop never snaps.
	var t := 1.0 - exp(-delta * 12.0)
	# Arms swing opposite to the leg on the same side (natural counter-swing).
	left_leg_pivot.rotation.x = lerpf(left_leg_pivot.rotation.x, swing, t)
	right_leg_pivot.rotation.x = lerpf(right_leg_pivot.rotation.x, -swing, t)
	left_arm_pivot.rotation.x = lerpf(left_arm_pivot.rotation.x, -swing, t)
	right_arm_pivot.rotation.x = lerpf(right_arm_pivot.rotation.x, swing, t)


# A shoulder/hip pivot node added to the body at the given position.
func _pivot(pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	add_child(p)
	return p


# A leg = thigh/calf capsule + a shoe box, hanging below a hip pivot.
func _leg_limb(pivot: Node3D) -> void:
	pivot.add_child(_make_capsule(0.12, 0.8, Vector3(0, -0.42, 0), pants_color))
	pivot.add_child(_make_box(Vector3(0.18, 0.12, 0.34), Vector3(0, -0.86, -0.05), shoe_color))


# An arm limb hanging below the given shoulder pivot, with a hand at the end.
# The capsule's top sits at the pivot (= torso top), and it's long enough to
# reach down to about hip level.
func _arm_limb(pivot: Node3D) -> void:
	pivot.add_child(_make_capsule(0.09, 0.72, Vector3(0, -0.36, 0), shirt_color))
	pivot.add_child(_make_sphere(0.08, Vector3(0, -0.74, 0), skin_color))


# ---------------------------------------------------------------------------
# Primitive helpers. The `_make_*` builders return an unparented MeshInstance3D;
# the `_box/_capsule/_sphere` wrappers add it straight onto the body.
# ---------------------------------------------------------------------------
func _make_box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.position = pos
	m.material_override = _mat(color)
	return m


func _make_capsule(radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	m.mesh = mesh
	m.position = pos
	m.material_override = _mat(color)
	return m


func _make_sphere(radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	m.mesh = mesh
	m.position = pos
	m.material_override = _mat(color)
	return m


func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := _make_box(size, pos, color)
	add_child(m)
	return m


func _capsule(radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := _make_capsule(radius, height, pos, color)
	add_child(m)
	return m


func _sphere(radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := _make_sphere(radius, pos, color)
	add_child(m)
	return m


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat
