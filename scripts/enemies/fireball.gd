class_name Fireball
extends Projectile
## Fire projectile breathed by Dragon.gd. See Projectile for flight, damage,
## slashing and recall behavior.
##
## launch_to_ground() flies it to a set landing point instead of until it
## hits something: it passes through the world (the dragon already picked a
## spot on solid ground) and emits `landed` on arrival, which the dragon
## turns into a FirePatch.

signal landed(at: Vector2)

var _origin := Vector2.ZERO
var _landing := Vector2.ZERO
var _land_distance := INF
## Landing only spawns fire once — a recall that rewinds the flight doesn't
## undo the FirePatch, so a replayed landing mustn't make a second one.
var _has_landed := false


func launch(from_position: Vector2, target_position: Vector2) -> void:
	super(from_position, target_position)
	rotation = direction.angle()


func launch_to_ground(from_position: Vector2, landing_position: Vector2) -> void:
	# Only the player (layer 2) stops it; the world is flown through.
	collision_mask = 2
	_origin = from_position
	_landing = landing_position
	_land_distance = from_position.distance_to(landing_position)
	lifetime = maxf(lifetime, _land_distance / speed + 0.5)
	launch(from_position, landing_position)


func _physics_process(delta: float) -> void:
	super(delta)
	if alive and _origin.distance_to(global_position) >= _land_distance:
		global_position = _landing
		if not _has_landed:
			_has_landed = true
			landed.emit(_landing)
		_vanish()
