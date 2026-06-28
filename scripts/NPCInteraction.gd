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

# Phonetic / shorthand alternatives for goal names.
# Covers katakana-English pronunciation patterns common among Japanese
# elementary school students, plus Chrome STT mishear variants.
const GOAL_ALIASES: Dictionary = {
	"Library":          ["rye bra", "rai bura", "lie berry", "lie bra", "raiburari", "ribrary"],
	"Hospital":         ["hosu", "hospita", "hoshipital", "hosupita", "hosupi", "hospitoru"],
	"Drugstore":        ["drug store", "doraggu", "drag store"],
	"Bookstore":        ["book store", "bukku"],
	"Supermarket":      ["super market", "supa market", "suupaa"],
	"Convenience Store":["convenience", "konbini", "combini", "konbiniensu"],
	"Restaurant":       ["restoran", "resutoran", "resu"],
	"Swimming Pool":    ["swim pool", "suimingu", "sweeming pool", "swimmin pool"],
	"Starbucks":        ["star bucks", "star box"],
	"Gas Station":      ["gas stand", "gasorin", "gasoline station", "gasorin station"],
	"Post Office":      ["post offis", "postu"],
	"Museum":           ["myuzeum", "myujiamu", "myuziam", "mezeum"],
	"City Hall":        ["city hole", "shiti hall", "shitty hall"],
	"Police Station":   ["porisu", "police stay shun", "poris"],
	"Fire Station":     ["faia station", "fire stay shun"],
	"Shopping Mall":    ["mall", "seven park", "shopping center", "shoppin"],
	"Bakery":           ["beika ri", "beikari", "bake ri"],
	"Bank":             ["banco"],
	"School":           ["sukuru", "sukuuru"],
	"Church":           ["chaachi", "chachi"],
	"Hotel":            ["hoteru"],
	"Nolan's House":    ["nolan house", "nolan home", "norans house", "noran house"],
}

# Accepted renderings of the mandatory "Where is ...?" carrier (the grammar point).
# Tolerant of JP-L1 pronunciation and STT mistranscription, but every entry still
# contains the where + copula structure, so a bare "where" (dropped "is") is NOT
# accepted — the student must produce the copula. Contracted "where's" counts.
const WHERE_IS_PHRASES: Array = [
	"where is", "where's", "wheres", "where iz", "wherez", "where his",
	"wear is", "ware is", "were is", "wea is", "weah is", "whereis",
	"wears", "wares",   # engine renderings of the "where's" contraction
]

enum State { IDLE, GREET, ASK }

# Only one NPC converses at a time (they share a single recognizer).
static var _active: NPCInteraction = null
# Set true during the opening cinematic to silence all NPC interaction.
static var _cinematic: bool = false

@export var shirt_color: Color = Color(0.85, 0.45, 0.20)
@export var pants_color: Color = Color(0.30, 0.28, 0.25)
@export var hair_color: Color = Color(0.10, 0.08, 0.06)
@export var female: bool = false
@export var height_scale: float = 1.0
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
var _query: Label3D    # "?" shown briefly when the NPC doesn't understand

var _state: int = State.IDLE
var _player_in_range: bool = false
var _conversing: bool = false   # true only once the player actually starts talking
var _walk_i: int = 0
var _greeted: bool = false      # true after first greeting reply this conversation

enum MicState { OFF, LISTENING, PROCESSING }
var _mic_state: int = MicState.OFF
var _mic_dot: MeshInstance3D
var _ripples: Array[MeshInstance3D] = []   # concentric sonar rings around the dot
var _ellipsis_dots: Array[MeshInstance3D] = []  # three bouncing dots shown while processing
var _dot_timer: float = 0.0

const RIPPLE_COUNT := 3
const RIPPLE_PERIOD := 1.4    # seconds for one ring to grow + fade
const RIPPLE_MIN := 0.30      # starting radius scale
const RIPPLE_MAX := 1.30      # ending radius scale

var npc_name: String = "Townsperson"
var voice_pitch: float = 1.0
var voice_rate: float = 0.88
var voice_index: int = 0
var voice_family: String = "female"

var _face_start: Basis
var _face_end: Basis

const ARM_REST_X := 0.0
const ARM_POINT_X := PI * 0.5
const POINT_HOLD_SECONDS := 2.0
const QUESTION_FLASH_SECONDS := 1.2


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
	_speech.speech_started.connect(_on_speech_started)
	_dialogue.text_submitted.connect(_on_text_submitted)


# -----------------------------------------------------------------------------
# Visuals + proximity
# -----------------------------------------------------------------------------
func _build_visuals() -> void:
	_hum = Humanoid.new()
	_hum.shirt_color = shirt_color
	_hum.pants_color = pants_color
	_hum.hair_color = hair_color
	_hum.female = female
	_hum.walk_enabled = true
	add_child(_hum)
	_hum.scale = Vector3(height_scale, height_scale, height_scale)
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
	_hint.visibility_range_end = 70.0
	_hint.visibility_range_end_margin = 4.0
	_hint.visible = false
	add_child(_hint)

	# A "?" in the same style as the "!", flashed when the NPC can't make out
	# what the player said while listening.
	_query = Label3D.new()
	_query.text = "?"
	_query.position.y = 2.95
	_query.font_size = 256
	_query.pixel_size = 0.0045
	_query.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_query.modulate = Color(1.0, 0.85, 0.1)
	_query.outline_size = 20
	_query.outline_modulate = Color(0.1, 0.1, 0.1)
	_query.visibility_range_end = 70.0
	_query.visibility_range_end_margin = 4.0
	_query.visible = false
	add_child(_query)

	# Listening indicator: a glowing cyan sphere (a mesh, so it never depends on
	# whether a given glyph exists in the font).
	_mic_dot = MeshInstance3D.new()
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.22
	dot_mesh.height = 0.44
	_mic_dot.mesh = dot_mesh
	var dot_mat := StandardMaterial3D.new()
	dot_mat.albedo_color = Color(0.25, 0.85, 1.0)
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.emission_enabled = true
	dot_mat.emission = Color(0.25, 0.85, 1.0)
	dot_mat.emission_energy_multiplier = 2.0
	_mic_dot.material_override = dot_mat
	_mic_dot.position.y = 2.95
	_mic_dot.visibility_range_end = 70.0
	_mic_dot.visibility_range_end_margin = 4.0
	_mic_dot.visible = false
	add_child(_mic_dot)

	# Sonar ripples: thin cyan rings that grow outward from the dot and fade,
	# staggered in phase so a steady stream radiates while the mic is open.
	for i in RIPPLE_COUNT:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.46
		torus.outer_radius = 0.56
		ring.mesh = torus
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.25, 0.85, 1.0, 0.0)
		rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.emission_enabled = true
		rmat.emission = Color(0.25, 0.85, 1.0)
		rmat.emission_energy_multiplier = 1.5
		ring.material_override = rmat
		ring.position.y = 2.95
		ring.visibility_range_end = 70.0
		ring.visibility_range_end_margin = 4.0
		ring.visible = false
		add_child(ring)
		_ripples.append(ring)

	# Processing indicator: three small bouncing cyan spheres shown while the
	# speech recogniser has detected audio and is waiting for a transcript.
	var emat := StandardMaterial3D.new()
	emat.albedo_color = Color(0.25, 0.85, 1.0)
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emat.emission_enabled = true
	emat.emission = Color(0.25, 0.85, 1.0)
	emat.emission_energy_multiplier = 2.0
	for i in 3:
		var ed := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.10
		em.height = 0.20
		ed.mesh = em
		ed.material_override = emat
		ed.position = Vector3((i - 1) * 0.30, 2.95, 0.0)
		ed.visibility_range_end = 70.0
		ed.visibility_range_end_margin = 4.0
		ed.visible = false
		add_child(ed)
		_ellipsis_dots.append(ed)


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
	_update_walk(delta)
	if engaged and not _cinematic and _state == State.GREET:
		if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept"):
			_greet()
	if engaged and not _cinematic and _state == State.ASK:
		if Input.is_action_just_pressed("ui_cancel"):
			_reset()

	if _mic_state != MicState.OFF:
		_dot_timer += delta
	if _mic_state == MicState.LISTENING:
		var pulse := 1.0 + 0.15 * sin(_dot_timer * 3.5)
		_mic_dot.scale = Vector3(pulse, pulse, pulse)
	elif _mic_state == MicState.PROCESSING:
		for i in 3:
			var bounce := 0.10 * absf(sin(_dot_timer * 7.0 - float(i) * 1.1))
			_ellipsis_dots[i].position.y = 2.95 + bounce
		if _dot_timer > 5.0:
			_set_mic_state(MicState.LISTENING)
		var cam := get_viewport().get_camera_3d()
		var head_pos := global_transform * Vector3(0.0, 2.95, 0.0)
		# Build a camera-facing basis: the torus hole-axis (local +Y) points at the
		# camera so each ring is seen face-on, like Wi-Fi arcs radiating outward.
		var face := Basis()
		if cam != null:
			var dir := (cam.global_position - head_pos).normalized()
			var bx := Vector3.UP.cross(dir)
			if bx.length() < 0.0001:
				bx = Vector3.RIGHT
			bx = bx.normalized()
			var bz := bx.cross(dir).normalized()
			face = Basis(bx, dir, bz)
		for i in _ripples.size():
			var phase: float = fmod(_dot_timer / RIPPLE_PERIOD + float(i) / RIPPLE_COUNT, 1.0)
			var rad: float = lerpf(RIPPLE_MIN, RIPPLE_MAX, phase)
			var ring := _ripples[i]
			var b := face
			b.x *= rad      # scale the ring's in-plane axes -> grows the radius
			b.z *= rad
			ring.global_transform = Transform3D(b, head_pos)
			# Fade in quickly, then out as the ring expands.
			var a: float = clampf(phase * 4.0, 0.0, 1.0) * (1.0 - phase)
			var rmat := ring.material_override as StandardMaterial3D
			rmat.albedo_color.a = a * 0.85


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


func _greet(via_keyboard: bool = true) -> void:
	_state = State.ASK
	_conversing = true
	_greeted = false
	_dialogue.speak("Yes?", voice_pitch, voice_rate, voice_index, voice_family)
	_dialogue.show_text(npc_name,"Yes?")
	_face_target(_player)
	_hint.visible = false
	_speech.listen()
	_set_mic_state(MicState.LISTENING)
	if via_keyboard:
		_dialogue.show_text_input()


func _on_heard(text: String) -> void:
	if _active != self or _cinematic:
		return
	# Alternatives are newline-separated (up to 5 from the STT engine).
	var alts := text.split("|", false)
	if alts.is_empty():
		return
	if _state == State.GREET and _heard(alts, ["how are you", "how you", "how are"]):
		var replies := ["I'm fine!", "I'm good!", "I'm great, thanks!"]
		var r: String = replies[randi() % replies.size()]
		_dialogue.speak(r, voice_pitch, voice_rate, voice_index, voice_family)
		_dialogue.show_text(npc_name, r)
		_speech.listen()
	elif _state == State.GREET and _heard(alts, ["hello", "good morning", "haro", "morning"]):
		var replies := ["Hello!", "Hi there!", "Good morning!", "Hey!"]
		var r: String = replies[randi() % replies.size()]
		_dialogue.speak(r, voice_pitch, voice_rate, voice_index, voice_family)
		_dialogue.show_text(npc_name, r)
		_speech.listen()
	elif _state == State.GREET and _heard(alts, ["excuse me", "excuse", "ekusukyu"]):
		_greet(false)
	elif _state == State.ASK and _heard(alts, ["bye", "goodbye", "see you", "thank you", "senkyu", "baibai"]):
		var farewells := ["See you!", "Take care!", "Goodbye!", "Anytime, good luck!"]
		var r: String = farewells[randi() % farewells.size()]
		_dialogue.speak(r, voice_pitch, voice_rate, voice_index, voice_family)
		_dialogue.show_text(npc_name, r)
		_dialogue.hide_text_input()
		_reset()
	elif _state == State.ASK and _heard(alts, ["hello", "good morning", "haro", "morning"]):
		if not _greeted:
			_greeted = true
			var replies := ["Hello!", "Hi there!", "Good morning!", "Hey!"]
			var r: String = replies[randi() % replies.size()]
			_dialogue.speak(r, voice_pitch, voice_rate, voice_index, voice_family)
			_dialogue.show_text(npc_name, r)
		_set_mic_state(MicState.LISTENING)
		_speech.listen()
	elif _state == State.ASK and _heard(alts, ["how are you", "how you", "how are"]):
		var replies := ["I'm fine!", "I'm good!", "I'm great, thanks!"]
		var r: String = replies[randi() % replies.size()]
		_dialogue.speak(r, voice_pitch, voice_rate, voice_index, voice_family)
		_dialogue.show_text(npc_name, r)
		_set_mic_state(MicState.LISTENING)
		_speech.listen()
	elif _state == State.ASK:
		# Try every STT alternative for "where is <place>".
		var dest := ""
		var had_where_is := false
		for alt in alts:
			var c := _clean(alt)
			if _has_where_is(c):
				had_where_is = true
				dest = _match_goal(c)
				if dest != "":
					break
		if dest != "":
			_deliver(dest)
		elif had_where_is:
			_dialogue.speak("Sorry, I don't know that place.", voice_pitch, voice_rate, voice_index, voice_family)
			_dialogue.show_text(npc_name, "Sorry, I don't know that place.")
			_set_mic_state(MicState.LISTENING)
			_speech.listen()
		else:
			_flash_question()
	elif _state != State.IDLE:
		_speech.listen()


# Text input submitted from the keyboard pipeline — route through same logic as STT.
func _on_text_submitted(text: String) -> void:
	if _active != self or _cinematic or _state != State.ASK:
		return
	if text.strip_edges().is_empty():
		_reset()
		return
	_on_heard(text)


func _deliver_directions_only(dest_name: String) -> void:
	# Re-navigate to an already-discovered building via text (no reward, no ring).
	_dialogue.hide_text_input()
	_dialogue.speak("It's over there!", voice_pitch, voice_rate, voice_index, voice_family)
	_dialogue.show_text(npc_name,"It's over there!")
	_goal_manager.set_target(dest_name, _goals[dest_name])


func _deliver(dest_name: String) -> void:
	_state = State.IDLE
	_speech.stop()
	_hint.visible = false
	_query.visible = false
	_set_mic_state(MicState.OFF)
	_dialogue.hide_text_input()
	_player.set_input_enabled(false)
	var target: Node3D = _goals[dest_name]

	_dialogue.speak("It's over there!", voice_pitch, voice_rate, voice_index, voice_family)
	_dialogue.show_text(npc_name,"It's over there!")
	await _face_target(target)
	await _raise_arm()
	await _camera_focus.pan_to(target, global_position)
	await get_tree().create_timer(POINT_HOLD_SECONDS).timeout
	await _camera_focus.pan_back()
	await _lower_arm()

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
	_greeted = false
	_hint.visible = false
	_query.visible = false
	_set_mic_state(MicState.OFF)
	if _active == self:
		_active = null
		_speech.stop()
		_dialogue.hide_dialogue()
		_dialogue.hide_text_input()


func _flash_question() -> void:
	# Hide the listening dot/ripples, show "?" briefly, keep the mic open
	# underneath, then restore the listening indicator if still in the ask phase.
	_set_mic_state(MicState.OFF)
	_query.visible = true
	_speech.listen()
	await get_tree().create_timer(QUESTION_FLASH_SECONDS).timeout
	_query.visible = false
	if _active == self and _state == State.ASK:
		_set_mic_state(MicState.LISTENING)


func _on_speech_started() -> void:
	if _active != self or _cinematic:
		return
	if _mic_state == MicState.LISTENING:
		_set_mic_state(MicState.PROCESSING)


func _set_mic_state(state: int) -> void:
	_mic_state = state
	_dot_timer = 0.0
	match state:
		MicState.OFF:
			_mic_dot.visible = false
			for ring in _ripples:
				ring.visible = false
			for ed in _ellipsis_dots:
				ed.visible = false
		MicState.LISTENING:
			_mic_dot.scale = Vector3.ONE
			_mic_dot.visible = true
			for ring in _ripples:
				ring.visible = true
			for ed in _ellipsis_dots:
				ed.visible = false
		MicState.PROCESSING:
			_mic_dot.visible = false
			for ring in _ripples:
				ring.visible = false
			for ed in _ellipsis_dots:
				ed.visible = true


# -----------------------------------------------------------------------------
# Matching + direction text (relative to THIS npc's position)
# -----------------------------------------------------------------------------
func _clean(s: String) -> String:
	var r := s.to_lower()
	for ch in ["’", ".", ",", "!", "?", "-", "’"]:
		r = r.replace(ch, "")
	return r


# True if the cleaned text is a genuine "Where is ...?" attempt (copula required).
func _has_where_is(cleaned_text: String) -> bool:
	for p in WHERE_IS_PHRASES:
		if cleaned_text.contains(p):
			return true
	return false


# Returns true if any STT alternative contains at least one of the given phrases.
func _heard(alts: PackedStringArray, phrases: Array) -> bool:
	for alt in alts:
		var c := _clean(alt)
		for phrase in phrases:
			if c.contains(phrase):
				return true
	return false


func _match_goal(cleaned_text: String) -> String:
	for n in _goal_names:
		if cleaned_text.contains(_clean(n)):
			return n
	for goal_name in GOAL_ALIASES:
		if not _goal_names.has(goal_name):
			continue
		for alias in GOAL_ALIASES[goal_name]:
			if cleaned_text.contains(alias):
				return goal_name
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
