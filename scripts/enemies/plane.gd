extends Enemy
## Big flying enemy. Patrols between the level's high platforms — hovering
## and bobbing gently at each one for a while, then flying on to the next,
## looping back to the first after the last — and, when the player is close,
## spits a Fireball from its mouth down at the floor beneath them. Where it
## lands, a FirePatch lingers for a couple of seconds.
##
## Ignores gravity and world collision (collision_mask should be 0 in the
## scene) — it flies wherever the script tells it to, regardless of platforms.

## --- Tuning -------------------------------------------------------------

## How far above the reference platform (see central_platform below) the
## dragon is allowed to descend.
const ALTITUDE_CLEARANCE := 00.0

## Where the dragon patrols, as offsets from its own spawn position.
@export var PATROL_OFFSETS: Array[Vector2] = [
	Vector2(-466.56, 0.00),
	Vector2(-231.56, 0.00),
	Vector2(-2.56, 0.00),
]

## Which colour's flight animation Body plays: &"fly_red" or &"fly_gold".
@export var flight_animation := &"fly_red"

@export_group("Flight")
@export var patrol_speed := 70.0
@export var patrol_acceleration := 160.0
@export var arrival_radius := 1.0
@export var patrol_dwell_time := 1.0
@export var bob_height := 5.0
@export var bob_speed := 1.2

@export_subgroup("Altitude Floor")
@export var central_platform: NodePath
@export var wall_aspect_ratio := 1.0

@export_group("Telegraph")
## What shows while the dragon winds up, and where the shot comes from: the
## ember gathering in a dragon's mouth, or the bomb slung under a plane's
## belly. The chosen node *is* the release point — `_breathe_fire()` spawns
## from its global position — so moving it moves where the shot comes from.
@export_enum("Ember", "Bomb") var telegraph := 0
## Offset of that release point from the dragon's origin. The x is mirrored
## with the direction it faces.
@export var telegraph_offset := Vector2(54.0, 0.0)
## How far the telegraph sinks over the windup, for a bomb about to drop.
@export var telegraph_sag := 0.0

@export_group("Fire Breath")
@export var fireball_scene: PackedScene
@export var fireball_speed := 200.0
@export var fire_patch_scene: PackedScene
@export var fire_range := 233.0
@export var fire_interval := 2.5
@export var fire_windup := 0.5
@export var fire_patch_damage := 1

var direction := 1
var fire_start_tick := NEVER
var last_fire_tick := NEVER

var _patrol_points: Array[Vector2] = []
var _target_index := 0
var _altitude_floor_y := INF
var _altitude_floor_ready := false
var _dwell_until_tick := NEVER
var _dwell_base_position := Vector2.ZERO

const SPRITE_OFFSET := Vector2(7.5, -11.0)

## Whichever telegraph this one wears; the other is hidden for good.
@onready var glow: Node2D = _pick_telegraph()
@onready var sprite: AnimatedSprite2D = $Body
@onready var flying_sound: AudioStreamPlayer2D = $FlyingSound


func _ready() -> void:
	super()
	sprite.play(flight_animation)

	for offset in PATROL_OFFSETS:
		_patrol_points.append(global_position + offset)


func _physics_process(delta: float) -> void:
	if not _altitude_floor_ready:
		_init_altitude_floor()

	if is_stunned():
		velocity = velocity.move_toward(Vector2.ZERO, 500.0 * delta)
	else:
		_behave(delta)
		_update_fire_breath()

	move_and_slide()

	if _dwell_until_tick != NEVER:
		global_position.y = _dwell_base_position.y + sin(
			_dwell_elapsed() * bob_speed
		) * bob_height

	_enforce_altitude_floor()
	_update_visuals()
	
	if velocity.length() > 5.0 and not is_stunned():
		if not flying_sound.playing:
			flying_sound.play()
	else:
		flying_sound.stop()


func _behave(delta: float) -> void:
	if _patrol_points.is_empty():
		velocity = velocity.move_toward(
			Vector2.ZERO,
			patrol_acceleration * delta
		)
		return

	if _dwell_until_tick != NEVER:
		velocity = velocity.move_toward(
			Vector2.ZERO,
			patrol_acceleration * delta
		)

		if GameManager.timeline_tick >= _dwell_until_tick:
			_dwell_until_tick = NEVER
			_target_index = (_target_index + 1) % _patrol_points.size()

		return

	var target := _patrol_points[_target_index]
	var to_target := target - global_position
	var dist := to_target.length()

	if dist <= arrival_radius:
		global_position = target
		velocity = Vector2.ZERO
		_dwell_base_position = global_position
		_dwell_until_tick = (
			GameManager.timeline_tick
			+ _ticks(patrol_dwell_time)
		)
		return

	var dir := to_target / dist

	if absf(dir.x) > 0.05:
		direction = 1 if dir.x > 0.0 else -1

	velocity = velocity.move_toward(
		dir * patrol_speed,
		patrol_acceleration * delta
	)


func is_winding_up() -> bool:
	return fire_start_tick != NEVER


func on_recall_finished() -> void:
	super()
	fire_start_tick = _expire_future(fire_start_tick)
	last_fire_tick = _expire_future(last_fire_tick)
	# A dwell that would end in the undone future restarts from here instead
	# of expiring, so the dragon still finishes hovering at its patrol point.
	var now := GameManager.timeline_tick
	if _dwell_until_tick != NEVER and _dwell_until_tick > now:
		_dwell_until_tick = (
			now + _ticks(patrol_dwell_time)
		)


func on_time_stop_ended(frozen_ticks: int) -> void:
	super(frozen_ticks)

	fire_start_tick = _shift_stamp(
		fire_start_tick,
		frozen_ticks
	)

	last_fire_tick = _shift_stamp(
		last_fire_tick,
		frozen_ticks
	)

	if _dwell_until_tick != NEVER:
		_dwell_until_tick = _shift_stamp(
			_dwell_until_tick,
			frozen_ticks
		)


# -------------------------------------------------------------------------
# Altitude floor
# -------------------------------------------------------------------------

func _init_altitude_floor() -> void:
	var reference_top := _central_platform_top_y()

	if is_inf(reference_top):
		return

	_altitude_floor_ready = true

	_altitude_floor_y = (
		reference_top - ALTITUDE_CLEARANCE
	)

	for i in _patrol_points.size():
		_patrol_points[i] = _clamp_altitude(
			_patrol_points[i]
		)

	global_position = _clamp_altitude(global_position)
	_dwell_base_position = _clamp_altitude(
		_dwell_base_position
	)


func _central_platform_top_y() -> float:
	if not central_platform.is_empty():
		var chosen := get_node_or_null(
			central_platform
		) as Platform

		if chosen:
			return (
				chosen.global_position.y
				- _platform_extent(chosen).y * 0.5
			)

	var platforms := _standable_platforms()

	if platforms.is_empty():
		return INF

	if platforms.size() > 1:
		var widest: Platform = platforms[0]

		for platform in platforms:
			if _platform_extent(platform).x > _platform_extent(widest).x:
				widest = platform

		platforms.erase(widest)

	var min_x := INF
	var max_x := -INF

	for platform in platforms:
		min_x = minf(
			min_x,
			platform.global_position.x
		)

		max_x = maxf(
			max_x,
			platform.global_position.x
		)

	var middle_x := (min_x + max_x) * 0.5

	var best: Platform = platforms[0]

	for platform in platforms:
		if absf(
			platform.global_position.x - middle_x
		) < absf(
			best.global_position.x - middle_x
		):
			best = platform

	return (
		best.global_position.y
		- _platform_extent(best).y * 0.5
	)


func _standable_platforms() -> Array[Platform]:
	var found: Array[Platform] = []
	_collect_platforms(_level_root(), found)
	return found


func _collect_platforms(
	node: Node,
	into: Array[Platform]
) -> void:
	var platform := node as Platform

	if platform:
		var extent := _platform_extent(platform)

		if (
			extent.x > 0.0
			and extent.y <= extent.x * wall_aspect_ratio
		):
			into.append(platform)

	for child in node.get_children():
		_collect_platforms(child, into)


func _platform_extent(platform: Platform) -> Vector2:
	return platform.size * platform.global_scale.abs()


func _clamp_altitude(point: Vector2) -> Vector2:
	return Vector2(
		point.x,
		minf(point.y, _altitude_floor_y)
	)


func _enforce_altitude_floor() -> void:
	if global_position.y > _altitude_floor_y:
		global_position.y = _altitude_floor_y
		velocity.y = minf(velocity.y, 0.0)


func _level_root() -> Node:
	var level := GameManager.current_level

	if level != null:
		return level

	return get_tree().current_scene


# -------------------------------------------------------------------------
# Internals
# -------------------------------------------------------------------------

func _dwell_elapsed() -> float:
	var remaining := (
		_dwell_until_tick
		- GameManager.timeline_tick
	)

	return GameManager.ticks_to_seconds(
		_ticks(patrol_dwell_time) - remaining
	)


func _update_fire_breath() -> void:
	var player := GameManager.player

	if (
		player == null
		or player.health <= 0
		or not alive
	):
		fire_start_tick = NEVER
		return

	if fire_start_tick == NEVER:
		var dist := global_position.distance_to(
			player.global_position
		)

		if (
			dist <= fire_range
			and GameManager.ticks_since(last_fire_tick)
				>= _ticks(fire_interval)
		):
			fire_start_tick = GameManager.timeline_tick

	elif (
		GameManager.ticks_since(fire_start_tick)
		>= _ticks(fire_windup)
	):
		_breathe_fire(player)

		last_fire_tick = GameManager.timeline_tick
		fire_start_tick = NEVER


## Spits a Fireball from the mouth toward the player's X position.
## The fireball tries to land on the floor beneath the player, but walls
## between the dragon and the landing point block the shot.
func _breathe_fire(player: Player) -> void:
	if fireball_scene == null:
		return

	var mouth := glow.global_position
	var target_x := player.global_position.x

	# IMPORTANT:
	# Always search downward starting from the dragon's mouth.
	# This works even when the player is above the dragon.
	var target_y := _find_floor_y(
		target_x,
		mouth.y
	)

	var target := Vector2(
		target_x,
		target_y
	)

	# Find the first world collision between the dragon and the target.
	# This includes walls AND floors.
	var landing := _first_floor_hit(
		mouth,
		target
	)

	var fireball := fireball_scene.instantiate() as Fireball

	if fireball == null:
		return

	get_parent().add_child(fireball)

	fireball.speed = fireball_speed
	fireball.landed.connect(_on_fireball_landed)

	fireball.launch_to_ground(
		mouth,
		landing
	)


func _on_fireball_landed(at: Vector2) -> void:
	if (
		fire_patch_scene == null
		or not is_inside_tree()
	):
		return

	var patch := fire_patch_scene.instantiate() as FirePatch

	if patch == null:
		return

	get_parent().add_child(patch)

	patch.damage = fire_patch_damage
	patch.global_position = at


## Returns the first world collision between the dragon and the target.
##
## Unlike the old version, this does NOT ignore walls. Any collision on
## collision layer 1 stops the projectile.
func _first_floor_hit(
	from: Vector2,
	to: Vector2
) -> Vector2:
	var space_state := get_world_2d().direct_space_state

	var query := PhysicsRayQueryParameters2D.create(
		from,
		to
	)

	query.collision_mask = 1

	var result := space_state.intersect_ray(query)

	if result:
		return result.position

	return to


## Casts straight down from the dragon's height at the player's X position.
## This finds the first world surface underneath the player.
func _find_floor_y(
	x: float,
	from_y: float
) -> float:
	var space_state := get_world_2d().direct_space_state

	var query := PhysicsRayQueryParameters2D.create(
		Vector2(x, from_y),
		Vector2(x, from_y + 1200.0)
	)

	query.collision_mask = 1

	var result := space_state.intersect_ray(query)

	if result:
		return result.position.y

	return from_y + 200.0


## Picks the telegraph this dragon wears and puts the other one away.
func _pick_telegraph() -> Node2D:
	var ember := $Glow as Node2D
	var bomb := $BombGlow as Node2D
	var chosen := bomb if telegraph == 1 else ember

	for node in [ember, bomb]:
		if node != chosen:
			node.visible = false

	return chosen


## Runs the telegraph out over the windup. The two wear different scripts, so
## each is asked for what it understands rather than being told.
func _pose_telegraph() -> void:
	if glow == null:
		return

	glow.visible = is_winding_up()

	var charge := 0.0

	if glow.visible:
		charge = clampf(
			GameManager.seconds_since(fire_start_tick)
			/ maxf(fire_windup, 0.001),
			0.0,
			1.0
		)

	glow.position = Vector2(
		telegraph_offset.x * direction,
		telegraph_offset.y + telegraph_sag * charge
	)

	if glow.has_method(&"set_charge"):
		glow.set_charge(charge)
	elif glow.has_method(&"set_angle"):
		# A bomb hangs nose-down, already pointing the way it will fall.
		glow.set_angle(PI * 0.5)


func _update_visuals() -> void:
	super()

	sprite.flip_h = direction < 0

	sprite.position = Vector2(
		SPRITE_OFFSET.x * direction,
		SPRITE_OFFSET.y
	)

	_pose_telegraph()
