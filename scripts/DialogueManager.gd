class_name DialogueManager
extends CanvasLayer
# =============================================================================
# DialogueManager.gd
# =============================================================================

signal option_selected(index: int)
signal text_submitted(text: String)   # fired when player submits text input
signal destination_selected(index: int)

var _center_label: Label
var _panel: PanelContainer
var _speaker_label: Label
var _text_label: Label
var _text_jp: Label        # optional Japanese gloss under the English line
var _options_scroll: ScrollContainer
var _options_grid: GridContainer
var _dir_panel: PanelContainer
var _dir_title: Label
var _dir_text: Label
var _text_input: LineEdit

# Assigned destination card (top-centre objective banner)
var _destination_card: PanelContainer
var _destination_name: Label
var _dest_tween: Tween = null

# Discovery progress (compact top-left counter; full list on demand)
var _disc_panel: PanelContainer
var _disc_count: Label
var _disc_style: StyleBoxFlat
var _disc_style_hover: StyleBoxFlat
var _disc_total: int = 0
var _found_count: int = 0        # all discovered buildings (hinted or not)
var _known: Array[String] = []   # places the player has learned of, in order
var _found: Dictionary = {}      # place name -> true once discovered
var _new_places: Dictionary = {} # place name -> true while its NEW badge lasts
var _disc_tween: Tween = null

# Expanded places list (opened from the counter)
var _places_bg: ColorRect
var _places_panel: PanelContainer
var _places_title: Label
var _places_list: VBoxContainer
var _places_scroll: ScrollContainer
var _places_open: bool = false

var _jp_font: Font = null

# Poster close-up overlay
var _poster_bg: ColorRect
var _poster_panel: PanelContainer
var _poster_vbox: VBoxContainer

# First-destination tutorial hint (bottom-centre, non-blocking)
var _tutorial_panel: PanelContainer
var _tutorial_line1: Label
var _tutorial_line2: Label
var _tutorial_tween: Tween = null

# Three-choice destination overlay
var _destination_bg: ColorRect
var _destination_prompt: Label
var _destination_buttons: VBoxContainer
var _destination_choice_open: bool = false

# Elapsed timer (top-centre while goal active)
var _elapsed_label: Label

# Typewriter state
var _tw_tween: Tween = null
var _is_typing: bool = false

var _tts_enabled: bool = false

const PANEL_H := -245.0

# Top-centre HUD stack: the destination card sits at the top edge, and the
# elapsed timer clears its height so the two never overlap while navigating.
const DEST_CARD_TOP := 12.0
const ELAPSED_TOP := 94.0
const DEST_FADE_SECONDS := 0.18
const TUTORIAL_WIDTH := 640.0

# Discovery counter + places list
const DISC_COUNT_COLOR := Color(1.0, 0.90, 0.45)
const PLACES_WIDTH := 330.0
const NEW_BADGE_SECONDS := 30.0

# --- Pre-recorded NPC voice clips -------------------------------------------
# Each fixed NPC line maps to an audio file slug in res://assets/voice/. When a
# clip is present it's played (with per-NPC pitch via pitch_scale); otherwise we
# fall back to the Web Speech API. Generate the files with tools/generate_voices.sh.
const VOICE_DIR := "res://assets/voice/"
const LINE_CLIPS := {
	"Yes?": "yes",
	"Hello!": "hello",
	"Hi there!": "hi_there",
	"Good morning!": "good_morning",
	"Hey!": "hey",
	"See you!": "see_you",
	"Take care!": "take_care",
	"Goodbye!": "goodbye",
	"Anytime, good luck!": "anytime_good_luck",
	"I'm fine!": "im_fine",
	"I'm good!": "im_good",
	"I'm great, thanks!": "im_great_thanks",
	"Sorry, I don't know that place.": "sorry_dont_know",
	"I don't know. Ask him.": "dont_know_ask_him",
	"I don't know. Ask her.": "dont_know_ask_her",
	"It's over there!": "its_over_there",
}
var _voice_player: AudioStreamPlayer
var _clip_cache: Dictionary = {}   # slug -> AudioStream (or null when missing)


func _ready() -> void:
	_build_ui()
	_voice_player = AudioStreamPlayer.new()
	add_child(_voice_player)
	if OS.has_feature("web"):
		_setup_tts()


func _build_ui() -> void:
	var _jp_base := load("res://assets/fonts/NotoSansJP.ttf") as FontFile
	var _jp_var := FontVariation.new()
	_jp_var.base_font = _jp_base
	_jp_var.variation_embolden = 0.5   # synthetic bold; works regardless of font axes
	_jp_font = _jp_var
	# --- Assigned destination card (top-centre) -------------------------------
	# Anchored to the centre of the top edge and sized by its own content, so it
	# stays centred and compact at any window size.
	_destination_card = PanelContainer.new()
	_destination_card.anchor_left = 0.5
	_destination_card.anchor_right = 0.5
	_destination_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_destination_card.offset_top = DEST_CARD_TOP
	_destination_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var destination_style := StyleBoxFlat.new()
	destination_style.bg_color = Color(0.04, 0.06, 0.11, 0.72)
	destination_style.border_color = Color(1.0, 0.82, 0.35, 0.55)
	destination_style.set_border_width_all(2)
	destination_style.set_corner_radius_all(14)
	destination_style.content_margin_left = 26.0
	destination_style.content_margin_right = 26.0
	destination_style.content_margin_top = 7.0
	destination_style.content_margin_bottom = 9.0
	_destination_card.add_theme_stylebox_override("panel", destination_style)
	add_child(_destination_card)

	var destination_box := VBoxContainer.new()
	destination_box.add_theme_constant_override("separation", 0)
	_destination_card.add_child(destination_box)
	var destination_caption := Label.new()
	destination_caption.text = "行き先"
	destination_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	destination_caption.add_theme_font_size_override("font_size", 16)
	destination_caption.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	if _jp_font:
		destination_caption.add_theme_font_override("font", _jp_font)
	destination_box.add_child(destination_caption)
	_destination_name = Label.new()
	_destination_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_destination_name.add_theme_font_size_override("font_size", 28)
	_destination_name.add_theme_color_override("font_color", Color.WHITE)
	if _jp_font:
		_destination_name.add_theme_font_override("font", _jp_font)
	destination_box.add_child(_destination_name)
	_destination_card.visible = false

	# --- Discovery counter (top-left, compact) --------------------------------
	# Only the count sits on the HUD; the full list is one tap away. It stays
	# visually quieter than the top-centre destination card, which is the thing
	# the player is meant to be acting on.
	_disc_panel = PanelContainer.new()
	_disc_panel.position = Vector2(14, 14)
	_disc_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_disc_style = StyleBoxFlat.new()
	_disc_style.bg_color = Color(0.04, 0.06, 0.11, 0.64)
	_disc_style.border_color = Color(1.0, 0.90, 0.45, 0.38)
	_disc_style.set_border_width_all(2)
	_disc_style.set_corner_radius_all(12)
	_disc_style.content_margin_left = 12.0
	_disc_style.content_margin_right = 15.0
	_disc_style.content_margin_top = 6.0
	_disc_style.content_margin_bottom = 6.0
	_disc_style_hover = _disc_style.duplicate() as StyleBoxFlat
	_disc_style_hover.bg_color = Color(0.10, 0.15, 0.24, 0.88)
	_disc_style_hover.border_color = Color(1.0, 0.90, 0.45, 0.80)
	_disc_panel.add_theme_stylebox_override("panel", _disc_style)
	_disc_panel.gui_input.connect(_on_disc_input)
	_disc_panel.mouse_entered.connect(
			func() -> void: _disc_panel.add_theme_stylebox_override("panel", _disc_style_hover))
	_disc_panel.mouse_exited.connect(
			func() -> void: _disc_panel.add_theme_stylebox_override("panel", _disc_style))
	add_child(_disc_panel)

	var disc_box := HBoxContainer.new()
	disc_box.add_theme_constant_override("separation", 8)
	disc_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disc_panel.add_child(disc_box)

	# Drawn rather than an emoji: the UI font is a subset of Noto Sans JP, which
	# has no pictographs at all, so a map glyph would render as blank space.
	var pin := MapPin.new()
	pin.custom_minimum_size = Vector2(15, 20)
	pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc_box.add_child(pin)

	_disc_count = Label.new()
	_disc_count.add_theme_font_size_override("font_size", 21)
	_disc_count.add_theme_color_override("font_color", DISC_COUNT_COLOR)
	_disc_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_disc_count.text = "0 / 0"
	_disc_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc_box.add_child(_disc_count)
	_disc_panel.visible = false

	_build_places_list_ui()

	# --- Elapsed timer (top-centre) ------------------------------------------
	_elapsed_label = Label.new()
	_elapsed_label.anchor_left = 0.5
	_elapsed_label.anchor_right = 0.5
	_elapsed_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_elapsed_label.offset_top = ELAPSED_TOP
	_elapsed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_elapsed_label.add_theme_font_size_override("font_size", 30)
	_elapsed_label.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	_elapsed_label.visible = false
	add_child(_elapsed_label)

	# --- Centered message (e.g. "You found the X!") --------------------------
	_center_label = Label.new()
	_center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center_label.add_theme_font_size_override("font_size", 72)
	_center_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	_center_label.visible = false
	add_child(_center_label)

	# --- Persistent directions (bottom-centre) --------------------------------
	_dir_panel = PanelContainer.new()
	_dir_panel.anchor_left = 0.5
	_dir_panel.anchor_top = 1.0
	_dir_panel.anchor_right = 0.5
	_dir_panel.anchor_bottom = 1.0
	_dir_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dir_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dir_panel.offset_bottom = -16
	_dir_panel.visible = false
	add_child(_dir_panel)

	var dmargin := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		dmargin.add_theme_constant_override(s, 12)
	_dir_panel.add_child(dmargin)
	var dvbox := VBoxContainer.new()
	dmargin.add_child(dvbox)
	_dir_title = Label.new()
	_dir_title.add_theme_font_size_override("font_size", 20)
	_dir_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_dir_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_dir_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dvbox.add_child(_dir_title)
	_dir_text = Label.new()
	_dir_text.add_theme_font_size_override("font_size", 24)
	_dir_text.custom_minimum_size = Vector2(360, 0)
	_dir_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_dir_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dvbox.add_child(_dir_text)

	# --- Dialogue panel (bottom) ---------------------------------------------
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 40
	_panel.offset_right = -40
	_panel.offset_top = PANEL_H
	_panel.offset_bottom = -40
	_panel.visible = false
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 22)
	_speaker_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	vbox.add_child(_speaker_label)

	_text_label = Label.new()
	_text_label.add_theme_font_size_override("font_size", 26)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _jp_font:
		_text_label.add_theme_font_override("font", _jp_font)
	vbox.add_child(_text_label)

	# Japanese gloss shown under the English line. It appears in full straight
	# away — the typewriter is the English line's effect, and a student reading
	# the translation should not have to wait for it.
	_text_jp = Label.new()
	_text_jp.add_theme_font_size_override("font_size", 20)
	_text_jp.add_theme_color_override("font_color", Color(0.72, 0.82, 0.95))
	_text_jp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _jp_font:
		_text_jp.add_theme_font_override("font", _jp_font)
	_text_jp.visible = false
	vbox.add_child(_text_jp)

	_options_scroll = ScrollContainer.new()
	_options_scroll.custom_minimum_size = Vector2(0, 65)
	_options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_options_scroll)

	_options_grid = GridContainer.new()
	_options_grid.columns = 3
	_options_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options_grid.add_theme_constant_override("h_separation", 6)
	_options_grid.add_theme_constant_override("v_separation", 6)
	_options_scroll.add_child(_options_grid)

	# --- Text input (keyboard pipeline, below the dialogue panel) -----------
	_text_input = LineEdit.new()
	_text_input.placeholder_text = "ここに入力してエンターを押してください..."
	_text_input.add_theme_font_size_override("font_size", 20)
	if _jp_font:
		_text_input.add_theme_font_override("font", _jp_font)
		_text_input.add_theme_font_override("font_placeholder", _jp_font)
	_text_input.anchor_left = 0.0
	_text_input.anchor_top = 1.0
	_text_input.anchor_right = 1.0
	_text_input.anchor_bottom = 1.0
	_text_input.offset_left = 40
	_text_input.offset_right = -40
	_text_input.offset_top = -38
	_text_input.offset_bottom = -2
	_text_input.visible = false
	add_child(_text_input)
	_text_input.text_submitted.connect(_on_text_input_submitted)

	_build_poster_ui()
	_build_destination_choice_ui()
	_build_tutorial_ui()


# --- First-destination tutorial hint -----------------------------------------
# A small notice, not a modal: it never takes focus and never blocks input, so
# the player can walk off looking for a townsperson while it is still up.
func _build_tutorial_ui() -> void:
	_tutorial_panel = PanelContainer.new()
	_tutorial_panel.anchor_left = 0.5
	_tutorial_panel.anchor_top = 1.0
	_tutorial_panel.anchor_right = 0.5
	_tutorial_panel.anchor_bottom = 1.0
	_tutorial_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tutorial_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tutorial_panel.offset_bottom = -22
	_tutorial_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.11, 0.78)
	style.border_color = Color(0.55, 0.85, 0.60, 0.65)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	_tutorial_panel.add_theme_stylebox_override("panel", style)
	add_child(_tutorial_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_tutorial_panel.add_child(box)

	_tutorial_line1 = Label.new()
	_tutorial_line1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Capped width + wrapping: with the English sentence inline, a long place
	# name ("Excuse me. Where is the Convenience Store?") would otherwise stretch
	# the notice past the edges of a smaller window.
	_tutorial_line1.custom_minimum_size = Vector2(TUTORIAL_WIDTH, 0)
	_tutorial_line1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tutorial_line1.add_theme_font_size_override("font_size", 22)
	_tutorial_line1.add_theme_color_override("font_color", Color(1, 1, 1))
	if _jp_font:
		_tutorial_line1.add_theme_font_override("font", _jp_font)
	box.add_child(_tutorial_line1)

	_tutorial_line2 = Label.new()
	_tutorial_line2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_line2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tutorial_line2.add_theme_font_size_override("font_size", 18)
	_tutorial_line2.add_theme_color_override("font_color", Color(0.72, 0.90, 0.76))
	if _jp_font:
		_tutorial_line2.add_theme_font_override("font", _jp_font)
	box.add_child(_tutorial_line2)

	_tutorial_panel.visible = false


func show_tutorial_hint(line1: String, line2: String) -> void:
	_tutorial_line1.text = line1
	_tutorial_line2.text = line2
	if _tutorial_tween != null:
		_tutorial_tween.kill()
	_tutorial_panel.modulate.a = 0.0
	_tutorial_panel.visible = true
	_tutorial_tween = create_tween()
	_tutorial_tween.tween_property(_tutorial_panel, "modulate:a", 1.0, 0.35)


func hide_tutorial_hint() -> void:
	if _tutorial_panel == null or not _tutorial_panel.visible:
		return
	if _tutorial_tween != null:
		_tutorial_tween.kill()
	_tutorial_tween = create_tween()
	_tutorial_tween.tween_property(_tutorial_panel, "modulate:a", 0.0, 0.4)
	_tutorial_tween.finished.connect(
			func() -> void: _tutorial_panel.visible = false)


# --- Poster close-up overlay -------------------------------------------------
func _build_poster_ui() -> void:
	# Dimmed full-screen backdrop.
	_poster_bg = ColorRect.new()
	_poster_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_poster_bg.color = Color(0, 0, 0, 0.6)
	_poster_bg.visible = false
	add_child(_poster_bg)

	# Centered poster panel.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_poster_bg.add_child(center)

	_poster_panel = PanelContainer.new()
	_poster_panel.custom_minimum_size = Vector2(460, 680)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.97, 0.95, 0.88)
	pstyle.border_color = Color(0.20, 0.18, 0.12)
	pstyle.set_border_width_all(10)
	pstyle.set_corner_radius_all(8)
	pstyle.set_content_margin_all(30)
	_poster_panel.add_theme_stylebox_override("panel", pstyle)
	center.add_child(_poster_panel)

	# Lines centered both vertically and horizontally.
	_poster_vbox = VBoxContainer.new()
	_poster_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_poster_vbox.add_theme_constant_override("separation", 26)
	_poster_panel.add_child(_poster_vbox)


func show_poster(lines: Array) -> void:
	for c in _poster_vbox.get_children():
		c.queue_free()
	var sizes := [46, 32]   # ad sentence, hours
	var colors := [
		Color(0.55, 0.20, 0.12),
		Color(0.30, 0.30, 0.32),
	]
	for i in lines.size():
		var lbl := Label.new()
		lbl.text = str(lines[i])
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Ad sentence (first line) may wrap to as many lines as needed; the hours
		# line (last) always stays on one line.
		var is_last: bool = (i == lines.size() - 1)
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF if is_last else TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = Vector2(400, 0)
		lbl.add_theme_font_size_override("font_size", sizes[mini(i, sizes.size() - 1)])
		lbl.add_theme_color_override("font_color", colors[mini(i, colors.size() - 1)])
		_poster_vbox.add_child(lbl)
	_poster_bg.visible = true


func hide_poster() -> void:
	_poster_bg.visible = false


func show_directory(title: String, entries: Array) -> void:
	for c in _poster_vbox.get_children():
		c.queue_free()
	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 36)
	title_lbl.add_theme_color_override("font_color", Color(0.45, 0.15, 0.10))
	_poster_vbox.add_child(title_lbl)
	var sep := HSeparator.new()
	_poster_vbox.add_child(sep)
	for entry: String in entries:
		var lbl := Label.new()
		lbl.text = "• " + entry
		lbl.add_theme_font_size_override("font_size", 26)
		lbl.add_theme_color_override("font_color", Color(0.18, 0.18, 0.22))
		_poster_vbox.add_child(lbl)
	_poster_bg.visible = true


func is_poster_open() -> bool:
	return _poster_bg != null and _poster_bg.visible


# --- Assigned destination + three-choice overlay ----------------------------
func _build_destination_choice_ui() -> void:
	_destination_bg = ColorRect.new()
	_destination_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_destination_bg.color = Color(0.01, 0.03, 0.08, 0.76)
	_destination_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_destination_bg.visible = false
	add_child(_destination_bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_destination_bg.add_child(center)
	var choice_panel := PanelContainer.new()
	choice_panel.custom_minimum_size = Vector2(620, 430)
	var choice_style := StyleBoxFlat.new()
	choice_style.bg_color = Color(0.96, 0.94, 0.86)
	choice_style.border_color = Color(0.12, 0.24, 0.42)
	choice_style.set_border_width_all(6)
	choice_style.set_corner_radius_all(18)
	choice_style.set_content_margin_all(34)
	choice_panel.add_theme_stylebox_override("panel", choice_style)
	center.add_child(choice_panel)

	var choice_box := VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 20)
	choice_panel.add_child(choice_box)
	_destination_prompt = Label.new()
	_destination_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_destination_prompt.add_theme_font_size_override("font_size", 34)
	_destination_prompt.add_theme_color_override("font_color", Color(0.08, 0.16, 0.30))
	if _jp_font:
		_destination_prompt.add_theme_font_override("font", _jp_font)
	choice_box.add_child(_destination_prompt)
	var separator := HSeparator.new()
	choice_box.add_child(separator)
	_destination_buttons = VBoxContainer.new()
	_destination_buttons.add_theme_constant_override("separation", 14)
	choice_box.add_child(_destination_buttons)


func show_destination_choice(prompt: String, places: Array[String]) -> int:
	assert(places.size() == 3, "Destination choice overlay requires exactly three places.")
	_clear_destination_buttons()
	_destination_prompt.text = prompt
	_destination_choice_open = true

	var buttons: Array[Button] = []
	for i in places.size():
		var button := Button.new()
		button.name = "DestinationChoice%d" % i
		button.text = places[i]
		button.custom_minimum_size = Vector2(520, 76)
		button.add_theme_font_size_override("font_size", 28)
		button.focus_mode = Control.FOCUS_ALL
		if _jp_font:
			button.add_theme_font_override("font", _jp_font)
		button.pressed.connect(_on_destination_pressed.bind(i))
		_destination_buttons.add_child(button)
		buttons.append(button)

	for i in buttons.size():
		var previous := buttons[(i - 1 + buttons.size()) % buttons.size()]
		var next := buttons[(i + 1) % buttons.size()]
		buttons[i].focus_neighbor_top = buttons[i].get_path_to(previous)
		buttons[i].focus_neighbor_left = buttons[i].get_path_to(previous)
		buttons[i].focus_neighbor_bottom = buttons[i].get_path_to(next)
		buttons[i].focus_neighbor_right = buttons[i].get_path_to(next)

	_destination_bg.visible = true
	buttons[0].grab_focus()
	var index: int = await destination_selected
	return index


func hide_destination_choice() -> void:
	_destination_choice_open = false
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and _destination_bg.is_ancestor_of(focused):
		focused.release_focus()
	_destination_bg.visible = false
	_clear_destination_buttons()


func set_destination_card(place: String) -> void:
	_destination_name.text = place
	_destination_card.visible = true
	# Quick fade so the new objective registers without holding up play.
	if _dest_tween != null:
		_dest_tween.kill()
	_destination_card.modulate.a = 0.0
	_dest_tween = create_tween()
	_dest_tween.tween_property(_destination_card, "modulate:a", 1.0, DEST_FADE_SECONDS)


func clear_destination_card() -> void:
	if _dest_tween != null:
		_dest_tween.kill()
		_dest_tween = null
	_destination_name.text = ""
	_destination_card.visible = false
	_destination_card.modulate.a = 1.0


func _on_destination_pressed(index: int) -> void:
	if not _destination_choice_open:
		return
	_destination_choice_open = false
	for child in _destination_buttons.get_children():
		if child is Button:
			(child as Button).disabled = true
	destination_selected.emit(index)


func _clear_destination_buttons() -> void:
	for child in _destination_buttons.get_children():
		_destination_buttons.remove_child(child)
		child.queue_free()


func _on_text_input_submitted(txt: String) -> void:
	var trimmed := txt.strip_edges()
	if trimmed == "":
		return
	_text_input.text = ""
	text_submitted.emit(trimmed)


# -----------------------------------------------------------------------------
# Discovery panel
# -----------------------------------------------------------------------------
func init_discovery(total: int) -> void:
	_disc_total = total
	_disc_count.text = "0 / %d" % total
	_disc_panel.visible = false


func show_discovery_panel() -> void:
	_disc_panel.visible = true


func mark_discovered(place: String, _time_str: String) -> void:
	if not _known.has(place):
		_known.append(place)
	if _found.has(place):
		return
	_found[place] = true
	_found_count += 1
	_disc_count.text = "%d / %d" % [_found_count, _disc_total]
	_disc_panel.visible = true
	_flag_new(place)
	_pulse_counter()
	if _places_open:
		_rebuild_places_rows()


# A place stays flagged NEW until the player opens the list or the timer expires.
func _flag_new(place: String) -> void:
	_new_places[place] = true
	var timer := get_tree().create_timer(NEW_BADGE_SECONDS)
	timer.timeout.connect(func() -> void: _new_places.erase(place))


# Brief pop + colour flash, so a new discovery registers without pulling the eye
# away from play.
func _pulse_counter() -> void:
	if _disc_tween != null:
		_disc_tween.kill()
	_disc_panel.pivot_offset = _disc_panel.size * 0.5
	_disc_panel.scale = Vector2.ONE
	_disc_count.add_theme_color_override("font_color", Color(0.55, 1.0, 0.62))
	_disc_tween = create_tween()
	_disc_tween.set_trans(Tween.TRANS_SINE)
	_disc_tween.tween_property(_disc_panel, "scale", Vector2(1.16, 1.16), 0.13)
	_disc_tween.tween_property(_disc_panel, "scale", Vector2.ONE, 0.20)
	_disc_tween.tween_callback(func() -> void:
			_disc_count.add_theme_color_override("font_color", DISC_COUNT_COLOR))


func add_hint(place: String, already_found: bool = false) -> void:
	if not _known.has(place):
		_known.append(place)
	if already_found and not _found.has(place):
		_found[place] = true
	_disc_panel.visible = true
	if _places_open:
		_rebuild_places_rows()


# -----------------------------------------------------------------------------
# Expanded places list
# -----------------------------------------------------------------------------
func _build_places_list_ui() -> void:
	# Faint scrim: it catches clicks outside the panel so they close it, but stays
	# light enough that this reads as a HUD expansion rather than a menu screen.
	_places_bg = ColorRect.new()
	_places_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_places_bg.color = Color(0, 0, 0, 0.28)
	_places_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_places_bg.visible = false
	_places_bg.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
				hide_places_list())
	add_child(_places_bg)

	_places_panel = PanelContainer.new()
	_places_panel.position = Vector2(14, 62)
	_places_panel.custom_minimum_size = Vector2(PLACES_WIDTH, 0)
	_places_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.12, 0.95)
	style.border_color = Color(1.0, 0.90, 0.45, 0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(14)
	_places_panel.add_theme_stylebox_override("panel", style)
	_places_bg.add_child(_places_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_places_panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	box.add_child(header)
	_places_title = Label.new()
	_places_title.add_theme_font_size_override("font_size", 19)
	_places_title.add_theme_color_override("font_color", DISC_COUNT_COLOR)
	_places_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _jp_font:
		_places_title.add_theme_font_override("font", _jp_font)
	header.add_child(_places_title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(hide_places_list)
	header.add_child(close_btn)

	box.add_child(HSeparator.new())

	_places_scroll = ScrollContainer.new()
	_places_scroll.custom_minimum_size = Vector2(PLACES_WIDTH - 10, 0)
	_places_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_places_scroll)
	var scroll := _places_scroll

	_places_list = VBoxContainer.new()
	_places_list.add_theme_constant_override("separation", 3)
	_places_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_places_list)


func _on_disc_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		toggle_places_list()


func toggle_places_list() -> void:
	if _places_open:
		hide_places_list()
	else:
		show_places_list()


func show_places_list() -> void:
	# Never stack on top of a choice the player has to make first.
	if _destination_choice_open or is_poster_open():
		return
	_rebuild_places_rows()
	_places_bg.visible = true
	_places_open = true
	# Seeing the list is what retires the NEW badges: this viewing still shows
	# them, the next one will not.
	_new_places.clear()


func hide_places_list() -> void:
	_places_open = false
	_places_bg.visible = false


func is_places_list_open() -> bool:
	return _places_open


func _rebuild_places_rows() -> void:
	for child in _places_list.get_children():
		_places_list.remove_child(child)
		child.queue_free()
	_places_title.text = "発見した場所  %d / %d" % [_found_count, _disc_total]

	# Found first, then places the player knows of but has not reached.
	var ordered: Array[String] = []
	for place: String in _known:
		if _found.has(place):
			ordered.append(place)
	for place: String in _known:
		if not _found.has(place):
			ordered.append(place)

	for place: String in ordered:
		_places_list.add_child(_make_place_row(place))

	# Height follows the list so the panel is not mostly empty early on, capped
	# so a full town still fits on screen and scrolls instead.
	_places_scroll.custom_minimum_size.y = clampf(float(ordered.size()) * 29.0, 60.0, 340.0)


func _make_place_row(place: String) -> HBoxContainer:
	var found: bool = _found.has(place)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)

	# A tick marks the found ones. Deliberately not strikethrough, which reads as
	# "removed" or "unavailable" rather than "done".
	var mark := Label.new()
	mark.text = "✓" if found else ""
	mark.custom_minimum_size = Vector2(18, 0)
	mark.add_theme_font_size_override("font_size", 18)
	mark.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55))
	row.add_child(mark)

	var label := Label.new()
	label.text = place
	label.add_theme_font_size_override("font_size", 18)
	# Found places dim slightly; unfound stay bright and fully readable, since
	# those are the ones still worth going after.
	label.add_theme_color_override("font_color",
			Color(0.62, 0.66, 0.62) if found else Color(0.95, 0.97, 0.95))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	if _new_places.has(place):
		var badge := Label.new()
		badge.text = "NEW"
		badge.add_theme_font_size_override("font_size", 13)
		badge.add_theme_color_override("font_color", Color(0.15, 0.10, 0.02))
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color(1.0, 0.84, 0.30)
		bs.set_corner_radius_all(6)
		bs.content_margin_left = 7.0
		bs.content_margin_right = 7.0
		bs.content_margin_top = 1.0
		bs.content_margin_bottom = 2.0
		var wrap := PanelContainer.new()
		wrap.add_theme_stylebox_override("panel", bs)
		wrap.add_child(badge)
		row.add_child(wrap)

	return row


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

func show_text(speaker: String, text: String, translation: String = "") -> void:
	_speaker_label.text = speaker
	_text_label.text = text
	_text_label.visible_characters = 0
	_text_jp.text = translation
	_text_jp.visible = translation != ""
	_clear_options()
	_options_scroll.visible = false
	_panel.visible = true
	_start_typewriter(text.length())


func _start_typewriter(length: int) -> void:
	if _tw_tween != null:
		_tw_tween.kill()
	_is_typing = true
	_tw_tween = create_tween()
	_tw_tween.tween_method(
		func(v: int) -> void: _text_label.visible_characters = v,
		0, length, maxf(0.3, length / 28.0)
	)
	_tw_tween.finished.connect(func() -> void: _is_typing = false)


func is_typing() -> bool:
	return _is_typing


func skip_typewriter() -> void:
	if _tw_tween != null:
		_tw_tween.kill()
		_tw_tween = null
	_text_label.visible_characters = -1
	_is_typing = false


func show_options(speaker: String, prompt: String, options: Array) -> int:
	_speaker_label.text = speaker
	_text_label.text = prompt
	_text_label.visible_characters = -1
	_is_typing = false
	_text_jp.visible = false   # the gloss belongs to the line it was shown with
	_clear_options()

	var first: Button = null
	for i in options.size():
		var button := Button.new()
		button.text = str(options[i])
		button.add_theme_font_size_override("font_size", 20)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _jp_font:
			button.add_theme_font_override("font", _jp_font)
		button.pressed.connect(_on_option_pressed.bind(i))
		_options_grid.add_child(button)
		if first == null:
			first = button

	_options_scroll.visible = true
	_panel.visible = true
	if first != null:
		first.grab_focus()
	var index: int = await option_selected
	_clear_options()
	return index


func _on_option_pressed(index: int) -> void:
	option_selected.emit(index)


func show_text_input() -> void:
	_text_input.text = ""
	_text_input.visible = true
	_text_input.grab_focus()


func hide_text_input() -> void:
	_text_input.visible = false
	_text_input.text = ""


func set_directions(dest_name: String, instruction: String) -> void:
	_dir_title.text = dest_name
	_dir_text.text = instruction
	_dir_panel.visible = true


func clear_directions() -> void:
	_dir_panel.visible = false
	_elapsed_label.visible = false


func update_elapsed(seconds: float) -> void:
	var s := int(seconds)
	_elapsed_label.text = "%d:%02d" % [s / 60, s % 60]
	_elapsed_label.visible = true


func hide_dialogue() -> void:
	_panel.visible = false
	_clear_options()
	skip_typewriter()


func show_center_message(text: String) -> void:
	_center_label.text = text
	_center_label.modulate.a = 1.0
	_center_label.visible = true
	await get_tree().create_timer(2.0).timeout
	var tween := create_tween()
	tween.tween_property(_center_label, "modulate:a", 0.0, 0.6)
	await tween.finished
	_center_label.visible = false


func _clear_options() -> void:
	for child in _options_grid.get_children():
		child.queue_free()


# -----------------------------------------------------------------------------
# TTS (Web Speech API, local voices only)
# -----------------------------------------------------------------------------
func _setup_tts() -> void:
	JavaScriptBridge.eval("""
		(function () {
			if (!window.speechSynthesis) return;
			window._gd_tts_voices = [];
			function pickVoices() {
				var all = window.speechSynthesis.getVoices();
				var local = all.filter(function (v) {
					return v.localService && v.lang.indexOf('en') === 0;
				});
				window._gd_tts_voices = local.length > 0 ? local
					: (all.length > 0 ? all : []);
			}
			pickVoices();
			window.speechSynthesis.addEventListener('voiceschanged', pickVoices);
		})();
	""", true)
	_tts_enabled = true


func _play_clip(text: String, pitch: float, family: String = "female") -> bool:
	if not LINE_CLIPS.has(text):
		return false
	var stream := _get_clip(LINE_CLIPS[text], family)
	if stream == null:
		return false
	_voice_player.stream = stream
	_voice_player.pitch_scale = clampf(pitch, 0.7, 1.5)
	_voice_player.play()
	return true


func _get_clip(slug: String, family: String) -> AudioStream:
	var cache_key: String = family + "/" + slug
	if _clip_cache.has(cache_key):
		return _clip_cache[cache_key]
	var stream: AudioStream = null
	for ext in [".ogg", ".wav", ".mp3"]:
		var path: String = VOICE_DIR + family + "/" + slug + ext
		if ResourceLoader.exists(path):
			stream = ResourceLoader.load(path)
			break
	# Fallback: root voice dir (backward-compat with pre-family files)
	if stream == null:
		for ext in [".ogg", ".wav", ".mp3"]:
			var path: String = VOICE_DIR + slug + ext
			if ResourceLoader.exists(path):
				stream = ResourceLoader.load(path)
				break
	_clip_cache[cache_key] = stream
	return stream


func speak(text: String, pitch: float = 1.0, rate: float = 0.88, voice_index: int = 0, voice_family: String = "female") -> void:
	# Prefer a pre-recorded clip; pitch_scale keeps the per-NPC voice variety.
	if _play_clip(text, pitch, voice_family):
		return
	if not _tts_enabled:
		return
	JavaScriptBridge.eval(
		"window._gd_tts_text = %s; window._gd_tts_pitch = %f; window._gd_tts_rate = %f; window._gd_tts_vi = %d;" \
		% [JSON.stringify(text), pitch, rate, voice_index], true)
	JavaScriptBridge.eval("""
		(function () {
			if (!window.speechSynthesis) return;
			window.speechSynthesis.cancel();
			var u = new SpeechSynthesisUtterance(window._gd_tts_text || '');
			var voices = window._gd_tts_voices || [];
			if (voices.length > 0) {
				u.voice = voices[(window._gd_tts_vi || 0) % voices.length];
			}
			u.pitch = (window._gd_tts_pitch !== undefined) ? window._gd_tts_pitch : 1.0;
			u.rate  = (window._gd_tts_rate  !== undefined) ? window._gd_tts_rate  : 0.88;
			u.volume = 1.0;
			window.speechSynthesis.speak(u);
		})();
	""", true)


# -----------------------------------------------------------------------------
# Small drawn map-pin for the discovery counter. Vector art rather than an emoji
# because the subset UI font carries no pictographs at all.
# -----------------------------------------------------------------------------
class MapPin:
	extends Control

	const PIN_COLOR := Color(1.0, 0.88, 0.45)
	const HOLE_COLOR := Color(0.06, 0.08, 0.13)

	func _draw() -> void:
		var head := Vector2(size.x * 0.5, size.y * 0.36)
		var radius: float = size.x * 0.42
		draw_circle(head, radius, PIN_COLOR)
		draw_colored_polygon(PackedVector2Array([
			Vector2(size.x * 0.5 - radius * 0.62, size.y * 0.62),
			Vector2(size.x * 0.5 + radius * 0.62, size.y * 0.62),
			Vector2(size.x * 0.5, size.y * 0.99),
		]), PIN_COLOR)
		draw_circle(head, radius * 0.40, HOLE_COLOR)
