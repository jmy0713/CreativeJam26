extends CanvasLayer
## Time-warp level transitions (autoload).
##
## GameManager.load_level() hands the next level to warp_to_scene(). The game
## is paused for the whole transition, and two beats play over it:
##
##   TRAVEL  the warp and the loading screen run together. The current frame
##           is sucked into a swirling time tunnel (WARP_SECONDS) while the
##           loading card is already up: the player binary-searching a
##           timeline for the next level (time_search_bar.gd), finishing at
##           LOADING_SECONDS. Once the tunnel covers the screen, the new
##           level is swapped in behind it.
##   REVEAL  the tunnel collapses and the new level flies back out of it
##
## The tunnel is time_warp.gdshader on a full-screen ColorRect, drawn above the
## HUD. The card is built here in code so there is no scene to keep in sync.
## Deaths (GameManager.restart_level) deliberately skip all of this.

## How long the level takes to be pulled into the tunnel. Must not be longer
## than LOADING_SECONDS.
const WARP_SECONDS := 1.4
## How long the loading screen runs, starting together with the warp.
const LOADING_SECONDS := 3.0
## How long the tunnel takes to collapse and reveal the new level.
const REVEAL_SECONDS := 0.8
## The loading card fades in over this long at the start of the warp.
const CARD_FADE_IN_SECONDS := 0.35

const SHADER := preload("res://shaders/time_warp.gdshader")
const SearchBar := preload("res://scripts/ui/time_search_bar.gd")

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

var _warp_rect: ColorRect
var _material: ShaderMaterial
var _card: Control
var _title: Label
var _status: Label
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

	match _phase:
		Phase.TRAVEL:
			var warp_t := clampf(_phase_time / WARP_SECONDS, 0.0, 1.0)
			var progress := clampf(_phase_time / LOADING_SECONDS, 0.0, 1.0)
			_set_warp(smoothstep(0.0, 1.0, warp_t))
			# Speed climbs through the warp, then settles into a cruise.
			var settle := clampf((_phase_time - WARP_SECONDS) / 0.6, 0.0, 1.0)
			_speed = lerpf(lerpf(SPEED_SLOW, SPEED_PEAK, warp_t), SPEED_LOADING, settle)
			_card.modulate.a = clampf(_phase_time / CARD_FADE_IN_SECONDS, 0.0, 1.0)
			_search.set_progress(progress)
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
			_card.modulate.a = 1.0 - clampf(_phase_time / 0.25, 0.0, 1.0)
			if t >= 1.0:
				_finish()

	_anim_time += delta * _speed
	_material.set_shader_parameter("anim_time", _anim_time)


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
	# The timeline runs through every level: search from the one we're
	# leaving to the one we're heading for.
	_search.setup(GameManager.LEVELS.size(), GameManager.current_level_index, GameManager.LEVELS.find(scene_path))
	_status.text = _search.status
	# The clock's hands turn clockwise when heading to a later level, and
	# counter-clockwise when looping back (boss -> level 1).
	var to_future := GameManager.LEVELS.find(scene_path) >= GameManager.current_level_index
	_material.set_shader_parameter("clock_spin", 1.0 if to_future else -1.0)
	_anim_time = 0.0
	_speed = SPEED_SLOW
	_card.modulate.a = 0.0
	_card.visible = true
	_set_warp(0.0)
	_material.set_shader_parameter("anim_time", 0.0)
	_warp_rect.visible = true

	get_tree().paused = true
	_enter(Phase.TRAVEL)


func _begin_reveal() -> void:
	_search.set_progress(1.0)
	_status.text = _search.status
	_enter(Phase.REVEAL)


func _finish() -> void:
	_phase = Phase.IDLE
	_warp_rect.visible = false
	_card.visible = false
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


func _build() -> void:
	_warp_rect = ColorRect.new()
	_warp_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_warp_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warp_rect.visible = false
	_material = ShaderMaterial.new()
	_material.shader = SHADER
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

	var subtitle := _make_label(9, CYAN)
	subtitle.text = "WARPING THROUGH TIME"
	_anchor_top_wide(subtitle, 60.0, 14.0)
	_card.add_child(subtitle)

	# The loading bar: a timeline the player binary-searches.
	_search = SearchBar.new()
	_anchor_bottom_center(_search, SearchBar.WIDTH, 40.0, SearchBar.HEIGHT)
	_card.add_child(_search)

	_status = _make_label(9, GOLD)
	_anchor_bottom_center(_status, SearchBar.WIDTH, 22.0, 14.0)
	_card.add_child(_status)

	var past := _make_label(7, CYAN)
	past.text = "PAST"
	past.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_anchor_bottom_center(past, SearchBar.WIDTH, 22.0, 14.0)
	_card.add_child(past)

	var future := _make_label(7, CYAN)
	future.text = "FUTURE"
	future.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor_bottom_center(future, SearchBar.WIDTH, 22.0, 14.0)
	_card.add_child(future)


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
