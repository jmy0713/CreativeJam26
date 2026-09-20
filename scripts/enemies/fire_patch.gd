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

## When the patch was lit, so the flames burn down on the timeline's clock
## and rewind with a recall. The lifetime itself is still on a Timer (see
## below), so the two can drift apart during a time stop.
var _lit_tick := 0

@onready var fire: PixelFire = $Fire
@onready var _life_timer: Timer = $LifeTimer
@onready var _tick_timer: Timer = $TickTimer


func _ready() -> void:
	_lit_tick = GameManager.timeline_tick
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


func _physics_process(_delta: float) -> void:
	fire.set_burn(GameManager.seconds_since(_lit_tick) / maxf(lifetime, 0.001))


func _damage_overlapping() -> void:
	for body in get_overlapping_bodies():
		_damage_body(body)


func _damage_body(body: Node) -> void:
	var player := body as Player
	if player and player.health > 0:
		player.take_damage(damage, global_position)
