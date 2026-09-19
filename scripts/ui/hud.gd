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
	var key_status := ""
	if is_instance_valid(GameManager.key_enemy):
		key_status = "    Key: COLLECTED" if GameManager.key_collected else "    Key: LOCKED (kill the strongest enemy)"
	label.text = "%s    HP %s%s    Enemies %d    Level %.2fs    Run %.2fs    History %.1fs (%d events)%s%s\n%s" % [
		level_name,
		hp,
		" (INVINCIBLE)" if GameManager.cheat_invincible else "",
		GameManager.alive_enemies().size(),
		GameManager.level_time_seconds(),
		GameManager.ticks_to_seconds(GameManager.real_tick),
		Recall.history_seconds(),
		Recall.stack_size(),
		"    << RECALLING" if Recall.is_recalling else ("    << TIME STOP" if TimeStop.is_active() else ""),
		key_status,
		"Move/aim: WASD/Arrows   Jump: Space/C (x2)   Dash: Shift/X   Attack: Z/J (up/down to aim)   Parry: V/K   Recall: R   Cheats: I invincible, N skip level",
	]
