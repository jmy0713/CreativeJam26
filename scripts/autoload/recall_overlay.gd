extends Node2D
## Full-screen colour-inversion overlay (autoload). Several systems can want
## it at once (the recall freeze, the parry time stop), so each one turns its
## own source on/off and the screen stays negative while any source is on.

@onready var _negative: ColorRect = $CanvasLayer/RecallNegative

var _sources: Dictionary = {}  # StringName -> true


func set_source(source: StringName, on: bool) -> void:
	if on:
		_sources[source] = true
	else:
		_sources.erase(source)
	_negative.visible = not _sources.is_empty()
