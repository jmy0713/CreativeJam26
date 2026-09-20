class_name Walker
extends Enemy
## Patrols back and forth, turning at walls and ledges.

@export var speed := 38.8
@export_enum("Left:-1", "Right:1") var start_direction := -1

var direction := -1

@onready var ledge_check: RayCast2D = $LedgeCheck
@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")


func _ready() -> void:
	super()
	direction = start_direction

	if animated_sprite:
		# Hide only the old ColorRect.
		body.modulate.a = 0.0

		animated_sprite.play(&"default")


func _behave(_delta: float) -> void:
	if is_on_wall() or (is_on_floor() and not ledge_check.is_colliding()):
		direction = -direction

	ledge_check.position.x = absf(ledge_check.position.x) * direction

	velocity.x = direction * speed

	if animated_sprite:
		animated_sprite.flip_h = direction < 0


func recall_sample() -> Dictionary:
	var sample := super()
	sample.direction = direction
	return sample


func apply_recall_sample(sample: Dictionary) -> void:
	super(sample)
	direction = sample.direction
