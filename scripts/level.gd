class_name Level
extends Node2D
## Root script for every gameplay scene. Registers itself with GameManager,
## which then collects the player and enemies inside it.

@export var level_name := "Level"

## Make every platform in this level jump-through: the player can pass up
## through one from below and land on top. Walls and the ground plane stay
## solid automatically, so this is safe to switch on wholesale — see
## Platform.is_jump_through_shape(). New platforms added to the level inherit
## it without anyone having to remember.
@export var one_way_platforms := false


func _ready() -> void:
	if one_way_platforms:
		_apply_one_way(self)
	GameManager.register_level(self)


func _apply_one_way(node: Node) -> void:
	var platform := node as Platform
	if platform:
		platform.one_way = true
	for child in node.get_children():
		_apply_one_way(child)
