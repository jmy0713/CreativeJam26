extends Area2D
## Touching this with the player finishes the level.


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		GameManager.complete_level()
