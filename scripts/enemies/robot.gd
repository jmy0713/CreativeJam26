class_name Robot
extends Walker
## Guard-bot: a knight-sized robot that fights with its fists.
##
## Patrols like a Walker. When the player is nearby it turns to face them,
## closes in with its guard up, and throws a punch: a slow WIND-UP (fist
## cocked back, not parryable) followed by the PUNCH. The punch is parryable
## from the moment it launches (same rule as Knight: a parry pressed during
## the wind-up doesn't count) and the fist only connects when the punch ends,
## so there's a whole punch's worth of time to react. Facing is locked from
## the wind-up on, so the player can also dodge past it.
##
## GUARD: while the guard is up, the player's hits are blocked (a flash on
## the guard plate, no damage). Three things get through: hits from overhead,
## because the guard can't be raised above the robot's head (see
## `overhead_height`) — a down slash lands, and pogos off it — hits from
## underfoot, because it can't be held under the robot's feet either (see
## `underfoot_height`) — an up slash at a robot on a platform above lands —
## and a parry, which BREAKS the guard. The robot staggers, and for
## `guard_break_time` it takes hits like any other enemy, on top of the
## parry's own time stop, during which it stands frozen and defenceless.
##
## RobotBoss overrides _guard_covers_overhead() and holds its guard around the
## whole silhouette, so neither the down slash nor the up slash works on it.
##
## Recall / time stop: every timer is a tick stamp, reset in
## on_recall_finished() and shifted in on_time_stop_ended(), like Knight.
##
## Subclasses: RobotBoss (big version, adds laser eyes). Hooks for them:
## is_busy(), _can_start_punch(), _update_attack(), _cancel_attacks(),
## _on_damaged(), _guard_covers_overhead() and _update_combat_visuals().

const GUARD_COLOR := Color(0.35, 0.6, 0.85, 1)
const GUARD_BLOCK_COLOR := Color(1, 1, 1, 1)
const WINDUP_COLOR := Color(1, 0.6, 0.2, 1)
const ACTIVE_COLOR := Color(1, 0.9, 0.3, 1)
const EYE_IDLE_COLOR := Color(0.55, 0.15, 0.15, 1)
const EYE_ENGAGED_COLOR := Color(1, 0.2, 0.2, 1)
const EYE_BROKEN_COLOR := Color(0.2, 0.2, 0.22, 1)
## How long the guard plate stays lit after it blocks a hit.
const BLOCK_FLASH_TIME := 0.1

@export_group("Combat")
## How far away (and how much vertical offset) counts as "sees the player".
@export var detection_range := 120.0
@export var detection_height := 50.0
## Stops closing the distance once this close (centre to centre).
@export var attack_range := 20.0
@export var approach_speed := 38.8
## Fist pulled back. A parry pressed during this doesn't count.
@export var punch_windup := 0.5
## The punch itself: parryable throughout, damage lands when it ends.
@export var punch_active := 0.25
## The guard stays up at least this long after a punch before the next one.
@export var punch_cooldown := 1.2
@export var punch_damage := 1

@export_group("Guard")
## How long the guard stays broken after a parry, counted from the moment
## the parry's time stop ends.
@export var guard_break_time := 1.2
## If true, only hits from the side the robot faces are blocked, so the
## player can also get through by dashing behind it.
@export var guard_frontal_only := false
## If true, the guard drops while a punch is in progress, so hitting the
## robot mid-punch lands (and interrupts it) instead of being blocked.
@export var vulnerable_while_punching := false
## A hit landing more than this far above the robot's origin comes down over
## the guard, which can't be held overhead. Matches GuardVisual's top edge,
## so anything above the guard's silhouette connects. Ignored when
## _guard_covers_overhead() is true (RobotBoss).
@export var overhead_height := 10.0
## The mirror of `overhead_height`: a hit landing more than this far below the
## origin comes up under the guard, which can't be held under the robot's feet
## either — this is the up slash at a robot standing on a platform above you.
## Matches GuardVisual's bottom edge, and is ignored by the same hook.
@export var underfoot_height := 10.0

@export_group("Patrol")
## While patrolling, turn back when this far from the spawn point.
## 0 = no leash (only walls and ledges turn it around).
@export var patrol_radius := 0.0

@export_group("Visuals")
## Horizontal placement (right-facing; mirrored by `direction`) of the
## guard plate, the eye, and the fist at rest / cocked back / fully out.
@export var guard_x := 8.8
@export var eye_x := 3.5
@export var fist_rest_x := 9.0
@export var fist_back_x := -11.0
@export var fist_reach_x := 20.0

var engaged := false
var attack_start_tick := NEVER
var last_punch_end_tick := NEVER
var guard_broken_tick := NEVER
var last_block_tick := NEVER

var _home_x := 0.0
## Vertical centres of the moving parts, read from the scene.
var _guard_y := 0.0
var _eye_y := 0.0
var _fist_y := 0.0
var _fist_area_x := 0.0
## Set by hit_through_guard() for the duration of that one hit.
var _guard_bypass := false
## True from a parry until its time stop ends. Keeps the guard down while the
## robot is frozen, however short guard_break_time is.
var _frozen_broken := false

@onready var fist_area: Area2D = $FistArea
@onready var fist: ColorRect = $Fist
@onready var guard_visual: ColorRect = $GuardVisual
@onready var eye: ColorRect = $Eye
@onready var dizzy_mark: ColorRect = $DizzyMark


func _ready() -> void:
	super()
	_home_x = global_position.x
	_fist_area_x = absf(fist_area.position.x)
	_guard_y = (guard_visual.offset_top + guard_visual.offset_bottom) * 0.5
	_eye_y = (eye.offset_top + eye.offset_bottom) * 0.5
	_fist_y = (fist.offset_top + fist.offset_bottom) * 0.5
	_update_visuals()


func _behave(delta: float) -> void:
	if is_guard_broken():
		# Staggered: no walking, no attacking, until the guard comes back.
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

## True while a punch is in progress (wind-up or punch).
func is_punching() -> bool:
	return attack_start_tick != NEVER


## True while the robot is committed to an attack: it holds still and keeps
## its facing. Subclasses add their own attacks.
func is_busy() -> bool:
	return is_punching()


func is_guard_broken() -> bool:
	return _frozen_broken or GameManager.ticks_since(guard_broken_tick) < _ticks(guard_break_time)


## True while the guard would block a hit.
func guard_up() -> bool:
	if not engaged or is_guard_broken():
		return false
	return not (vulnerable_while_punching and is_punching())


func take_hit(damage: int, from_position: Vector2) -> void:
	if not alive:
		return
	if not _guard_bypass and _blocks(from_position):
		# Blocked: the plate flashes, no damage, no stun.
		last_block_tick = GameManager.timeline_tick
		return
	super(damage, from_position)
	_on_damaged()


## A hit that ignores the guard (a reflected laser). Still interrupts,
## staggers and damages like a normal hit.
func hit_through_guard(damage: int, from_position: Vector2) -> void:
	_guard_bypass = true
	take_hit(damage, from_position)
	_guard_bypass = false


func on_time_stop_ended(frozen_ticks: int) -> void:
	super(frozen_ticks)
	attack_start_tick = _shift_stamp(attack_start_tick, frozen_ticks)
	last_punch_end_tick = _shift_stamp(last_punch_end_tick, frozen_ticks)
	guard_broken_tick = _shift_stamp(guard_broken_tick, frozen_ticks)
	last_block_tick = _shift_stamp(last_block_tick, frozen_ticks)
	_frozen_broken = false


func on_recall_finished() -> void:
	super()
	attack_start_tick = _expire_future(attack_start_tick)
	last_punch_end_tick = _expire_future(last_punch_end_tick)
	guard_broken_tick = _expire_future(guard_broken_tick)
	last_block_tick = _expire_future(last_block_tick)
	_frozen_broken = false
	engaged = false
	_update_visuals()


# --- Hooks for subclasses ---------------------------------------------------

## Whether a new punch may start (subclasses hold it back during other attacks).
func _can_start_punch() -> bool:
	return true


## Whether the guard is held around the whole silhouette rather than just in
## front of the chest. False here, so a down slash gets through from above
## (and pogos off the robot) and an up slash gets through from below.
## RobotBoss returns true — neither way in works on it.
func _guard_covers_overhead() -> bool:
	return false


## Drives the attacks while engaged. Subclasses call super() and add theirs.
func _update_attack(player: Player) -> void:
	if is_punching():
		var over := GameManager.ticks_since(attack_start_tick) >= _ticks(punch_windup + punch_active)
		if (_is_active() or over) and _fist_reaches(player):
			# Parrying works at any point during the punch (not the wind-up)...
			var punch_start := attack_start_tick + _ticks(punch_windup)
			if player.try_parry(punch_start):
				_on_parried()
				return
			# ...and the fist only connects once the punch has finished.
			if over:
				player.take_damage(punch_damage, global_position)
		if over:
			attack_start_tick = NEVER
			last_punch_end_tick = GameManager.timeline_tick
		return

	if _can_start_punch() and _fist_reaches(player) \
			and GameManager.ticks_since(last_punch_end_tick) >= _ticks(punch_cooldown):
		attack_start_tick = GameManager.timeline_tick


## Drop whatever attack is in progress.
func _cancel_attacks() -> void:
	attack_start_tick = NEVER


## The robot took damage: that interrupts whatever it was doing.
func _on_damaged() -> void:
	_cancel_attacks()
	last_punch_end_tick = GameManager.timeline_tick


## Poses the fist, guard plate, eye and stun marker. Called every frame.
func _update_combat_visuals() -> void:
	var broken := is_guard_broken()

	guard_visual.visible = guard_up()
	var blocked := GameManager.ticks_since(last_block_tick) < _ticks(BLOCK_FLASH_TIME)
	guard_visual.color = GUARD_BLOCK_COLOR if blocked else GUARD_COLOR

	dizzy_mark.visible = broken and (GameManager.timeline_tick / 6) % 2 == 0

	if broken:
		eye.color = EYE_BROKEN_COLOR
	elif engaged:
		eye.color = EYE_ENGAGED_COLOR
	else:
		eye.color = EYE_IDLE_COLOR

	if _is_windup():
		var t := _punch_progress(0.0, punch_windup)
		fist.visible = true
		fist.color = WINDUP_COLOR
		_place(fist, Vector2(lerpf(fist_rest_x, fist_back_x, t * (2.0 - t)) * direction, _fist_y))
	elif _is_active():
		# Accelerates so the fist is fully out just as the hit would land.
		var t := _punch_progress(punch_windup, punch_active)
		fist.visible = true
		fist.color = ACTIVE_COLOR
		_place(fist, Vector2(lerpf(fist_back_x, fist_reach_x, t * t) * direction, _fist_y))
	else:
		fist.visible = false


# --- Internals --------------------------------------------------------------

func _update_visuals() -> void:
	super()
	_position_combat_parts()
	_update_combat_visuals()


func _position_combat_parts() -> void:
	fist_area.position.x = _fist_area_x * direction
	_place(guard_visual, Vector2(guard_x * direction, _guard_y))
	_place(eye, Vector2(eye_x * direction, _eye_y))


## Centres a ColorRect on `center` (local coordinates).
func _place(rect: ColorRect, center: Vector2) -> void:
	var rect_size := Vector2(rect.offset_right - rect.offset_left, rect.offset_bottom - rect.offset_top)
	rect.position = center - rect_size * 0.5


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


func _blocks(from_position: Vector2) -> bool:
	if not guard_up():
		return false
	if not _guard_covers_overhead() and _is_unguarded_angle(from_position):
		return false
	return not guard_frontal_only or _is_frontal(from_position)


## True for a hit coming in above or below the guard, which covers the robot's
## own silhouette and neither the air over it nor the ground under it.
func _is_unguarded_angle(from_position: Vector2) -> bool:
	return _is_overhead(from_position) or _is_underfoot(from_position)


## The guard covers the robot's own silhouette, not the air above it.
func _is_overhead(from_position: Vector2) -> bool:
	return from_position.y < global_position.y - overhead_height


## ...nor the ground below it, which is where an up slash comes from.
func _is_underfoot(from_position: Vector2) -> bool:
	return from_position.y > global_position.y + underfoot_height


func _is_frontal(from_position: Vector2) -> bool:
	var side := signf(from_position.x - global_position.x)
	return side == 0.0 or side == float(direction)


func _fist_reaches(player: Player) -> bool:
	return fist_area.get_overlapping_bodies().has(player)


func _is_windup() -> bool:
	return is_punching() and GameManager.ticks_since(attack_start_tick) < _ticks(punch_windup)


func _is_active() -> bool:
	if not is_punching():
		return false
	var t := GameManager.ticks_since(attack_start_tick)
	return t >= _ticks(punch_windup) and t < _ticks(punch_windup + punch_active)


## The punch was deflected: it ends now, the guard breaks, and the robot
## staggers with a hit flash but takes no damage.
func _on_parried() -> void:
	var now := GameManager.timeline_tick
	_cancel_attacks()
	last_punch_end_tick = now
	last_hit_tick = now
	guard_broken_tick = now
	_frozen_broken = TimeStop.is_active()


## 0 -> 1 over the `duration` seconds that start `offset` seconds into the punch.
func _punch_progress(offset: float, duration: float) -> float:
	var elapsed := GameManager.ticks_since(attack_start_tick) - _ticks(offset)
	return clampf(float(elapsed) / maxi(_ticks(duration), 1), 0.0, 1.0)
