#!/usr/bin/env bash
# =============================================================================
# generate_voices.sh — pre-record the NPC lines with Piper TTS.
# -----------------------------------------------------------------------------
# Produces one audio file per fixed NPC line into assets/voice/. The game loads
# these automatically (DialogueManager.LINE_CLIPS) and falls back to browser TTS
# for any line whose file is missing.
#
# SETUP (one time):
#   1. Install Piper:           pip install piper-tts
#   2. Download a voice model (an .onnx + .onnx.json pair). Good English voices:
#        en_US-lessac-medium      (clear, neutral US)
#        en_US-amy-medium         (warmer US)
#        en_GB-alba-medium        (UK)
#      From: https://huggingface.co/rhasspy/piper-voices  (US/en/<voice>/...)
#      Put the .onnx (and its .onnx.json) somewhere and pass the .onnx path below.
#   3. (Optional) Install ffmpeg to convert WAV -> OGG (smaller, web-friendly).
#
# USAGE:
#   # Female voice (en_US-amy-medium recommended):
#   bash tools/generate_voices.sh /path/to/en_US-amy-medium.onnx female
#
#   # Male voice (en_US-ryan-high recommended):
#   bash tools/generate_voices.sh /path/to/en_US-ryan-high.onnx male
#
# Then re-deploy:  bash deploy.sh "add NPC voice clips"
# =============================================================================
set -euo pipefail

MODEL="${1:-en_US-lessac-medium.onnx}"
GENDER="${2:-female}"
OUT="assets/voice/${GENDER}"
mkdir -p "$OUT"

if ! command -v piper >/dev/null 2>&1; then
	echo "ERROR: 'piper' not found. Install with: pip install piper-tts" >&2
	exit 1
fi
if [ ! -f "$MODEL" ]; then
	echo "ERROR: voice model not found: $MODEL" >&2
	echo "Download one from https://huggingface.co/rhasspy/piper-voices" >&2
	exit 1
fi

HAVE_FFMPEG=0
if command -v ffmpeg >/dev/null 2>&1; then HAVE_FFMPEG=1; fi

gen() {
	local slug="$1"; local line="$2"
	echo "  $slug  <-  \"$line\""
	echo "$line" | piper -m "$MODEL" -f "$OUT/$slug.wav" >/dev/null 2>&1
	if [ "$HAVE_FFMPEG" = "1" ]; then
		ffmpeg -y -i "$OUT/$slug.wav" -c:a libvorbis -q:a 4 "$OUT/$slug.ogg" >/dev/null 2>&1
		rm -f "$OUT/$slug.wav"
	fi
}

echo "Generating NPC voice clips into $OUT/ ..."
gen yes               "Yes?"
gen hello             "Hello!"
gen hi_there          "Hi there!"
gen good_morning      "Good morning!"
gen hey               "Hey!"
gen see_you           "See you!"
gen take_care         "Take care!"
gen goodbye           "Goodbye!"
gen anytime_good_luck "Anytime, good luck!"
gen im_fine           "I'm fine!"
gen im_good           "I'm good!"
gen im_great_thanks   "I'm great, thanks!"
gen sorry_dont_know   "Sorry, I don't know that place."
gen its_over_there    "It's over there!"

echo "Done. Files in $OUT/. Now run: bash deploy.sh \"add NPC voice clips\""
