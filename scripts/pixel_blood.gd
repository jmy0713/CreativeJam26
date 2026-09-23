class_name PixelBlood
extends Node2D
## The blood thrown off the painter when you pick him: arms of it flung out
## from the body, droplets past their tips, a pool spreading under him, and the
## deep red mark the hit leaves on his back.
##
## `part` picks which of the three a node draws, because they layer at
## different depths on him: the pool is on the floor he is standing on, the
## mark is on the man himself, and the spatter is in the air between him and
## the camera. FinalCutscene therefore carries three of these -- one before
## `Painter` in the tree and two after -- and tree order alone does the
## layering, exactly as it does for the player's own effects. None of them may
## take a z_index; see section 7 of ARCHITECTURE.md.
##
## House rules, same as the other effects drawn in code (section 7 of
## ARCHITECTURE.md): opaque tones only, no alpha and no antialiasing anywhere;
## the shape snaps between `frames` poses instead of sliding; it comes apart by
## losing pixels to an ordered dither rather than going transparent; and the
## node is never rotated or scaled, so every rect stays on the pixel grid.
##
## Two things are its own. It is drawn in `pixel`-sized blocks rather than
## screen pixels, like BlobShadow, because it lands on a room painted four
## times coarser than the sprite bleeding onto it -- at 1:1 it reads as noise
## from a finer game. And the pool does not dither: spatter in the air thins
## out and breaks up, but what has already hit the floor stays put, so the
## last pose is a pool and a few settled specks rather than nothing.
##
## `progress` comes in from the owner through set_pose(), so it runs on
## whatever clock the owner is on -- FinalCutscene counts plain `delta`.

enum Part { SPATTER, POOL, MARK }

## Arms flung out from the middle. Angles are fixed, not rolled: _draw() runs
## again on every pose, so anything random here would jump from frame to frame
## instead of the spatter holding its shape while it travels.
const ARM_ANGLE := [-2.62, -1.98, -1.31, -0.58, 0.12, 0.74, 1.42, 2.16, 2.88]
## Per-arm reach and thickness, so no two arms are the same length.
const ARM_REACH := [1.0, 0.68, 1.18, 0.86, 0.52, 1.1, 0.78, 1.22, 0.62]
const ARM_GIRTH := [1.0, 0.76, 1.2, 0.92, 0.66, 1.12, 0.84, 1.04, 0.72]
## How far past its arm's tip each droplet flies.
const DROP_FLY := [1.42, 1.25, 1.5, 1.3, 1.6, 1.34, 1.48, 1.22, 1.55]

@export var part := Part.SPATTER
@export var frames := 5
## How many world pixels one of the blood's own pixels is. The room this plays
## in is painted at 4, the man bleeding at 1; 2 sits between them so the
## spatter reads as part of the picture without going as coarse as the
## wallpaper. Sizes below stay in world pixels either way, so changing this
## re-blocks the blood rather than resizing it.
@export var pixel := 2.0

@export_group("Spatter")
@export var arms := 9
## Blobs stacked along each arm. Enough that neighbours overlap, or an arm
## reads as a row of beads rather than one tapering streak.
@export var beads := 7
## How far the longest arm reaches, first pose to last: it is flung outward.
@export var reach_from := 10.0
@export var reach_to := 70.0
## Arm thickness at the body and at the tip, first pose and last -- it thins
## as it travels, the way a thrown streak does.
@export var girth_near_from := 5.5
@export var girth_near_to := 3.0
@export var girth_far_from := 2.4
@export var girth_far_to := 0.9
## Droplet size, and how much of the life passes before any break away.
@export var drop_radius := 2.2
@export_range(0.0, 1.0) var drop_after := 0.25

@export_group("Pool")
## Where the pool sits below the origin -- put the origin on the body and this
## on the floor under it.
@export var pool_y := 104.0
## Half-width and half-height of the pool on the last pose. It opens out of
## nothing, so there is no "from".
@export var pool_half_width := 44.0
@export var pool_half_height := 4.5
## Per-blob size wobble, so the puddle has a lumpy edge rather than reading as
## a lozenge. Fixed, not rolled -- see ARM_ANGLE.
@export var pool_lump: Array[float] = [1.0, 0.72, 1.2, 0.86, 1.12, 0.66, 0.95]
## Of the life, how much has passed before the first blood lands.
@export_range(0.0, 1.0) var pool_after := 0.35

@export_group("Mark")
## Radius of the mark, in world pixels. It is the wound rather than blood in
## flight, so this is a size it opens at and keeps: nothing here is lerped.
@export var mark_radius := 18.0

@export_group("Look")
## Tone ramp, brightest first. Every tone fully opaque -- blood paints over
## the floor, it does not tint it.
@export var tones: Array[Color] = [
	Color(0.85, 0.16, 0.17, 1),
	Color(0.58, 0.08, 0.12, 1),
	Color(0.33, 0.04, 0.08, 1),
]
## Where on the ramp this part starts. The pool is a tone down from the
## spatter: it is blood that has already run off and gone dark, and a puddle
## as bright as an open wound reads as a slab of paint on the floor.
@export var tone_from := 0
## How deep into a blob the bright core and the mid tone reach, 0 at the edge.
@export_range(0.0, 1.0) var core_depth := 0.55
@export_range(0.0, 1.0) var mid_depth := 0.2
## Fraction of the spatter's pixels still standing on the last pose. The
## dither cuts away the rest, eating the thin edges well before the cores.
@export_range(0.0, 1.0) var keep_to := 0.52
@export var keep_core := 1.6
@export var keep_edge := 0.5

## How far through the splash this is, 0..1. Holds at 1: the pool stays.
var progress := 0.0

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


func _step() -> int:
	return mini(int(progress * frames), maxi(frames - 1, 0))


func _draw() -> void:
	var step := _step()
	# How far through the splash this pose is: 0 on the first, 1 on the last.
	var s := float(step) / float(maxi(frames - 1, 1))
	var cell := maxf(pixel, 1.0)
	var offset := PixelDraw.snap(self, cell)
	match part:
		Part.POOL:
			_draw_pool(s, cell, offset)
		Part.MARK:
			_draw_mark(cell, offset)
		_:
			_draw_spatter(s, cell, offset, step)


# --- The three parts --------------------------------------------------------

## The arms and their droplets. Everything is built in the blood's own pixels
## rather than world ones, so a coarser `pixel` is the same splash drawn in
## bigger blocks.
func _draw_spatter(s: float, cell: float, offset: Vector2, step: int) -> void:
	var reach := lerpf(reach_from, reach_to, s) / cell
	var near := lerpf(girth_near_from, girth_near_to, s) / cell
	var far := lerpf(girth_far_from, girth_far_to, s) / cell
	var centres := PackedVector2Array()
	var radii := PackedFloat32Array()
	var extent := 0.0
	for i in maxi(arms, 1):
		var angle: float = ARM_ANGLE[posmod(i, ARM_ANGLE.size())]
		var dir := Vector2(cos(angle), sin(angle))
		var length: float = reach * ARM_REACH[posmod(i, ARM_REACH.size())]
		var girth: float = ARM_GIRTH[posmod(i, ARM_GIRTH.size())]
		for b in maxi(beads, 1):
			# 0 at the body, 1 at the tip.
			var along := float(b) / float(maxi(beads - 1, 1))
			var r := lerpf(near, far, along) * girth
			centres.append(dir * (length * along))
			radii.append(r)
			extent = maxf(extent, length * along + r)
		if s > drop_after:
			var fly: float = DROP_FLY[posmod(i, DROP_FLY.size())]
			var r := drop_radius / cell * girth
			centres.append(dir * (length * fly))
			radii.append(r)
			extent = maxf(extent, length * fly + r)
	_rasterise(centres, radii, Vector2i.ZERO, int(ceil(extent)) + 1,
		lerpf(1.0, keep_to, s), step, cell, offset)


## What has already hit the floor: a line of blobs, so it spreads as a puddle
## rather than a circle. It never dithers -- see the class comment.
func _draw_pool(s: float, cell: float, offset: Vector2) -> void:
	if s <= pool_after:
		return
	# 0 as the first blood lands, 1 at the end.
	var t := (s - pool_after) / maxf(1.0 - pool_after, 0.001)
	var half := pool_half_width * t / cell
	var r := pool_half_height / cell
	if half <= 0.0 or r <= 0.0:
		return
	var centres := PackedVector2Array()
	var radii := PackedFloat32Array()
	# Enough blobs that neighbours always overlap, however wide the puddle has
	# got: a fixed count spreads them apart as it grows and the pool comes out
	# as a row of separate spots instead of one sheet.
	var blobs := maxi(int(ceil(half / maxf(r * 0.5, 0.25))) + 1, 3)
	var widest := 0.0
	for i in blobs:
		var along := float(i) / float(blobs - 1) * 2.0 - 1.0
		var lump: float = pool_lump[posmod(i, pool_lump.size())] if not pool_lump.is_empty() else 1.0
		centres.append(Vector2(along * half, 0.0))
		radii.append(r * lump)
		widest = maxf(widest, r * lump)
	_rasterise(centres, radii, Vector2i(0, int(round(pool_y / cell))),
		Vector2i(int(ceil(half + widest)) + 1, int(ceil(widest)) + 1), 1.0, 0, cell, offset)


## Where the hit landed: one opaque disc on the body, up with the first of the
## spatter. It is the only part that does not move -- a wound neither travels
## nor thins out, so it is drawn at the same size and the same tones on every
## pose (`step` 0, `keep` 1), and the last frame of the shot still has it. The
## ramp does the shading: a core, a mid ring and a dark rim, which is what
## keeps it from reading as a sticker.
func _draw_mark(cell: float, offset: Vector2) -> void:
	var r := mark_radius / cell
	if r <= 0.0:
		return
	var centres := PackedVector2Array([Vector2.ZERO])
	var radii := PackedFloat32Array([r])
	_rasterise(centres, radii, Vector2i.ZERO, int(ceil(r)) + 1, 1.0, 0, cell, offset)


# --- Rasteriser -------------------------------------------------------------

## Walks the bounding box a pixel at a time, merging each row into runs so a
## row of one tone costs a single rect rather than one per pixel. `extent` is
## either a radius (an int) or a half-width/half-height pair.
func _rasterise(centres: PackedVector2Array, radii: PackedFloat32Array, at: Vector2i,
		extent: Variant, keep: float, step: int, cell: float, offset: Vector2) -> void:
	var box: Vector2i = extent if extent is Vector2i else Vector2i(extent, extent)
	for py in range(-box.y, box.y + 1):
		var run_from := 0
		var run_tone := -1
		# One past the end, so the last run is always closed off.
		for px in range(-box.x, box.x + 2):
			var tone := -1
			if px <= box.x:
				tone = _tone_at(px, py, at, centres, radii, keep, step)
			if tone == run_tone:
				continue
			if run_tone >= 0:
				draw_rect(Rect2(Vector2(run_from + at.x, py + at.y) * cell + offset,
					Vector2(px - run_from, 1) * cell), tones[run_tone])
			run_from = px
			run_tone = tone


## Which tone the pixel at (px, py) is, or -1 for one outside every blob or cut
## away by the dither. `depth` is how far inside the nearest blob it sits: 1 at
## a centre, 0 at an edge. Dithered on its own coordinates rather than the
## offset ones, so the pattern holds still as the splash grows.
func _tone_at(px: int, py: int, at: Vector2i, centres: PackedVector2Array,
		radii: PackedFloat32Array, keep: float, step: int) -> int:
	# Sample the middle of the pixel.
	var point := Vector2(px + 0.5, py + 0.5)
	var depth := 0.0
	for i in centres.size():
		var r := radii[i]
		if r <= 0.0:
			continue
		depth = maxf(depth, 1.0 - point.distance_to(centres[i]) / r)
	if depth <= 0.0:
		return -1
	if keep < 1.0 and PixelDraw.dither(px + at.x, py + at.y) >= keep * lerpf(keep_edge, keep_core, depth):
		return -1
	var tone := 2
	if depth > core_depth:
		tone = 0
	elif depth > mid_depth:
		tone = 1
	# Darkens as it ages, a tone every other pose.
	return mini(tone + tone_from + step / 2, tones.size() - 1)
