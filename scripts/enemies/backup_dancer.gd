class_name BackupDancer
extends Walker
## Fodder enemy spawned by DJ.gd. Struts back and forth like a Walker, but
## every few seconds stops to bust a move: it holds still and puffs up a
## little (hitbox included) for the duration, then shrinks back down and
## keeps dancing.

const NEVER := GameManager.NEVER

@export_group("Bust a Move")
@export var move_interval := 4.0
@export var move_duration := 0.5
## Root scale while posing — keep this modest, it's a flourish, not a new
## enemy size.
@export var move_hitbox_scale := 1.15

var move_start_tick := NEVER
var _next_move_tick := NEVER


func _ready() -> void:
	super()
	_next_move_tick = GameManager.timeline_tick + _ticks(move_interval)


func _behave(delta: float) -> void:
	if is_busting_move():
		velocity.x = move_toward(velocity.x, 0.0, 416.7 * delta)
		if GameManager.ticks_since(move_start_tick) >= _ticks(move_duration):
			move_start_tick = NEVER
			_next_move_tick = GameManager.timeline_tick + _ticks(move_interval)
	else:
		super(delta)
		if GameManager.timeline_tick >= _next_move_tick:
			move_start_tick = GameManager.timeline_tick


func is_busting_move() -> bool:
	return move_start_tick != NEVER


func on_recall_finished() -> void:
	super()
	if move_start_tick > GameManager.timeline_tick:
		move_start_tick = NEVER


func _update_visuals() -> void:
	super()
	var s := move_hitbox_scale if is_busting_move() else 1.0
	scale = Vector2(s, s)


func _ticks(seconds: float) -> int:
	return GameManager.seconds_to_ticks(seconds)
