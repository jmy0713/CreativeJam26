class_name DJ
extends Enemy
## Disco boss: holds his ground behind the decks, throws spinning Vinyl
## projectiles at the player, and keeps a pair of Backup Dancers in
## rotation — one spawns, then a second later another spawns, and the
## whole cycle repeats every dancer_cycle_interval seconds. Each spawn
## lands on one of the arena's dancer_spawn_points (its platforms) at a
## time, rather than always beside the DJ.

const NEVER := GameManager.NEVER

@export_group("Vinyl Throw")
@export var vinyl_scene: PackedScene
@export var throw_range := 233.4
@export var throw_interval := 2.6
@export var throw_windup := 0.5
@export var vinyl_speed := 177.8
@export var vinyl_damage := 1

@export_group("Backup Dancers")
@export var backup_dancer_scene: PackedScene
## Marker2D nodes (children of the DJ, one per arena platform) a dancer can
## land on. Each spawn picks one at random, never the same one twice in a row.
@export var dancer_spawn_points: Array[NodePath] = []
## Time from the start of one spawn cycle to the start of the next.
@export var dancer_cycle_interval := 5.0
## How long after the first dancer the second spawns, within a cycle.
@export var dancer_spawn_stagger := 1.0

var facing := 1
var throw_start_tick := NEVER
var last_throw_tick := NEVER

var _next_first_spawn_tick := NEVER
var _next_second_spawn_tick := NEVER
var _spawn_points: Array[Node2D] = []
var _last_spawn_point_index := -1
## timeline_tick when the current recall began, so the spawn schedule can be
## shifted back by however far the rewind went.
var _pre_recall_tick := 0

@onready var deck_glow: ColorRect = $DeckGlow


func _ready() -> void:
	super()
	for spawn_path in dancer_spawn_points:
		var point := get_node_or_null(spawn_path) as Node2D
		if point:
			_spawn_points.append(point)
	var now := GameManager.timeline_tick
	_next_first_spawn_tick = now
	_next_second_spawn_tick = now + _ticks(dancer_spawn_stagger)
	Recall.recall_started.connect(_on_recall_started)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)

	if is_stunned():
		velocity.x = move_toward(velocity.x, 0.0, 833.4 * delta)
	else:
		_behave(delta)
		_update_vinyl_throw()
		_update_dancer_spawns()

	move_and_slide()
	_update_visuals()


func _behave(delta: float) -> void:
	var player := GameManager.player
	if player:
		facing = 1 if player.global_position.x >= global_position.x else -1
	# The DJ holds his ground behind the decks.
	velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)


func is_winding_up_throw() -> bool:
	return throw_start_tick != NEVER


func on_recall_finished() -> void:
	super()
	var now := GameManager.timeline_tick
	if throw_start_tick > now:
		throw_start_tick = NEVER
	if last_throw_tick > now:
		last_throw_tick = NEVER
	# Dancer spawns aren't undone by recall, so keep the schedule relative:
	# the next spawn stays the same real wait away instead of stalling until
	# the timeline catches back up.
	var rewound := _pre_recall_tick - now
	_next_first_spawn_tick -= rewound
	_next_second_spawn_tick -= rewound


func _on_recall_started(_target_tick: int) -> void:
	_pre_recall_tick = GameManager.timeline_tick


# --- Internals ----------------------------------------------------------

func _update_vinyl_throw() -> void:
	var player := GameManager.player
	if player == null or player.health <= 0 or not alive:
		throw_start_tick = NEVER
		return

	if throw_start_tick == NEVER:
		var dist := global_position.distance_to(player.global_position)
		if dist <= throw_range and GameManager.ticks_since(last_throw_tick) >= _ticks(throw_interval):
			throw_start_tick = GameManager.timeline_tick
	elif GameManager.ticks_since(throw_start_tick) >= _ticks(throw_windup):
		_throw_vinyl(player)
		last_throw_tick = GameManager.timeline_tick
		throw_start_tick = NEVER


func _throw_vinyl(player: Player) -> void:
	if vinyl_scene == null:
		return
	var vinyl := vinyl_scene.instantiate() as Vinyl
	if vinyl == null:
		return
	get_parent().add_child(vinyl)
	vinyl.speed = vinyl_speed
	vinyl.damage = vinyl_damage
	vinyl.launch(global_position, player.global_position)


## First dancer spawns at the start of each cycle; the second follows
## dancer_spawn_stagger seconds later. Both then wait dancer_cycle_interval
## seconds for the next cycle.
func _update_dancer_spawns() -> void:
	if not alive:
		return
	var now := GameManager.timeline_tick
	if now >= _next_first_spawn_tick:
		_spawn_dancer()
		_next_first_spawn_tick += _ticks(dancer_cycle_interval)
	if now >= _next_second_spawn_tick:
		_spawn_dancer()
		_next_second_spawn_tick += _ticks(dancer_cycle_interval)


func _spawn_dancer() -> void:
	if backup_dancer_scene == null:
		return
	var point := _pick_spawn_point()
	if point == null:
		return
	GameManager.spawn_enemy(backup_dancer_scene, point.global_position)


## Picks one spawn point at a time — never the same platform twice in a row
## (when there's a choice), so dancers spread across the arena over time.
func _pick_spawn_point() -> Node2D:
	if _spawn_points.is_empty():
		return null
	if _spawn_points.size() == 1:
		return _spawn_points[0]
	var index := randi() % _spawn_points.size()
	if index == _last_spawn_point_index:
		index = (index + 1) % _spawn_points.size()
	_last_spawn_point_index = index
	return _spawn_points[index]


func _update_visuals() -> void:
	super()
	if deck_glow:
		deck_glow.visible = is_winding_up_throw()
		deck_glow.position.x = 14.4 * facing


func _ticks(seconds: float) -> int:
	return GameManager.seconds_to_ticks(seconds)
