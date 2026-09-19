extends Area2D
## Touching this with the player finishes the level — but only once the key
## dropped by the level's strongest enemy has been collected (see
## GameManager.key_enemy / is_level_unlocked()). Levels with no enemy to
## drop a key stay open, same as before this door was locked.

const COLOR_LOCKED := Color(0.75, 0.2, 0.15, 0.55)
const COLOR_UNLOCKED := Color(0.95, 0.95, 0.95, 0.3)

@onready var color_rect: ColorRect = $ColorRect


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _process(_delta: float) -> void:
	color_rect.color = COLOR_UNLOCKED if GameManager.is_level_unlocked() else COLOR_LOCKED


func _on_body_entered(body: Node2D) -> void:
	if body is Player and GameManager.is_level_unlocked():
		GameManager.complete_level()
