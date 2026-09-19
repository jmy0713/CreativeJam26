class_name Player
extends CharacterBody2D
## Platformer controller: run, jump (coyote time + jump buffer + variable height),
## double jump, horizontal dash, Hollow Knight-style directional slash with
## down-slash pogo, parry (deflects an enemy attack and stops time for every
## enemy), and HP with invincibility frames.
##
## All timers are tick stamps compared against GameManager.timeline_tick.
## For recall, position/facing are sampled by Recall and damage pushes an undo
## event; everything else is transient and reset in on_recall_finished().

signal health_changed(current: int, maximum: int)
signal died
## Emitted when the body starts sliding to the afterimage during a recall:
## the player "splits" from `from_position` towards `to_position`.
signal recall_split(from_position: Vector2, to_position: Vector2)

const NEVER := GameManager.NEVER

@export_group("Run")
@export var move_speed := 133.4
@export var ground_acceleration := 2000.0
@export var ground_friction := 2222.2
@export var air_acceleration := 1444.4
## Reversing direction snaps velocity to zero first instead of decelerating
## through it, so turning around is instant rather than a slide.
@export var snap_turn := true
## Used instead of the snap when `snap_turn` is off: reversals accelerate at
## this rate rather than the normal one.
@export var turn_acceleration := 3888.8

@export_group("Jump")
@export var gravity := 777.8
@export var fall_gravity_multiplier := 1.6
@export var max_fall_speed := 416.6
@export var jump_velocity := -288.8
@export var double_jump_velocity := -255.6
@export var max_air_jumps := 1
## Multiplier applied to upward velocity when jump is released early.
@export var jump_cut_multiplier := 0.45
@export var coyote_time := 0.1
@export var jump_buffer_time := 0.12

@export_group("Dash")
@export var dash_speed := 388.8
@export var dash_duration := 0.14
@export var dash_cooldown := 0.2
@export var max_air_dashes := 1

@export_group("Attack")
@export var attack_damage := 1
@export var attack_cooldown := 0.35
## How long the slash hitbox stays active.
@export var attack_active_time := 0.1
@export var pogo_velocity := -244.4

@export_group("Parry")
## How long after pressing parry an incoming attack gets deflected.
@export var parry_window := 0.2
## Minimum time between parry presses (from press to press).
@export var parry_cooldown := 0.5
## How long enemies stay frozen after a successful parry.
@export var parry_time_stop := 1.0

@export_group("Health")
@export var max_health := 5
@export var invincibility_time := 1.0
## Input is ignored for this long after being hit.
@export var hurt_stun_time := 0.15
@export var hurt_knockback := Vector2(144.4, -166.6)
## Turn snapping is suppressed for this long after a hit so steering back into
## the enemy doesn't cancel the knockback.
@export var hurt_momentum_time := 0.35
## Falling below this Y costs 1 HP and returns the player to the spawn point.
@export var kill_y := 444.4

const COLOR_NORMAL := Color(0.8, 0.8, 0.8)
const COLOR_DASHING := Color(1, 1, 1)
const COLOR_NO_DASH := Color(0.5, 0.5, 0.5)

# Side-slash sword angles (right-facing; mirrored by the Swing's scale.x):
# the blade sweeps from high in front down to low in front.
const SWING_FROM := deg_to_rad(-75.0)
const SWING_TO := deg_to_rad(80.0)
## The blade lingers at the end of the sweep for this long after the hitbox ends.
const SWING_FOLLOW_THROUGH := 0.06
const SWING_COLOR := Color(1, 1, 1, 0.95)
## Blade held up in front as a guard while the parry window is open.
const PARRY_ANGLE := deg_to_rad(-70.0)
const PARRY_COLOR := Color(0.5, 0.9, 1, 1)

var health := 0
var air_jumps_left := 0
var dashes_left := 0
var facing := 1.0
var dash_direction := Vector2.ZERO
var attack_direction := Vector2.RIGHT
var spawn_position := Vector2.ZERO

# Tick stamps (GameManager.timeline_tick) of when things last happened.
var last_floor_tick := NEVER
var jump_pressed_tick := NEVER
var dash_start_tick := NEVER
var attack_start_tick := NEVER
var parry_start_tick := NEVER
var hurt_tick := NEVER

## Enemies already hit by the current swing (one hit per swing).
var _swing_hits: Array[Enemy] = []

@onready var body: ColorRect = $Body
@onready var hurtbox: Area2D = $Hurtbox
@onready var slash_pivot: Node2D = $SlashPivot
@onready var slash_area: Area2D = $SlashPivot/SlashArea
@onready var swing: SwordSwing = $Swing
@onready var afterimage: Node2D = $Afterimage
@onready var afterimage_body: ColorRect = $Afterimage/Body

## Where the body waits while the afterimage rewinds.
var _recall_hold_position := Vector2.ZERO
var _recall_facing := 1.0


func _ready() -> void:
	add_to_group("player")
	add_to_group("recordable")
	spawn_position = global_position
	health = max_health
	air_jumps_left = max_air_jumps
	dashes_left = max_air_dashes


func _physics_process(delta: float) -> void:
	var input_x := Input.get_axis("move_left", "move_right")
	var stunned := _active(hurt_tick, hurt_stun_time)
	if stunned:
		input_x = 0.0
	elif input_x != 0.0:
		facing = signf(input_x)

	_refresh_on_floor()

	if not stunned:
		if Input.is_action_just_pressed("jump"):
			jump_pressed_tick = _now()
		if Input.is_action_just_pressed("dash") and _can_dash():
			_start_dash()
		if Input.is_action_just_pressed("attack") and _can_attack():
			_start_attack()
		if Input.is_action_just_pressed("parry") and _can_parry():
			parry_start_tick = _now()

	if is_dashing():
		velocity = dash_direction * dash_speed
	else:
		if GameManager.ticks_since(dash_start_tick) == _ticks(dash_duration):
			_end_dash()
		_apply_gravity(delta)
		_apply_horizontal(input_x, delta)
		_handle_jump()

	_process_attack()
	move_and_slide()
	_check_hurt()

	if global_position.y > kill_y:
		_hazard_respawn()

	_update_visuals()


# --- Public -----------------------------------------------------------------

func is_dashing() -> bool:
	return _active(dash_start_tick, dash_duration)


func is_invincible() -> bool:
	return _active(hurt_tick, invincibility_time)


func is_parrying() -> bool:
	return _active(parry_start_tick, parry_window)


## Called by an enemy attack that is about to hit the player. Returns true if
## the parry window is open: the attacker should cancel the attack instead of
## dealing damage, and time stops for every enemy.
func try_parry() -> bool:
	if health <= 0 or not is_parrying():
		return false
	TimeStop.start(parry_time_stop)
	return true


func take_damage(amount: int, from_position: Vector2, ignore_invincibility := false) -> void:
	if health <= 0 or (is_invincible() and not ignore_invincibility):
		return
	Recall.record(self, &"damaged", _restore_health.bind(health, hurt_tick))
	health -= amount
	hurt_tick = _now()
	dash_start_tick = NEVER
	var dir := signf(global_position.x - from_position.x)
	if dir == 0.0:
		dir = -facing
	velocity = Vector2(dir * hurt_knockback.x, hurt_knockback.y)
	health_changed.emit(health, max_health)
	if health <= 0:
		died.emit()


# --- Movement ---------------------------------------------------------------

func _refresh_on_floor() -> void:
	if is_on_floor():
		last_floor_tick = _now()
		air_jumps_left = max_air_jumps
		if not is_dashing():
			dashes_left = max_air_dashes


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var g := gravity
	if velocity.y > 0.0:
		g *= fall_gravity_multiplier
	velocity.y = minf(velocity.y + g * delta, max_fall_speed)


func _apply_horizontal(input_x: float, delta: float) -> void:
	var target := input_x * move_speed
	var turning := input_x != 0.0 and velocity.x != 0.0 and signf(input_x) != signf(velocity.x)
	# Knockback keeps its momentum; only player-driven turns snap.
	var can_snap := snap_turn and not _active(hurt_tick, hurt_momentum_time)
	if turning and can_snap:
		# Drop the old momentum so the next accel step starts from a standstill.
		velocity.x = 0.0
	var rate: float
	if turning and not snap_turn:
		rate = turn_acceleration
	elif is_on_floor():
		rate = ground_acceleration if input_x != 0.0 else ground_friction
	else:
		rate = air_acceleration
	velocity.x = move_toward(velocity.x, target, rate * delta)


func _handle_jump() -> void:
	if _active(jump_pressed_tick, jump_buffer_time):
		if _active(last_floor_tick, coyote_time):
			velocity.y = jump_velocity
			jump_pressed_tick = NEVER
			last_floor_tick = NEVER
		elif air_jumps_left > 0:
			velocity.y = double_jump_velocity
			air_jumps_left -= 1
			jump_pressed_tick = NEVER

	# Variable jump height: releasing jump early cuts the ascent.
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut_multiplier


func _can_dash() -> bool:
	return dashes_left > 0 and not is_dashing() \
		and GameManager.ticks_since(dash_start_tick) >= _ticks(dash_duration + dash_cooldown)


func _start_dash() -> void:
	var dir := signf(Input.get_axis("move_left", "move_right"))
	if dir == 0.0:
		dir = facing
	dash_direction = Vector2(dir, 0.0)
	dash_start_tick = _now()
	dashes_left -= 1
	last_floor_tick = NEVER


func _end_dash() -> void:
	# Keep some momentum so the dash doesn't stop dead.
	velocity = dash_direction * move_speed


# --- Combat -----------------------------------------------------------------

func _can_attack() -> bool:
	return GameManager.ticks_since(attack_start_tick) >= _ticks(attack_cooldown)


func _start_attack() -> void:
	attack_start_tick = _now()
	_swing_hits.clear()
	if Input.is_action_pressed("move_up"):
		attack_direction = Vector2.UP
	elif Input.is_action_pressed("move_down") and not is_on_floor():
		attack_direction = Vector2.DOWN
	else:
		attack_direction = Vector2(facing, 0.0)
	slash_pivot.rotation = attack_direction.angle()


func _can_parry() -> bool:
	return GameManager.ticks_since(parry_start_tick) >= _ticks(parry_cooldown)


func _process_attack() -> void:
	var active := _active(attack_start_tick, attack_active_time)
	# Side slashes are drawn by the Swing; up/down still use the flat slash.
	slash_pivot.visible = active and attack_direction.y != 0.0
	if not active:
		return
	for node in slash_area.get_overlapping_bodies():
		var enemy := node as Enemy
		if enemy == null or not enemy.alive or enemy in _swing_hits:
			continue
		_swing_hits.append(enemy)
		enemy.take_hit(attack_damage, global_position)
		if attack_direction == Vector2.DOWN:
			# Pogo off enemies like Hollow Knight; also refreshes air moves.
			velocity.y = pogo_velocity
			air_jumps_left = max_air_jumps
			dashes_left = max_air_dashes


func _check_hurt() -> void:
	# Enemies frozen by a parry can't hurt on contact.
	if is_invincible() or TimeStop.is_active():
		return
	for node in hurtbox.get_overlapping_bodies():
		var enemy := node as Enemy
		if enemy and enemy.alive:
			take_damage(enemy.contact_damage, enemy.global_position)
			return


func _hazard_respawn() -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	dash_start_tick = NEVER
	take_damage(1, global_position, true)
	velocity = Vector2.ZERO


# --- Visuals ----------------------------------------------------------------

func _update_visuals() -> void:
	if is_dashing():
		body.color = COLOR_DASHING
	elif dashes_left <= 0:
		body.color = COLOR_NO_DASH
	else:
		body.color = COLOR_NORMAL
	# Blink while invincible.
	body.visible = not is_invincible() or (GameManager.ticks_since(hurt_tick) / 4) % 2 == 0
	_update_swing()


## Poses the sword from the attack/parry stamps: a side slash sweeps the blade
## over the hitbox's active window, a parry holds it up as a guard.
func _update_swing() -> void:
	var since_attack := GameManager.ticks_since(attack_start_tick)
	var swing_ticks := maxi(_ticks(attack_active_time), 1)
	if attack_direction.y == 0.0 and since_attack < swing_ticks + _ticks(SWING_FOLLOW_THROUGH):
		var t := clampf(float(since_attack) / swing_ticks, 0.0, 1.0)
		swing.visible = true
		swing.scale.x = attack_direction.x
		swing.color = SWING_COLOR
		swing.set_pose(lerpf(SWING_FROM, SWING_TO, t * (2.0 - t)), SWING_FROM)
	elif is_parrying():
		swing.visible = true
		swing.scale.x = facing
		swing.color = PARRY_COLOR
		swing.set_pose(PARRY_ANGLE)
	else:
		swing.visible = false


# --- Tick helpers -----------------------------------------------------------

func _now() -> int:
	return GameManager.timeline_tick


func _ticks(seconds: float) -> int:
	return GameManager.seconds_to_ticks(seconds)


## True while fewer than `duration` seconds have passed since `tick`.
func _active(tick: int, duration: float) -> bool:
	return GameManager.ticks_since(tick) < _ticks(duration)


# --- Recall -----------------------------------------------------------------

func recall_sample() -> Dictionary:
	return {"position": global_position, "facing": facing}


func apply_recall_sample(sample: Dictionary) -> void:
	if Recall.is_recalling:
		# The afterimage travels the rewind path; the body catches up later.
		afterimage.global_position = sample.position
		_recall_facing = sample.facing
		return
	global_position = sample.position
	facing = sample.facing


func begin_recall_visual() -> void:
	_recall_hold_position = global_position
	_recall_facing = facing
	afterimage.global_position = global_position
	afterimage_body.color = Color(body.color, 0.4)
	afterimage.visible = true


func begin_recall_catchup() -> void:
	recall_split.emit(_recall_hold_position, afterimage.global_position)


func set_recall_catchup(t: float) -> void:
	global_position = _recall_hold_position.lerp(afterimage.global_position, _catchup_curve(t))


## Quick acceleration over the first ~20%, then a long brake that reaches zero
## speed exactly at the afterimage (quartic ease-out, faded in by a smoothstep).
func _catchup_curve(t: float) -> float:
	return (1.0 - pow(1.0 - t, 7.0)) * smoothstep(0.0, 0.2, t)


func on_recall_finished() -> void:
	global_position = afterimage.global_position
	facing = _recall_facing
	afterimage.visible = false
	velocity = Vector2.ZERO
	_swing_hits.clear()
	# Stamps newer than the rewound clock happened in the undone future.
	var now := _now()
	if last_floor_tick > now: last_floor_tick = NEVER
	if jump_pressed_tick > now: jump_pressed_tick = NEVER
	if dash_start_tick > now: dash_start_tick = NEVER
	if attack_start_tick > now: attack_start_tick = NEVER
	if parry_start_tick > now: parry_start_tick = NEVER
	if hurt_tick > now: hurt_tick = NEVER
	_update_visuals()


func _restore_health(previous_health: int, previous_hurt_tick: int) -> void:
	health = previous_health
	hurt_tick = previous_hurt_tick
	health_changed.emit(health, max_health)
