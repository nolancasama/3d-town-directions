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
var _found_count: int = 0        # all discovered buildings (hinted or not)
var _hints: Dictionary = {}      # place name -> RichTextLabel
var _found_hint_count: int = 0   # how many struck-through hints sit at the bottom

var _jp_font: Font = null

# Poster close-up overlay
var _poster_bg: ColorRect
var _poster_panel: PanelContainer
var _poster_vbox: VBoxContainer

# Elapsed timer (top-centre while goal active)
var _elapsed_label: Label

# Typewriter state
var _tw_tween: Tween = null
var _is_typing: bool = false

var _tts_enabled: bool = false

const PANEL_H := -245.0

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


func mark_discovered(name: String, _time_str: String) -> void:
	_found_count += 1
	_disc_count.text = "%d / %d か所発見" % [_found_count, _disc_total]
	if _hints.has(name):
		_apply_hint_found(name)


func add_hint(name: String, already_found: bool = false) -> void:
	if _hints.has(name):
		return
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.scroll_active = false
	lbl.custom_minimum_size = Vector2(200, 22)
	lbl.add_theme_font_size_override("normal_font_size", 17)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hints[name] = lbl
	if already_found:
		lbl.text = "[color=#6a9a6a][s]" + name + "[/s][/color]"
		_disc_list.add_child(lbl)
		_found_hint_count += 1
	else:
		lbl.text = "[color=#d9ffd9]" + name + "[/color]"
		var insert_at := _disc_list.get_child_count() - _found_hint_count
		_disc_list.add_child(lbl)
		_disc_list.move_child(lbl, insert_at)
	_disc_panel.visible = true


func _apply_hint_found(name: String) -> void:
	if not _hints.has(name):
		return
	var lbl: RichTextLabel = _hints[name]
	if lbl.text.contains("[s]"):
		return
	lbl.text = "[color=#6a9a6a][s]" + name + "[/s][/color]"
	_disc_list.move_child(lbl, _disc_list.get_child_count() - 1)
	_found_hint_count += 1


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
