extends Node
## Global game state: the tick clock, level flow, and registries of the
## player and enemies in the current level.
##
## TIME
## Gameplay code should never keep its own float timers. Instead, store the
## tick at which something happened and compare against the clock:
##     attack_tick = GameManager.timeline_tick
##     if GameManager.ticks_since(attack_tick) < GameManager.seconds_to_ticks(0.3): ...
##
## Two clocks, both advanced once per physics frame:
## - real_tick: never rewinds, never resets. Use for UI, run timers, stats.
## - timeline_tick: resets to 0 at level start and is what gameplay uses.
##   Recall runs this clock backwards.
##
## RECALL
## See recall.gd. Recall rewinds timeline_tick along with the world, so any
## stamp greater than timeline_tick after a recall is "from the future" —
## recordables clear those in on_recall_finished(). Dead enemies are never
## freed so recall can revive them.

signal level_started(level: Level)
signal level_completed(level_index: int)
signal game_completed
signal player_died
signal enemy_died(enemy: Enemy)

const LEVELS: Array[String] = [
	"res://scenes/levels/level_1.tscn",
	"res://scenes/levels/level_2.tscn",
	"res://scenes/levels/level_3.tscn",
	"res://scenes/levels/level_4.tscn",
	"res://scenes/levels/boss_level.tscn",
]

## Stamp value meaning "this never happened". Far enough in the past that any
## "ticks_since(NEVER) < duration" check is false.
const NEVER := -1_000_000_000

## Spawned where the player splits off from during every recall.
const ECHO_SCENE_PATH := "res://scenes/enemies/echo.tscn"
## Dropped by the strongest enemy in a level; collecting it unlocks the exit.
const KEY_SCENE_PATH := "res://scenes/key.tscn"

var real_tick := 0
var timeline_tick := 0

var current_level: Level
var current_level_index := -1
var player: Player
var enemies: Array[Enemy] = []

## The most powerful enemy (highest max_health) present when the level
## started. Killing it drops a key; null if the level has no enemies.
var key_enemy: Enemy
var key_collected := false

## Debug cheats: I toggles invincibility, N skips to the next level.
var cheat_invincible := false

var _transitioning := false


func _ready() -> void:
	# Advance the clock before any other node's _physics_process this frame.
	process_physics_priority = -1000


func _physics_process(_delta: float) -> void:
	real_tick += 1
	# While recalling, Recall drives timeline_tick backwards instead.
	if not Recall.is_recalling:
		timeline_tick += 1


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cheat_invincible"):
		cheat_invincible = not cheat_invincible
	elif event.is_action_pressed("cheat_skip_level") and is_instance_valid(current_level):
		complete_level()


# --- Time helpers -----------------------------------------------------------

func ticks_per_second() -> int:
	return Engine.physics_ticks_per_second


func seconds_to_ticks(seconds: float) -> int:
	return roundi(seconds * ticks_per_second())


func ticks_to_seconds(ticks: int) -> float:
	return float(ticks) / ticks_per_second()


## Timeline ticks elapsed since `tick`.
func ticks_since(tick: int) -> int:
	return timeline_tick - tick


func seconds_since(tick: int) -> float:
	return ticks_to_seconds(ticks_since(tick))


func level_time_seconds() -> float:
	return ticks_to_seconds(timeline_tick)


# --- Registration -----------------------------------------------------------

## Called by Level._ready(). Children are ready before their parent, so the
## player and enemies have already joined their groups at this point.
func register_level(level: Level) -> void:
	current_level = level
	current_level_index = LEVELS.find(level.scene_file_path)
	timeline_tick = 0
	_transitioning = false

	player = null
	for node in get_tree().get_nodes_in_group("player"):
		if level.is_ancestor_of(node):
			player = node
			player.died.connect(_on_player_died)
			player.recall_split.connect(_on_player_recall_split)
			break

	enemies.clear()
	for node in get_tree().get_nodes_in_group("enemies"):
		if level.is_ancestor_of(node):
			enemies.append(node)

	key_collected = false
	key_enemy = null
	var best_health := -1
	for enemy in enemies:
		if enemy.max_health > best_health:
			best_health = enemy.max_health
			key_enemy = enemy

	level_started.emit(level)


## Add an enemy to the current level at runtime. The spawn itself is NOT
## undone by recall — the enemy stays even when rewinding past its spawn —
## but after spawning it records samples/damage/death like any enemy.
func spawn_enemy(scene: PackedScene, at: Vector2) -> Enemy:
	var enemy: Enemy = scene.instantiate()
	var parent := current_level.get_node_or_null("Enemies")
	(parent if parent else current_level).add_child(enemy, true)
	enemy.global_position = at
	enemies.append(enemy)
	Recall.track(enemy)
	return enemy


func alive_enemies() -> Array[Enemy]:
	return enemies.filter(func(e: Enemy) -> bool: return e.alive)


# --- Key / level exit ---------------------------------------------------

## Called by Enemy.die() when the enemy that died is this level's key_enemy.
func drop_key(at: Vector2) -> void:
	var scene: PackedScene = load(KEY_SCENE_PATH)
	if scene == null or current_level == null:
		return
	var key: Node2D = scene.instantiate()
	var parent := current_level.get_node_or_null("Enemies")
	(parent if parent else current_level).add_child(key, true)
	key.global_position = at


func collect_key() -> void:
	key_collected = true


## True once the key has been collected, or immediately if the level never
## had an enemy to drop one (so untouched levels still work as before).
func is_level_unlocked() -> bool:
	return key_enemy == null or key_collected


# --- Events -----------------------------------------------------------------

func notify_enemy_died(enemy: Enemy) -> void:
	enemy_died.emit(enemy)


func _on_player_recall_split(from_position: Vector2, to_position: Vector2) -> void:
	var echo := spawn_enemy(load(ECHO_SCENE_PATH), from_position) as Walker
	echo.direction = 1 if to_position.x > from_position.x else -1


func _on_player_died() -> void:
	player_died.emit()
	restart_level()


# --- Level flow -------------------------------------------------------------

func complete_level() -> void:
	if _transitioning:
		return
	level_completed.emit(current_level_index)
	var next := current_level_index + 1
	if next < LEVELS.size():
		load_level(next)
	else:
		game_completed.emit()
		load_level(0)


func load_level(index: int) -> void:
	_transitioning = true
	get_tree().change_scene_to_file.call_deferred(LEVELS[index])


func restart_level() -> void:
	if _transitioning:
		return
	_transitioning = true
	get_tree().reload_current_scene.call_deferred()
