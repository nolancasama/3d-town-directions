class_name DestinationDirector
extends Node
# =============================================================================
# DestinationDirector.gd
# -----------------------------------------------------------------------------
# Owns the assigned-destination loop layered above GoalManager navigation. It
# offers three places after each completed assigned trip and schedules invisible
# character needs at predictable trip-count milestones.
# =============================================================================

const NEED_SCHEDULE: Array[Dictionary] = [
	{"need": "Thirst", "trip": 2, "jitter": 0},
	{"need": "Hunger", "trip": 4, "jitter": 1},
	{"need": "Tiredness", "trip": 7, "jitter": 1},
]
const REPEATING_NEED_SCHEDULE: Array[Dictionary] = [
	{"need": "Thirst", "gap": 3, "jitter": 1},
	{"need": "Hunger", "gap": 3, "jitter": 1},
	{"need": "Tiredness", "gap": 3, "jitter": 1},
]

const HUNGER_PLACES: Array[String] = [
	"Restaurant", "Bakery", "Convenience Store", "Supermarket",
]
const THIRST_PLACES: Array[String] = [
	"Starbucks", "Convenience Store", "Restaurant",
]
const TIREDNESS_PLACES: Array[String] = [
	"Hotel", "Park", "Starbucks",
]

const NEED_LINES: Dictionary = {
	"Hunger": "I'm hungry!",
	"Thirst": "I'm thirsty!",
	"Tiredness": "I'm tired!",
}
const REACTIONS: Dictionary = {
	"Restaurant": "Yum!",
	"Bakery": "Yum!",
	"Convenience Store": "Yum!",
	"Supermarket": "Yum!",
	"Starbucks": "Ahh, refreshing!",
	"Hotel": "I feel better!",
	"Park": "I feel better!",
}

const CHOICE_PROMPT := "Where do you want to go next?"

# Shown once, after the very first destination is chosen, to teach the loop:
# choose a place -> walk up to a townsperson -> ask -> follow the directions.
const TUTORIAL_LINE_1 := "人に近づいて、「Excuse me. Where is %s?」と聞いてみよう！"
const TUTORIAL_LINE_2 := "人に近づくと話しかけられるよ。"
const RECENT_OFFER_LIMIT := 2
const NORMAL_TRIPS_AFTER_NEED := 2
const REFUSAL_PROBABILITY := 0.28
# Master switch for NPC refusals ("I don't know. Ask him/her."). Currently OFF:
# every townsperson answers. Nothing about the feature is deleted — the referral
# search, the point-and-camera reveal, the recorded voice clips, the Japanese
# gloss, and the one-redirect cap all remain — so setting this back to true
# restores the behaviour exactly as it was.
const REFUSALS_ENABLED := false

var trip_count: int = 0
var active_need: String = ""
var assigned_destination: String = ""

var _dialogue: DialogueManager
var _goal_manager: GoalManager
var _player: PlayerController
var _goal_names: Array[String] = []
var _interaction_guard: Callable
var _rng := RandomNumberGenerator.new()

var _scheduled_needs: Array[String] = []
var _scheduled_trips: Array[int] = []
var _schedule_index: int = 0
var _repeat_index: int = 0
var _repeat_trip: int = 0
var _pending_needs: Array[String] = []
var _normal_trips_remaining: int = 0
var _recent_offer_keys: Array[String] = []
var _consecutive_refusals: int = 0
var _destination_questions: int = 0
var _tutorial_shown: bool = false


func setup(dialogue: DialogueManager, goal_manager: GoalManager,
		player: PlayerController, goal_names: Array[String],
		interaction_guard: Callable) -> void:
	_dialogue = dialogue
	_goal_manager = goal_manager
	_player = player
	_goal_names = goal_names.duplicate()
	_interaction_guard = interaction_guard
	_rng.randomize()
	_build_need_schedule()
	_goal_manager.arrival_completed.connect(_on_arrival_completed)


func start() -> void:
	_set_modal_active(true)
	await _offer_destination("")
	_set_modal_active(false)


func should_refuse(destination: String, has_nearby_referral: bool) -> bool:
	if not REFUSALS_ENABLED:
		return false
	_destination_questions += 1
	if _destination_questions == 1:
		return false
	if destination != assigned_destination or not has_nearby_referral:
		return false
	# One redirect only: after a single "I don't know", the next townsperson the
	# player asks always answers, so a chain never builds up.
	if _consecutive_refusals >= 1:
		return false
	if _rng.randf() >= REFUSAL_PROBABILITY:
		return false
	_consecutive_refusals += 1
	return true


func note_directions_given(_destination: String) -> void:
	_consecutive_refusals = 0


func _build_need_schedule() -> void:
	_scheduled_needs.clear()
	_scheduled_trips.clear()
	var last_trip := 0
	for entry: Dictionary in NEED_SCHEDULE:
		var jitter := int(entry["jitter"])
		var due_trip := int(entry["trip"]) + _rng.randi_range(0, jitter)
		_scheduled_needs.append(String(entry["need"]))
		_scheduled_trips.append(due_trip)
		last_trip = maxi(last_trip, due_trip)
	_repeat_trip = last_trip + _next_repeat_gap()


func _next_repeat_gap() -> int:
	var entry: Dictionary = REPEATING_NEED_SCHEDULE[_repeat_index]
	var gap := int(entry["gap"])
	var jitter := int(entry["jitter"])
	return gap + _rng.randi_range(0, jitter)


func _collect_due_needs() -> void:
	while _schedule_index < _scheduled_trips.size() \
			and _scheduled_trips[_schedule_index] <= trip_count:
		_pending_needs.append(_scheduled_needs[_schedule_index])
		_schedule_index += 1

	while _schedule_index >= _scheduled_trips.size() and _repeat_trip <= trip_count:
		var entry: Dictionary = REPEATING_NEED_SCHEDULE[_repeat_index]
		_pending_needs.append(String(entry["need"]))
		_repeat_index = (_repeat_index + 1) % REPEATING_NEED_SCHEDULE.size()
		_repeat_trip += _next_repeat_gap()


func _on_arrival_completed(destination: String) -> void:
	if destination != assigned_destination:
		return

	assigned_destination = ""
	_dialogue.clear_destination_card()
	trip_count += 1
	_set_modal_active(true)

	var resolved_need := false
	if active_need != "" and _need_places(active_need).has(destination):
		resolved_need = true
		active_need = ""
		_normal_trips_remaining = NORMAL_TRIPS_AFTER_NEED
		var reaction := String(REACTIONS.get(destination, "I feel better!"))
		await _dialogue.show_center_message(reaction)

	_collect_due_needs()
	if not resolved_need and active_need == "" and _normal_trips_remaining > 0:
		_normal_trips_remaining -= 1

	if active_need == "" and _normal_trips_remaining == 0:
		var next_need := _take_next_eligible_need(destination)
		if next_need != "":
			active_need = next_need
			await _dialogue.show_center_message(String(NEED_LINES[active_need]))

	await _offer_destination(destination)
	_set_modal_active(false)


func _take_next_eligible_need(last_arrived: String) -> String:
	if _pending_needs.is_empty():
		return ""
	var next_need := _pending_needs[0]
	var available := _need_places(next_need)
	available.erase(last_arrived)
	# Thirst and tiredness have exactly three valid buildings. If the player has
	# just arrived at one of them, hold the due need until all three can be shown
	# without immediately re-offering the place they reached.
	if available.size() < 3:
		return ""
	_pending_needs.remove_at(0)
	return next_need


func _offer_destination(last_arrived: String) -> void:
	var places := _generate_choices(last_arrived)
	if places.size() != 3:
		push_error("DestinationDirector could not generate exactly three choices.")
		return
	var chosen_index: int = await _dialogue.show_destination_choice(CHOICE_PROMPT, places)
	_dialogue.hide_destination_choice()
	if chosen_index < 0 or chosen_index >= places.size():
		return

	assigned_destination = places[chosen_index]
	_consecutive_refusals = 0
	# Assignment only: do NOT call GoalManager.set_target() here. The ring, timer,
	# and directions must wait until the player asks an NPC "Where is the <place>?".
	_dialogue.set_destination_card(assigned_destination)

	if not _tutorial_shown:
		_tutorial_shown = true
		# Match the game's existing article rule: possessive names take no "the".
		var article := "" if assigned_destination.contains("'s") else "the "
		_dialogue.show_tutorial_hint(
				TUTORIAL_LINE_1 % (article + assigned_destination), TUTORIAL_LINE_2)


func _generate_choices(last_arrived: String) -> Array[String]:
	var source: Array[String]
	if active_need != "":
		source = _need_places(active_need)
	else:
		source = _goal_names.duplicate()
	source.erase(last_arrived)

	var fallback: Array[String] = []
	var preferred: Array[String] = []
	for place: String in source:
		if active_need == "" and _goal_manager.is_discovered(place):
			fallback.append(place)
		else:
			preferred.append(place)

	var latest: Array[String] = []
	for attempt in 12:
		_shuffle(preferred)
		_shuffle(fallback)
		latest.clear()
		for place: String in preferred:
			if latest.size() == 3:
				break
			latest.append(place)
		for place: String in fallback:
			if latest.size() == 3:
				break
			latest.append(place)
		if latest.size() != 3:
			return latest
		var key := _offer_key(latest)
		if not _recent_offer_keys.has(key) or attempt == 11:
			_remember_offer(key)
			return latest.duplicate()
	return latest


func _need_places(need: String) -> Array[String]:
	match need:
		"Hunger":
			return HUNGER_PLACES.duplicate()
		"Thirst":
			return THIRST_PLACES.duplicate()
		"Tiredness":
			return TIREDNESS_PLACES.duplicate()
	return []


func _shuffle(items: Array[String]) -> void:
	for i in range(items.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, i)
		var held := items[i]
		items[i] = items[swap_index]
		items[swap_index] = held


func _offer_key(places: Array[String]) -> String:
	var ordered := places.duplicate()
	ordered.sort()
	return "|".join(PackedStringArray(ordered))


func _remember_offer(key: String) -> void:
	_recent_offer_keys.append(key)
	while _recent_offer_keys.size() > RECENT_OFFER_LIMIT:
		_recent_offer_keys.remove_at(0)


func _set_modal_active(active: bool) -> void:
	_player.set_input_enabled(not active)
	if _interaction_guard.is_valid():
		_interaction_guard.call(active)
