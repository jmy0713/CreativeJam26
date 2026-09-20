class_name PixelEmber
extends Node2D
## The ball of fire gathering in the dragon's mouth while it winds up, drawn
## as pixel art: a lumpy orb that swells and heats up over the windup, with
## sparks coming off the top once it is nearly ready.
##
## House rules, same as the other effects drawn here (see section 7 of
## ARCHITECTURE.md): opaque tones only, hard edges, a dither rather than
## transparency, and no rotation on the node.
##
## Doubles as the mouth itself: `dragon.gd` spawns its shot at this node's
## global position, so moving it moves where fire comes from.
##
## The flicker rides GameManager's clock, so it rewinds with a recall and
## holds still through a time stop; how far wound up the dragon is comes in
## from the owner through set_charge().

## Radius of the orb at the start of the windup and at the moment it fires.
@export var radius_from := 1.6
@export var radius_to := 5.6
## Lumps around the core, which is what stops it reading as a plain circle.
## Five, off-axis: four land on the compass points and the bright centres
## read as a plus sign rather than a ball.
@export var lobes := 5
@export var flicker_frames := 4
@export var flicker_fps := 14.0

@export_group("Look")
## Tone ramp from the middle outwards, matching PixelFlame and PixelFire.
@export var tones: Array[Color] = [
	Color(1, 0.96, 0.75, 1),
	Color(1, 0.65, 0.16, 1),
	Color(0.83, 0.26, 0.09, 1),
]
@export_range(0.0, 1.0) var core_depth := 0.58
@export_range(0.0, 1.0) var mid_depth := 0.22
## Fraction of the outermost pixels kept, for a ragged edge.
@export_range(0.0, 1.0) var edge_keep := 0.66
## Charge past which sparks start coming off the top.
@export_range(0.0, 1.0) var spark_from := 0.45
@export var spark_rise := 7.0

## Per-flicker-frame wobble on each lump, and where the sparks sit.
const WOBBLE := [1.0, 0.72, 1.18, 0.86, 0.94, 0.66]
const SPARK_X := [-2.0, 1.0, 3.0]
const SPARK_LIFT := [1.0, 0.55, 0.8]

## How far through the windup the dragon is, 0..1.
var charge := 0.0

var _drawn_frame := -1
var _drawn_charge := -1.0


func _physics_process(_delta: float) -> void:
	# Redraw only when the flicker actually steps.
	if _flicker() != _drawn_frame:
		queue_redraw()


func set_charge(t: float) -> void:
	var value := clampf(t, 0.0, 1.0)
	# A redraw per flicker step is plenty; the swell rides along with it.
	if absf(value - _drawn_charge) > 0.03:
		queue_redraw()
	charge = value


## Which flicker frame the shared clock is on.
func _flicker() -> int:
	return posmod(int(GameManager.level_time_seconds() * flicker_fps), maxi(flicker_frames, 1))


func _draw() -> void:
	_drawn_frame = _flicker()
	_drawn_charge = charge
	var r := lerpf(radius_from, radius_to, charge)
	var centres := PackedVector2Array([Vector2.ZERO])
	var radii := PackedFloat32Array([r])
	for i in maxi(lobes, 0):
		var a := TAU * i / maxi(lobes, 1) + 0.6 + _drawn_frame * 0.4
		var wobble: float = WOBBLE[posmod(_drawn_frame + i, WOBBLE.size())]
		centres.append(Vector2.from_angle(a) * r * 0.5)
		radii.append(r * 0.6 * wobble)
	# Cold and dim at the start of the windup, white-hot by the time it fires.
	_rasterise(centres, radii, int(ceil(r * 1.7)) + 1, int((1.0 - charge) * 1.9))
	if charge >= spark_from:
		_draw_sparks(r)


## Walks the orb's bounding box a pixel at a time, merging each row into runs
## so a row of one tone costs a single rect.
func _rasterise(centres: PackedVector2Array, radii: PackedFloat32Array, reach: int,
		cooling: int) -> void:
	var offset := PixelDraw.snap(self)
	for py in range(-reach, reach + 1):
		var run_from := 0
		var run_tone := -1
		# One past the end, so the last run is always closed off.
		for px in range(-reach, reach + 2):
			var tone := -1
			if px <= reach:
				tone = _tone_at(px, py, centres, radii, cooling)
			if tone == run_tone:
				continue
			if run_tone >= 0:
				draw_rect(Rect2(Vector2(run_from, py) + offset,
					Vector2(px - run_from, 1)), tones[run_tone])
			run_from = px
			run_tone = tone


## Which tone the pixel at (px, py) is, or -1 if it is outside the orb or cut
## away by the edge dither. `depth` is how far inside the nearest lump it
## sits: 1 at a centre, 0 at an edge.
func _tone_at(px: int, py: int, centres: PackedVector2Array, radii: PackedFloat32Array,
		cooling: int) -> int:
	# Sample the middle of the pixel.
	var at := Vector2(px + 0.5, py + 0.5)
	var depth := 0.0
	for i in centres.size():
		var r := radii[i]
		if r > 0.0:
			depth = maxf(depth, 1.0 - at.distance_to(centres[i]) / r)
	if depth <= 0.0:
		return -1
	if depth <= mid_depth and PixelDraw.dither(px, py) >= edge_keep:
		return -1
	var tone := 0 if depth > core_depth else (1 if depth > mid_depth else 2)
	return mini(tone + cooling, tones.size() - 1)


## Embers lifting off the top as the shot gets close.
func _draw_sparks(r: float) -> void:
	var offset := PixelDraw.snap(self)
	var through := inverse_lerp(spark_from, 1.0, charge)
	for i in SPARK_X.size():
		var lift: float = SPARK_LIFT[i] * spark_rise
		# Each spark is at its own point in the climb, so they trail apart.
		var up := fposmod(through + float(i) / SPARK_X.size(), 1.0)
		var at := Vector2(SPARK_X[i], -r - lift * up)
		draw_rect(Rect2(at.floor() + offset, Vector2.ONE), tones[1 if up < 0.6 else 2])
