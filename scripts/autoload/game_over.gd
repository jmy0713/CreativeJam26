extends CanvasLayer
## Game over screen (autoload).
##
## The player's last HP is gone, GameManager.game_over() calls play(), and
## this holds a card on screen for HOLD_SECONDS before handing the game back
## to the title screen. That's the whole thing — no menu, no retry prompt: a
## run ends where it started.
##
## Like SceneTransition, the card is built here in code rather than in a
## scene, the tree is paused underneath it, and this layer keeps processing
## (PROCESS_MODE_ALWAYS) so it can run out its own clock while everything
## else is frozen. It sits above the HUD and below the time warp — a warp and
## a death can't both be running, but if they ever were, the warp owns the
## screen.
##
## The fade is stepped rather than slid, for the same reason the transition's
## card steps: nothing in this game cross-fades. The backdrop lands fully
## opaque, so the level the player just lost is gone rather than showing
## through.

## How long the card stays up before the title screen comes back.
const HOLD_SECONDS := 2.5
## How long the card takes to step in, and how many steps it takes.
const FADE_IN_SECONDS := 0.4
const FADE_STEPS := 5.0

const BACKDROP := Color(0.05, 0.04, 0.07, 1.0)
const RED := Color(0.86, 0.22, 0.27)
const ASH := Color(0.62, 0.6, 0.68)

var _playing := false
var _time := 0.0

var _root: Control


func _ready() -> void:
	# Above the HUD (layer 10), below the time warp (layer 100).
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _process(delta: float) -> void:
	if not _playing:
		return
	_time += delta
	_set_fade(clampf(_time / FADE_IN_SECONDS, 0.0, 1.0))
	if _time >= HOLD_SECONDS:
		_finish()


## Show the card and, HOLD_SECONDS later, return to the title screen.
## Ignored if it is already up.
func play() -> void:
	# Deferred: the death that triggers this happens inside a physics
	# callback, where pausing the tree isn't safe.
	_begin.call_deferred()


func is_active() -> bool:
	return _playing


# --- Internals --------------------------------------------------------------

func _begin() -> void:
	if _playing:
		return
	# A parry time stop shouldn't leave the screen negative under the card.
	TimeStop.stop()
	_playing = true
	_time = 0.0
	_set_fade(0.0)
	_root.visible = true
	get_tree().paused = true


func _finish() -> void:
	_playing = false
	_root.visible = false
	get_tree().paused = false
	GameManager.return_to_menu()


## How much of the card is showing, 0..1, in FADE_STEPS jumps rather than a
## slide — the same frame clock the transition's card fades on.
func _set_fade(amount: float) -> void:
	var steps := floorf(clampf(amount, 0.0, 1.0) * FADE_STEPS)
	_root.modulate.a = minf(steps / (FADE_STEPS - 1.0), 1.0)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.color = BACKDROP
	_root.add_child(backdrop)

	var title := _make_label(26, RED)
	title.text = "GAME OVER"
	_anchor_top_wide(title, 130.0, 40.0)
	_root.add_child(title)

	var note := _make_label(9, ASH)
	note.text = "THE RUN ENDS HERE"
	_anchor_top_wide(note, 174.0, 14.0)
	_root.add_child(note)


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.05))
	label.add_theme_constant_override("outline_size", maxi(roundi(font_size * 0.25), 2))
	return label


## Stretch across the top of the screen, `top` px down, `height` px tall.
func _anchor_top_wide(control: Control, top: float, height: float) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 1.0
	control.anchor_top = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = 0.0
	control.offset_right = 0.0
	control.offset_top = top
	control.offset_bottom = top + height
