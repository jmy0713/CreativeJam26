class_name FinalCutscene
extends Node2D
## The ending. Plays once after the final boss dies, then hands the game back
## to the title screen.
##
## Placeholder for now: the soldier finishes his painting, turns around, and
## the screen holds on him for HOLD_SECONDS before the menu comes back. No
## input is read — there is nothing here to interact with yet.
##
## The frame comes from SpriteClock like every other sprite in the game, so
## the clip holds its last frame on its own once it runs out. It counts plain
## `delta` rather than a tick stamp because a cutscene is not a level: there is
## no timeline to rewind, and GameManager's clocks belong to a running level.
## GameOver does the same for the same reason.

## How long the last frame stays up after the animation finishes.
const HOLD_SECONDS := 5.0
const ANIMATION := &"paint"

var _time := 0.0
var _done := false

@onready var soldier: AnimatedSprite2D = $Soldier


func _process(delta: float) -> void:
	if _done:
		return
	_time += delta
	soldier.frame = SpriteClock.frame_at(soldier.sprite_frames, ANIMATION, _time)
	if _time >= SpriteClock.seconds(soldier.sprite_frames, ANIMATION) + HOLD_SECONDS:
		_done = true
		GameManager.return_to_menu()
