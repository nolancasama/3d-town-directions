#!/usr/bin/env bash
# =============================================================================
# generate_voices_edge.sh — pre-record the NPC lines with Microsoft edge-tts.
# -----------------------------------------------------------------------------
# Easiest option: installs cleanly on any modern Python (incl. 3.14), needs no
# model download, and produces high-quality neural voices. Outputs .mp3 files
# into assets/voice/ which Godot imports directly. The game loads them via
# DialogueManager.LINE_CLIPS and falls back to browser TTS for any missing file.
#
# NOTE: edge-tts uses Microsoft's online read-aloud endpoint (needs internet).
# Redistribution licensing of the generated audio is a grey area — fine for a
# prototype / educational project; for a commercial release prefer Piper
# (tools/generate_voices.sh) or a cloud TTS whose terms permit redistribution.
#
# SETUP (one time):
#   pip install edge-tts
#
# USAGE:
#   # Female voice:
#   bash tools/generate_voices_edge.sh en-US-AriaNeural female
#
#   # Male voice:
#   bash tools/generate_voices_edge.sh en-US-GuyNeural male
#
#   (list all voices with:  edge-tts --list-voices)
#
# Then re-deploy:  bash deploy.sh "add NPC voice clips"
# =============================================================================
set -euo pipefail

VOICE="${1:-en-US-AriaNeural}"
GENDER="${2:-female}"
OUT="assets/voice/${GENDER}"
mkdir -p "$OUT"

if ! command -v edge-tts >/dev/null 2>&1; then
	echo "ERROR: 'edge-tts' not found. Install with: pip install edge-tts" >&2
	exit 1
fi

gen() {
	local slug="$1"; local line="$2"
	echo "  $slug  <-  \"$line\""
	edge-tts --voice "$VOICE" --text "$line" --write-media "$OUT/$slug.mp3" >/dev/null 2>&1
}

echo "Generating NPC voice clips ($VOICE) into $OUT/ ..."
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
