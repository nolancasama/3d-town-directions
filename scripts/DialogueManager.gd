class_name DialogueManager
extends CanvasLayer
# =============================================================================
# DialogueManager.gd
# -----------------------------------------------------------------------------
# Owns the entire 2D UI:
#   * A score label (top-left).
#   * A big centered message label (used for "Correct!").
#   * A dialogue panel (bottom) that can show either a line of NPC text or a
#     list of selectable option buttons.
#
# show_options() is a coroutine: callers `await` it and receive the index of
# the option the player clicked.
# =============================================================================

signal option_selected(index: int)

var _score_label: Label
var _timer_label: Label
var _center_label: Label
var _panel: PanelContainer
var _speaker_label: Label
var _text_label: Label
var _options_scroll: ScrollContainer
var _options_grid: GridContainer
var _dir_panel: PanelContainer
var _dir_title: Label
var _dir_text: Label

const PANEL_TOP_TEXT := -180.0
const PANEL_TOP_OPTIONS := -360.0


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# --- Score (top-left) ----------------------------------------------------
	_score_label = Label.new()
	_score_label.position = Vector2(24, 18)
	_score_label.add_theme_font_size_override("font_size", 30)
	add_child(_score_label)

	# --- Time bonus countdown (top-centre, only while a goal is active) -------
	_timer_label = Label.new()
	_timer_label.anchor_left = 0.5
	_timer_label.anchor_right = 0.5
	_timer_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_timer_label.offset_top = 16
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 30)
	_timer_label.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	_timer_label.visible = false
	add_child(_timer_label)

	# --- Centered message (e.g. "Correct!") ----------------------------------
	_center_label = Label.new()
	_center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center_label.add_theme_font_size_override("font_size", 72)
	_center_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	_center_label.visible = false
	add_child(_center_label)

	# --- Persistent turn-by-turn directions (bottom-center) ------------------
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
	_dir_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dvbox.add_child(_dir_title)
	_dir_text = Label.new()
	_dir_text.add_theme_font_size_override("font_size", 24)
	_dir_text.custom_minimum_size = Vector2(360, 0)
	_dir_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dir_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dvbox.add_child(_dir_text)

	# --- Dialogue panel (bottom) ---------------------------------------------
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 40
	_panel.offset_right = -40
	_panel.offset_top = PANEL_TOP_TEXT
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
	vbox.add_child(_text_label)

	# Options live in a scrollable multi-column grid so a long destination list
	# (the player can ask about ~20 places) fits and scrolls with the wheel.
	_options_scroll = ScrollContainer.new()
	_options_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_options_scroll)

	_options_grid = GridContainer.new()
	_options_grid.columns = 3
	_options_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options_grid.add_theme_constant_override("h_separation", 6)
	_options_grid.add_theme_constant_override("v_separation", 6)
	_options_scroll.add_child(_options_grid)


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

# Show a question with clickable options. Awaitable: returns the chosen index.
func show_options(speaker: String, prompt: String, options: Array) -> int:
	_speaker_label.text = speaker
	_text_label.text = prompt
	_clear_options()

	var first: Button = null
	for i in options.size():
		var button := Button.new()
		button.text = str(options[i])
		button.add_theme_font_size_override("font_size", 20)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_option_pressed.bind(i))
		_options_grid.add_child(button)
		if first == null:
			first = button

	_panel.offset_top = PANEL_TOP_OPTIONS
	_options_scroll.visible = true
	_panel.visible = true
	# Keyboard-only navigation: focus the first option so the arrow keys move
	# between buttons and Enter/Space (ui_accept) selects. No mouse needed.
	if first != null:
		first.grab_focus()
	var index: int = await option_selected
	_clear_options()
	return index


func _on_option_pressed(index: int) -> void:
	option_selected.emit(index)


# Persistent bottom-right directions panel (updated every frame by GoalManager).
func set_directions(dest_name: String, instruction: String) -> void:
	_dir_title.text = "→ " + dest_name
	_dir_text.text = instruction
	_dir_panel.visible = true


func clear_directions() -> void:
	_dir_panel.visible = false


# Time-bonus countdown shown while a goal is active. Turns red when it runs out.
func set_timer(seconds: float) -> void:
	_timer_label.text = "Time bonus: %.1f" % seconds
	_timer_label.add_theme_color_override("font_color",
			Color(1, 0.9, 0.3) if seconds > 0.0 else Color(0.95, 0.4, 0.35))
	_timer_label.visible = true


func clear_timer() -> void:
	_timer_label.visible = false


# Show a plain line of dialogue (no buttons).
func show_text(speaker: String, text: String) -> void:
	_speaker_label.text = speaker
	_text_label.text = text
	_clear_options()
	_options_scroll.visible = false
	_panel.offset_top = PANEL_TOP_TEXT
	_panel.visible = true


func hide_dialogue() -> void:
	_panel.visible = false
	_clear_options()


# Briefly flash a big centered message, then fade it out.
func show_center_message(text: String) -> void:
	_center_label.text = text
	_center_label.modulate.a = 1.0
	_center_label.visible = true
	await get_tree().create_timer(2.0).timeout
	var tween := create_tween()
	tween.tween_property(_center_label, "modulate:a", 0.0, 0.6)
	await tween.finished
	_center_label.visible = false


func set_score(value: int) -> void:
	_score_label.text = "Score: %d" % value


func _clear_options() -> void:
	for child in _options_grid.get_children():
		child.queue_free()
