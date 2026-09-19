extends CanvasLayer
## Persistent HUD (autoload). Reads everything from GameManager.

@onready var label: Label = $Label


func _process(_delta: float) -> void:
	var player := GameManager.player
	var hp := "-"
	if is_instance_valid(player):
		hp = "%d / %d" % [player.health, player.max_health]
	var level_name := "-"
	if is_instance_valid(GameManager.current_level):
		level_name = GameManager.current_level.level_name
	label.text = "%s    HP %s    Enemies %d    Level %.2fs    Run %.2fs    History %.1fs (%d events)%s\n%s" % [
		level_name,
		hp,
		GameManager.alive_enemies().size(),
		GameManager.level_time_seconds(),
		GameManager.ticks_to_seconds(GameManager.real_tick),
		Recall.history_seconds(),
		Recall.stack_size(),
		"    << RECALLING" if Recall.is_recalling else "",
		"Move/aim: WASD/Arrows   Jump: Space/C (x2)   Dash: Shift/X   Attack: Z/J (up/down to aim)   Recall: R",
	]
