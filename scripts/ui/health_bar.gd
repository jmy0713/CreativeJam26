extends TextureRect
class_name HealthBar
## Pixel health bar, driven by Player.health_changed.
##
## Three effects, all tuned from the Inspector:
##
## 1. DISSOLVE — a hit doesn't snap from one stage sprite to the next. The two
##    stages are cross-dithered in the shader, so the change crumbles across
##    the bar pixel by pixel. The wipe runs from the bar's tip toward its base
##    when you lose health and the other way when you heal.
## 2. TRAIL — the pixels the bar just lost stay lit in the level's secondary
##    colour, then crumble away `trail_hold_time` after the red does. Red that
##    survives the hit (the ragged tip of a stage) is left alone.
## 3. SHAKE — a decaying jitter on damage, snapped to whole screen pixels.
##
## Timing uses real_tick stamps rather than float timers, per the rule in
## game_manager.gd. That clock keeps running while the level is frozen, and
## recall's _restore_health re-emits health_changed, so the bar rewinds with
## everything else.

## Cells in the atlas, fullest first, read left to right then top to bottom.
const STAGE_COUNT := 5
## Frame index the shader treats as "nothing left", used at 0 HP.
const FRAME_EMPTY := STAGE_COUNT

## Cell grid of the atlas, as columns x rows. The cell size in pixels is
## derived from the texture, so re-exporting the art at a different scale
## needs no changes here.
@export var atlas_grid := Vector2i(4, 2)

## Secondary colour per entry in GameManager.LEVELS, to fit each level's
## theme. Index past the end (or -1, before a level registers) falls back to
## DEFAULT_TRAIL_COLOR.
const TRAIL_COLORS: Array[Color] = [
	Color("1f2124"),  # level 1 — neutral stone grey
	Color("2b1f36"),  # level 2 — disco violet
	Color("18292c"),  # level 3 — cold teal
	Color("1b2736"),  # level 4 — dusk blue, before the sky goes orange
	Color("321c1e"),  # boss    — dried blood
]
const DEFAULT_TRAIL_COLOR := Color("1f2124")

@export_group("Dissolve")
## Seconds for one stage to crumble into the next.
@export var dissolve_time := 0.16
## 0 = a clean ordered stipple, 1 = pure per-pixel noise.
@export_range(0.0, 1.0) var dither_noise := 0.35
## Width of the travelling dither band, in fractions of the bar's length.
## 0 flips every pixel at once; higher reads more like draining.
@export_range(0.0, 2.0) var edge_softness := 0.55

@export_group("Trail")
## How long the lost pixels hold in the secondary colour before crumbling.
@export var trail_hold_time := 0.40
@export var trail_dissolve_time := 0.35
## Darkening applied to the trail where the sprite's outline was.
@export_range(0.0, 1.0) var trail_outline_darken := 0.45

@export_group("Shake")
@export var shake_time := 0.22
## Peak offset for a 1-damage hit, in screen pixels.
@export var shake_pixels := 3.0
## Extra peak offset per point of damage beyond the first.
@export var shake_per_damage := 1.5
@export var shake_max_pixels := 7.0

var _material: ShaderMaterial

var _health := -1
var _maximum := -1

## Stage the bar is leaving, and the one it is arriving at.
var _frame_from := 0
var _frame_to := 0
## Stage the trail's silhouette is measured against. Held at the oldest stage
## of a burst so back-to-back hits leave one trail, not several overlapping.
var _frame_trail := 0

var _dissolve_tick := GameManager.NEVER
var _trail_tick := GameManager.NEVER
var _shake_tick := GameManager.NEVER
var _shake_amount := 0.0

var _base_position := Vector2.ZERO


func _ready() -> void:
	_material = material as ShaderMaterial
	if _material == null:
		push_error("HealthBar needs a ShaderMaterial running health_bar.gdshader")
		set_process(false)
		return
	_base_position = position
	_bind_atlas()
	GameManager.level_started.connect(_on_level_started)
	if is_instance_valid(GameManager.player):
		_on_level_started(GameManager.current_level)


## Hand the atlas to the shader and work out one cell's size from it. The
## shader samples this uniform rather than the node's own texture, but the
## node still needs that texture set to have something to draw into.
func _bind_atlas() -> void:
	if texture == null:
		push_error("HealthBar has no texture; expected the health bar atlas")
		return
	_material.set_shader_parameter(&"atlas", texture)
	_material.set_shader_parameter(&"grid", Vector2(atlas_grid))
	var cell := Vector2(texture.get_size()) / Vector2(atlas_grid)
	_material.set_shader_parameter(&"frame_pixels", cell)
	if cell != cell.round():
		push_warning("Health bar atlas %s does not divide evenly into a %dx%d grid"
			% [texture.get_size(), atlas_grid.x, atlas_grid.y])


## The bar lives in the Hud autoload and outlives levels, so it re-binds to
## each level's player and re-reads the level's theme colour.
func _on_level_started(_level: Level) -> void:
	var player := GameManager.player
	if not is_instance_valid(player):
		return
	if not player.health_changed.is_connected(_on_health_changed):
		player.health_changed.connect(_on_health_changed)
	_apply_trail_color()
	_reset_to(player.health, player.max_health)


## Snap to a health value with no animation. Used on level start and restart.
func _reset_to(current: int, maximum: int) -> void:
	_health = current
	_maximum = maximum
	_frame_from = _frame_for(current, maximum)
	_frame_to = _frame_from
	_frame_trail = _frame_from
	_dissolve_tick = GameManager.NEVER
	_trail_tick = GameManager.NEVER
	_shake_tick = GameManager.NEVER


func _on_health_changed(current: int, maximum: int) -> void:
	if current == _health and maximum == _maximum:
		return
	if _health < 0:
		# Never showed a value yet, so there is nothing to animate from.
		_reset_to(current, maximum)
		return
	var lost := _health - current
	_maximum = maximum
	_health = current

	if lost > 0:
		_shake_tick = GameManager.real_tick
		_shake_amount = minf(shake_pixels + (lost - 1) * shake_per_damage, shake_max_pixels)

	# A hit landing mid-dissolve finishes the one in flight first, so the
	# shader only ever blends two stages.
	_frame_from = _frame_to
	_frame_to = _frame_for(current, maximum)
	# Damage too small to cross a stage boundary still shakes, but there is
	# nothing to dissolve or to leave behind.
	if _frame_from == _frame_to:
		return
	_dissolve_tick = GameManager.real_tick

	if lost > 0:
		# Keep the older silhouette while a trail is still on screen, so a
		# burst of hits leaves one trail covering the whole loss.
		if not _trail_active():
			_frame_trail = _frame_from
		_trail_tick = GameManager.real_tick
	else:
		# Healing: no trail, and drop any trail still fading.
		_frame_trail = _frame_to
		_trail_tick = GameManager.NEVER


## Move the bar and make that its new rest position, so an in-flight shake
## doesn't snap it back to where it used to sit.
func set_base_position(to: Vector2) -> void:
	_base_position = to
	position = to


func _process(_delta: float) -> void:
	_update_shader()
	_update_shake()


func _update_shader() -> void:
	var dissolve := _progress(_dissolve_tick, dissolve_time)
	_material.set_shader_parameter(&"frame_from", _frame_from)
	_material.set_shader_parameter(&"frame_to", _frame_to)
	_material.set_shader_parameter(&"dissolve", dissolve)
	# Losing health wipes from the tip inward; healing fills the other way.
	_material.set_shader_parameter(&"sweep_dir", 1.0 if _frame_to >= _frame_from else -1.0)
	_material.set_shader_parameter(&"dither_noise", dither_noise)
	_material.set_shader_parameter(&"edge_softness", edge_softness)

	_material.set_shader_parameter(&"frame_ghost", _frame_trail)
	_material.set_shader_parameter(&"ghost_dissolve", _trail_progress())
	_material.set_shader_parameter(&"ghost_outline_darken", trail_outline_darken)

	_material.set_shader_parameter(&"frame_count", STAGE_COUNT)


func _update_shake() -> void:
	var t := _seconds_since(_shake_tick)
	if t >= shake_time or _shake_tick == GameManager.NEVER:
		position = _base_position
		return
	# Quadratic falloff, re-aimed once per physics tick so it stays chunky
	# instead of smearing at the render rate.
	var decay := 1.0 - t / shake_time
	var amp := _shake_amount * decay * decay
	var n := float(GameManager.real_tick)
	position = _base_position + Vector2(roundf(sin(n * 2.7) * amp), roundf(cos(n * 3.9) * amp * 0.6))


func _apply_trail_color() -> void:
	var index := GameManager.current_level_index
	var color := TRAIL_COLORS[index] if index >= 0 and index < TRAIL_COLORS.size() else DEFAULT_TRAIL_COLOR
	_material.set_shader_parameter(&"ghost_color", color)


# --- Helpers ----------------------------------------------------------------

## Atlas frame for a health value. Stage 0 is full; FRAME_EMPTY is death.
## Written as a ratio so it still works if max_health stops being 5.
func _frame_for(current: int, maximum: int) -> int:
	if current <= 0 or maximum <= 0:
		return FRAME_EMPTY
	var filled := ceili(float(current) / float(maximum) * STAGE_COUNT)
	return STAGE_COUNT - clampi(filled, 1, STAGE_COUNT)


func _seconds_since(tick: int) -> float:
	return GameManager.ticks_to_seconds(GameManager.real_tick - tick)


## 0 -> 1 over `duration` since `tick`. 1 when `tick` is NEVER (i.e. settled).
func _progress(tick: int, duration: float) -> float:
	if tick == GameManager.NEVER or duration <= 0.0:
		return 1.0
	return clampf(_seconds_since(tick) / duration, 0.0, 1.0)


## The trail holds at full for `trail_hold_time`, then crumbles.
func _trail_progress() -> float:
	if _trail_tick == GameManager.NEVER:
		return 1.0
	var t := _seconds_since(_trail_tick) - trail_hold_time
	if t <= 0.0:
		return 0.0
	if trail_dissolve_time <= 0.0:
		return 1.0
	return clampf(t / trail_dissolve_time, 0.0, 1.0)


func _trail_active() -> bool:
	return _trail_tick != GameManager.NEVER and _trail_progress() < 1.0
