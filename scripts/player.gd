extends CharacterBody2D
## Platformer controller: run, jump (coyote time + jump buffer + variable height),
## double jump, and an 8-directional dash that refills on landing.

@export_group("Run")
@export var move_speed := 240.0
@export var ground_acceleration := 2200.0
@export var ground_friction := 2600.0
@export var air_acceleration := 1600.0

@export_group("Jump")
@export var gravity := 1400.0
@export var fall_gravity_multiplier := 1.6
@export var max_fall_speed := 750.0
@export var jump_velocity := -520.0
@export var double_jump_velocity := -460.0
@export var max_air_jumps := 1
## Multiplier applied to upward velocity when jump is released early.
@export var jump_cut_multiplier := 0.45
@export var coyote_time := 0.1
@export var jump_buffer_time := 0.12

@export_group("Dash")
@export var dash_speed := 700.0
@export var dash_duration := 0.14
@export var dash_cooldown := 0.2
@export var max_air_dashes := 1

@export_group("Misc")
## Falling below this Y respawns the player at their start position.
@export var kill_y := 1200.0

const COLOR_NORMAL := Color(0.8, 0.8, 0.8)
const COLOR_DASHING := Color(1, 1, 1)
const COLOR_NO_DASH := Color(0.5, 0.5, 0.5)

var air_jumps_left := 0
var dashes_left := 0
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var dash_timer := 0.0
var dash_cooldown_timer := 0.0
var dash_direction := Vector2.ZERO
var facing := 1.0
var spawn_position := Vector2.ZERO

@onready var body: ColorRect = $Body


func _ready() -> void:
	spawn_position = global_position
	air_jumps_left = max_air_jumps
	dashes_left = max_air_dashes


func _physics_process(delta: float) -> void:
	var input_x := Input.get_axis("move_left", "move_right")
	if input_x != 0.0:
		facing = signf(input_x)

	_update_timers(delta)

	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time

	if Input.is_action_just_pressed("dash") and _can_dash():
		_start_dash()

	if is_dashing():
		dash_timer -= delta
		velocity = dash_direction * dash_speed
		if dash_timer <= 0.0:
			_end_dash()
	else:
		_apply_gravity(delta)
		_apply_horizontal(input_x, delta)
		_handle_jump()

	move_and_slide()

	if global_position.y > kill_y:
		respawn()

	_update_visuals()


func is_dashing() -> bool:
	return dash_timer > 0.0


func respawn() -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	dash_timer = 0.0
	air_jumps_left = max_air_jumps
	dashes_left = max_air_dashes


func _update_timers(delta: float) -> void:
	if is_on_floor():
		coyote_timer = coyote_time
		air_jumps_left = max_air_jumps
		if not is_dashing():
			dashes_left = max_air_dashes
	else:
		coyote_timer -= delta
	jump_buffer_timer -= delta
	dash_cooldown_timer -= delta


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var g := gravity
	if velocity.y > 0.0:
		g *= fall_gravity_multiplier
	velocity.y = minf(velocity.y + g * delta, max_fall_speed)


func _apply_horizontal(input_x: float, delta: float) -> void:
	var target := input_x * move_speed
	var rate: float
	if is_on_floor():
		rate = ground_acceleration if input_x != 0.0 else ground_friction
	else:
		rate = air_acceleration
	velocity.x = move_toward(velocity.x, target, rate * delta)


func _handle_jump() -> void:
	if jump_buffer_timer > 0.0:
		if coyote_timer > 0.0:
			velocity.y = jump_velocity
			jump_buffer_timer = 0.0
			coyote_timer = 0.0
		elif air_jumps_left > 0:
			velocity.y = double_jump_velocity
			air_jumps_left -= 1
			jump_buffer_timer = 0.0

	# Variable jump height: releasing jump early cuts the ascent.
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut_multiplier


func _can_dash() -> bool:
	return dashes_left > 0 and dash_cooldown_timer <= 0.0 and not is_dashing()


func _start_dash() -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir == Vector2.ZERO:
		dir = Vector2(facing, 0.0)
	dash_direction = dir.normalized()
	dash_timer = dash_duration
	dash_cooldown_timer = dash_duration + dash_cooldown
	dashes_left -= 1
	coyote_timer = 0.0


func _end_dash() -> void:
	# Keep some momentum so the dash doesn't stop dead.
	velocity = dash_direction * move_speed


func _update_visuals() -> void:
	if is_dashing():
		body.color = COLOR_DASHING
	elif dashes_left <= 0:
		body.color = COLOR_NO_DASH
	else:
		body.color = COLOR_NORMAL
