class_name SwordSwing
extends Node2D
## Placeholder sword drawn in code: a blade pointing out from this node's
## origin at `angle`, plus an optional fading arc trail from `trail_from` up
## to the blade.
##
## Owners set the pose every physics frame from their tick stamps (no
## AnimationPlayer), so the animation freezes with recall / time stop and
## stays in sync with the hitbox. Angles are for a right-facing swing;
## mirror it with scale.x = -1.

@export var inner_radius := 4.0
@export var blade_length := 20.0
@export var blade_width := 3.0
@export var color := Color(1, 1, 1, 0.95)
@export var trail_color := Color(1, 1, 1, 0.35)
@export var trail_segments := 10

var angle := 0.0
## NAN = no trail.
var trail_from := NAN


func set_pose(blade_angle: float, trail_start: float = NAN) -> void:
	angle = blade_angle
	trail_from = trail_start
	queue_redraw()


func _draw() -> void:
	if not is_nan(trail_from) and not is_equal_approx(trail_from, angle):
		_draw_trail()
	var dir := Vector2.from_angle(angle)
	var side := dir.orthogonal() * blade_width * 0.5
	var base := dir * inner_radius
	var tip := dir * (inner_radius + blade_length)
	draw_colored_polygon(PackedVector2Array([
		base + side, tip + side, tip + dir * blade_width, tip - side, base - side,
	]), color)


## Arc band behind the blade, transparent at `trail_from`, solid at the blade.
func _draw_trail() -> void:
	var r_outer := inner_radius + blade_length
	var r_inner := inner_radius + blade_length * 0.4
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	for i in trail_segments + 1:
		var t := float(i) / trail_segments
		points.append(Vector2.from_angle(lerpf(trail_from, angle, t)) * r_outer)
		colors.append(Color(trail_color, trail_color.a * t))
	for i in range(trail_segments, -1, -1):
		var t := float(i) / trail_segments
		points.append(Vector2.from_angle(lerpf(trail_from, angle, t)) * r_inner)
		colors.append(Color(trail_color, trail_color.a * t))
	draw_polygon(points, colors)
