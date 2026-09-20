extends CanvasLayer
## Time-warp level transitions (autoload).
##
## GameManager.load_level() hands the next level to warp_to_scene(). The game
## is paused for the whole transition, and two beats play over it:
##
##   TRAVEL  the warp and the loading screen run together. The current frame
##           is sucked into a swirling time tunnel (WARP_SECONDS) while the
##           loading card is already up: the player binary-searching a
##           timeline of years for the next level's time period
##           (time_search_bar.gd), finishing at
##           LOADING_SECONDS. Once the tunnel covers the screen, the new
##           level is swapped in behind it.
##   REVEAL  the tunnel collapses and the new level flies back out of it
##
## The card is built here in code so there is no scene to keep in sync.
## Deaths (GameManager.game_over) deliberately skip all of this.
##
## The tunnel is drawn in two passes, which is what keeps it affordable:
##
##   time_tunnel.gdshader  draws the tunnel on its own into _tunnel_viewport,
##                         which is one texel per pixel-art cell (a quarter of
##                         the game's resolution in area) and is redrawn only
##                         when the frame clock ticks over, TUNNEL_FPS times a
##                         second. All the atan/hash/sin work lives here.
##   time_warp.gdshader    composites that over the live screen on a
##                         full-screen ColorRect above the HUD. Inside the
##                         portal that is a single texture read.
##
## Drawing it in one full-resolution pass instead costs upwards of sixty times
## as many of those samples a second, for a picture that is identical because
## every value is constant across a cell anyway.
##
## The card is a plain Control on this layer: its text renders at the window's
## resolution, like the HUD's, while the search bar underneath keeps to whole
## game pixels so it stays pixel art (see time_search_bar.gd).

## How long the level takes to be pulled into the tunnel. Must not be longer
## than LOADING_SECONDS.
const WARP_SECONDS := 1.4
## How long the loading screen runs, starting together with the warp.
const LOADING_SECONDS := 3.0
## How long the tunnel takes to collapse and reveal the new level.
const REVEAL_SECONDS := 0.8
## The loading card steps in over this long at the start of the warp.
const CARD_FADE_IN_SECONDS := 0.35

const SHADER := preload("res://shaders/time_warp.gdshader")
const TUNNEL_SHADER := preload("res://shaders/time_tunnel.gdshader")
const SearchBar := preload("res://scripts/ui/time_search_bar.gd")

## Game pixels to a tunnel cell. 2 puts the tunnel on a 320x180 grid: chunkier
## than the sprites, so it reads as a backdrop rather than competing with them.
const TUNNEL_PIXEL := 2.0
## Steps of tunnel motion per second. The tunnel is a hand-animated thing on a
## frame clock, like the slash and the puff, so this is both how fast it moves
## and how often its viewport is redrawn.
const TUNNEL_FPS := 12.0
## Steps the card fades in and out in.
const CARD_FADE_STEPS := 5.0

## Tunnel speed multipliers: fast at the peak of the warp, calmer once it
## settles.
const SPEED_SLOW := 0.6
const SPEED_PEAK := 3.0
const SPEED_LOADING := 1.0

const GOLD := Color(1.0, 0.9, 0.62)
const CYAN := Color(0.55, 0.9, 1.0)

enum Phase { IDLE, TRAVEL, REVEAL }

var _phase := Phase.IDLE
var _phase_time := 0.0
var _anim_time := 0.0
var _speed := SPEED_SLOW
var _scene_path := ""
var _swapped := false

## The tunnel, drawn small and redrawn on the frame clock.
var _tunnel_viewport: SubViewport
var _tunnel_material: ShaderMaterial
## Which tunnel frame the viewport is currently holding, -1 for none.
var _tunnel_frame := -1
## The grid the tunnel is currently sized to, zero until the first sync.
var _cells := Vector2i.ZERO

var _warp_rect: ColorRect
var _material: ShaderMaterial
var _card: Control
var _audio_player: AudioStreamPlayer
var _title: Label
var _era: Label
var _status: Label
var _past: Label
var _future: Label
var _search: SearchBar


func _ready() -> void:
	# Above the HUD (layer 10), and keeps animating while the game is paused.
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _process(delta: float) -> void:
	if _phase == Phase.IDLE:
		return
	_phase_time += delta
	_sync_resolution()

	match _phase:
		Phase.TRAVEL:
			var warp_t := clampf(_phase_time / WARP_SECONDS, 0.0, 1.0)
			var progress := clampf(_phase_time / LOADING_SECONDS, 0.0, 1.0)
			_set_warp(smoothstep(0.0, 1.0, warp_t))
			# Speed climbs through the warp, then settles into a cruise.
			var settle := clampf((_phase_time - WARP_SECONDS) / 0.6, 0.0, 1.0)
			_speed = lerpf(lerpf(SPEED_SLOW, SPEED_PEAK, warp_t), SPEED_LOADING, settle)
			_set_card_fade(clampf(_phase_time / CARD_FADE_IN_SECONDS, 0.0, 1.0))
			_search.set_progress(progress, _phase_time)
			_status.text = _search.status
			# Fully covered: only now is it safe to swap the level underneath.
			if not _swapped and warp_t >= 1.0 and _scene_is_ready():
				_swap_scene()
				_swapped = true
			if progress >= 1.0 and _swapped:
				_begin_reveal()
		Phase.REVEAL:
			var t := clampf(_phase_time / REVEAL_SECONDS, 0.0, 1.0)
			# Accelerate back out of the cruise as the tunnel collapses.
			_speed = lerpf(SPEED_LOADING, SPEED_PEAK, clampf(_phase_time / 0.3, 0.0, 1.0))
			_set_warp(1.0 - smoothstep(0.0, 1.0, t))
			_set_card_fade(1.0 - clampf(_phase_time / 0.25, 0.0, 1.0))
			if t >= 1.0:
				_finish()

	_anim_time += delta * _speed
	_step_tunnel()


## Warp out of the current level while the loading screen runs for
## LOADING_SECONDS, then reveal `scene_path`. `title` is the big text on the
## loading card. Ignored if a transition is already running.
func warp_to_scene(scene_path: String, title: String = "") -> void:
	# Deferred: this is usually called from a physics callback (touching the
	# exit door), where pausing the tree isn't safe.
	_begin_warp.call_deferred(scene_path, title)


func is_active() -> bool:
	return _phase != Phase.IDLE


# --- Phases -----------------------------------------------------------------

func _begin_warp(scene_path: String, title: String) -> void:
	if _phase != Phase.IDLE:
		return
	# A parry time stop shouldn't leave the screen negative under the tunnel.
	TimeStop.stop()

	_scene_path = scene_path
	_swapped = false
	# Start reading the next level now so it's ready by the time the warp ends.
	ResourceLoader.load_threaded_request(scene_path)

	_title.text = title
	# The timeline runs through history: search from the year we're leaving
	# to the year we're heading for.
	var to_index := GameManager.LEVELS.find(scene_path)
	_search.setup(GameManager.LEVEL_YEARS, GameManager.current_level_index, to_index)
	_status.text = _search.status
	_era.text = "DESTINATION  %s" % GameManager.level_year_text(to_index)
	_past.text = "<< %d" % _search.min_year()
	_future.text = "%d >>" % _search.max_year()
	# The clock's hands turn clockwise when travelling forward in time, and
	# counter-clockwise when heading back into the past.
	_tunnel_material.set_shader_parameter("clock_spin", 1.0 if _search.to_future else -1.0)
	_anim_time = 0.0
	_speed = SPEED_SLOW
	_set_card_fade(0.0)
	_card.visible = true
	_set_warp(0.0)
	_warp_rect.visible = true
	_sync_resolution()
	# Frame -1 so the first tick always draws one, spin included.
	_tunnel_frame = -1
	_step_tunnel()

	get_tree().paused = true
	_audio_player.play()
	
	_enter(Phase.TRAVEL)


func _begin_reveal() -> void:
	_search.set_progress(1.0, LOADING_SECONDS)
	_status.text = _search.status
	_enter(Phase.REVEAL)


func _finish() -> void:
	_phase = Phase.IDLE
	_warp_rect.visible = false
	_card.visible = false
	# Nothing reads the tunnel until the next warp.
	_tunnel_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	get_tree().paused = false


func _enter(phase: Phase) -> void:
	_phase = phase
	_phase_time = 0.0


# --- Scene swap -------------------------------------------------------------

func _scene_is_ready() -> bool:
	return ResourceLoader.load_threaded_get_status(_scene_path) != ResourceLoader.THREAD_LOAD_IN_PROGRESS


## The new level's Level._ready() registers it with GameManager, exactly as
## with a plain change_scene_to_file. The tree is paused, so nothing in it
## moves until _finish().
func _swap_scene() -> void:
	var packed := ResourceLoader.load_threaded_get(_scene_path) as PackedScene
	if packed != null:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(_scene_path)


# --- Visuals ----------------------------------------------------------------

func _set_warp(amount: float) -> void:
	_material.set_shader_parameter("warp_amount", amount)


## How much of the card is showing, 0..1, in CARD_FADE_STEPS jumps rather than
## a slide -- the same frame clock the rest of the transition runs on.
func _set_card_fade(amount: float) -> void:
	var steps := floorf(clampf(amount, 0.0, 1.0) * CARD_FADE_STEPS)
	_card.modulate.a = minf(steps / (CARD_FADE_STEPS - 1.0), 1.0)


## Which tunnel frame we are on. When it ticks over, the viewport is given that
## frame's time and asked for exactly one redraw -- so the expensive shader
## runs TUNNEL_FPS times a second instead of once per displayed frame.
func _step_tunnel() -> void:
	var frame := int(_anim_time * TUNNEL_FPS)
	if frame == _tunnel_frame:
		return
	_tunnel_frame = frame
	_tunnel_material.set_shader_parameter("anim_time", float(frame) / TUNNEL_FPS)
	_tunnel_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Keep the tunnel's grid matching the game's own resolution. The window can be
## resized mid-run and the aspect is "expand", so this isn't a constant -- but
## it only changes when the window does, so nothing happens on a normal frame.
func _sync_resolution() -> void:
	# A full-rect Control on this layer is sized in game pixels, not window
	# pixels, which is the number the grid is measured in.
	var game_size := _warp_rect.size
	if game_size.x < 4.0 or game_size.y < 4.0:
		return
	var grid := (game_size / TUNNEL_PIXEL).floor()
	var cells := Vector2i(maxi(int(grid.x), 1), maxi(int(grid.y), 1))
	if cells == _cells:
		return
	_cells = cells
	_tunnel_viewport.size = cells
	_tunnel_material.set_shader_parameter("grid", Vector2(cells))
	_material.set_shader_parameter("tunnel_grid", Vector2(cells))
	# The tunnel is the wrong size until it is redrawn, and the composite is
	# about to read it.
	_tunnel_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _build() -> void:
	# The tunnel, drawn small. Not displayed itself -- the composite below
	# samples its texture.
	_tunnel_viewport = SubViewport.new()
	_tunnel_viewport.disable_3d = true
	_tunnel_viewport.gui_disable_input = true
	_tunnel_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_tunnel_viewport.size = Vector2i(320, 180)
	add_child(_tunnel_viewport)

	var tunnel_rect := ColorRect.new()
	tunnel_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tunnel_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tunnel_material = ShaderMaterial.new()
	_tunnel_material.shader = TUNNEL_SHADER
	tunnel_rect.material = _tunnel_material
	_tunnel_viewport.add_child(tunnel_rect)

	_warp_rect = ColorRect.new()
	_warp_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_warp_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warp_rect.visible = false
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("tunnel_texture", _tunnel_viewport.get_texture())
	_warp_rect.material = _material
	add_child(_warp_rect)

	_card = Control.new()
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	add_child(_card)

	_title = _make_label(22, GOLD)
	_anchor_top_wide(_title, 26.0, 32.0)
	_card.add_child(_title)

	# Filled in per warp: the time period this level is set in.
	_era = _make_label(9, CYAN)
	_era.text = "WARPING THROUGH TIME"
	_anchor_top_wide(_era, 60.0, 14.0)
	_card.add_child(_era)

	# The loading bar: a timeline the player binary-searches.
	_search = SearchBar.new()
	_anchor_bottom_center(_search, SearchBar.WIDTH, 40.0, SearchBar.HEIGHT)
	_card.add_child(_search)

	_status = _make_label(9, GOLD)
	_anchor_bottom_center(_status, SearchBar.WIDTH, 22.0, 14.0)
	_card.add_child(_status)

	# The years at either end of the timeline, set per warp from the bar.
	_past = _make_label(7, CYAN)
	_past.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_anchor_bottom_center(_past, SearchBar.WIDTH, 22.0, 14.0)
	_card.add_child(_past)

	_future = _make_label(7, CYAN)
	_future.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor_bottom_center(_future, SearchBar.WIDTH, 22.0, 14.0)
	_card.add_child(_future)
	
	_audio_player = AudioStreamPlayer.new()
	_audio_player.stream = load("res://scenes/assets/transition.mp3") 
	_audio_player.process_mode = Node.PROCESS_MODE_ALWAYS 
	add_child(_audio_player)


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.08))
	label.add_theme_constant_override("outline_size", maxi(roundi(font_size * 0.25), 2))
	return label


## Stretch across the top of the screen, `top` px down, `height` px tall.
func _anchor_top_wide(control: Control, top: float, height: float) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 1.0
	control.anchor_top = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = 0.0
	control.offset_right = 0.0
	control.offset_top = top
	control.offset_bottom = top + height


## Centre horizontally along the bottom edge, `margin` px up from it.
func _anchor_bottom_center(control: Control, width: float, margin: float, height: float) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = -width * 0.5
	control.offset_right = width * 0.5
	control.offset_top = -(margin + height)
	control.offset_bottom = -margin
