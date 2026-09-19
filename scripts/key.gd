extends Area2D
## Dropped where the level's strongest enemy dies. Picking it up unlocks
## the LevelExit door (see level_exit.gd / GameManager.is_level_unlocked()).
##
## Purely cosmetic bob; not a recordable — like other pickups/projectiles it
## simply freezes with the rest of the level while recall is active.

@export var bob_height := 4.4
@export var bob_speed := 2.4

var _rest_y := 0.0

@onready var body: ColorRect = $Body


func _ready() -> void:
	_rest_y = body.position.y
	body_entered.connect(_on_body_entered)


func _process(_delta: float) -> void:
	body.position.y = _rest_y + sin(GameManager.level_time_seconds() * bob_speed) * bob_height


func _on_body_entered(other: Node2D) -> void:
	if other is Player:
		GameManager.collect_key()
		queue_free()
