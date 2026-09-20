class_name PixelFire
extends Node2D
## A patch of fire burning on the ground, drawn as pixel art: a row of flame
## tongues that flicker, and die down as the patch burns out.
##
## House rules, same as the other effects drawn here (see section 7 of
## ARCHITECTURE.md): opaque tones only, hard edges, and it fades by losing
## pixels to a dither and stepping down the ramp rather than by going
## transparent. The origin sits on the ground and the flames stand up in -y.
##
## The flicker rides GameManager's clock, so it rewinds with a recall and
## holds still through a time stop; how far burnt the patch is comes in from
## the owner through set_burn().

## How wide the row of tongues is, and how tall the tallest stands.
@export var width := 32.0
@export var height := 17.0
@export var tongues := 5
## Radius of a tongue at the ground and at its tip.
@export var base := 4.4
@export var tip := 0.9
## Blobs stacked up each tongue. Enough that neighbours overlap: any fewer
## and a tongue reads as a stack of beads rather than one tapering flame.
@export var stack := 7
@export var flicker_frames := 4
@export var flicker_fps := 12.0

@export_group("Look")
## Tone ramp from the middle of the flame outwards, matching PixelFlame.
@export var tones: Array[Color] = [
	Color(1, 0.96, 0.75, 1),
	Color(1, 0.65, 0.16, 1),
	Color(0.83, 0.26, 0.09, 1),
]
@export_range(0.0, 1.0) var core_depth := 0.6
@export_range(0.0, 1.0) var mid_depth := 0.24
## Fraction of the outermost pixels kept, for a ragged edge.
@export_range(0.0, 1.0) var edge_keep := 0.62
## How much of the fire is left standing at the end of the burn, and how far
## it shrinks by then.
@export_range(0.0, 1.0) var die_keep := 0.22
@export_range(0.0, 1.0) var die_shrink := 0.45

## Per-tongue height and lean, stepped through by the flicker so the tongues
## wave out of step with one another. Fixed rather than random: _draw() runs
## again on every flicker, so anything rolled here would crawl.
const TALL := [1.0, 0.66, 1.18, 0.84, 0.97, 0.6, 1.1]
const LEAN := [0.0, 0.6, -0.45, 0.3, -0.7, 0.15, 0.4]

## How far through the patch's life the fire is, 0..1.
var burn := 0.0

var _drawn_frame := -1
var _drawn_burn := -1.0


func _physics_process(_delta: float) -> void:
	# Redraw only when the flicker actually steps.
	if _flicker() != _drawn_frame:
		queue_redraw()


func set_burn(t: float) -> void:
	var value := clampf(t, 0.0, 1.0)
	# A redraw per flicker step is plenty; the burn rides along with it.
	if absf(value - _drawn_burn) > 0.02:
		queue_redraw()
	burn = value


## Which flicker frame the shared clock is on.
func _flicker() -> int:
	return posmod(int(GameManager.level_time_seconds() * flicker_fps), maxi(flicker_frames, 1))


func _draw() -> void:
	_drawn_frame = _flicker()
	_drawn_burn = burn
	var wither := lerpf(1.0, die_shrink, burn)
	var centres := PackedVector2Array()
	var radii := PackedFloat32Array()
	var count := maxi(tongues, 1)
	for i in count:
		var at_x := 0.0 if count == 1 else lerpf(-width * 0.5, width * 0.5, float(i) / (count - 1))
		var tall: float = TALL[posmod(_drawn_frame + i, TALL.size())] * wither
		var lean: float = LEAN[posmod(_drawn_frame + i * 3, LEAN.size())]
		for j in maxi(stack, 1):
			var up := 0.0 if stack <= 1 else float(j) / (stack - 1)
			# The sway builds towards the tip; the root stays put on the ground.
			centres.append(Vector2(at_x + lean * up * up * 4.5, -height * tall * up))
			radii.append(lerpf(base, tip, up) * wither)
	_rasterise(centres, radii)


## Walks the patch's bounding box a pixel at a time, merging each row into
## runs so a row of one tone costs a single rect.
func _rasterise(centres: PackedVector2Array, radii: PackedFloat32Array) -> void:
	var offset := PixelDraw.snap(self)
	var box := Rect2(centres[0], Vector2.ZERO)
	for i in centres.size():
		box = box.expand(centres[i] - Vector2.ONE * radii[i])
		box = box.expand(centres[i] + Vector2.ONE * radii[i])
	var x0 := int(floor(box.position.x))
	var x1 := int(ceil(box.end.x))
	var y0 := int(floor(box.position.y))
	var y1 := int(ceil(box.end.y))
	var keep := lerpf(1.0, die_keep, burn)
	# As it dies the fire loses its heat as well as its size.
	var cooling := int(burn * 1.9)
	for py in range(y0, y1 + 1):
		var run_from := 0
		var run_tone := -1
		# One past the end, so the last run is always closed off.
		for px in range(x0, x1 + 2):
			var tone := -1
			if px <= x1:
				tone = _tone_at(px, py, centres, radii, keep, cooling)
			if tone == run_tone:
				continue
			if run_tone >= 0:
				draw_rect(Rect2(Vector2(run_from, py) + offset,
					Vector2(px - run_from, 1)), tones[run_tone])
			run_from = px
			run_tone = tone


## Which tone the pixel at (px, py) is, or -1 if it is outside the fire or
## cut away by a dither. `depth` is how far inside the nearest blob it sits:
## 1 at a centre, 0 at an edge.
func _tone_at(px: int, py: int, centres: PackedVector2Array, radii: PackedFloat32Array,
		keep: float, cooling: int) -> int:
	# Sample the middle of the pixel.
	var at := Vector2(px + 0.5, py + 0.5)
	var depth := 0.0
	for i in centres.size():
		var r := radii[i]
		# Cheap reject before the distance: most blobs are nowhere near.
		if r <= 0.0 or absf(at.x - centres[i].x) > r or absf(at.y - centres[i].y) > r:
			continue
		depth = maxf(depth, 1.0 - at.distance_to(centres[i]) / r)
	if depth <= 0.0:
		return -1
	var dither := PixelDraw.dither(px, py)
	# The rim burns ragged rather than ending on a clean curve, and the whole
	# patch thins out as it dies.
	if depth <= mid_depth and dither >= edge_keep:
		return -1
	if keep < 1.0 and dither >= keep:
		return -1
	var tone := 0 if depth > core_depth else (1 if depth > mid_depth else 2)
	return mini(tone + cooling, tones.size() - 1)
