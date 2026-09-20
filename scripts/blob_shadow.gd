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

## The snap offset the current rects were built with, so the blob is only
## re-rasterised when the player crosses a pixel boundary rather than every
## time it moves.
var _drawn_snap := Vector2(INF, INF)


func _ready() -> void:
	set_notify_transform(true)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and not PixelDraw.snap(self).is_equal_approx(_drawn_snap):
		queue_redraw()


func _draw() -> void:
	_drawn_snap = PixelDraw.snap(self)
	var rx := maxf(radius, 0.5)
	var ry := maxf(radius * squash, 0.5)
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
		draw_rect(Rect2(Vector2(from, py) + _drawn_snap, Vector2(to - from + 1, 1)), color)
