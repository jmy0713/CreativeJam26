class_name LightBurst
extends Node2D
## The end of the final boss: it does not fall over, it goes out as light, and
## the light takes the screen with it.
##
## Two things on one clock, drawn by one node:
##
##   BURST  a white core with a ring of lumpy blobs thrown off it and rays shot
##          out past them. The same recipe as PuffCloud, opening outward
##          instead of puffing, and climbing the tone ramp toward white as it
##          ages instead of stepping down it -- this is something catching
##          light, not something cooling off.
##   WASH   from `wash_after` of the way through, the light eats the arena.
##          Cells of it flip to white as an ordered dither lets them, from the
##          burst outward, until the screen is white and there is nothing of
##          the fight left to look at.
##
## Then `finished` fires, and Boss.die() has hung GameManager.complete_level()
## off it -- so the cut to the ending happens under the white rather than in
## the middle of the arena. See boss.gd.
##
## House rules, same as the other effects drawn in code (section 7 of
## ARCHITECTURE.md): opaque tones only, no alpha and no antialiasing anywhere;
## the shape snaps between `frames` poses instead of sliding; it comes apart --
## and the wash comes together -- by gaining and losing whole pixels to an
## ordered dither; and the node is never rotated or scaled, so every rect
## stays on the pixel grid.
##
## Unlike the level's own effects it counts plain `delta` and runs its own
## clock. The boss is dead, the fight is over, and there is no timeline left
## worth rewinding it along. That is also why it is spawned into the level
## rather than parented to the boss: a dead boss hides itself and stops
## processing, and would take a child of its own down with it.

## Fires once the wash is solid and the screen is ready to be cut away.
signal finished

## Per-blob size and angle wobble on the ring, and the rays' own angles,
## reaches and thicknesses. Fixed tables rather than rolls: _draw() runs again
## on every pose, so anything random here would crawl between poses instead of
## the burst holding its shape while it opens.
const RING_LUMP := [1.0, 0.74, 1.18, 0.86, 1.1, 0.68, 0.95]
const RING_WOBBLE := [0.0, 0.28, -0.2, 0.14, -0.32, 0.22, -0.1]
const RAY_ANGLE := [-1.53, -0.72, 0.09, 0.84, 1.62, 2.44, -2.36, 3.02]
const RAY_REACH := [1.0, 0.72, 0.9, 0.62, 1.0, 0.8, 0.66, 0.86]
const RAY_GIRTH := [1.0, 0.7, 0.85, 0.62, 0.95, 0.75, 0.66, 0.8]

## Life of the whole thing, and how many poses it is cut into. The wash is the
## back half of it, so this is also how long the ending is kept waiting.
@export var duration := 1.5
@export var frames := 8

@export_group("Burst")
## World pixels per pixel of the burst. Coarser than a sprite on purpose: this
## is the arena's light, not a detail on the boss.
@export var pixel := 3.0
## The core, first pose to last.
@export var core_from := 8.0
@export var core_to := 34.0
## The ring of blobs around it: how far out they sit, and how big each is.
## Big enough that neighbours overlap while the ring is still tight, or the
## burst opens as a necklace of separate rings rather than one shape -- by the
## last pose they have outrun each other, which is when it should be coming
## apart anyway.
@export var ring_blobs := 7
@export var ring_from := 4.0
@export var ring_to := 64.0
@export var blob_from := 14.0
@export var blob_to := 11.0
## The rays past the ring: a stack of blobs each, tapering to a point. Enough
## beads that neighbours overlap near the body, for the same reason, and one
## ray per fixed angle so the star comes out even.
@export var rays := 8
@export var ray_beads := 7
@export var ray_to := 132.0
@export var ray_girth := 6.0
## Fraction of the burst's pixels still standing on the last pose -- by then
## the wash is over it anyway, so it is free to come apart.
@export_range(0.0, 1.0) var keep_to := 0.72
@export var keep_core := 1.8
@export var keep_edge := 0.72

@export_group("Wash")
## World pixels per pixel of the wash. Coarser again than the burst: it is the
## whole screen going, and at a finer grid the dither reads as noise rather
## than as light arriving in blocks.
@export var wash_pixel := 4.0
## How much of the life passes before the first of it lands.
@export_range(0.0, 1.0) var wash_after := 0.5
## How far past the furthest corner the front travels, so the corners are
## solid rather than only just reached.
@export var wash_overshoot := 1.1
## Grown onto the area before any of that. The window is not always exactly
## the game's aspect, and the few world pixels of slop that buys are outside
## the arena the boss hands over -- without this they stay unwashed and the
## fight shows through in a strip along the edge of the screen.
@export var wash_margin := 64.0
## How deep behind the front the dither runs, as a fraction of the reach. This
## is the ragged edge of the light: at 0 it would arrive as a hard circle.
@export_range(0.05, 1.0) var wash_feather := 0.45

@export_group("Look")
## Tone ramp, brightest first. Every tone fully opaque -- light paints over
## the arena, it does not tint it.
@export var tones: Array[Color] = [
	Color(1, 1, 1, 1),
	Color(1, 0.96, 0.82, 1),
	Color(1, 0.84, 0.46, 1),
	Color(0.99, 0.65, 0.22, 1),
]
## How deep into a blob each band of the ramp reaches, 0 at the edge. The
## outermost is what keeps the burst readable where it crosses something as
## bright as it is -- the boss dies in front of a white sun.
@export_range(0.0, 1.0) var core_depth := 0.62
@export_range(0.0, 1.0) var mid_depth := 0.3
@export_range(0.0, 1.0) var rim_depth := 0.1

var _time := 0.0
## The arena, in this node's own space: what the wash has to cover. Zero-sized
## until ignite() hands it over, which is what keeps the wash off screen until
## there is something for it to eat.
var _area := Rect2()
var _handed_over := false

## Which pose the current draw commands were built from. -1 = nothing yet.
var _drawn_step := -1


func _ready() -> void:
	visibility_changed.connect(_invalidate)
	set_process(false)


## Put the light where the boss was and tell it how much screen to swallow.
## `area` is in world coordinates -- the boss hands over its own arena bounds.
func ignite(at: Vector2, area: Rect2) -> void:
	global_position = at
	_area = Rect2(area.position - at, area.size).grow(wash_margin)
	_time = 0.0
	_drawn_step = -1
	_handed_over = false
	queue_redraw()
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	var step := _step()
	if step != _drawn_step:
		_drawn_step = step
		queue_redraw()
	if _time < duration:
		return
	# The last pose stays up: the scene change is deferred by a frame, and a
	# light that took itself down first would show the arena again underneath.
	set_process(false)
	if not _handed_over:
		_handed_over = true
		finished.emit()


func _invalidate() -> void:
	_drawn_step = -1


## Which of the `frames` poses the clock is on.
func _step() -> int:
	var t := _time / maxf(duration, 0.001)
	return clampi(int(t * frames), 0, maxi(frames - 1, 0))


func _draw() -> void:
	var step := _step()
	# How far through the life this pose is: 0 on the first, 1 on the last.
	var s := float(step) / float(maxi(frames - 1, 1))
	_draw_burst(s, step)
	# Over the burst, not under it: the wash is the light arriving, and what it
	# has covered is gone, the burst included.
	_draw_wash(s)


# --- The burst --------------------------------------------------------------

## The core, the ring and the rays, all of them blobs, all built in the
## burst's own pixels so a coarser `pixel` is the same shape in bigger blocks.
func _draw_burst(s: float, step: int) -> void:
	var cell := maxf(pixel, 1.0)
	var offset := PixelDraw.snap(self, cell)
	var centres := PackedVector2Array()
	var radii := PackedFloat32Array()
	var extent := lerpf(core_from, core_to, s) / cell
	centres.append(Vector2.ZERO)
	radii.append(extent)

	var spread := lerpf(ring_from, ring_to, s) / cell
	var blob := lerpf(blob_from, blob_to, s) / cell
	for i in maxi(ring_blobs, 0):
		var angle: float = TAU * i / maxi(ring_blobs, 1) + RING_WOBBLE[posmod(i, RING_WOBBLE.size())]
		var r: float = blob * RING_LUMP[posmod(i, RING_LUMP.size())]
		centres.append(Vector2(cos(angle), sin(angle)) * spread)
		radii.append(r)
		extent = maxf(extent, spread + r)

	# Each ray is a stack of blobs from the ring outward, thinning to a point,
	# so it reads as a shard of light rather than a drawn line.
	var reach := lerpf(ring_from, ray_to, s) / cell
	var girth := ray_girth / cell
	for i in maxi(rays, 0):
		var angle: float = RAY_ANGLE[posmod(i, RAY_ANGLE.size())]
		var dir := Vector2(cos(angle), sin(angle))
		var length: float = reach * RAY_REACH[posmod(i, RAY_REACH.size())]
		var thick: float = girth * RAY_GIRTH[posmod(i, RAY_GIRTH.size())]
		for b in maxi(ray_beads, 1):
			# 0 at the core, 1 at the tip.
			var along := float(b) / float(maxi(ray_beads - 1, 1))
			var r := lerpf(thick, thick * 0.3, along)
			centres.append(dir * (length * along))
			radii.append(r)
			extent = maxf(extent, length * along + r)

	_rasterise_blobs(centres, radii, int(ceil(extent)) + 1, lerpf(1.0, keep_to, s),
		step, cell, offset)


## Walks the burst's bounding box a pixel at a time, merging each row into runs
## so a row of one tone costs a single rect rather than one per pixel.
func _rasterise_blobs(centres: PackedVector2Array, radii: PackedFloat32Array, reach: int,
		keep: float, step: int, cell: float, offset: Vector2) -> void:
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
				draw_rect(Rect2(Vector2(run_from, py) * cell + offset,
					Vector2(px - run_from, 1) * cell), tones[run_tone])
			run_from = px
			run_tone = tone


## Which tone the pixel at (px, py) is, or -1 for one outside every blob or cut
## away by the dither. `depth` is how far inside the nearest blob it sits: 1 at
## a centre, 0 at an edge. The pose brightens the result rather than darkening
## it -- a tone up the ramp every other pose, toward the white it ends on.
func _tone_at(px: int, py: int, centres: PackedVector2Array, radii: PackedFloat32Array,
		keep: float, step: int) -> int:
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
	if keep < 1.0 and PixelDraw.dither(px, py) >= keep * lerpf(keep_edge, keep_core, depth):
		return -1
	var tone := 3
	if depth > core_depth:
		tone = 0
	elif depth > mid_depth:
		tone = 1
	elif depth > rim_depth:
		tone = 2
	# A tone up the ramp every third pose. Slower than the puff dims, on
	# purpose: climb it any faster and the whole burst is white by the second
	# pose, with no shape left to read.
	return clampi(tone - step / 3, 0, tones.size() - 1)


# --- The wash --------------------------------------------------------------

## The light arriving, cell by cell, from the burst outward. A cell is white
## once the dither lets it be, and the front drags a dithered edge behind it --
## which is the whole look: the screen does not fade, it fills in.
func _draw_wash(s: float) -> void:
	if s <= wash_after or _area.size.x <= 0.0 or _area.size.y <= 0.0:
		return
	var cell := maxf(wash_pixel, 1.0)
	var offset := PixelDraw.snap(self, cell)
	# 0 as the first of it lands, 1 when the screen is solid.
	var t := (s - wash_after) / maxf(1.0 - wash_after, 0.001)
	var reach := _corner_distance() * wash_overshoot
	var front := reach * t
	var feather := maxf(reach * wash_feather, 0.001)
	var white := tones[0]
	var from := Vector2i((_area.position / cell).floor())
	var to := Vector2i((_area.end / cell).ceil())
	for py in range(from.y, to.y + 1):
		var run_from := 0
		var filled := false
		# One past the end, so the last run is always closed off.
		for px in range(from.x, to.x + 2):
			var on := px <= to.x and _washed(px, py, cell, front, feather, t)
			if on == filled:
				continue
			if filled:
				draw_rect(Rect2(Vector2(run_from, py) * cell + offset,
					Vector2(px - run_from, 1) * cell), white)
			run_from = px
			filled = on


## Whether the cell at (px, py) has been taken by the light. Behind the front
## it is solid; within `feather` of it the ordered dither decides, so the edge
## arrives as scattered blocks. The last pose is forced solid -- a dither left
## anywhere in it would put holes in the screen the ending shows through.
func _washed(px: int, py: int, cell: float, front: float, feather: float, t: float) -> bool:
	if t >= 1.0:
		return true
	# Sample the middle of the cell.
	var distance := Vector2((px + 0.5) * cell, (py + 0.5) * cell).length()
	var amount := (front - distance) / feather
	if amount <= 0.0:
		return false
	if amount >= 1.0:
		return true
	return PixelDraw.dither(px, py) < amount


## Distance from the light to the furthest corner of the area it has to cover.
## The light can go out anywhere in the arena, so which corner that is moves
## with it.
func _corner_distance() -> float:
	var corners := PackedVector2Array([
		_area.position,
		_area.end,
		Vector2(_area.position.x, _area.end.y),
		Vector2(_area.end.x, _area.position.y),
	])
	var reach := 0.0
	for corner in corners:
		reach = maxf(reach, corner.length())
	return reach
