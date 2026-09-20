class_name DiscoLaser
extends Projectile
## One sweep of the Disco Ball's laser attack: a thin warning line along a
## lane, then a beam the width of the screen that runs the length of it.
##
## The two phases are one node rather than two, the same way Bomb carries its
## own shell and blast — the telegraph and the beam it promises can never
## drift apart or be cleaned up separately. Phase is read off `_launch_tick`,
## so the whole thing rewinds and freezes on the shared clock.
##
## Like DiscoBullet this is dodge-only: `is_slashable()` is false and nothing
## calls `try_parry()`. The lane you are standing on is the whole decision.
##
## **This is the one effect in the game that carries a z_index** (set in the
## scene). Section 7's rule that effects must not have one exists so they
## layer *with* the player; a boss laser is supposed to pass in front of
## everything, the player included, so it opts out on purpose.

## The art is a 32x32 horizontal beam segment. Only rows 3..28 of it are
## opaque, and the damaging band matches that rather than the full frame, or
## the beam would hurt through a visible gap above and below it.
const SPRITE_TEXELS := 32.0
const OPAQUE_TEXELS := 26.0

@export_group("Beam")
@export var beam_texture: Texture2D
## Length of the beam along the lane. At the screen's own width the lane is
## briefly filled end to end mid-sweep, which is what makes it read as one
## big beam passing through rather than a bolt flying past.
@export var beam_length := 640.0
## World pixels per texel. Whole numbers only — a fractional scale rasterises
## the art off the pixel grid and the beam comes out soft.
@export var beam_scale := 2.0

@export_group("Telegraph")
## Tones the warning line blinks between.
@export var telegraph_tones: Array[Color] = [
	Color(1, 0.95, 0.98, 1),
	Color(1, 0.22, 0.42, 1),
]
@export var telegraph_thickness := 2.0
@export var telegraph_fps := 10.0

var _telegraph_ticks := 0
var _sweep_ticks := 0
var _from_x := 0.0
var _to_x := 0.0
## Half the lane's length, for the warning line drawn in local space.
var _half_lane := 0.0
var _sweeping := false
var _drawn_frame := -1

@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var laser_sound: AudioStreamPlayer2D = $LaserSound


func _ready() -> void:
	super()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(beam_length, OPAQUE_TEXELS * beam_scale)
	_shape.shape = rect


## Half the beam's length, so the owner can start it fully off screen.
func half_length() -> float:
	return beam_length / 2.0


## Arms the lane: the warning line sits still across `lane_width` centred on
## `lane_centre`, then the beam runs from `from_x` to `to_x` through it.
func arm(lane_centre: Vector2, lane_width: float, from_x: float, to_x: float,
		telegraph_seconds: float, sweep_seconds: float) -> void:
	_from_x = from_x
	_to_x = to_x
	_half_lane = lane_width / 2.0
	_telegraph_ticks = GameManager.seconds_to_ticks(telegraph_seconds)
	_sweep_ticks = maxi(GameManager.seconds_to_ticks(sweep_seconds), 1)
	lifetime = telegraph_seconds + sweep_seconds + 1.0
	# Parked at the lane's centre so the warning line can be drawn in local
	# space; the sweep moves it from the first physics frame after that.
	launch(lane_centre, lane_centre + Vector2.RIGHT * signf(to_x - from_x))
	_sweeping = false
	set_deferred(&"monitoring", false)


## The player's slash can do nothing to a beam.
func is_slashable() -> bool:
	return false


func destroy() -> void:
	pass


func _physics_process(_delta: float) -> void:
	if not alive:
		return
	var elapsed := GameManager.ticks_since(_launch_tick)
	if elapsed < _telegraph_ticks:
		if _telegraph_frame() != _drawn_frame:
			queue_redraw()
		return

	if not _sweeping:
		_sweeping = true
		set_deferred(&"monitoring", true)
		# Swap the warning line for the beam itself.
		queue_redraw()
		laser_sound.play()
		
	var t := float(elapsed - _telegraph_ticks) / float(_sweep_ticks)
	if t >= 1.0:
		_vanish()
		return
	# Straight arithmetic on the launch stamp, so the sweep is exactly
	# reproducible when a recall runs it again.
	global_position.x = lerpf(_from_x, _to_x, t)


## Which blink frame the shared clock is on.
func _telegraph_frame() -> int:
	return posmod(int(GameManager.level_time_seconds() * telegraph_fps),
		maxi(telegraph_tones.size(), 1))


func _draw() -> void:
	if not alive:
		return
	if _sweeping:
		_draw_beam()
	else:
		_draw_telegraph()


## The beam, tiled a segment at a time the way Platform lays out its disco
## strip. Tiling by hand rather than leaning on a repeating texture keeps it
## to one well-trodden path, and the whole thing is drawn under one scaled
## transform so the art stays on whole texels instead of being stretched.
func _draw_beam() -> void:
	if beam_texture == null:
		return
	draw_set_transform(PixelDraw.snap(self), 0.0, Vector2(beam_scale, beam_scale))
	var texels_long := beam_length / maxf(beam_scale, 0.001)
	var drawn := 0.0
	while drawn < texels_long:
		var width := minf(SPRITE_TEXELS, texels_long - drawn)
		draw_texture_rect_region(beam_texture,
			Rect2(-texels_long / 2.0 + drawn, -SPRITE_TEXELS / 2.0, width, SPRITE_TEXELS),
			Rect2(0.0, 0.0, width, SPRITE_TEXELS))
		drawn += SPRITE_TEXELS
	draw_set_transform(Vector2.ZERO)


## The warning line: an opaque bar across the lane, blinking between tones on
## the shared clock so every lane's warning is on the same beat.
func _draw_telegraph() -> void:
	if telegraph_tones.is_empty():
		return
	_drawn_frame = _telegraph_frame()
	var offset := PixelDraw.snap(self)
	var height := maxf(telegraph_thickness, 1.0)
	draw_rect(Rect2(Vector2(-_half_lane, -height / 2.0) + offset,
		Vector2(_half_lane * 2.0, height)), telegraph_tones[_drawn_frame])


func _vanish() -> void:
	super()
	queue_redraw()
