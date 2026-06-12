class_name NPCInteraction
extends Node3D
# =============================================================================
# NPCInteraction.gd
# -----------------------------------------------------------------------------
# A townsperson you talk to by VOICE. There are many of them spread across town
# (one per street); some patrol a path, some stand. Whichever one you walk up to
# becomes the active listener and gives directions from ITS OWN position.
#
#   1. Walk close  -> the mic turns on, a prompt floats over that NPC.
#   2. Say "Excuse me"             -> NPC answers "Yes?"
#   3. Say "Where is the <place>?" -> NPC gives a compass hint relative to where
#      it's standing, turns and points at the building, the camera reveals it.
#
# All NPCs share ONE microphone (SpeechInput), so a static `_active` reference
# makes sure only the NPC you're next to listens/responds. Keyboard fallback:
# press E to greet, E again for the destination menu.
# =============================================================================

enum State { IDLE, GREET, ASK }

# Only one NPC converses at a time (they share a single recognizer).
static var _active: NPCInteraction = null
# Set true during the opening cinematic to silence all NPC interaction.
static var _cinematic: bool = false

@export var shirt_color: Color = Color(0.85, 0.45, 0.20)
@export var pants_color: Color = Color(0.30, 0.28, 0.25)
@export var hair_color: Color = Color(0.10, 0.08, 0.06)
@export var speed: float = 2.0

var path: PackedVector3Array = PackedVector3Array()   # patrol loop (optional)

var _dialogue: DialogueManager
var _camera_focus: CameraFocusManager
var _player: PlayerController
var _goal_manager: GoalManager
var _goals: Dictionary
var _goal_names: Array
var _speech: SpeechInput

var _hum: Humanoid
var _arm_pivot: Node3D
var _hint: Label3D

var _state: int = State.IDLE
var _player_in_range: bool = false
var _conversing: bool = false   # true only once the player actually starts talking
var _walk_i: int = 0

var _face_start: Basis
var _face_end: Basis

const ARM_REST_X := 0.0
const ARM_POINT_X := PI * 0.5
const POINT_HOLD_SECONDS := 2.0
const HIDE_DIST := 70.0   # hide far-away NPCs entirely (cheap on low-end GPUs)


func _ready() -> void:
	_build_visuals()
	_build_detection_area()


func setup(dialogue: DialogueManager, camera_focus: CameraFocusManager,
		player: PlayerController, goal_manager: GoalManager,
		goals: Dictionary, goal_names: Array, speech: SpeechInput) -> void:
	_dialogue = dialogue
	_camera_focus = camera_focus
	_player = player
	_goal_manager = goal_manager
	_goals = goals
	_goal_names = goal_names
	_speech = speech
	_speech.heard.connect(_on_heard)


# -----------------------------------------------------------------------------
# Visuals + proximity
# -----------------------------------------------------------------------------
func _build_visuals() -> void:
	_hum = Humanoid.new()
	_hum.shirt_color = shirt_color
	_hum.pants_color = pants_color
	_hum.hair_color = hair_color
	_hum.walk_enabled = true
	add_child(_hum)
	_arm_pivot = _hum.right_arm_pivot
	_arm_pivot.rotation.x = ARM_REST_X

	# Solid body so the player bumps into the NPC instead of walking through it.
	var body := StaticBody3D.new()
	var bcol := CollisionShape3D.new()
	var bshape := CapsuleShape3D.new()
	bshape.radius = 0.4
	bshape.height = 1.8
	bcol.shape = bshape
	bcol.position.y = 0.9
	body.add_child(bcol)
	add_child(body)

	# A big cartoony "!" that pops over the NPC's head when the player is in
	# range (it always faces the camera).
	_hint = Label3D.new()
	_hint.text = "!"
	_hint.position.y = 2.95           # raised so the taller marker still clears the head
	_hint.font_size = 256
	_hint.pixel_size = 0.0045          # 5x larger than before (~1.15 units tall)
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.modulate = Color(1.0, 0.85, 0.1)   # bright yellow
	_hint.outline_size = 20
	_hint.outline_modulate = Color(0.1, 0.1, 0.1)
	_hint.visible = false
	add_child(_hint)


func _build_detection_area() -> void:
	var area := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 5.0
	col.shape = shape
	col.position.y = 1.0
	area.add_child(col)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body == _player:
		_player_in_range = true
		if _state == State.IDLE and _active == null and not _cinematic:
			_active = self
			_begin_greet()


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player_in_range = false
		_reset()


func _process(delta: float) -> void:
	var engaged := (_active == self)
	# Distance hiding: NPCs far from the player aren't drawn at all (you can
	# only talk to them up close anyway). Engaged NPCs always stay visible.
	if not engaged and _player != null:
		if global_position.distance_to(_player.global_position) > HIDE_DIST:
			if _hum.visible:
				_hum.visible = false
			return
		elif not _hum.visible:
			_hum.visible = true

	_update_walk(delta)
	if engaged and not _cinematic and Input.is_action_just_pressed("interact"):
		if _state == State.GREET:
			_greet()
		elif _state == State.ASK:
			_ask_via_menu()


# Keep patrolling even when the player is just nearby; only stand still once an
# actual conversation has started (and through the pointing).
func _update_walk(delta: float) -> void:
	if _conversing or path.size() < 2:
		_hum.walk_speed = 0.0
		return
	var to: Vector3 = path[_walk_i] - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.4:
		_walk_i = (_walk_i + 1) % path.size()
		return
	var dir := to / dist
	global_position += dir * speed * delta
	look_at(global_position + dir, Vector3.UP)
	_hum.walk_speed = speed


# -----------------------------------------------------------------------------
# Conversation state machine (speech or the E key)
# -----------------------------------------------------------------------------
func _begin_greet() -> void:
	_state = State.GREET
	_hint.visible = true     # show the "!" marker
	_speech.listen()


func _greet() -> void:
	_state = State.ASK
	_conversing = true      # now stop walking and engage
	_dialogue.speak("Yes?")
	_dialogue.show_text("Townsperson", "Yes?")
	_face_target(_player)   # turn to face the player once they say "Excuse me"
	_speech.listen()


func _on_heard(text: String) -> void:
	if _active != self or _cinematic:
		return
	var t := _clean(text)
	if _state == State.GREET and (t.contains("excuse me") or t.contains("pardon me") or t.contains("hello") or t.contains("good morning")):
		_greet()
	elif _state == State.ASK and (t.contains("hello") or t.contains("good morning")):
		var replies := ["Hello!", "Hi there!", "Good morning!", "Hey!"]
		var r: String = replies[randi() % replies.size()]
		_dialogue.speak(r)
		_dialogue.show_text("Townsperson", r)
		_speech.listen()
	elif _state == State.ASK and t.contains("how are you"):
		var replies := ["I'm fine!", "I'm good!", "I'm great, thanks!"]
		var r: String = replies[randi() % replies.size()]
		_dialogue.speak(r)
		_dialogue.show_text("Townsperson", r)
		_speech.listen()
	elif _state == State.ASK and t.contains("where is"):
		var dest := _match_goal(t)
		if dest == "":
			_dialogue.speak("Sorry, I don't know that place.")
			_dialogue.show_text("Townsperson", "Sorry, I don't know that place.")
			_speech.listen()
		else:
			_deliver(dest)
	elif _state != State.IDLE:
		_speech.listen()   # didn't catch it — keep the mic open


func _ask_via_menu() -> void:
	_state = State.IDLE
	_speech.stop()
	_player.set_input_enabled(false)
	_dialogue.speak("Where would you like to go?")
	var idx: int = await _dialogue.show_options(
			"Townsperson", "Where would you like to go?", _goal_names)
	_player.set_input_enabled(true)
	_deliver(_goal_names[idx])


func _deliver(dest_name: String) -> void:
	_state = State.IDLE
	_speech.stop()
	_hint.visible = false
	_player.set_input_enabled(false)
	var target: Node3D = _goals[dest_name]

	_dialogue.speak("It's over there!")
	_dialogue.show_text("Townsperson", "It's over there!")
	await _face_target(target)
	await _raise_arm()
	# Arm stays pointing through the pan out and the hold...
	await _camera_focus.pan_to(target, global_position)
	await get_tree().create_timer(POINT_HOLD_SECONDS).timeout
	# ...then it comes back down as the camera pans back to the player.
	_lower_arm()
	await _camera_focus.pan_back()

	_goal_manager.set_target(dest_name, target)
	_dialogue.hide_dialogue()
	_player.set_input_enabled(true)
	_conversing = false       # resume patrolling until the player asks again
	if _player_in_range:
		_begin_greet()        # ready for another question
	elif _active == self:
		_active = null
		_state = State.IDLE


func _reset() -> void:
	_state = State.IDLE
	_conversing = false
	_hint.visible = false
	if _active == self:
		_active = null
		_speech.stop()
		_dialogue.hide_dialogue()


# -----------------------------------------------------------------------------
# Matching + direction text (relative to THIS npc's position)
# -----------------------------------------------------------------------------
func _clean(s: String) -> String:
	var r := s.to_lower()
	for ch in ["'", ".", ",", "!", "?", "-", "’"]:
		r = r.replace(ch, "")
	return r


func _match_goal(cleaned_text: String) -> String:
	for n in _goal_names:
		if cleaned_text.contains(_clean(n)):
			return n
	return ""


# -----------------------------------------------------------------------------
# Turn + point animation
# -----------------------------------------------------------------------------
func _face_target(target: Node3D) -> void:
	var look_pos := target.global_position
	look_pos.y = global_position.y
	_face_start = global_transform.basis
	_face_end = global_transform.looking_at(look_pos, Vector3.UP).basis
	var tween := create_tween()
	tween.tween_method(_apply_face_rotation, 0.0, 1.0, 0.5)
	await tween.finished


func _apply_face_rotation(t: float) -> void:
	var q := _face_start.get_rotation_quaternion().slerp(
			_face_end.get_rotation_quaternion(), t)
	var tr := global_transform
	tr.basis = Basis(q)
	global_transform = tr


func _raise_arm() -> void:
	var tween := create_tween()
	tween.tween_property(_arm_pivot, "rotation:x", ARM_POINT_X, 0.4)
	await tween.finished


func _lower_arm() -> void:
	var tween := create_tween()
	tween.tween_property(_arm_pivot, "rotation:x", ARM_REST_X, 0.4)
	await tween.finished
