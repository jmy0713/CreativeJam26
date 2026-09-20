class_name PixelBomb
extends Node2D
## The plane's bomb, drawn as pixel art: a stubby shell with a lit highlight
## along its back and a fin block at the tail, rasterised onto the pixel grid.
##
## House rules, same as the other effects drawn here (see section 7 of
## ARCHITECTURE.md): opaque tones only, hard edges, and the node is never
## rotated — a rotated node rasterises off the grid and the shell comes out
## soft. The bomb tips over as it falls, so the angle comes in through
## set_angle() and every pixel is tested in the bomb's own frame instead.

## Half the shell's length and width. The nose points along the bomb's +x.
@export var shell := Vector2(6.5, 3.0)
## Where the fins start, as a fraction back along the shell, and how far they
## stand out past it.
@export_range(0.0, 1.0) var fin_from := 0.55
@export var fin_flare := 2.6
## Shell, lit edge, and fins. The highlight rides the side the nose points up
## towards, so a tumbling bomb catches the light as it turns.
@export var tones: Array[Color] = [
	Color(0.29, 0.31, 0.4, 1),
	Color(0.62, 0.66, 0.78, 1),
	Color(0.16, 0.17, 0.24, 1),
]
## How much of the shell's width the highlight takes.
@export_range(0.0, 1.0) var highlight := 0.42

## Direction the nose points, in radians.
var angle := 0.0

var _drawn := INF


func set_angle(radians: float) -> void:
	if is_equal_approx(radians, _drawn):
		return
	angle = radians
	queue_redraw()


func _draw() -> void:
	_drawn = angle
	var offset := PixelDraw.snap(self)
	var reach := int(ceil(maxf(shell.x, shell.y + fin_flare))) + 1
	# One inverse rotation per pixel puts it in the bomb's frame, which keeps
	# the rects themselves axis-aligned and on the grid.
	var facing := Vector2.from_angle(-angle)
	for py in range(-reach, reach + 1):
		var run_from := 0
		var run_tone := -1
		# One past the end, so the last run is always closed off.
		for px in range(-reach, reach + 2):
			var tone := -1
			if px <= reach:
				tone = _tone_at(px, py, facing)
			if tone == run_tone:
				continue
			if run_tone >= 0:
				draw_rect(Rect2(Vector2(run_from, py) + offset,
					Vector2(px - run_from, 1)), tones[run_tone])
			run_from = px
			run_tone = tone


## Which tone the pixel at (px, py) is, or -1 for a pixel off the bomb.
func _tone_at(px: int, py: int, facing: Vector2) -> int:
	# Sample the middle of the pixel, rotated into the bomb's own frame:
	# +x runs from tail to nose, +y is the side the highlight sits away from.
	var at := Vector2(px + 0.5, py + 0.5)
	var local := Vector2(at.x * facing.x - at.y * facing.y, at.x * facing.y + at.y * facing.x)
	var along := local.x / shell.x
	var across := local.y / shell.y
	if along * along + across * across <= 1.0:
		return 1 if across < -(1.0 - highlight) else 0
	# Fins: a wedge standing out from the back of the shell, widening to the
	# tail, so the bomb reads as pointed even end-on.
	var back := (-local.x - shell.x * fin_from) / maxf(shell.x * (1.0 - fin_from), 0.001)
	if back >= 0.0 and back <= 1.0 and absf(local.y) <= shell.y + fin_flare * back:
		return 2
	return -1
