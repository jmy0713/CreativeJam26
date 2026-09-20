class_name MagicBarrier
extends Node2D
## The pair of magic panels a Slime raises while it is defending: one curved
## wall on each side, drawn as pixel art the same way SlashArc and PuffCloud
## are (see ARCHITECTURE.md section 7).
##
## "Half transparent" the pixel-art way: every pixel drawn is fully opaque and
## the see-through comes from an ordered dither cutting the panel's interior
## away, so the floor shows through the holes. How much survives is the `keep`
## the owner passes each pose — 0.5 is the even checker that reads as half
## transparent — so the same panel can thicken and thin with the owner's state
## without ever touching alpha. A real alpha would blend against whatever is
## behind it and go soft at the edges, which would put the only smooth-shaded
## thing in the game right next to the sharpest. The outer rim skips the dither
## and stays solid by default, so the panel keeps a hard bright outline around
## the screen-door middle — but `rim_keep` lets the owner dither it away too,
## which is how the guard comes apart instead of blinking out.
##
## The shimmer is frame-stepped, not tweened: `steps` poses that the owner
## clocks off the level time, each one pushing the wall out or in by a pixel
## and shifting the dither, so it flickers like a held spell instead of
## sliding. Being on the level clock means it rewinds with a recall and holds
## still during a time stop, like everything else drawn this way.
##
## The node is never rotated and every rect is snapped with PixelDraw.snap(),
## which is what keeps the edges hard however fractional the owner's position
## is. It carries no z_index, and must not: tree order alone decides whether it
## sits in front of its owner (see the same note in ARCHITECTURE.md).

## Distance from this node's origin to the middle of each panel.
@export var radius := 14.0
## How thick the panel is at its fattest, straddling `radius`.
@export var thickness := 6.0
## Half the angle each panel spans, in radians. The owner matches it to its own
## overhead cutoff — the slime's 0.9 puts the top of the panel 11 px up, which
## is exactly where Slime.overhead_height stops the block. The guard can't be
## held above the slime's head, and it shouldn't look like it is.
@export var span := 0.9
## How many poses the shimmer cycles through.
@export var steps := 4

@export_group("Look")
## Solid outer rim, then the dithered interior. Both fully opaque.
@export var rim_color := Color(0.85, 0.98, 1, 1)
@export var fill_color := Color(0.36, 0.72, 0.95, 1)
## How deep the solid rim is, in pixels.
@export var rim_px := 1.0

## Pixels each pose pushes the wall out by, and how far it slides the dither.
## Fixed tables rather than anything rolled in _draw(), which would crawl from
## frame to frame instead of cycling.
const PUSH := [0.0, 1.0, 0.0, -1.0]
const DITHER_SHIFT := [0, 2, 1, 3]

## What the current draw commands were built from, so a pose that lands on the
## same step doesn't re-rasterise. -1 = nothing drawn yet.
var _drawn_step := -1
var _drawn_keep := -1.0
var _drawn_rim := -1.0


func _ready() -> void:
	visibility_changed.connect(_invalidate)


## `step` is the pose, counted by the owner off the level clock; `keep` is how
## much of the interior survives the dither, and `rim_keep` how much of the
## outline does — 1.0, the default, is the solid rim a standing guard has.
## Redraws only when one of the three actually changes.
func set_pose(step: int, keep: float, rim_keep: float = 1.0) -> void:
	var s := posmod(step, maxi(steps, 1))
	# Snapped so an owner easing either one can't ask for a redraw every frame.
	var k := snappedf(clampf(keep, 0.0, 1.0), 0.05)
	var rim := snappedf(clampf(rim_keep, 0.0, 1.0), 0.05)
	if s == _drawn_step and is_equal_approx(k, _drawn_keep) and is_equal_approx(rim, _drawn_rim):
		return
	_drawn_step = s
	_drawn_keep = k
	_drawn_rim = rim
	queue_redraw()


func _invalidate() -> void:
	_drawn_step = -1


func _draw() -> void:
	if _drawn_step < 0:
		return
	_draw_panel(0.0, _drawn_step, _drawn_keep, _drawn_rim)
	_draw_panel(PI, _drawn_step, _drawn_keep, _drawn_rim)


## One wall: the slice of a ring that sits within `span` of `facing`, walked a
## pixel at a time and emitted as opaque 1-px-tall runs, so a row of the same
## tone costs one rect rather than one per pixel.
func _draw_panel(facing: float, step: int, keep: float, rim_keep: float) -> void:
	var r: float = radius + PUSH[step % PUSH.size()]
	var r_in := maxf(r - thickness * 0.5, 0.0)
	var r_out := r + thickness * 0.5
	if r_out <= 0.0 or span <= 0.0:
		return
	var shift: int = DITHER_SHIFT[step % DITHER_SHIFT.size()]
	# Only the half the panel is on, and only as tall as the span reaches.
	var reach := int(ceil(r_out)) + 1
	var x0 := 0 if is_zero_approx(facing) else -reach
	var x1 := reach if is_zero_approx(facing) else 0
	var y_reach := int(ceil(r_out * sin(span))) + 1
	for py in range(-y_reach, y_reach + 1):
		var run_from := 0
		var run_tone := -1
		# One past the end, so the last run is always closed off.
		for px in range(x0, x1 + 2):
			var tone := -1
			if px <= x1:
				tone = _tone_at(px, py, r, r_in, r_out, facing, keep, rim_keep, shift)
			if tone == run_tone:
				continue
			if run_tone >= 0:
				_fill(run_from, py, px - run_from, run_tone)
			run_from = px
			run_tone = tone


## 0 for the solid rim, 1 for a kept interior pixel, -1 for a pixel that isn't
## part of the panel — outside it, or cut away by the dither.
func _tone_at(px: int, py: int, r: float, r_in: float, r_out: float,
		facing: float, keep: float, rim_keep: float, shift: int) -> int:
	# Sample the middle of the pixel. Cheap radial test first: most of the
	# bounding box is outside the ring and never needs the trig.
	var fx := px + 0.5
	var fy := py + 0.5
	var d2 := fx * fx + fy * fy
	if d2 < r_in * r_in or d2 > r_out * r_out:
		return -1
	var off := absf(angle_difference(facing, atan2(fy, fx)))
	if off > span:
		return -1
	# Lens profile: fattest across the middle of the panel, pointed at the
	# tips, so it reads as a curved plate rather than a slice of pipe.
	var u := off / span
	var half_w := thickness * 0.5 * sqrt(maxf(1.0 - u * u, 0.0))
	if half_w <= 0.0:
		return -1
	var from_mid := absf(sqrt(d2) - r)
	if from_mid > half_w:
		return -1
	# The rim is the outline of the spell: at a full rim_keep it never dithers,
	# so the panel holds a hard edge however thin the middle gets. Only a guard
	# being dismissed takes the outline apart too.
	var dither := PixelDraw.dither(px + shift, py + shift)
	if from_mid > half_w - rim_px:
		return 0 if rim_keep >= 1.0 or dither < rim_keep else -1
	return 1 if dither < keep else -1


## One run of pixels, snapped so its corners land on whole world pixels — the
## node has no rotation or scale, so local and world axes agree and the rect
## comes out with hard edges however fractional the owner's position is.
func _fill(px: int, py: int, run: int, tone: int) -> void:
	if run <= 0:
		return
	var at := Vector2(px, py) + PixelDraw.snap(self)
	draw_rect(Rect2(at, Vector2(run, 1)), rim_color if tone == 0 else fill_color)
