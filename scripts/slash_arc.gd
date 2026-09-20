class_name SlashArc
extends Node2D
## The white slice of air a swing throws, drawn as pixel art: one hard crescent
## rasterised onto the game's pixel grid, then eroded away over a couple of
## frames.
##
## Everything here is deliberately chunky. The shape snaps between `frames`
## poses instead of moving continuously, every pixel is fully opaque and comes
## from a small tone ramp, and the slice dissipates by *losing pixels* to an
## ordered dither and dropping down that ramp — never by going transparent.
## Nothing is antialiased, nothing is semi-transparent, and no two frames are
## the same.
##
## The node is **not** rotated: a rotated node would rasterise its rects off
## the pixel grid and give them soft edges. The owner passes the attack angle
## and the maths is rotated instead, and every rect is snapped so its corners
## land on whole world pixels.
##
## Like SwordSwing, the pose comes from the owner's tick stamps rather than an
## AnimationPlayer, so the slice rewinds with a recall and freezes with a time
## stop along with the hitbox it illustrates. It only redraws when the frame
## actually changes, which is at most `frames` times a swing.

## Distance from the pivot to the middle of the crescent on the strike frame.
@export var radius := 27.0
## How wide the crescent is at its fattest, straddling `radius`.
@export var thickness := 20.0
## Angle the crescent spans. Wide enough that the tips pass the head and the
## feet, so the swing reads as having gone through the character.
@export var sweep := 1.9
## Radians the crescent sits above the attack direction on the strike. A side
## slash is a chop: it starts high, behind the head, and finishes around the
## boots rather than buried in the floor.
@export var lean := -0.25
## How many poses the life is cut into: the strike, then the aftermath.
@export var frames := 3

@export_group("Aftermath")
## Radius, width and span at the last frame, as multipliers on the strike.
@export var grow_to := 1.3
@export var thin_to := 0.4
@export var close_to := 0.72
## Fraction of the crescent's pixels still standing on the last frame. The
## rest are cut away by the dither, which is how this fades.
@export var keep_to := 0.3
## The dither eats the thin edges of the band well before the core, so the
## slice comes apart ragged instead of turning into an even screen door.
## Multipliers on `keep` at the middle of the band and at its edge.
@export var keep_core := 1.7
@export var keep_edge := 0.5
## How far the crescent swings on past the strike, in radians. Small: the
## aftermath is the shape coming apart, not the slash travelling off.
@export var drift := 0.18

@export_group("Look")
## Tone ramp, brightest first. Each frame starts one tone further down it, so
## the slice dims in steps instead of going transparent. All fully opaque.
@export var tones: Array[Color] = [
	Color(1, 1, 1, 1),
	Color(0.76, 0.84, 1, 1),
	Color(0.44, 0.5, 0.74, 1),
]
## How much of the band's half-width is the bright core tone.
@export_range(0.0, 1.0) var core_width := 0.55
## Pixel chips thrown off the leading edge from the second frame on.
@export var spark_px := 1.0
@export var spark_reach := 9.0

## Where the sparks sit along the crescent, and how far past its edge each one
## flies. Fixed rather than random: anything rolled in _draw() would crawl
## from frame to frame instead of holding still.
const SPARK_SPOTS := [0.22, 0.48, 0.7, 0.9]
const SPARK_KICK := [0.9, 0.45, 1.3, 0.75]

## Progress through the slice's life, 0..1.
var progress := 0.0
## -1 mirrors the crescent, for a swing that faces the other way.
var flip := 1.0
## Attack direction, in radians. Set by the owner instead of rotating the node.
var direction := 0.0

## What the current draw commands were built from, so a pose that lands on the
## same frame doesn't re-rasterise. -1 = nothing drawn yet.
var _drawn_step := -1
var _drawn_key := 0.0


func _ready() -> void:
	visibility_changed.connect(_invalidate)


func set_pose(t: float, sweep_flip: float, angle: float) -> void:
	progress = clampf(t, 0.0, 1.0)
	flip = -1.0 if sweep_flip < 0.0 else 1.0
	direction = angle
	var step := _step()
	var key := direction * flip
	if step == _drawn_step and is_equal_approx(key, _drawn_key):
		return
	_drawn_step = step
	_drawn_key = key
	queue_redraw()


func _invalidate() -> void:
	_drawn_step = -1


## Which of the `frames` poses `progress` lands on.
func _step() -> int:
	return mini(int(progress * frames), maxi(frames - 1, 0))


func _draw() -> void:
	var step := _step()
	# How far into the aftermath this frame is: 0 on the strike, 1 on the last.
	var s := float(step) / float(maxi(frames - 1, 1))
	var r := radius * lerpf(1.0, grow_to, s)
	var width := thickness * lerpf(1.0, thin_to, s)
	var span := sweep * lerpf(1.0, close_to, s)
	# The whole crescent rides on past the strike as it comes apart.
	var half := span * 0.5 * flip
	var centre := direction + (lean + drift * s) * flip
	var lead := centre + half
	var trail := centre - half
	_draw_crescent(r, width, lead, trail, lerpf(1.0, keep_to, s), step)
	if step > 0:
		_draw_sparks(r, width, lead, trail, s, step)


## Rasterises the crescent a pixel at a time, merging each row into runs so a
## row of the same tone costs one rect rather than one per pixel.
func _draw_crescent(r: float, width: float, lead: float, trail: float,
		keep: float, step: int) -> void:
	var total := angle_difference(trail, lead)
	if is_zero_approx(total) or width <= 0.0:
		return
	var r_in := maxf(r - width * 0.5, 0.0)
	var r_out := r + width * 0.5
	var bounds := _bounds(r_in, r_out, lead, trail)
	var x0 := int(floor(bounds.position.x))
	var x1 := int(ceil(bounds.end.x))
	var y0 := int(floor(bounds.position.y))
	var y1 := int(ceil(bounds.end.y))
	for py in range(y0, y1 + 1):
		var run_from := 0
		var run_tone := -1
		# One past the end, so the last run is always closed off.
		for px in range(x0, x1 + 2):
			var tone := -1
			if px <= x1:
				tone = _tone_at(px, py, r, r_in, r_out, width, trail, total, keep, step)
			if tone == run_tone:
				continue
			if run_tone >= 0:
				_fill(run_from, py, px - run_from, run_tone)
			run_from = px
			run_tone = tone


## Which tone the pixel at (px, py) is, or -1 for a pixel that isn't part of
## the crescent (outside it, or cut away by the dither).
func _tone_at(px: int, py: int, r: float, r_in: float, r_out: float, width: float,
		trail: float, total: float, keep: float, step: int) -> int:
	# Sample the middle of the pixel. The cheap radial test first: most of the
	# bounding box is outside the ring and never needs the trig.
	var fx := px + 0.5
	var fy := py + 0.5
	var d2 := fx * fx + fy * fy
	if d2 < r_in * r_in or d2 > r_out * r_out:
		return -1
	var u := angle_difference(trail, atan2(fy, fx)) / total
	if u < 0.0 or u > 1.0:
		return -1
	# Fattest past the middle, so the crescent leans into the lead.
	var half_w := width * 0.5 * sin(PI * pow(u, 1.3))
	if half_w <= 0.0:
		return -1
	var from_mid := absf(sqrt(d2) - r)
	if from_mid > half_w:
		return -1
	var across := from_mid / half_w
	if keep < 1.0 and PixelDraw.dither(px, py) >= keep * lerpf(keep_core, keep_edge, across):
		return -1
	# Bright core down the middle of the band, except at the trailing tip,
	# which is the thin end of the swing.
	var core: bool = across < core_width and u > 0.25
	return mini(step + (0 if core else 1), tones.size() - 1)


## Chips flung off the outer edge once the crescent starts to break up.
func _draw_sparks(r: float, width: float, lead: float, trail: float, s: float,
		step: int) -> void:
	var tone := mini(step, tones.size() - 1)
	var size := maxf(spark_px, 1.0)
	for i in SPARK_SPOTS.size():
		var u: float = SPARK_SPOTS[i]
		var a := lerpf(trail, lead, u)
		var d: float = r + width * 0.5 + SPARK_KICK[i] * spark_reach * s
		var at := Vector2.from_angle(a) * d
		_fill(int(floor(at.x)), int(floor(at.y)), int(size), tone)


## One run of pixels, snapped so its corners land on whole world pixels — the
## node has no rotation or scale, so local and world axes agree and the rect
## comes out with hard edges however fractional the owner's position is.
func _fill(px: int, py: int, run: int, tone: int) -> void:
	if run <= 0:
		return
	var at := Vector2(px, py) + PixelDraw.snap(self)
	draw_rect(Rect2(at, Vector2(run, 1)), tones[tone])


## Bounding box of the crescent, from samples down its outer and inner edges.
func _bounds(r_in: float, r_out: float, lead: float, trail: float) -> Rect2:
	var box := Rect2(Vector2.from_angle(trail) * r_in, Vector2.ZERO)
	for i in 9:
		var a := lerpf(trail, lead, float(i) / 8.0)
		box = box.expand(Vector2.from_angle(a) * r_out)
		box = box.expand(Vector2.from_angle(a) * r_in)
	return box.grow(1.0)
