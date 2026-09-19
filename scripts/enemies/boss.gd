class_name Boss
extends Walker
## Placeholder boss: a big, tanky walker. Killing it completes the level.
## Replace _behave() with real attack patterns / phases.


func die() -> void:
	super()
	GameManager.complete_level()
