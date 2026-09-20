class_name Projectile
extends Area2D
## Base for enemy projectiles (Fireball, Vinyl). Flies in a straight line,
## damages the player on contact, and vanishes when it hits the world, is
## slashed by the player, or its lifetime runs out.
##
## Recordable: position is sampled by Recall so a rewind flies it backwards
## along its path. Vanishing never frees the node — it's hidden and pushes an
## undo event, so rewinding past the hit (or slash) brings it back. Rewinding
## past the launch hides it again, and it's freed once that recall finishes.

@export var speed := 144.4
@export var damage := 1
@export var lifetime := 4.0

var direction := Vector2.RIGHT
var alive := true

var _launch_tick := 0
## Set when a recall rewinds past the launch; freed when the recall ends.
var _unlaunched := false


func _ready() -> void:
	add_to_group("projectiles")
	add_to_group("recordable")
	body_entered.connect(_on_body_entered)


## Point the projectile from `from_position` toward `target_position` and
## place it. Call after adding it to the tree.
func launch(from_position: Vector2, target_position: Vector2) -> void:
	global_position = from_position
	direction = (target_position - from_position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	_launch_tick = GameManager.timeline_tick
	Recall.track(self)
	Recall.record(self, &"launched", _unlaunch)


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	if GameManager.ticks_since(_launch_tick) >= GameManager.seconds_to_ticks(lifetime):
		_vanish()


## Whether the player's slash can do anything to this one at all. False
## turns the projectile into something you dodge rather than deal with:
## Player._process_attack skips it entirely, so there is no destroy() and no
## pogo off a down-slash either. See DiscoBullet.
func is_slashable() -> bool:
	return true


## Slashed by the player.
func destroy() -> void:
	_vanish()


func _on_body_entered(body: Node) -> void:
	if not alive:
		return
	var player := body as Player
	if player and player.health > 0:
		player.take_damage(damage, global_position)
	_vanish()


func _vanish() -> void:
	if not alive:
		return
	# Sample the exact vanish point so the rewind path starts from here.
	Recall.sample_now(self)
	Recall.record(self, &"vanished", _set_alive.bind(true))
	_set_alive(false)


func _set_alive(value: bool) -> void:
	alive = value
	visible = value
	# Deferred: this can run inside a physics callback (body_entered).
	set_deferred(&"monitoring", value)
	set_deferred(&"monitorable", value)
	set_physics_process(value)


func _unlaunch() -> void:
	_unlaunched = true
	_set_alive(false)


# --- Time stop / Recall -----------------------------------------------------

## The timeline kept running while frozen; don't let that eat the lifetime.
func on_time_stop_ended(frozen_ticks: int) -> void:
	_launch_tick += frozen_ticks


func recall_sample() -> Dictionary:
	return {"position": global_position}


func apply_recall_sample(sample: Dictionary) -> void:
	global_position = sample.position


func on_recall_finished() -> void:
	if _unlaunched:
		remove_from_group("recordable")
		remove_from_group("projectiles")
		Recall.untrack(self)
		queue_free()
