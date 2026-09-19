extends Node
## Parry time stop: every enemy and projectile freezes for a moment (real
## time) while the player keeps moving, and the screen stays negative.
##
## Frozen nodes get process_mode DISABLED. Enemies keep their physics body
## (DISABLE_MODE_KEEP_ACTIVE) so the player can still slash them; projectiles
## are pulled out of physics so they can't hit anyone. The player ignores
## contact damage while a stop is active.
##
## The timeline keeps running during the stop (the player still uses it), so
## when it ends each frozen enemy gets on_time_stop_ended(frozen_ticks) to
## push its tick stamps forward, as if its own clock had paused too
## (projectiles get it too, for their lifetime).
##
## Recall ends any active stop before it starts rewinding.

signal started
signal ended

const OVERLAY_SOURCE := &"time_stop"

var _active := false
var _end_real_tick := 0
var _start_tick := 0
## Node -> [process_mode, disable_mode] from before the freeze.
var _frozen: Dictionary = {}


func _ready() -> void:
	# After gameplay, so hits landed on frozen enemies this frame show up.
	process_physics_priority = 999
	GameManager.level_started.connect(_on_level_started)


func _physics_process(_delta: float) -> void:
	if not _active:
		return
	if GameManager.real_tick >= _end_real_tick:
		stop()
		return
	# Frozen enemies don't process, but should still flash when slashed.
	for node in _frozen:
		var enemy := node as Enemy
		if is_instance_valid(enemy) and enemy.alive:
			enemy.refresh_visuals()


func is_active() -> bool:
	return _active


func start(seconds: float) -> void:
	if _active or Recall.is_recalling:
		return
	_active = true
	_start_tick = GameManager.timeline_tick
	_end_real_tick = GameManager.real_tick + GameManager.seconds_to_ticks(seconds)
	for node in get_tree().get_nodes_in_group("enemies"):
		if node.alive:
			_freeze(node, CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE)
	for node in get_tree().get_nodes_in_group("projectiles"):
		_freeze(node, CollisionObject2D.DISABLE_MODE_REMOVE)
	RecallOverlay.set_source(OVERLAY_SOURCE, true)
	started.emit()


func stop() -> void:
	if not _active:
		return
	_active = false
	var frozen_ticks := GameManager.timeline_tick - _start_tick
	for node: Node in _frozen:
		if not is_instance_valid(node):
			continue
		var saved: Array = _frozen[node]
		var enemy := node as Enemy
		# An enemy killed while frozen stays disabled (die() already set that).
		if enemy == null or enemy.alive:
			node.process_mode = saved[0]
		node.disable_mode = saved[1]
		if node.has_method(&"on_time_stop_ended"):
			node.on_time_stop_ended(frozen_ticks)
	_frozen.clear()
	RecallOverlay.set_source(OVERLAY_SOURCE, false)
	ended.emit()


func _freeze(node: CollisionObject2D, disable_mode: CollisionObject2D.DisableMode) -> void:
	_frozen[node] = [node.process_mode, node.disable_mode]
	# Set disable_mode first so enemies never leave the physics world.
	node.disable_mode = disable_mode
	node.process_mode = Node.PROCESS_MODE_DISABLED


func _on_level_started(_level: Level) -> void:
	_active = false
	_frozen.clear()
	RecallOverlay.set_source(OVERLAY_SOURCE, false)
