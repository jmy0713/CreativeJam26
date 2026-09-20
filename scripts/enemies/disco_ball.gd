class_name DiscoBall
extends DJ
## Level 2's boss: a disco ball parked on the booth platform. For now it
## reuses the DJ's attacks (Vinyl throws + Backup Dancer waves); the planned
## bullet-hell beams and projectile patterns will go here.
##
## Body is an AnimatedSprite2D looping the 3 fps "sparkle" animation. It
## sparkles faster while winding up a throw, in place of the DJ's DeckGlow.

@export var windup_sparkle_speed := 3.0

@onready var sprite: AnimatedSprite2D = $Body

func _physics_process(delta: float) -> void:
	_update_visuals()
	# keep running attacks
	
func _update_visuals() -> void:
	super()
	sprite.speed_scale = windup_sparkle_speed if is_winding_up_throw() else 1.0
