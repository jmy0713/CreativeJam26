@tool
class_name Platform
extends StaticBody2D
## Solid block. Set `size` in the inspector; the collision shape and the
## drawn surface follow it.
##
## Drawn with the disco strip in scenes/assets/disco_tiles: 12 frames of a
## rainbow bar whose stripes step sideways, tiled along the block. Wide
## blocks get the bar along their top edge (where the player stands); blocks
## taller than they are wide (walls) get it turned a quarter turn, centred.
##
## Can also be a jump-through platform (`one_way`): the player passes up
## through it from below and lands on top, and can press down to drop back
## off it (see Player._try_drop_through). Walls and the ground plane are
## never made one-way, whatever the flag says — see is_jump_through_shape().

## --- Disco strip art -----------------------------------------------------

const DISCO_FRAME_COUNT := 12
const DISCO_FRAME_PATH := "res://scenes/assets/disco_tiles/%02d.png"
## The strip's stripes repeat every 72px, so any 72-wide window of it tiles
## seamlessly. This one skips the rounded pixels at the strip's own ends.
const DISCO_SLICE := Rect2(12.0, 12.0, 72.0, 8.0)
## Frames per second the stripes step at. Whole frames only — never blended.
const DISCO_FPS := 12.0

## Shared by every platform; loaded once, on the first draw.
static var _disco_frames: Array[Texture2D] = []


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
var _drawn_frame := -1


func _ready() -> void:
	# The editor shows a still frame; only a running level animates.
	set_process(not Engine.is_editor_hint())
	_rebuild()


func _process(_delta: float) -> void:
	var frame := _disco_frame_index()
	if frame != _drawn_frame:
		_drawn_frame = frame
		queue_redraw()


## True when this block is actually behaving as a jump-through platform: the
## flag is on and the shape qualifies. The same test _apply_one_way() makes,
## exposed because the player asks it before dropping down through one (see
## Player._try_drop_through).
func is_one_way_active() -> bool:
	return one_way and is_jump_through_shape()


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
	shape_owner_set_one_way_collision(_owner_id, is_one_way_active())
	# Never leave this at the API's 0 default; see one_way_margin.
	shape_owner_set_one_way_collision_margin(_owner_id, maxf(one_way_margin, 0.1))


func _draw() -> void:
	var frames := _load_disco_frames()
	if frames.is_empty():
		draw_rect(Rect2(-size / 2.0, size), color)
		return

	var texture: Texture2D = frames[_disco_frame_index()]
	# Walls are taller than they are wide: lay the strip along the long side.
	var vertical := size.y > size.x
	var length := size.y if vertical else size.x
	var thickness := DISCO_SLICE.size.y
	if vertical:
		# In this rotated frame, local x runs down the wall and local y runs
		# across it, so the same tiling loop covers both cases.
		draw_set_transform(Vector2.ZERO, PI / 2.0)

	# Wide blocks wear the bar on top, where the player actually stands;
	# walls wear it down the middle.
	var across := -thickness / 2.0 if vertical else -size.y / 2.0
	var drawn := 0.0
	while drawn < length:
		var slice := DISCO_SLICE
		slice.size.x = minf(slice.size.x, length - drawn)
		# Snapped to whole pixels so the stripes stay crisp.
		var at := Vector2(roundf(-length / 2.0 + drawn), roundf(across))
		draw_texture_rect_region(texture, Rect2(at, slice.size), slice)
		drawn += DISCO_SLICE.size.x
	if vertical:
		draw_set_transform(Vector2.ZERO)


## Which strip frame is showing. Driven by the level clock, so the stripes
## freeze and run backwards with a recall, like everything else.
func _disco_frame_index() -> int:
	if Engine.is_editor_hint() or not is_inside_tree():
		return 0
	var seconds := GameManager.level_time_seconds()
	return posmod(int(seconds * DISCO_FPS), DISCO_FRAME_COUNT)


static func _load_disco_frames() -> Array[Texture2D]:
	if _disco_frames.is_empty():
		for i in DISCO_FRAME_COUNT:
			var texture := load(DISCO_FRAME_PATH % i) as Texture2D
			if texture:
				_disco_frames.append(texture)
	return _disco_frames
