class_name Vinyl
extends Projectile
## Vinyl record projectile thrown by DJ.gd. See Projectile for flight, damage
## and recall behavior; this just spins the disc for show.

## Purely cosmetic — how fast the disc spins as it flies, in radians/sec.
@export var spin_speed := 16.0

@onready var _spin_visual: Node2D = $SpinVisual


func _physics_process(delta: float) -> void:
	super(delta)
	if _spin_visual:
		_spin_visual.rotation += spin_speed * delta
