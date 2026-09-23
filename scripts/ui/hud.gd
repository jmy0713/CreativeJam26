extends CanvasLayer
## Persistent HUD (autoload). Reads everything from GameManager.
##
## The health bar sits in the top-left corner and is on for the whole of a
## level, with the controls hint printed under it. The debug readout to its
## right is off (SHOW_DEBUG_READOUT) — dev_mode still gates the cheat keys,
## so turning the readout back on for a debugging session is a one-line
## change that doesn't touch anything else.
##
## The whole layer hides whenever no level is in the tree, which is what
## keeps a health bar off the title screen. It's polled rather than driven by
## a signal because there are several ways out of a level (finishing one,
## dying, reloading) and only one of them announces itself; GameManager's
## reference to the freed level answers for all of them. The gap between two
## levels is hidden under the time warp anyway, so nothing blinks.

## Flip to true to get the dev readout (HP, timers, history depth) back.
const SHOW_DEBUG_READOUT := false

## Set while something else has the screen and a health bar floating over it
## would be wrong -- the light the final boss goes out in, which covers the
## arena on its way into the ending (see light_burst.gd and Boss.die()). The
## next level clears it, so nothing has to remember to put the HUD back.
var suppressed := false

@onready var label: Label = $Label
@onready var health_bar: HealthBar = $HealthBar


func _ready() -> void:
	GameManager.dev_mode_changed.connect(_apply_dev_mode)
	GameManager.level_started.connect(_on_level_started)
	_apply_dev_mode(GameManager.dev_mode)
	visible = GameManager.has_active_level()


func _on_level_started(_level: Level) -> void:
	suppressed = false


func _apply_dev_mode(on: bool) -> void:
	label.visible = on and SHOW_DEBUG_READOUT


func _process(_delta: float) -> void:
	visible = GameManager.has_active_level() and not suppressed
	if not label.visible:
		return
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
	label.text = "%s    HP %s%s    Enemies %d    Level %.2fs    Run %.2fs    History %.1fs (%d events)%s%s" % [
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
	]
