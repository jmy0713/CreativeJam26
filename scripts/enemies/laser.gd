class_name Laser
extends Projectile
## Straight laser fired by RobotBoss. Flies, damages the player and vanishes
## on the world/lifetime — all inherited from Projectile — but being
## SLASHED does something different from a normal projectile: instead of
## just vanishing, it REFLECTS.
##
## A reflected laser reverses direction, speeds up, stops being able to hurt
## the player, and starts being able to hurt enemies instead. If it reaches
## the robot that fired it, the hit bypasses the guard entirely
## (Enemy.hit_through_guard(), same path a parried punch uses) — reflecting
## the laser back is the intended way to punish the boss while its guard is
## up between punches.

## Layers: 1 world, 2 player, 3 enemy (value 4), 4 projectile (value 8).
const WORLD_AND_PLAYER := 3
const WORLD_AND_ENEMY := 5
const REFLECTED_COLOR := Color(0.35, 1.0, 0.45, 1)

@export var reflect_damage := 1
## Reflected shots fly faster, so ping-ponging it back is a real punish, not
## a slow lob the boss can just walk away from.
@export var reflect_speed_multiplier := 1.35

var reflected := false

@onready var _body: ColorRect = get_node_or_null("Body")


func launch(from_position: Vector2, target_position: Vector2) -> void:
	super(from_position, target_position)
	rotation = direction.angle()


## Slashed by the player (see Player._process_attack): reflect instead of
## vanishing. Safe to call more than once — later slashes on an already
## reflected beam are a no-op, it's already flying the other way.
func destroy() -> void:
	if not alive or reflected:
		return
	reflected = true
	direction = -direction
	rotation = direction.angle()
	speed *= reflect_speed_multiplier
	# Stop threatening the player, start threatening enemies.
	collision_mask = WORLD_AND_ENEMY
	if _body:
		_body.color = REFLECTED_COLOR


func _on_body_entered(body: Node) -> void:
	if not alive:
		return
	if reflected:
		var enemy := body as Enemy
		if enemy and enemy.alive:
			if enemy.has_method(&"hit_through_guard"):
				enemy.hit_through_guard(reflect_damage, global_position)
			else:
				enemy.take_hit(reflect_damage, global_position)
		_vanish()
		return
	super(body)
