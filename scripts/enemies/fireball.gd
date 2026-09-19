class_name Fireball
extends Projectile
## Fire projectile spawned by Dragon.gd. See Projectile for flight, damage,
## slashing and recall behavior.


func launch(from_position: Vector2, target_position: Vector2) -> void:
	super(from_position, target_position)
	rotation = direction.angle()
