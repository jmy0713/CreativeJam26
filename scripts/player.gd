class_name Player
extends CharacterBody2D
## Platformer controller: run, jump (coyote time + jump buffer + variable height),
## double jump, horizontal dash, drop through a jump-through platform, Hollow
## Knight-style directional slash with down-slash pogo, parry (deflects an
## enemy attack and stops time for every enemy), and HP with invincibility
## frames.
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
## How long the cloud kicked out by an air jump lasts.
@export var air_jump_puff_time := 0.26
## Multiplier applied to upward velocity when jump is released early.
@export var jump_cut_multiplier := 0.45
## Holding jump past a tap turns it into a high jump: for up to this long
## after takeoff, gravity is scaled by jump_hold_gravity_multiplier while the
## button stays down and the player is still rising.
@export var jump_hold_time := 0.12
@export var jump_hold_gravity_multiplier := 0.5
@export var coyote_time := 0.1
@export var jump_buffer_time := 0.12

@export_group("Drop through")
## Pressing down on a jump-through platform (Platform.one_way) falls off it.
## The platform is collision-excepted for this long, which has to outlast the
## drop clearing its underside — well over the ~0.1 s the fall below takes,
## and short enough that you can't ride the exception back up through the
## next platform you jump at.
@export var drop_through_time := 0.35
## Downward speed the drop starts with, so it reads as stepping off rather
## than waiting a frame for gravity to pick up.
@export var drop_through_speed := 55.6

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
## The down slash freezes on this frame — the blade straight down, body
## pitched forward — for down_slash_hold_time, so the plunge stays on screen
## as long as the pogo reads for. The rest of the clip plays out after it.
@export var down_slash_hold_frame := 2
@export var down_slash_hold_time := 0.15
## How long the SlashArc "slice of air" stays on screen after a swing starts.
## SlashArc cuts this into its own frames, so this is the whole strike plus
## aftermath: a touch longer than attack_active_time, not long enough for the
## slice to outstay the window it advertises.
@export var slash_fx_time := 0.16

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

## Sprite tints. The sprite carries its own colours, so "normal" adds nothing;
## the dash flashes overbright and a spent dash dims the player slightly.
const TINT_NORMAL := Color.WHITE
const TINT_DASHING := Color(1.5, 1.5, 1.8)
const TINT_NO_DASH := Color(0.7, 0.7, 0.8)

## Ground speed above which the run animation plays instead of idle.
const RUN_ANIM_SPEED := 8.0

## How far the drop-through probe pushes the body into the floor to find what
## it is standing on. Enough to overlap a platform the feet are resting on,
## far less than the thinnest one (~9 px) so it can't reach past it.
const DROP_PROBE_DEPTH := 3.0

var health := 0
var air_jumps_left := 0
var dashes_left := 0
var facing := 1.0
var dash_direction := Vector2.ZERO
var attack_direction := Vector2.RIGHT
## Animation picked when the current swing started (see _attack_animation).
var attack_anim := &"slash"
var spawn_position := Vector2.ZERO

# Tick stamps (GameManager.timeline_tick) of when things last happened.
var last_floor_tick := NEVER
var jump_pressed_tick := NEVER
var jump_start_tick := NEVER
var dash_start_tick := NEVER
var attack_start_tick := NEVER
var parry_start_tick := NEVER
var hurt_tick := NEVER
## When the current airborne phase began — leaving the floor, or the last air
## jump. NEVER while grounded. Only the jump/fall animations read it.
var air_tick := NEVER
## When the current descent began. Kept apart from air_tick so the fall
## animation starts at the apex rather than being over before the drop.
var fall_tick := NEVER
## When the last air jump went off. The cloud it kicks out is posed from this
## like every other visual here, so it rewinds and freezes with the clock.
var air_jump_tick := NEVER
## When the current drop through a jump-through platform started.
var drop_through_tick := NEVER

## Enemies already hit by the current swing (one hit per swing).
var _swing_hits: Array[Enemy] = []
## Flips every side slash so repeated attacks alternate two animations.
var _swing_variant := 0
## Where the dash started and which way the player faced then. The trail of
## silhouettes is worked out from these rather than from a history buffer.
var _dash_start_position := Vector2.ZERO
var _dash_facing := 1.0
## Where the last air jump's cloud was left. The player rises away from it,
## so the cloud stays put in the world rather than following the feet.
var _puff_position := Vector2.ZERO
## Facing at the moment the current swing started. The pivot's rotation is
## frozen then too, so the slice must not re-mirror if the player turns
## mid-swing.
var _swing_facing := 1.0
## Whether the dash was still running last frame, so its exit momentum is
## applied on the frame it ends however far the clock jumped.
var _was_dashing := false
## Platforms the current drop is falling through, collision-excepted until
## drop_through_time runs out. Empty whenever drop_through_tick is NEVER.
var _dropped_platforms: Array[Platform] = []

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var shadow: BlobShadow = $Shadow
@onready var hurtbox: Area2D = $Hurtbox
@onready var slash_pivot: Node2D = $SlashPivot
@onready var slash_area: Area2D = $SlashPivot/SlashArea
@onready var slash_fx: SlashArc = $SlashFx
@onready var puff: PuffCloud = $Puff
@onready var dash_ghosts: DashGhosts = $DashGhosts
@onready var afterimage: Node2D = $Afterimage
@onready var afterimage_sprite: AnimatedSprite2D = $Afterimage/Sprite

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
	dash_ghosts.bind(sprite)


func _physics_process(delta: float) -> void:
	var input_x := Input.get_axis("move_left", "move_right")
	var stunned := _active(hurt_tick, hurt_stun_time)
	if stunned:
		input_x = 0.0
	elif input_x != 0.0:
		facing = signf(input_x)

	_refresh_on_floor()
	_expire_drop_through()

	if not stunned:
		if Input.is_action_just_pressed("jump"):
			jump_pressed_tick = _now()
		if Input.is_action_just_pressed("move_down"):
			_try_drop_through()
		if Input.is_action_just_pressed("dash") and _can_dash():
			_start_dash()
		if Input.is_action_just_pressed("attack") and _can_attack():
			_start_attack()
		if Input.is_action_just_pressed("parry") and _can_parry():
			parry_start_tick = _now()

	var dashing := is_dashing()
	if dashing:
		velocity = dash_direction * dash_speed
	else:
		# The dash ran its course. A dash *cancelled* by a hit clears its stamp
		# instead, and keeps whatever velocity cancelled it.
		if _was_dashing and dash_start_tick != NEVER:
			_end_dash()
		_apply_gravity(delta)
		_apply_horizontal(input_x, delta)
		_handle_jump()
	_was_dashing = dashing

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
## dealing damage, and time stops for every enemy. A parry pressed before
## `pressed_since` (e.g. during an attack's windup) doesn't count.
func try_parry(pressed_since := NEVER) -> bool:
	if health <= 0 or not is_parrying() or parry_start_tick < pressed_since:
		return false
	TimeStop.start(parry_time_stop)
	return true


func take_damage(amount: int, from_position: Vector2, ignore_invincibility := false) -> void:
	if health <= 0 or GameManager.cheat_invincible:
		return
	if is_invincible() and not ignore_invincibility:
		return
	Recall.record(self, &"damaged", _restore_health.bind(health, hurt_tick))
	health = maxi(health - amount, 0)
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
		air_tick = NEVER
		fall_tick = NEVER
		air_jumps_left = max_air_jumps
		if not is_dashing():
			dashes_left = max_air_dashes
	else:
		if air_tick == NEVER:
			air_tick = _now()
		if velocity.y < 0.0:
			fall_tick = NEVER
		elif fall_tick == NEVER:
			fall_tick = _now()


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var g := gravity
	if velocity.y > 0.0:
		g *= fall_gravity_multiplier
	elif _is_holding_jump():
		g *= jump_hold_gravity_multiplier
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
			jump_start_tick = _now()
			air_tick = _now()
			last_floor_tick = NEVER
		elif air_jumps_left > 0:
			velocity.y = double_jump_velocity
			air_jumps_left -= 1
			jump_pressed_tick = NEVER
			jump_start_tick = _now()
			air_jump_tick = _now()
			# Kicked off the boots, which is where the sprite's feet are.
			_puff_position = global_position + Vector2(0.0, sprite.position.y)
			# Restart the jump animation so a double jump reads as its own hop.
			air_tick = _now()

	# Variable jump height: releasing jump early cuts the ascent, and ends
	# the high-jump hold window.
	if Input.is_action_just_released("jump"):
		jump_start_tick = NEVER
		if velocity.y < 0.0:
			velocity.y *= jump_cut_multiplier


## True during the high-jump window: jump still held shortly after takeoff.
func _is_holding_jump() -> bool:
	return _active(jump_start_tick, jump_hold_time) and Input.is_action_pressed("jump")


func _can_dash() -> bool:
	return dashes_left > 0 and not is_dashing() \
		and GameManager.ticks_since(dash_start_tick) >= _ticks(dash_duration + dash_cooldown)


func _start_dash() -> void:
	var dir := signf(Input.get_axis("move_left", "move_right"))
	if dir == 0.0:
		dir = facing
	dash_direction = Vector2(dir, 0.0)
	dash_start_tick = _now()
	_dash_start_position = global_position
	_dash_facing = facing
	dashes_left -= 1
	last_floor_tick = NEVER


func _end_dash() -> void:
	# Keep some momentum so the dash doesn't stop dead.
	velocity = dash_direction * move_speed


## Down on a jump-through platform steps off it. The platform can't just be
## ignored for a frame — Godot's one-way surface would catch the player again
## on the way down — so it is collision-excepted outright for
## drop_through_time, by which point the fall has cleared its underside and
## the one-way rule takes over again on its own.
##
## Only the platforms actually being stood on are excepted, so the drop stops
## at whatever is under them, and a dash isn't interrupted mid-flight.
func _try_drop_through() -> void:
	if not is_on_floor() or is_dashing():
		return
	var dropped := false
	for platform in _platforms_underfoot():
		if platform in _dropped_platforms:
			continue
		add_collision_exception_with(platform)
		_dropped_platforms.append(platform)
		dropped = true
	if not dropped:
		return
	drop_through_tick = _now()
	velocity.y = maxf(velocity.y, drop_through_speed)
	# The platform underfoot is gone, so the coyote window and any buffered
	# jump go with it — otherwise down-then-jump hops straight back onto it.
	last_floor_tick = NEVER
	jump_pressed_tick = NEVER


## Every jump-through platform the feet are resting on, found by pushing the
## body's own shape DROP_PROBE_DEPTH into the floor and asking the space what
## that overlaps. The last move's slide collisions would usually answer this
## and cost nothing, but a body standing perfectly still doesn't reliably
## produce one — and "down did nothing that time" is worse than a query that
## only runs on the press. The overlap test ignores the one-way rule, which
## is the point: the platform has to be found from above.
func _platforms_underfoot() -> Array[Platform]:
	var found: Array[Platform] = []
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape.shape
	query.transform = collision_shape.global_transform.translated(
		Vector2(0.0, DROP_PROBE_DEPTH))
	query.collision_mask = collision_mask
	var exclude: Array[RID] = [get_rid()]
	query.exclude = exclude
	for hit in get_world_2d().direct_space_state.intersect_shape(query):
		var platform := hit.collider as Platform
		if platform != null and platform.is_one_way_active() and platform not in found:
			found.append(platform)
	return found


## Hands the dropped platforms back once the window has run out. Times off the
## timeline like everything else here, so a recall or a time stop holds the
## drop open rather than closing it under the player.
func _expire_drop_through() -> void:
	if drop_through_tick == NEVER or _active(drop_through_tick, drop_through_time):
		return
	_clear_drop_through()


func _clear_drop_through() -> void:
	for platform in _dropped_platforms:
		if is_instance_valid(platform):
			remove_collision_exception_with(platform)
	_dropped_platforms.clear()
	drop_through_tick = NEVER


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
	_swing_facing = facing
	attack_anim = _attack_animation()


## Which animation this swing plays. Up slashes have a ground and an air
## variant, down slashes are air-only, and side slashes alternate two swings so
## repeated attacks never replay the same clip — with a separate pair for
## slashing out of a dash.
func _attack_animation() -> StringName:
	if attack_direction == Vector2.UP:
		return &"up_slash" if is_on_floor() else &"air_up_slash"
	if attack_direction == Vector2.DOWN:
		return &"down_slash"
	_swing_variant = 1 - _swing_variant
	if is_dashing():
		return &"dash_slash" if _swing_variant == 0 else &"dash_thrust"
	if not is_on_floor():
		return &"air_slash"
	return &"slash" if _swing_variant == 0 else &"thrust"


func _can_parry() -> bool:
	return GameManager.ticks_since(parry_start_tick) >= _ticks(parry_cooldown)


func _process_attack() -> void:
	if not _active(attack_start_tick, attack_active_time):
		return
	for area in slash_area.get_overlapping_areas():
		var projectile := area as Projectile
		if projectile == null or not projectile.alive:
			continue
		projectile.destroy()
		_pogo()
	for node in slash_area.get_overlapping_bodies():
		var enemy := node as Enemy
		if enemy == null or not enemy.alive or enemy in _swing_hits:
			continue
		_swing_hits.append(enemy)
		enemy.take_hit(attack_damage, global_position)
		_pogo()


## A down-slash that connects bounces off it like Hollow Knight (enemies and
## projectiles alike); also refreshes air moves.
func _pogo() -> void:
	if attack_direction != Vector2.DOWN:
		return
	velocity.y = pogo_velocity
	jump_start_tick = NEVER
	# The bounce is a fresh hop: replay the jump arc rather than holding the
	# last frame of the one before it.
	air_tick = _now()
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
	_clear_drop_through()
	take_damage(1, global_position, true)
	velocity = Vector2.ZERO


# --- Visuals ----------------------------------------------------------------

func _update_visuals() -> void:
	if is_dashing():
		sprite.modulate = TINT_DASHING
	elif dashes_left <= 0:
		sprite.modulate = TINT_NO_DASH
	else:
		sprite.modulate = TINT_NORMAL
	# Blink while invincible.
	sprite.visible = not is_invincible() or (GameManager.ticks_since(hurt_tick) / 4) % 2 == 0
	# Nothing to fall on in the air, and the blink takes the shadow with it so
	# an invincible player doesn't leave a shadow standing on its own.
	shadow.visible = is_on_floor() and sprite.visible
	_pose_slash_fx()
	_pose_puff()
	_pose_dash_ghosts()
	_pose_sprite()
	if afterimage.visible:
		_copy_pose_to_afterimage()


## Sweeps the slice of air across the swing, on the same tick stamp as the
## hitbox and the sprite, then hides it once it has faded.
func _pose_slash_fx() -> void:
	# A negative elapsed is a swing in the undone future, part-way through a
	# recall; NEVER puts it far enough in the past to fall out on its own.
	var elapsed := GameManager.seconds_since(attack_start_tick)
	slash_fx.visible = elapsed >= 0.0 and elapsed < slash_fx_time
	if slash_fx.visible:
		# The slice draws unrotated so its pixels stay on the grid, so the
		# swing's angle goes in as data rather than as the node's transform.
		slash_fx.set_pose(elapsed / slash_fx_time, _swing_facing, slash_pivot.rotation)


## Trails the dash's silhouettes behind the player, from the dash's stamp. A
## dash cancelled by a hit clears the stamp, which drops the trail with it.
func _pose_dash_ghosts() -> void:
	var elapsed := GameManager.seconds_since(dash_start_tick)
	if elapsed < 0.0 or elapsed >= dash_ghosts.trail_seconds():
		dash_ghosts.clear()
		return
	dash_ghosts.set_trail(elapsed, _dash_start_position, global_position,
		dash_direction * dash_speed, dash_duration, _dash_facing)


## Runs out the cloud an air jump kicked out, from the stamp of that jump.
func _pose_puff() -> void:
	var elapsed := GameManager.seconds_since(air_jump_tick)
	puff.visible = elapsed >= 0.0 and elapsed < air_jump_puff_time
	if puff.visible:
		# Pinned in the world, so it stays put while the player climbs away.
		puff.global_position = _puff_position
		puff.set_pose(elapsed / air_jump_puff_time)


## Picks the animation for the current state and hands it to SpriteClock,
## which turns a tick stamp into a frame index (see sprite_clock.gd for why
## nothing here ever calls play()).
func _pose_sprite() -> void:
	# Actions run longer than their animations: an attack holds its last frame
	# through the rest of the cooldown, a parry through the recovery after the
	# window has shut. Whichever action started most recently wins, so dashing
	# out of an attack's recovery reads as a dash and not a stuck swing.
	var anim := &""
	var stamp := NEVER
	if _active(attack_start_tick, _attack_pose_seconds()) and attack_start_tick >= stamp:
		anim = attack_anim
		stamp = attack_start_tick
	if _active(parry_start_tick, SpriteClock.seconds(sprite.sprite_frames, &"parry")) and parry_start_tick >= stamp:
		anim = &"parry"
		stamp = parry_start_tick
	if is_dashing() and dash_start_tick >= stamp:
		anim = &"dash"
		stamp = dash_start_tick
	if anim == &"":
		if not is_on_floor():
			var rising := velocity.y < 0.0
			anim = &"jump" if rising else &"fall"
			stamp = air_tick if rising else fall_tick
		elif absf(velocity.x) > RUN_ANIM_SPEED:
			anim = &"run"
		else:
			anim = &"idle"
	sprite.animation = anim
	if anim == &"down_slash":
		sprite.frame = SpriteClock.frame_for_held(sprite.sprite_frames, anim, stamp,
			down_slash_hold_frame, down_slash_hold_time)
	else:
		sprite.frame = SpriteClock.frame_for(sprite.sprite_frames, anim, stamp)
	sprite.scale.x = facing


## How long the swing keeps the sprite. Normally the cooldown, but the down
## slash's held frame makes its clip longer than that, and cutting to `fall`
## mid-plunge is exactly what this change is meant to stop.
func _attack_pose_seconds() -> float:
	var clip := SpriteClock.seconds(sprite.sprite_frames, attack_anim)
	if attack_anim == &"down_slash":
		clip += down_slash_hold_time
	return maxf(attack_cooldown, clip)


func _copy_pose_to_afterimage() -> void:
	afterimage_sprite.animation = sprite.animation
	afterimage_sprite.frame = sprite.frame
	afterimage_sprite.scale.x = sprite.scale.x


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
	_copy_pose_to_afterimage()
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
	_was_dashing = false
	_swing_hits.clear()
	# The rewind puts the body back on solid ground; a drop that was in the
	# air at the time is not something to land in the middle of.
	_clear_drop_through()
	# Stamps newer than the rewound clock happened in the undone future.
	var now := _now()
	if last_floor_tick > now: last_floor_tick = NEVER
	if jump_pressed_tick > now: jump_pressed_tick = NEVER
	if jump_start_tick > now: jump_start_tick = NEVER
	if dash_start_tick > now: dash_start_tick = NEVER
	if attack_start_tick > now: attack_start_tick = NEVER
	if parry_start_tick > now: parry_start_tick = NEVER
	if hurt_tick > now: hurt_tick = NEVER
	if air_tick > now: air_tick = NEVER
	if fall_tick > now: fall_tick = NEVER
	if air_jump_tick > now: air_jump_tick = NEVER
	_update_visuals()


func _restore_health(previous_health: int, previous_hurt_tick: int) -> void:
	health = previous_health
	hurt_tick = previous_hurt_tick
	health_changed.emit(health, max_health)
