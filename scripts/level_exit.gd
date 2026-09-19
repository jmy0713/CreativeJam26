extends Area2D
## Touching this with the player finishes the level — but only once the key
## dropped by the level's strongest enemy has been collected (see
## GameManager.key_enemy / is_level_unlocked()). Levels with no enemy to
## drop a key stay open, same as before this door was locked.

## Tint over the door sprite while the key is still out.
const TINT_LOCKED := Color(1.0, 0.45, 0.4, 1.0)
const TINT_UNLOCKED := Color.WHITE

@onready var door: Sprite2D = $Door


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _process(_delta: float) -> void:
	door.modulate = TINT_UNLOCKED if GameManager.is_level_unlocked() else TINT_LOCKED


func _on_body_entered(body: Node2D) -> void:
	if body is Player and GameManager.is_level_unlocked():
		GameManager.complete_level()
