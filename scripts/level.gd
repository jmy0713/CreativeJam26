class_name Level
extends Node2D
## Root script for every gameplay scene. Registers itself with GameManager,
## which then collects the player and enemies inside it.

@export var level_name := "Level"


func _ready() -> void:
	GameManager.register_level(self)
