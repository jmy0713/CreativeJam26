class_name PixelFlame
extends Node2D
## The fireball's flame, drawn as pixel art: a bright head with a tail that
## flickers, rasterised onto the pixel grid.
##
## House rules, same as the other effects drawn here (see section 7 of
## ARCHITECTURE.md): opaque tones only, hard edges, a dither rather than
## transparency, and the node is never rotated — a rotated node rasterises off
## the grid. The direction of travel comes in through set_angle() and every
## pixel is tested in the flame's own frame instead.
##
## The flicker rides GameManager's clock like any looping animation, so it
## rewinds with a recall and holds still through a time stop.

## Radius of the head, which sits on the node's origin.
@export var head := 4.5
## How far the tail reaches back from the head.
@export var length := 13.0
## Radius of the last, smallest puff of the tail.
@export var tail := 1.6
## Puffs strung between the head and the end of the tail.
@export var puffs := 3
@export var flicker_frames := 4
@export var flicker_fps := 14.0
## Tone ramp from the middle of the flame outwards.
@export var tones: Array[Color] = [
	Color(1, 0.96, 0.75, 1),
	Color(1, 0.65, 0.16, 1),
	Color(0.83, 0.26, 0.09, 1),
]
## How deep into the flame the two inner tones reach.
@export_range(0.0, 1.0) var core_depth := 0.62
@export_range(0.0, 1.0) var mid_depth := 0.26
## Fraction of the outermost pixels the dither keeps, for a ragged edge.
@export_range(0.0, 1.0) var edge_keep := 0.6

## Per-flicker-frame wobble on each puff: across the flame, and on its size.
const SWAY := [0.0, 0.85, -0.35, -0.9, 0.45, 0.2]
const PUFF := [1.0, 0.86, 1.12, 0.92]

## Direction of travel, in radians.
var angle := 0.0

var _drawn_frame := -1
var _drawn_angle := 0.0


func _physics_process(_delta: float) -> void:
	# Redraw only when the flicker actually steps.
	if _flicker() != _drawn_frame:
		queue_redraw()


func set_angle(radians: float) -> void:
	if is_equal_approx(radians, _drawn_angle):
		return
	angle = radians
	queue_redraw()


## Which flicker frame the shared clock is on.
func _flicker() -> int:
	return posmod(int(GameManager.level_time_seconds() * flicker_fps), maxi(flicker_frames, 1))


func _draw() -> void:
	_drawn_frame = _flicker()
	_drawn_angle = angle
	# Puff centres and radii, strung back along the flame's own -x axis.
	var centres := PackedVector2Array([Vector2.ZERO])
	var radii := PackedFloat32Array([head])
	for i in maxi(puffs, 0):
		var t := float(i + 1) / maxi(puffs, 1)
		var sway: float = SWAY[posmod(_drawn_frame * 2 + i, SWAY.size())]
		var size: float = PUFF[posmod(_drawn_frame + i, PUFF.size())]
		centres.append(Vector2(-length * t, sway))
		radii.append(lerpf(head, tail, t) * size)
	var reach := 0.0
	for i in centres.size():
		reach = maxf(reach, centres[i].length() + radii[i])
	_rasterise(centres, radii, int(ceil(reach)) + 1)


## Walks the flame's bounding box a pixel at a time, merging each row into
## runs so a row of one tone costs a single rect.
func _rasterise(centres: PackedVector2Array, radii: PackedFloat32Array, reach: int) -> void:
	var offset := PixelDraw.snap(self)
	# One inverse rotation per pixel puts it in the flame's frame, which keeps
	# the rects themselves axis-aligned and on the grid.
	var facing := Vector2.from_angle(-angle)
	for py in range(-reach, reach + 1):
		var run_from := 0
		var run_tone := -1
		# One past the end, so the last run is always closed off.
		for px in range(-reach, reach + 2):
			var tone := -1
			if px <= reach:
				tone = _tone_at(px, py, facing, centres, radii)
			if tone == run_tone:
				continue
			if run_tone >= 0:
				draw_rect(Rect2(Vector2(run_from, py) + offset,
					Vector2(px - run_from, 1)), tones[run_tone])
			run_from = px
			run_tone = tone


## Which tone the pixel at (px, py) is, or -1 if it is outside the flame or
## cut away by the dither. `depth` is how far inside the nearest puff it sits:
## 1 at a centre, 0 at an edge.
func _tone_at(px: int, py: int, facing: Vector2, centres: PackedVector2Array,
		radii: PackedFloat32Array) -> int:
	# Sample the middle of the pixel, rotated into the flame's own frame.
	var at := Vector2(px + 0.5, py + 0.5)
	var local := Vector2(at.x * facing.x - at.y * facing.y, at.x * facing.y + at.y * facing.x)
	var depth := 0.0
	for i in centres.size():
		var r := radii[i]
		if r > 0.0:
			depth = maxf(depth, 1.0 - local.distance_to(centres[i]) / r)
	if depth <= 0.0:
		return -1
	if depth > core_depth:
		return 0
	if depth > mid_depth:
		return 1
	# The rim burns ragged rather than ending on a clean curve.
	if PixelDraw.dither(px, py) >= edge_keep:
		return -1
	return 2
