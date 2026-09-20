class_name DiscoBullet
extends Projectile
## A round from the Disco Ball's bullet hell. Flies slowly in a straight
## line and hurts the player on contact — but unlike every other projectile
## here it cannot be dealt with, only dodged.
##
## Not breakable: is_slashable() is false, so Player._process_attack skips it
## outright — the slash neither destroys it nor pogos off it. Not parryable:
## it never calls Player.try_parry(), so there is no attack to deflect and no
## freeze to win. Both are the point of the attack — the answer to a wall of
## these is footwork, not the sword.
##
## It also ignores the world: collision_mask is the player alone, so a ring
## fired from the middle of the arena stays a whole ring instead of being
## eaten by the six jump-through platforms ringing the Disco Ball, and the
## platforms stay somewhere to stand rather than cover to hide behind.
## max_range is what cleans it up — distance from where it was fired is a
## tighter and more predictable bound than a lifetime on a bullet whose
## speed the boss retunes per attack.

## Vanishes once it is this far from where it was fired. 0 hands the job
## back to `lifetime`.
@export var max_range := 400.0

## Where launch() put it, for the max_range test.
var _fired_from := Vector2.ZERO


func launch(from_position: Vector2, target_position: Vector2) -> void:
	super(from_position, target_position)
	_fired_from = from_position


## The player's slash can do nothing to this one — see the class comment.
func is_slashable() -> bool:
	return false


## Backstop for anything that reaches past is_slashable() and calls this
## directly. A slashed bullet keeps flying.
func destroy() -> void:
	pass


func _physics_process(delta: float) -> void:
	super(delta)
	# super() may have vanished it on the lifetime, which stops physics — but
	# not before this line runs, so check before spending a second _vanish().
	if alive and max_range > 0.0 and _fired_from.distance_to(global_position) >= max_range:
		_vanish()

