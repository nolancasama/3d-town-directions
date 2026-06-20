class_name WelcomeSign
extends Node3D
# =============================================================================
# WelcomeSign.gd
# A free-standing ground sign in the park. Interact with it (Space/E) to open
# a "Town Directory" overlay listing key civic buildings. The first interaction
# also adds each listed building to the hint panel in the top-left HUD.
# =============================================================================

var place_names: Array = []
var _dialogue:     DialogueManager
var _player:       PlayerController
var _goal_manager: GoalManager = null
var _prompt:       Label3D
var _in_range:     bool = false
var _is_open:      bool = false
var _hint_given:   bool = false


func setup(dialogue: DialogueManager, player: PlayerController, gm: GoalManager = null) -> void:
	_dialogue     = dialogue
	_player       = player
	_goal_manager = gm


func _ready() -> void:
	_build_visuals()
	_build_detection_area()


func _build_visuals() -> void:
	var post_mat   := _mat(Color(0.12, 0.10, 0.08))
	var border_mat := _mat(Color(0.12, 0.10, 0.08))
	var paper_mat  := _mat(Color(0.97, 0.95, 0.88))
	var line_mat   := _mat(Color(0.40, 0.38, 0.34))

	var board_cy := 1.025

	for lx in [-0.40, 0.40]:
		_box(Vector3(0.06, 0.55, 0.06), Vector3(lx, 0.20, 0.0), post_mat)

	_box(Vector3(1.25, 1.40, 0.10), Vector3(0.0, board_cy, 0.0), border_mat)
	_box(Vector3(1.15, 1.30, 0.06), Vector3(0.0, board_cy, 0.0), paper_mat)

	var widths := [0.65, 0.475, 0.325]
	var ys     := [0.25, 0.025, -0.20]
	for face_z in [-0.04, 0.04]:
		for i in 3:
			_box(Vector3(widths[i], 0.10, 0.04),
				Vector3(0.0, board_cy + ys[i], face_z), line_mat)

	_prompt = Label3D.new()
	_prompt.text = "!"
	_prompt.position = Vector3(0, 2.5, 0.0)
	_prompt.font_size = 256
	_prompt.pixel_size = 0.0045
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.modulate = Color(1.0, 0.85, 0.1)
	_prompt.outline_size = 20
	_prompt.outline_modulate = Color(0.1, 0.1, 0.1)
	_prompt.visible = false
	add_child(_prompt)


func _box(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


func _build_detection_area() -> void:
	var body   := StaticBody3D.new()
	var bcol   := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size   = Vector3(1.25, 1.40, 0.14)
	bcol.shape    = bshape
	bcol.position = Vector3(0.0, 1.025, 0.0)
	body.add_child(bcol)
	add_child(body)

	var area  := Area3D.new()
	var col   := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 4.0
	col.shape    = shape
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
	var can_read := _in_range and not _is_open and not _blocked()
	if _prompt.visible != can_read:
		_prompt.visible = can_read
	if Input.is_action_just_pressed("interact"):
		if _is_open:
			_close()
		elif can_read:
			_open()


func _blocked() -> bool:
	return NPCInteraction._cinematic \
		or NPCInteraction._active != null \
		or Poster._open_poster != null


func _open() -> void:
	_is_open = true
	_prompt.visible = false
	NPCInteraction._cinematic = true
	if _player != null:
		_player.set_input_enabled(false)
	if not _hint_given:
		_hint_given = true
		for name: String in place_names:
			var found := _goal_manager != null and _goal_manager.is_discovered(name)
			_dialogue.add_hint(name, found)
	_dialogue.show_directory("Town Directory", place_names)


func _close() -> void:
	_is_open = false
	_dialogue.hide_poster()
	NPCInteraction._cinematic = false
	if _player != null:
		_player.set_input_enabled(true)
