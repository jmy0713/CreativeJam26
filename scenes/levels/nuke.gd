extends Sprite2D

@export var image_1: Texture2D
@export var image_2: Texture2D
@export var white_fade: ColorRect

@export var transition_delay := 5.0
@export var fade_duration := 1.0
@export var white_duration := 3.0
@onready var explosion_player: AudioStreamPlayer = $ExplosionPlayer
var explosion_played := false

func _ready() -> void:
	# The level timeline always starts at 0.
	# Do NOT use the current timeline_tick as the start time,
	# because the scene can be initialized after GameManager has
	# already advanced the clock.
	white_fade.modulate.a = 0.0
	texture = image_1

	# Update normally.
	_update_transition()
	# Recall disables the level's process mode, so this node will not
	# receive _physics_process() during the rewind. Listen directly
	# to Recall so we can update the visual state while the timeline
	# is being moved backwards.
	if not Recall.rewind_started.is_connected(_on_rewind_started):
		Recall.rewind_started.connect(_on_rewind_started)

	if not Recall.recall_finished.is_connected(_on_recall_finished):
		Recall.recall_finished.connect(_on_recall_finished)


func _physics_process(_delta: float) -> void:
	_update_transition()


func _on_rewind_started() -> void:
	# Recall has now moved the timeline backwards.
	# Immediately show the state corresponding to the new timeline.
	_update_transition()


func _on_recall_finished() -> void:
	# The final timeline position is now GameManager.timeline_tick.
	# Recalculate one last time so the image/fade exactly matches it.
	_update_transition()


func _update_transition() -> void:
	if white_fade == null:
		return

	# GameManager.timeline_tick is the ONLY clock that matters.
	# Since Recall moves it backwards, this automatically moves the
	# transition backwards too.
	var elapsed := GameManager.ticks_to_seconds(GameManager.timeline_tick)
	var fade_start := transition_delay
	var white_start := fade_start + fade_duration
	var image_change := white_start + white_duration
	var fade_end := image_change + fade_duration

	if elapsed >= white_start and not explosion_played:
		explosion_played = true
		explosion_player.play()
	elif elapsed < white_start:
		explosion_played = false
	# ---------------------------------------------------------
	# 0 -> 5 seconds
	# Image 1, no white overlay
	# ---------------------------------------------------------
	if elapsed < fade_start:
		texture = image_1
		white_fade.modulate.a = 0.0
		return

	# ---------------------------------------------------------
	# 5 -> 6 seconds
	# Fade from image 1 to white
	# ---------------------------------------------------------
	if elapsed < white_start:
		texture = image_1

		var progress := (
			(elapsed - fade_start) / fade_duration
		)

		white_fade.modulate.a = clampf(progress, 0.0, 1.0)
		return

	# ---------------------------------------------------------
	# 6 -> 9 seconds
	# Completely white
	# ---------------------------------------------------------
	if elapsed < image_change:
		texture = image_1
		white_fade.modulate.a = 1.0
		return

	# ---------------------------------------------------------
	# 9 -> 10 seconds
	# Image changes to image 2 while screen is white,
	# then fade back out.
	# ---------------------------------------------------------
	if elapsed < fade_end:
		texture = image_2

		var progress := (
			(elapsed - image_change) / fade_duration
		)

		white_fade.modulate.a = 1.0 - clampf(progress, 0.0, 1.0)
		return

	# ---------------------------------------------------------
	# 10+ seconds
	# Image 2, no white overlay
	# ---------------------------------------------------------
	texture = image_2
	white_fade.modulate.a = 0.0
