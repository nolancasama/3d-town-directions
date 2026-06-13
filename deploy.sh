#!/usr/bin/env bash
# =============================================================================
# deploy.sh — re-export the Godot web build and publish it.
# -----------------------------------------------------------------------------
# Editing .gd source and pushing does NOT update the playable web version.
# The game ships as a prebuilt export (index.pck/.wasm/.js/.html) that lives:
#   * at the repo root on `master`  (the committed build)
#   * on the `gh-pages` branch       (what GitHub Pages actually serves)
#
# This script does all three steps in order:
#   1. Re-export the "Web" preset from current source (Godot 4.6.2).
#   2. Copy the build to the repo root and commit/push `master`.
#   3. Copy the build onto `gh-pages` (via a temp worktree) and push it.
#
# Usage:  bash deploy.sh ["optional commit message"]
#
# After it finishes, hard-refresh the Pages URL (Ctrl+Shift+R) — the browser
# and the game's service worker cache the old .pck aggressively.
# =============================================================================
set -euo pipefail

# --- Config ------------------------------------------------------------------
GODOT="/c/Users/nolan/Downloads/godot462/Godot_v4.6.2-stable_win64_console.exe"
REPO="C:/Users/nolan/3d-town-directions"
PRESET="Web"
MSG="${1:-Deploy: re-export web build with latest changes}"

# Files that make up the web deploy (must match what gh-pages tracks).
WEB_FILES=(
	coi-serviceworker.js
	index.apple-touch-icon.png
	index.audio.position.worklet.js
	index.audio.worklet.js
	index.html
	index.icon.png
	index.js
	index.pck
	index.png
	index.wasm
)
# Subset that lives at the repo root on master.
ROOT_FILES=(index.html index.js index.pck index.wasm)

cd "$REPO"

if [ ! -f "$GODOT" ]; then
	echo "ERROR: Godot not found at: $GODOT" >&2
	echo "Edit the GODOT path at the top of deploy.sh." >&2
	exit 1
fi

# --- 1. Export ---------------------------------------------------------------
echo "==> Exporting '$PRESET' build..."
mkdir -p build/web
"$GODOT" --headless --path "$REPO" \
	--export-release "$PRESET" "$REPO/build/web/index.html"
echo "    export done (index.pck = $(stat -c%s build/web/index.pck) bytes)"

# --- 2. Update master --------------------------------------------------------
echo "==> Updating master root build..."
for f in "${ROOT_FILES[@]}"; do
	cp "build/web/$f" "$f"
done
git add "${ROOT_FILES[@]}"
if git diff --cached --quiet; then
	echo "    no build changes on master (source produced an identical build)"
else
	git commit -m "$MSG"
	git push origin master
	echo "    master pushed"
fi

# --- 3. Update gh-pages (the live site) --------------------------------------
echo "==> Updating gh-pages..."
WT="$(mktemp -d)/ghp"
git worktree add "$WT" gh-pages >/dev/null
for f in "${WEB_FILES[@]}"; do
	cp "build/web/$f" "$WT/$f"
done
(
	cd "$WT"
	git add -A
	if git diff --cached --quiet; then
		echo "    no changes on gh-pages"
	else
		git commit -m "$MSG"
		git push origin gh-pages
		echo "    gh-pages pushed"
	fi
)
git worktree remove "$WT" --force

echo ""
echo "==> Deploy complete."
echo "    Live in ~1-3 min: https://nolancasama.github.io/3d-town-directions/"
echo "    Hard-refresh (Ctrl+Shift+R) to bypass the service-worker cache."
