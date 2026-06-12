class_name SpeechInput
extends Node
# =============================================================================
# SpeechInput.gd
# -----------------------------------------------------------------------------
# Speech-to-text via the browser's Web Speech API (Chrome / Chromebooks), driven
# through JavaScriptBridge. Only works in a WEB export served over HTTPS or
# localhost, and the first listen() triggers the browser's microphone-permission
# prompt.
#
# On any non-web build (e.g. the desktop editor) `available` stays false and the
# caller should fall back to keyboard input — speech recognition simply isn't
# reachable outside the browser.
#
# Usage:
#   speech.heard.connect(_on_heard)   # _on_heard(text: String)
#   speech.listen()                   # start one phrase capture
#   speech.stop()
# =============================================================================

signal heard(text: String)

var available: bool = false


func _ready() -> void:
	if OS.has_feature("web"):
		_setup_web()


func _setup_web() -> void:
	# Create a single recognition object on the JS side and stash the latest
	# transcript on window._gd_speech_result for us to poll each frame.
	var ok = JavaScriptBridge.eval("""
		(function () {
			var SR = window.SpeechRecognition || window.webkitSpeechRecognition;
			if (!SR) { return 0; }
			if (!window._gd_recog) {
				var r = new SR();
				r.lang = 'en-US';
				r.continuous = false;
				r.interimResults = false;
				r.maxAlternatives = 1;
				window._gd_speech_result = '';
				window._gd_recog_active = false;
				window._gd_should_listen = false;
				r.onresult = function (e) {
					window._gd_speech_result = e.results[e.results.length - 1][0].transcript;
				};
				r.onerror = function (e) {
					window._gd_recog_active = false;
					if (e.error === 'not-allowed' || e.error === 'service-not-allowed') {
						window._gd_should_listen = false;
					}
				};
				r.onend = function () {
					window._gd_recog_active = false;
					if (window._gd_should_listen) {
						setTimeout(function () {
							if (window._gd_should_listen && !window._gd_recog_active) {
								try { window._gd_recog_active = true; window._gd_recog.start(); } catch (e) {}
							}
						}, 150);
					}
				};
				window._gd_recog = r;
			}
			return 1;
		})();
	""", true)
	available = (int(ok) == 1)
	if available:
		_request_permission()


# Ask for microphone permission right away (at game start) so the browser's
# prompt appears immediately rather than mid-conversation. We grab a stream just
# to trigger the prompt, then stop it — the Web Speech API manages its own.
func _request_permission() -> void:
	JavaScriptBridge.eval("""
		try {
			if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
				navigator.mediaDevices.getUserMedia({ audio: true }).then(function (s) {
					s.getTracks().forEach(function (t) { t.stop(); });
					window._gd_mic_ok = true;
				}).catch(function (e) { window._gd_mic_ok = false; });
			}
		} catch (e) {}
	""", true)


# Begin capturing one spoken phrase (no-op if unavailable or already listening).
func listen() -> void:
	if not available:
		return
	JavaScriptBridge.eval("""
		try {
			window._gd_should_listen = true;
			if (window._gd_recog && !window._gd_recog_active) {
				window._gd_recog_active = true;
				window._gd_recog.start();
			}
		} catch (e) {}
	""", true)


func stop() -> void:
	if not available:
		return
	JavaScriptBridge.eval("try { window._gd_should_listen = false; if (window._gd_recog) { window._gd_recog.abort(); } } catch (e) {}", true)


func _process(_delta: float) -> void:
	if not available:
		return
	# Poll + clear the latest transcript the JS side captured.
	var res = JavaScriptBridge.eval(
			"(function(){var t=window._gd_speech_result||'';window._gd_speech_result='';return t;})();", true)
	if typeof(res) == TYPE_STRING and res != "":
		heard.emit(String(res))
