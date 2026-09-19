class_name Walker
extends Enemy
## Patrols back and forth, turning at walls and ledges.

@export var speed := 70.0
@export_enum("Left:-1", "Right:1") var start_direction := -1

var direction := -1

@onready var ledge_check: RayCast2D = $LedgeCheck


func _ready() -> void:
	super()
	direction = start_direction


func _behave(_delta: float) -> void:
	if is_on_wall() or (is_on_floor() and not ledge_check.is_colliding()):
		direction = -direction
	ledge_check.position.x = absf(ledge_check.position.x) * direction
	velocity.x = direction * speed


func recall_sample() -> Dictionary:
	var sample := super()
	sample.direction = direction
	return sample


func apply_recall_sample(sample: Dictionary) -> void:
	super(sample)
	direction = sample.direction
