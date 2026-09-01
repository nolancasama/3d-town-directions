# 3D Town Directions — Godot 4 Prototype

A small North-American-style town on a street grid with a central green. The
player walks up to an NPC, asks **"Where is the ... ?"** for any of ~20
destinations, watches the NPC point and the camera reveal the building, then
walks there to score a point. Built for teaching English directions and place
vocabulary.

Everything is made from primitive shapes and generated materials — **no
external assets required**.

---

## Quick start

1. Install **Godot 4.x** (standard build — no C# needed).
2. Open the Godot Project Manager → **Import** → select this folder's
   `project.godot`.
3. Press **F5** (Run Project). `Main.tscn` is already set as the main scene.

The project uses the **Compatibility (OpenGL/WebGL2) renderer** so it runs the
same in the editor and in the browser.

### Controls (keyboard — no mouse needed)

| Action | Key |
| --- | --- |
| Walk forward / back | `W` `S` or `↑` `↓` |
| Turn left / right | `A` `D` or `←` `→` |
| Talk to NPC (keyboard fallback) / confirm | `E` or `Space` |
| Navigate the destination menu | Arrow keys, then `Enter` / `Space` |

The camera is locked directly behind the avatar and turns with it, so you steer
entirely with the keyboard.

---

## How to play

After the opening, choose one of **three destinations**. Your choice appears in
the **DESTINATION** card at the top-left. Choosing does not give you directions:
you still need to ask a townsperson.

1. Walk close to an NPC. The microphone turns on and **!** appears.
2. Say **"Excuse me."** The NPC answers **"Yes?"**
3. Say **"Where is the &lt;place&gt;?"** using the exact place in your destination
   card, such as *"Where is the library?"*
4. The NPC points, the camera shows the place, and directions begin. Sometimes
   the NPC says **"I don't know. Ask him/her."** and points to another nearby
   NPC. Ask that person the same question.
5. Follow the streets to the assigned place. After the arrival celebration,
   choose your next destination from a new set of three.

You can also ask about another place while exploring. You still discover it,
but your assigned destination stays the same and the trip does not advance.
Sometimes, after an arrival, the character says **"I'm thirsty!"**,
**"I'm hungry!"**, or **"I'm tired!"** The next three choices will be places
that can help. There are no need meters.

**Keyboard fallback** (desktop editor, or if the mic is unavailable/denied):
use the arrow keys and `Enter` or `Space` in the three-choice screen. Press
**E** to greet an NPC, then type **"Where is the &lt;place&gt;?"** and press
`Enter`. The voice and keyboard paths drive the same flow.

> Speech recognition uses the browser's **Web Speech API** (Chrome/Chromebooks)
> and only works in a **web build served over HTTPS or localhost**. The
> **microphone-permission prompt appears at game start** (via `getUserMedia`);
> once allowed, the in-game listening uses it without re-prompting. It does
> nothing in the desktop editor — use the keyboard fallback there.

### The 25 goal buildings (one per block)

Every block has a goal building at its centre, packed around with houses, shops
and offices so the block reads as a dense city block and the streets form a
maze. The goals: **Library, Bank, Post Office, Museum, City Hall, Town Office,
Police Station, Fire Station, Hospital, Drugstore, Bakery, Bookstore, Starbucks,
McDonald's, Supermarket, Convenience Store, Diner, Gas Station, School, Swimming
Pool, Church, Shrine, Train Station, Motel**, and the central **Park**.

---

## Scene hierarchy

The scene file (`Main.tscn`) is intentionally just a single scripted node.
`Main.gd` builds the rest of the tree at runtime, so the *effective* hierarchy
while the game is running is:

```
Main (Node3D)                         [Main.gd]  — bootstrap & town builder
├── DirectionalLight3D                           — the "sun"
├── WorldEnvironment                             — procedural sky + ambient
├── Ground (StaticBody3D)
│   ├── MeshInstance3D (PlaneMesh)               — grass
│   └── CollisionShape3D (BoxShape3D)            — the floor
├── Roads (Node3D)                               — 5x5 street grid
│   └── …road slabs, sidewalks (broken at intersections), crosswalks, dashed
│       lane lines, sidewalk lampposts, stop signs at downtown intersections
├── Town (Node3D)                                — ~96 buildings, each a
│   └── StaticBody3D built per "style": civic (columns+pediment), brick,
│       hospital (cross), shop/market (storefront+awning), police, firehouse
│       (garage doors), station (clock tower), pool, shrine (torii), house
│       (pitched roof), church (steeple), gas/diner/motel/office, park.
│       Goal buildings carry a "reach_radius" meta (no name signs).
│       (After build, the visible meshes are baked into WorldMesh below; each
│        StaticBody keeps its CollisionShape3D.)
├── WorldMesh (MeshInstance3D)                    — all static road + building
│       geometry merged into one mesh, one surface per material (see Performance)
├── SpeechInput (Node)              [SpeechInput.gd]  — ONE shared Web Speech mic
├── DialogueManager (CanvasLayer)    [DialogueManager.gd]
│   ├── ScoreLabel (Label)
│   ├── CenterLabel (Label)                      — flashes "Correct! …"
│   └── DialoguePanel (PanelContainer)
│       └── speaker / prompt / ScrollContainer→GridContainer of options
├── Player (CharacterBody3D)         [PlayerController.gd]
│   ├── CollisionShape3D (CapsuleShape3D)
│   ├── Humanoid (Node3D)            [Humanoid.gd]  — walks (arms/legs swing)
│   └── CameraPivot (Node3D)                     — carries pitch
│       └── Camera3D                             — the player's view
├── NPC × ~12 (Node3D)               [NPCInteraction.gd]  — one per street
│   ├── Humanoid (Node3D)            [Humanoid.gd]  — patrols + points
│   ├── Hint (Label3D)                           — "Say 'Excuse me'…"
│   └── Area3D (SphereShape3D)                   — proximity (turns the mic on)
│      (all NPCs share the single SpeechInput; only the nearest one listens)
├── CameraFocusManager (Node3D)      [CameraFocusManager.gd]
│   └── Camera3D                                 — the "cutscene" view
└── GoalManager (Node)               [GoalManager.gd]
```

> **Why build in code?** A hand-written `.tscn` with dozens of meshes,
> materials, colliders and node-path references is easy to corrupt and hard to
> review. Building from `Main.gd` keeps the whole structure in one readable,
> commented place and guarantees the project runs on first open.

---

## Scripts (the requested architecture)

| Script | Responsibility |
| --- | --- |
| `Main.gd` | Registers input, builds the world (grid + buildings), bakes meshes, spawns & wires everything. |
| `Humanoid.gd` | Reusable walking person built from primitives; player, NPC, pedestrians. |
| `PlayerController.gd` | Keyboard third-person movement + behind-the-avatar camera. |
| `NPCInteraction.gd` | A townsperson (one per street): patrols, and on approach runs the voice conversation (greet → ask), pointing from its own position. E/menu fallback. |
| `SpeechInput.gd` | Speech-to-text via the browser Web Speech API (web only); one shared instance. |
| `DialogueManager.gd` | All 2D UI: score, dialogue box, scrollable options, "Correct!". |
| `CameraFocusManager.gd` | Smooth camera pan to reveal the pointed building. |
| `GoalManager.gd` | Detects arrival at the asked destination, awards the point. |

Managers receive their dependencies through a `setup()` call from `Main.gd`
(simple dependency injection) — no globals or autoloads needed.

---

## How the pointing & camera-focus systems work

### Pointing (NPCInteraction.gd)

* The NPC's arm is a box hanging from an **`ArmPivot`** placed at the shoulder.
  At rest the arm hangs straight down (`rotation.x = 0`).
* When the NPC speaks it first **turns to face the library**. We take the
  current orientation and the orientation returned by
  `global_transform.looking_at(library, UP)`, then `slerp` between the two
  quaternions over half a second so the turn is smooth (yaw only — the height
  is flattened first so the NPC doesn't tip).
* Because `looking_at` makes the NPC's local **−Z** axis point at the library,
  swinging the arm pivot to `rotation.x = +90°` makes the arm point *forward*,
  i.e. straight at the building. The pose is held while the camera does its
  thing, then lowered.

### Camera focus (CameraFocusManager.gd)

This manager owns a **second camera**. Godot only renders the camera whose
`current` property is `true`, and setting one `current` automatically clears
the others — so switching views is just flipping that flag.

The pan works in five steps:

1. Copy the **player camera's exact transform** into the focus camera and make
   the focus camera `current`. Starting from the player's real view means
   there's no jarring cut.
2. Compute a **vantage point**: a spot raised above and slightly behind the NPC
   (relative to the building), oriented with `looking_at(building)`.
3. Drive a `Tween` from `0 → 1` over ~1 second, and each step **interpolate**
   the camera: `lerp` the position and `slerp` the rotation quaternion between
   start and target. That produces a smooth glide rather than a teleport.
4. **Hold** on the building for ~2 seconds with a `SceneTreeTimer`.
5. Set the **player camera** `current` again, returning control.

The whole conversation is a single coroutine in `NPCInteraction._start_conversation()`
that `await`s each phase (turn → raise arm → camera focus → lower arm), and the
player's input is frozen for the duration via `PlayerController.set_input_enabled(false)`.

---

## Performance & playing on the web (Chromebooks)

The town is a **5×5 street-block grid with ~96 buildings**, but it's built to run
on low-power devices in a browser:

* **One baked mesh.** After `Main.gd` builds all the road + building geometry as
  separate `MeshInstance3D` nodes, `_bake_static_meshes()` merges them into a
  **single `MeshInstance3D` with one surface per material**. Identical materials
  (shared via the `_mat` color cache) collapse together, so the whole static
  world is ~90 surfaces / **~150 total draw calls** — and that number barely
  grows with more buildings, since new houses reuse existing materials.
* **No real-time shadows** (the directional light's shadow is off).
* **Compatibility renderer** (WebGL2), set in `project.godot`.
* Collision boxes and name signs are left as separate nodes (signs only on named
  places; houses are unlabeled) so the merge doesn't touch gameplay.

Measured on the OpenGL/Compatibility backend the whole town is **~140 draw
calls**, and in normal play it's lower still:

* **All buildings and roads are baked** into one mesh, so packing each block
  full of buildings (~215 total, for the dense "city maze" feel) costs no extra
  draw calls — only the distinct material colours add surfaces.
* **NPCs use distance hiding** — any NPC more than 70 units from the player is
  `visible = false`, so only the few near you are ever drawn (the rest cost
  nothing even when the camera can see their direction). NPCs are the only
  un-baked figures, so this is the main lever.

Well within a Chromebook's comfort zone (which starts to struggle around
800–1,200 draw calls).

### Exporting for the web

A **Web** export preset is already in `export_presets.cfg` (threads off, so it
works on simple static hosting without cross-origin-isolation headers).

1. In Godot: **Editor → Manage Export Templates → Download and Install** (one-time).
2. **Project → Export → Web → Export Project** to `build/web/index.html`
   (or headless: `godot --headless --export-release "Web" build/web/index.html`).
3. Serve the `build/web/` folder over HTTP (e.g. `python -m http.server`) and open
   it in Chrome on the Chromebook. (Browsers won't run the `.wasm` from a `file://`
   path — it must be served.)

## Extending it further

* **More blocks/buildings:** add lines to `GRID`, bump `EXT` and the ground size,
  and `_generate_fill()` will populate the new outer lots automatically. Draw
  calls stay low because of the bake.
* **More goal destinations:** add entries to `BUILDINGS` with `"goal": true`; the
  NPC menu, direction hints, and `GoalManager` pick them up automatically.
* **Better art:** swap the primitive meshes in `Main.gd` for imported models —
  the bake still merges anything with a shared material.
