@tool
class_name Platform
extends StaticBody2D
## Solid gray block. Set `size` in the inspector; the collision shape and the
## drawn rectangle follow it.
##
## Can also be a jump-through platform (`one_way`): the player passes up
## through it from below and lands on top. Walls and the ground plane are
## never made one-way, whatever the flag says — see is_jump_through_shape().

## A block at least this wide is the level's ground plane, not a platform.
## One-way ground is a trapdoor: anything that ends up a pixel below the
## surface falls out of the level instead of being pushed back up.
const GROUND_MIN_WIDTH := 400.0

@export var size := Vector2(112, 12):
	set(value):
		size = value
		_rebuild()

@export var color := Color(0.4, 0.4, 0.4):
	set(value):
		color = value
		queue_redraw()

## Jump-through: the player can pass up through this block and land on top.
## Ignored on walls and on the ground plane. Levels switch this on for every
## platform at once — see Level.one_way_platforms.
@export var one_way := false:
	set(value):
		one_way = value
		_apply_one_way()

## Contact depth, in pixels, that the one-way test accepts.
##
## This MUST be > 0. The shape here is built through create_shape_owner()
## rather than a CollisionShape2D node, and the two disagree on the default:
## the node sets 1.0, the shape-owner API leaves it at 0. Godot treats the
## margin as the deepest contact the one-way surface will accept, so at 0 it
## accepts nothing and the platform stops blocking from *either* side — the
## player drops straight through instead of landing.
##
## Wants to be at least the distance the player can fall in one frame
## (max_fall_speed 416.6 / 60 = ~7px) so a fast drop still lands, and well
## under the platform's own thickness (~9-11px here) so jumping up through
## one isn't caught on the way.
@export var one_way_margin := 8.0:
	set(value):
		one_way_margin = value
		_apply_one_way()

var _shape := RectangleShape2D.new()
var _owner_id := -1


func _ready() -> void:
	_rebuild()


## True for a block shaped like something you jump onto: wider than it is
## tall, and not the full-width ground. A wall fails the first test (the
## 23x23 cubes in level 2 count as walls, which is what we want), the ground
## fails the second.
func is_jump_through_shape() -> bool:
	var extent := _extent()
	return extent.x > extent.y and extent.x < GROUND_MIN_WIDTH


func _extent() -> Vector2:
	# Level scenes scale some platforms, and a few are nested inside another.
	var s := global_scale if is_inside_tree() else scale
	return (size * s).abs()


func _rebuild() -> void:
	_shape.size = size
	# Shape is added through the API instead of a child node so every instance
	# gets its own shape without saving extra resources into level scenes.
	if _owner_id == -1:
		_owner_id = create_shape_owner(self)
		shape_owner_add_shape(_owner_id, _shape)
	_apply_one_way()
	queue_redraw()


func _apply_one_way() -> void:
	if _owner_id == -1:
		return
	shape_owner_set_one_way_collision(_owner_id, one_way and is_jump_through_shape())
	# Never leave this at the API's 0 default; see one_way_margin.
	shape_owner_set_one_way_collision_margin(_owner_id, maxf(one_way_margin, 0.1))


func _draw() -> void:
	draw_rect(Rect2(-size / 2.0, size), color)
