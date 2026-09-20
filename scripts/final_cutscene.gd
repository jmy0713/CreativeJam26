class_name FinalCutscene
extends Node2D
## The ending. Plays once the final boss dies, then hands the game back to the
## title screen (GameManager.play_final_cutscene()).
##
## The set is one room, `Scrollablefinalroom_0000.png` at ROOM_SCALE, which
## makes it two screens wide -- so the room is scrolled rather than framed, the
## same trick the prologue plays with its road. Three figures are in it: you,
## walking in through the door on the left; another you, standing in the middle
## of the room; and the painter at the far end, painting with his back turned.
##
## The beats, in order:
##
##   WALK_IN    you walk in from off the left and stop. The camera holds the
##              opening shot, so the other you is simply standing there at the
##              right-hand side of it
##   LOOK       a beat to let that land
##   PAN        the camera slides right, off you and onto the other you and
##              the painter beyond him
##   WATCH      the painter paints. His clip is looped short of the turn (see
##              PAINT_LOOP_END) -- he does not know anyone is there yet
##   ZOOM_OUT   the camera pulls back to hold all three at once
##   CHOOSE     the choice goes up across the top of the screen and waits
##   ZOOM_IN    whichever was picked, the camera goes in on the painter
##   PAINT      the whole paint clip plays out, turn and all, and the run ends.
##              Pick the painter and he is bleeding by then: the splash goes up
##              as he starts to come round (see PixelBlood and _pose_blood())
##
## The two answers only differ in the blood today. The rest of the branch goes
## in _on_chosen() and _pose_blood() when there is a second ending to play.
##
## LIKE THE OTHER CUTSCENES, THIS COUNTS PLAIN `delta`. GameManager's clocks
## belong to a running level; a cutscene has no timeline to rewind, so a tick
## stamp would be worth nothing here. prologue.gd and GameOver do the same. The
## frames still come from SpriteClock, so the sheets stay the one source of
## frame counts and rates.

## `Scrollablefinalroom_0000.png` is 320x90 and the game is 640x360, so 4 is
## the only whole-number scale that fills the screen's height -- and it makes
## the room 1280 across, exactly two screens. One room pixel is PIXEL screen
## pixels, and the camera is snapped to that grid whenever it isn't in the
## middle of a zoom, or the room's chunky pixels crawl as it scrolls.
const ROOM_SCALE := 4.0
const PIXEL := ROOM_SCALE

## Floor line, in world pixels: the foot of the wall, where the door's bottom
## edge sits (y 77 of the art). Both player sprites are anchored feet-on-this
## by the sheet's own anchor, so their node y IS this -- see make_player_sprites.py.
const FLOOR_Y := 308.0

## How fast you walk in. Not the player's own move_speed: he is drawn four
## times his in-game size here, so his in-game speed would read as a crawl
## across a room this size. This is the knob for how long the entrance takes.
const WALK_SPEED := 220.0

## Where you come in from and where you stop, in world pixels.
const ENTER_X := -60.0
const STAND_X := 340.0

## Camera shots, as (x, y, zoom). SHOT_WIDE has to hold you, the other you and
## the whole easel at once, and SHOT_CLOSE the painter and the canvas he is
## working on, so both move if any of the three do. Zoom 0.75 is the pull-back:
## at 3/4 one room pixel is exactly 3 screen pixels, so it stays on a
## whole-number grid, and it is still loose enough to hold all three.
const SHOT_ROOM := Vector3(400.0, 180.0, 1.0)
const SHOT_PAINTER := Vector3(834.0, 180.0, 1.0)
const SHOT_WIDE := Vector3(668.0, 180.0, 0.75)
const SHOT_CLOSE := Vector3(985.0, 219.0, 1.5)

## How long each beat runs. CHOOSE has none -- it waits.
const LOOK_SECONDS := 1.2
const PAN_SECONDS := 2.2
const WATCH_SECONDS := 3.0
const ZOOM_OUT_SECONDS := 1.6
const ZOOM_IN_SECONDS := 1.8
## How long the last frame of the paint clip stays up before the menu returns.
const HOLD_SECONDS := 5.0

const PAINT_ANIM := &"paint"
const WALK_ANIM := &"run"
const STAND_ANIM := &"idle"

## The painter turns to face the room around frame 61 of his 82. Everything
## before that is him working, so that is what loops while he is unaware --
## the turn is saved for the ending itself.
const PAINT_LOOP_END := 61

## The blood, on Choice.PAINTER only -- two nodes, one either side of the
## painter in the tree, see PixelBlood. It goes up a beat before the turn does,
## so it is already in the air by the time his face comes round, and runs for
## BLOOD_SECONDS -- after which PixelBlood holds its last pose and the pool
## stays on the floor for the rest of the shot.
const BLOOD_LEAD := 0.25
const BLOOD_SECONDS := 1.4

enum Phase { WALK_IN, LOOK, PAN, WATCH, ZOOM_OUT, CHOOSE, ZOOM_IN, PAINT, DONE }
enum Choice { NONE, SELF, PAINTER }

var choice := Choice.NONE

var _phase := Phase.WALK_IN
var _phase_time := 0.0
var _actor_x := ENTER_X
## Counts only while you are walking, so the cycle doesn't restart when you stop.
var _walk_time := 0.0
## The painter's own clock: it loops him short of the turn until the choice is
## made, and then runs the whole clip once from the top.
var _paint_time := 0.0

@onready var actor: AnimatedSprite2D = $Actor
@onready var painter: AnimatedSprite2D = $Painter
@onready var blood: PixelBlood = $Blood
@onready var blood_pool: PixelBlood = $BloodPool
@onready var camera: Camera2D = $Camera2D
@onready var choice_ui: Control = $Ui/Choice
@onready var first_option: Button = $Ui/Choice/Options/Self


func _ready() -> void:
	_actor_x = ENTER_X
	choice_ui.visible = false
	blood.visible = false
	blood_pool.visible = false
	_set_shot(SHOT_ROOM)
	_pose()


func _process(delta: float) -> void:
	_phase_time += delta
	if _phase != Phase.CHOOSE:
		_paint_time += delta

	match _phase:
		Phase.WALK_IN:
			_actor_x = minf(_actor_x + WALK_SPEED * delta, STAND_X)
			_walk_time += delta
			if _actor_x >= STAND_X:
				_enter(Phase.LOOK)
		Phase.LOOK:
			if _phase_time >= LOOK_SECONDS:
				_enter(Phase.PAN)
		Phase.PAN:
			_pan(SHOT_ROOM, SHOT_PAINTER, _phase_time / PAN_SECONDS)
			if _phase_time >= PAN_SECONDS:
				_enter(Phase.WATCH)
		Phase.WATCH:
			if _phase_time >= WATCH_SECONDS:
				_enter(Phase.ZOOM_OUT)
		Phase.ZOOM_OUT:
			_pan(SHOT_PAINTER, SHOT_WIDE, _phase_time / ZOOM_OUT_SECONDS)
			if _phase_time >= ZOOM_OUT_SECONDS:
				_begin_choice()
		Phase.CHOOSE:
			pass
		Phase.ZOOM_IN:
			_pan(SHOT_WIDE, SHOT_CLOSE, _phase_time / ZOOM_IN_SECONDS)
			if _phase_time >= ZOOM_IN_SECONDS:
				_enter(Phase.PAINT)
		Phase.PAINT:
			if _paint_time >= SpriteClock.seconds(painter.sprite_frames, PAINT_ANIM) + HOLD_SECONDS:
				_enter(Phase.DONE)
				GameManager.return_to_menu()

	_pose()


func _enter(phase: Phase) -> void:
	_phase = phase
	_phase_time = 0.0


# --- The choice -------------------------------------------------------------

func _begin_choice() -> void:
	_enter(Phase.CHOOSE)
	choice_ui.visible = true
	# Focused so the keyboard works: arrows move between the two, Enter picks.
	first_option.grab_focus()


func _on_kill_self_pressed() -> void:
	_on_chosen(Choice.SELF)


func _on_kill_painter_pressed() -> void:
	_on_chosen(Choice.PAINTER)


## Both answers end the same way today. The ending that is different goes here.
func _on_chosen(picked: Choice) -> void:
	if _phase != Phase.CHOOSE:
		return
	choice = picked
	choice_ui.visible = false
	# The clip restarts so the whole take -- the turn included -- plays in the
	# close-up, rather than the zoom catching it part way through its loop.
	_paint_time = 0.0
	_enter(Phase.ZOOM_IN)


# --- Camera -----------------------------------------------------------------

## Put the camera on `shot`: (x, y, zoom). It is snapped to the room's own
## pixel grid at zoom 1, where one room pixel is exactly PIXEL screen pixels.
## Through a zoom the art is being resampled anyway, and snapping there would
## only make the move judder.
func _set_shot(shot: Vector3) -> void:
	var zoom := shot.z
	if is_equal_approx(zoom, 1.0):
		camera.position = Vector2(snappedf(shot.x, PIXEL), snappedf(shot.y, PIXEL))
	else:
		camera.position = Vector2(shot.x, shot.y)
	camera.zoom = Vector2(zoom, zoom)


func _pan(from: Vector3, to: Vector3, t: float) -> void:
	_set_shot(from.lerp(to, smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))))


# --- Posing -----------------------------------------------------------------

func _pose() -> void:
	actor.position.x = snappedf(_actor_x, PIXEL)
	var anim := WALK_ANIM if _phase == Phase.WALK_IN else STAND_ANIM
	actor.animation = anim
	actor.frame = SpriteClock.frame_in_loop(actor.sprite_frames, anim, _walk_time)
	_pose_painter()
	_pose_blood()


## Before the choice he is looping his work and must not turn round, so the
## loop is cut at PAINT_LOOP_END rather than running the clip's own length.
## Afterwards it is the clip itself, once, holding the last frame -- which is
## what SpriteClock.frame_at does for free.
func _pose_painter() -> void:
	var frames := painter.sprite_frames
	if _phase == Phase.ZOOM_IN or _phase == Phase.PAINT or _phase == Phase.DONE:
		painter.frame = SpriteClock.frame_at(frames, PAINT_ANIM, _paint_time)
		return
	var fps := frames.get_animation_speed(PAINT_ANIM)
	painter.frame = posmod(int(_paint_time * fps), PAINT_LOOP_END)


## The splash, keyed off the same clip clock the turn is: PAINT_LOOP_END is
## where he starts to come round, so the blood is hung off that rather than off
## a second hand-timed number that would drift away from it.
func _pose_blood() -> void:
	if choice != Choice.PAINTER or _phase == Phase.CHOOSE or _phase == Phase.ZOOM_IN:
		return
	var fps := painter.sprite_frames.get_animation_speed(PAINT_ANIM)
	var start := PAINT_LOOP_END / fps - BLOOD_LEAD
	if _paint_time < start:
		return
	var t := (_paint_time - start) / BLOOD_SECONDS
	blood.visible = true
	blood.set_pose(t)
	blood_pool.visible = true
	blood_pool.set_pose(t)
