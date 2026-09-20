class_name RobotBoss
extends Robot
## Mini-boss guard-bot: same guard + punch moveset as Robot (see Robot for
## that), plus laser eyes.
##
## LASER: while engaged and not already busy (punching or lasering), it
## periodically charges up — eye glows, a telegraph line shows exactly where
## the shot will go — then fires a Laser straight at wherever the player was
## standing when the charge started (so the beam itself is dodgeable: moving
## out of the telegraphed line during the charge is enough).
##
## REFLECT: slashing a Laser doesn't destroy it like a normal projectile —
## it reverses direction and switches to targeting enemies (see Laser). A
## reflected laser that reaches this robot deals damage straight through the
## guard (Laser calls hit_through_guard(), same path as a parried punch), so
## reflecting one is the "real" way to hurt the boss when it's turtling
## behind the guard between punches.
##
## Same tick-stamp / recall / time-stop discipline as Robot: everything is a
## stamp, shifted in on_time_stop_ended(), cleared in on_recall_finished().

const EYE_CHARGE_COLOR := Color(1, 0.15, 0.85, 1)

@export_group("Laser")
@export var laser_scene: PackedScene
## Eye glow + telegraph line before the shot; the beam itself is instant.
@export var laser_windup := 0.7
## Minimum time between laser shots, start to start.
@export var laser_cooldown := 2.4
@export var laser_speed := 155.6
@export var laser_damage := 1

var laser_start_tick := NEVER
var last_laser_tick := NEVER
## Player position captured when the charge starts; the beam is fired at
## this fixed point regardless of where the player moves to during the charge.
var _laser_aim := Vector2.ZERO

## Optional telegraph line from the eye to the aim point. Safe to omit from
## the scene (get_node_or_null), same pattern as DJ's deck_glow.
@onready var laser_telegraph: Line2D = get_node_or_null("LaserTelegraph")


## True while charging or the beam is out (the shot itself is instantaneous,
## so this really only covers the charge, but kept as its own predicate for
## clarity and future use).
func is_lasering() -> bool:
	return laser_start_tick != NEVER


func is_busy() -> bool:
	return super() or is_lasering()


func _can_start_punch() -> bool:
	return super() and not is_lasering()


func _update_attack(player: Player) -> void:
	if is_lasering():
		if GameManager.ticks_since(laser_start_tick) >= _ticks(laser_windup):
			_fire_laser()
			laser_start_tick = NEVER
			last_laser_tick = GameManager.timeline_tick
		return

	super(player)

	# Only start a charge once the punch logic above didn't just claim this
	# frame (is_busy() covers is_punching() too).
	if not is_busy() and GameManager.ticks_since(last_laser_tick) >= _ticks(laser_cooldown):
		laser_start_tick = GameManager.timeline_tick
		_laser_aim = player.global_position


func _cancel_attacks() -> void:
	super()
	laser_start_tick = NEVER


## Getting hit interrupts a charge too, same as it interrupts a punch.
func _on_damaged() -> void:
	super()
	laser_start_tick = NEVER


func on_time_stop_ended(frozen_ticks: int) -> void:
	super(frozen_ticks)
	laser_start_tick = _shift_stamp(laser_start_tick, frozen_ticks)
	last_laser_tick = _shift_stamp(last_laser_tick, frozen_ticks)


func on_recall_finished() -> void:
	super()
	laser_start_tick = _expire_future(laser_start_tick)
	last_laser_tick = _expire_future(last_laser_tick)


func _update_combat_visuals() -> void:
	super()
	var charging := is_lasering()
	if charging:
		eye.color = EYE_CHARGE_COLOR
	if laser_telegraph:
		laser_telegraph.visible = charging
		if charging:
			laser_telegraph.points = PackedVector2Array([Vector2.ZERO, to_local(_laser_aim)])


func _fire_laser() -> void:
	if laser_scene == null:
		return
	var laser := laser_scene.instantiate() as Laser
	if laser == null:
		return
	get_parent().add_child(laser)
	laser.speed = laser_speed
	laser.damage = laser_damage
	laser.launch(global_position, _laser_aim)
