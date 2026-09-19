class_name Dragon
extends Enemy
## Big flying enemy. Hovers at a set altitude with a gentle bob, drifts
## toward the player's x position when they're close, and periodically
## breathes a Fireball at them after a short telegraph.
##
## Ignores gravity and world collision (collision_mask should be 0 in the
## scene) — it flies wherever the script tells it to, regardless of platforms.

const NEVER := GameManager.NEVER

@export_group("Flight")
@export var patrol_speed := 40.0
## How far from its spawn x it will drift while chasing or idling.
@export var patrol_width := 200.0
@export var chase_range := 420.0
@export var bob_height := 14.0
@export var bob_speed := 1.2

@export_group("Fire Breath")
@export var fireball_scene: PackedScene
@export var fire_range := 380.0
@export var fire_interval := 2.4
@export var fire_windup := 0.5
@export var fireball_speed := 260.0
@export var fireball_damage := 1

var direction := 1
var fire_start_tick := NEVER
var last_fire_tick := NEVER

var _origin_x := 0.0
var _base_altitude := 0.0

@onready var glow: ColorRect = $Glow


func _ready() -> void:
	super()
	_origin_x = global_position.x
	_base_altitude = global_position.y


func _physics_process(delta: float) -> void:
	if is_stunned():
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
	else:
		_behave(delta)
		_update_fire_breath()
	move_and_slide()
	# Hover bob is purely cosmetic; drive it directly rather than via velocity.
	global_position.y = _base_altitude + sin(GameManager.level_time_seconds() * bob_speed) * bob_height
	_update_visuals()


func _behave(delta: float) -> void:
	var player := GameManager.player
	var has_target := player != null and player.health > 0 \
		and absf(player.global_position.x - global_position.x) <= chase_range

	var desired_x: float
	if has_target:
		desired_x = clampf(player.global_position.x, _origin_x - patrol_width, _origin_x + patrol_width)
		direction = 1 if player.global_position.x >= global_position.x else -1
	else:
		desired_x = _origin_x + sin(GameManager.level_time_seconds() * bob_speed * 0.4) * patrol_width

	var dx := desired_x - global_position.x
	if absf(dx) < 4.0:
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, signf(dx) * patrol_speed, 400.0 * delta)


func is_winding_up() -> bool:
	return fire_start_tick != NEVER


func on_recall_finished() -> void:
	super()
	var now := GameManager.timeline_tick
	if fire_start_tick > now:
		fire_start_tick = NEVER
	if last_fire_tick > now:
		last_fire_tick = NEVER


# --- Internals ----------------------------------------------------------

func _update_fire_breath() -> void:
	var player := GameManager.player
	if player == null or player.health <= 0 or not alive:
		fire_start_tick = NEVER
		return

	if fire_start_tick == NEVER:
		var dist := global_position.distance_to(player.global_position)
		if dist <= fire_range and GameManager.ticks_since(last_fire_tick) >= _ticks(fire_interval):
			fire_start_tick = GameManager.timeline_tick
	elif GameManager.ticks_since(fire_start_tick) >= _ticks(fire_windup):
		_breathe_fire(player)
		last_fire_tick = GameManager.timeline_tick
		fire_start_tick = NEVER


func _breathe_fire(player: Player) -> void:
	if fireball_scene == null:
		return
	var fireball := fireball_scene.instantiate() as Fireball
	if fireball == null:
		return
	get_parent().add_child(fireball)
	fireball.speed = fireball_speed
	fireball.damage = fireball_damage
	fireball.launch(global_position, player.global_position)


func _update_visuals() -> void:
	super()
	if glow:
		glow.visible = is_winding_up()
		glow.position.x = 26.0 * direction


func _ticks(seconds: float) -> int:
	return GameManager.seconds_to_ticks(seconds)
