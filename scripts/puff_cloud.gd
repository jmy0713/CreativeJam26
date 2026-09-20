class_name PuffCloud
extends Node2D
## The little cloud a double jump kicks out: a ring of lumpy blobs that
## expands, thins and dithers away over a few frames.
##
## Same rules as SlashArc, for the same reason — see it for the long version.
## Opaque tones only, no alpha and no antialiasing; the shape snaps between
## `frames` poses instead of moving continuously; it fades by losing pixels to
## an ordered dither rather than by going transparent; and the node is never
## rotated or scaled, so its rects stay on the pixel grid.
##
## The owner drops it at the feet on the air jump and holds it there by world
## position, so the cloud is left behind while the player rises away from it.
## It stays an ordinary child rather than going top_level, because it has to
## keep the player's z_index: the effects layer with him, and a node that
## leaves his z ends up behind the level's foreground tilemaps. The pose comes
## from a tick stamp, so it rewinds with a recall and holds still through a
## time stop.

## How many blobs the ring is made of.
@export var blobs := 6
## Vertical squash on the ring, so the cloud spreads sideways rather than
## ballooning — it reads as a puff kicked off the boots, not a smoke ball.
@export var ring_squash := 0.55
@export var frames := 4

@export_group("Spread")
## Radius of the ring the blobs sit on, first frame to last. Starts inside one
## blob (so the cloud is solid) and opens into a ring as it grows.
@export var spread_from := 1.5
@export var spread_to := 9.0
## Radius of each blob, first frame to last.
@export var blob_from := 5.0
@export var blob_to := 2.0
## Pixels the whole cloud sinks over its life, as the player leaves it behind.
@export var drift := 2.0

@export_group("Look")
## Tone ramp, brightest first. Each frame starts one tone further down it, so
## the cloud dims in steps instead of going transparent. All fully opaque.
@export var tones: Array[Color] = [
	Color(1, 1, 1, 1),
	Color(0.79, 0.83, 0.95, 1),
	Color(0.48, 0.52, 0.68, 1),
]
## How deep into a blob the bright core tone reaches, 0 at the edge.
@export_range(0.0, 1.0) var core_depth := 0.45
## Fraction of the cloud's pixels still standing on the last frame; the dither
## cuts away the rest, eating the edges well before the middle.
@export var keep_to := 0.35
@export var keep_core := 1.7
@export var keep_edge := 0.5

## Per-blob size and angle wobble, so the ring is lumpy rather than a clean
## circle. Fixed rather than random: anything rolled in _draw() would crawl
## from frame to frame instead of holding still.
const LUMP := [1.0, 0.78, 1.15, 0.88, 1.05, 0.72]
const WOBBLE := [0.0, 0.25, -0.18, 0.12, -0.3, 0.2]

## Progress through the cloud's life, 0..1.
var progress := 0.0

## Which frame the current draw commands were built from. -1 = nothing yet.
var _drawn_step := -1


func _ready() -> void:
	visibility_changed.connect(_invalidate)


func set_pose(t: float) -> void:
	progress = clampf(t, 0.0, 1.0)
	var step := _step()
	if step == _drawn_step:
		return
	_drawn_step = step
	queue_redraw()


func _invalidate() -> void:
	_drawn_step = -1


## Which of the `frames` poses `progress` lands on.
func _step() -> int:
	return mini(int(progress * frames), maxi(frames - 1, 0))


func _draw() -> void:
	var step := _step()
	# How far through the cloud's life this frame is: 0 on the first, 1 on the
	# last.
	var s := float(step) / float(maxi(frames - 1, 1))
	var spread := lerpf(spread_from, spread_to, s)
	var blob := lerpf(blob_from, blob_to, s)
	var keep := lerpf(1.0, keep_to, s)
	var centres := PackedVector2Array()
	var radii := PackedFloat32Array()
	var reach := 0.0
	for i in maxi(blobs, 1):
		var a: float = TAU * i / maxi(blobs, 1) + WOBBLE[posmod(i, WOBBLE.size())]
		var r: float = blob * LUMP[posmod(i, LUMP.size())]
		centres.append(Vector2(cos(a) * spread, sin(a) * spread * ring_squash + drift * s))
		radii.append(r)
		reach = maxf(reach, spread + r)
	_rasterise(centres, radii, int(ceil(reach)) + 1, keep, step)


## Walks the cloud's bounding box a pixel at a time, merging each row into
## runs so a row of one tone costs a single rect rather than one per pixel.
func _rasterise(centres: PackedVector2Array, radii: PackedFloat32Array, reach: int,
		keep: float, step: int) -> void:
	var offset := PixelDraw.snap(self)
	for py in range(-reach, reach + 1):
		var run_from := 0
		var run_tone := -1
		# One past the end, so the last run is always closed off.
		for px in range(-reach, reach + 2):
			var tone := -1
			if px <= reach:
				tone = _tone_at(px, py, centres, radii, keep, step)
			if tone == run_tone:
				continue
			if run_tone >= 0:
				draw_rect(Rect2(Vector2(run_from, py) + offset,
					Vector2(px - run_from, 1)), tones[run_tone])
			run_from = px
			run_tone = tone


## Which tone the pixel at (px, py) is, or -1 for a pixel outside every blob
## or cut away by the dither. `depth` is how far inside the nearest blob it
## sits: 1 at a centre, 0 at an edge.
func _tone_at(px: int, py: int, centres: PackedVector2Array, radii: PackedFloat32Array,
		keep: float, step: int) -> int:
	# Sample the middle of the pixel.
	var at := Vector2(px + 0.5, py + 0.5)
	var depth := 0.0
	for i in centres.size():
		var r := radii[i]
		if r <= 0.0:
			continue
		depth = maxf(depth, 1.0 - at.distance_to(centres[i]) / r)
	if depth <= 0.0:
		return -1
	if keep < 1.0 and PixelDraw.dither(px, py) >= keep * lerpf(keep_edge, keep_core, depth):
		return -1
	return mini(step + (0 if depth > core_depth else 1), tones.size() - 1)
