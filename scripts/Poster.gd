class_name Poster
extends Node3D
# =============================================================================
# Poster.gd
# -----------------------------------------------------------------------------
# A wall-mounted advertisement poster for one of the town's destinations. Walk
# up to it and press Space/E to open a close-up overlay showing the ad. Press
# Space/E again to close.
#
# Each poster advertises a place that is intentionally placed FAR from the real
# building, so the poster works as a spoiler-free vocabulary hint ("oh, there's
# a bakery in this town — I should ask someone where it is") rather than a
# pointer to the building itself.
# =============================================================================

# Only one poster overlay open at a time.
static var _open_poster: Poster = null

# Shared materials — all poster instances use the same three, so the bake
# merges every poster's geometry into exactly 3 mesh surfaces.
static var _s_frame_mat: StandardMaterial3D
static var _s_board_mat: StandardMaterial3D
static var _s_line_mat: StandardMaterial3D

var place_name: String = ""
var ad_line: String = ""
var hours_line: String = ""

var _dialogue: DialogueManager
var _player: PlayerController
var _goal_manager: GoalManager = null

var _prompt: Label3D
var _in_range: bool = false
var _is_open: bool = false
var _hint_given: bool = false

const VIS_RANGE := 110.0


func setup(dialogue: DialogueManager, player: PlayerController, gm: GoalManager = null) -> void:
	_dialogue = dialogue
	_player = player
	_goal_manager = gm


func _ready() -> void:
	_build_visuals()
	_build_detection_area()


func _build_visuals() -> void:
	# Initialise shared materials once for the lifetime of the scene.
	# All poster instances reuse the same three StandardMaterial3D objects so
	# the bake in Main._bake_poster_visuals() can merge every poster into 3 surfaces.
	if not _s_frame_mat:
		_s_frame_mat = StandardMaterial3D.new()
		_s_frame_mat.albedo_color = Color(0.12, 0.10, 0.08)
	if not _s_board_mat:
		_s_board_mat = StandardMaterial3D.new()
		_s_board_mat.albedo_color = Color(0.97, 0.95, 0.88)
	if not _s_line_mat:
		_s_line_mat = StandardMaterial3D.new()
		_s_line_mat.albedo_color = Color(0.40, 0.38, 0.34)

	# Dark frame behind the paper for contrast against light building walls.
	var frame := MeshInstance3D.new()
	var fmesh := BoxMesh.new()
	fmesh.size = Vector3(1.9, 2.5, 0.06)
	frame.mesh = fmesh
	frame.material_override = _s_frame_mat
	frame.position = Vector3(0, 0, 0.03)
	add_child(frame)

	# Backing paper (flat against the wall, faces local -Z = outward toward road).
	var board := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(1.7, 2.3, 0.08)
	board.mesh = bmesh
	board.material_override = _s_board_mat
	add_child(board)

	# Three abstract "text" lines of varying length.
	var widths := [1.30, 0.95, 0.65]
	var ys := [0.50, 0.05, -0.40]
	for i in 3:
		var ln := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(widths[i], 0.20, 0.06)
		ln.mesh = lm
		ln.material_override = _s_line_mat
		ln.position = Vector3(0.0, ys[i], -0.05)
		add_child(ln)

	# Proximity marker: the same cartoony "!" used for NPC interactions.
	_prompt = Label3D.new()
	_prompt.text = "!"
	_prompt.position = Vector3(0, 2.2, -0.4)
	_prompt.font_size = 256
	_prompt.pixel_size = 0.0045
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.modulate = Color(1.0, 0.85, 0.1)
	_prompt.outline_size = 20
	_prompt.outline_modulate = Color(0.1, 0.1, 0.1)
	_prompt.visibility_range_end = VIS_RANGE
	_prompt.visibility_range_end_margin = 4.0
	_prompt.visible = false
	add_child(_prompt)


func _build_detection_area() -> void:
	var area := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 4.0
	col.shape = shape
	col.position.y = 1.0
	area.add_child(col)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body == _player:
		_in_range = true


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_in_range = false
		if _is_open:
			_close()
		_prompt.visible = false


func _process(_delta: float) -> void:
	# Show the prompt only when nearby, idle, and nothing else is going on.
	var can_read := _in_range and not _is_open and not _blocked()
	if _prompt.visible != can_read:
		_prompt.visible = can_read

	if Input.is_action_just_pressed("interact"):
		if _is_open:
			_close()
		elif can_read:
			_open()


# True when an NPC conversation or the opening cinematic is active.
func _blocked() -> bool:
	return NPCInteraction._cinematic or NPCInteraction._active != null \
		or (_open_poster != null and _open_poster != self)


func _open() -> void:
	_is_open = true
	_open_poster = self
	_prompt.visible = false
	NPCInteraction._cinematic = true   # silence NPCs while reading
	if _player != null and _player.has_method("set_input_enabled"):
		_player.set_input_enabled(false)
	if not _hint_given:
		_hint_given = true
		var found := _goal_manager != null and _goal_manager.is_discovered(place_name)
		_dialogue.add_hint(place_name, found)
	_dialogue.show_poster([ad_line, hours_line])


func _close() -> void:
	_is_open = false
	if _open_poster == self:
		_open_poster = null
	_dialogue.hide_poster()
	NPCInteraction._cinematic = false
	if _player != null and _player.has_method("set_input_enabled"):
		_player.set_input_enabled(true)
