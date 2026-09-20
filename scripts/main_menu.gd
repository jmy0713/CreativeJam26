extends Node2D
## Title screen, and the stage the prologue plays on.
##
## The menu's backdrop is the prologue's set (see prologue.gd): the buttons sit
## on the left half of a road that is two screens wide. Play takes the menu off
## screen and starts the cutscene on the spot rather than changing scenes, so
## there is nothing to cut between -- the road stays exactly where it was and
## he walks onto it. The HUD looks after itself: no Level registers here, so it
## is already hidden (hud.gd).
##
## When the cutscene finishes, the run starts the ordinary way, through the
## time warp. "I need to go back" is answered by the loading timeline hunting
## down 1437 AD.


@onready var ui: CanvasLayer = $Ui
@onready var prologue: Prologue = $Prologue


func _ready() -> void:
	prologue.finished.connect(_on_prologue_finished)


func _on_play_pressed() -> void:
	ui.hide()
	prologue.play()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_prologue_finished() -> void:
	GameManager.load_level(0)
