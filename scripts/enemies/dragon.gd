class_name Dragon
extends Enemy
## Big flying enemy. Patrols between the level's high platforms — hovering
## and bobbing gently at each one for a while, then flying on to the next,
## looping back to the first after the last — and, when the player is close,
## spits a Fireball from its mouth down at the floor beneath them. Where it
## lands, a FirePatch lingers for a couple of seconds.
##
## Ignores gravity and world collision (collision_mask should be 0 in the
## scene) — it flies wherever the script tells it to, regardless of platforms.

const NEVER := GameManager.NEVER

## --- Tuning: edit these two directly, no scene/inspector needed -----------

## How far above the reference platform (see central_platform below) the
## dragon is allowed to descend. Raise it to keep the
## dragon higher up; lower it to let it dip further down.
const ALTITUDE_CLEARANCE := 00.0

## Where the dragon patrols, as offsets from its own spawn position
## (Vector2.ZERO would be the spawn point itself). Visited in order,
## looping back to the first after the last. Add, remove, or reposition
## entries here directly — no markers or scene editing needed.
const PATROL_OFFSETS: Array[Vector2] = [
	Vector2(-466.56, 0.00),  # near LedgeA -466.56, 94.88
	Vector2(-231.56, 0.00),  # top of the ramp
	Vector2(-2.56, 0.00),    # near FinalPlatform
]

## Which colour's flight animation Body plays: &"fly_red" or &"fly_gold".
@export var flight_animation := &"fly_red"

@export_group("Flight")
@export var patrol_speed := 70.0
@export var patrol_acceleration := 160.0
## How close counts as "arrived" at a patrol point.
@export var arrival_radius := 1.0
## How long it hovers at each point before moving on to the next.
@export var patrol_dwell_time := 1.0
@export var bob_height := 5.0
@export var bob_speed := 1.2

@export_subgroup("Altitude Floor")
## The platform ALTITUDE_CLEARANCE is measured from. Leave empty to
## auto-pick the one nearest the horizontal middle of the level (the ground
## plane is ignored).
@export var central_platform: NodePath
## Platforms taller than they are wide are treated as walls and ignored when
## looking for platforms.
@export var wall_aspect_ratio := 1.0

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

## Patrol point positions, snapshotted in _ready — see the note there.
var _patrol_points: Array[Vector2] = []
var _target_index := 0
## Lowest y the dragon may ever occupy (smaller y = higher up).
var _altitude_floor_y := INF
var _altitude_floor_ready := false
var _dwell_until_tick := NEVER
var _dwell_base_position := Vector2.ZERO

## The sprite's art sits off-centre in its frame; this nudges it onto the
## hitbox when facing right, mirrored when facing left.
const SPRITE_OFFSET := Vector2(7.5, -11.0)

@onready var glow: ColorRect = $Glow
@onready var sprite: AnimatedSprite2D = $Body


func _ready() -> void:
	super()
	sprite.play(flight_animation)
	for offset in PATROL_OFFSETS:
		_patrol_points.append(global_position + offset)


func _physics_process(delta: float) -> void:
	# Deferred to the first frame: GameManager.current_level is assigned by
	# Level._ready(), which runs after this node's _ready() (children are
	# ready before their parent).
	if not _altitude_floor_ready:
		_init_altitude_floor()

	if is_stunned():
		velocity = velocity.move_toward(Vector2.ZERO, 500.0 * delta)
	else:
		_behave(delta)
		_update_fire_breath()
	move_and_slide()
	if _dwell_until_tick != NEVER:
		# Hover bob is purely cosmetic; drive it directly rather than via
		# velocity, and only while parked at a point (not mid-flight).
		global_position.y = _dwell_base_position.y + sin(_dwell_elapsed() * bob_speed) * bob_height
	# Hard altitude floor, applied after every movement path (patrol, bob,
	# knockback) so nothing can push the dragon down into the level.
	_enforce_altitude_floor()
	_update_visuals()


func _behave(delta: float) -> void:
	if _patrol_points.is_empty():
		velocity = velocity.move_toward(Vector2.ZERO, patrol_acceleration * delta)
		return

	if _dwell_until_tick != NEVER:
		velocity = velocity.move_toward(Vector2.ZERO, patrol_acceleration * delta)
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
		_dwell_until_tick = GameManager.timeline_tick + _ticks(patrol_dwell_time)
		return

	var dir := to_target / dist
	if absf(dir.x) > 0.05:
		direction = 1 if dir.x > 0.0 else -1
	velocity = velocity.move_toward(dir * patrol_speed, patrol_acceleration * delta)


func is_winding_up() -> bool:
	return fire_start_tick != NEVER


func on_recall_finished() -> void:
	super()
	var now := GameManager.timeline_tick
	if fire_start_tick > now:
		fire_start_tick = NEVER
	if last_fire_tick > now:
		last_fire_tick = NEVER
	if _dwell_until_tick != NEVER and _dwell_until_tick > now:
		_dwell_until_tick = now + _ticks(patrol_dwell_time)


func on_time_stop_ended(frozen_ticks: int) -> void:
	super(frozen_ticks)
	fire_start_tick = _shift_stamp(fire_start_tick, frozen_ticks)
	last_fire_tick = _shift_stamp(last_fire_tick, frozen_ticks)
	if _dwell_until_tick != NEVER:
		_dwell_until_tick = _shift_stamp(_dwell_until_tick, frozen_ticks)


# --- Altitude floor ------------------------------------------------------

func _init_altitude_floor() -> void:
	var reference_top := _central_platform_top_y()
	if is_inf(reference_top):
		# No platforms found yet — leave _altitude_floor_ready false so this
		# retries next frame instead of silently disabling the floor forever.
		return
	_altitude_floor_ready = true

	# Smaller y is higher up, so the limit sits *above* the platform top.
	_altitude_floor_y = reference_top - ALTITUDE_CLEARANCE
	# A patrol point parked below the limit would fight the clamp forever.
	for i in _patrol_points.size():
		_patrol_points[i] = _clamp_altitude(_patrol_points[i])
	global_position = _clamp_altitude(global_position)
	_dwell_base_position = _clamp_altitude(_dwell_base_position)


## Top edge y of the platform the altitude floor is measured from: the one
## set in central_platform, or else the one nearest the horizontal middle of
## the level's platforms.
func _central_platform_top_y() -> float:
	if not central_platform.is_empty():
		var chosen := get_node_or_null(central_platform) as Platform
		if chosen:
			return chosen.global_position.y - _platform_extent(chosen).y * 0.5

	var platforms := _standable_platforms()
	if platforms.is_empty():
		return INF

	# The ground plane spans the whole level and would drag the midpoint
	# down to itself; the widest platform is that ground, so drop it.
	if platforms.size() > 1:
		var widest: Platform = platforms[0]
		for platform in platforms:
			if _platform_extent(platform).x > _platform_extent(widest).x:
				widest = platform
		platforms.erase(widest)

	var min_x := INF
	var max_x := -INF
	for platform in platforms:
		min_x = minf(min_x, platform.global_position.x)
		max_x = maxf(max_x, platform.global_position.x)
	var middle_x := (min_x + max_x) * 0.5

	var best: Platform = platforms[0]
	for platform in platforms:
		if absf(platform.global_position.x - middle_x) < absf(best.global_position.x - middle_x):
			best = platform
	return best.global_position.y - _platform_extent(best).y * 0.5


## Every Platform in the level the player could stand on (walls excluded).
## Walks the tree with an `is Platform` test rather than find_children()'s
## string type match, which silently returns nothing if it fails to resolve.
func _standable_platforms() -> Array[Platform]:
	var found: Array[Platform] = []
	_collect_platforms(_level_root(), found)
	return found


func _collect_platforms(node: Node, into: Array[Platform]) -> void:
	var platform := node as Platform
	if platform:
		var extent := _platform_extent(platform)
		# Walls are tall and narrow; they aren't somewhere the player stands.
		if extent.x > 0.0 and extent.y <= extent.x * wall_aspect_ratio:
			into.append(platform)
	for child in node.get_children():
		_collect_platforms(child, into)


## Real size on screen — level scenes scale some platforms.
func _platform_extent(platform: Platform) -> Vector2:
	return platform.size * platform.global_scale.abs()


func _clamp_altitude(point: Vector2) -> Vector2:
	return Vector2(point.x, minf(point.y, _altitude_floor_y))


func _enforce_altitude_floor() -> void:
	if global_position.y > _altitude_floor_y:
		global_position.y = _altitude_floor_y
		velocity.y = minf(velocity.y, 0.0)


func _level_root() -> Node:
	var level := GameManager.current_level
	return level if level != null else get_tree().current_scene


# --- Internals ----------------------------------------------------------

## Seconds spent hovering at the current point, so the bob starts from its
## rest position on arrival instead of snapping to a mid-swing offset.
## Derived from _dwell_until_tick, which time stops already shift.
func _dwell_elapsed() -> float:
	var remaining := _dwell_until_tick - GameManager.timeline_tick
	return GameManager.ticks_to_seconds(_ticks(patrol_dwell_time) - remaining)


func _update_fire_breath() -> void:
	var player := GameManager.player
	if player == null or player.health <= 0 or not alive:
		fire_start_tick = NEVER
		return

	if fire_start_tick == NEVER:
		var dist := global_position.distance_to(player.global_position)
		if dist <= fire_range and GameManager.ticks_since(last_fire_tick) >= _ticks(fire_interval):
			fire_start_tick = GameManager.timeline_tick
	elif GameManager.ticks_since(fire_start_tick) >= _ticks(fire_windup):
		_breathe_fire(player)
		last_fire_tick = GameManager.timeline_tick
		fire_start_tick = NEVER


## Spits a Fireball from the mouth at the floor beneath the player; the
## FirePatch appears where it lands (see _on_fireball_landed).
func _breathe_fire(player: Player) -> void:
	if fireball_scene == null:
		return
	var mouth := glow.global_position
	var target_x := player.global_position.x
	var target := Vector2(target_x, _find_floor_y(target_x, minf(global_position.y, player.global_position.y)))
	var landing := _first_floor_hit(mouth, target)
	var fireball := fireball_scene.instantiate() as Fireball
	if fireball == null:
		return
	get_parent().add_child(fireball)
	fireball.speed = fireball_speed
	fireball.landed.connect(_on_fireball_landed)
	fireball.launch_to_ground(mouth, landing)


func _on_fireball_landed(at: Vector2) -> void:
	if fire_patch_scene == null or not is_inside_tree():
		return
	var patch := fire_patch_scene.instantiate() as FirePatch
	if patch == null:
		return
	get_parent().add_child(patch)
	patch.damage = fire_patch_damage
	patch.global_position = at


## Where a straight shot from `from` to `to` first lands on top of something
## (e.g. a platform in the way); side hits on walls are flown through.
func _first_floor_hit(from: Vector2, to: Vector2) -> Vector2:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = 1
	var result := space_state.intersect_ray(query)
	if result and result.normal.y < -0.5:
		return result.position
	return to


## Casts straight down from (x, from_y) to find the floor beneath a point,
## so the fire lands on solid ground instead of mid-air or inside a wall.
func _find_floor_y(x: float, from_y: float) -> float:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(Vector2(x, from_y), Vector2(x, from_y + 1200.0))
	query.collision_mask = 1
	var result := space_state.intersect_ray(query)
	if result:
		return result.position.y
	return from_y + 200.0


func _update_visuals() -> void:
	super()
	# The sheet's flight row faces right; mirror it when flying left.
	sprite.flip_h = direction < 0
	sprite.position = Vector2(SPRITE_OFFSET.x * direction, SPRITE_OFFSET.y)
	if glow:
		glow.visible = is_winding_up()
		glow.position.x = 54.0 * direction


func _ticks(seconds: float) -> int:
	return GameManager.seconds_to_ticks(seconds)
