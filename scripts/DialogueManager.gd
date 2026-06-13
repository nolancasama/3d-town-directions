class_name DialogueManager
extends CanvasLayer
# =============================================================================
# DialogueManager.gd
# =============================================================================

signal option_selected(index: int)
signal text_submitted(text: String)   # fired when player submits text input

var _center_label: Label
var _panel: PanelContainer
var _speaker_label: Label
var _text_label: Label
var _options_scroll: ScrollContainer
var _options_grid: GridContainer
var _dir_panel: PanelContainer
var _dir_title: Label
var _dir_text: Label
var _text_input: LineEdit

# Discovery panel (top-left)
var _disc_panel: PanelContainer
var _disc_count: Label
var _disc_list: VBoxContainer
var _disc_total: int = 0

var _jp_font: Font = null

# Elapsed timer (top-centre while goal active)
var _elapsed_label: Label

# Typewriter state
var _tw_tween: Tween = null
var _is_typing: bool = false

var _tts_enabled: bool = false

const PANEL_H := -245.0


func _ready() -> void:
	_build_ui()
	if OS.has_feature("web"):
		_setup_tts()


func _build_ui() -> void:
	var _jp_base := load("res://assets/fonts/NotoSansJP.ttf") as FontFile
	var _jp_var := FontVariation.new()
	_jp_var.base_font = _jp_base
	_jp_var.variation_embolden = 0.8   # synthetic bold; works regardless of font axes
	_jp_font = _jp_var
	# --- Discovery panel (top-left) ------------------------------------------
	_disc_panel = PanelContainer.new()
	_disc_panel.position = Vector2(14, 14)
	_disc_panel.custom_minimum_size = Vector2(220, 0)
	add_child(_disc_panel)

	var dm := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		dm.add_theme_constant_override(s, 10)
	_disc_panel.add_child(dm)

	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 4)
	dm.add_child(dv)

	_disc_count = Label.new()
	_disc_count.add_theme_font_size_override("font_size", 22)
	_disc_count.add_theme_color_override("font_color", Color(1.0, 0.90, 0.4))
	_disc_count.text = "0 / 0 か所発見"
	if _jp_font:
		_disc_count.add_theme_font_override("font", _jp_font)
	dv.add_child(_disc_count)

	# Scroll container caps the list at ~7 visible rows; extra entries scroll.
	var disc_scroll := ScrollContainer.new()
	disc_scroll.custom_minimum_size = Vector2(200, 154)
	disc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dv.add_child(disc_scroll)

	_disc_list = VBoxContainer.new()
	_disc_list.add_theme_constant_override("separation", 2)
	_disc_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disc_scroll.add_child(_disc_list)

	# --- Elapsed timer (top-centre) ------------------------------------------
	_elapsed_label = Label.new()
	_elapsed_label.anchor_left = 0.5
	_elapsed_label.anchor_right = 0.5
	_elapsed_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_elapsed_label.offset_top = 16
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
	_text_input.placeholder_text = "Type your question here, then press Enter..."
	_text_input.add_theme_font_size_override("font_size", 20)
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
	_disc_count.text = "0 / %d か所発見" % total
	_disc_panel.visible = false


func show_discovery_panel() -> void:
	_disc_panel.visible = true


func mark_discovered(name: String, time_str: String) -> void:
	var found := _disc_list.get_child_count() + 1
	_disc_count.text = "%d / %d か所発見" % [found, _disc_total]
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	lbl.text = "* %s  %s" % [name, time_str]
	_disc_list.add_child(lbl)


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

func show_text(speaker: String, text: String) -> void:
	_speaker_label.text = speaker
	_text_label.text = text
	_text_label.visible_characters = 0
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
			window._gd_tts_voice = null;
			function pickVoice() {
				var voices = window.speechSynthesis.getVoices();
				var local = voices.filter(function (v) {
					return v.localService && v.lang.indexOf('en') === 0;
				});
				window._gd_tts_voice = local.length > 0 ? local[0]
					: (voices.length > 0 ? voices[0] : null);
			}
			pickVoice();
			window.speechSynthesis.addEventListener('voiceschanged', pickVoice);
		})();
	""", true)
	_tts_enabled = true


func speak(text: String) -> void:
	if not _tts_enabled:
		return
	JavaScriptBridge.eval("window._gd_tts_text = %s;" % JSON.stringify(text), true)
	JavaScriptBridge.eval("""
		(function () {
			if (!window.speechSynthesis) return;
			window.speechSynthesis.cancel();
			var u = new SpeechSynthesisUtterance(window._gd_tts_text || '');
			if (window._gd_tts_voice) u.voice = window._gd_tts_voice;
			u.rate = 0.88;
			u.volume = 1.0;
			window.speechSynthesis.speak(u);
		})();
	""", true)
