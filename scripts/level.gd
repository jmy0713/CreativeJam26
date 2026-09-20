class_name Level
extends Node2D
## Root script for every gameplay scene. Registers itself with GameManager,
## which then collects the player and enemies inside it.

## Walls this thick are built down each screen edge; they sit entirely outside
## the play area, so only the inner face is ever touched.
const SIDE_WALL_THICKNESS := 32.0
## And this tall, centred on the screen: far above anything the player can jump
## to, and well below Player.kill_y, so there is no way around either end.
const SIDE_WALL_HEIGHT := 4000.0

@export var level_name := "Level"

## Make every platform in this level jump-through: the player can pass up
## through one from below and land on top. Walls and the ground plane stay
## solid automatically, so this is safe to switch on wholesale — see
## Platform.is_jump_through_shape(). New platforms added to the level inherit
## it without anyone having to remember.
@export var one_way_platforms := false

## Seal the left and right edges of the screen with invisible walls.
##
## Every level here is a single fixed 640x360 screen (the camera never moves),
## so the screen edge IS the level edge. Hand-placed wall blocks kept drifting
## off the ends of the floor — level 2's sat 10px outside it, which left a
## floor-less slot at each end the player could drop straight through — so the
## boundary is built here instead. It lands on the screen edge by construction,
## and a level added later gets it without anyone having to remember.
##
## Levels keep whatever wall blocks they already have; these are a backstop
## underneath them, not a replacement.
@export var side_walls := true


func _ready() -> void:
	if one_way_platforms:
		_apply_one_way(self)
	if side_walls:
		_build_side_walls()
	GameManager.register_level(self)


func _apply_one_way(node: Node) -> void:
	var platform := node as Platform
	if platform:
		platform.one_way = true
	for child in node.get_children():
		_apply_one_way(child)


## A wall down each screen edge, its inner face exactly on x = 0 and
## x = viewport width. The floor of every level reaches at least that far, so
## the player is stopped while there is still ground under their feet.
func _build_side_walls() -> void:
	var size := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 640)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 360)))
	_add_side_wall(&"SideWallLeft", -SIDE_WALL_THICKNESS / 2.0, size.y)
	_add_side_wall(&"SideWallRight", size.x + SIDE_WALL_THICKNESS / 2.0, size.y)


func _add_side_wall(wall_name: StringName, centre_x: float, screen_height: float) -> void:
	# A plain StaticBody2D rather than a Platform: nothing should draw it, and
	# it must never be caught by the one-way pass above.
	var wall := StaticBody2D.new()
	wall.name = wall_name
	wall.position = Vector2(centre_x, screen_height / 2.0)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(SIDE_WALL_THICKNESS, SIDE_WALL_HEIGHT)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	wall.add_child(collider)
	add_child(wall)
