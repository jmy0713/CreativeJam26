extends Area2D
## Touching this with the player finishes the level — but only once the key
## dropped by the level's strongest enemy has been collected (see
## GameManager.key_enemy / is_level_unlocked()). Levels with no enemy to
## drop a key stay open, same as before this door was locked.
##
## Locked, the door just shows its art (with any tint the level gives this
## node). Unlocked, it warms toward yellow and a soft pulsing halo appears
## behind it.

## Colour the door leans toward while unlocked (overbright = glowing).
const UNLOCKED_TINT := Color(1.2, 1.05, 0.55)
## How far toward UNLOCKED_TINT the door leans, at the pulse's low and high.
const UNLOCKED_BLEND_MIN := 0.2
const UNLOCKED_BLEND_MAX := 0.45

@export var glow_pulse_speed := 3.0

## The level's tint for this door (the node's modulate in the level scene).
## Moved onto the door sprite so the halo keeps its own yellow.
var _base_tint := Color.WHITE

@onready var door: Sprite2D = $Door
@onready var glow: Sprite2D = $Glow


func _ready() -> void:
	_base_tint = modulate
	modulate = Color.WHITE
	body_entered.connect(_on_body_entered)


func _process(_delta: float) -> void:
	var unlocked := GameManager.is_level_unlocked()
	glow.visible = unlocked
	if not unlocked:
		door.modulate = _base_tint
		return
	var pulse := 0.5 + 0.5 * sin(GameManager.level_time_seconds() * glow_pulse_speed)
	door.modulate = _base_tint.lerp(UNLOCKED_TINT, lerpf(UNLOCKED_BLEND_MIN, UNLOCKED_BLEND_MAX, pulse))
	glow.modulate.a = lerpf(0.6, 1.0, pulse)


func _on_body_entered(body: Node2D) -> void:
	if body is Player and GameManager.is_level_unlocked():
		GameManager.complete_level()
