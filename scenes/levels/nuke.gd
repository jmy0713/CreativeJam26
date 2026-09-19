extends Sprite2D

@export var image_1: Texture2D
@export var image_2: Texture2D
@export var white_fade: ColorRect

func _ready():
	texture = image_1
	
	# Start with the white fade completely invisible
	white_fade.modulate.a = 0.0
	
	# Wait 5 seconds
	await get_tree().create_timer(5.0).timeout
	
	# Fade to white over 1 second
	var tween = create_tween()
	tween.tween_property(white_fade, "modulate:a", 1.0, 1.0)
	await tween.finished
	
	# Stay completely white for 3 seconds
	await get_tree().create_timer(3.0).timeout
	
	# Change the image while the screen is white
	texture = image_2
	
	# Fade the white screen away
	tween = create_tween()
	tween.tween_property(white_fade, "modulate:a", 0.0, 1.0)
