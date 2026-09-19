extends Node
## Recall: rewinds the level by undoing events from a per-level undo stack.
##
## RECORDING
## - Samples: every `sample_interval` seconds, each node in the "recordable"
##   group is asked for recall_sample() (e.g. {position, facing}). If it
##   changed since the last sample, a sample event is pushed. Unchanged
##   entities push nothing.
## - Discrete events: gameplay code calls Recall.record(target, kind, undo)
##   for things that aren't captured by samples (damage, deaths, ...).
##
## RECALLING (four phases)
## 1. FREEZE: the level stops for `freeze_seconds`.
## 2. REWIND: events are popped newest-first as the timeline cursor runs back
##    to `now - recall_seconds` (clamped to level start). Sample events are
##    interpolated so positions move smoothly along the recorded path.
## 3. HOLD: a beat of stillness at the end of the rewind, so the slide reads as
##    a separate move instead of running out of the rewind.
## 4. CATCH-UP: nodes with a recall visual (the player's afterimage) move to
##    where their visual ended up.
## Recalling again keeps popping; an empty stack means the level is back at
## its start.
##
## Recordables implement:
##     func recall_sample() -> Dictionary
##     func apply_recall_sample(sample: Dictionary) -> void
##     func on_recall_finished() -> void   # clear state the stack doesn't track
## and optionally, to show an afterimage while the body stays put:
##     func begin_recall_visual() -> void
##     func begin_recall_catchup() -> void          # the body starts moving
##     func set_recall_catchup(t: float) -> void   # t goes 0 -> 1

signal recall_started(target_tick: int)
signal rewind_started
signal recall_finished
## Emitted for every event popped during a recall — hook rewind VFX here.
signal event_undone(event: Event)

enum Phase { NONE, FREEZE, REWIND, HOLD, CATCHUP }

class Event:
	var tick: int
	var target: Node
	var kind: StringName
	## Discrete events: restores the state from before the event.
	var undo: Callable
	## Sample events: {sample, previous, previous_tick}.
	var data: Dictionary

## A sample event being played back: `node` moves from `from_sample` (at
## from_tick) to `to_sample` (at to_tick) as the cursor runs backwards.
class Segment:
	var node: Node
	var from_sample: Dictionary
	var to_sample: Dictionary
	var from_tick: int
	var to_tick: int

@export var recall_seconds := 5.0
## Real time the rewind takes for a full `recall_seconds` rewind.
@export var playback_seconds := 1.5
## Frozen (screen inverted) for this long before the rewind starts...
@export var freeze_before_seconds := 0.2
## ...and for this long after it ends, before the level resumes.
@export var freeze_after_seconds := 0.2
@export var sample_interval := 0.2
## How long the player takes to slide to the afterimage.
@export var catchup_seconds := 2
## Beat of stillness between the rewind ending and the slide starting.
@export var catchup_pause_seconds := 0.18

const OVERLAY_PATH := "/root/RecallOverlay/CanvasLayer/RecallNegative"
var _negative: ColorRect
var _negative_material: ShaderMaterial
var is_recalling := false

var _stack: Array[Event] = []
var _last_samples: Dictionary = {}  # Node -> Dictionary
var _last_sample_ticks: Dictionary = {}  # Node -> int
var _segments: Dictionary = {}  # Node -> Segment

var _phase := Phase.NONE
var _phase_start_real_tick := 0
var _target_tick := 0
var _rewind_step := 1


func _ready() -> void:
	# Record after gameplay has moved everything this frame.
	process_physics_priority = 1000
	GameManager.level_started.connect(_on_level_started)


func _physics_process(_delta: float) -> void:
	if GameManager.current_level == null:
		return

	match _phase:
		Phase.FREEZE:
			if _real_ticks_in_phase() >= GameManager.seconds_to_ticks(freeze_before_seconds):
				_begin_rewind()

		Phase.REWIND:
			_step_rewind()
		Phase.HOLD:
			if _real_ticks_in_phase() >= GameManager.seconds_to_ticks(catchup_pause_seconds):
				_begin_catchup()
		Phase.CATCHUP:
			_step_catchup()
		Phase.NONE:
			if Input.is_action_just_pressed("recall"):
				start_recall()
			elif GameManager.timeline_tick % GameManager.seconds_to_ticks(sample_interval) == 0:
				_record_samples()
				
				
# --- Public -----------------------------------------------------------------

## Push a discrete event. `undo` must restore the state from before it.
func record(target: Node, kind: StringName, undo: Callable) -> void:
	if is_recalling:
		return
	var event := Event.new()
	event.tick = GameManager.timeline_tick
	event.target = target
	event.kind = kind
	event.undo = undo
	_stack.append(event)


func start_recall() -> void:
	if is_recalling:
		return
	# Capture where things are right now so the rewind starts from the present.
	_record_samples()
	is_recalling = true
	_target_tick = maxi(GameManager.timeline_tick - GameManager.seconds_to_ticks(recall_seconds), 0)
	var playback_ticks := maxi(GameManager.seconds_to_ticks(playback_seconds), 1)
	_rewind_step = maxi(ceili(float(GameManager.seconds_to_ticks(recall_seconds)) / playback_ticks), 1)
	GameManager.current_level.process_mode = Node.PROCESS_MODE_DISABLED
	_set_negative(true)

	_set_phase(Phase.FREEZE)
	recall_started.emit(_target_tick)


## Start tracking a recordable created mid-level (e.g. a spawned enemy) so
## its first sample has a baseline.
func track(node: Node) -> void:
	_last_samples[node] = node.recall_sample()
	_last_sample_ticks[node] = GameManager.timeline_tick


func stack_size() -> int:
	return _stack.size()


## Seconds of history left to rewind through.
func history_seconds() -> float:
	if _stack.is_empty():
		return 0.0
	return GameManager.ticks_to_seconds(GameManager.timeline_tick - _stack[0].tick)


# --- Recording --------------------------------------------------------------

func _on_level_started(_level: Level) -> void:
	_set_negative(false)

	is_recalling = false
	_phase = Phase.NONE
	_stack.clear()
	_segments.clear()
	_last_samples.clear()
	_last_sample_ticks.clear()
	for node in _recordables():
		_last_samples[node] = node.recall_sample()
		_last_sample_ticks[node] = 0


func _record_samples() -> void:
	var now := GameManager.timeline_tick
	for node in _recordables():
		if not node.is_inside_tree() or node.get(&"alive") == false:
			continue
		var sample: Dictionary = node.recall_sample()
		var previous: Dictionary = _last_samples.get(node, sample)
		var previous_tick: int = _last_sample_ticks.get(node, now)
		_last_sample_ticks[node] = now
		if sample == previous:
			continue
		_last_samples[node] = sample
		var event := Event.new()
		event.tick = now
		event.target = node
		event.kind = &"sample"
		event.data = {"sample": sample, "previous": previous, "previous_tick": previous_tick}
		_stack.append(event)


# --- Recalling --------------------------------------------------------------

func _begin_rewind() -> void:
	_set_negative(false)

	_set_phase(Phase.REWIND)
	for node in _recordables():
		if node.has_method(&"begin_recall_visual"):
			node.begin_recall_visual()
	rewind_started.emit()


func _step_rewind() -> void:
	var cursor := maxi(GameManager.timeline_tick - _rewind_step, _target_tick)
	while not _stack.is_empty() and _stack.back().tick > cursor:
		var event: Event = _stack.pop_back()
		if event.kind == &"sample":
			_start_segment(event)
		else:
			event.undo.call()
		event_undone.emit(event)
	GameManager.timeline_tick = cursor
	_update_segments(cursor)

	if cursor <= _target_tick:
		_set_phase(Phase.HOLD)


## The body starts moving: lets recordables react (the player's split spawns
## the echo enemy).
func _begin_catchup() -> void:
	_set_phase(Phase.CATCHUP)
	for node in _recordables():
		if node.has_method(&"begin_recall_catchup"):
			node.begin_recall_catchup()


## Slides every node with a recall visual from where it froze to its afterimage.
func _step_catchup() -> void:
	var catchup_ticks := maxi(GameManager.seconds_to_ticks(catchup_seconds), 1)
	var t := clampf(float(_real_ticks_in_phase()) / catchup_ticks, 0.0, 1.0)
	for node in _recordables():
		if node.has_method(&"set_recall_catchup"):
			node.set_recall_catchup(t)
	if t >= 1.0:
		_finish_recall()


func _start_segment(event: Event) -> void:
	var node := event.target
	if _segments.has(node):
		_end_segment(_segments[node])
	var segment := Segment.new()
	segment.node = node
	segment.from_sample = event.data.sample
	segment.to_sample = event.data.previous
	segment.from_tick = event.tick
	segment.to_tick = event.data.previous_tick
	_segments[node] = segment


func _update_segments(cursor: int) -> void:
	for segment: Segment in _segments.values():
		if cursor <= segment.to_tick:
			_end_segment(segment)
			continue
		var span := maxi(segment.from_tick - segment.to_tick, 1)
		var weight := float(segment.from_tick - cursor) / span
		var sample := segment.to_sample.duplicate()
		if sample.has("position"):
			sample.position = segment.from_sample.position.lerp(segment.to_sample.position, weight)
		segment.node.apply_recall_sample(sample)
		# If the recall ends mid-segment, this interpolated state is the truth.
		_last_samples[segment.node] = sample
		_last_sample_ticks[segment.node] = cursor


func _end_segment(segment: Segment) -> void:
	segment.node.apply_recall_sample(segment.to_sample)
	_last_samples[segment.node] = segment.to_sample
	_last_sample_ticks[segment.node] = segment.to_tick
	_segments.erase(segment.node)


func _finish_recall() -> void:
	_set_negative(false)
	_segments.clear()
	# Nodes tracked mid-rewind (spawned during the recall) got a baseline tick
	# from the moving cursor; clamp it to where the timeline ended up.
	for node in _last_sample_ticks:
		_last_sample_ticks[node] = mini(_last_sample_ticks[node], _target_tick)
	is_recalling = false
	_phase = Phase.NONE
	for node in _recordables():
		node.on_recall_finished()
	GameManager.current_level.process_mode = Node.PROCESS_MODE_INHERIT
	recall_finished.emit()


# --- Helpers ----------------------------------------------------------------


func _set_negative(on: bool) -> void:
	if _negative == null or not is_instance_valid(_negative):
		_negative = get_node_or_null(OVERLAY_PATH) as ColorRect
		if _negative == null:
			push_warning("Recall: %s not found. Is RecallOverlay registered as an autoload?" % OVERLAY_PATH)
			return
		_negative_material = _negative.material as ShaderMaterial
	_negative.visible = on
	if _negative_material:
		_negative_material.set_shader_parameter("intensity", 1.0 if on else 0.0)

func _set_phase(phase: Phase) -> void:
	_phase = phase
	_phase_start_real_tick = GameManager.real_tick


func _real_ticks_in_phase() -> int:
	return GameManager.real_tick - _phase_start_real_tick


func _recordables() -> Array[Node]:
	return get_tree().get_nodes_in_group("recordable")
