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
## The bullet hell is independent from the sweep state machine.


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

@export var attack_delay := 1.5
@export var attack_recovery := 0.5


# =============================================================================
# SWEEP SETTINGS
# =============================================================================

@export_category("Sweep")

@export var sweep_telegraph_duration := 1.5
@export var sweep_duration := 5.0
@export var pillar_width := 15
@export var sweep_damage := 2
@onready var laser_sound: AudioStreamPlayer2D = $LaserSound


# =============================================================================
# ARENA SETTINGS
# =============================================================================

@export_category("Arena")

@export var arena_left := 0.0
@export var arena_right := 640.0
@export var arena_top := 0.0
@export var arena_bottom := 360.0


# =============================================================================
# SWEEP TELEGRAPH SETTINGS
# =============================================================================

@export_category("Sweep Telegraph")

@export var telegraph_offset := 25.0

@export_range(0.0, 1.0)
var telegraph_min_alpha := 0.25

@export_range(0.0, 1.0)
var telegraph_max_alpha := 1.0

@export var arrow_scale_min := 0.8
@export var arrow_scale_max := 1.2


# =============================================================================
# BULLET HELL SETTINGS
# =============================================================================

@export_category("Bullet Hell")

## Time between radial bullet bursts.
@export var bullet_spawn_interval := 1.0

## Number of bullets in the main radial ring.
@export var bullets_per_burst := 4

## Speed of main bullets.
@export var bullet_speed := 60.0

## Damage dealt by one bullet.
@export var bullet_damage := 1

## Bullet collision/visual radius.
@export var bullet_radius := 6.0

## Distance from the boss where bullets spawn.
@export var bullet_spawn_radius := 35.0

## Rotation applied after every burst.
@export var bullet_pattern_rotation := 40.0

## Initial pattern angle in degrees.
@export var bullet_pattern_start_angle := 0.0

## Random angle variation.
@export var bullet_angle_jitter := 0.0

## Spawn first burst immediately.
@export var bullet_spawn_immediately := true

## Enable secondary ring.
@export var secondary_ring_enabled := true

## Number of secondary bullets.
@export var secondary_bullets_per_burst := 6

## Speed of secondary bullets.
@export var secondary_bullet_speed := 105.0

## Every Nth burst gets the secondary ring.
@export var secondary_ring_every := 3

@onready var bullet_sound: AudioStreamPlayer2D = $BulletSound


# =============================================================================
# BULLET TELEGRAPH SETTINGS
# =============================================================================

@export_category("Bullet Telegraph")

## Length of each red warning line.
@export var bullet_telegraph_length := 120.0

## Width of each red warning line.
@export var bullet_telegraph_width := 2.0

## Transparency of each red warning line.
@export_range(0.0, 1.0)
var bullet_telegraph_alpha := 0.35

## Z layer used by bullet telegraphs.
@export var bullet_telegraph_z_index := 10


# =============================================================================
# GENERAL STATE
# =============================================================================

var state := State.ATTACK_COOLDOWN

var next_attack := Attack.SWEEP

var state_time := 0.0


# =============================================================================
# SWEEP STATE
# =============================================================================

var sweep_start_x := 0.0
var sweep_end_x := 0.0
var sweep_y := 0.0

## +1 = LEFT -> RIGHT
## -1 = RIGHT -> LEFT
var _sweep_direction := 1.0

var _player_hit_this_sweep := false


# =============================================================================
# BULLET STATE
# =============================================================================

## Red Line2D objects showing the directions of the NEXT bullet burst.
var _bullet_telegraphs: Array[Line2D] = []

## Time remaining until the next burst.
var _bullet_spawn_timer := 0.0

## Current mathematical angle of the bullet pattern.
var _bullet_pattern_angle := 0.0

## Number of bursts already spawned.
var _bullet_burst_count := 0


# =============================================================================
# BULLET DATA
# =============================================================================

var _bullets: Array[Dictionary] = []


# =============================================================================
# BOSS POSITION / FADE
# =============================================================================

@export_category("Boss Position")

@export var boss_position_duration := 5.0
@export var boss_fade_duration := 0.5


@export var boss_top_position := Vector2(320.0, 120.0)
@export var boss_bottom_left_position := Vector2(180.0, 290.0)
@export var boss_bottom_right_position := Vector2(455.0, 290.0)

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
@onready var pillar_animation: AnimatedSprite2D = $Pillar/AnimatedSprite2D
@onready var sweep_telegraph: Node2D = $SweepTelegraph
@onready var telegraph_line: CanvasItem = $SweepTelegraph/Line
@onready var telegraph_arrow: CanvasItem = $SweepTelegraph/Arrow


# =============================================================================
# HIT FLASH
# =============================================================================

var _hit_flash_time := 0.0

@export var hit_flash_duration := 0.1


# =============================================================================
# READY
# =============================================================================

func _ready() -> void:
	super._ready()

	# -------------------------------------------------------------------------
	# Boss is not part of Recall.
	# -------------------------------------------------------------------------

	remove_from_group("recordable")
	add_to_group("boss")

	global_position = boss_top_position
	modulate.a = 1.0

	body_animation.play("default")

	_boss_position_timer = boss_position_duration
	_boss_position_index = 0

	# -------------------------------------------------------------------------
	# Pillar starts disabled.
	# -------------------------------------------------------------------------

	pillar.visible = false
	pillar.monitoring = false

	# -------------------------------------------------------------------------
	# Sweep telegraph starts disabled.
	# -------------------------------------------------------------------------

	sweep_telegraph.visible = false
	telegraph_line.visible = false
	telegraph_arrow.visible = false

	# -------------------------------------------------------------------------
	# Initialize bullet pattern.
	# -------------------------------------------------------------------------

	_bullet_pattern_angle = deg_to_rad(
		bullet_pattern_start_angle
	)

	if bullet_spawn_immediately:
		_bullet_spawn_timer = 0.0
	else:
		_bullet_spawn_timer = bullet_spawn_interval

	# -------------------------------------------------------------------------
	# Create red bullet telegraphs.
	# -------------------------------------------------------------------------

	_create_bullet_telegraphs()
	_update_bullet_telegraphs()

	# -------------------------------------------------------------------------
	# Start sweep cycle.
	# -------------------------------------------------------------------------

	_begin_attack_cooldown()


# =============================================================================
# PHYSICS PROCESS
# =============================================================================

func _physics_process(delta: float) -> void:
	if not alive:
		return

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
	# BULLET HELL RUNS INDEPENDENTLY.
	# -------------------------------------------------------------------------

	_update_bullet_hell(delta)

	_update_hit_flash(delta)

	_update_visuals()

	_update_boss_position(delta)

	# -------------------------------------------------------------------------
	# Make sure bullet telegraphs stay attached to the boss.
	# -------------------------------------------------------------------------

	_update_bullet_telegraphs()


# =============================================================================
# DAMAGE
# =============================================================================

func take_hit(damage: int, from_position: Vector2) -> void:
	if not alive:
		return

	health -= damage

	last_hit_tick = GameManager.timeline_tick

	_hit_flash_time = hit_flash_duration

	body_animation.modulate = Color(
		2.0,
		2.0,
		2.0,
		1.0
	)

	var dir := signf(
		global_position.x - from_position.x
	)

	velocity.x = (
		dir if dir != 0.0 else 1.0
	) * knockback_speed

	if health <= 0:
		die()


# =============================================================================
# DEATH
# =============================================================================

func die() -> void:
	if not alive:
		return

	_set_boss_alive(false)

	died.emit(self)

	GameManager.notify_enemy_died(self)

	GameManager.complete_level()


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
		process_mode = Node.PROCESS_MODE_DISABLED

	# -------------------------------------------------------------------------
	# Disable pillar.
	# -------------------------------------------------------------------------

	pillar.visible = false
	pillar.monitoring = false

	# -------------------------------------------------------------------------
	# Disable sweep telegraph.
	# -------------------------------------------------------------------------

	sweep_telegraph.visible = false
	telegraph_line.visible = false
	telegraph_arrow.visible = false

	# -------------------------------------------------------------------------
	# Disable bullet telegraphs.
	# -------------------------------------------------------------------------

	_hide_bullet_telegraphs()

	# -------------------------------------------------------------------------
	# Destroy bullets.
	# -------------------------------------------------------------------------

	_clear_all_bullets()

	state = State.DEAD


# =============================================================================
# BULLET TELEGRAPHS
# =============================================================================
#
# IMPORTANT:
#
# These Line2D nodes are CHILDREN of the boss.
#
# Therefore:
#
#     line.position = Vector2.ZERO
#
# means the line starts exactly at the boss origin.
#
# The line itself always points RIGHT in local coordinates:
#
#     (0, 0) ----------------> (length, 0)
#
# We rotate the line by the SAME ANGLE used to spawn the bullets.
#
# Therefore:
#
#     telegraph direction == bullet direction
#
# =============================================================================

func _create_bullet_telegraphs() -> void:
	_clear_bullet_telegraphs()

	var total_lines := 0

	# Main ring.
	total_lines += max(bullets_per_burst, 0)

	# Secondary ring.
	if (
		secondary_ring_enabled
		and secondary_bullets_per_burst > 0
	):
		total_lines += secondary_bullets_per_burst

	for i in range(total_lines):
		var line := Line2D.new()

		line.name = "BulletTelegraph_%d" % i

		line.position = Vector2.ZERO

		line.width = bullet_telegraph_width

		line.default_color = Color(
			1.0,
			0.0,
			0.0,
			bullet_telegraph_alpha
		)

		line.z_index = bullet_telegraph_z_index

		line.antialiased = true

		# IMPORTANT:
		#
		# The line ALWAYS points RIGHT locally.
		#
		# Rotation below determines its actual direction.
		line.points = PackedVector2Array([
			Vector2.ZERO,
			Vector2(
				bullet_telegraph_length,
				0.0
			)
		])

		add_child(line)

		_bullet_telegraphs.append(line)

func _update_bullet_telegraphs() -> void:
	var line_index := 0

	# =========================================================================
	# MAIN RING
	# =========================================================================

	if bullets_per_burst > 0:
		var angle_step := TAU / float(bullets_per_burst)

		for i in range(bullets_per_burst):
			var angle := (
				_bullet_pattern_angle
				+ angle_step * float(i)
			)

			_set_bullet_telegraph_angle(
				line_index,
				angle
			)

			line_index += 1

	# =========================================================================
	# SECONDARY RING
	# =========================================================================

	# Only show the secondary telegraphs on the bursts where the actual
	# secondary ring will spawn.
	var next_burst_is_secondary := (
		secondary_ring_enabled
		and secondary_ring_every > 0
		and _bullet_burst_count % secondary_ring_every == 0
	)

	if (
		next_burst_is_secondary
		and secondary_bullets_per_burst > 0
	):
		var secondary_step := (
			TAU / float(secondary_bullets_per_burst)
		)

		var secondary_offset := (
			PI / float(secondary_bullets_per_burst)
		)

		for i in range(secondary_bullets_per_burst):
			var angle := (
				_bullet_pattern_angle
				+ secondary_offset
				+ secondary_step * float(i)
			)

			_set_bullet_telegraph_angle(
				line_index,
				angle
			)

			line_index += 1

	# Hide any unused lines.
	for i in range(line_index, _bullet_telegraphs.size()):
		_bullet_telegraphs[i].visible = false

func _set_bullet_telegraph_angle(
	line_index: int,
	angle: float
) -> void:
	if line_index < 0:
		return

	if line_index >= _bullet_telegraphs.size():
		return

	var line := _bullet_telegraphs[line_index]

	if not is_instance_valid(line):
		return

	# -------------------------------------------------------------------------
	# The line's local geometry is:
	#
	#     (0,0) -----> (length,0)
	#
	# Rotating by `angle` gives:
	#
	#     direction = Vector2.from_angle(angle)
	#
	# which is EXACTLY the direction used by the bullet.
	# -------------------------------------------------------------------------

	line.position = Vector2.ZERO
	line.rotation = angle

	line.visible = true

	line.modulate.a = 1.0


func _hide_bullet_telegraphs() -> void:
	for line in _bullet_telegraphs:
		if is_instance_valid(line):
			line.visible = false


func _clear_bullet_telegraphs() -> void:
	for line in _bullet_telegraphs:
		if is_instance_valid(line):
			line.queue_free()

	_bullet_telegraphs.clear()


# =============================================================================
# ATTACK ARCHITECTURE
# =============================================================================

func _begin_attack_cooldown() -> void:
	state = State.ATTACK_COOLDOWN

	state_time = 0.0

	pillar.visible = false
	pillar.monitoring = false

	sweep_telegraph.visible = false
	telegraph_line.visible = false
	telegraph_arrow.visible = false

	_player_hit_this_sweep = false


func _update_attack_cooldown() -> void:
	if state_time < attack_delay:
		return

	_begin_next_attack()


func _begin_next_attack() -> void:
	match next_attack:
		Attack.SWEEP:
			_begin_sweep_telegraph()

		Attack.BULLET_HELL:
			_begin_sweep_telegraph()


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

	sweep_y = (
		arena_top
		+ arena_bottom
	) * 0.5

	# -------------------------------------------------------------------------
	# Position warning.
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
	# Arrow direction.
	# -------------------------------------------------------------------------

	if _sweep_direction > 0.0:
		telegraph_arrow.rotation = 0.0
	else:
		telegraph_arrow.rotation = PI

	# -------------------------------------------------------------------------
	# Initial appearance.
	# -------------------------------------------------------------------------

	telegraph_arrow.scale = (
		Vector2.ONE
		* arrow_scale_min
	)

	telegraph_line.modulate.a = telegraph_min_alpha
	telegraph_arrow.modulate.a = telegraph_min_alpha

	sweep_telegraph.visible = true
	telegraph_line.visible = true
	telegraph_arrow.visible = true

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

	var pulse_speed := lerpf(
		5.0,
		20.0,
		progress
	)

	var pulse := (
		sin(state_time * pulse_speed)
		+ 1.0
	) * 0.5

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
		Vector2.ONE
		* arrow_scale
	)

	# -------------------------------------------------------------------------
	# Keep warning at edge.
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

	if state_time >= sweep_telegraph_duration:
		_begin_sweep()


# =============================================================================
# SWEEP
# =============================================================================

func _begin_sweep() -> void:
	state = State.SWEEP

	state_time = 0.0

	sweep_telegraph.visible = false
	telegraph_line.visible = false
	telegraph_arrow.visible = false
	pillar.visible = true
	pillar.monitoring = true
	pillar.modulate.a = 1.0

	pillar_animation.modulate.a = 1.0
	pillar_animation.play("default")

	pillar.global_position = Vector2(
		sweep_start_x,
		sweep_y
	)

	_player_hit_this_sweep = false
	
	laser_sound.play()


func _update_sweep() -> void:
	var progress := clampf(
		state_time / sweep_duration,
		0.0,
		1.0
	)

	pillar.global_position = Vector2(
		lerpf(
			sweep_start_x,
			sweep_end_x,
			progress
		),
		sweep_y
	)

	_check_pillar_damage(true)

	if progress >= 1.0:
		_end_sweep()


func _end_sweep() -> void:
	pillar.visible = false
	pillar.monitoring = false

	_player_hit_this_sweep = false

	_sweep_direction *= -1.0

	_begin_attack_recovery()


# =============================================================================
# PILLAR DAMAGE
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

func _update_bullet_hell(delta: float) -> void:
	_bullet_spawn_timer -= delta

	while _bullet_spawn_timer <= 0.0:
		_spawn_bullet_burst()

		_bullet_spawn_timer += bullet_spawn_interval

	_update_bullets(delta)


# =============================================================================
# BULLET BURST
# =============================================================================

func _spawn_bullet_burst() -> void:
	# -------------------------------------------------------------------------
	# The CURRENT telegraphs describe this burst.
	#
	# Hide them while the bullets are actually released.
	# -------------------------------------------------------------------------

	_hide_bullet_telegraphs()

	var burst_center := global_position

	# =========================================================================
	# MAIN RING
	# =========================================================================

	if bullets_per_burst > 0:
		var angle_step := TAU / float(bullets_per_burst)

		for i in range(bullets_per_burst):
			var angle := (
				_bullet_pattern_angle
				+ angle_step * float(i)
			)

			# IMPORTANT:
			#
			# If jitter is used, the telegraph cannot know the exact direction
			# unless that random value is stored ahead of time.
			#
			# Therefore the recommended value is:
			#
			#     bullet_angle_jitter = 0
			#
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
			
			bullet_sound.play()

	# =========================================================================
	# SECONDARY RING
	# =========================================================================

	if (
		secondary_ring_enabled
		and secondary_ring_every > 0
		and _bullet_burst_count % secondary_ring_every == 0
		and secondary_bullets_per_burst > 0
	):
		var secondary_step := (
			TAU / float(secondary_bullets_per_burst)
		)

		var secondary_offset := (
			PI / float(secondary_bullets_per_burst)
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
			
			bullet_sound.play()

	# =========================================================================
	# PREPARE NEXT PATTERN
	# =========================================================================

	_bullet_pattern_angle += deg_to_rad(
		bullet_pattern_rotation
	)

	_bullet_burst_count += 1

	# -------------------------------------------------------------------------
	# Show telegraphs for the NEXT burst.
	# -------------------------------------------------------------------------

	_update_bullet_telegraphs()


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

	# -------------------------------------------------------------------------
	# Visual
	# -------------------------------------------------------------------------

	var visual := Polygon2D.new()

	visual.polygon = PackedVector2Array([
		Vector2(0, -bullet_radius),
		Vector2(bullet_radius, 0),
		Vector2(0, bullet_radius),
		Vector2(-bullet_radius, 0),
	])

	bullet.add_child(visual)

	# -------------------------------------------------------------------------
	# Collision
	# -------------------------------------------------------------------------

	var collision := CollisionShape2D.new()

	var circle := CircleShape2D.new()

	circle.radius = bullet_radius

	collision.shape = circle

	bullet.add_child(collision)

	# -------------------------------------------------------------------------
	# Parent first.
	# -------------------------------------------------------------------------

	add_child(bullet)

	# Then assign global position.
	bullet.global_position = spawn_position

	# -------------------------------------------------------------------------
	# Store bullet.
	# -------------------------------------------------------------------------

	_bullets.append({
		"node": bullet,
		"velocity": bullet_velocity,
	})


# =============================================================================
# UPDATE BULLETS
# =============================================================================

func _update_bullets(delta: float) -> void:
	var player := GameManager.player as Player

	for i in range(
		_bullets.size() - 1,
		-1,
		-1
	):
		var bullet_data: Dictionary = _bullets[i]

		var bullet: Area2D = bullet_data["node"]

		var velocity: Vector2 = bullet_data["velocity"]

		if not is_instance_valid(bullet):
			_bullets.remove_at(i)
			continue

		# ---------------------------------------------------------------------
		# Move.
		# ---------------------------------------------------------------------

		bullet.global_position += (
			velocity * delta
		)

		# ---------------------------------------------------------------------
		# Rotate diamond toward movement direction.
		# ---------------------------------------------------------------------

		bullet.rotation = velocity.angle()

		# ---------------------------------------------------------------------
		# Player collision.
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
		# Remove outside arena.
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
	if index < 0:
		return

	if index >= _bullets.size():
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
# BOSS POSITION / FADE
# =============================================================================

func _update_boss_position(delta: float) -> void:

	if _boss_fading:
		_boss_fade_time += delta

		var progress := clampf(
			_boss_fade_time / boss_fade_duration,
			0.0,
			1.0
		)

		if _boss_fade_out:

			modulate.a = 1.0 - progress

			if progress >= 1.0:
				_move_to_next_boss_position()

		else:

			modulate.a = progress

			if progress >= 1.0:
				_boss_fading = false

				_boss_position_timer = (
					boss_position_duration
				)

		return

	# -------------------------------------------------------------------------
	# Boss is visible.
	# -------------------------------------------------------------------------

	_boss_position_timer -= delta

	if _boss_position_timer <= 0.0:
		_begin_boss_fade_out()


func _begin_boss_fade_out() -> void:
	_boss_fading = true

	_boss_fade_out = true

	_boss_fade_time = 0.0


func _move_to_next_boss_position() -> void:
	var previous_index := _boss_position_index

	while _boss_position_index == previous_index:
		_boss_position_index = randi_range(
			0,
			2
		)

	global_position = _get_boss_position(
		_boss_position_index
	)

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
