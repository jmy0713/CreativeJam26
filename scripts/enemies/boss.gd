
class_name Boss
extends Enemy
## Boss enemy whose state is NOT affected by Recall.
##
## The player can rewind their own timeline, but:
## - Boss position is not rewound.
## - Boss health is not rewound.
## - Boss attack state is not rewound.
## - Boss attacks are not rewound.
##
## The boss has two simultaneous systems:
##
##     1. SWEEP
##        A large pillar periodically crosses the arena.
##
##     2. BULLET HELL
##        A continuous mathematical bullet pattern runs for the entire
##        duration of the boss fight.
##
## The bullet hell is deliberately NOT part of the sweep state machine.
##
## Therefore bullets can exist during:
##
##     ATTACK_COOLDOWN
##     SWEEP_TELEGRAPH
##     SWEEP
##     SWEEP_RECOVERY
##
## This allows the player to dodge both hazards simultaneously.
##
## During Recall:
##
##     - Player timeline rewinds.
##     - Boss timeline is frozen.
##     - Existing bullets freeze.
##     - Bullet spawning freezes.
##     - Sweep freezes.
##
## When Recall ends, everything resumes from exactly where it stopped.


# =============================================================================
# STATES
# =============================================================================

enum State {
	ATTACK_COOLDOWN,
	SWEEP_TELEGRAPH,
	SWEEP,
	SWEEP_RECOVERY,
	DEAD,
}


# =============================================================================
# ATTACK TYPES
# =============================================================================

enum Attack {
	SWEEP,
	BULLET_HELL,
}


# =============================================================================
# BOSS SETTINGS
# =============================================================================

@export_category("Boss")

## Time spent waiting before starting the next sweep.
@export var attack_delay := 1.5

## Time spent recovering after a sweep.
@export var attack_recovery := 0.5


# =============================================================================
# SWEEP SETTINGS
# =============================================================================

@export_category("Sweep")

## How long the player has to react before the sweep begins.
@export var sweep_telegraph_duration := 1.5

## How long the pillar takes to cross the entire viewport.
@export var sweep_duration := 5.0

## Width of the sweeping pillar.
##
## The actual collision size comes from the Pillar CollisionShape2D.
@export var pillar_width := 15

## Damage dealt by the pillar.
@export var sweep_damage := 2


# =============================================================================
# ARENA SETTINGS
# =============================================================================

@export_category("Arena")

## Left edge of the arena.
@export var arena_left := 0.0

## Right edge of the arena.
@export var arena_right := 640.0

## Top edge of the arena.
@export var arena_top := 0.0

## Bottom edge of the arena.
@export var arena_bottom := 360.0


# =============================================================================
# TELEGRAPH SETTINGS
# =============================================================================

@export_category("Sweep Telegraph")

## Distance inside the arena from the sweep boundary.
@export var telegraph_offset := 25.0

## Starting alpha of the telegraph.
@export_range(0.0, 1.0)
var telegraph_min_alpha := 0.25

## Maximum alpha near the beginning of the attack.
@export_range(0.0, 1.0)
var telegraph_max_alpha := 1.0

## Minimum arrow scale.
@export var arrow_scale_min := 0.8

## Maximum arrow scale.
@export var arrow_scale_max := 1.2


# =============================================================================
# BULLET HELL SETTINGS
# =============================================================================
#
# The bullet hell is independent from the sweep state machine.
#
# The boss continuously generates patterns while alive.
#
# Current pattern:
#
#     rotating radial bursts
#
# Example:
#
#                 •
#             •       •
#
#          •     BOSS    •
#
#             •       •
#                 •
#
# Every burst rotates slightly, producing a spiral / flower pattern.
#


@export_category("Bullet Hell")

## Time between radial bullet bursts.
@export var bullet_spawn_interval := 1

## Number of bullets spawned in each radial burst.
@export var bullets_per_burst := 4

## Initial speed of each bullet.
@export var bullet_speed := 60.0

## Damage dealt by one bullet.
@export var bullet_damage := 1

## Radius of the bullet collision.
@export var bullet_radius := 6

## Radius at which bullets are spawned around the boss.
##
## This prevents the bullet from spawning directly inside the boss.
@export var bullet_spawn_radius := 35.0

## Amount by which the whole radial pattern rotates after every burst.
##
## 0 degrees:
##
##         •
##         |
##     •---B---•
##         |
##         •
##
## Positive values gradually rotate the pattern.
@export var bullet_pattern_rotation := 40.0

## Starting angle of the bullet pattern in degrees.
@export var bullet_pattern_start_angle := 0.0

## Small random variation added to each bullet angle.
##
## Keep this at 0 for a perfectly mathematical pattern.
@export var bullet_angle_jitter := 0.0

## Whether bullets should be allowed to spawn immediately when the boss
## enters the scene.
@export var bullet_spawn_immediately := true

## Additional second pattern.
##
## Every few bursts, a second ring is emitted with fewer bullets.
## This makes the pattern less repetitive while remaining deterministic.
@export var secondary_ring_enabled := true

## Number of bullets in the secondary ring.
@export var secondary_bullets_per_burst := 6

## Speed of the secondary ring.
@export var secondary_bullet_speed := 105.0

## Every Nth burst also creates the secondary ring.
@export var secondary_ring_every := 3


# =============================================================================
# GENERAL STATE
# =============================================================================

var state := State.ATTACK_COOLDOWN

## Attack that will be started after the current cooldown.
##
## The sweep system currently only uses SWEEP.
var next_attack := Attack.SWEEP

## Time elapsed in the current sweep state.
##
## This is deliberately NOT GameManager.timeline_tick.
## Recall therefore does not rewind this timer.
var state_time := 0.0


# =============================================================================
# SWEEP STATE
# =============================================================================

## X position where the pillar enters the viewport.
var sweep_start_x := 0.0

## X position where the pillar leaves the viewport.
var sweep_end_x := 0.0

## Y position of the sweep.
var sweep_y := 0.0

## +1:
##
##     LEFT → RIGHT
##
## -1:
##
##     RIGHT → LEFT
var _sweep_direction := 1.0

## Prevents repeated damage during one sweep.
var _player_hit_this_sweep := false


# =============================================================================
# BULLET STATE
# =============================================================================

## Time until the next bullet burst.
var _bullet_spawn_timer := 0.0

## Current rotation of the mathematical bullet pattern.
##
## Stored in radians.
var _bullet_pattern_angle := 0.0

## Number of radial bursts that have been created.
var _bullet_burst_count := 0


# =============================================================================
# BULLET DATA
# =============================================================================
#
# Each bullet is stored as:
#
# {
#     "node": Area2D,
#     "velocity": Vector2
# }
#
# The bullet itself is an Area2D with:
#
#     Area2D
#     ├── Polygon2D
#     └── CollisionShape2D
#
# The Boss owns the movement and lifetime of all bullets.
#
# This means there is no separate Bullet.gd needed yet.
#




var _bullets: Array[Dictionary] = []



# =============================================================================
# BOSS POSITION / FADE
# =============================================================================

@export_category("Boss Position")

## How long the boss stays at each position.
@export var boss_position_duration := 10.0

## How long the fade-out/fade-in takes.
@export var boss_fade_duration := 0.5

## Positions used by the boss.
@export var boss_top_position := Vector2(305.0, 120.0)
@export var boss_bottom_left_position := Vector2(150.0, 260.0)
@export var boss_bottom_right_position := Vector2(475.0, 260.0)

var _boss_position_timer := 0.0
var _boss_position_index := 0

var _boss_fading := false
var _boss_fade_time := 0.0
var _boss_fade_out := false



# =============================================================================
# NODES
# =============================================================================
@onready var body_animation: AnimatedSprite2D = $BodyAnimation
@onready var pillar: Area2D = $Pillar
var _hit_flash_time := 0.0
@export var hit_flash_duration := 0.1

## Visual warning shown before the sweep.
##
## Expected structure:
##
##     SweepTelegraph
##     ├── Line
##     └── Arrow
@onready var sweep_telegraph: Node2D = $SweepTelegraph


## Vertical warning line.
@onready var telegraph_line: CanvasItem = $SweepTelegraph/Line


## Direction arrow.
##
## Assumes the arrow's default orientation points RIGHT.
@onready var telegraph_arrow: CanvasItem = $SweepTelegraph/Arrow


# =============================================================================
# READY
# =============================================================================

func _ready() -> void:
	super._ready()

	# -------------------------------------------------------------------------
	# The boss is outside the Recall timeline.
	# -------------------------------------------------------------------------

	remove_from_group("recordable")
	add_to_group("boss")
	global_position = boss_top_position
	modulate.a = 1.0
	
	body_animation.play("default")
	_boss_position_timer = boss_position_duration
	_boss_position_index = 0
	# -------------------------------------------------------------------------
	# Pillar starts inactive.
	# -------------------------------------------------------------------------

	pillar.visible = false
	pillar.monitoring = false

	# -------------------------------------------------------------------------
	# Telegraph starts inactive.
	# -------------------------------------------------------------------------

	sweep_telegraph.visible = false
	telegraph_line.visible = false
	telegraph_arrow.visible = false

	# -------------------------------------------------------------------------
	# Initialize bullet system.
	# -------------------------------------------------------------------------

	_bullet_pattern_angle = deg_to_rad(
		bullet_pattern_start_angle
	)

	if bullet_spawn_immediately:
		_bullet_spawn_timer = 0.0
	else:
		_bullet_spawn_timer = bullet_spawn_interval

	# -------------------------------------------------------------------------
	# Start the sweep cycle.
	# -------------------------------------------------------------------------

	_begin_attack_cooldown()


# =============================================================================
# PROCESS
# =============================================================================

func _physics_process(delta: float) -> void:
	if not alive:
		return

	# -------------------------------------------------------------------------
	# Boss timers are independent from GameManager.timeline_tick.
	#
	# Recall freezes this entire node because the boss is outside the player's
	# rewind timeline.
	# -------------------------------------------------------------------------

	state_time += delta

	# -------------------------------------------------------------------------
	# SWEEP STATE MACHINE
	# -------------------------------------------------------------------------

	match state:
		State.ATTACK_COOLDOWN:
			_update_attack_cooldown()

		State.SWEEP_TELEGRAPH:
			_update_sweep_telegraph()

		State.SWEEP:
			_update_sweep()

		State.SWEEP_RECOVERY:
			_update_sweep_recovery()

		State.DEAD:
			return

	# -------------------------------------------------------------------------
	# BULLET HELL
	#
	# IMPORTANT:
	#
	# This runs OUTSIDE the state machine.
	#
	# Therefore bullets continue during sweeps.
	# -------------------------------------------------------------------------

	_update_bullet_hell(delta)
	_update_hit_flash(delta)

	_update_visuals()
	_update_boss_position(delta)

# =============================================================================
# DAMAGE
# =============================================================================

## Boss damage is permanent.
##
## Enemy.take_hit() normally records damage in Recall.
## The boss deliberately does not do that.
func take_hit(damage: int, from_position: Vector2) -> void:
	if not alive:
		return

	health -= damage
	last_hit_tick = GameManager.timeline_tick
	_hit_flash_time = hit_flash_duration
	body_animation.modulate = Color(2.0, 2.0, 2.0, 1.0)
	# Keep normal enemy knockback behavior.
	var dir := signf(global_position.x - from_position.x)

	velocity.x = (
		dir if dir != 0.0 else 1.0
	) * knockback_speed

	if health <= 0:
		die()


## Boss death is permanent.
func die() -> void:
	if not alive:
		return

	_set_boss_alive(false)

	died.emit(self)
	GameManager.notify_enemy_died(self)


func _set_boss_alive(value: bool) -> void:
	alive = value
	visible = value

	if value:
		collision_layer = _collision_layer
		collision_mask = _collision_mask
		process_mode = Node.PROCESS_MODE_INHERIT
	else:
		collision_layer = 0
		collision_mask = 0

		# Stop the entire boss hierarchy.
		process_mode = Node.PROCESS_MODE_DISABLED

	# -------------------------------------------------------------------------
	# Disable pillar.
	# -------------------------------------------------------------------------

	pillar.visible = false
	pillar.monitoring = false

	# -------------------------------------------------------------------------
	# Disable telegraph.
	# -------------------------------------------------------------------------

	sweep_telegraph.visible = false
	telegraph_line.visible = false
	telegraph_arrow.visible = false

	# -------------------------------------------------------------------------
	# Destroy all active bullets.
	# -------------------------------------------------------------------------

	_clear_all_bullets()

	state = State.DEAD


# =============================================================================
# ATTACK ARCHITECTURE
# =============================================================================

## Starts the generic cooldown between sweeps.
##
## NOTE:
##
## This does NOT stop the bullet hell.
func _begin_attack_cooldown() -> void:
	state = State.ATTACK_COOLDOWN
	state_time = 0.0

	# Disable sweep.
	pillar.visible = false
	pillar.monitoring = false

	# Disable telegraph.
	sweep_telegraph.visible = false
	telegraph_line.visible = false
	telegraph_arrow.visible = false

	_player_hit_this_sweep = false


func _update_attack_cooldown() -> void:
	if state_time < attack_delay:
		return

	_begin_next_attack()


## Starts the next sweep.
##
## Bullet hell is deliberately NOT selected here.
##
## The bullet hell runs continuously in parallel.
func _begin_next_attack() -> void:
	match next_attack:
		Attack.SWEEP:
			_begin_sweep_telegraph()

		Attack.BULLET_HELL:
			# Kept for future expansion.
			_begin_sweep_telegraph()


## All sweep attacks eventually pass through the recovery state.
func _begin_attack_recovery() -> void:
	state = State.SWEEP_RECOVERY
	state_time = 0.0


func _update_sweep_recovery() -> void:
	if state_time >= attack_recovery:
		_begin_attack_cooldown()


# =============================================================================
# SWEEP TELEGRAPH
# =============================================================================

func _begin_sweep_telegraph() -> void:
	state = State.SWEEP_TELEGRAPH
	state_time = 0.0

	_player_hit_this_sweep = false

	# -------------------------------------------------------------------------
	# Calculate sweep boundaries.
	# -------------------------------------------------------------------------

	if _sweep_direction > 0.0:
		sweep_start_x = arena_left
		sweep_end_x = arena_right
	else:
		sweep_start_x = arena_right
		sweep_end_x = arena_left

	# Sweep through the vertical center of the viewport.
	sweep_y = (arena_top + arena_bottom) * 0.5

	# -------------------------------------------------------------------------
	# Position telegraph.
	# -------------------------------------------------------------------------

	var warning_x := sweep_start_x

	if _sweep_direction > 0.0:
		warning_x += telegraph_offset
	else:
		warning_x -= telegraph_offset

	sweep_telegraph.global_position = Vector2(
		warning_x,
		sweep_y
	)

	# -------------------------------------------------------------------------
	# Configure arrow direction.
	# -------------------------------------------------------------------------

	if _sweep_direction > 0.0:
		telegraph_arrow.rotation = 0.0
	else:
		telegraph_arrow.rotation = PI

	# -------------------------------------------------------------------------
	# Initial telegraph appearance.
	# -------------------------------------------------------------------------

	telegraph_arrow.scale = (
		Vector2.ONE * arrow_scale_min
	)

	telegraph_line.modulate.a = telegraph_min_alpha
	telegraph_arrow.modulate.a = telegraph_min_alpha

	sweep_telegraph.visible = true
	telegraph_line.visible = true
	telegraph_arrow.visible = true

	# -------------------------------------------------------------------------
	# Pillar remains inactive.
	# -------------------------------------------------------------------------

	pillar.visible = false
	pillar.monitoring = false


# =============================================================================
# SWEEP TELEGRAPH UPDATE
# =============================================================================

func _update_sweep_telegraph() -> void:
	var progress := clampf(
		state_time / sweep_telegraph_duration,
		0.0,
		1.0
	)

	# -------------------------------------------------------------------------
	# Pulse increasingly quickly.
	# -------------------------------------------------------------------------

	var pulse_speed := lerpf(
		5.0,
		20.0,
		progress
	)

	var pulse := (
		sin(state_time * pulse_speed)
		+ 1.0
	) * 0.5

	# -------------------------------------------------------------------------
	# Increase visibility toward the attack.
	# -------------------------------------------------------------------------

	var alpha := lerpf(
		telegraph_min_alpha,
		telegraph_max_alpha,
		progress
	)

	alpha *= lerpf(
		0.55,
		1.0,
		pulse
	)

	telegraph_line.modulate.a = alpha
	telegraph_arrow.modulate.a = alpha

	# -------------------------------------------------------------------------
	# Grow arrow.
	# -------------------------------------------------------------------------

	var arrow_scale := lerpf(
		arrow_scale_min,
		arrow_scale_max,
		progress
	)

	arrow_scale *= lerpf(
		0.95,
		1.05,
		pulse
	)

	telegraph_arrow.scale = (
		Vector2.ONE * arrow_scale
	)

	# -------------------------------------------------------------------------
	# Keep warning at correct edge.
	# -------------------------------------------------------------------------

	var warning_x := sweep_start_x

	if _sweep_direction > 0.0:
		warning_x += telegraph_offset
	else:
		warning_x -= telegraph_offset

	sweep_telegraph.global_position = Vector2(
		warning_x,
		sweep_y
	)

	# -------------------------------------------------------------------------
	# Begin actual sweep.
	# -------------------------------------------------------------------------

	if state_time >= sweep_telegraph_duration:
		_begin_sweep()


# =============================================================================
# SWEEP
# =============================================================================

func _begin_sweep() -> void:
	state = State.SWEEP
	state_time = 0.0

	# Hide telegraph.
	sweep_telegraph.visible = false
	telegraph_line.visible = false
	telegraph_arrow.visible = false

	# Activate pillar.
	pillar.visible = true
	pillar.monitoring = true
	pillar.modulate.a = 1.0

	# Start at viewport boundary.
	pillar.global_position = Vector2(
		sweep_start_x,
		sweep_y
	)

	_player_hit_this_sweep = false


func _update_sweep() -> void:
	var progress := clampf(
		state_time / sweep_duration,
		0.0,
		1.0
	)

	# -------------------------------------------------------------------------
	# Move pillar across entire viewport.
	# -------------------------------------------------------------------------

	pillar.global_position = Vector2(
		lerpf(
			sweep_start_x,
			sweep_end_x,
			progress
		),
		sweep_y
	)

	# -------------------------------------------------------------------------
	# Check collision every physics frame.
	# -------------------------------------------------------------------------

	_check_pillar_damage(true)

	if progress >= 1.0:
		_end_sweep()


func _end_sweep() -> void:
	# Disable pillar.
	pillar.visible = false
	pillar.monitoring = false

	_player_hit_this_sweep = false

	# Next sweep comes from opposite side.
	_sweep_direction *= -1.0

	# Enter recovery.
	_begin_attack_recovery()


# =============================================================================
# PILLAR COLLISION / DAMAGE
# =============================================================================

func _check_pillar_damage(active: bool) -> void:
	if not active:
		return

	if _player_hit_this_sweep:
		return

	var player := GameManager.player as Player

	if player == null:
		return

	if player.health <= 0:
		return

	if not pillar.get_overlapping_bodies().has(player):
		return

	player.take_damage(
		sweep_damage,
		pillar.global_position
	)

	_player_hit_this_sweep = true


# =============================================================================
# BULLET HELL
# =============================================================================
#
# This entire system runs independently of the sweep state machine.
#
# A burst looks approximately like:
#
#
#                 •
#
#            •         •
#
#        •       B       •
#
#            •         •
#
#                 •
#
#
# The next burst rotates:
#
#
#                  •
#
#             •         •
#
#         •       B       •
#
#             •         •
#
#                  •
#
#
# Repeating this produces a rotating flower / spiral pattern.
#


func _update_bullet_hell(delta: float) -> void:
	# -------------------------------------------------------------------------
	# Spawn timer.
	# -------------------------------------------------------------------------
	_bullet_spawn_timer -= delta

	while _bullet_spawn_timer <= 0.0:
		_spawn_bullet_burst()

		_bullet_spawn_timer += bullet_spawn_interval

	# -------------------------------------------------------------------------
	# Move existing bullets.
	# -------------------------------------------------------------------------

	_update_bullets(delta)


# =============================================================================
# BULLET BURST
# =============================================================================

func _spawn_bullet_burst() -> void:


	var burst_center := global_position

	# -------------------------------------------------------------------------
	# Main radial ring.
	# -------------------------------------------------------------------------

	if bullets_per_burst > 0:
		var angle_step := TAU / float(bullets_per_burst)

		for i in range(bullets_per_burst):
			var angle := (
				_bullet_pattern_angle
				+ angle_step * float(i)
			)

			if bullet_angle_jitter > 0.0:
				angle += randf_range(
					-deg_to_rad(bullet_angle_jitter),
					deg_to_rad(bullet_angle_jitter)
				)

			var direction := Vector2.from_angle(angle)

			var spawn_position := (
				burst_center
				+ direction * bullet_spawn_radius
			)

			_create_bullet(
				spawn_position,
				direction * bullet_speed
			)

	# -------------------------------------------------------------------------
	# Optional secondary ring.
	#
	# Every few bursts, create a smaller/faster ring.
	#
	# This gives the player another layer to navigate without making the
	# pattern completely random.
	# -------------------------------------------------------------------------

	if (
		secondary_ring_enabled
		and secondary_ring_every > 0
		and _bullet_burst_count % secondary_ring_every == 0
		and secondary_bullets_per_burst > 0
	):
		var secondary_step := (
			TAU / float(secondary_bullets_per_burst)
		)

		# Rotate secondary ring relative to the main ring.
		var secondary_offset := PI / float(
			secondary_bullets_per_burst
		)

		for i in range(secondary_bullets_per_burst):
			var angle := (
				_bullet_pattern_angle
				+ secondary_offset
				+ secondary_step * float(i)
			)

			var direction := Vector2.from_angle(angle)

			var spawn_position := (
				burst_center
				+ direction * bullet_spawn_radius
			)

			_create_bullet(
				spawn_position,
				direction * secondary_bullet_speed
			)

	# -------------------------------------------------------------------------
	# Rotate pattern for the next burst.
	# -------------------------------------------------------------------------

	_bullet_pattern_angle += deg_to_rad(
		bullet_pattern_rotation
	)

	_bullet_burst_count += 1


# =============================================================================
# CREATE BULLET
# =============================================================================

func _create_bullet(
	spawn_position: Vector2,
	bullet_velocity: Vector2
) -> void:
	var bullet := Area2D.new()

	bullet.name = "BossBullet"

	bullet.collision_layer = 1
	bullet.collision_mask = 2

	
	var visual := Polygon2D.new()

	visual.polygon = PackedVector2Array([
		Vector2(0, -bullet_radius),
		Vector2(bullet_radius, 0),
		Vector2(0, bullet_radius),
		Vector2(-bullet_radius, 0),
	])


	bullet.add_child(visual)

	var collision := CollisionShape2D.new()

	var circle := CircleShape2D.new()
	circle.radius = bullet_radius

	collision.shape = circle

	bullet.add_child(collision)

	# IMPORTANT:
	# Parent the bullet first.
	add_child(bullet)

	# NOW global_position is relative to the Boss hierarchy correctly.
	bullet.global_position = spawn_position

	_bullets.append({
		"node": bullet,
		"velocity": bullet_velocity,
	})
# =============================================================================
# UPDATE BULLETS
# =============================================================================

func _update_bullets(delta: float) -> void:
	var player := GameManager.player as Player

	# Iterate backwards so bullets can safely be removed.
	for i in range(_bullets.size() - 1, -1, -1):
		var bullet_data: Dictionary = _bullets[i]

		var bullet: Area2D = bullet_data["node"]
		var velocity: Vector2 = bullet_data["velocity"]

		if not is_instance_valid(bullet):
			_bullets.remove_at(i)
			continue

		# ---------------------------------------------------------------------
		# Move bullet.
		# ---------------------------------------------------------------------

		bullet.global_position += velocity * delta

		# ---------------------------------------------------------------------
		# Rotate visual so the diamond follows its direction.
		# ---------------------------------------------------------------------

		bullet.rotation = velocity.angle()

		# ---------------------------------------------------------------------
		# Check player collision.
		#
		# We deliberately check overlapping bodies ourselves instead of using
		# body_entered. This is consistent with the pillar implementation and
		# makes Recall behavior predictable.
		# ---------------------------------------------------------------------

		if player != null and player.health > 0:
			if bullet.get_overlapping_bodies().has(player):
				player.take_damage(
					bullet_damage,
					bullet.global_position
				)

				_remove_bullet(i)
				continue

		# ---------------------------------------------------------------------
		# Delete bullets after they leave the arena.
		#
		# The margin prevents bullets from disappearing visually right at
		# the edge.
		# ---------------------------------------------------------------------

		var margin := bullet_radius * 2.0

		if (
			bullet.global_position.x < arena_left - margin
			or bullet.global_position.x > arena_right + margin
			or bullet.global_position.y < arena_top - margin
			or bullet.global_position.y > arena_bottom + margin
		):
			_remove_bullet(i)


# =============================================================================
# REMOVE BULLET
# =============================================================================

func _remove_bullet(index: int) -> void:
	if index < 0 or index >= _bullets.size():
		return

	var bullet_data: Dictionary = _bullets[index]
	var bullet: Area2D = bullet_data["node"]

	_bullets.remove_at(index)

	if is_instance_valid(bullet):
		bullet.queue_free()


# =============================================================================
# CLEAR ALL BULLETS
# =============================================================================

func _clear_all_bullets() -> void:
	for bullet_data in _bullets:
		var bullet: Area2D = bullet_data["node"]

		if is_instance_valid(bullet):
			bullet.queue_free()

	_bullets.clear()


# =============================================================================
# RECALL / TIME STOP
# =============================================================================
#
# There are intentionally no Recall sample functions here.
#
# The boss removes itself from "recordable", so Recall never samples:
#
#     global_position
#     state
#     state_time
#     pillar position
#     sweep direction
#     attack progress
#     boss health
#     bullet positions
#     bullet velocities
#     bullet pattern angle
#
# During Recall:
#
#     PLAYER TIMELINE
#         ↓
#       REWINDS
#
#     BOSS TIMELINE
#         ↓
#       FROZEN
#         ↓
#       RESUMES
#
# Existing bullets therefore freeze.
#
# The bullet spawn timer also freezes.
#
# This means the boss resumes its bullet pattern exactly where it was
# before Recall started.

# =============================================================================
# BOSS POSITION / FADE
# =============================================================================

func _update_boss_position(delta: float) -> void:
	# -------------------------------------------------------------------------
	# Currently fading.
	# -------------------------------------------------------------------------

	if _boss_fading:
		_boss_fade_time += delta

		var progress := clampf(
			_boss_fade_time / boss_fade_duration,
			0.0,
			1.0
		)

		if _boss_fade_out:
			# Fade OUT: 1 -> 0
			modulate.a = 1.0 - progress

			if progress >= 1.0:
				_move_to_next_boss_position()

		else:
			# Fade IN: 0 -> 1
			modulate.a = progress

			if progress >= 1.0:
				_boss_fading = false
				_boss_position_timer = boss_position_duration

		return

	# -------------------------------------------------------------------------
	# Boss is visible and stationary.
	# -------------------------------------------------------------------------

	_boss_position_timer -= delta

	if _boss_position_timer <= 0.0:
		_begin_boss_fade_out()


func _begin_boss_fade_out() -> void:
	_boss_fading = true
	_boss_fade_out = true
	_boss_fade_time = 0.0


func _move_to_next_boss_position() -> void:
	# Choose one of the OTHER two positions.
	var previous_index := _boss_position_index

	while _boss_position_index == previous_index:
		_boss_position_index = randi_range(0, 2)

	# Move while invisible.
	global_position = _get_boss_position(_boss_position_index)

	# Begin fade-in.
	_boss_fade_out = false
	_boss_fade_time = 0.0


func _get_boss_position(index: int) -> Vector2:
	match index:
		0:
			return boss_top_position

		1:
			return boss_bottom_left_position

		2:
			return boss_bottom_right_position

	return boss_top_position
# =============================================================================
# VISUALS
# =============================================================================

func refresh_visuals() -> void:
	_update_visuals()
	
func _update_hit_flash(delta: float) -> void:
	if _hit_flash_time <= 0.0:
		return

	_hit_flash_time -= delta

	if _hit_flash_time <= 0.0:
		body_animation.modulate = Color.WHITE

func _update_visuals() -> void:
	super()
