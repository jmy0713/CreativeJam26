class_name FirePatch
extends Area2D
## Lingering fire hazard left behind by Dragon.gd's fire breath. Sits in
## place and burns for `lifetime` seconds, damaging the player on contact.
## The player's own invincibility frames (see Player.take_damage) already
## govern how often standing in it can hurt, so this just checks for
## overlap on a steady interval rather than tracking hit cooldowns itself.

@export var damage := 1
@export var lifetime := 2.0
@export var damage_check_interval := 0.2

@onready var _life_timer: Timer = $LifeTimer
@onready var _tick_timer: Timer = $TickTimer


func _ready() -> void:
	_life_timer.wait_time = lifetime
	_life_timer.one_shot = true
	_life_timer.timeout.connect(queue_free)
	_life_timer.start()

	_tick_timer.wait_time = damage_check_interval
	_tick_timer.one_shot = false
	_tick_timer.timeout.connect(_damage_overlapping)
	_tick_timer.start()

	body_entered.connect(_damage_body)
	_damage_overlapping()


func _damage_overlapping() -> void:
	for body in get_overlapping_bodies():
		_damage_body(body)


func _damage_body(body: Node) -> void:
	var player := body as Player
	if player and player.health > 0:
		player.take_damage(damage, global_position)
