class_name Fireball
extends Projectile
## Fire projectile breathed by Dragon.gd.
##
## The fireball travels toward the predetermined landing position but checks
## the world every physics frame. Walls and platforms on collision layer 1
## stop the projectile. The player can also be hit through Projectile's
## normal collision handling.

signal landed(at: Vector2)

var _origin := Vector2.ZERO
var _landing := Vector2.ZERO
var _land_distance := INF
var _has_landed := false


func launch(
	from_position: Vector2,
	target_position: Vector2
) -> void:
	super(from_position, target_position)
	rotation = direction.angle()


func launch_to_ground(
	from_position: Vector2,
	landing_position: Vector2
) -> void:
	# Player is still handled by Projectile.
	# World collision is handled manually below so we can stop on walls.
	collision_mask = 2

	_origin = from_position
	_landing = landing_position

	_land_distance = from_position.distance_to(
		landing_position
	)

	lifetime = maxf(
		lifetime,
		_land_distance / speed + 0.5
	)

	launch(
		from_position,
		landing_position
	)


func _physics_process(delta: float) -> void:
	if not alive:
		return

	# Store where we started this physics frame.
	var previous_position := global_position

	# Let Projectile handle its normal movement/damage/etc.
	super(delta)

	if not alive:
		return

	var current_position := global_position

	# Check the segment travelled this frame against the world.
	var world_hit := _check_world_collision(
		previous_position,
		current_position
	)

	if world_hit:
		global_position = world_hit.position

		_land(world_hit.position)
		return

	# Check whether we've reached our intended landing position.
	if (
		_origin.distance_to(global_position)
		>= _land_distance
	):
		global_position = _landing
		_land(_landing)


## Checks collision layer 1 between the previous and current positions.
## This prevents the fireball from tunnelling through thin walls when its
## movement between physics frames is large.
func _check_world_collision(
	from: Vector2,
	to: Vector2
) -> Dictionary:
	if from.is_equal_approx(to):
		return {}

	var space_state := get_world_2d().direct_space_state

	var query := PhysicsRayQueryParameters2D.create(
		from,
		to
	)

	# Layer 1 = world/platforms/walls.
	query.collision_mask = 1

	# Don't accidentally hit the fireball itself.
	query.exclude = [self]

	return space_state.intersect_ray(query)


func _land(at: Vector2) -> void:
	if _has_landed:
		return

	_has_landed = true

	landed.emit(at)

	_vanish()
