@tool
class_name Platform
extends StaticBody2D
## Solid gray block. Set `size` in the inspector; the collision shape and the
## drawn rectangle follow it.

@export var size := Vector2(200, 20):
	set(value):
		size = value
		_rebuild()

@export var color := Color(0.4, 0.4, 0.4):
	set(value):
		color = value
		queue_redraw()

var _shape := RectangleShape2D.new()
var _owner_id := -1


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	_shape.size = size
	# Shape is added through the API instead of a child node so every instance
	# gets its own shape without saving extra resources into level scenes.
	if _owner_id == -1:
		_owner_id = create_shape_owner(self)
		shape_owner_add_shape(_owner_id, _shape)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-size / 2.0, size), color)
