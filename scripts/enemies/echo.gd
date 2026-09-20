class_name Echo
extends Walker
## The echo/clone spawned when the player recalls. Buffed version of Walker
## with double jump, increased speed, and chases the player.
##
## It wears the player's own frames as a photographic negative
## (`echo_frames.tres` over `echo_sheet.png`, both baked by
## tools/make_player_sprites.py alongside the player's) and picks its animation
## from its own state, the same way Player does.
##
## It fights with the player's own moveset: once you are in reach it plants and
## swings, alternating `slash` and `thrust` (`air_slash` off the ground). The
## swing telegraphs through `attack_windup` and only connects when the sweep
## finishes, and it is parryable for the whole sweep — same contract as the
## Knight (see Player.try_parry), so the parry you learned on them works here.
## It also still hurts on contact, like any other enemy.

## Ground speed above which the run animation plays instead of idle.
const RUN_ANIM_SPEED := 8.0

@export var jump_velocity := -244.4
@export var double_jump_velocity := -200.0
@export var chase_range := 300.0  # How far away the echo will chase from

@export_group("Attack")
## How close the player has to be, horizontally and vertically, to be swung at.
## Measured at scale 1.0: the echo's own scale (copied from the player) grows
## or shrinks them, the same way it does the sword.
@export var attack_range := 26.0
@export var attack_height := 26.0
## The telegraph: blade goes up, nothing lands yet. Long enough to react to.
@export var attack_windup := 0.30
## The sweep. Parryable throughout; the damage lands as it ends.
@export var attack_active := 0.22
## Measured from the end of one swing to the earliest start of the next.
@export var attack_cooldown := 0.85
@export var sword_damage := 1

var air_jumps_left := 0
var max_air_jumps := 1
var last_floor_tick := NEVER

## When this airborne phase began (leaving the floor, or the last jump) and
## when the descent began. Only the jump/fall animations read them.
var air_tick := NEVER
var fall_tick := NEVER

var attack_start_tick := NEVER
var last_swing_end_tick := NEVER
## Animation picked when the current swing started.
var attack_anim := &"slash"
## Flips every ground swing so repeated attacks alternate two animations.
var _swing_variant := 0

@onready var sprite: AnimatedSprite2D = $Body
@onready var sword_area: Area2D = $SwordArea


func _ready() -> void:
	super()
	air_jumps_left = max_air_jumps
	# Increase speed from default 38.8 to ~77.6 (double)
	speed = 38.8
	# An echo spawns on top of where you just were: make it wait out one
	# cooldown before its first swing rather than opening with one.
	last_swing_end_tick = GameManager.timeline_tick


## Makes the echo a copy of the player as they are right now: same size (so
## collider, sprite and sword reach scale with the level, like the player's do),
## same movement stats and same durability. Call it right after the echo has
## been added to the tree -- _ready() sets this echo's own defaults, and this
## overwrites them.
func copy_player_stats(player: Player) -> void:
	if player == null:
		return
	# Size. Player.scale already carries LEVEL_SCALE for the current level.
	scale = player.scale
	# Movement, including the level-scaled jump heights.
	jump_velocity = player.jump_velocity
	double_jump_velocity = player.double_jump_velocity
	max_air_jumps = player.max_air_jumps
	air_jumps_left = max_air_jumps
	# Combat and durability.
	sword_damage = player.attack_damage
	max_health = player.max_health
	health = max_health


## Gravity is already applied by Enemy._physics_process before this runs, so
## nothing here touches velocity.y except the jumps.
func _behave(delta: float) -> void:
	var player := GameManager.player

	if is_swinging():
		# Planted for the swing: no chasing, no jumping, no patrol turn. The
		# facing is locked in at _start_swing, so it can't spin mid-sweep.
		velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
		_update_swing(player)
		_position_sword()
		return

	if is_on_floor():
		last_floor_tick = GameManager.timeline_tick
		air_jumps_left = max_air_jumps

	_chase_player(player)
	_handle_jump()
	# Patrol turn, ledge probe and walk speed, straight from Walker.
	super(delta)

	if _can_swing(player):
		_start_swing(player)
	_position_sword()


## Steers toward the player while they're within chase_range, and hops when
## they're overhead. Only sets `direction`; Walker's patrol step turns that
## into movement.
func _chase_player(player: Player) -> void:
	if player == null or global_position.distance_to(player.global_position) > chase_range:
		return

	var dx := player.global_position.x - global_position.x
	if dx != 0.0:
		direction = 1 if dx > 0.0 else -1

	var player_above := player.global_position.y < global_position.y - 30.0 * scale.y
	if player_above and is_on_floor():
		_jump(jump_velocity)


## Random hops on top of the chase, to make the echo harder to read.
func _handle_jump() -> void:
	if randf() >= 0.01:  # 1% chance per frame to attempt a jump
		return
	if is_on_floor():
		_jump(jump_velocity)
	elif air_jumps_left > 0:
		air_jumps_left -= 1
		_jump(double_jump_velocity)


func _jump(speed_y: float) -> void:
	velocity.y = speed_y
	last_floor_tick = NEVER
	# Restart the arc so each hop reads as its own jump.
	air_tick = GameManager.timeline_tick


# --- Attack -----------------------------------------------------------------

func is_swinging() -> bool:
	return attack_start_tick != NEVER


## True during the sweep: the blade is moving and a parry would catch it.
func _is_sweeping() -> bool:
	if not is_swinging():
		return false
	var t := GameManager.ticks_since(attack_start_tick)
	return t >= _ticks(attack_windup) and t < _ticks(attack_windup + attack_active)


func _can_swing(player: Player) -> bool:
	if player == null or player.health <= 0 or is_swinging():
		return false
	if GameManager.ticks_since(last_swing_end_tick) < _ticks(attack_cooldown):
		return false
	var offset := player.global_position - global_position
	return absf(offset.x) <= attack_range and absf(offset.y) <= attack_height
	return absf(offset.x) <= attack_range * scale.x and absf(offset.y) <= attack_height * scale.y


func _start_swing(player: Player) -> void:
	direction = 1 if player.global_position.x >= global_position.x else -1
	attack_start_tick = GameManager.timeline_tick
	attack_anim = _attack_animation()


## The player's own swings, alternated so repeated attacks never replay one
## clip. Off the ground there is only the one air swing to use.
func _attack_animation() -> StringName:
	if not is_on_floor():
		return &"air_slash"
	_swing_variant = 1 - _swing_variant
	return &"slash" if _swing_variant == 0 else &"thrust"


## Runs the swing to its end. Parryable for the whole sweep; the blade only
## connects as the sweep finishes, so there is a full windup to react to.
func _update_swing(player: Player) -> void:
	var swing_over := GameManager.ticks_since(attack_start_tick) >= _ticks(attack_windup + attack_active)
	if player != null and (_is_sweeping() or swing_over) and _sword_reaches(player):
		var sweep_start := attack_start_tick + _ticks(attack_windup)
		if player.try_parry(sweep_start):
			_on_parried()
			return
		if swing_over:
			player.take_damage(sword_damage, global_position)
	if swing_over:
		_end_swing()


func _sword_reaches(player: Player) -> bool:
	return sword_area.get_overlapping_bodies().has(player)


## Deflected: the swing ends now, the cooldown restarts and the echo staggers
## with a hit flash. It has no shield to break, so the opening is simply that
## the time stop leaves it standing there.
func _on_parried() -> void:
	_end_swing()
	last_hit_tick = GameManager.timeline_tick


func _end_swing() -> void:
	attack_start_tick = NEVER
	last_swing_end_tick = GameManager.timeline_tick


func _position_sword() -> void:
	sword_area.position.x = absf(sword_area.position.x) * direction


# --- Visuals ----------------------------------------------------------------

## Overridden rather than done in _behave(), which Enemy skips while this echo
## is hit-stunned -- a stunned echo still falls, and should still be animated.
func _update_visuals() -> void:
	super()
	_update_air_stamps()
	_pose_sprite()


func _update_air_stamps() -> void:
	if is_on_floor():
		air_tick = NEVER
		fall_tick = NEVER
		return
	if air_tick == NEVER:
		air_tick = GameManager.timeline_tick
	if velocity.y < 0.0:
		fall_tick = NEVER
	elif fall_tick == NEVER:
		fall_tick = GameManager.timeline_tick


## Same rules as Player._pose_sprite(), over the states the echo actually has.
func _pose_sprite() -> void:
	var frames := sprite.sprite_frames
	if is_swinging():
		# Stretched over windup + sweep rather than run at the clip's own fps,
		# so what you see telegraphing is the window you have to parry in.
		sprite.animation = attack_anim
		sprite.frame = SpriteClock.frame_over(frames, attack_anim, attack_start_tick,
			attack_windup + attack_active)
		sprite.scale.x = direction
		return

	var anim: StringName
	var stamp := NEVER
	if not is_on_floor():
		var rising := velocity.y < 0.0
		anim = &"jump" if rising else &"fall"
		stamp = air_tick if rising else fall_tick
	elif absf(velocity.x) > RUN_ANIM_SPEED:
		anim = &"run"
	else:
		anim = &"idle"
	sprite.animation = anim
	sprite.frame = SpriteClock.frame_for(frames, anim, stamp)
	sprite.scale.x = direction


# --- Recall and time stop ---------------------------------------------------

func on_time_stop_ended(frozen_ticks: int) -> void:
	super(frozen_ticks)
	air_tick = _shift_stamp(air_tick, frozen_ticks)
	fall_tick = _shift_stamp(fall_tick, frozen_ticks)
	attack_start_tick = _shift_stamp(attack_start_tick, frozen_ticks)
	last_swing_end_tick = _shift_stamp(last_swing_end_tick, frozen_ticks)


func recall_sample() -> Dictionary:
	var sample := super()
	sample.air_jumps_left = air_jumps_left
	sample.last_floor_tick = last_floor_tick
	return sample


func apply_recall_sample(sample: Dictionary) -> void:
	super(sample)
	air_jumps_left = sample.get("air_jumps_left", max_air_jumps)
	last_floor_tick = sample.get("last_floor_tick", NEVER)


func on_recall_finished() -> void:
	super()
	air_jumps_left = max_air_jumps
	last_floor_tick = NEVER
	# Stamps newer than the rewound clock are from the undone future.
	air_tick = _expire_future(air_tick)
	fall_tick = _expire_future(fall_tick)
	attack_start_tick = _expire_future(attack_start_tick)
	last_swing_end_tick = _expire_future(last_swing_end_tick)
