class_name Enemy
extends CharacterBody2D
## Base enemy: health, knockback, contact damage, and death.
##
## Dead enemies are NEVER freed (recall needs to revive them).
## die() hides the enemy, strips its collision layers so the player can't touch
## or hit it, and disables processing. revive() reverses that. Damage and death
## push undo events onto the Recall stack.
##
## Subclasses override _behave(delta) to drive movement.

signal died(enemy: Enemy)

@export var max_health := 3
@export var contact_damage := 1
@export var gravity := 777.8
@export var max_fall_speed := 416.6
@export var knockback_speed := 144.4
@export var hit_stun_time := 0.15
@export var hit_flash_time := 0.1

var health := 0
var alive := true
var last_hit_tick := GameManager.NEVER

## Set once this enemy has dropped a key, so re-dying after a revive
## (e.g. recalled and killed again) never drops a second one.
var _key_dropped := false

var _collision_layer := 0
var _collision_mask := 0
var _base_color := Color.WHITE

@onready var body: ColorRect = $Body


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("recordable")
	health = max_health
	_collision_layer = collision_layer
	_collision_mask = collision_mask
	_base_color = body.color


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)

	if is_stunned():
		velocity.x = move_toward(velocity.x, 0.0, 833.4 * delta)
	else:
		_behave(delta)

	move_and_slide()
	_update_visuals()


## Override in subclasses.
func _behave(_delta: float) -> void:
	pass


func is_stunned() -> bool:
	return GameManager.ticks_since(last_hit_tick) < GameManager.seconds_to_ticks(hit_stun_time)


func take_hit(damage: int, from_position: Vector2) -> void:
	if not alive:
		return
	Recall.record(self, &"damaged", _restore_hit.bind(health, last_hit_tick))
	health -= damage
	last_hit_tick = GameManager.timeline_tick
	var dir := signf(global_position.x - from_position.x)
	velocity.x = (dir if dir != 0.0 else 1.0) * knockback_speed
	if health <= 0:
		die()


func die() -> void:
	if not alive:
		return
	Recall.record(self, &"died", _set_alive.bind(true))
	_set_alive(false)
	died.emit(self)
	GameManager.notify_enemy_died(self)
	if self == GameManager.key_enemy and not _key_dropped:
		_key_dropped = true
		GameManager.drop_key(global_position)


func revive() -> void:
	health = max_health
	_set_alive(true)


func _set_alive(value: bool) -> void:
	alive = value
	visible = value
	collision_layer = _collision_layer if value else 0
	collision_mask = _collision_mask if value else 0
	process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED


func _update_visuals() -> void:
	var flashing := GameManager.ticks_since(last_hit_tick) < GameManager.seconds_to_ticks(hit_flash_time)
	body.color = Color.WHITE if flashing else _base_color


# --- Recall -----------------------------------------------------------------

func recall_sample() -> Dictionary:
	return {"position": global_position}


func apply_recall_sample(sample: Dictionary) -> void:
	global_position = sample.position


func on_recall_finished() -> void:
	velocity = Vector2.ZERO
	if last_hit_tick > GameManager.timeline_tick:
		last_hit_tick = GameManager.NEVER


func _restore_hit(previous_health: int, previous_hit_tick: int) -> void:
	health = previous_health
	last_hit_tick = previous_hit_tick
