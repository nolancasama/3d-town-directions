extends Node3D
# =============================================================================
# Main.gd  -  Bootstrap / TownBuilder
# -----------------------------------------------------------------------------
# Builds a small North-American-style town on a STREET GRID, then populates it:
#   * A central green (the Park) ringed by civic buildings (town-square logic).
#   * 19 "goal" buildings dispersed across town following loose city logic
#     (civic core downtown, commercial frontage on main streets, services to
#     one side, transport toward the edge, recreation/landmark toward the
#     outskirts).
#   * The remaining lots filled with miscellaneous buildings a US town has
#     (houses, church, gas station, diner, motel, office...).
#
# Everything is primitive geometry. Buildings are authored in LOCAL space with
# their front on +Z, then rotated so the front faces the nearest street.
# =============================================================================

# --- Street grid -------------------------------------------------------------
# 5x5 blocks of 64 units. Buildings are packed into each block (see
# _layout_buildings), and the street grid between blocks is the "maze".
const GRID := [-135.0, -81.0, -27.0, 27.0, 81.0, 135.0]   # x/z positions of street lines (54-unit spacing)
const ROAD_W := 9.0
const HALF := 4.5                          # road half width
const SW_W := 2.2                          # sidewalk width
const SW_OFF := HALF + 1.1                  # sidewalk center offset from road line (5.6)
const EXT := 150.0                          # how far roads/sidewalks run from origin
const HALF_BLOCK := 27.0                    # block centre -> inner street line (= spacing / 2)

const PLAYER_SPAWN := Vector3(0, 1, 16)
const NPC_SPAWN := Vector3(0, 0, 9)

# --- Palette -----------------------------------------------------------------
const ASPHALT := Color(0.17, 0.17, 0.20)
const SIDEWALK := Color(0.66, 0.66, 0.69)
const LINE := Color(0.90, 0.88, 0.66)

# Each building: name, lot position (y=0), footprint size, base color, style,
# and whether it is a navigable goal. `accent` tints trims/awnings/roofs.
const GOAL_DEFS := {
	"Library": {"style": "civic", "size": Vector3(16, 11, 13), "color": Color(0.80, 0.73, 0.55)},
	"Bank": {"style": "civic", "size": Vector3(16, 10, 13), "color": Color(0.82, 0.81, 0.77), "accent": Color(0.80, 0.66, 0.18)},
	"Post Office": {"style": "civic", "size": Vector3(16, 9, 13), "color": Color(0.74, 0.70, 0.62)},
	"Museum": {"style": "civic", "size": Vector3(18, 12, 15), "color": Color(0.86, 0.84, 0.78)},
	"City Hall": {"style": "civic", "size": Vector3(16, 12, 14), "color": Color(0.85, 0.82, 0.74), "accent": Color(0.70, 0.60, 0.20)},
	"Police Station": {"style": "police", "size": Vector3(14, 8, 13), "color": Color(0.32, 0.38, 0.52), "accent": Color(0.15, 0.20, 0.35)},
	"Fire Station": {"style": "firehouse", "size": Vector3(15, 9, 15), "color": Color(0.66, 0.13, 0.11), "accent": Color(0.20, 0.20, 0.22)},
	"Hospital": {"style": "hospital", "size": Vector3(18, 13, 16), "color": Color(0.93, 0.95, 0.97)},
	"Drugstore": {"style": "shop", "size": Vector3(13, 7, 12), "color": Color(0.30, 0.55, 0.45), "accent": Color(0.85, 0.85, 0.88)},
	"Bakery": {"style": "shop", "size": Vector3(12, 7, 11), "color": Color(0.86, 0.72, 0.55), "accent": Color(0.75, 0.45, 0.30)},
	"Bookstore": {"style": "shop", "size": Vector3(12, 7, 11), "color": Color(0.45, 0.36, 0.55), "accent": Color(0.30, 0.22, 0.40)},
	"Starbucks": {"style": "shop", "size": Vector3(11, 6, 11), "color": Color(0.10, 0.42, 0.27), "accent": Color(0.05, 0.30, 0.18)},
	"Restaurant": {"style": "shop", "size": Vector3(12, 6, 11), "color": Color(0.74, 0.13, 0.11), "accent": Color(0.95, 0.78, 0.10)},
	"Supermarket": {"style": "market", "size": Vector3(20, 7, 18), "color": Color(0.80, 0.34, 0.26), "accent": Color(0.55, 0.20, 0.15)},
	"Convenience Store": {"style": "shop", "size": Vector3(12, 6, 11), "color": Color(0.90, 0.55, 0.20), "accent": Color(0.55, 0.30, 0.10)},
	"Gas Station": {"style": "gas", "size": Vector3(14, 4, 11)},
	"School": {"style": "brick", "size": Vector3(18, 8, 14), "color": Color(0.68, 0.27, 0.22)},
	"Swimming Pool": {"style": "pool", "size": Vector3(20, 3, 16), "color": Color(0.80, 0.80, 0.82), "accent": Color(0.25, 0.55, 0.85)},
	"Church": {"style": "church", "size": Vector3(14, 9, 16), "color": Color(0.95, 0.95, 0.93)},
	"Hotel": {"style": "office", "size": Vector3(14, 13, 13), "color": Color(0.72, 0.68, 0.64), "accent": Color(0.55, 0.50, 0.48)},
	"Nolan's House": {"style": "house", "size": Vector3(10, 4, 9), "color": Color(0.78, 0.72, 0.62), "accent": Color(0.38, 0.25, 0.18)},
}

# One goal per block across the 5x5 grid (rows north->south, cols west->east).
# The central block is the Park (town green).
const GOAL_GRID := [
	["Hotel", "School", "Convenience Store", "", "Nolan's House"],
	["Hospital", "Library", "Bakery", "Bank", "Police Station"],
	["Drugstore", "Museum", "Park", "Post Office", "Fire Station"],
	["Church", "Starbucks", "Restaurant", "City Hall", ""],
	["", "Swimming Pool", "Supermarket", "Bookstore", "Gas Station"],
]

const BLOCK_CENTERS := [-108.0, -54.0, 0.0, 54.0, 108.0]   # world block centres

# Wall-poster ads: place -> [ad sentence, opening hours]. Each ad is mounted on
# a building FAR from the real place, so it hints that the place exists without
# revealing where it is.
const POSTER_ADS := {
	"Hotel": ["Stay at the Hotel!", "Open 24 Hours"],
	"Convenience Store": ["Need a Snack? Visit the Convenience Store!", "Open 24 Hours"],
	"Bakery": ["Fresh Bread at the Bakery!", "7:00 AM - 6:00 PM"],
	"Drugstore": ["Need Medicine? Visit the Drugstore!", "8:00 AM - 9:00 PM"],
	"Museum": ["Discover History at the Museum!", "9:00 AM - 5:00 PM"],
	"Starbucks": ["Hot Coffee at Starbucks!", "6:00 AM - 8:00 PM"],
	"Restaurant": ["Eat at the Restaurant!", "11:00 AM - 9:00 PM"],
	"Swimming Pool": ["Swim at the Swimming Pool!", "9:00 AM - 6:00 PM"],
	"Supermarket": ["Fresh Food at the Supermarket!", "7:00 AM - 10:00 PM"],
	"Bookstore": ["New Books at the Bookstore!", "9:00 AM - 8:00 PM"],
	"Gas Station": ["Stop at the Gas Station!", "Open 24 Hours"],
	"Train Station": ["Take the Train from the Train Station!", "Open 24 Hours"],
	"Beach": ["Have Fun at the Beach!", "Open All Day"],
	"Shopping Mall": ["Come to the Shopping Mall!", "10:00 AM - 9:00 PM"],
}

# Palettes for the procedural filler buildings, so the streets look varied.
const HOUSE_COLORS := [
	Color(0.85, 0.80, 0.70), Color(0.70, 0.78, 0.82), Color(0.82, 0.72, 0.68),
	Color(0.75, 0.80, 0.72), Color(0.88, 0.84, 0.74), Color(0.78, 0.74, 0.80),
	Color(0.66, 0.74, 0.66), Color(0.86, 0.78, 0.66), Color(0.62, 0.66, 0.72),
	Color(0.80, 0.66, 0.60), Color(0.74, 0.82, 0.84), Color(0.90, 0.86, 0.80),
]
const ROOF_COLORS := [
	Color(0.45, 0.28, 0.22), Color(0.30, 0.34, 0.40), Color(0.55, 0.42, 0.30),
	Color(0.35, 0.30, 0.32), Color(0.50, 0.30, 0.28), Color(0.32, 0.40, 0.36),
]
const SHOP_COLORS := [
	Color(0.62, 0.55, 0.45), Color(0.50, 0.58, 0.62), Color(0.68, 0.50, 0.45),
	Color(0.55, 0.62, 0.52), Color(0.66, 0.60, 0.50),
]
const OFFICE_COLORS := [
	Color(0.55, 0.60, 0.66), Color(0.60, 0.64, 0.62), Color(0.52, 0.58, 0.64),
]

var _mat_cache := {}   # color -> StandardMaterial3D (shared to cut resource churn)
var _brick_cache: Dictionary = {}        # color -> brick StandardMaterial3D (dark mortar)
var _brick_light_cache: Dictionary = {}  # color -> brick StandardMaterial3D (light mortar)
var _brick_white_cache: Dictionary = {}  # color -> brick StandardMaterial3D (white mortar)
var _siding_cache: Dictionary = {}       # color -> siding StandardMaterial3D
var _speckle_cache: Dictionary = {}      # color -> speckle/stucco StandardMaterial3D
var _grass_cache: Dictionary = {}        # color -> grass-textured StandardMaterial3D
var _shingle_cache: Dictionary = {}      # color -> roof-shingle StandardMaterial3D
var _flat_roof_cache: Dictionary = {}   # color -> flat-roof gravel StandardMaterial3D
var _ripple_cache: Dictionary = {}      # color -> water-ripple StandardMaterial3D
var _vpaint_cache: Dictionary = {}     # color -> shiny vehicle paint StandardMaterial3D
var _brick_wall_color: Color = Color.TRANSPARENT
var _brick_light_wall_color: Color = Color.TRANSPARENT
var _brick_white_wall_color: Color = Color.TRANSPARENT
var _siding_wall_color: Color = Color.TRANSPARENT
var _speckle_wall_color: Color = Color.TRANSPARENT
var _grass_wall_color: Color = Color.TRANSPARENT
var _brick_tex:       ImageTexture
var _brick_light_tex: ImageTexture
var _brick_white_tex: ImageTexture
var _siding_tex:      ImageTexture
var _speckle_tex:     ImageTexture
var _shingle_tex:     ImageTexture
var _asphalt_tex:     ImageTexture
var _gravel_tex:      ImageTexture
var _ripple_tex:      ImageTexture
var _concrete_tex: ImageTexture   # sidewalk panel joints
var _grass_tex:    ImageTexture
var _bark_tex:     ImageTexture
var _leaf_tex:     ImageTexture
var _sand_tex:     ImageTexture
var _glass_cache: Dictionary = {}
var _house_i := 0
var _props: StaticBody3D   # holds collision shapes for lampposts / trees
var _roads: Node3D         # parent for road geometry + lampposts (baked)

# Intro-cinematic scratch state (used by the camera tween callbacks).
var _intro_cam: Camera3D
var _intro_title: CanvasLayer
var _io_center: Vector3
var _io_radius: float
var _io_height: float
var _im_p0: Vector3
var _im_p1: Vector3
var _im_l0: Vector3
var _im_l1: Vector3

var _dialogue: DialogueManager
var _bgm_player: AudioStreamPlayer
var _bus_ref: Node3D
var _bus_origin_x: float
var _icon_nodes: Dictionary = {}   # building name -> Node3D (hidden until discovered)
var _icons_root: Node3D
var _cine_skip: bool = false
var _water_warned: bool = false
var _player_ref: PlayerController = null
var _orbit_tween: Tween = null
var _orbit_a1: float = 0.0
var _walk_finished: bool = false   # instance var: GDScript lambdas capture locals by VALUE,
								   # so the walk_done callback must write to a member, not a local.


func _ready() -> void:
	_setup_input()

	_build_environment()
	_build_ground()
	_build_bounds()
	# Collision-only body that props (lampposts, trees) add their colliders to,
	# so the player can't walk through them even though their meshes get baked.
	_props = StaticBody3D.new()
	_props.name = "Props"
	add_child(_props)
	_icons_root = Node3D.new()
	_icons_root.name = "Icons"
	add_child(_icons_root)
	_brick_tex       = _make_brick_texture(Color(0.97, 0.96, 0.95))
	_brick_light_tex = _make_brick_texture(Color(0.92, 0.90, 0.87))
	_brick_white_tex = _make_brick_texture(Color(0.97, 0.96, 0.95))
	_siding_tex      = _make_siding_texture()
	_speckle_tex     = _make_speckle_tex()
	_shingle_tex     = _make_shingle_tex()
	_asphalt_tex     = _make_asphalt_tex()
	_gravel_tex      = _make_gravel_tex()
	_ripple_tex      = _make_ripple_tex()
	_concrete_tex = _make_concrete_tex()
	_grass_tex    = _make_grass_tex()
	_bark_tex     = _make_bark_tex()
	_leaf_tex     = _make_leaf_tex()
	_sand_tex     = _make_sand_tex()
	_build_roads()
	var goals: Dictionary = {}
	var goal_names: Array = []
	var layout := _layout_buildings()
	_build_town(layout, goals, goal_names)
	# Train Station goal is the new north platform (not a grid block building).
	# Registered manually so NPCs can navigate the player there.
	var ts_anchor := Node3D.new()
	ts_anchor.name = "TrainStationAnchor"
	ts_anchor.position = Vector3(0, 0, -148)
	add_child(ts_anchor)
	ts_anchor.set_meta("goal_spot", Vector3(0, 0, -145))
	ts_anchor.set_meta("goal_reach", 8.0)
	ts_anchor.set_meta("goal_street_axis_x", false)
	ts_anchor.set_meta("goal_street_line", -135.0)
	ts_anchor.set_meta("goal_seg_half", HALF_BLOCK - HALF)
	ts_anchor.set_meta("label_pos", Vector3(0, 7.0, -148))
	goals["Train Station"] = ts_anchor
	goal_names.append("Train Station")

	# Beach goal â€” ring appears on the sand.
	var beach_anchor := Node3D.new()
	beach_anchor.name = "BeachAnchor"
	beach_anchor.position = Vector3(0, 0, 162)
	add_child(beach_anchor)
	beach_anchor.set_meta("goal_spot", Vector3(0, 0, 155))
	beach_anchor.set_meta("goal_reach", 14.0)
	beach_anchor.set_meta("goal_zone_z_min", 143.0)
	beach_anchor.set_meta("goal_street_axis_x", false)
	beach_anchor.set_meta("goal_street_line", 135.0)
	beach_anchor.set_meta("goal_seg_half", HALF_BLOCK - HALF)
	beach_anchor.set_meta("label_pos", Vector3(0, 5.0, 162))
	goals["Beach"] = beach_anchor
	goal_names.append("Beach")

	# Shopping Mall goal â€” ring appears in front of the west entrance (facing the sidewalk).
	var mall_anchor := Node3D.new()
	mall_anchor.name = "MallAnchor"
	mall_anchor.position = Vector3(162, 0, -27)
	add_child(mall_anchor)
	mall_anchor.set_meta("goal_spot", Vector3(141, 0, -27))
	mall_anchor.set_meta("goal_reach", 12.0)
	mall_anchor.set_meta("goal_street_axis_x", true)
	mall_anchor.set_meta("goal_street_line", 135.0)
	mall_anchor.set_meta("goal_seg_half", HALF_BLOCK - HALF)
	mall_anchor.set_meta("label_pos", Vector3(162, 12.0, -27))
	goals["Shopping Mall"] = mall_anchor
	goal_names.append("Shopping Mall")

	# Lampposts go in after the buildings so they can be placed in the gaps
	# between the frontage buildings rather than in front of a door.
	_build_lampposts(layout)

	# Expanded world zones (beach, train tracks, woods, mall).
	var terrain := Node3D.new()
	terrain.name = "Terrain"
	add_child(terrain)
	_build_beach(terrain)
	_build_train_tracks(terrain)
	_build_woods(terrain)
	_build_mall(terrain)
	_build_woods_fog()

	# Merge all the static road + building geometry into one mesh grouped by
	# material. This turns ~1000+ draw calls into a few dozen so the WebGL2
	# (Compatibility) build runs smoothly on low-power devices like Chromebooks.
	_tune_materials()
	_bake_static_meshes()
	_apply_terrain_textures()

	# --- Spawn actors and managers -------------------------------------------
	_dialogue = DialogueManager.new()
	add_child(_dialogue)

	var player := PlayerController.new()
	player.position = PLAYER_SPAWN
	add_child(player)
	_player_ref = player

	var camera_focus := CameraFocusManager.new()
	add_child(camera_focus)

	var goal := GoalManager.new()
	add_child(goal)

	# One shared microphone/recognizer for every NPC (only the nearest listens).
	var speech := SpeechInput.new()
	add_child(speech)

	camera_focus.setup(player.camera)
	goal.setup(player, _dialogue, camera_focus, _icon_nodes)
	_dialogue.init_discovery(goal_names.size())

	_spawn_npcs(_dialogue, camera_focus, player, goal, goals, goal_names, speech)
	_spawn_posters(goals, player, layout, goal)
	_spawn_welcome_sign(player, goal)
	_play_intro(player)


# -----------------------------------------------------------------------------
# Opening cinematic: orbit the player from a high angle, hold a high-angle shot,
# then low pans across the buildings ringing the park, then hand over control.
# -----------------------------------------------------------------------------
func _play_intro(player: PlayerController) -> void:
	# Block all NPC interaction for the entire cinematic so NPCs can't overwrite
	# Matsubara's dialogue lines or hijack the dialogue panel.
	NPCInteraction._cinematic = true

	player.set_input_enabled(false)
	_intro_cam = Camera3D.new()
	add_child(_intro_cam)
	_intro_cam.current = true

	var player_start := player.global_position
	# Player faces north (toward town) from the moment he steps off the bus.
	player.rotation.y = 0.0
	# Hide player for the orbital shot; they step off the bus at the midpoint.
	player.visible = false
	var focus := player.global_position + Vector3(0, 1.2, 0)

	# Bus parked at the curb: north face (z-1.25) flush with the curb at z=22.5,
	# so the bus centre sits at z=23.75, entirely on the road.
	var bus := _build_intro_bus()
	bus.position = Vector3(0, 0, 23.75)

	# Title card fades in 2 s into the orbit (fire-and-forget coroutine).
	_show_intro_title()

	# BGM starts with the title card and loops for the rest of the game.
	_bgm_player = AudioStreamPlayer.new()
	add_child(_bgm_player)
	_bgm_player.stream = _make_bgm()
	_bgm_player.volume_db = -10.0
	_bgm_player.play()

	# 1) High-angle orbit â€” continuous half-turn over 11 s.
	_intro_orbit(focus, 14.0, 26.0, -PI * 0.5, PI * 0.5, 11.0)
	# At the midpoint the player steps off the bus and walks to their start position.
	await _cine_wait(5.5)
	player.global_position = Vector3(bus.position.x + 2.5, 0.0, bus.position.z - 1.5)
	player.rotation.y = 0.0
	player.visible = true
	player.walk_to(player_start, 3.0)   # half speed for cinematic walk
	_walk_finished = false
	player.walk_done.connect(func(): _walk_finished = true, CONNECT_ONE_SHOT)
	while not _walk_finished:
		await get_tree().process_frame
		if _cine_skip:
			_cine_skip = false
			player.stop_walk()
			player.global_position = player_start
			break
	# Let the orbit run to its natural end (bus parallel to screen bottom).
	while _orbit_tween != null:
		await get_tree().process_frame
	player.rotation.y = PI  # face south â€” toward the camera for his introduction

	# 2) Hard cut to side bus shot.
	_intro_cam.position = Vector3(0, 2.0, 32)
	_intro_cam.look_at(Vector3(0, 1.5, 23.75), Vector3.UP)
	await _cine_wait(0.6)

	# 3) Engine starts, bus rumbles for 1 s, then drives off camera-left.
	_bus_ref = bus
	_bus_origin_x = bus.position.x
	var engine := AudioStreamPlayer.new()
	add_child(engine)
	engine.stream = _make_engine_sound()
	engine.volume_db = -4.0
	engine.play()

	var rt := create_tween()
	rt.tween_method(_apply_bus_rumble, 0.0, 0.5, 0.5)
	while rt.is_running():
		await get_tree().process_frame
		if _cine_skip:
			_cine_skip = false; rt.kill()
			break
	bus.position = Vector3(_bus_origin_x, 0.0, bus.position.z)

	var bt := create_tween()
	bt.set_ease(Tween.EASE_IN)
	bt.set_trans(Tween.TRANS_SINE)
	bt.tween_property(bus, "position:x", -55.0, 4.5)
	var rv := create_tween()
	rv.tween_property(engine, "pitch_scale", 2.2, 4.0)
	while bt.is_running():
		await get_tree().process_frame
		if _cine_skip:
			_cine_skip = false; bt.kill(); rv.kill(); break

	engine.queue_free()
	bus.queue_free()

	# 4) Push-in to the player's face â€” Matsubara introduces himself.
	var face_pos := Vector3(0, 2.5, 24)
	_dialogue.show_text("Matsubara kun", "ã‚„ã‚ï¼ã¼ãæ¾åŽŸãã‚“ã‚„ã§ï¼ã‚¢ãƒ¡ãƒªã‚«æ¥ã‚‹ã®åˆã‚ã¦ã‚„ã­ã‚“ï¼")
	await _intro_move(Vector3(0, 2.0, 32), face_pos, Vector3(0, 1.5, 23.75), focus, 5.0)
	await _cine_wait(1.0)

	# 5) Town pan shots.
	player.rotation.y = PI
	_dialogue.show_text("Matsubara kun", "ã‚ã‚ï¼ã‚ã£ã¡ã‚ƒåºƒã„ãªã‚ã€ã‚¢ãƒ¡ãƒªã‚«ï¼")
	await _intro_move(Vector3(0, 4, -12), Vector3(0, 4, -12),
			Vector3(-35, 5, -54), Vector3(35, 5, -54), 3.8)
	await _intro_move(Vector3(12, 4, 0), Vector3(12, 4, 0),
			Vector3(54, 5, -35), Vector3(54, 5, 35), 3.8)

	# 6) Close-up of Matsubara's face, then ask for help after a short delay.
	var close_pos := Vector3(0, 1.7, 19.5)
	var close_look := player.global_position + Vector3(0, 0.8, 0)
	await _intro_move(Vector3(12, 4, 0), close_pos, Vector3(54, 5, 35), close_look, 2.0)

	_dialogue.show_text("Matsubara kun", "ã©ã“ã«ä½•ãŒã‚ã‚‹ã‚“ã‹ã€ãœã‚“ãœã‚“ã‚ã‹ã‚‰ã¸ã‚“ï¼åŠ©ã‘ã¦ãã‚Œã¸ã‚“ï¼Ÿ")
	await _cine_wait(3.0)   # buttons appear after 3 s OR immediately on skip

	var idx: int = await _dialogue.show_options("Matsubara kun",
			"ã©ã“ã«ä½•ãŒã‚ã‚‹ã‚“ã‹ã€ãœã‚“ãœã‚“ã‚ã‹ã‚‰ã¸ã‚“ï¼åŠ©ã‘ã¦ãã‚Œã¸ã‚“ï¼Ÿ",
			["åŠ©ã‘ã‚‹", "æ–­ã‚‹"])

	if idx != 0:
		_dialogue.show_text("Matsubara kun", "é ¼ã‚€ã‚ã€œï¼")
		await _cine_wait(2.0)
		idx = await _dialogue.show_options(
				"Matsubara kun", "é ¼ã‚€ã‚ã€œï¼", ["åŠ©ã‘ã‚‹", "æ–­ã‚‹"])
		if idx != 0:
			_dialogue.show_text("Matsubara kun", "ãã£ã‹ã€œã€æ®‹å¿µã‚„ã‚ã€‚ã»ãªã€ã•ã„ãªã‚‰ï¼")
			await _cine_wait(3.0)
			_dialogue.hide_dialogue()
			_fade_out_intro_title()
			NPCInteraction._cinematic = false
			player.visible = false
			_intro_cam.queue_free()
			_intro_cam = null
			get_tree().quit()
			return

	# 7) Matsubara thanks the player.
	_dialogue.show_text("Matsubara kun", "ãŠãŠãã«ï¼èª°ã‹ã«é“ãã„ãŸã‚‰ãˆãˆãªã€‚")
	await _cine_wait(3.5)
	_dialogue.hide_dialogue()

	# 8) Camera pans to reveal the welcome sign.
	player.rotation.y = PI
	await _intro_move(close_pos, Vector3(10, 3, 26),
			close_look, Vector3(5, 1.5, 20), 2.5)
	await _cine_wait(2.0)

	# Unblock NPCs and hand control back to the player.
	NPCInteraction._cinematic = false
	_fade_out_intro_title()
	player.visible = true
	_intro_cam.queue_free()
	_intro_cam = null
	player.camera.current = true
	player.set_input_enabled(true)
	_dialogue.show_discovery_panel()
	_fade_out_bgm()
	_setup_train_schedule()


func _fade_out_bgm() -> void:
	await get_tree().create_timer(3.0).timeout
	if not is_instance_valid(_bgm_player):
		return
	var ft := create_tween()
	ft.tween_property(_bgm_player, "volume_db", -60.0, 2.0)
	await ft.finished
	if is_instance_valid(_bgm_player):
		_bgm_player.stop()
	_start_ambient()


func _start_ambient() -> void:
	var hum := AudioStreamPlayer.new()
	add_child(hum)
	hum.stream = _make_ambient_hum()
	hum.volume_db = -30.0
	hum.play()
	_ambient_bird_loop()
	_ambient_traffic_loop()


func _ambient_bird_loop() -> void:
	while is_inside_tree():
		await get_tree().create_timer(randf_range(14.0, 25.0)).timeout
		if not is_inside_tree():
			return
		var chirp := AudioStreamPlayer.new()
		add_child(chirp)
		chirp.stream = _make_bird_chirp()
		chirp.volume_db = randf_range(-28.0, -20.0)
		chirp.play()
		await chirp.finished
		chirp.queue_free()


func _ambient_traffic_loop() -> void:
	while is_inside_tree():
		await get_tree().create_timer(randf_range(8.0, 20.0)).timeout
		if not is_inside_tree():
			return
		var car := AudioStreamPlayer.new()
		add_child(car)
		car.stream = _make_traffic_whoosh()
		car.volume_db = -22.0
		car.play()
		await car.finished
		car.queue_free()




func _make_ambient_hum() -> AudioStreamWAV:
	var rate := 11025
	var num_samples := int(4.0 * rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var prev := 0.0
	for s in num_samples:
		prev = prev * 0.93 + randf_range(-1.0, 1.0) * 0.07
		var iv := int(clampf(prev, -1.0, 1.0) * 32767.0)
		data[s * 2]     = iv & 0xFF
		data[s * 2 + 1] = (iv >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format     = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate   = rate
	wav.stereo     = false
	wav.data       = data
	wav.loop_mode  = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end   = num_samples - 1
	return wav


func _make_bird_chirp() -> AudioStreamWAV:
	var rate      := 11025
	var base_freq := randf_range(1800.0, 3000.0)
	var num_notes := randi_range(3, 6)
	var note_s    := int(0.07 * rate)
	var gap_s     := int(0.03 * rate)
	var freqs: Array[float] = []
	var f := base_freq
	for _i in num_notes:
		freqs.append(f)
		f += randf_range(-350.0, 500.0)
		f = clampf(f, 1400.0, 4200.0)
	var num_samples := num_notes * note_s + (num_notes - 1) * gap_s
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var phase := 0.0
	var s := 0
	for ni in num_notes:
		var freq: float = freqs[ni]
		var peak := freq + randf_range(200.0, 600.0)
		for ns in note_s:
			var p := float(ns) / float(note_s)
			var cur_freq := freq + (peak - freq) * sin(p * PI)
			var env := sin(p * PI)
			var iv := int(clampf(sin(phase) * env * 0.65, -1.0, 1.0) * 32767.0)
			data[s * 2]     = iv & 0xFF
			data[s * 2 + 1] = (iv >> 8) & 0xFF
			phase += TAU * cur_freq / float(rate)
			s += 1
		if ni < num_notes - 1:
			for _g in gap_s:
				data[s * 2]     = 0
				data[s * 2 + 1] = 0
				phase += TAU * freq / float(rate)
				s += 1
	var wav := AudioStreamWAV.new()
	wav.format   = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo   = false
	wav.data     = data
	return wav


func _make_traffic_whoosh() -> AudioStreamWAV:
	var rate := 11025
	var num_samples := int(2.0 * rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var prev := 0.0
	for s in num_samples:
		var env := sin(float(s) / float(num_samples) * PI)
		prev = prev * 0.85 + randf_range(-1.0, 1.0) * 0.15
		var iv := int(clampf(prev * env, -1.0, 1.0) * 32767.0)
		data[s * 2]     = iv & 0xFF
		data[s * 2 + 1] = (iv >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format   = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo   = false
	wav.data     = data
	return wav


# Orbit the intro camera around `center` at the given radius/height, sweeping the
# angle a0 -> a1 while always looking at the centre.
# Skip the current cinematic wait when the player presses Space/Enter.
# First press during typewriter: complete the text. Second (or non-typewriter): skip wait.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode not in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		return
	if not NPCInteraction._cinematic:
		return
	if _dialogue != null and _dialogue.is_typing():
		_dialogue.skip_typewriter()
	else:
		_cine_skip = true


func _cine_wait(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		if _cine_skip:
			_cine_skip = false
			return
		elapsed += get_process_delta_time()


func _intro_orbit(center: Vector3, radius: float, height: float,
		a0: float, a1: float, dur: float) -> void:
	_orbit_a1 = a1
	_io_center = center
	_io_radius = radius
	_io_height = height
	_apply_intro_orbit(a0)
	_orbit_tween = create_tween()
	_orbit_tween.set_trans(Tween.TRANS_SINE)
	_orbit_tween.set_ease(Tween.EASE_IN_OUT)
	_orbit_tween.tween_method(_apply_intro_orbit, a0, a1, dur)
	while _orbit_tween != null and _orbit_tween.is_running():
		await get_tree().process_frame
		if _cine_skip:
			_cine_skip = false
			if _orbit_tween != null:
				_orbit_tween.kill()
				_orbit_tween = null
			_apply_intro_orbit(a1)
			return
	_orbit_tween = null


func _apply_intro_orbit(a: float) -> void:
	if _intro_cam == null:
		return
	_intro_cam.position = _io_center + Vector3(cos(a) * _io_radius, _io_height, sin(a) * _io_radius)
	_intro_cam.look_at(_io_center, Vector3.UP)


# Slide the intro camera from p0->p1 while its look target slides l0->l1.
func _intro_move(p0: Vector3, p1: Vector3, l0: Vector3, l1: Vector3, dur: float) -> void:
	_im_p0 = p0
	_im_p1 = p1
	_im_l0 = l0
	_im_l1 = l1
	_apply_intro_move(0.0)
	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE)
	t.set_ease(Tween.EASE_IN_OUT)
	t.tween_method(_apply_intro_move, 0.0, 1.0, dur)
	while t.is_running():
		await get_tree().process_frame
		if _cine_skip:
			_cine_skip = false
			t.kill()
			_apply_intro_move(1.0)
			return


func _apply_intro_move(f: float) -> void:
	if _intro_cam == null:
		return
	_intro_cam.position = _im_p0.lerp(_im_p1, f)
	_intro_cam.look_at(_im_l0.lerp(_im_l1, f), Vector3.UP)


# Oscillate the bus around its parked position to simulate engine vibration.
func _apply_bus_rumble(t: float) -> void:
	if not is_instance_valid(_bus_ref):
		return
	_bus_ref.position.x = _bus_origin_x + sin(t * 48.0) * 0.025
	_bus_ref.position.y = absf(sin(t * 67.0)) * 0.01


# Happy whimsical background music, procedurally synthesised as a looping WAV.
# Bell/xylophone timbre (decaying sine + 2nd harmonic). Loops seamlessly because
# all notes decay to silence well before the loop point.
func _make_bgm() -> AudioStreamWAV:
	var rate := 11025
	var beat := 0.25   # eighth note at 120 BPM

	# [frequency_hz, eighth_note_count]  â€” 0.0 = rest
	# Four 16-beat phrases = 64 eighth notes = 16 s at 120 BPM before looping.
	var seq: Array = [
		# Phrase A â€” bright opening
		[659.25, 1], [783.99, 1], [880.00, 2], [783.99, 1], [659.25, 1], [523.25, 2],
		[587.33, 1], [659.25, 1], [783.99, 2], [659.25, 2], [0.0, 2],
		# Phrase B â€” stepwise climb and fall
		[523.25, 1], [587.33, 1], [659.25, 1], [698.46, 1], [783.99, 4],
		[698.46, 1], [659.25, 1], [587.33, 1], [523.25, 1], [659.25, 2], [0.0, 2],
		# Phrase C â€” soar into upper register
		[659.25, 1], [783.99, 1], [880.00, 1], [987.77, 1], [1046.50, 2], [880.00, 2],
		[783.99, 1], [880.00, 1], [783.99, 1], [698.46, 1], [659.25, 2], [523.25, 2],
		# Phrase D â€” triumphant finish, land on long tonic
		[523.25, 1], [659.25, 1], [783.99, 1], [880.00, 1], [987.77, 2], [1046.50, 2],
		[880.00, 1], [783.99, 1], [698.46, 1], [659.25, 1], [523.25, 4],
	]

	var total_beats := 0
	for entry in seq:
		total_beats += int(entry[1])
	var total_samples := int(total_beats * beat * rate)

	var data := PackedByteArray()
	data.resize(total_samples * 2)
	data.fill(0)

	var pos := 0
	for entry in seq:
		var freq: float = entry[0]
		var beats: int   = int(entry[1])
		var note_samples := int(beats * beat * rate)
		if freq > 0.0:
			var decay := 5.0 + freq * 0.006
			var play_samples := mini(note_samples, int((beats * beat - 0.018) * rate))
			for s in play_samples:
				if pos + s >= total_samples:
					break
				var t := float(s) / float(rate)
				var env := exp(-t * decay)
				var v := sin(TAU * freq * t) * env * 0.32
				v += sin(TAU * freq * 2.0 * t) * env * 0.09
				var iv := int(clampf(v, -1.0, 1.0) * 32767.0)
				var si := (pos + s) * 2
				data[si]     = iv & 0xFF
				data[si + 1] = (iv >> 8) & 0xFF
		pos += note_samples

	var wav := AudioStreamWAV.new()
	wav.format   = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo   = false
	wav.data     = data
	wav.loop_mode  = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end   = total_samples - 1
	return wav


# Low-frequency engine idle loop. Period = 150 samples at 11025 Hz â†’ 73.5 Hz
# fundamental. All harmonics used (Ã—0.5, Ã—1, Ã—2, Ã—3) divide evenly into the
# 1500-sample loop so there is no click at the loop point.
func _make_engine_sound() -> AudioStreamWAV:
	var rate    := 11025
	var period  := 150                  # samples per fundamental cycle
	var fund    := float(rate) / float(period)   # 73.5 Hz
	var num_samples := period * 10      # 10 cycles = 1500 samples

	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for s in num_samples:
		var t := float(s) / float(rate)
		var v := sin(TAU * fund * t)       * 0.28
		v += sin(TAU * fund * 2.0 * t)    * 0.12
		v += sin(TAU * fund * 3.0 * t)    * 0.07
		v += sin(TAU * fund * 0.5 * t)    * 0.06
		var iv := int(clampf(v, -1.0, 1.0) * 32767.0)
		data[s * 2]     = iv & 0xFF
		data[s * 2 + 1] = (iv >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.format   = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo   = false
	wav.data     = data
	wav.loop_mode  = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end   = num_samples - 1
	return wav


# Spawn a CanvasLayer title card ("matsubara kun") and start fading it in after
# 2 seconds. Returns immediately; the fade runs as a fire-and-forget coroutine.
func _show_intro_title() -> void:
	_intro_title = CanvasLayer.new()
	add_child(_intro_title)
	var lbl := Label.new()
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 128)
	lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	lbl.add_theme_constant_override("outline_size", 28)
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.05))
	lbl.text = "Matsubara kun"
	lbl.modulate.a = 0.0
	_intro_title.add_child(lbl)
	_fade_in_title_async(lbl)


func _fade_in_title_async(lbl: Label) -> void:
	await get_tree().create_timer(2.0).timeout
	if not is_instance_valid(lbl):
		return
	var t := create_tween()
	t.set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "modulate:a", 1.0, 1.5)
	await t.finished
	# Hold for 3 seconds then fade out automatically.
	await get_tree().create_timer(3.0).timeout
	if not is_instance_valid(lbl):
		return
	var t2 := create_tween()
	t2.tween_property(lbl, "modulate:a", 0.0, 1.0)


func _fade_out_intro_title() -> void:
	if _intro_title == null:
		return
	var layer := _intro_title
	_intro_title = null
	if layer.get_child_count() == 0:
		layer.queue_free()
		return
	var lbl := layer.get_child(0)
	var t := create_tween()
	t.tween_property(lbl, "modulate:a", 0.0, 0.8)
	t.tween_callback(layer.queue_free)


# Procedural city bus for the opening cinematic.
# Oriented east-west (long axis = X). South face (local +Z) faces the camera.
# Windows are semi-transparent so the park and player show through.
func _build_intro_bus() -> Node3D:
	var b := Node3D.new()
	add_child(b)

	var green  := Color(0.14, 0.48, 0.22)
	var dark_g := Color(0.08, 0.30, 0.13)
	var black  := Color(0.12, 0.12, 0.14)
	var chrome := Color(0.80, 0.80, 0.82)

	# == Structural frame (no solid south or north wall â€” park visible through) ==
	# Roof slab
	_box(b, Vector3(8.0, 0.22, 2.5), Vector3(0, 2.62, 0), dark_g)
	# Roof-mounted AC unit
	_box(b, Vector3(1.8, 0.30, 0.9), Vector3(-1.0, 2.90, -0.2), dark_g)
	# Floor / underbody slab
	_box(b, Vector3(8.0, 0.32, 2.5), Vector3(0, 0.56, 0), green)
	# East end wall + dark destination-sign band above
	_box(b, Vector3(0.32, 2.06, 2.5), Vector3(4.16, 1.39, 0), green)
	_box(b, Vector3(0.32, 0.38, 2.5), Vector3(4.16, 2.61, 0), dark_g)
	# West end wall
	_box(b, Vector3(0.32, 2.44, 2.5), Vector3(-4.16, 1.58, 0), green)

	# == South face: lower body strip (tall), three pillars, small windows, header ==
	# Windows: 1.0 Ã— 0.80, centre y=1.75  â†’  bottom y=1.35, top y=2.15
	# Lower strip: floor top (y=0.72) to window bottom (y=1.35), h=0.63, cy=1.035
	_box(b, Vector3(7.4, 0.63, 0.14), Vector3(0, 1.035, 1.26), green)
	# Upper header: window top (y=2.15) to roof bottom (y=2.51), h=0.36, cy=2.33
	_box(b, Vector3(7.4, 0.36, 0.14), Vector3(0, 2.33, 1.26), dark_g)
	# Three vertical A-pillars (match window height)
	for px in [-2.0, 0.0, 2.0]:
		_box(b, Vector3(0.18, 0.80, 0.14), Vector3(px, 1.75, 1.27), black)
	# Four small window panes â€” semi-transparent so park and player show through
	var win_mat := StandardMaterial3D.new()
	win_mat.albedo_color = Color(0.38, 0.58, 0.82, 0.22)
	win_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	win_mat.metallic = 0.25
	win_mat.roughness = 0.12
	for wx in [-3.0, -1.0, 1.0, 3.0]:
		_box_mat(b, Vector3(1.0, 0.80, 0.08), Vector3(wx, 1.75, 1.27), win_mat)
	# Bumper along south face base
	_box(b, Vector3(7.6, 0.20, 0.22), Vector3(0, 0.38, 1.30), chrome)
	# White decorative stripe just below windows
	_box(b, Vector3(7.4, 0.10, 0.12), Vector3(0, 1.30, 1.27), Color(0.92, 0.92, 0.92))

	# == North face (park-facing): mirrors south face so bus is solid from all angles ==
	_box(b, Vector3(7.4, 0.63, 0.14), Vector3(0, 1.035, -1.26), green)
	_box(b, Vector3(7.4, 0.36, 0.14), Vector3(0, 2.33, -1.26), dark_g)
	for px in [-2.0, 0.0, 2.0]:
		_box(b, Vector3(0.18, 0.80, 0.14), Vector3(px, 1.75, -1.27), black)
	for wx in [-3.0, -1.0, 1.0, 3.0]:
		_box_mat(b, Vector3(1.0, 0.80, 0.08), Vector3(wx, 1.75, -1.27), win_mat)
	_box(b, Vector3(7.6, 0.20, 0.22), Vector3(0, 0.38, -1.30), chrome)
	_box(b, Vector3(7.4, 0.10, 0.12), Vector3(0, 1.30, -1.27), Color(0.92, 0.92, 0.92))

	# == Wheels (long axis = X, so axle runs along Z; rotation.x = PI/2) ==
	for wv in [Vector3(-3.1, 0.44, -0.92), Vector3(3.1, 0.44, -0.92),
			   Vector3(-3.1, 0.44,  0.92), Vector3(3.1, 0.44,  0.92)]:
		var w := _cylinder(b, 0.44, 0.32, wv, black)
		w.rotation.x = PI * 0.5

	# == Passengers â€” one per window, seated, visible through south glass ==
	var shirts := [Color(0.20, 0.25, 0.62), Color(0.70, 0.28, 0.22),
				   Color(0.26, 0.58, 0.30), Color(0.58, 0.34, 0.64)]
	var skins  := [Color(0.90, 0.75, 0.60), Color(0.55, 0.42, 0.32),
				   Color(0.88, 0.72, 0.58), Color(0.40, 0.30, 0.25)]
	for i in range(4):
		var px: float = [-3.0, -1.0, 1.0, 3.0][i]
		_box(b, Vector3(0.46, 0.56, 0.24), Vector3(px, 1.15, 0.0), shirts[i])
		_sphere(b, 0.19, Vector3(px, 1.82, 0.0), skins[i])

	return b


# Place at least one talkable NPC on every street (each grid line), most of them
# patrolling a short stretch of that street's sidewalk. Each gives directions
# from its own position; they share the one microphone.
func _spawn_npcs(dialogue: DialogueManager, camera_focus: CameraFocusManager,
		player: PlayerController, goal: GoalManager,
		goals: Dictionary, goal_names: Array, speech: SpeechInput) -> void:
	var palette := [
		[Color(0.80, 0.30, 0.25), Color(0.20, 0.20, 0.25), Color(0.10, 0.08, 0.05)],
		[Color(0.20, 0.45, 0.65), Color(0.30, 0.28, 0.25), Color(0.35, 0.22, 0.10)],
		[Color(0.30, 0.55, 0.35), Color(0.20, 0.20, 0.22), Color(0.15, 0.12, 0.08)],
		[Color(0.70, 0.60, 0.20), Color(0.25, 0.25, 0.30), Color(0.45, 0.30, 0.18)],
		[Color(0.55, 0.35, 0.60), Color(0.22, 0.22, 0.26), Color(0.10, 0.08, 0.06)],
		[Color(0.85, 0.55, 0.25), Color(0.28, 0.26, 0.24), Color(0.12, 0.10, 0.07)],
	]
	var k := 0
	var nolan_k := 7   # which inner-town NPC is named Nolan
	# 3 families Ã— 3 subtle pitches = 9 distinct voices. Range kept narrow (0.93-1.07)
	# so all voices remain fully intelligible. "piper" falls back to assets/voice/*.wav.
	var voice_combos: Array = [
		["female", 0.93], ["female", 1.00], ["female", 1.07],
		["male",   0.93], ["male",   1.00], ["male",   1.07],
		["piper",  0.93], ["piper",  1.00], ["piper",  1.07],
	]
	# One NPC in front of every block (on the inner-street sidewalk, where the
	# block's frontage is) so at least one townsperson is within visual range of
	# every building. Each patrols a short stretch of that sidewalk.
	for j in BLOCK_CENTERS.size():
		for i in BLOCK_CENTERS.size():
			var cx: float = BLOCK_CENTERS[i]
			var cz: float = BLOCK_CENTERS[j]
			if cx == 0.0 and cz == 0.0:
				continue   # the Park itself; covered by the spawn greeter below
			var npos: Vector3
			var p: PackedVector3Array
			# 0 = front centered, 1 = front offset, 2 = back sidewalk
			var variant: int = k % 3
			# Alternate offset direction so NPCs spread across both ends of a street.
			var off_sign: float = 1.0 if (i + j) % 2 == 0 else -1.0
			if absf(cx) >= absf(cz):
				var sx_f: float = cx - signf(cx) * (HALF_BLOCK - SW_OFF)  # front
				var sx_b: float = cx + signf(cx) * (HALF_BLOCK - SW_OFF)  # back
				match variant:
					0:  # front sidewalk, centered on block
						npos = Vector3(sx_f, 0, cz)
						p = PackedVector3Array([Vector3(sx_f, 0, cz - 12), Vector3(sx_f, 0, cz + 12)])
					1:  # front sidewalk, further along the street
						var oz: float = off_sign * 15.0
						npos = Vector3(sx_f, 0, cz + oz)
						p = PackedVector3Array([Vector3(sx_f, 0, cz + oz - 9), Vector3(sx_f, 0, cz + oz + 9)])
					_:  # back sidewalk (opposite face of the block)
						npos = Vector3(sx_b, 0, cz)
						p = PackedVector3Array([Vector3(sx_b, 0, cz - 12), Vector3(sx_b, 0, cz + 12)])
			else:
				var sz_f: float = cz - signf(cz) * (HALF_BLOCK - SW_OFF)
				var sz_b: float = cz + signf(cz) * (HALF_BLOCK - SW_OFF)
				match variant:
					0:
						npos = Vector3(cx, 0, sz_f)
						p = PackedVector3Array([Vector3(cx - 12, 0, sz_f), Vector3(cx + 12, 0, sz_f)])
					1:
						var ox: float = off_sign * 15.0
						npos = Vector3(cx + ox, 0, sz_f)
						p = PackedVector3Array([Vector3(cx + ox - 9, 0, sz_f), Vector3(cx + ox + 9, 0, sz_f)])
					_:
						npos = Vector3(cx, 0, sz_b)
						p = PackedVector3Array([Vector3(cx - 12, 0, sz_b), Vector3(cx + 12, 0, sz_b)])
			var nn := "Nolan" if k == nolan_k else "Townsperson"
			var nrng := RandomNumberGenerator.new()
			nrng.seed = k + 4999
			var is_female: bool = (k != nolan_k) and (nrng.randi() % 2 == 0)
			var npc_heights: Array = [0.88, 1.0, 1.12]
			var hs: float = npc_heights[nrng.randi() % 3]
			var voice_idx: int = (k % 3) if is_female else (3 + k % 6)
			var combo: Array = voice_combos[voice_idx]
			_make_npc(npos, p, palette[k % palette.size()],
					dialogue, camera_focus, player, goal, goals, goal_names, speech,
					nn, combo[1], 0.88, k, combo[0], is_female, hs)
			k += 1
	# One NPC on each outer boundary sidewalk.
	var outer_z := 135.0 + SW_OFF   # south/north outer sidewalk z offset
	var outer_x := 135.0 + SW_OFF   # east/west outer sidewalk x offset
	# North: NPC on the train station platform (z=-143.5, y=0.85 = platform surface).
	# The outer sidewalk at z=-140.6 sits inside the platform, so patrol there instead.
	var plat_y := 0.85
	var plat_z := -143.5
	var _pr := RandomNumberGenerator.new(); _pr.seed = k + 4999
	var _pf: bool = _pr.randi() % 2 == 0
	var _ph: float = ([0.88, 1.0, 1.12] as Array)[_pr.randi() % 3]
	var _pvc: Array = voice_combos[(k % 3) if _pf else (3 + k % 6)]
	_make_npc(Vector3(0, plat_y, plat_z),
			PackedVector3Array([Vector3(-8, plat_y, plat_z), Vector3(8, plat_y, plat_z)]),
			palette[k % palette.size()],
			dialogue, camera_focus, player, goal, goals, goal_names, speech,
			"Townsperson", _pvc[1], 0.88, k, _pvc[0], _pf, _ph)
	k += 1
	# South outer sidewalk: patrol in the gap between the two center beach benches
	# (benches at x=-20 and x=20 â€” NPC bypasses collision, so keep x in [-14, 14]).
	var _sr := RandomNumberGenerator.new(); _sr.seed = k + 4999
	var _sf: bool = _sr.randi() % 2 == 0
	var _sh: float = ([0.88, 1.0, 1.12] as Array)[_sr.randi() % 3]
	var _svc: Array = voice_combos[(k % 3) if _sf else (3 + k % 6)]
	_make_npc(Vector3(0, 0, outer_z),
			PackedVector3Array([Vector3(-14, 0, outer_z), Vector3(14, 0, outer_z)]),
			palette[k % palette.size()],
			dialogue, camera_focus, player, goal, goals, goal_names, speech,
			"Townsperson", _svc[1], 0.88, k, _svc[0], _sf, _sh)
	k += 1
	# West outer sidewalk (patrols north-south at x = -outer_x)
	var _wr := RandomNumberGenerator.new(); _wr.seed = k + 4999
	var _wf: bool = _wr.randi() % 2 == 0
	var _wh: float = ([0.88, 1.0, 1.12] as Array)[_wr.randi() % 3]
	var _wvc: Array = voice_combos[(k % 3) if _wf else (3 + k % 6)]
	_make_npc(Vector3(-outer_x, 0, 0),
			PackedVector3Array([Vector3(-outer_x, 0, -40), Vector3(-outer_x, 0, 40)]),
			palette[k % palette.size()],
			dialogue, camera_focus, player, goal, goals, goal_names, speech,
			"Townsperson", _wvc[1], 0.88, k, _wvc[0], _wf, _wh)
	k += 1
	# East outer sidewalk (patrols north-south at x = +outer_x)
	var _er := RandomNumberGenerator.new(); _er.seed = k + 4999
	var _ef: bool = _er.randi() % 2 == 0
	var _enh: float = ([0.88, 1.0, 1.12] as Array)[_er.randi() % 3]
	var _evc: Array = voice_combos[(k % 3) if _ef else (3 + k % 6)]
	_make_npc(Vector3(outer_x, 0, 0),
			PackedVector3Array([Vector3(outer_x, 0, -40), Vector3(outer_x, 0, 40)]),
			palette[k % palette.size()],
			dialogue, camera_focus, player, goal, goals, goal_names, speech,
			"Townsperson", _evc[1], 0.88, k, _evc[0], _ef, _enh)


func _make_npc(pos: Vector3, p: PackedVector3Array, c: Array,
		dialogue: DialogueManager, camera_focus: CameraFocusManager,
		player: PlayerController, goal: GoalManager,
		goals: Dictionary, goal_names: Array, speech: SpeechInput,
		npc_name: String = "Townsperson",
		voice_pitch: float = 1.0, voice_rate: float = 0.88,
		voice_index: int = 0, voice_family: String = "female",
		female: bool = false, height_scale: float = 1.0) -> NPCInteraction:
	var npc := NPCInteraction.new()
	npc.shirt_color = c[0]
	npc.pants_color = c[1]
	npc.hair_color = c[2]
	npc.female = female
	npc.height_scale = height_scale
	npc.speed = 1.8
	npc.path = p
	npc.position = pos
	npc.npc_name = npc_name
	npc.voice_pitch = voice_pitch
	npc.voice_rate = voice_rate
	npc.voice_index = voice_index
	npc.voice_family = voice_family
	add_child(npc)
	npc.setup(dialogue, camera_focus, player, goal, goals, goal_names, speech)
	return npc


# -----------------------------------------------------------------------------
# Wall posters: one per advertised place, each mounted on the road-facing wall of
# a DIFFERENT goal building chosen to be as far as possible from the real place.
# -----------------------------------------------------------------------------
func _spawn_posters(goals: Dictionary, player: PlayerController, layout: Array, goal: GoalManager) -> void:
	# Where the NPCs stand / patrol â€” posters should be kept clear of these so
	# reading an ad never clashes with talking to a townsperson.
	var npc_points: Array = []
	for child in get_children():
		if child is NPCInteraction:
			npc_points.append((child as NPCInteraction).global_position)
			for pt in (child as NPCInteraction).path:
				npc_points.append(pt)

	# Footprints of every building, used to find which wall faces open space.
	var all_fps := _building_footprints(layout)

	# Candidate host buildings: solid-walled grid goal buildings. Exclude the
	# off-grid anchors, the Park, and open structures (gas station, pool) that
	# have no real wall to mount a poster on.
	var hosts: Array = []
	for name in goals.keys():
		if name in ["Train Station", "Beach", "Shopping Mall", "Park"]:
			continue
		if not GOAL_DEFS.has(name):
			continue
		if GOAL_DEFS[name].style in ["gas", "pool"]:
			continue
		var node: Node3D = goals[name]
		var size: Vector3 = GOAL_DEFS[name].size
		var fp := _footprint({"pos": node.global_position, "size": size})

		# Mount on a SIDE wall (perpendicular to the door/front), and of the two
		# sides choose the one facing the most open space â€” i.e. the cross-street,
		# not the narrow alley between buildings.
		var sx: Vector3 = node.global_transform.basis.x
		sx.y = 0.0
		if absf(sx.x) >= absf(sx.z):
			sx = Vector3(signf(sx.x), 0.0, 0.0)
		else:
			sx = Vector3(0.0, 0.0, signf(sx.z))

		# Prefer the side wall that faces the nearest road intersection (block
		# corner); use open clearance only to break near-ties.
		var inter := Vector3(_nearest_road(fp.x) - fp.x, 0.0, _nearest_road(fp.z) - fp.z)
		if inter.length() > 0.01:
			inter = inter.normalized()
		var best_wall: Dictionary = {}
		var best_score := -1.0e9
		for d in [sx, -sx]:
			var cx: float
			var cz: float
			var lat: float
			if absf(d.x) > 0.5:
				cx = fp.x + d.x * fp.hx
				cz = fp.z
				lat = fp.hz
			else:
				cx = fp.x
				cz = fp.z + d.z * fp.hz
				lat = fp.hx
			var px: float = cx + d.x * 4.0
			var pz: float = cz + d.z * 4.0
			var clear := 1.0e9
			for o in all_fps:
				if absf(o.x - fp.x) < 0.5 and absf(o.z - fp.z) < 0.5:
					continue
				clear = minf(clear, _box_dist_xz(px, pz, o))
			var score: float = d.dot(inter) + 0.02 * clear
			if score > best_score:
				best_score = score
				best_wall = {"dir": d, "cx": cx, "cz": cz, "lat": lat}

		if best_wall.is_empty():
			continue
		var dir: Vector3 = best_wall.dir
		var ppos := Vector3(best_wall.cx + dir.x * 0.10, 3.2, best_wall.cz + dir.z * 0.10)
		hosts.append({
			"name": name,
			"pos": node.global_position,
			"size": size,
			"fwd": dir,
			"poster_pos": ppos,
			"wall_lat": best_wall.lat,
			"npc_clear": _min_dist_xz(ppos, npc_points),
		})

	# Corner filler buildings: those within ~16 units of a road line in BOTH
	# axes (the Â±SLOT diagonal ring slots). Mid-block ring buildings are ~27
	# units from the road in one axis and won't pass both checks.
	const CORNER_THRESH := 16.0
	for cfg in layout:
		if cfg.get("goal", false):
			continue
		if not cfg.get("style", "") in ["house", "office", "shop"]:
			continue
		var bpos: Vector3 = cfg.pos
		if absf(bpos.x - _nearest_road(bpos.x)) > CORNER_THRESH:
			continue
		if absf(bpos.z - _nearest_road(bpos.z)) > CORNER_THRESH:
			continue
		var bsize: Vector3 = cfg.size
		var bfp := _footprint(cfg)
		var binter := Vector3(_nearest_road(bfp.x) - bfp.x, 0.0, _nearest_road(bfp.z) - bfp.z)
		if binter.length() > 0.01:
			binter = binter.normalized()
		var cbest_wall: Dictionary = {}
		var cbest_score := -1.0e9
		# Derive the true side-wall axis from _clear_facing â€” filler buildings can
		# face any cardinal direction, so hard-coded Â±X is wrong for rotated ones.
		var filler_yaw := _clear_facing(bfp, all_fps)
		# _footprint() uses _park_or_street_facing which can differ from _clear_facing,
		# so recompute half-extents from the actual filler rotation to avoid placing
		# the poster inside the wall when the two yaws disagree.
		var ff_x: bool = absf(filler_yaw) > 0.01 and absf(absf(filler_yaw) - PI) > 0.01
		var fhx: float = (bsize.z if ff_x else bsize.x) * 0.5
		var fhz: float = (bsize.x if ff_x else bsize.z) * 0.5
		var bsx := Vector3(cos(filler_yaw), 0.0, -sin(filler_yaw))
		if absf(bsx.x) >= absf(bsx.z):
			bsx = Vector3(signf(bsx.x), 0.0, 0.0)
		else:
			bsx = Vector3(0.0, 0.0, signf(bsx.z))
		for d in [bsx, -bsx]:
			var dcx: float
			var dcz: float
			var dlat: float
			if absf(d.x) > 0.5:
				dcx = bfp.x + d.x * fhx
				dcz = bfp.z
				dlat = fhz
			else:
				dcx = bfp.x
				dcz = bfp.z + d.z * fhz
				dlat = fhx
			var dpx: float = dcx + d.x * 4.0
			var dpz: float = dcz + d.z * 4.0
			var dclear := 1.0e9
			for o in all_fps:
				if absf(o.x - bfp.x) < 0.5 and absf(o.z - bfp.z) < 0.5:
					continue
				dclear = minf(dclear, _box_dist_xz(dpx, dpz, o))
			var dscore: float = d.dot(binter) + 0.02 * dclear
			if dscore > cbest_score:
				cbest_score = dscore
				cbest_wall = {"dir": d, "cx": dcx, "cz": dcz, "lat": dlat}
		if cbest_wall.is_empty():
			continue
		var cdir: Vector3 = cbest_wall.dir
		var cppos := Vector3(cbest_wall.cx + cdir.x * 0.10, 3.2, cbest_wall.cz + cdir.z * 0.10)
		hosts.append({
			"name": str(bpos),
			"pos": bpos,
			"size": bsize,
			"fwd": cdir,
			"poster_pos": cppos,
			"wall_lat": cbest_wall.lat,
			"npc_clear": _min_dist_xz(cppos, npc_points),
		})

	const MIN_NPC_DIST := 8.0
	var used: Dictionary = {}
	# Place two copies of each ad on different host buildings.
	for _copy in 2:
		for place in POSTER_ADS.keys():
			if not goals.has(place):
				continue
			# Pick a random host, preferring NPC-clear walls; fall back to any host.
			var best: Dictionary = _pick_host(hosts, used, MIN_NPC_DIST)
			if best.is_empty():
				best = _pick_host(hosts, used, 0.0)
			if best.is_empty():
				continue
			used[best.name] = true
			_mount_poster(best, place, player, goal)

	_bake_poster_visuals()


func _pick_host(hosts: Array, used: Dictionary, min_npc_dist: float) -> Dictionary:
	var valid: Array = []
	for h in hosts:
		if used.has(h.name):
			continue
		if h.npc_clear < min_npc_dist:
			continue
		valid.append(h)
	if valid.is_empty():
		return {}
	return valid[randi() % valid.size()]


func _nearest_road(v: float) -> float:
	# Road lines run along the block boundaries (and the outer ring).
	var roads := [-135.0, -81.0, -27.0, 27.0, 81.0, 135.0]
	var best: float = roads[0]
	for r in roads:
		if absf(r - v) < absf(best - v):
			best = r
	return best


func _box_dist_xz(px: float, pz: float, fp: Dictionary) -> float:
	var dx: float = maxf(absf(px - fp.x) - fp.hx, 0.0)
	var dz: float = maxf(absf(pz - fp.z) - fp.hz, 0.0)
	return sqrt(dx * dx + dz * dz)


func _min_dist_xz(p: Vector3, points: Array) -> float:
	var best := 1e9
	for q in points:
		var dx: float = p.x - (q as Vector3).x
		var dz: float = p.z - (q as Vector3).z
		var d := sqrt(dx * dx + dz * dz)
		if d < best:
			best = d
	return best


func _mount_poster(host: Dictionary, place: String, player: PlayerController, goal: GoalManager) -> void:
	var poster := Poster.new()
	poster.place_name = place
	poster.ad_line = POSTER_ADS[place][0]
	poster.hours_line = POSTER_ADS[place][1]
	add_child(poster)
	# Random spot on the wall: slide along the wall and vary the height a little,
	# keeping the board fully on the wall.
	var size: Vector3 = host.size
	var fwd: Vector3 = host.fwd
	var along := Vector3(fwd.z, 0.0, -fwd.x)   # horizontal, perpendicular to fwd
	var max_off: float = maxf(0.0, float(host.wall_lat) - 1.0)
	var h_off: float = randf_range(-max_off, max_off)
	var pos: Vector3 = (host.poster_pos as Vector3) + along * h_off
	pos.y = clampf(randf_range(2.6, 3.6), 1.3, size.y - 1.3)
	poster.global_position = pos
	# Face outward: Poster's board faces local -Z, so -Z must point along fwd.
	poster.look_at(pos + host.fwd, Vector3.UP)
	poster.setup(_dialogue, player, goal)


func _spawn_welcome_sign(player: PlayerController, goal: GoalManager) -> void:
	var sign := WelcomeSign.new()
	sign.place_names = [
		"Library", "Hospital", "City Hall",
		"Police Station", "Fire Station", "Post Office",
	]
	sign.position = Vector3(5.0, 0.0, 20.0)
	add_child(sign)
	sign.setup(_dialogue, player, goal)


# -----------------------------------------------------------------------------
# Poster visual baking: sweep every MeshInstance3D out of all Poster children,
# merge them into one static mesh (3 surfaces: frame / board / lines), then
# free the originals.  All posters share three material instances (set up in
# Poster._build_visuals) so the SurfaceTool merges all geometry per-material.
# -----------------------------------------------------------------------------
func _bake_poster_visuals() -> void:
	var tools: Dictionary = {}
	var order: Array = []
	var to_free: Array = []
	for child in get_children():
		if not (child is Poster):
			continue
		var meshes: Array = []
		_collect_mesh_instances(child, meshes)
		for mi in meshes:
			var mat: Material = mi.material_override
			var mesh: Mesh = mi.mesh
			if mat == null or mesh == null:
				continue
			if not tools.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[mat] = st
				order.append(mat)
			tools[mat].append_from(mesh, 0, mi.global_transform)
			to_free.append(mi)
	for mi in to_free:
		mi.queue_free()
	if order.is_empty():
		return
	var arr := ArrayMesh.new()
	for mat in order:
		(tools[mat] as SurfaceTool).commit(arr)
		arr.surface_set_material(arr.get_surface_count() - 1, mat)
	var inst := MeshInstance3D.new()
	inst.name = "PosterMesh"
	inst.mesh = arr
	add_child(inst)


# -----------------------------------------------------------------------------
# Static-geometry baking: collect every MeshInstance3D under Roads + Town and
# merge them into a single MeshInstance3D with one surface per material. The
# building collision boxes (CollisionShape3D) and name signs (Label3D) are left
# untouched, and the player/NPC (under their own nodes) are not baked.
# -----------------------------------------------------------------------------
func _bake_static_meshes() -> void:
	var tools := {}        # Material -> SurfaceTool
	var order := []        # keep a stable material order
	for root_name in ["Roads", "Town", "Terrain"]:
		var root := get_node_or_null(NodePath(root_name))
		if root == null:
			continue
		var meshes: Array = []
		_collect_mesh_instances(root, meshes)
		for mi in meshes:
			var mat: Material = mi.material_override
			var mesh: Mesh = mi.mesh
			if mat == null or mesh == null:
				continue
			if not tools.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[mat] = st
				order.append(mat)
			tools[mat].append_from(mesh, 0, mi.global_transform)
			mi.queue_free()

	var arr := ArrayMesh.new()
	for mat in order:
		tools[mat].commit(arr)
		arr.surface_set_material(arr.get_surface_count() - 1, mat)
	var inst := MeshInstance3D.new()
	inst.name = "WorldMesh"
	inst.mesh = arr
	add_child(inst)


func _collect_mesh_instances(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is MeshInstance3D:
			out.append(c)
		else:
			_collect_mesh_instances(c, out)


# Generates a 128Ã—128 seamlessly-tiling running-bond brick pattern as an
# ImageTexture. Bricks are warm-tinted near-white; mortar is a cooler mid-grey.
# When applied with albedo_color, the colour tints both brick and mortar so
# every building keeps its identifying hue.
func _make_brick_texture(mortar: Color = Color(0.52, 0.50, 0.48)) -> ImageTexture:
	const SZ  := 128
	const BH  := 16   # brick row height  (SZ / 8 rows)
	const BW  := 32   # brick column width (SZ / 4 cols)
	const MRT := 4    # mortar thickness in pixels (bold for Lego look)
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGB8)
	for py in SZ:
		var row   := py / BH
		var in_hm := (py % BH) < MRT
		var xsh   := (BW / 2) if (row % 2 == 0) else 0
		for px in SZ:
			var bx    := (px + xsh) % SZ
			var in_vm := (bx % BW) < MRT
			if in_hm or in_vm:
				img.set_pixel(px, py, mortar)
			else:
				var bid   := float((bx / BW) + row * 4)
				var rng_v := absf(fmod(sin(bid * 127.1 + 43.758) * 43758.5, 1.0))
				var v     := 0.90 + rng_v * 0.10
				img.set_pixel(px, py, Color(v, v * 0.97, v * 0.94))
	return ImageTexture.create_from_image(img)


# 128Ã—128 horizontal lap-siding pattern. Each board has a cast-shadow at the
# top edge and brightens toward the bottom, plus subtle per-board variation.
func _make_siding_texture() -> ImageTexture:
	const SZ      := 128
	const BOARDS  := 8     # 8 boards per tile â†’ 16 px tall each
	const BH      := SZ / BOARDS
	const SHADOW  := 3     # shadow depth in pixels at the top of each board
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGB8)
	for py in SZ:
		var board  := py / BH
		var fy     := float(py % BH) / float(BH)    # 0=top edge, 1=bottom edge
		var shadow := clampf(1.0 - float(py % BH) / float(SHADOW), 0.0, 1.0)
		# Base brightness: darkens under shadow, otherwise rises toward bottom
		var base   := lerpf(0.92 + fy * 0.06, 0.86, shadow)
		# Per-board subtle variation
		var bid    := float(board)
		base += absf(fmod(sin(bid * 73.3 + 13.7) * 43758.5, 1.0)) * 0.02 - 0.01
		base = clampf(base, 0.80, 1.0)
		for px in SZ:
			# Faint horizontal wood grain
			var grain := absf(fmod(sin(float(px) * 0.28 + bid * 17.1) * 127.1, 1.0)) * 0.02 - 0.01
			var v     := clampf(base + grain, 0.35, 1.0)
			img.set_pixel(px, py, Color(v * 1.03, v * 0.98, v * 0.91))
	return ImageTexture.create_from_image(img)


# Dark aggregate grain for asphalt roads, with sparse faint cracks.
func _make_asphalt_tex() -> ImageTexture:
	const SZ := 128
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGB8)
	for py in SZ:
		for px in SZ:
			var n1 := absf(fmod(sin(float(px) * 127.1 + float(py) * 311.7) * 43758.5, 1.0))
			var n2 := absf(fmod(sin(float(px) * 43.3  + float(py) * 89.7  + 7.3) * 18492.3, 1.0))
			var n3 := absf(fmod(sin(float(px) * 7.1   + float(py) * 13.9  + 31.2) * 7634.2, 1.0))
			var base := 0.78 + n1 * 0.10 + n3 * 0.06   # mid-grey aggregate, range 0.78â€“0.94
			# Sparse darker crack pixels: ~4 % of surface
			var crack := n2 < 0.04
			var v := base * (0.55 if crack else 1.0)
			v = clampf(v, 0.0, 1.0)
			# Asphalt is slightly cool/blue-grey
			img.set_pixel(px, py, Color(v * 0.97, v * 0.97, v))
	return ImageTexture.create_from_image(img)


# Light grey gravel/tar-paper for flat roofs.
func _make_gravel_tex() -> ImageTexture:
	const SZ := 128
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGB8)
	for py in SZ:
		for px in SZ:
			var n1 := absf(fmod(sin(float(px) * 127.1 + float(py) * 311.7) * 43758.5, 1.0))
			var n2 := absf(fmod(sin(float(px) * 31.7  + float(py) * 53.3  + 17.9) * 18492.3, 1.0))
			var n3 := absf(fmod(sin(float(px) * 5.3   + float(py) * 11.7  + 43.1) * 7634.2, 1.0))
			# Larger-grain pebble feel: medium freq dominant
			var v := 0.72 + n2 * 0.14 + n1 * 0.06 - n3 * 0.08
			# Occasional darker gap between pebbles
			var gap := n1 < 0.06
			v = v * (0.70 if gap else 1.0)
			v = clampf(v, 0.0, 1.0)
			img.set_pixel(px, py, Color(v, v * 0.99, v * 0.98))
	return ImageTexture.create_from_image(img)


# Overlapping sine-wave ripples for pool and fountain water surfaces.
func _make_ripple_tex() -> ImageTexture:
	const SZ := 128
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGB8)
	for py in SZ:
		for px in SZ:
			var u := float(px) * 0.22
			var v2 := float(py) * 0.22
			var cx := float(px) - SZ * 0.5
			var cy := float(py) - SZ * 0.5
			var r  := sqrt(cx * cx + cy * cy) * 0.22
			var n1 := sin(u) * sin(v2)
			var n2 := sin(u + v2)
			var n3 := sin(r)
			var raw := (n1 * 0.35 + n2 * 0.35 + n3 * 0.30)   # range ~-1 to 1
			var v   := 0.82 + raw * 0.12                        # range 0.70 â€“ 0.94
			v = clampf(v, 0.0, 1.0)
			# Slight blue tint on highlights
			img.set_pixel(px, py, Color(v * 0.93, v * 0.97, v))
	return ImageTexture.create_from_image(img)


# Fine stucco/pebble-dash speckle for plain building walls.
# Base near-white with occasional darker aggregate flecks (~12 % of pixels).
func _make_speckle_tex() -> ImageTexture:
	const SZ := 128
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGB8)
	for py in SZ:
		for px in SZ:
			var n1 := absf(fmod(sin(float(px) * 127.1 + float(py) * 311.7) * 43758.5, 1.0))
			var n2 := absf(fmod(sin(float(px) * 17.3  + float(py) * 41.9 + 113.5) * 18492.3, 1.0))
			var n3 := absf(fmod(sin(float(px) * 3.7   + float(py) * 9.1  + 57.3) * 7634.2, 1.0))
			var base := 0.92 + n1 * 0.06 + n3 * 0.02
			var v := base * (0.78 if n2 > 0.88 else 1.0)
			v = clampf(v, 0.0, 1.0)
			img.set_pixel(px, py, Color(v, v * 0.99, v * 0.97))
	return ImageTexture.create_from_image(img)


# Running-bond roof shingles. Rows offset by half a tile; top 2 px of each
# row are darker (shadow from the overlapping course above).
func _make_shingle_tex() -> ImageTexture:
	const SZ := 128
	const SH := 14   # shingle row height
	const SW := 22   # shingle width
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGB8)
	for py in SZ:
		var row   := py / SH
		var in_sh := (py % SH) < 2   # shadow band at top of each course
		var xsh   := (SW / 2) if (row % 2 == 0) else 0
		for px in SZ:
			var bx    := (px + xsh) % SZ
			var in_gp := (bx % SW) == SW - 1   # 1-px gap between tiles
			var bid   := float((bx / SW) + row * 6)
			var rng_v := absf(fmod(sin(bid * 127.1 + 43.758) * 43758.5, 1.0))
			var v: float
			if in_gp:
				v = 0.58
			elif in_sh:
				v = 0.62 + rng_v * 0.06
			else:
				v = 0.82 + rng_v * 0.12
			img.set_pixel(px, py, Color(v, v * 0.97, v * 0.93))
	return ImageTexture.create_from_image(img)


# Concrete sidewalk panels with expansion joint lines.
# 128Ã—128 with 2Ã—2 panels (64 px each); joint lines are 3 px wide and darker.
func _make_concrete_tex() -> ImageTexture:
	const SZ    := 128
	const PANEL := 64
	const JOINT := 6
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGB8)
	for py in SZ:
		var in_hj := (py % PANEL) < JOINT
		for px in SZ:
			var in_vj := (px % PANEL) < JOINT
			if in_hj or in_vj:
				img.set_pixel(px, py, Color(0.56, 0.56, 0.58))
			else:
				var nx   := float(px) / 32.0
				var ny   := float(py) / 32.0
				var n    := absf(fmod(sin(nx * 12.99 + ny * 78.23) * 43758.5, 1.0)) * 0.08 - 0.04
				var v    := clampf(0.92 + n, 0.80, 1.0)
				img.set_pixel(px, py, Color(v, v, v * 1.01))
	return ImageTexture.create_from_image(img)


# Large-blotch grass for low-poly Lego look â€” very low frequency gives bold patches.
func _make_grass_tex() -> ImageTexture:
	const SZ := 128
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGB8)
	for py in SZ:
		for px in SZ:
			var nx := float(px) / 128.0
			var ny := float(py) / 128.0
			var n1 := absf(fmod(sin(nx * 1.5 + ny * 2.3) * 43758.5, 1.0))
			var n2 := absf(fmod(sin(nx * 0.9 + ny * 1.4 + 1.3) * 18492.3, 1.0))
			var patch := n1 * 0.70 + n2 * 0.30
			var v     := lerpf(0.72, 1.05, patch)
			v = clampf(v, 0.0, 1.0)
			img.set_pixel(px, py, Color(v * 0.93, v, v * 0.84))
	return ImageTexture.create_from_image(img)


# Vertical bark ridges for tree trunks.
func _make_bark_tex() -> ImageTexture:
	const SZ := 128
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGB8)
	for py in SZ:
		for px in SZ:
			var nx    := float(px) / 128.0
			var ny    := float(py) / 128.0
			var ridge := absf(fmod(sin(nx * 37.4) * 43758.5, 1.0))
			var vvar  := absf(fmod(sin(nx * 19.1 + ny * 13.7) * 43758.5, 1.0))
			var v     := lerpf(0.50, 1.0, ridge * 0.55 + vvar * 0.45)
			img.set_pixel(px, py, Color(v * 1.03, v * 0.95, v * 0.88))
	return ImageTexture.create_from_image(img)


# Mottled dappled-light leaf canopy â€” random bright and dark patches.
func _make_leaf_tex() -> ImageTexture:
	const SZ := 128
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGB8)
	for py in SZ:
		for px in SZ:
			var nx := float(px) / 128.0
			var ny := float(py) / 128.0
			var n1 := absf(fmod(sin(nx * 43.7 + ny * 31.2) * 43758.5, 1.0))
			var n2 := absf(fmod(sin(nx * 89.1 + ny * 17.3) * 43758.5, 1.0))
			var n3 := absf(fmod(sin(nx * 13.6 + ny * 71.8) * 43758.5, 1.0))
			var v  := clampf(lerpf(0.52, 1.08, n1 * 0.5 + n2 * 0.3 + n3 * 0.2), 0.0, 1.0)
			img.set_pixel(px, py, Color(v * 0.90, v, v * 0.80))
	return ImageTexture.create_from_image(img)


# Fine granular sand â€” high-frequency noise, very subtle.
func _make_sand_tex() -> ImageTexture:
	const SZ := 128
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGB8)
	for py in SZ:
		for px in SZ:
			var nx := float(px) / 128.0
			var ny := float(py) / 128.0
			var n1 := absf(fmod(sin(nx * 127.1 + ny * 311.7) * 43758.5, 1.0))
			var n2 := absf(fmod(sin(nx *  53.3 + ny *  89.2) * 43758.5, 1.0))
			var v  := lerpf(0.82, 1.0, n1 * 0.7 + n2 * 0.3)
			img.set_pixel(px, py, Color(v * 1.03, v * 0.99, v * 0.91))
	return ImageTexture.create_from_image(img)


# Applies environment textures to globally-unique material colours by modifying
# the cached StandardMaterial3D instances in place. Both baked (WorldMesh) and
# unbaked (ground plane) geometry share these instances, so one call updates all.
func _apply_terrain_textures() -> void:
	pass


func _tex_mat(color: Color, tex: ImageTexture, scale: Vector3) -> void:
	var mat := _mat_cache.get(color) as StandardMaterial3D
	if mat == null:
		return
	mat.albedo_texture = tex
	mat.uv1_triplanar  = true
	mat.uv1_scale      = scale


# -----------------------------------------------------------------------------
# Input
# -----------------------------------------------------------------------------
func _setup_input() -> void:
	# Keyboard only â€” WASD or the arrow keys. No mouse needed anywhere.
	_add_key_action("move_forward", [KEY_W, KEY_UP])
	_add_key_action("move_back", [KEY_S, KEY_DOWN])
	_add_key_action("turn_left", [KEY_A, KEY_LEFT])
	_add_key_action("turn_right", [KEY_D, KEY_RIGHT])
	_add_key_action("interact", [KEY_E, KEY_SPACE])


func _add_key_action(action_name: String, keys: Array) -> void:
	if InputMap.has_action(action_name):
		InputMap.erase_action(action_name)
	InputMap.add_action(action_name)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action_name, ev)


# -----------------------------------------------------------------------------
# Environment + ground
# -----------------------------------------------------------------------------
func _build_environment() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -35, 0)
	light.shadow_enabled = false   # off for cheap rendering on low-power web devices
	add_child(light)

	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.38, 0.60, 0.96)
	sky_mat.sky_horizon_color = Color(0.82, 0.76, 0.58)
	sky_mat.ground_horizon_color = Color(0.70, 0.64, 0.50)
	sky_mat.sun_angle_max = 28.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	world_env.environment = env
	add_child(world_env)
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	mesh.mesh = plane
	mesh.material_override = _mat(Color(0.40, 0.58, 0.33))
	ground.add_child(mesh)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	col.shape = box
	col.position.y = -0.5
	ground.add_child(col)
	add_child(ground)


# Invisible walls ringing the expanded world (beach south, woods west, mall east,
# train tracks north). Different per-side distances accommodate each new zone.
func _build_bounds() -> void:
	var bounds := StaticBody3D.new()
	bounds.name = "Bounds"
	var h := 12.0
	var bn := 195.0   # north: backup behind train-track barrier
	var bs := 215.0   # south: past the beach sand
	var bw := 230.0   # west: deep into the woods
	var be := 208.0   # east: just past the mall building (prevents groundless escape)
	var wide := bw + be + 10.0
	var tall := bn + bs + 10.0
	for spec in [
		[Vector3(0, h * 0.5, -bn), Vector3(wide, h, 3)],
		[Vector3(0, h * 0.5, bs), Vector3(wide, h, 3)],
		[Vector3(-bw, h * 0.5, 0), Vector3(3, h, tall)],
		[Vector3(be, h * 0.5, 0), Vector3(3, h, tall)],
	]:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = spec[1]
		col.shape = shape
		col.position = spec[0]
		bounds.add_child(col)
	add_child(bounds)

	# East sidewalk barrier â€” continuous invisible wall at x=143 (outer edge of east sidewalk).
	var esb := StaticBody3D.new()
	esb.name = "EastSidewalkBarrier"
	var sc := CollisionShape3D.new()
	var ss := BoxShape3D.new()
	ss.size = Vector3(1.2, h, bn + bs)
	sc.shape = ss
	sc.position = Vector3(143.0, h * 0.5, (-bn + bs) * 0.5)
	esb.add_child(sc)
	add_child(esb)


# Add a vertical collision cylinder to the shared Props body (for a lamppost or
# tree trunk) so the player bumps into it instead of passing through.
func _prop_collider(pos: Vector3, radius: float, height: float) -> void:
	if _props == null:
		return
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	col.position = pos + Vector3(0, height * 0.5, 0)
	_props.add_child(col)


# Add a box collider (for benches etc.) to the shared Props body.
func _prop_box(center: Vector3, size: Vector3, yaw: float) -> void:
	if _props == null:
		return
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = center
	col.rotation.y = yaw
	_props.add_child(col)


# -----------------------------------------------------------------------------
# Roads: full grid of asphalt, with sidewalks that run along the streets but
# STOP at each intersection (replaced there by crosswalks), lampposts out on the
# sidewalks (never on the road), and stop signs at the downtown intersections.
# -----------------------------------------------------------------------------
func _build_roads() -> void:
	var roads := Node3D.new()
	roads.name = "Roads"
	add_child(roads)
	_roads = roads

	# Asphalt grid (the crossing slabs simply overlap at intersections). Kept
	# nearly flush with the ground so the player walks on it without sinking in.
	# N-S roads stop at z=141 (beach edge) â€” length 291, centre at -4.5.
	for gx in GRID:
		_slab(roads, Vector3(ROAD_W, 0.06, 291.0), Vector3(gx, 0.0, -4.5), ASPHALT)
	for gz in GRID:
		# Span = 270 â†’ roads stop at x=Â±135 (outermost N-S grid lines), no stubs into mall/woods zones.
		_slab(roads, Vector3(270.0, 0.06, ROAD_W), Vector3(0, 0.0, gz), ASPHALT)

	_build_sidewalks(roads)
	_build_lane_lines(roads)
	for gx in GRID:
		for gz in GRID:
			_build_crosswalks(roads, gx, gz)

	_build_stop_signs(roads)


# Sidewalk strips flanking every street, split into segments so they never run
# across the road at an intersection. The gap left at each crossing is exactly
# the road, where a crosswalk goes instead.
func _build_sidewalks(roads: Node3D) -> void:
	var curb_col := Color(0.56, 0.54, 0.52)
	for gx in GRID:
		for side in [-1.0, 1.0]:
			var x: float = gx + side * SW_OFF
			var cx: float = x - side * SW_W * 0.5
			for seg in _segments():
				var seg_end := minf(seg.y, 141.0)   # clip N-S sidewalks at beach edge
				if seg_end <= seg.x:
					continue
				var slen: float = seg_end - seg.x
				var smid: float = (seg.x + seg_end) * 0.5
				_slab(roads, Vector3(SW_W, 0.10, slen), Vector3(x, 0.0, smid), SIDEWALK)
				_box(roads, Vector3(0.18, 0.10, slen), Vector3(cx, 0.05, smid), curb_col)
	# West outer sidewalk: fill E-W road gaps with asphalt (road continues through).
	var west_sw_x := -135.0 - SW_OFF
	for gap_z in GRID:
		_slab(roads, Vector3(SW_W, 0.10, ROAD_W), Vector3(west_sw_x, 0.0, gap_z), ASPHALT)
	for gz in GRID:
		for side in [-1.0, 1.0]:
			var z: float = gz + side * SW_OFF
			var cz: float = z - side * SW_W * 0.5
			# South outer sidewalk (beach edge): one continuous slab, no gaps.
			if gz == 135.0 and side == 1.0:
				_slab(roads, Vector3(270.0, 0.10, SW_W), Vector3(0, 0.0, z), SIDEWALK)
				continue
			for seg in _segments():
				if seg.x >= 134.9 or seg.y <= -134.9:
					continue   # skip stubs east/west of the outermost N-S grid lines
				var hlen: float = seg.y - seg.x
				var hmid: float = (seg.x + seg.y) * 0.5
				_slab(roads, Vector3(hlen, 0.10, SW_W), Vector3(hmid, 0.0, z), SIDEWALK)
				_box(roads, Vector3(hlen, 0.10, 0.18), Vector3(hmid, 0.05, cz), curb_col)


# The runs of clear pavement between the road crossings, as [start, end] pairs.
func _segments() -> Array:
	var bounds := [-EXT]
	for line in GRID:
		bounds.append(line - HALF)
		bounds.append(line + HALF)
	bounds.append(EXT)
	var segs := []
	var i := 0
	while i + 1 < bounds.size():
		if bounds[i + 1] - bounds[i] > 0.5:
			segs.append(Vector2(bounds[i], bounds[i + 1]))
		i += 2
	return segs


# Dashed center lines on the four downtown "main streets" (Â±32), broken at
# intersections.
func _build_lane_lines(roads: Node3D) -> void:
	for line in [-HALF_BLOCK, HALF_BLOCK]:
		var p := -EXT + 4.0
		while p < EXT:
			if not _near_grid(p, HALF + 2.0):
				if p < 141.0:   # N-S dashes stop at beach edge
					_slab(roads, Vector3(0.35, 0.04, 2.4), Vector3(line, 0.06, p), LINE)
				if absf(p) < 135.0:   # E-W dashes stop at grid boundary â€” no stubs past x=Â±135
					_slab(roads, Vector3(2.4, 0.04, 0.35), Vector3(p, 0.06, line), LINE)
			p += 5.0


# Four zebra crosswalks (one per arm) painted on the road at an intersection.
func _build_crosswalks(roads: Node3D, gx: float, gz: float) -> void:
	for sx in [-1.0, 1.0]:
		# East outer sidewalk: only the z=27 crossing kept (parking-lot entrance).
		if gx == 135.0 and sx == 1.0 and gz != 27.0:
			continue
		# West outer sidewalk: no road beyond, so no crosswalk on the grass.
		if gx == -135.0 and sx == -1.0:
			continue
		_crosswalk(roads, Vector3(gx + sx * SW_OFF, 0.06, gz), true)   # across the E-W road
	for sz in [-1.0, 1.0]:
		if gz == 135.0 and sz == 1.0:
			continue
		_crosswalk(roads, Vector3(gx, 0.06, gz + sz * SW_OFF), false)  # across the N-S road


func _crosswalk(roads: Node3D, pos: Vector3, along_z: bool) -> void:
	var span := ROAD_W - 1.0
	for i in 4:
		var o := -1.65 + 1.1 * float(i)
		if along_z:
			_slab(roads, Vector3(0.45, 0.04, span), pos + Vector3(o, 0, 0), LINE)
		else:
			_slab(roads, Vector3(span, 0.04, 0.45), pos + Vector3(0, 0, o), LINE)


# Lampposts on the GRASSY edge of the sidewalk, placed in the GAPS between the
# frontage buildings (never in front of a door). For each interior street we scan
# along it and drop a lamp wherever the frontage has an opening, spaced out and
# kept off the intersections.
func _build_lampposts(layout: Array) -> void:
	var edge := HALF + SW_W + 0.3   # outer (grass) edge of the sidewalk = 7.0
	for line in [-81.0, -HALF_BLOCK, HALF_BLOCK, 81.0]:
		var s := 1.0 if line > 0.0 else -1.0          # build on the outer side
		_lamps_in_gaps(layout, true, line, s, line + s * edge)   # N-S street (runs along z)
		_lamps_in_gaps(layout, false, line, s, line + s * edge)  # E-W street (runs along x)


# Walk a single street edge and place lamps where the frontage is open.
#   vertical=true  -> street is the line x=`line`, lamps sit at x=`perp`, vary z.
#   vertical=false -> street is the line z=`line`, lamps sit at z=`perp`, vary x.
func _lamps_in_gaps(layout: Array, vertical: bool, line: float, s: float, perp: float) -> void:
	# Collect the along-axis intervals occupied by the frontage buildings.
	var blocked := []
	for cfg in layout:
		if cfg.has("prop"):
			continue
		var fp := _footprint(cfg)
		var bperp: float = fp.x if vertical else fp.z
		var hperp: float = fp.hx if vertical else fp.hz
		if signf(bperp - line) != s:
			continue
		# Only the front row: its near edge is just past the sidewalk.
		var near := absf(bperp - s * hperp - line)
		if near < 5.0 or near > 13.0:
			continue
		var along: float = fp.z if vertical else fp.x
		var halong: float = fp.hz if vertical else fp.hx
		blocked.append(Vector2(along - halong - 0.8, along + halong + 0.8))

	# March along the street at a regular spacing, nudging each lamp to the
	# nearest opening so it lands in a gap, never in front of a door. Skip it if
	# the frontage is solid nearby or the spot falls in an intersection.
	var t := -EXT + 14.0
	while t <= EXT - 14.0:
		var spot := _nearest_open(blocked, t, 7.0)
		if spot < 1.0e8 and not _near_grid(spot, 7.0):
			if vertical:
				_add_lamppost(_roads, Vector3(perp, 0, spot))
			else:
				_add_lamppost(_roads, Vector3(spot, 0, perp))
		t += 24.0


func _covered(intervals: Array, v: float) -> bool:
	for iv in intervals:
		if v >= iv.x and v <= iv.y:
			return true
	return false


# Nearest along-axis position to `t` (within +/- maxshift) that no frontage
# building covers, or a huge number if the frontage is solid there.
func _nearest_open(intervals: Array, t: float, maxshift: float) -> float:
	var d := 0.0
	while d <= maxshift:
		if not _covered(intervals, t + d):
			return t + d
		if not _covered(intervals, t - d):
			return t - d
		d += 1.0
	return 1.0e9


# Stop signs on the corners of the four busy downtown intersections (the green's
# corners). Each is a pole topped with a red octagon.
func _build_stop_signs(roads: Node3D) -> void:
	for gx in [-HALF_BLOCK, HALF_BLOCK]:
		for gz in [-HALF_BLOCK, HALF_BLOCK]:
			# Inner corner (green side) of the intersection, on the sidewalk.
			var x: float = gx - signf(gx) * SW_OFF
			var z: float = gz - signf(gz) * SW_OFF
			_add_stop_sign(roads, Vector3(x, 0, z))


func _add_stop_sign(parent: Node3D, pos: Vector3) -> void:
	_cylinder(parent, 0.1, 3.0, pos + Vector3(0, 1.5, 0), Color(0.55, 0.55, 0.58))  # pole
	var sign := MeshInstance3D.new()
	var oct := CylinderMesh.new()
	oct.top_radius = 0.65
	oct.bottom_radius = 0.65
	oct.height = 0.12
	oct.radial_segments = 8          # octagon
	sign.mesh = oct
	sign.material_override = _mat(Color(0.80, 0.08, 0.08))
	sign.position = pos + Vector3(0, 2.8, 0)
	sign.rotation = Vector3(PI * 0.5, PI / 8.0, 0)  # face outward, flats level
	parent.add_child(sign)
	_prop_collider(pos, 0.18, 3.0)   # solid pole


func _near_grid(v: float, r: float) -> bool:
	for line in GRID:
		if absf(v - line) < r:
			return true
	return false


# -----------------------------------------------------------------------------
# Town: spawn every building, collecting the goals into a name->node dictionary.
# -----------------------------------------------------------------------------
func _build_town(layout: Array, goals: Dictionary, goal_names: Array) -> void:
	var town := Node3D.new()
	town.name = "Town"
	add_child(town)

	# Footprints of every solid building, used to pick house facings that point
	# at a road the house actually has a clear shot to (no neighbour in front).
	var all_fps := _building_footprints(layout)

	for cfg in layout:
		# Courtyard greenery placed in the (road-less) centre of a block instead
		# of a landlocked building.
		if cfg.has("prop"):
			if cfg.prop == "tree":
				_tree(town, cfg.pos)
			elif cfg.prop == "ground_slab":
				_courtyard_slab(town, cfg.pos, cfg.color, cfg.get("circular", true))
			else:
				_bench(town, cfg.pos, cfg.yaw)
			continue
		var node := _spawn_building(cfg)
		node.position = cfg.pos
		# Park stays unrotated so its tree/bench/fountain colliders (added to the
		# Props body in world space) line up with the meshes. Goal buildings keep
		# their inner-street facing (their door/goal_spot logic depends on it).
		# Filler houses face the nearest road they have a clear path to, so none
		# end up staring at a neighbour's back wall.
		if cfg.style == "park":
			node.rotation.y = 0.0
		elif cfg.get("goal", false):
			node.rotation.y = _park_or_street_facing(cfg.pos)
		else:
			node.rotation.y = _clear_facing(_footprint(cfg), all_fps)
		town.add_child(node)
		if cfg.get("goal", false):
			var size: Vector3 = cfg.size
			# The goal is the patch of ground right in front of the door (building
			# front is local +Z, rotated by the node's facing). The Park has no
			# door, so its goal is simply standing on the green.
			var spot: Vector3
			var reach: float
			if cfg.style == "park":
				spot = node.global_position
				reach = 14.0
			else:
				var fwd := node.global_transform.basis.z   # door direction in world
				spot = node.global_position + fwd * (size.z * 0.5 + 3.5)
				reach = 4.0
			spot.y = 0.0
			node.set_meta("goal_spot", spot)
			node.set_meta("goal_reach", reach)
			# Which street the goal fronts: the door faces it, so the street line is
			# the nearest grid line along the door axis. Used for the "It is here!"
			# hint once the player turns onto that street.
			var fwd := node.global_transform.basis.z
			var axis_x: bool = absf(fwd.x) > absf(fwd.z)
			node.set_meta("goal_street_axis_x", axis_x)
			node.set_meta("goal_street_line", _nearest(spot.x if axis_x else spot.z))
			# How far along the street (each way from the goal) still counts as
			# "directly in front" â€” the block frontage between the two flanking
			# intersections, minus the road at each so it stays on the segment.
			node.set_meta("goal_seg_half", HALF_BLOCK - HALF)
			# Where the building's name label floats once it's been found: a sign
			# just above the door, on the front face.
			node.set_meta("label_pos", node.global_position
					+ Vector3(0, size.y + 5.0, 0))
			goals[cfg.name] = node
			goal_names.append(cfg.name)
			# Buildings with facade icons (cross, burger) â€” added as hidden nodes
			# under _icons_root so they're excluded from baking and can be revealed
			# individually when the player discovers that building.
			if cfg.name in ["Hospital", "Restaurant", "Drugstore", "Church", "Bakery", "Police Station", "Bookstore", "Starbucks"]:
				_add_icon_for_building(cfg.name, size, node)


# Pack each block with buildings to create a dense "city maze": the goal sits at
# the block centre and houses/shops/offices fill a ring of slots around it (any
# that would overlap the goal are skipped). The street grid between blocks is
# what you navigate. All positions are final (no setback) â€” the slot spacing is
# pre-chosen so nothing spills onto a road. Coordinates are in world units.
const SLOT := 13.0              # ring offset from block centre (tight packing)
const CORE := 9.0               # central courtyard half-size kept clear of buildings
const SB := HALF + SW_W + 2.0   # building face clearance from a road line (8.7)
# Max distance a building face may sit from its block centre before it would
# touch the sidewalk: (HALF_BLOCK - SW_OFF - SW_W/2) minus a 0.5 grass strip.
const BUILDABLE := HALF_BLOCK - SW_OFF - SW_W * 0.5 - 0.5

func _layout_buildings() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 71
	var out := []
	for j in BLOCK_CENTERS.size():
		for i in BLOCK_CENTERS.size():
			var cx: float = BLOCK_CENTERS[i]
			var cz: float = BLOCK_CENTERS[j]
			var gname: String = GOAL_GRID[j][i]
			if gname == "Park":
				out.append({"name": "Park", "pos": Vector3(0, 0, 0), "size": Vector3(40, 0.08, 40),
						"color": Color(0.30, 0.55, 0.27), "style": "park", "goal": true})
				continue
			var placed := []
			if gname != "":
				# Goal fronts the inner street (toward downtown); block centre stays
				# open so nothing is landlocked without road access.
				var d: Dictionary = GOAL_DEFS[gname]
				var pos: Vector3
				if gname == "Gas Station":
					# Corner placement: set back equally from both inner street lines.
					pos = Vector3(
						cx - signf(cx) * (HALF_BLOCK - SB - d.size.z * 0.5),
						0,
						cz - signf(cz) * (HALF_BLOCK - SB - d.size.z * 0.5))
				else:
					pos = _front_inner(cx, cz, d.size)
				var gcfg := {"name": gname, "pos": pos,
						"size": d.size, "style": d.style, "goal": true}
				if d.has("color"):
					gcfg["color"] = d.color
				if d.has("accent"):
					gcfg["accent"] = d.accent
				out.append(gcfg)
				placed = [_footprint(gcfg)]
			# Main ring of houses around the goal (or around empty blocks).
			for ox in [-SLOT, 0.0, SLOT]:
				for oz in [-SLOT, 0.0, SLOT]:
					if ox == 0.0 and oz == 0.0:
						continue
					_try_place(_house_cfg(Vector3(cx + ox, 0, cz + oz), rng), placed, out)
			# Fill pass: squeeze small fillers into whatever gaps remain so blocks
			# read as solid city blocks instead of a sparse ring.
			_fill_block(cx, cz, placed, out, rng)
			# The road-less block centre is left open and dressed with a little
			# greenery (trees + the odd bench) instead of a landlocked building.
			out.append_array(_courtyard_props(cx, cz, placed, rng))
	return out


# Try to add `cfg` to the block if it doesn't overlap anything already placed
# (and stays off the sidewalk). `gap` is the alley left around it. Returns true
# on success.
func _try_place(cfg: Dictionary, placed: Array, out: Array, gap: float = 1.0) -> bool:
	var fp := _footprint(cfg)
	# Keep the footprint clear of the sidewalk on all four sides.
	if absf(fp.x - _block_center(fp.x)) + fp.hx > BUILDABLE:
		return false
	if absf(fp.z - _block_center(fp.z)) + fp.hz > BUILDABLE:
		return false
	for f in placed:
		if _overlaps(f, fp, gap):
			return false
	out.append(cfg)
	placed.append(fp)
	return true


# Greedily drop filler houses across a fine grid inside the block, but leave the
# central core (CORE x CORE) clear (that pocket becomes a courtyard). At each
# spot we try the largest filler that fits down to a small one, with a tight
# alley, so even the slivers right beside the big goal buildings get filled.
func _fill_block(cx: float, cz: float, placed: Array, out: Array, rng: RandomNumberGenerator) -> void:
	var offs := [-15.0, -12.0, -9.0, -6.0, -3.0, 0.0, 3.0, 6.0, 9.0, 12.0, 15.0]
	for ox in offs:
		for oz in offs:
			if absf(ox) < CORE and absf(oz) < CORE:
				continue
			var pos := Vector3(cx + ox, 0, cz + oz)
			# Largest-first so big lots stay roomy but tight gaps still get a small one.
			for w in [8.5, 7.0, 5.5]:
				var cfg := _storeyed_house(pos, rng, 4, w, w * rng.randf_range(0.85, 1.0))
				if _try_place(cfg, placed, out, 0.4):
					break


# Trees (1-2) and the occasional bench (0-2) for the open courtyard at a block's
# road-less centre. Positions are overlap-checked against the block's buildings.
func _courtyard_slab(parent: Node3D, pos: Vector3, color: Color, circular: bool = true) -> void:
	var mi := MeshInstance3D.new()
	if circular:
		var cm := CylinderMesh.new()
		cm.top_radius = 4.5
		cm.bottom_radius = 4.5
		cm.height = 0.04
		cm.rings = 1
		mi.mesh = cm
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(9.0, 0.04, 9.0)
		mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	mi.position = pos + Vector3(0, 0.02, 0)
	parent.add_child(mi)


func _courtyard_props(cx: float, cz: float, placed: Array, rng: RandomNumberGenerator) -> Array:
	var out := []

	# Deterministic courtyard surface variant â€” 0=dirt, 1=cement, 2=none.
	var crng := RandomNumberGenerator.new()
	crng.seed = abs(int(cx * 997 + cz * 1009)) + 3571
	var variant := crng.randi() % 3
	if variant == 0:
		out.append({"prop": "ground_slab", "pos": Vector3(cx, 0, cz),
				"color": Color(0.62, 0.49, 0.34), "circular": true})   # dirt circle
	elif variant == 1:
		out.append({"prop": "ground_slab", "pos": Vector3(cx, 0, cz),
				"color": Color(0.60, 0.60, 0.63), "circular": false})  # cement square

	var spots := []
	for ox in [-5.0, -2.5, 0.0, 2.5, 5.0]:
		for oz in [-5.0, -2.5, 0.0, 2.5, 5.0]:
			spots.append(Vector3(cx + ox, 0, cz + oz))
	# Deterministic shuffle (Fisher-Yates) using our seeded rng.
	for i in range(spots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Vector3 = spots[i]
		spots[i] = spots[j]
		spots[j] = tmp

	var trees_left := rng.randi_range(1, 2)
	var benches_left := rng.randi_range(0, 2)
	var used := []
	for s in spots:
		if trees_left <= 0 and benches_left <= 0:
			break
		var is_tree := trees_left > 0
		var fp := {"x": s.x, "z": s.z,
				"hx": 0.6 if is_tree else 1.3, "hz": 0.6 if is_tree else 0.9}
		var clash := false
		for f in placed:
			if _overlaps(f, fp):
				clash = true
				break
		if not clash:
			for f in used:
				if _overlaps(f, fp):
					clash = true
					break
		if clash:
			continue
		if is_tree:
			out.append({"prop": "tree", "pos": s})
			trees_left -= 1
		else:
			out.append({"prop": "bench", "pos": s, "yaw": rng.randf() * TAU})
			benches_left -= 1
		used.append(fp)
	return out


# Nearest block centre to a world coordinate (for the sidewalk-clearance check).
func _block_center(v: float) -> float:
	var best: float = BLOCK_CENTERS[0]
	for c in BLOCK_CENTERS:
		if absf(c - v) < absf(best - v):
			best = c
	return best


# Position a goal so it fronts the inner street (the block edge nearest the town
# centre), set back to clear the road. The block centre is left empty.
func _front_inner(cx: float, cz: float, size: Vector3) -> Vector3:
	if absf(cx) >= absf(cz):
		var line: float = cx - signf(cx) * HALF_BLOCK
		return Vector3(line + signf(cx) * (SB + size.z * 0.5), 0, cz)
	var zline: float = cz - signf(cz) * HALF_BLOCK
	return Vector3(cx, 0, zline + signf(cz) * (SB + size.z * 0.5))


# A ring-slot building. Mostly multi-storey houses/apartments (3-5 floors are
# common, single-storey is rare) so the blocks rise into tall maze walls; a few
# low shops add variety.
func _house_cfg(pos: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	var r := rng.randf()
	if r < 0.72:
		return _storeyed_house(pos, rng, 5, rng.randf_range(9, 12), rng.randf_range(9, 12))
	if r < 0.88:
		return {"name": "Office", "pos": pos, "style": "office",
				"size": Vector3(10, rng.randf_range(12, 18), 10),
				"color": OFFICE_COLORS[rng.randi() % OFFICE_COLORS.size()]}
	return {"name": "Store", "pos": pos, "style": "shop", "size": Vector3(11, 6, 11),
			"color": SHOP_COLORS[rng.randi() % SHOP_COLORS.size()], "accent": Color(0.38, 0.34, 0.30)}


# Build a multi-storey house config of the given footprint, picking a floor count
# weighted toward the taller end (single-storey rare). Tall ones get flat roofs
# (apartment/tower look); short ones keep pitched roofs + chimneys.
func _storeyed_house(pos: Vector3, rng: RandomNumberGenerator, hi: int, w: float, d: float) -> Dictionary:
	var floors := _pick_floors(rng, hi)
	var tall := floors >= 3
	return {
		"name": "House", "pos": pos, "style": "house",
		"size": Vector3(w, 2.0 + floors * 3.0 + rng.randf_range(-0.3, 0.5), d),
		"color": HOUSE_COLORS[rng.randi() % HOUSE_COLORS.size()],
		"accent": ROOF_COLORS[rng.randi() % ROOF_COLORS.size()],   # roof colour
		"floors": floors,
		"flat_roof": tall or rng.randf() < 0.30,
		"chimney": (not tall) and rng.randf() < 0.6,
	}


# Floor count weighted toward mid/tall buildings; single-storey is rare. `hi`
# caps the count (5 for full lots, 4 for the narrow fillers).
func _pick_floors(rng: RandomNumberGenerator, hi: int) -> int:
	var r := rng.randf()
	if hi >= 5:
		if r < 0.08: return 1
		if r < 0.30: return 2
		if r < 0.60: return 3
		if r < 0.85: return 4
		return 5
	if r < 0.12: return 1
	if r < 0.45: return 2
	if r < 0.80: return 3
	return 4


# World footprint (axis-aligned half extents) of a building at its final pos,
# using the SAME facing it will be rotated to (so the overlap check is accurate).
func _footprint(cfg: Dictionary) -> Dictionary:
	var s: Vector3 = cfg.size
	var yaw := _park_or_street_facing(cfg.pos)
	# yaw of Â±PI/2 turns the depth (z) along world X; yaw of 0/PI keeps it along Z.
	var faces_x: bool = absf(yaw) > 0.01 and absf(absf(yaw) - PI) > 0.01
	return {"x": cfg.pos.x, "z": cfg.pos.z,
			"hx": (s.z if faces_x else s.x) * 0.5, "hz": (s.x if faces_x else s.z) * 0.5}


# True if two footprints are closer than `gap` (the alley left between buildings).
func _overlaps(a: Dictionary, b: Dictionary, gap: float = 1.0) -> bool:
	return (a.hx + b.hx + gap) > absf(a.x - b.x) and (a.hz + b.hz + gap) > absf(a.z - b.z)


# Face the building's front (+Z) toward the nearest street.
func _facing(pos: Vector3) -> float:
	var nx := _nearest(pos.x)
	var nz := _nearest(pos.z)
	if absf(pos.x - nx) <= absf(pos.z - nz):
		return PI * 0.5 if nx > pos.x else -PI * 0.5
	return 0.0 if nz > pos.z else PI


# Buildings in the row directly fronting the central Park face the Park (so the
# green has a consistent storefront) instead of being turned toward a side street
# by the nearest-street tie-break. Everything else just faces its street. Used for
# goal-building facing and for footprint orientation during placement.
const PARK_LAT := 20.0   # Park half-width: how far a frontage can sit off-axis
func _park_or_street_facing(pos: Vector3) -> float:
	# South / north blocks (Park lies along the z axis from them).
	if absf(pos.x) <= PARK_LAT:
		if pos.z > HALF_BLOCK and pos.z < 54.0:
			return PI            # south block -> face north toward the Park
		if pos.z < -HALF_BLOCK and pos.z > -54.0:
			return 0.0           # north block -> face south toward the Park
	# East / west blocks (Park lies along the x axis from them).
	if absf(pos.z) <= PARK_LAT:
		if pos.x > HALF_BLOCK and pos.x < 54.0:
			return -PI * 0.5     # east block -> face west toward the Park
		if pos.x < -HALF_BLOCK and pos.x > -54.0:
			return PI * 0.5      # west block -> face east toward the Park
	return _facing(pos)


# Axis-aligned footprints of every solid building (goals + filler houses). The
# Park and courtyard props are open space, so they're skipped.
func _building_footprints(layout: Array) -> Array:
	var fps := []
	for cfg in layout:
		if cfg.has("prop"):
			continue
		if cfg.get("style", "") == "park":
			continue
		fps.append(_footprint(cfg))
	return fps


# Face the nearest road this building has a CLEAR shot to (no other building
# sitting in the strip between its front face and that road). Falls back to the
# plain nearest road if every side is blocked. Front is local +Z, so the yaws
# are: +z -> 0, -z -> PI, +x -> PI/2, -x -> -PI/2.
func _clear_facing(fp: Dictionary, fps: Array) -> float:
	var bcx := _block_center(fp.x)
	var bcz := _block_center(fp.z)
	var cands := [
		{"yaw": 0.0,       "axis": "z", "sign":  1.0, "road": bcz + HALF_BLOCK},
		{"yaw": PI,        "axis": "z", "sign": -1.0, "road": bcz - HALF_BLOCK},
		{"yaw": PI * 0.5,  "axis": "x", "sign":  1.0, "road": bcx + HALF_BLOCK},
		{"yaw": -PI * 0.5, "axis": "x", "sign": -1.0, "road": bcx - HALF_BLOCK},
	]
	var best_clear_yaw := 0.0
	var best_clear_dist := INF
	var best_any_yaw := 0.0
	var best_any_dist := INF
	for c in cands:
		var dist: float = absf(c.road - fp.x) if c.axis == "x" else absf(c.road - fp.z)
		if dist < best_any_dist:
			best_any_dist = dist
			best_any_yaw = c.yaw
		if _front_clear(fp, c, fps) and dist < best_clear_dist:
			best_clear_dist = dist
			best_clear_yaw = c.yaw
	return best_clear_yaw if best_clear_dist < INF else best_any_yaw


# True if nothing blocks the strip between this building's front face (in the
# candidate direction `c`) and its road.
func _front_clear(fp: Dictionary, c: Dictionary, fps: Array) -> bool:
	var eps := 0.4
	for o in fps:
		if is_equal_approx(o.x, fp.x) and is_equal_approx(o.z, fp.z):
			continue   # skip self
		if c.axis == "x":
			# Must overlap the front width (z) to be "in front".
			if o.z + o.hz <= fp.z - fp.hz or o.z - o.hz >= fp.z + fp.hz:
				continue
			if c.sign > 0.0:
				var face: float = fp.x + fp.hx
				if o.x + o.hx > face + eps and o.x - o.hx < c.road:
					return false
			else:
				var face_n: float = fp.x - fp.hx
				if o.x - o.hx < face_n - eps and o.x + o.hx > c.road:
					return false
		else:
			if o.x + o.hx <= fp.x - fp.hx or o.x - o.hx >= fp.x + fp.hx:
				continue
			if c.sign > 0.0:
				var facez: float = fp.z + fp.hz
				if o.z + o.hz > facez + eps and o.z - o.hz < c.road:
					return false
			else:
				var facez_n: float = fp.z - fp.hz
				if o.z - o.hz < facez_n - eps and o.z + o.hz > c.road:
					return false
	return true


func _nearest(v: float) -> float:
	var best := GRID[0]
	for g in GRID:
		if absf(g - v) < absf(best - v):
			best = g
	return best


# =============================================================================
# Building factory
# =============================================================================
func _spawn_building(cfg: Dictionary) -> Node3D:
	var style: String = cfg.style
	var size: Vector3 = cfg.size
	var color: Color = cfg.get("color", Color(0.8, 0.8, 0.8))
	var accent: Color = cfg.get("accent", Color(0.4, 0.4, 0.4))
	if style == "house" and not cfg.has("color"):
		color = HOUSE_COLORS[_house_i % HOUSE_COLORS.size()]
		_house_i += 1
	var body := StaticBody3D.new()
	body.name = cfg.name

	match style:
		"park":
			_brick_wall_color = Color(0.72, 0.68, 0.60)   # path colour
			_build_park(body, size, color)
			_brick_wall_color = Color.TRANSPARENT
		"pool":
			_build_pool(body, size, color, accent)
		"station":
			_build_station(body, size, color, accent)
		"gas":
			_build_gas(body, size)
		"house":
			# 0â€“25 % brick, 25â€“50 % siding, 50â€“100 % speckle.
			var brng := RandomNumberGenerator.new()
			brng.seed = abs(hash(cfg.get("pos", Vector3.ZERO)) + 91273)
			var roll := brng.randf()
			if roll < 0.25:
				# Dark-mortar group split: 75 % white, 25 % dark, 0 % cream unchanged.
				var mrng := RandomNumberGenerator.new()
				mrng.seed = abs(hash(cfg.get("pos", Vector3.ZERO)) + 13577)
				var mroll := mrng.randf()
				if mroll < 0.375:
					_brick_white_wall_color = color
				elif mroll < 0.50:
					_brick_wall_color = color
				else:
					_brick_light_wall_color = color
			elif roll < 0.50:
				_siding_wall_color = color
			_build_structure(body, cfg, size, color, accent)
			_brick_wall_color = Color.TRANSPARENT
			_brick_light_wall_color = Color.TRANSPARENT
			_brick_white_wall_color = Color.TRANSPARENT
			_siding_wall_color = Color.TRANSPARENT
		_:
			_build_structure(body, cfg, size, color, accent)

	# Most styles want a solid collision box covering the full footprint.
	# Park stays walkable. Gas station gets per-piece boxes matching its visual geometry.
	if style != "park" and style != "gas":
		_collide(body, size)
	elif style == "gas":
		_collide_gas(body, size)
	return body


# A generic structure: mass + windows + door + a roof/accent per style.
func _build_structure(body: Node3D, cfg: Dictionary, size: Vector3, color: Color, accent: Color) -> void:
	var style: String = cfg.style
	_box(body, size, Vector3(0, size.y * 0.5, 0), color)
	var rows := 2
	var cols := int(clampf(size.x / 3.5, 2, 5))
	match style:
		"civic":
			_columns(body, size)
			_pediment(body, size, color)
			rows = 2
		"hospital":
			_flat_roof(body, size, Color(0.72, 0.74, 0.77))
			rows = 3   # red cross added as a hidden icon node, revealed on discovery
		"brick":
			_flat_roof(body, size, Color(0.30, 0.16, 0.13))
			_flagpole(body, size)
		"police":
			_flat_roof(body, size, accent)
			_band(body, size, accent)
		"firehouse":
			_flat_roof(body, size, accent)
			_garage_doors(body, size, accent)
			_cylinder(body, 0.9, size.y + 5.0, Vector3(size.x * 0.5 - 1.0, (size.y + 5.0) * 0.5, 0), Color(0.5, 0.12, 0.10))
			rows = 1
		"shop", "market", "diner":
			_flat_roof(body, size, accent.darkened(0.1))
			_awning(body, size, accent)
			_storefront(body, size)
			rows = 0   # storefront replaces the window grid on the ground floor
			if style == "market":
				rows = 1   # a strip of clerestory windows above the storefront
			# burger added as hidden icon node, revealed on discovery
		"office":
			_flat_roof(body, size, color.darkened(0.2))
			rows = 4
		"house":
			if cfg.get("flat_roof", false):
				_flat_roof(body, size, accent)
			else:
				_pitched_roof(body, size, accent)
			if cfg.get("chimney", true):
				_chimney(body, size)
			rows = cfg.get("floors", 1)
			cols = int(clampf(size.x / 3.5, 2, 4))
		"church":
			_pitched_roof(body, size, Color(0.45, 0.30, 0.35))
			_steeple(body, size)
			_steeple_cross(body, size)
			rows = 2
			cols = 2
		"motel":
			_flat_roof(body, size, accent)
			_motel_doors(body, size)
			rows = 0
		_:
			_flat_roof(body, size, accent)

	if rows > 0:
		_windows(body, size, rows, cols, hash(cfg.get("pos", Vector3.ZERO)), style)
	# Shop styles get their door from the storefront; firehouse/motel have none.
	if style not in ["firehouse", "motel", "shop", "market", "diner"]:
		var drng := RandomNumberGenerator.new()
		drng.seed = abs(hash(cfg.get("pos", Vector3.ZERO)) + 7919)
		_door(body, size, drng.randf() < 0.5)


# -----------------------------------------------------------------------------
# Shared facade parts (front is +Z)
# -----------------------------------------------------------------------------
func _windows(body: Node3D, size: Vector3, rows: int, cols: int, seed_hint: int = 0, style: String = "") -> void:
	var z := size.z * 0.5
	var col_gap := size.x / float(cols + 1)
	var row_gap := size.y / float(rows + 1)
	var frame := _mat(Color(0.20, 0.20, 0.22))
	# Per-building style flags seeded from the building's world position (passed in
	# as seed_hint) so each building is consistent across reloads.
	var wrng := RandomNumberGenerator.new()
	wrng.seed = abs(seed_hint)
	var has_sill := wrng.randf() < 0.42
	var official := style in ["police", "civic", "hospital", "firehouse", "church", "station", "office"]
	var has_dividers := (rows <= 2) and not official and wrng.randf() < 0.45
	var tints := [
		Color(0.55, 0.72, 0.90),
		Color(0.55, 0.72, 0.90),
		Color(0.52, 0.82, 0.76),
		Color(0.74, 0.78, 0.80),
		Color(0.80, 0.76, 0.58),
	]
	var glass := _glass(tints[int(wrng.randf() * 5.0)])
	for r in rows:
		var wy := size.y - row_gap * float(r + 1)
		for c in cols:
			var wx := -size.x * 0.5 + col_gap * float(c + 1)
			# Skip any window that would sit over / touch the door (centre, low).
			if absf(wx) < 2.4 and wy < 3.8:
				continue
			_box_mat(body, Vector3(1.25, 1.6, 0.06), Vector3(wx, wy, z + 0.04), frame)
			_box_mat(body, Vector3(1.0, 1.35, 0.12), Vector3(wx, wy, z + 0.08), glass)
			if has_sill:
				_box(body, Vector3(1.50, 0.13, 0.28), Vector3(wx, wy - 0.92, z + 0.10), Color(0.80, 0.78, 0.76))
			if has_dividers:
				_box_mat(body, Vector3(1.00, 0.05, 0.06), Vector3(wx, wy, z + 0.15), frame)
				_box_mat(body, Vector3(0.05, 1.35, 0.06), Vector3(wx, wy, z + 0.15), frame)


func _door(body: Node3D, size: Vector3, show_canopy: bool = true) -> void:
	var z := size.z * 0.5
	_box(body, Vector3(2.2, 2.7, 0.1), Vector3(0, 1.35, z + 0.04), Color(0.28, 0.20, 0.13))
	_box(body, Vector3(1.8, 2.4, 0.14), Vector3(0, 1.2, z + 0.08), Color(0.45, 0.32, 0.20))
	# Flat threshold (kept low so the player doesn't sink into a raised step).
	_box(body, Vector3(3.0, 0.06, 1.2), Vector3(0, 0.03, z + 0.6), Color(0.75, 0.74, 0.72))
	if show_canopy:
		_box(body, Vector3(3.0, 0.14, 1.0), Vector3(0, 3.0, z + 0.45), Color(0.55, 0.52, 0.48))


func _storefront(body: Node3D, size: Vector3) -> void:
	var z := size.z * 0.5
	_box_mat(body, Vector3(size.x - 1.4, 2.4, 0.12), Vector3(0, 1.6, z + 0.07), _glass())
	_box(body, Vector3(1.6, 2.4, 0.16), Vector3(0, 1.4, z + 0.1), Color(0.30, 0.22, 0.16))  # door


func _awning(body: Node3D, size: Vector3, accent: Color) -> void:
	var aw := _box(body, Vector3(size.x + 0.4, 0.18, 1.8), Vector3(0, 3.05, size.z * 0.5 + 0.75), accent)
	aw.rotation.x = deg_to_rad(12)
	_box(body, Vector3(size.x + 0.4, 0.32, 0.06), Vector3(0, 2.66, size.z * 0.5 + 1.60), accent.darkened(0.12))


# A hamburger icon on the front wall (for Restaurant).
func _burger(body: Node3D, size: Vector3) -> void:
	var z := size.z * 0.5 + 0.12
	var bun := Color(0.86, 0.62, 0.33)
	var patty := Color(0.34, 0.18, 0.10)
	var cheese := Color(0.96, 0.74, 0.16)
	_box(body, Vector3(1.7, 0.28, 0.25), Vector3(0, 4.2, z), bun)       # bottom bun
	_box(body, Vector3(1.85, 0.30, 0.27), Vector3(0, 4.5, z), patty)    # patty
	_box(body, Vector3(1.95, 0.12, 0.29), Vector3(0, 4.7, z), cheese)   # cheese
	# Top bun: a HEMISPHERE (flat bottom on the cheese, domed top) so it reads as
	# a half-ellipse rather than a full ball poking out below the patty.
	var top := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 0.98
	dome.height = 0.98             # hemisphere -> dome rises 0.49 above its flat base
	dome.is_hemisphere = true
	top.mesh = dome
	top.material_override = _mat(bun)
	top.position = Vector3(0, 4.76, z)        # flat base sits on the cheese top
	top.scale = Vector3(1.0, 1.0, 0.30)       # thin in depth (a wall relief)
	body.add_child(top)
	for sx in [-0.45, 0.0, 0.45]:                                       # sesame seeds
		_sphere(body, 0.05, Vector3(sx, 4.98, z + 0.14), Color(0.97, 0.93, 0.80))


func _flat_roof(body: Node3D, size: Vector3, color: Color) -> void:
	_box(body, Vector3(size.x + 1.0, 0.5, size.z + 1.0), Vector3(0, size.y + 0.25, 0), color)
	_box(body, Vector3(size.x + 1.0, 0.28, size.z + 1.0), Vector3(0, size.y - 0.04, 0), color.darkened(0.22))


func _pitched_roof(body: Node3D, size: Vector3, color: Color) -> void:
	# Prism ridge runs along Z, giving a front-gabled roof.
	_prism(body, Vector3(size.x + 1.0, size.y * 0.45, size.z + 1.0),
			Vector3(0, size.y + size.y * 0.225, 0), color)


func _columns(body: Node3D, size: Vector3) -> void:
	var z := size.z * 0.5 + 0.7
	var stone := Color(0.90, 0.88, 0.82)
	var n := int(clampf(size.x / 4.0, 3, 5))
	var span := size.x - 2.0
	for i in n:
		var x := -span * 0.5 + span * float(i) / float(n - 1)
		_cylinder(body, 0.35, size.y, Vector3(x, size.y * 0.5, z), stone)
		var col := CollisionShape3D.new()
		var cshape := CylinderShape3D.new()
		cshape.radius = 0.35
		cshape.height = size.y
		col.shape = cshape
		col.position = Vector3(x, size.y * 0.5, z)
		body.add_child(col)
	_box(body, Vector3(size.x + 0.8, 0.08, 1.8), Vector3(0, 0.04, z), Color(0.82, 0.80, 0.74))  # flush base
	_box(body, Vector3(size.x + 0.8, 0.7, 2.0), Vector3(0, size.y + 0.35, z - 0.1), stone)


func _pediment(body: Node3D, size: Vector3, _color: Color) -> void:
	_prism(body, Vector3(size.x + 0.9, 1.7, 2.0), Vector3(0, size.y + 1.55, size.z * 0.5 + 0.6), Color(0.88, 0.86, 0.80))


func _cross(body: Node3D, size: Vector3) -> void:
	var z := size.z * 0.5 + 0.1
	var y := size.y - 1.3        # high on the wall, above the top row of windows
	var red := Color(0.85, 0.12, 0.12)
	_box(body, Vector3(0.55, 1.8, 0.2), Vector3(0, y, z), red)
	_box(body, Vector3(1.7, 0.55, 0.2), Vector3(0, y, z), red)


func _band(body: Node3D, size: Vector3, accent: Color) -> void:
	_box(body, Vector3(size.x + 0.1, 0.6, size.z + 0.1), Vector3(0, size.y - 1.5, 0), accent)


func _garage_doors(body: Node3D, size: Vector3, accent: Color) -> void:
	var z := size.z * 0.5
	var w := size.x / 2.4
	for sx in [-1.0, 1.0]:
		_box(body, Vector3(w, 3.6, 0.2), Vector3(sx * w * 0.62, 1.9, z + 0.06), accent.lightened(0.1))


func _flagpole(body: Node3D, size: Vector3) -> void:
	_cylinder(body, 0.1, 7.0, Vector3(-size.x * 0.5 - 1.5, 3.5, size.z * 0.5), Color(0.8, 0.8, 0.82))
	_box(body, Vector3(0.05, 0.9, 1.4), Vector3(-size.x * 0.5 - 1.5, 6.4, size.z * 0.5 + 0.7), Color(0.8, 0.2, 0.2))


func _chimney(body: Node3D, size: Vector3) -> void:
	_box(body, Vector3(0.8, size.y * 0.7, 0.8), Vector3(size.x * 0.3, size.y + size.y * 0.2, -size.z * 0.2), Color(0.4, 0.3, 0.28))


func _steeple(body: Node3D, size: Vector3) -> void:
	var x := 0.0
	var z := size.z * 0.5 - 1.5   # front of building
	_box(body, Vector3(3.0, size.y + 4.0, 3.0), Vector3(x, (size.y + 4.0) * 0.5, z), Color(0.92, 0.92, 0.90))
	_prism(body, Vector3(3.2, 4.0, 3.2), Vector3(x, size.y + 6.0, z), Color(0.45, 0.30, 0.35))


func _steeple_cross(body: Node3D, size: Vector3) -> void:
	var z := size.z * 0.5 - 1.5 + 1.52   # front face of steeple tower
	var y := size.y + 5.2
	var white := Color(0.98, 0.98, 0.96)
	_box(body, Vector3(0.28, 1.8, 0.14), Vector3(0, y, z), white)
	_box(body, Vector3(1.1, 0.28, 0.14), Vector3(0, y + 0.35, z), white)


func _add_icon_for_building(bname: String, size: Vector3, body: Node3D) -> void:
	var icon := Node3D.new()
	_icons_root.add_child(icon)
	icon.global_transform = body.global_transform
	match bname:
		"Hospital":
			_cross(icon, size)
		"Restaurant":
			_burger(icon, size)
		"Drugstore":
			_drugstore_cross(icon, size)
		"Church":
			_church_cross_icon(icon, size)
		"Bakery":
			_baguette(icon, size)
		"Police Station":
			_sheriff_badge(icon, size)
		"Bookstore":
			_bookstore_book(icon, size)
		"Starbucks":
			_coffee_cup(icon, size)
	icon.visible = false
	_icon_nodes[bname] = icon


func _drugstore_cross(body: Node3D, size: Vector3) -> void:
	var z := size.z * 0.5 + 0.1
	var y := size.y - 1.3
	var green := Color(0.10, 0.68, 0.38)
	_box(body, Vector3(0.55, 1.8, 0.20), Vector3(0, y, z), green)
	_box(body, Vector3(1.7, 0.55, 0.20), Vector3(0, y, z), green)


func _church_cross_icon(body: Node3D, size: Vector3) -> void:
	var z := size.z * 0.5 + 0.1
	var y := size.y - 1.2
	var gold := Color(0.94, 0.82, 0.28)
	_box(body, Vector3(0.30, 2.2, 0.16), Vector3(0, y, z), gold)
	_box(body, Vector3(1.30, 0.30, 0.16), Vector3(0, y + 0.45, z), gold)


func _baguette(body: Node3D, size: Vector3) -> void:
	var z := size.z * 0.5 + 0.12
	var y := size.y - 1.2
	var tilt := PI * 0.25   # 45 degrees
	var m := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.50
	cap.height = 3.0
	m.mesh = cap
	m.material_override = _mat(Color(0.82, 0.64, 0.30))
	m.position = Vector3(0, y, z)
	m.rotation.z = tilt
	m.scale = Vector3(1.0, 1.0, 0.35)
	body.add_child(m)
	for i in 3:
		var t := -0.72 + i * 0.72
		var cut := Node3D.new()
		cut.position = Vector3(-t * sin(tilt), y + t * cos(tilt), z + 0.24)
		cut.rotation.z = tilt
		body.add_child(cut)
		_box(cut, Vector3(0.44, 0.10, 0.08), Vector3(0, 0, 0), Color(0.55, 0.35, 0.14))


func _sheriff_badge(body: Node3D, size: Vector3) -> void:
	# Pushed well in front of the blue accent band (band front face is at
	# size.z*0.5 + 0.05) so the badge sits ON the strip, not behind it.
	var z := size.z * 0.5 + 0.35
	var y := size.y - 1.4
	var gold := Color(0.95, 0.78, 0.10)
	var R := 0.90              # outer tip radius
	var r := R / sqrt(3.0)     # inner hexagon radius (true hexagram proportion)

	# Single solid hexagram (Star of David): 12 alternating outer/inner vertices
	# fan-triangulated from the centre, so there are no internal seams.
	var pts: Array = []
	for k in 12:
		var ang := deg_to_rad(30.0 + k * 30.0)
		var rad: float = R if (k % 2 == 0) else r
		pts.append(Vector2(cos(ang), sin(ang)) * rad)

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var fn := Vector3(0.0, 0.0, -1.0)
	for k in 12:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[(k + 1) % 12]
		# Wind centre -> b -> a so the face normal points toward -Z (the viewer).
		verts.append_array([
			Vector3(0.0, 0.0, 0.0),
			Vector3(b.x, b.y, 0.0),
			Vector3(a.x, a.y, 0.0),
		])
		norms.append_array([fn, fn, fn])

	var arr := Array()
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = gold
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(0.0, y, z)
	body.add_child(mi)

	# Circles at the 6 outer tips â€” 25% smaller, coplanar with the star face.
	for i in 6:
		var angle := deg_to_rad(30.0 + i * 60.0)
		var cp := Node3D.new()
		cp.position = Vector3(cos(angle) * R, y + sin(angle) * R, z)
		cp.rotation.x = PI * 0.5
		body.add_child(cp)
		_cylinder(cp, 0.165, 0.16, Vector3(0.0, 0.0, 0.0), gold)


func _coffee_cup(body: Node3D, size: Vector3) -> void:
	var z      := size.z * 0.5 + 0.1
	var y      := size.y - 1.4
	var white  := Color(1.00, 1.00, 1.00)
	var dark_g := Color(0.06, 0.28, 0.18)
	var coffee := Color(0.20, 0.11, 0.05)
	var steam  := Color(0.88, 0.88, 0.90)
	# Cup body: four stacked slabs tapering inward toward the bottom.
	_box(body, Vector3(1.30, 0.43, 0.18), Vector3(0, y + 0.64, z), white)
	_box(body, Vector3(1.20, 0.43, 0.18), Vector3(0, y + 0.21, z), white)
	_box(body, Vector3(1.10, 0.43, 0.18), Vector3(0, y - 0.21, z), white)
	_box(body, Vector3(1.00, 0.44, 0.18), Vector3(0, y - 0.64, z), white)
	# Collar / rim
	_box(body, Vector3(1.50, 0.16, 0.22), Vector3(0, y + 0.85, z), dark_g)
	# Dark coffee surface near the top
	_box(body, Vector3(1.10, 0.28, 0.22), Vector3(0, y + 0.64, z + 0.02), coffee)
	# Steam wisps above the cup
	_box(body, Vector3(0.07, 0.38, 0.10), Vector3(-0.22, y + 1.12, z), steam)
	_box(body, Vector3(0.07, 0.38, 0.10), Vector3( 0.18, y + 1.22, z), steam)


func _bookstore_book(body: Node3D, size: Vector3) -> void:
	var z := size.z * 0.5 + 0.1
	var y := size.y - 1.4
	var cover := Color(0.22, 0.35, 0.62)
	var spine := Color(0.14, 0.24, 0.48)
	var page  := Color(0.96, 0.94, 0.88)
	_box(body, Vector3(0.20, 1.9, 0.18), Vector3(-0.82, y, z), spine)
	_box(body, Vector3(1.40, 1.9, 0.16), Vector3(0.12, y, z), cover)
	_box(body, Vector3(1.26, 1.72, 0.20), Vector3(0.12, y, z + 0.02), page)
	for i in 3:
		_box(body, Vector3(0.84, 0.07, 0.07),
				Vector3(0.12, y - 0.46 + i * 0.46, z + 0.12), Color(0.75, 0.75, 0.80))


func _motel_doors(body: Node3D, size: Vector3) -> void:
	var z := size.z * 0.5
	var n := 4
	for i in n:
		var x := -size.x * 0.5 + size.x * (float(i) + 0.5) / float(n)
		_box(body, Vector3(1.4, 2.3, 0.14), Vector3(x, 1.15, z + 0.08), Color(0.30, 0.25, 0.40))
		_box_mat(body, Vector3(0.9, 1.1, 0.1), Vector3(x + 1.4, 1.7, z + 0.08), _glass())


# -----------------------------------------------------------------------------
# Bespoke styles
# -----------------------------------------------------------------------------
func _build_park(body: Node3D, size: Vector3, color: Color) -> void:
	_box(body, size, Vector3(0, size.y * 0.5, 0), color)            # grass (no collision)
	_box(body, Vector3(3, 0.08, size.z), Vector3(0, size.y, 0), Color(0.72, 0.68, 0.60))
	_box(body, Vector3(size.x, 0.08, 3), Vector3(0, size.y, 0), Color(0.72, 0.68, 0.60))
	# Collision for the cross paths so the player walks on their surface.
	for path_size in [Vector3(3, 0.08, size.z), Vector3(size.x, 0.08, 3)]:
		var col   := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = path_size
		col.shape    = shape
		col.position = Vector3(0, size.y, 0)
		body.add_child(col)
	_cylinder(body, 2.2, 0.6, Vector3(0, size.y + 0.3, 0), Color(0.70, 0.70, 0.72))
	_cylinder(body, 1.9, 0.5, Vector3(0, size.y + 0.55, 0), Color(0.40, 0.65, 0.85))
	_cylinder(body, 0.25, 1.6, Vector3(0, size.y + 1.0, 0), Color(0.70, 0.70, 0.72))
	_prop_collider(Vector3(0, 0, 0), 2.3, 1.2)   # solid fountain
	for off in [Vector3(-11, 0, -8), Vector3(11, 0, -8), Vector3(-11, 0, 8), Vector3(11, 0, 8)]:
		_tree(body, off + Vector3(0, size.y, 0))
	_bench(body, Vector3(-5, size.y, 0), PI * 0.5)
	_bench(body, Vector3(5, size.y, 0), -PI * 0.5)


func _build_pool(body: Node3D, size: Vector3, deck: Color, water: Color) -> void:
	# Deck bottom pushed to y=-0.15 so it never sits coplanar with the ground plane (y=0),
	# which would cause z-fighting / shimmering on the deck surface.
	_box(body, Vector3(size.x, 0.4, size.z), Vector3(0, 0.05, 0), deck)
	_box(body, Vector3(size.x - 5, 0.25, size.z - 5), Vector3(0, 0.13, 1), water)
	_box(body, Vector3(size.x * 0.4, 3.0, 4), Vector3(-size.x * 0.25, 1.5, -size.z * 0.5 + 2), Color(0.85, 0.86, 0.88))  # changing rooms
	# A simple fence of posts around the deck.
	for i in 10:
		var t := float(i) / 9.0
		_cylinder(body, 0.1, 1.4, Vector3(-size.x * 0.5 + size.x * t, 0.7, size.z * 0.5), Color(0.7, 0.7, 0.72))


func _build_station(body: Node3D, size: Vector3, color: Color, roof: Color) -> void:
	_box(body, size, Vector3(0, size.y * 0.5, 0), color)
	_box(body, Vector3(size.x + 1.0, 0.5, size.z + 1.0), Vector3(0, size.y + 0.25, 0), roof)  # overhang roof
	# Clock tower (kept within the footprint so nothing pokes over a sidewalk).
	_box(body, Vector3(4, size.y + 6, 4), Vector3(-size.x * 0.5 + 2.5, (size.y + 6) * 0.5, 0), color.lightened(0.05))
	_cylinder(body, 1.1, 0.3, Vector3(-size.x * 0.5 + 2.5, size.y + 5.2, size.z * 0.5 - 0.6), Color(0.95, 0.95, 0.90)).rotation.x = PI * 0.5
	_windows(body, size, 1, 4)
	_door(body, size)




func _build_gas(body: Node3D, size: Vector3) -> void:
	# Grey cement ground pad.
	_box(body, Vector3(size.x, 0.08, size.z), Vector3(0, 0.04, 0), Color(0.62, 0.63, 0.64))
	# Canopy on four posts â€” raised 50 % (4.2 â†’ 6.3).
	var canopy_h := 6.3
	_box(body, Vector3(size.x, 0.5, size.z), Vector3(0, canopy_h, 0), Color(0.90, 0.90, 0.92))
	_box(body, Vector3(size.x, 0.25, size.z), Vector3(0, canopy_h - 0.3, 0), Color(0.80, 0.20, 0.20))  # trim
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cylinder(body, 0.2, canopy_h, Vector3(sx * (size.x * 0.5 - 1), canopy_h * 0.5, sz * (size.z * 0.5 - 1)), Color(0.7, 0.7, 0.72))
	# Two pumps (height doubled to 3.2).
	for sx2 in [-1.0, 1.0]:
		_box(body, Vector3(1.0, 3.2, 0.8), Vector3(sx2 * 2.5, 1.6, size.z * 0.2), Color(0.5, 0.5, 0.55))
	# A customer car parked inside the station (clear of the pumps).
	var car_pos := Vector3(0.0, 0.0, -size.z * 0.16)
	_build_vehicle(body, car_pos, 0.0, Vector3(8.4, 3.0, 3.8), Color(0.78, 0.20, 0.18), "sedan")
	var ccol := CollisionShape3D.new()
	var cshape := BoxShape3D.new()
	cshape.size = Vector3(8.4, 3.2, 3.8)
	ccol.shape = cshape
	ccol.position = car_pos + Vector3(0, 1.6, 0)
	body.add_child(ccol)


# -----------------------------------------------------------------------------
# Little props
# -----------------------------------------------------------------------------
# A simple low-poly vehicle. dims = (length, height, width); local +X is forward.
func _build_vehicle(parent: Node3D, pos: Vector3, yaw: float, dims: Vector3,
		color: Color, kind: String) -> Node3D:
	var v := Node3D.new()
	v.position = pos
	v.rotation.y = yaw
	parent.add_child(v)
	var L := dims.x
	var H := dims.y
	var W := dims.z
	var wr := H * 0.26                       # wheel radius
	var floor_y := wr * 0.9                   # underside of body
	var glass := Color(0.13, 0.15, 0.18)
	var tyre := Color(0.07, 0.07, 0.08)

	# Sedans, SUVs, and compacts get shiny metallic paint; trucks and vans stay matte.
	var shiny := kind == "sedan" or kind == "suv" or kind == "compact"

	# Lower body
	if shiny:
		_box_mat(v, Vector3(L, H * 0.5, W), Vector3(0, floor_y + H * 0.25, 0), _vpmat(color))
	else:
		_box(v, Vector3(L, H * 0.5, W), Vector3(0, floor_y + H * 0.25, 0), color)

	# Cabin / roof (shape depends on the kind)
	var cab_l := L * 0.52
	var cab_x := 0.0
	if kind == "truck":
		cab_l = L * 0.34
		cab_x = -L * 0.20
		# Open cargo bed toward the front.
		_box(v, Vector3(L * 0.44, H * 0.30, W * 0.92),
				Vector3(L * 0.24, floor_y + H * 0.18, 0), color.darkened(0.12))
	elif kind == "van":
		cab_l = L * 0.64
	elif kind == "suv":
		cab_l = L * 0.58
	var cab_y := floor_y + H * 0.5 + H * 0.22
	if shiny:
		_box_mat(v, Vector3(cab_l, H * 0.46, W * 0.9), Vector3(cab_x, cab_y, 0), _vpmat(color.lightened(0.05)))
	else:
		_box(v, Vector3(cab_l, H * 0.46, W * 0.9), Vector3(cab_x, cab_y, 0), color.lightened(0.05))
	# Window band (slightly proud so it doesn't z-fight the cabin).
	_box(v, Vector3(cab_l * 0.9, H * 0.26, W * 0.94), Vector3(cab_x, cab_y + H * 0.02, 0), glass)

	# Four wheels (axis along width).
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var wheel := _cylinder(v, wr, 0.28, Vector3(sx * L * 0.33, wr, sz * (W * 0.5 - 0.04)), tyre)
			wheel.rotation.x = PI * 0.5
	return v


func _tree(parent: Node3D, base: Vector3) -> void:
	_cylinder(parent, 0.3, 2.0, base + Vector3(0, 1.0, 0), Color(0.45, 0.30, 0.15))
	var leaves := _sphere(parent, 1.3, base + Vector3(0, 3.0, 0), Color(0.16, 0.50, 0.17))
	leaves.scale = Vector3(1.0, 1.1, 1.0)
	_prop_collider(base, 0.45, 3.0)


func _bench(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var bench := Node3D.new()
	bench.position = pos
	bench.rotation.y = yaw
	parent.add_child(bench)
	var wood := Color(0.45, 0.30, 0.18)
	_box(bench, Vector3(2.4, 0.15, 0.7), Vector3(0, 0.5, 0), wood)
	_box(bench, Vector3(2.4, 0.6, 0.12), Vector3(0, 0.85, -0.3), wood)
	_box(bench, Vector3(0.12, 0.5, 0.6), Vector3(-1.0, 0.25, 0), wood)
	_box(bench, Vector3(0.12, 0.5, 0.6), Vector3(1.0, 0.25, 0), wood)
	_prop_box(pos + Vector3(0, 0.55, 0), Vector3(2.4, 1.1, 0.8), yaw)   # solid bench


func _add_lamppost(parent: Node3D, pos: Vector3) -> void:
	_cylinder(parent, 0.12, 4.0, pos + Vector3(0, 2.0, 0), Color(0.18, 0.18, 0.20))
	var bulb := _sphere(parent, 0.28, pos + Vector3(0, 4.1, 0), Color(1.0, 0.95, 0.7))
	var m := bulb.material_override as StandardMaterial3D
	m.emission_enabled = true
	m.emission = Color(1.0, 0.92, 0.6)
	m.emission_energy_multiplier = 2.0
	_prop_collider(pos, 0.25, 4.0)


# -----------------------------------------------------------------------------
# Primitive + material helpers (shared materials via _mat cache)
# -----------------------------------------------------------------------------
func _collide(body: Node3D, size: Vector3) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position.y = size.y * 0.5
	body.add_child(col)


func _collide_gas(body: Node3D, size: Vector3) -> void:
	# Pump islands â€” height doubled to 3.2.
	for sx in [-1.0, 1.0]:
		var ps := Vector3(1.0, 3.2, 0.8)
		var pc := CollisionShape3D.new()
		var pb := BoxShape3D.new()
		pb.size = ps
		pc.shape = pb
		pc.position = Vector3(sx * 2.5, ps.y * 0.5, size.z * 0.2)
		body.add_child(pc)
	# Canopy posts â€” four cylinders, matching _build_gas positions exactly.
	var canopy_h := 6.3
	for sx2 in [-1.0, 1.0]:
		for sz2 in [-1.0, 1.0]:
			var cc := CollisionShape3D.new()
			var cs := CylinderShape3D.new()
			cs.radius = 0.2
			cs.height = canopy_h
			cc.shape = cs
			cc.position = Vector3(sx2 * (size.x * 0.5 - 1.0), canopy_h * 0.5, sz2 * (size.z * 0.5 - 1.0))
			body.add_child(cc)


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	if _brick_wall_color != Color.TRANSPARENT and _brick_wall_color.is_equal_approx(color):
		return _box_mat(parent, size, pos, _bmat(color))
	if _brick_light_wall_color != Color.TRANSPARENT and _brick_light_wall_color.is_equal_approx(color):
		return _box_mat(parent, size, pos, _bmat_light(color))
	if _brick_white_wall_color != Color.TRANSPARENT and _brick_white_wall_color.is_equal_approx(color):
		return _box_mat(parent, size, pos, _bmat_white(color))
	if _siding_wall_color != Color.TRANSPARENT and _siding_wall_color.is_equal_approx(color):
		return _box_mat(parent, size, pos, _smat(color))
	if _speckle_wall_color != Color.TRANSPARENT and _speckle_wall_color.is_equal_approx(color):
		return _box_mat(parent, size, pos, _spmat(color))
	if _grass_wall_color != Color.TRANSPARENT and _grass_wall_color.is_equal_approx(color):
		return _box_mat(parent, size, pos, _gmat(color))
	return _box_mat(parent, size, pos, _mat(color))


func _box_mat(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.position = pos
	m.material_override = material
	parent.add_child(m)
	return m


func _cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	m.mesh = mesh
	m.position = pos
	m.material_override = _mat(color)
	parent.add_child(m)
	return m


func _sphere(parent: Node3D, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	m.mesh = mesh
	m.position = pos
	m.material_override = _mat(color)
	parent.add_child(m)
	return m


func _prism(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.position = pos
	m.material_override = _mat(color)
	parent.add_child(m)
	return m


func _prism_mat(parent: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.position = pos
	m.material_override = mat
	parent.add_child(m)
	return m


func _slab(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	return _box(parent, size, pos, color)


func _glass(color: Color = Color(0.55, 0.72, 0.90)) -> StandardMaterial3D:
	if not _glass_cache.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.metallic = 0.5
		mat.roughness = 0.08
		mat.emission_enabled = true
		mat.emission = color.darkened(0.30)
		mat.emission_energy_multiplier = 0.35
		_glass_cache[color] = mat
	return _glass_cache[color]


func _mat(color: Color) -> StandardMaterial3D:
	if not _mat_cache.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		_mat_cache[color] = mat
	return _mat_cache[color]


func _bmat(color: Color) -> StandardMaterial3D:
	if not _brick_cache.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.albedo_texture = _brick_tex
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(0.22, 0.17, 0.22)
		mat.roughness = 0.45
		_brick_cache[color] = mat
	return _brick_cache[color]


func _bmat_light(color: Color) -> StandardMaterial3D:
	if not _brick_light_cache.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.albedo_texture = _brick_light_tex
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(0.22, 0.17, 0.22)
		mat.roughness = 0.40
		_brick_light_cache[color] = mat
	return _brick_light_cache[color]


func _bmat_white(color: Color) -> StandardMaterial3D:
	if not _brick_white_cache.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.albedo_texture = _brick_white_tex
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(0.22, 0.17, 0.22)
		mat.roughness = 0.40
		_brick_white_cache[color] = mat
	return _brick_white_cache[color]


func _spmat(color: Color) -> StandardMaterial3D:
	if not _speckle_cache.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.albedo_texture = _speckle_tex
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(0.30, 0.30, 0.30)
		mat.roughness = 0.84
		_speckle_cache[color] = mat
	return _speckle_cache[color]


func _gmat(color: Color) -> StandardMaterial3D:
	if not _grass_cache.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.albedo_texture = _grass_tex
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(0.12, 0.12, 0.12)
		mat.roughness = 0.97
		_grass_cache[color] = mat
	return _grass_cache[color]


func _sroof_mat(color: Color) -> StandardMaterial3D:
	if not _shingle_cache.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.albedo_texture = _shingle_tex
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(0.28, 0.20, 0.28)
		mat.roughness = 0.88
		_shingle_cache[color] = mat
	return _shingle_cache[color]


func _frmat(color: Color) -> StandardMaterial3D:
	if not _flat_roof_cache.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.albedo_texture = _gravel_tex
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(0.20, 0.20, 0.20)
		mat.roughness = 0.94
		_flat_roof_cache[color] = mat
	return _flat_roof_cache[color]


func _ripple_mat(color: Color) -> StandardMaterial3D:
	if not _ripple_cache.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.albedo_texture = _ripple_tex
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(0.18, 0.18, 0.18)
		mat.roughness = 0.06
		mat.metallic = 0.18
		_ripple_cache[color] = mat
	return _ripple_cache[color]


func _vpmat(color: Color) -> StandardMaterial3D:
	if not _vpaint_cache.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.12
		mat.metallic  = 0.35
		_vpaint_cache[color] = mat
	return _vpaint_cache[color]


func _smat(color: Color) -> StandardMaterial3D:
	if not _siding_cache.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.albedo_texture = _siding_tex
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(0.22, 0.17, 0.22)
		mat.roughness = 0.40
		_siding_cache[color] = mat
	return _siding_cache[color]


func _tune_materials() -> void:
	for color: Color in _mat_cache:
		var mat: StandardMaterial3D = _mat_cache[color]
		if color == ASPHALT:
			mat.roughness = 0.96
		elif color == SIDEWALK:
			mat.roughness = 0.88
		elif color.is_equal_approx(Color(0.56, 0.54, 0.52)):   # curb
			mat.roughness = 0.88
		elif color.is_equal_approx(Color(0.08, 0.38, 0.92)):   # ocean
			mat.roughness = 0.03
			mat.metallic  = 0.0
		elif color.is_equal_approx(Color(0.40, 0.65, 0.85)):   # fountain water
			mat.roughness = 0.08
			mat.metallic  = 0.15
		elif color.is_equal_approx(Color(0.80, 0.74, 0.52)):   # wet sand
			mat.roughness = 0.42
		elif color.is_equal_approx(Color(0.93, 0.84, 0.60)):   # dry sand
			mat.roughness = 0.94
		elif color.is_equal_approx(Color(0.40, 0.58, 0.33)):   # terrain grass
			mat.roughness = 0.97
		elif color.is_equal_approx(Color(0.30, 0.55, 0.27)):   # park grass
			mat.roughness = 0.97
		elif color.is_equal_approx(Color(0.16, 0.50, 0.17)):   # tree leaves
			mat.roughness = 0.93
		elif color.is_equal_approx(Color(0.45, 0.30, 0.15)):   # tree bark
			mat.roughness = 0.97
		elif color.is_equal_approx(Color(0.52, 0.54, 0.58)):   # steel rail
			mat.roughness = 0.28
			mat.metallic  = 0.80
		elif color.is_equal_approx(Color(0.70, 0.70, 0.72)):   # fountain stone / pillar
			mat.roughness = 0.76
		elif color.is_equal_approx(Color(0.82, 0.80, 0.76)):   # platform concrete
			mat.roughness = 0.90
		else:
			mat.roughness = 0.35   # plastic sheen for Lego low-poly look


func _build_woods_fog() -> void:
	# Layered semi-transparent slabs simulate ground-level haze in the woods.
	# Compatibility renderer has no FogVolume, so this is baked-geometry-free fog
	# placed directly under the scene root (not baked with Terrain).
	for i in 4:
		var xpos: float = -158.0 - i * 10.0
		var alpha: float = 0.12 + i * 0.05
		var fog_mat := StandardMaterial3D.new()
		fog_mat.albedo_color = Color(0.74, 0.78, 0.76, alpha)
		fog_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fog_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fog_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.1, 8.0, 280.0)
		mi.mesh = bm
		mi.material_override = fog_mat
		mi.position = Vector3(xpos, 4.0, -3.5)
		add_child(mi)


# =============================================================================
# World zone builders
# =============================================================================

func _build_beach(terrain: Node3D) -> void:
	var sand      := Color(0.93, 0.84, 0.60)
	var wet_sand  := Color(0.80, 0.74, 0.52)
	var ocean     := Color(0.08, 0.38, 0.92)

	# Sand starts at z=141 (road/sidewalk clipped here). Centre at 166, length 50.
	# Widths capped at 396 so nothing hangs past the ground plane's x=Â±198 edge.
	# Dry sand strip (z=141 â†’ z=191)
	_box(terrain, Vector3(396, 0.30, 50), Vector3(0, -0.13, 166.0), sand)
	# Wet sand at waterline (z=191 â†’ z=201)
	_box(terrain, Vector3(396, 0.20, 10), Vector3(0, -0.09, 196.0), wet_sand)
	# Ocean (z=198 â†’ z=318, mostly beyond player reach but looks infinite)
	_box(terrain, Vector3(396, 0.15, 120), Vector3(0, -0.08, 258.0), ocean)

	# Barrier further into the ocean â€” player can now wade into the shallows.
	var water_wall := StaticBody3D.new()
	water_wall.name = "WaterBarrier"
	var wc := CollisionShape3D.new()
	var ws := BoxShape3D.new()
	ws.size = Vector3(400, 4.0, 1.0)
	wc.shape = ws
	wc.position = Vector3(0, 2.0, 203.0)
	water_wall.add_child(wc)
	add_child(water_wall)

	# Ramp from beach (z=198, y=0) down into water (z=204, y=-0.35) so the
	# player can walk in and back out without getting stuck on a ledge.
	# Box center y solved so the top face hits y=0 at the z=198 end.
	var wr := StaticBody3D.new()
	wr.name = "WaterRamp"
	var wrc := CollisionShape3D.new()
	var wrs := BoxShape3D.new()
	wrs.size = Vector3(400, 0.4, 6.2)
	wrc.shape = wrs
	wrc.position = Vector3(0, -0.380, 201.0)
	wrc.rotation.x = atan2(0.35, 6.0)   # positive: +Z end tilts down
	wr.add_child(wrc)
	add_child(wr)

	# Flat floor at y=-0.35 for the deeper water zone (past the ramp).
	var water_floor := StaticBody3D.new()
	water_floor.name = "WaterFloor"
	var wfc := CollisionShape3D.new()
	var wfb := BoxShape3D.new()
	wfb.size = Vector3(400, 1.0, 14.0)
	wfc.shape = wfb
	wfc.position = Vector3(0, -0.85, 206.0)  # top at y=-0.35
	water_floor.add_child(wfc)
	add_child(water_floor)

	# One-shot trigger zone: entering the water makes Matsubara kun react.
	var water_trigger := Area3D.new()
	water_trigger.name = "WaterTrigger"
	var wtc := CollisionShape3D.new()
	var wts := BoxShape3D.new()
	wts.size = Vector3(400, 4.0, 12.0)
	wtc.shape = wts
	wtc.position = Vector3(0, 2.0, 197.0)
	water_trigger.add_child(wtc)
	add_child(water_trigger)
	water_trigger.body_entered.connect(_on_water_entered)

	# Palm trees scattered along the sand
	for data in [
		[-82.0, 152.0], [-55.0, 165.0], [-20.0, 156.0],
		[15.0, 173.0],  [48.0, 160.0],  [78.0, 149.0],
	]:
		_palm(terrain, Vector3(data[0], 0.3, data[1]))

	# Benches sit on the southernmost sidewalk (center zâ‰ˆ140.6) facing the beach.
	for xi in [-100.0, -60.0, -20.0, 20.0, 60.0, 100.0]:
		_bench(terrain, Vector3(xi, 0.1, 140.5), 0.0)


func _on_water_entered(body: Node3D) -> void:
	if _water_warned or not (body is CharacterBody3D):
		return
	_water_warned = true
	var line := "I can't swim!  I am scared!"
	_dialogue.show_text("Matsubara kun", line)
	_dismiss_water_dialogue()


func _dismiss_water_dialogue() -> void:
	var timer := get_tree().create_timer(4.0)
	while timer.time_left > 0.0:
		if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel"):
			break
		await get_tree().process_frame
	_dialogue.hide_dialogue()


func _palm(parent: Node3D, base: Vector3) -> void:
	var trunk := Color(0.55, 0.40, 0.22)
	var frond  := Color(0.20, 0.54, 0.14)
	_cylinder(parent, 0.22, 5.0, base + Vector3(0, 2.5, 0), trunk)
	# Six radiating fronds
	for i in 6:
		var a: float = i * TAU / 6.0
		var ox := cos(a) * 1.2
		var oz := sin(a) * 1.2
		_box(parent, Vector3(1.2, 0.10, 3.2), base + Vector3(ox, 5.0, oz), frond)
	_prop_collider(base, 0.28, 5.0)


func _setup_train_schedule() -> void:
	# First train arrives 20 s after the intro; subsequent ones every 75â€“95 s.
	var t := get_tree().create_timer(20.0)
	t.timeout.connect(_spawn_train)


func _spawn_train() -> void:
	var tr := Train.new()
	add_child(tr)
	var interval := 75.0 + randf() * 20.0
	var t := get_tree().create_timer(interval)
	t.timeout.connect(_spawn_train)


func _build_train_tracks(terrain: Node3D) -> void:
	var ballast  := Color(0.54, 0.52, 0.50)
	var rail     := Color(0.52, 0.54, 0.58)
	var tie      := Color(0.42, 0.30, 0.18)
	var platform := Color(0.82, 0.80, 0.76)
	var z_tr     := -150.0
	var span     := 396.0   # trimmed to stay within ground plane x=Â±198

	# Ballast bed
	_box(terrain, Vector3(span, 0.30, 5.0), Vector3(0, -0.04, z_tr), ballast)
	# Rails (decorative only â€” no collision, player can walk through)
	_box(terrain, Vector3(span, 0.18, 0.22), Vector3(0, 0.22, z_tr - 1.0), rail)
	_box(terrain, Vector3(span, 0.18, 0.22), Vector3(0, 0.22, z_tr + 1.0), rail)
	# Ties (sleepers) every 2 units
	var tx := -196.0
	while tx <= 196.0:
		_box(terrain, Vector3(2.8, 0.15, 2.6), Vector3(tx, 0.10, z_tr), tie)
		tx += 2.6

	# Station platform (south/town side of tracks, accessible to player)
	_box(terrain, Vector3(28, 0.85, 7), Vector3(0, 0.42, z_tr + 6.5), platform)
	# Solid collision for the platform slab (baked terrain has no physics by default).
	_prop_box(Vector3(0, 0.425, z_tr + 6.5), Vector3(28, 0.85, 7), 0.0)
	# Steps on the EAST side of the platform (east face at x=+14, stepping outward).
	# Each step gets a matching _prop_box so the player can stand on them.
	for i in 3:
		var step_h := 0.85 * (3 - i) / 3.0
		var step_x := 14.0 + i * 0.8 + 0.4
		var step_c := Vector3(step_x, step_h * 0.5, z_tr + 6.5)
		_box(terrain, Vector3(0.8, step_h, 6.0), step_c, platform)
		_prop_box(step_c, Vector3(0.8, step_h, 6.0), 0.0)
	# Invisible ramp so CharacterBody3D can walk up the step risers.
	# Spans x=18.0 â†’ x=14.8, rising from y=0 to y=0.85.  At each riser face the
	# player's feet are already above the riser height, so they glide up the slope
	# while the visual steps remain underneath.
	var r_run  := 3.2       # 18.0 - 14.8
	var r_rise := 0.85
	var r_len  := sqrt(r_run * r_run + r_rise * r_rise)
	var r_ang  := atan2(r_rise, r_run)
	var ramp   := StaticBody3D.new()
	ramp.name  = "StepsRamp"
	var rc     := CollisionShape3D.new()
	var rs     := BoxShape3D.new()
	rs.size    = Vector3(r_len, 0.30, 6.0)
	rc.shape   = rs
	rc.position = Vector3(16.4 - 0.15 * sin(r_ang), 0.425 - 0.15 * cos(r_ang), z_tr + 6.5)
	rc.rotation.z = -r_ang
	ramp.add_child(rc)
	add_child(ramp)
	# Canopy roof â€” raised to y=4.8 so it clears the player's head comfortably.
	var canopy_y  := 4.8
	var canopy_sz := Vector3(30, 0.30, 8)
	var canopy_p  := Vector3(0, canopy_y, z_tr + 6.5)
	_box(terrain, canopy_sz, canopy_p, Color(0.35, 0.28, 0.60))
	_prop_box(canopy_p, canopy_sz, 0.0)   # solid roof â€” player can't pass through
	# Canopy pillars â€” height matches new roof bottom
	for px in [-13.0, 13.0]:
		var pil_h := canopy_y - 0.15   # top of pillar meets underside of roof
		var pil_p := Vector3(px, pil_h * 0.5, z_tr + 6.5)
		_box(terrain, Vector3(0.45, pil_h, 0.45), pil_p, Color(0.75, 0.74, 0.72))
		_prop_collider(Vector3(px, 0.0, z_tr + 6.5), 0.28, pil_h)

	# Impassable collision barrier spanning the full track + ballast zone
	# (z = -147.5 to -153.0) so the player cannot enter from the platform edge.
	var barrier := StaticBody3D.new()
	barrier.name = "TrackBarrier"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(span, 3.5, 5.5)
	col.shape = shape
	col.position = Vector3(0, 1.75, z_tr - 0.25)
	barrier.add_child(col)
	add_child(barrier)


func _build_woods(terrain: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# Trees start at x=-150 (western sidewalk outer edge is ~x=-141.7; Â±3 jitter
	# keeps everything safely west of the road). Z capped at 133 so no tree lands
	# on the southern sidewalk or beach.
	var col_x := -150.0
	while col_x >= -200.0:
		var row_z := -140.0
		while row_z <= 133.0:
			var jx: float = rng.randf_range(-3.0, 3.0)
			var jz: float = rng.randf_range(-3.0, 3.0)
			_tree(terrain, Vector3(col_x + jx, 0.0, row_z + jz))
			row_z += 10.0
		col_x -= 14.0

	# Invisible wall at x=-178. Extends south from z=-160 to z=203 so it joins
	# the water barrier at the beach, sealing the west side completely.
	# Span = 203 - (-160) = 363, centre = (-160 + 203) / 2 = 21.5.
	var barrier := StaticBody3D.new()
	barrier.name = "WoodsBarrier"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, 8.0, 363.0)
	col.shape = shape
	col.position = Vector3(-178.0, 4.0, 21.5)
	barrier.add_child(col)
	add_child(barrier)


func _build_mall(terrain: Node3D) -> void:
	var lot_asphalt := Color(0.20, 0.20, 0.23)
	var stripe      := Color(0.85, 0.85, 0.85)
	var mall_wall   := Color(0.88, 0.86, 0.84)
	var mall_accent := Color(0.70, 0.68, 0.66)
	var sign_red    := Color(0.84, 0.18, 0.18)

	# Layout (east of town, east sidewalk outer edge ~x=141.7, barrier at x=143):
	#   Mall       x=144 â†’ x=180  z=-45 â†’ z=-5   (west face at x=144, entrance faces sidewalk)
	#   Parking lot x=144 â†’ x=180  z=-5  â†’ z=65  (touches mall south face, no gap)

	# --- Continuous east sidewalk -------------------------------------------------
	# Fill all E-W-road gaps in the east N-S sidewalk (xâ‰ˆ140.6) except z=27, which
	# becomes the parking-lot entrance driveway.
	var sw_x := 135.0 + SW_OFF   # sidewalk centre = 140.6
	for gap_z in [-135.0, -81.0, -27.0, 81.0, 135.0]:   # z=27 left open for entrance
		_box(terrain, Vector3(SW_W, 0.10, ROAD_W),
				Vector3(sw_x, 0.0, gap_z), SIDEWALK)
	# Entrance driveway at z=27: asphalt from east end of road (x=135) to lot edge (x=144).
	_box(terrain, Vector3(9.0, 0.11, ROAD_W), Vector3(139.5, 0.0, 27.0), lot_asphalt)
	# -------------------------------------------------------------------------------

	# Parking lot: south face of mall at z=-7 (mall center z=-27, half-depth=20).
	# Lot spans z=-7 to z=65, center z=29, depth 72.
	_box(terrain, Vector3(36, 0.06, 72), Vector3(162, 0.0, 29), lot_asphalt)
	for zi in range(6):
		_box(terrain, Vector3(32, 0.08, 0.22), Vector3(162, 0.05, 1.0 + zi * 12.0), stripe)

	# Mall building â€” StaticBody3D so the player collides with it.
	# Centre at (162, 0, -27): west face at x=144 (entrance), aligned with z=-27 E-W road.
	var mall := StaticBody3D.new()
	mall.name = "Mall"
	mall.position = Vector3(162, 0, -27)
	add_child(mall)

	var mw := Vector3(36, 10, 40)   # east-west width, height, north-south depth
	_collide(mall, mw)
	_box(mall, mw, Vector3(0, mw.y * 0.5, 0), mall_wall)
	# Decorative accent band near top
	_box(mall, Vector3(mw.x + 0.2, 1.5, mw.z + 0.2), Vector3(0, mw.y - 0.75, 0), mall_accent)
	# Glass windows on the WEST face (local x = -mw.x/2 = -18), facing the sidewalk
	for c2 in range(4):
		for r2 in range(2):
			_box_mat(mall, Vector3(0.2, 3.2, 5.0),
					Vector3(-mw.x * 0.5 + 0.15, 2.5 + r2 * 4.0, -13.5 + c2 * 9.0),
					_glass())
	# Entrance on west face â€” framed double door with overhead canopy.
	var door_dark  := Color(0.22, 0.20, 0.18)   # dark charcoal door panels
	var frame_col  := Color(0.60, 0.58, 0.54)   # light concrete frame / pilasters
	var wx := -mw.x * 0.5   # local x of west face = -18
	# Side pilasters flanking the 4-unit opening
	_box(mall, Vector3(0.35, 3.8, 0.4), Vector3(wx + 0.17, 1.9, -2.2), frame_col)
	_box(mall, Vector3(0.35, 3.8, 0.4), Vector3(wx + 0.17, 1.9,  2.2), frame_col)
	# Lintel spanning the opening
	_box(mall, Vector3(0.35, 0.55, 4.8), Vector3(wx + 0.17, 3.73, 0), frame_col)
	# Left door panel â€” glass to eliminate z-fighting with wall behind
	_box_mat(mall, Vector3(0.18, 3.1, 1.75), Vector3(wx + 0.09, 1.55, -0.9), _glass())
	# Right door panel
	_box_mat(mall, Vector3(0.18, 3.1, 1.75), Vector3(wx + 0.09, 1.55,  0.9), _glass())
	# Thin centre divider strip
	_box(mall, Vector3(0.22, 3.1, 0.12), Vector3(wx + 0.11, 1.55, 0), mall_wall)
	# Canopy protruding from above the door
	_box(mall, Vector3(0.9, 0.18, 5.0), Vector3(wx - 0.27, 4.0, 0), mall_accent)
	# Rooftop sign on west face
	_box(mall, Vector3(0.4, 1.8, 20.0), Vector3(-mw.x * 0.5, mw.y + 0.9, 0), sign_red)
	# "Seven Park" text on the sign â€” hidden until the mall is discovered.
	var sign_lbl := Label3D.new()
	sign_lbl.text = "Seven Park Mall"
	sign_lbl.font_size = 160
	sign_lbl.pixel_size = 0.009
	sign_lbl.modulate = Color(1.0, 1.0, 1.0)
	sign_lbl.outline_size = 10
	sign_lbl.outline_modulate = Color(0.25, 0.03, 0.03)
	sign_lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sign_lbl.no_depth_test = false
	sign_lbl.position = Vector3(-mw.x * 0.5 - 0.22, mw.y + 0.9, 0.0)
	sign_lbl.rotation.y = -PI * 0.5
	sign_lbl.visible = false
	mall.add_child(sign_lbl)
	_icon_nodes["Shopping Mall"] = sign_lbl

	# Lampposts flanking the mall entrance and along the parking lot
	for lz in [-35.0, -19.0]:
		_add_lamppost(terrain, Vector3(143.5, 0.0, lz))   # beside west entrance
	for lx in [150.0, 162.0, 174.0]:
		_add_lamppost(terrain, Vector3(lx, 0.0, 35.0))    # mid lot

	# Parked vehicles of varied size, type and colour filling the lot.
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var v_colors := [
		Color(0.78, 0.20, 0.18), Color(0.18, 0.34, 0.66), Color(0.92, 0.92, 0.93),
		Color(0.10, 0.11, 0.13), Color(0.86, 0.78, 0.18), Color(0.20, 0.48, 0.30),
		Color(0.55, 0.57, 0.62), Color(0.82, 0.46, 0.14), Color(0.40, 0.22, 0.55)]
	var v_kinds := ["sedan", "suv", "van", "truck", "compact"]
	var v_dims := {
		"sedan": Vector3(4.2, 1.5, 1.9), "suv": Vector3(4.5, 1.95, 2.0),
		"van": Vector3(4.9, 2.15, 2.05), "truck": Vector3(5.1, 1.8, 2.0),
		"compact": Vector3(3.4, 1.45, 1.8)}
	var rows := [6.0, 18.0, 45.0, 57.0]
	var cols := [148.0, 152.5, 157.0, 167.0, 171.5, 176.0]
	for rz in rows:
		var face: float = PI * 0.5 if rz < 31.0 else -PI * 0.5
		for cxp in cols:
			if rng.randf() < 0.22:
				continue   # leave some spaces empty
			var kind: String = v_kinds[rng.randi() % v_kinds.size()]
			var d: Vector3 = (v_dims[kind] as Vector3) * 1.5 * rng.randf_range(0.95, 1.08)
			var col: Color = v_colors[rng.randi() % v_colors.size()]
			_build_vehicle(terrain, Vector3(cxp, 0.0, rz), face, d, col, kind)
			_prop_box(Vector3(cxp, 0.8, rz), Vector3(d.x, 1.7, d.z), face)

