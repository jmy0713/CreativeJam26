class_name Knight
extends Walker
## Hollow Knight "shield fool" style enemy: patrols like a Walker, but when
## the player is nearby it turns to face them and raises a shield that blocks
## every hit, from any side, for as long as it stays engaged — the swing
## included. Periodically it swings its sword, dealing damage if the player is
## in reach.
##
## Three things get through the shield: hits from overhead (it can't be raised
## above the Knight's head — see `overhead_height`), hits from underfoot (nor
## below its feet — see `underfoot_height`, which is what an up slash from a
## lower platform is), and anything landed while a parry has knocked it down
## (`shield_break_time`).
##
## The swing can be parried (see Player.try_parry) only while the blade is
## sweeping — a parry pressed during the windup doesn't count, and where that
## window starts is the one piece of it a subclass may move (see
## `_parry_from_tick()`). A parry deflects the sword, the Knight staggers, and
## time stops for every enemy. The hit itself only lands as the sweep finishes,
## so there's a whole swing's worth of time to react. The parry is the opening:
## the shield drops for the freeze and a moment after it.
##
## Facing/patrol direction is shared: `direction` (from Walker) is repurposed
## as the side the shield and sword sit on while engaged. It only places them
## — the block itself doesn't care which way the Knight faces.

# Sword angles (right-facing; mirrored by the Swing's scale.x). The blade
# rests low in front, is pulled up behind the head during the windup, then
# sweeps over and down in front during the active window, accelerating so it
# reaches the player near the end — when the hit lands.
const SWORD_REST := deg_to_rad(35.0)
const SWORD_RAISED := deg_to_rad(-140.0)
const SWORD_FOLLOW := deg_to_rad(55.0)
const WINDUP_COLOR := Color(1, 0.6, 0.2, 0.75)
const ACTIVE_COLOR := Color(1, 0.9, 0.3, 1)

@export_group("Combat")
## How far away (and how much vertical offset) counts as "sees the player".
@export var detection_range := 133.4
@export var detection_height := 50.0
## Stops closing the distance once this close, so the sword can reach.
@export var attack_range := 25.6
@export var approach_speed := 38.8
@export var swing_windup := 0.35
## The sweep: parryable throughout, damage lands when it ends.
@export var swing_active := 0.25
## Rest between swings, measured from the end of one to the start of the next.
@export var swing_cooldown := 1.1
@export var sword_damage := 1
## How long a parry keeps the shield down once the world is moving again.
## The parry's time stop doesn't eat into it (see `shield_broken`).
@export var shield_break_time := 0.75
## A hit landing more than this far above the Knight's origin goes over the
## shield: it can't be held overhead. Matches ShieldVisual's top edge, so
## anything coming down from above the shield's silhouette connects.
@export var overhead_height := 10.0
## The mirror of `overhead_height`: a hit landing more than this far below the
## origin comes up under the shield, which can't be held under the Knight's
## own feet either. This is the up slash from a lower platform — the Knight
## standing over you is open from below the same way one below you is open
## from above. Matches ShieldVisual's bottom edge.
@export var underfoot_height := 10.0

var engaged := false
var attack_start_tick := NEVER
var last_swing_end_tick := NEVER
## When a parry knocked the shield down. NEVER once the window has run out.
var shield_broken_tick := NEVER

@onready var sword_area: Area2D = $SwordArea
## The two placeholder visuals, and the only nodes a subclass may leave out:
## _position_combat_parts() and _update_combat_visuals() are the seam for
## drawing the fight some other way, and Slime overrides both (see slime.gd).
@onready var swing: SwordSwing = get_node_or_null("Swing")
@onready var shield_visual: ColorRect = get_node_or_null("ShieldVisual")


func _behave(delta: float) -> void:
	_expire_shield_break()
	var player := GameManager.player
	engaged = player != null and player.health > 0 and _can_see(player)

	if engaged:
		var dx := player.global_position.x - global_position.x
		direction = 1 if dx >= 0.0 else -1
		if is_swinging():
			velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
		elif absf(dx) > attack_range:
			velocity.x = signf(dx) * approach_speed
		else:
			velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
		_update_attack(player)
	else:
		attack_start_tick = NEVER
		super(delta)

	_position_combat_parts()
	_update_combat_visuals()


func is_swinging() -> bool:
	return attack_start_tick != NEVER


## True while the shield is up: the whole engagement, swing included, on every
## side. Only a parry takes it down.
func shield_up() -> bool:
	return engaged and not shield_broken()


## True while a parry has left the shield down. The window outlasts the time
## stop the parry starts: a frozen Knight never reaches _expire_shield_break(),
## and on_time_stop_ended() restarts the stamp so the full window still plays
## out once the world moves again. It also holds while the Knight is stunned,
## so landing hits doesn't shorten the opening they bought.
func shield_broken() -> bool:
	return shield_broken_tick != NEVER


func take_hit(damage: int, from_position: Vector2) -> void:
	if not alive:
		return
	if shield_up() and not _is_unguarded_angle(from_position):
		# Blocked: a brief clang stagger, but no damage and no death check.
		last_hit_tick = GameManager.timeline_tick
		return
	super(damage, from_position)


func on_time_stop_ended(frozen_ticks: int) -> void:
	super(frozen_ticks)
	attack_start_tick = _shift_stamp(attack_start_tick, frozen_ticks)
	last_swing_end_tick = _shift_stamp(last_swing_end_tick, frozen_ticks)
	# The freeze doesn't count against the punish window: it starts over now.
	if shield_broken_tick != NEVER:
		shield_broken_tick = GameManager.timeline_tick


func on_recall_finished() -> void:
	super()
	attack_start_tick = _expire_future(attack_start_tick)
	last_swing_end_tick = _expire_future(last_swing_end_tick)
	shield_broken_tick = _expire_future(shield_broken_tick)
	engaged = false
	_update_combat_visuals()


# --- Internals ----------------------------------------------------------

## True for a hit coming in above or below the shield, which covers the
## Knight's own silhouette and neither the air over it nor the ground under it.
func _is_unguarded_angle(from_position: Vector2) -> bool:
	return _is_overhead(from_position) or _is_underfoot(from_position)


## The shield covers the Knight's own silhouette, not the air above it.
func _is_overhead(from_position: Vector2) -> bool:
	return from_position.y < global_position.y - overhead_height


## ...nor the ground below it, which is where an up slash comes from.
func _is_underfoot(from_position: Vector2) -> bool:
	return from_position.y > global_position.y + underfoot_height


## Ends the parry window once it has run out. Only called from _behave, so a
## Knight that can't act — frozen or stunned — holds the window instead of
## burning through it.
func _expire_shield_break() -> void:
	if shield_broken_tick == NEVER:
		return
	if GameManager.ticks_since(shield_broken_tick) >= _ticks(shield_break_time):
		shield_broken_tick = NEVER


func _can_see(player: Player) -> bool:
	var offset := player.global_position - global_position
	return absf(offset.x) <= detection_range and absf(offset.y) <= detection_height


func _is_windup() -> bool:
	return is_swinging() and GameManager.ticks_since(attack_start_tick) < _ticks(swing_windup)


func _is_active() -> bool:
	if not is_swinging():
		return false
	var t := GameManager.ticks_since(attack_start_tick)
	return t >= _ticks(swing_windup) and t < _ticks(swing_windup + swing_active)


func _update_attack(player: Player) -> void:
	if is_swinging():
		var swing_over := GameManager.ticks_since(attack_start_tick) >= _ticks(swing_windup + swing_active)
		if (_is_active() or swing_over) and _sword_reaches(player):
			# Parrying works at any point during the sweep (not the windup)...
			if player.try_parry(_parry_from_tick()):
				_on_parried()
				return
			# ...and the blade only connects once the sweep finishes.
			if swing_over:
				player.take_damage(sword_damage, global_position)
		if swing_over:
			attack_start_tick = NEVER
			last_swing_end_tick = GameManager.timeline_tick
		return

	var in_reach := absf(player.global_position.x - global_position.x) <= attack_range + 6.6
	if in_reach and GameManager.ticks_since(last_swing_end_tick) >= _ticks(swing_cooldown):
		attack_start_tick = GameManager.timeline_tick


## The earliest press that counts as a parry of this swing: the top of the
## sweep, so mashing through the windup doesn't deflect anything. It is a
## method rather than a line inside _update_attack because it is the one part
## of the parry a subclass has any business moving — a Slime opens its window
## early, with the guard it drops (see slime.gd).
##
## Nothing has to widen the *check* to match: the check runs from the top of
## the sweep, and Player.parry_window keeps a press alive long enough to be
## read there, so an opening that starts less than a parry window early is
## honoured on the first frame the swing looks at it.
func _parry_from_tick() -> int:
	return attack_start_tick + _ticks(swing_windup)


func _sword_reaches(player: Player) -> bool:
	return sword_area.get_overlapping_bodies().has(player)


## The swing was deflected: it ends now (the cooldown restarts), the Knight
## staggers with a hit flash, and the shield drops — the parry's whole point.
## It takes no damage from the parry itself, but it's open to hits for the
## time stop plus `shield_break_time` after it.
func _on_parried() -> void:
	attack_start_tick = NEVER
	last_swing_end_tick = GameManager.timeline_tick
	last_hit_tick = GameManager.timeline_tick
	shield_broken_tick = GameManager.timeline_tick


func _position_combat_parts() -> void:
	sword_area.position.x = 21.2 * direction
	shield_visual.position.x = 8.8 * direction
	swing.scale.x = direction


func _update_combat_visuals() -> void:
	shield_visual.visible = shield_up()
	swing.visible = is_swinging()
	if _is_windup():
		var t := _swing_progress(0.0, swing_windup)
		swing.color = WINDUP_COLOR
		swing.set_pose(lerpf(SWORD_REST, SWORD_RAISED, t * (2.0 - t)))
	elif _is_active():
		var t := _swing_progress(swing_windup, swing_active)
		swing.color = ACTIVE_COLOR
		swing.set_pose(lerpf(SWORD_RAISED, SWORD_FOLLOW, t * t), SWORD_RAISED)


## 0 -> 1 over the `duration` seconds that start `offset` seconds into the swing.
func _swing_progress(offset: float, duration: float) -> float:
	var elapsed := GameManager.ticks_since(attack_start_tick) - _ticks(offset)
	return clampf(float(elapsed) / maxi(_ticks(duration), 1), 0.0, 1.0)
