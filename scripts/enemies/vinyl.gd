class_name Vinyl
extends Area2D
## Vinyl record projectile thrown by DJ.gd. Flies in a straight line, spins
## for show, damages the player on contact, and disappears when it hits the
## world or times out.
##
## Not a recordable: it simply freezes along with the rest of the level while
## the level's process_mode is disabled during a recall, and resumes after.

@export var speed := 320.0
@export var damage := 1
@export var lifetime := 4.0
## Purely cosmetic — how fast the disc spins as it flies, in radians/sec.
@export var spin_speed := 16.0

var direction := Vector2.RIGHT

@onready var _life_timer: Timer = $LifeTimer
@onready var _spin_visual: Node2D = $SpinVisual


func _ready() -> void:
	_life_timer.wait_time = lifetime
	_life_timer.one_shot = true
	_life_timer.timeout.connect(queue_free)
	_life_timer.start()
	body_entered.connect(_on_body_entered)


## Point the vinyl from `from_position` toward `target_position` and place it.
func launch(from_position: Vector2, target_position: Vector2) -> void:
	global_position = from_position
	direction = (target_position - from_position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	if _spin_visual:
		_spin_visual.rotation += spin_speed * delta


func _on_body_entered(body: Node) -> void:
	var player := body as Player
	if player and player.health > 0:
		player.take_damage(damage, global_position)
	queue_free()
