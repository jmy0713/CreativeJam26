class_name PixelBullet
extends Node2D
## A Disco Ball bullet, drawn as pixel art: a shard off the mirror ball with
## a hot centre, a body that strobes through the disco ramp, and four glitter
## spokes that turn an eighth of a turn every other frame.
##
## House rules, same as the other effects drawn in code (see section 7 of
## ARCHITECTURE.md): opaque tones only, hard edges, a dither instead of
## transparency, every rect on a whole world pixel, and the node is never
## rotated. Nothing here follows the direction of travel — a shard off a
## spinning ball looks the same whichever way it is going — so unlike
## PixelFlame and PixelBomb there is no set_angle().
##
## The strobe rides GameManager's clock like every other looping animation
## here, which is what lets a slow field of these rewind with a recall and
## hold still through a time stop — and means every bullet on screen is on
## the same beat instead of each one flickering on its own spawn time.

## Radius of the shard's body.
@export var radius := 4.0
## The hot centre and the glitter. This one does NOT strobe: it is what keeps
## the silhouette readable while the body changes colour underneath it.
@export var core := Color(1, 0.97, 1, 1)
## One body tone per strobe frame — the ramp's length is the strobe's length.
@export var hues: Array[Color] = [
	Color(1, 0.18, 0.66, 1),
	Color(0.24, 0.9, 1, 1),
	Color(1, 0.86, 0.22, 1),
	Color(0.55, 0.35, 1, 1),
]
@export var strobe_fps := 12.0
## How deep into the shard the core reaches: 1 at the centre, 0 at the rim.
@export_range(0.0, 1.0) var core_depth := 0.62
## How far in from the rim the darker edge band starts.
@export_range(0.0, 1.0) var rim_depth := 0.25
## Fraction of the edge band the dither keeps, so the outline breaks up
## rather than ending on a clean curve.
@export_range(0.0, 1.0) var rim_keep := 0.6
## The edge band is the body tone stepped down this far.
@export_range(0.0, 1.0) var rim_shade := 0.45
## Gap between the body and the single-pixel glitter spokes.
@export var spoke_gap := 2.0

var _drawn_frame := -1


func _physics_process(_delta: float) -> void:
	# Redraw only when the strobe actually steps.
	if _strobe() != _drawn_frame:
		queue_redraw()


## Which strobe frame the shared clock is on.
func _strobe() -> int:
	return posmod(int(GameManager.level_time_seconds() * strobe_fps), maxi(hues.size(), 1))


func _draw() -> void:
	if hues.is_empty():
		return
	_drawn_frame = _strobe()
	var body: Color = hues[_drawn_frame]
	# Tone 0 core, 1 body, 2 edge — the edge is the body tone stepped down
	# rather than its own export, so adding a hue never needs a second entry.
	var tones := [core, body, Color(body.r * rim_shade, body.g * rim_shade, body.b * rim_shade, 1.0)]
	var offset := PixelDraw.snap(self)
	_rasterise(tones, offset)
	_draw_spokes(offset)


## Walks the shard's bounding box a pixel at a time, merging each row into
## runs so a row of one tone costs a single rect.
func _rasterise(tones: Array, offset: Vector2) -> void:
	var reach := int(ceil(radius)) + 1
	for py in range(-reach, reach + 1):
		var run_from := 0
		var run_tone := -1
		# One past the end, so the last run is always closed off.
		for px in range(-reach, reach + 2):
			var tone := -1
			if px <= reach:
				tone = _tone_at(px, py)
			if tone == run_tone:
				continue
			if run_tone >= 0:
				draw_rect(Rect2(Vector2(run_from, py) + offset,
					Vector2(px - run_from, 1)), tones[run_tone])
			run_from = px
			run_tone = tone


## Which tone the pixel at (px, py) is, or -1 if it is outside the shard or
## cut away by the dither. `depth` is how far inside it sits: 1 at the
## centre, 0 at the rim.
func _tone_at(px: int, py: int) -> int:
	# Sample the middle of the pixel, so the circle stays symmetric.
	var depth := 1.0 - Vector2(px + 0.5, py + 0.5).length() / maxf(radius, 0.001)
	if depth <= 0.0:
		return -1
	if depth > core_depth:
		return 0
	if depth > rim_depth:
		return 1
	if PixelDraw.dither(px, py) >= rim_keep:
		return -1
	return 2


## Four single pixels off the rim, on the compass points, turned an eighth of
## a turn on odd frames so the shard reads as catching the light rather than
## wearing a fixed cross.
func _draw_spokes(offset: Vector2) -> void:
	var spin := PI / 4.0 * (_drawn_frame % 2)
	var reach := radius + spoke_gap
	for i in 4:
		var at := (Vector2.from_angle(spin + i * PI / 2.0) * reach).round()
		draw_rect(Rect2(at + offset, Vector2.ONE), core)
