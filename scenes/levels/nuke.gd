extends Sprite2D
## Level 4's skybox: holds `image_1`, then flashes white and comes back as
## `image_2` — the nuke going off in the background.
##
## Purely cosmetic and one-shot, so unlike gameplay code it runs off real
## seconds (tweens and scene timers) rather than timeline tick stamps. It is
## not a recordable: rewinding the level does not un-detonate the sky.

## Seconds of calm before the flash, and how long the screen stays white.
@export var delay_before := 5.0
@export var fade_in_time := 1.0
@export var hold_white_time := 3.0
@export var fade_out_time := 1.0

@export var image_1: Texture2D
@export var image_2: Texture2D
## Full-screen white ColorRect the flash is driven on.
@export var white_fade: ColorRect


func _ready() -> void:
	texture = image_1
	if white_fade == null:
		push_warning("nuke.gd has no white_fade assigned; skipping the flash")
		return
	white_fade.modulate.a = 0.0
	_detonate()


func _detonate() -> void:
	await get_tree().create_timer(delay_before).timeout
	await _fade_white_to(1.0, fade_in_time)

	# Swap the sky while the screen is fully white, so the cut is invisible.
	await get_tree().create_timer(hold_white_time).timeout
	texture = image_2

	await _fade_white_to(0.0, fade_out_time)


func _fade_white_to(alpha: float, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(white_fade, "modulate:a", alpha, duration)
	await tween.finished
