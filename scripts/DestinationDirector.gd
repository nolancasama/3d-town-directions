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

const REACTIONS: Dictionary = {
	"Restaurant": "Yum!",
	"Bakery": "Yum!",
	"Convenience Store": "Yum!",
	"Supermarket": "Yum!",
	"Starbucks": "Ahh, refreshing!",
	"Hotel": "I feel better!",
	"Park": "I feel better!",
}

# Matsubara-kun's name in the dialogue panel, matching the intro cinematic
# (Main.gd's _play_intro), so the same speaker label is used everywhere.
const MATSUBARA_NAME := "Matsubara kun"

# One-time cultural comment, shown the first time the player discovers each place.
const MATSUBARA_ARRIVAL: Dictionary = {
	"Library": "図書館って静かでええなぁ。本いっぱいあるで！",
	"Bank": "銀行や！日本やとATM使う人も多いな。",
	"Post Office": "郵便局やな。赤い〒マーク、よう見るやろ？",
	"Museum": "博物館や！昔のもん見るん、けっこうおもろいやん。",
	"City Hall": "市役所やな。引っ越しとか、いろんな手続きするとこやで。",
	"Police Station": "警察署や。日本には小さい「交番」もようあるで！",
	"Fire Station": "消防署や！赤い消防車、めっちゃ目立つなぁ。",
	"Hospital": "病院やな。元気なんがいちばんやで！",
	"Drugstore": "ドラッグストアや！薬だけやなくて、お菓子とかも売ってるで。",
	"Bakery": "パン屋さんや！日本のパン屋、種類めっちゃ多いねんな。",
	"Bookstore": "本屋や！マンガのコーナー、つい見てまうわ。",
	"Starbucks": "スタバやな。日本限定の飲みもん出ることあるで！",
	"Restaurant": "レストランや！さて、何食べよかな〜。",
	"Supermarket": "スーパーや。夕方になると、お弁当が安なることもあるで！",
	"Convenience Store": "コンビニや！日本のコンビニ、ほんま何でもあるなぁ。",
	"Gas Station": "ガソリンスタンドや。日本やと「セルフ」の店も多いで。",
	"School": "学校や！日本の学校って、みんなで掃除すること多いねんで。",
	"Swimming Pool": "プールや！学校の夏のプール、懐かしいなぁ。",
	"Church": "教会やな。日本やと結婚式で見ることも多いで。",
	"Hotel": "ホテルや！いっぱい歩いたし、ここで休みたいわ〜。",
	"Nolan's House": "ノーラン先生の家や！おじゃましまーす！",
	"Park": "公園や！ちょっと休むんにちょうどええな。",
	"Train Station": "駅や！関西は電車いっぱいあるから便利やで。",
	"Beach": "海やー！大阪からやったら、夏は海行きたなるなぁ！",
	"Shopping Mall": "ショッピングモールや！ごはんも買いもんも、ここで全部できそうやな。",
}
# Short reaction shown on every later visit, so repeat travel stays quick.
const MATSUBARA_ARRIVAL_REPEAT: Dictionary = {
	"Library": "また図書館来たな。",
	"Bank": "また銀行やな。",
	"Post Office": "また郵便局来たわ。",
	"Museum": "また博物館やな！",
	"City Hall": "また市役所来たな。",
	"Police Station": "また警察署やな。",
	"Fire Station": "また消防車見れるかな？",
	"Hospital": "また病院やな。",
	"Drugstore": "またドラッグストア来たな。",
	"Bakery": "またええ匂いしてるわ〜。",
	"Bookstore": "また本屋来たな。",
	"Starbucks": "またスタバやな。",
	"Restaurant": "またここでごはんか〜。",
	"Supermarket": "またスーパー来たな。",
	"Convenience Store": "またコンビニやな。",
	"Gas Station": "またガソリンスタンドやな。",
	"School": "また学校来たな。",
	"Swimming Pool": "またプールやな！",
	"Church": "また教会来たな。",
	"Hotel": "またホテルやな。",
	"Nolan's House": "またおじゃまします！",
	"Park": "また公園来たな。",
	"Train Station": "また駅来たな。",
	"Beach": "また海来たな！",
	"Shopping Mall": "またモール来たな。",
}
# Reading pace for Matsubara's arrival line: proportional to length (Japanese
# reads slower for elementary students than the typewriter's own pace implies),
# clamped so a short repeat line is never gone before it can be read and a long
# first-visit line never overstays it.
const MATSUBARA_MIN_SECONDS := 2.2
const MATSUBARA_MAX_SECONDS := 5.5
const MATSUBARA_SECONDS_PER_CHAR := 0.09
const MATSUBARA_BASE_SECONDS := 1.8

# Matsubara's "what now" line, shown after the place comment on every assigned
# arrival -- hungry/thirsty/tired pool if a need is active, general pool if not.
# This replaces the old plain-text need banner ("I'm hungry!") entirely: the
# state is now something Matsubara says, not a system alert.
const STATE_LINES_HUNGER: Array[String] = [
	"ちょっとお腹すいてきたわ。なんか食べに行きたいな。",
	"お腹ぺこぺこやわ。ごはん食べられるとこ行こか。",
]
const STATE_LINES_THIRST: Array[String] = [
	"なんか喉かわいたなぁ。飲みもんほしいわ。",
	"ちょっと喉カラカラや。なんか飲みに行こ。",
]
const STATE_LINES_TIREDNESS: Array[String] = [
	"ちょっと疲れてきたわ。ひと休みしたいなぁ。",
	"よう歩いたし、ちょっと休みたいわ。",
]
const STATE_LINES_GENERAL: Array[String] = [
	"次はどこ行こかな？",
	"さて、次はどこ行こか。",
	"次はどこ目指そかな。",
	"ほな、次の場所決めよか。",
]

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


func _on_arrival_completed(destination: String, first_discovery: bool) -> void:
	# Matsubara reacts to every arrival, not only assigned ones -- a place found
	# by curiosity deserves the same personality as one the player was sent to.
	# Needs and the next three-choice overlay stay tied to the assigned trip.
	_set_modal_active(true)
	await _show_matsubara_comment(destination, first_discovery)

	if destination != assigned_destination:
		_set_modal_active(false)
		return

	assigned_destination = ""
	_dialogue.clear_destination_card()
	trip_count += 1

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

	# Matsubara always says where his head's at before the next choice -- this
	# is the ONLY presentation of the need state now; there is no separate
	# system banner alongside it.
	await _show_matsubara_state(active_need)

	await _offer_destination(destination)
	_set_modal_active(false)


# Displays one Matsubara line in the dialogue panel for a readable pause, then
# clears it. Shared by the place comment and the state comment below, so both
# use the exact same presentation -- Matsubara talking, never a system banner.
func _speak_matsubara(line: String) -> void:
	if line == "":
		return
	_dialogue.show_text(MATSUBARA_NAME, line)
	var seconds := clampf(
			MATSUBARA_BASE_SECONDS + float(line.length()) * MATSUBARA_SECONDS_PER_CHAR,
			MATSUBARA_MIN_SECONDS, MATSUBARA_MAX_SECONDS)
	await get_tree().create_timer(seconds).timeout
	_dialogue.hide_dialogue()


# Matsubara's reaction to the place just reached: the full cultural line on a
# first discovery, a short one on every later visit. Never called while the
# player is still walking -- only from the post-arrival hook below.
func _show_matsubara_comment(destination: String, first_discovery: bool) -> void:
	var line: String = String(MATSUBARA_ARRIVAL.get(destination, ""))
	if not first_discovery:
		var repeat_line: String = String(MATSUBARA_ARRIVAL_REPEAT.get(destination, ""))
		if repeat_line != "":
			line = repeat_line
	await _speak_matsubara(line)


# Matsubara's "what now" line: hungry/thirsty/tired if a need is active after
# this arrival's need bookkeeping, otherwise a general "where to?" line. Shown
# on every assigned arrival, repeat visits included, right before the next
# three-choice overlay opens.
func _show_matsubara_state(need: String) -> void:
	var pool: Array[String] = STATE_LINES_GENERAL
	match need:
		"Hunger":
			pool = STATE_LINES_HUNGER
		"Thirst":
			pool = STATE_LINES_THIRST
		"Tiredness":
			pool = STATE_LINES_TIREDNESS
	if pool.is_empty():
		return
	await _speak_matsubara(pool[_rng.randi_range(0, pool.size() - 1)])


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
