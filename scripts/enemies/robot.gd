class_name Robot
extends Walker
## Guard-bot: a knight-sized robot that fights with an energy blade.
##
## Patrols like a Walker. When the player is nearby it turns to face them,
## closes in, and swings: a slow WIND-UP (blade cocked back, not parryable)
## followed by the SWING. The swing is parryable from the moment it launches
## (same rule as Knight: a parry pressed during the wind-up doesn't count) and
## only connects when it ends, so there's a whole swing's worth of time to
## react. Facing is locked from the wind-up on, so the player can also dodge
## past it. (The exports keep their old `punch_` names from when this was a
## fist.)
##
## The robot can't block: every hit lands like it would on any other enemy. A
## parry still staggers it: it stands frozen for the parry's own time stop, then
## stays dizzy for `guard_break_time` (no walking, no attacking).
##
## ANIMATION: the body is an AnimatedSprite2D wearing robot_frames.tres, and
## nothing here calls play(). Every pose is worked out from a tick stamp (or,
## for walking, from where the robot is standing), so it rewinds with a recall
## and holds still through a time stop, in step with the hitboxes it
## illustrates (ARCHITECTURE.md sections 4 and 7). One swing, frame by frame:
##
##   `punch_windup`   `windup_clip`, stretched to fit. Not parryable.
##   `sweep_time`     `strike`, the arc frame. The parry window opens with it,
##                    so it is the cue to react to.
##   rest of          `follow`: the blade held out in front of the player. The
##   `punch_active`   hit lands the moment this ends...
##   `follow_time`    ...and `follow` holds a little longer as the recovery.
##
## Other poses, highest priority first: dead (the wreck stays put for good),
## staggered by a parry (`hurt`, held), mid-swing (above), freshly hit (`hurt`),
## a subclass's own attack (`_pose_special()`), the follow-through of a swing
## that just ended, walking, idle.
##
## Recall / time stop: every timer is a tick stamp, reset in
## on_recall_finished() and shifted in on_time_stop_ended(), like Knight.
##
## Subclasses: RobotBoss (big version, adds laser eyes). Hooks for them:
## is_busy(), _can_start_punch(), _update_attack(), _cancel_attacks(),
## _on_damaged(), _pose_special() and _update_combat_visuals().

## Below this speed (px/s) the robot counts as standing still.
const WALK_MIN_SPEED := 6.0

@export_group("Combat")
## How far away (and how much vertical offset) counts as "sees the player".
@export var detection_range := 120.0
@export var detection_height := 50.0
## Stops closing the distance once this close (centre to centre).
@export var attack_range := 20.0
@export var approach_speed := 38.8
## Blade pulled back. A parry pressed during this doesn't count.
@export var punch_windup := 0.5
## The swing itself: parryable throughout, damage lands when it ends.
@export var punch_active := 0.25
## Minimum wait after a swing before the next one.
@export var punch_cooldown := 1.2
@export var punch_damage := 1

@export_group("Stagger")
## How long the robot stays staggered after a parry, counted from the moment
## the parry's time stop ends.
@export var guard_break_time := 1.2

@export_group("Patrol")
## While patrolling, turn back when this far from the spawn point.
## 0 = no leash (only walls and ledges turn it around).
@export var patrol_radius := 0.0

@export_group("Animation")
## The clip stretched across the wind-up. A regular robot just cocks its blade
## back (`windup`); RobotBoss raises it overhead (`windup_heavy`).
@export var windup_clip := &"windup"
## The swing opens on the arc frame (`strike`); this long into it, the blade
## settles out in front of the robot (`follow`) and stays there until the swing
## has landed. The parry window opens on the arc frame.
@export var sweep_time := 0.1
## How long the follow-through pose holds after the swing has landed.
@export var follow_time := 0.25
## Ground covered by one whole walk cycle. The walk follows position rather
## than the clock, so the feet match however fast the robot is going.
@export var walk_stride := 26.0

var engaged := false
var _punch_sound_tick := NEVER
var attack_start_tick := NEVER
var last_punch_end_tick := NEVER
var guard_broken_tick := NEVER
## When the last swing ran its course (hit or miss). Not set by a parry or by
## taking a hit, which cut a swing short and have poses of their own.
var swing_end_tick := NEVER
## When the robot died, for the death clip. NEVER while it is alive.
var death_tick := NEVER

var _home_x := 0.0
var _fist_area_x := 0.0
## True from a parry until its time stop ends. Keeps the robot staggered while
## it is frozen, however short guard_break_time is.
var _frozen_broken := false
## The tick the poses are worked out for. It is the timeline's tick, except
## that it stands still through a time stop, so a frozen robot holds its pose
## instead of playing on behind the freeze.
var _pose_tick := 0

@onready var fist_area: Area2D = $FistArea
@onready var sprite: AnimatedSprite2D = $Body
@onready var dizzy_mark: ColorRect = $DizzyMark
@onready var punch_sound: AudioStreamPlayer2D = $AttackSound
@onready var block_sound: AudioStreamPlayer2D = $BlockSound


func _ready() -> void:
	super()
	_home_x = global_position.x
	_fist_area_x = absf(fist_area.position.x)
	_pose_tick = GameManager.timeline_tick
	_update_visuals()


## Enemy skips its whole physics step for a robot that is still on screen, so a
## wreck gets a small one of its own: fall to rest, slide to a stop, keep
## animating. The collision layer is gone, so nothing can touch it — the player
## walks over the body rather than into it.
func _physics_process(delta: float) -> void:
	if alive:
		super(delta)
		return
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
	velocity.x = move_toward(velocity.x, 0.0, 833.4 * delta)
	move_and_slide()
	_update_visuals()


func _behave(delta: float) -> void:
	if is_guard_broken():
		# Staggered: no walking, no attacking, until it recovers.
		velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
		return

	var player := GameManager.player
	engaged = player != null and player.health > 0 and _can_see(player)
	if not engaged:
		_cancel_attacks()
		_patrol(delta)
		return

	var dx := player.global_position.x - global_position.x
	if not is_busy():
		direction = 1 if dx >= 0.0 else -1
	if is_busy() or absf(dx) <= attack_range or not _has_ground_ahead():
		velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
	else:
		velocity.x = signf(dx) * approach_speed
	_update_attack(player)


# --- Public -----------------------------------------------------------------

## True while a swing is in progress (wind-up or swing).
func is_punching() -> bool:
	return attack_start_tick != NEVER


## True while the robot is committed to an attack: it holds still and keeps
## its facing. Subclasses add their own attacks.
func is_busy() -> bool:
	return is_punching()


func is_guard_broken() -> bool:
	return _frozen_broken or GameManager.ticks_since(guard_broken_tick) < _ticks(guard_break_time)


func take_hit(damage: int, from_position: Vector2) -> void:
	if not alive:
		return
		
	# If the robot hasn't been parried (guard broken), it is invincible
	if not is_guard_broken():
		block_sound.play()
		return
		
	super(damage, from_position)
	_on_damaged()


## Kept for callers (a reflected laser). The robot has no guard to bypass, so
## this is just take_hit().
func hit_through_guard(damage: int, from_position: Vector2) -> void:
	if not alive:
		return
	# Explicitly call the parent's take_hit to bypass the local invincibility
	super.take_hit(damage, from_position)
	_on_damaged()


func on_time_stop_ended(frozen_ticks: int) -> void:
	super(frozen_ticks)
	attack_start_tick = _shift_stamp(attack_start_tick, frozen_ticks)
	last_punch_end_tick = _shift_stamp(last_punch_end_tick, frozen_ticks)
	guard_broken_tick = _shift_stamp(guard_broken_tick, frozen_ticks)
	swing_end_tick = _shift_stamp(swing_end_tick, frozen_ticks)
	_frozen_broken = false


func on_recall_finished() -> void:
	super()
	attack_start_tick = _expire_future(attack_start_tick)
	last_punch_end_tick = _expire_future(last_punch_end_tick)
	guard_broken_tick = _expire_future(guard_broken_tick)
	swing_end_tick = _expire_future(swing_end_tick)
	_frozen_broken = false
	engaged = false
	_update_visuals()


# --- Hooks for subclasses ---------------------------------------------------

## Whether a new swing may start (subclasses hold it back during other attacks).
func _can_start_punch() -> bool:
	return true


## Drives the attacks while engaged. Subclasses call super() and add theirs.
func _update_attack(player: Player) -> void:
	if is_punching():
		# Trigger punch sound when moving from wind-up into active swing
		if _is_active() and attack_start_tick != _punch_sound_tick:
			punch_sound.pitch_scale = randf_range(0.9, 1.1)
			punch_sound.play()
			_punch_sound_tick = attack_start_tick

		var over := GameManager.ticks_since(attack_start_tick) >= _ticks(punch_windup + punch_active)
		if (_is_active() or over) and _fist_reaches(player):
			# Parrying works at any point during the swing (not the wind-up)...
			var punch_start := attack_start_tick + _ticks(punch_windup)
			if player.try_parry(punch_start):
				_on_parried()
				return
			# ...and the blade only connects once the swing has finished.
			if over:
				player.take_damage(punch_damage, global_position)
		if over:
			attack_start_tick = NEVER
			last_punch_end_tick = GameManager.timeline_tick
			swing_end_tick = GameManager.timeline_tick
		return

	if _can_start_punch() and _fist_reaches(player) \
			and GameManager.ticks_since(last_punch_end_tick) >= _ticks(punch_cooldown):
		attack_start_tick = GameManager.timeline_tick


## Lets a subclass pose an attack of its own, after the swing and the hurt clip
## have had their say. Return true if it did (RobotBoss: the laser).
func _pose_special() -> bool:
	return false


## Drop whatever attack is in progress.
func _cancel_attacks() -> void:
	attack_start_tick = NEVER


## The robot took damage: that interrupts whatever it was doing.
func _on_damaged() -> void:
	_cancel_attacks()
	last_punch_end_tick = GameManager.timeline_tick


## Poses the sprite and the stun marker. Called every frame.
func _update_combat_visuals() -> void:
	dizzy_mark.visible = alive and is_guard_broken() and (GameManager.timeline_tick / 6) % 2 == 0
	_pose_sprite()


# --- Internals --------------------------------------------------------------

func _update_visuals() -> void:
	super()
	# A time stop freezes the pose clock, except for a wreck, which the stop
	# doesn't touch: a robot killed during a freeze should fall over now.
	if not TimeStop.is_active() or not alive:
		_pose_tick = GameManager.timeline_tick
	_position_combat_parts()
	_update_combat_visuals()


## Enemy.die() hides the enemy and stops it processing on the spot. A robot
## stays up and ticking instead, so its death clip can play. It keeps only the
## world mask, so the wreck still lands on the floor.
func _set_alive(value: bool) -> void:
	super(value)
	if value:
		death_tick = NEVER
		return
	death_tick = GameManager.timeline_tick
	collision_mask = _collision_mask
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT


func _position_combat_parts() -> void:
	fist_area.position.x = _fist_area_x * direction


## Picks the clip and frame for `_pose_tick` (see the header for the order).
func _pose_sprite() -> void:
	sprite.flip_h = direction < 0
	if not alive:
		_pose_corpse()
		return
	if is_guard_broken():
		# The clip plays out, then holds its last frame for the whole stagger.
		_show(&"hurt", _clip_frame(&"hurt", guard_broken_tick))
		return
	if is_punching():
		var age := _pose_tick - attack_start_tick
		if age < _ticks(punch_windup):
			_show(windup_clip, _stretched_frame(windup_clip, attack_start_tick, punch_windup))
		elif age < _ticks(punch_windup + sweep_time):
			_show(&"strike", 0)
		else:
			_show(&"follow", 0)
		return
	var since_hit := _pose_tick - last_hit_tick
	if since_hit >= 0 and GameManager.ticks_to_seconds(since_hit) < SpriteClock.seconds(sprite.sprite_frames, &"hurt"):
		_show(&"hurt", _clip_frame(&"hurt", last_hit_tick))
		return
	if _pose_special():
		return
	var since_swing := _pose_tick - swing_end_tick
	if since_swing >= 0 and GameManager.ticks_to_seconds(since_swing) < follow_time:
		_show(&"follow", 0)
		return
	if is_on_floor() and absf(velocity.x) > WALK_MIN_SPEED:
		var count := sprite.sprite_frames.get_frame_count(&"walk")
		_show(&"walk", posmod(floori(global_position.x * direction / walk_stride * count), count))
		return
	_show(&"idle", _loop_frame(&"idle"))


## The death clip, then the wreck stays where it fell. A killed robot is left
## lying on the floor for the rest of the level instead of blinking out: the
## bodies are the record of the fight, and a recall can stand them back up.
## Once the clip has played and the wreck has come to rest there is nothing
## left to update, so it stops processing and holds that last frame.
func _pose_corpse() -> void:
	_show(&"dead", _clip_frame(&"dead", death_tick))
	var age := GameManager.ticks_to_seconds(_pose_tick - death_tick)
	if age >= SpriteClock.seconds(sprite.sprite_frames, &"dead") \
			and is_on_floor() and is_zero_approx(velocity.x):
		process_mode = Node.PROCESS_MODE_DISABLED


func _show(anim: StringName, frame: int) -> void:
	sprite.animation = anim
	sprite.frame = frame


## Frame of a looping clip on the level clock, as it stood at `_pose_tick`.
func _loop_frame(anim: StringName) -> int:
	var frames := sprite.sprite_frames
	var seconds := GameManager.ticks_to_seconds(_pose_tick)
	return posmod(int(seconds * frames.get_animation_speed(anim)), frames.get_frame_count(anim))


## Frame of a one-shot clip that started at `stamp`, holding its last frame.
func _clip_frame(anim: StringName, stamp: int) -> int:
	return SpriteClock.frame_at(sprite.sprite_frames, anim, GameManager.ticks_to_seconds(_pose_tick - stamp))


## Frame of a clip stretched to fill `duration` seconds from `stamp`, however
## many frames it has. The wind-up is timed by gameplay, not by the art.
func _stretched_frame(anim: StringName, stamp: int, duration: float) -> int:
	var count := sprite.sprite_frames.get_frame_count(anim)
	var t := clampf(GameManager.ticks_to_seconds(_pose_tick - stamp) / maxf(duration, 0.001), 0.0, 1.0)
	return mini(int(t * count), count - 1)


func _patrol(delta: float) -> void:
	if patrol_radius > 0.0:
		var offset := global_position.x - _home_x
		if absf(offset) > patrol_radius and signf(offset) == float(direction):
			direction = -direction
	super._behave(delta)


func _can_see(player: Player) -> bool:
	var offset := player.global_position - global_position
	return absf(offset.x) <= detection_range and absf(offset.y) <= detection_height


## False at a ledge in the facing direction, so chasing never walks it off.
func _has_ground_ahead() -> bool:
	ledge_check.position.x = absf(ledge_check.position.x) * direction
	if not is_on_floor():
		return true
	ledge_check.force_raycast_update()
	return ledge_check.is_colliding()


func _fist_reaches(player: Player) -> bool:
	return fist_area.get_overlapping_bodies().has(player)


func _is_active() -> bool:
	if not is_punching():
		return false
	var t := GameManager.ticks_since(attack_start_tick)
	return t >= _ticks(punch_windup) and t < _ticks(punch_windup + punch_active)


## The swing was deflected: it ends now and the robot staggers with a hit
## flash but takes no damage.
func _on_parried() -> void:
	var now := GameManager.timeline_tick
	_cancel_attacks()
	last_punch_end_tick = now
	last_hit_tick = now
	guard_broken_tick = now
	_frozen_broken = TimeStop.is_active()
