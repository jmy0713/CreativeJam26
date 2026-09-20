class_name BlobShadow
extends Node2D
## The player's drop shadow: one round blob rasterised onto the pixel grid.
##
## The simplest shadow there is. It has no idea what it is falling on, so the
## owner only shows it while standing on a floor (see
## Player._update_visuals()); in the air there is nothing under it to lie on.
##
## Pixel art like the other effects drawn here: the ellipse is rasterised a
## row at a time into hard-edged rects, nothing is antialiased, and the rects
## are snapped so their corners land on whole world pixels. `color` carries the
## only alpha in any of these effects, because a shadow darkens whatever floor
## it is on rather than painting over it — set it to alpha 1 for a flat opaque
## blob instead.

@export var radius := 8.0
## Vertical squash: 1.0 is a circle, lower is a flatter ellipse.
@export_range(0.05, 1.0) var squash := 0.5
@export var color := Color(0.04, 0.04, 0.1, 0.42)
## How many world pixels one of the blob's own pixels is. 1 is the screen's
## grid, which is what anything standing on a tileset wants. The prologue's
## backdrop is painted at half the game's resolution, so the man walking down
## it casts a 2-pixel shadow: at 1 the blob is finer than the road it lies on
## and reads as a smudge from another game. `radius` stays in world pixels
## either way, so coarsening a shadow does not resize it.
@export var pixel := 1.0

## The snap offset the current rects were built with, so the blob is only
## re-rasterised when the player crosses a pixel boundary rather than every
## time it moves.
var _drawn_snap := Vector2(INF, INF)


func _ready() -> void:
	set_notify_transform(true)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and not PixelDraw.snap(self, _cell()).is_equal_approx(_drawn_snap):
		queue_redraw()


## One of the blob's pixels, in world pixels. Never smaller than the screen's
## own, which would only buy soft edges.
func _cell() -> float:
	return maxf(pixel, 1.0)


func _draw() -> void:
	var cell := _cell()
	_drawn_snap = PixelDraw.snap(self, cell)
	# The ellipse is rasterised in the blob's own pixels and only stretched
	# back out to world units on the way into draw_rect, so a coarse shadow is
	# the same shape drawn in bigger blocks rather than a bigger shadow.
	var rx := maxf(radius / cell, 0.5)
	var ry := maxf(radius * squash / cell, 0.5)
	var rows := int(ceil(ry))
	for py in range(-rows, rows + 1):
		# Sample the middle of the row: (x + 0.5)^2/rx^2 + (y + 0.5)^2/ry^2 <= 1.
		var fy := (py + 0.5) / ry
		if absf(fy) >= 1.0:
			continue
		var half := rx * sqrt(1.0 - fy * fy)
		var from := int(ceil(-half - 0.5))
		var to := int(floor(half - 0.5))
		if to < from:
			continue
		draw_rect(Rect2(Vector2(from, py) * cell + _drawn_snap,
			Vector2(to - from + 1, 1) * cell), color)
