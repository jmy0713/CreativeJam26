extends Node

var _t := 0.0

func _process(delta: float) -> void:
	_t += delta
	if GameManager.has_active_level():
		print("HANDOFF OK  level=%s index=%d" % [GameManager.current_level.level_name, GameManager.current_level_index])
		get_tree().quit()
	elif _t > 20.0:
		print("HANDOFF TIMEOUT  transition_active=%s" % SceneTransition.is_active())
		get_tree().quit()
