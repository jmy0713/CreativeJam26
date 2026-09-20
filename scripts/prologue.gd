class_name Prologue
extends Node2D
## The opening cutscene, played on the title screen itself.
##
## The title screen's backdrop IS this cutscene's set: `prologue.png` is twice
## as wide as the screen, and the menu sits on the left half of it. Pressing
## Play hides the menu and hands over to play(), so the camera never cuts --
## the buttons come off the same road the cutscene walks down. (The HUD needs
## no help: no Level registers here, so it hides itself. See hud.gd.)
##
## The beats, in order:
##
##   CUE       the time machine winds up (the same sound the level warps use)
##   WALK_IN   he walks in from off the left edge. The camera holds still
##             until he reaches the middle of the screen and then tracks him,
##             until it runs out of backdrop -- he keeps walking to the right
##             edge of the art on his own
##   SPEAK     he stands and says his LINES, typed out a character at a time
##   WALK_OUT  he turns around and walks back off the left of the screen. No
##             tracking this time: the camera stays where the art ran out
##
## Then `finished` fires and the menu sends the player to level 1.
##
## Nothing here reads input -- he is walked by the clock, not driven.
##
## LIKE THE OTHER CUTSCENES, THIS COUNTS PLAIN `delta`. GameManager's clocks
## belong to a running level; a cutscene has no timeline to rewind, so there
## is nothing for a tick stamp to be worth. final_cutscene.gd does the same.
## The frames still come from SpriteClock so the sheet stays the one source
## of frame counts and rates.

## Fires once he is off screen and the road is empty again.
signal finished

## The time machine. Deliberately the same stream scene_transition.gd plays
## over a level warp: this is the machine he is about to use.
const TIME_MACHINE_SOUND := "res://scenes/assets/audio/transition.mp3"

## Feet line, in world pixels. The road in `prologue.png` starts around y 141
## of the art (y 282 here, at 2x) and runs to the bottom of the screen, so
## this stands him a good way into it rather than on its ragged top edge.
const GROUND_Y := 342.0

## How fast he walks. This is Player.move_speed, so the cutscene and the game
## move him at the same rate -- and it is the knob for the whole thing's
## length, since the walk is nearly all of it (~21 s end to end today).
const WALK_SPEED := 200

## How far off the edge of the screen he starts and finishes: far enough that
## the sprite is fully clear of it, not so far that he wastes seconds walking
## somewhere nobody can see.
const OFFSCREEN_MARGIN := 48.0
## Where he stops, measured in from the right edge of the backdrop. He ends
## the walk at the end of the road, but not pressed against the frame: this
## leaves room for the caption to sit over his head instead of being shoved
## off him by the screen edge (see _place_line()).
const STAND_INSET := 300.0

## Quiet beat between the machine starting up and him walking on.
const CUE_SECONDS := 5.0
## Beat after he leaves the frame, before the menu takes over.
const EXIT_SECONDS := 0.6

## `prologue.png` is drawn at half the game's resolution, so one of its pixels
## is PIXEL screen pixels. Everything on this set is held to that grid: the
## actor is blown up by it (in the scene: scale (2, 1.6) -- the 0.8 squash
## Player wears, doubled) and both he and the camera are snapped to it. He is
## twice his in-game size as a result, which is the point -- at 1:1 his pixels
## are a quarter the size of the road's and he reads as a detail stuck on top
## of the painting rather than a man standing on it. Anything finer than this
## grid slides the backdrop's chunky pixels against the screen's and the whole
## thing shimmers as it scrolls.
const PIXEL := 2.0

const WALK_ANIM := &"run"
const STAND_ANIM := &"idle"

## What he says, in order. `face` is which way he turns to say it (he turns to
## look back the way he came for the second line, which is what sends him
## home), `cps` is how fast it types out -- the three dots are slow on purpose,
## one blip a beat -- and `hold` is how long the finished line stays up.
const LINES: Array[Dictionary] = [
	{"text": "...", "face": 1.0, "cps": 3.0, "hold": 1.0},
	{"text": "I need to go back", "face": -1.0, "cps": 15.0, "hold": 1.6},
]

## The caption's box: it hangs with its bottom edge on LINE_Y, just clear of
## his head, and is LINE_HALF_WIDTH either side of whatever it is centred on.
## LINE_EDGE_MARGIN is how close to the edge of the screen that box may get
## before it stops following him (see _place_line()).
const LINE_Y := 284.0
const LINE_HEIGHT := 24.0
const LINE_HALF_WIDTH := 90.0
const LINE_EDGE_MARGIN := 8.0

# --- Placeholder voice ------------------------------------------------------
# One square-wave blip per character, built in code rather than shipped as an
# asset: there is no recorded line to play yet, and a generated blip is honest
# about that where a borrowed sound effect would not be. Swap _make_voice()
# for a loaded stream once the line is recorded.
#
# It is pixel art's rules applied to a waveform: a hard square rather than a
# shaped tone, and an envelope that steps down VOICE_STEPS times instead of
# sliding to silence.
const VOICE_RATE := 22050
const VOICE_SECONDS := 0.055
const VOICE_HZ := 50.0
const VOICE_STEPS := 6
const VOICE_LEVEL := 9000.0

enum Phase { MENU, CUE, WALK_IN, SPEAK, WALK_OUT, DONE }

var _phase := Phase.MENU
var _phase_time := 0.0
## Counts only while he is actually walking, so the cycle doesn't restart
## (mid-stride) when he turns around.
var _walk_time := 0.0
var _actor_x := 0.0
var _facing := 1.0
var _line_index := 0
## Characters of the current line revealed so far.
var _shown := 0
var _exit_x := 0.0
## The scene's own x scale, kept so facing can flip its sign without losing
## the blow-up to the backdrop's pixel size (see PIXEL).
var _actor_scale_x := 1.0

@onready var background: Sprite2D = $Background
@onready var camera: Camera2D = $Camera2D
@onready var actor: AnimatedSprite2D = $Actor
## The same blob the player casts in a level, drawn in the backdrop's coarser
## pixels (see PIXEL) and sized for the actor's blow-up. He never leaves the
## road, so unlike the player's it is never taken away for a jump -- it is on
## screen for exactly as long as he is.
@onready var shadow: BlobShadow = $Shadow
@onready var line: Label = $Line

var _machine: AudioStreamPlayer
var _voice: AudioStreamPlayer


func _ready() -> void:
	_actor_scale_x = actor.scale.x
	actor.visible = false
	shadow.visible = false
	line.visible = false
	line.text = ""
	line.size = Vector2(LINE_HALF_WIDTH * 2.0, LINE_HEIGHT)
	_machine = AudioStreamPlayer.new()
	_machine.stream = load(TIME_MACHINE_SOUND)
	add_child(_machine)
	_voice = AudioStreamPlayer.new()
	_voice.stream = _make_voice()
	add_child(_voice)
	# The menu looks at the left end of the road.
	camera.position.x = _camera_limits().x


## Start the cutscene. The caller has already taken its own UI off screen.
func play() -> void:
	if _phase != Phase.MENU:
		return
	_actor_x = _view_left() - OFFSCREEN_MARGIN
	_facing = 1.0
	_line_index = 0
	_walk_time = 0.0
	_machine.play()
	_enter(Phase.CUE)


func _process(delta: float) -> void:
	if _phase == Phase.MENU or _phase == Phase.DONE:
		return
	_phase_time += delta

	match _phase:
		Phase.CUE:
			if _phase_time >= CUE_SECONDS:
				actor.visible = true
				shadow.visible = true
				_enter(Phase.WALK_IN)
		Phase.WALK_IN:
			_walk(delta)
			# Tracking is the clamp in _follow(): it holds at the left end of
			# the backdrop until he passes the middle, and again once the art
			# runs out on the right, which he then walks the last of alone.
			_follow()
			if _actor_x >= _stand_x():
				_actor_x = _stand_x()
				_begin_line()
		Phase.SPEAK:
			_speak()
		Phase.WALK_OUT:
			_walk(delta)
			if _actor_x <= _exit_x:
				_enter(Phase.DONE)
				actor.visible = false
				shadow.visible = false
				await get_tree().create_timer(EXIT_SECONDS).timeout
				finished.emit()

	_pose()


# --- Beats ------------------------------------------------------------------

func _walk(delta: float) -> void:
	_actor_x += WALK_SPEED * _facing * delta
	_walk_time += delta


## Reveal the current line a character at a time, blipping on each one, then
## hold it and move on. The last line hands over to the walk home.
func _speak() -> void:
	var text: String = LINES[_line_index]["text"]
	var cps: float = LINES[_line_index]["cps"]
	var revealed := mini(int(_phase_time * cps), text.length())
	if revealed > _shown:
		_shown = revealed
		line.text = text.substr(0, _shown)
		_blip(text.unicode_at(_shown - 1))
	if _shown < text.length():
		return
	if _phase_time < text.length() / cps + float(LINES[_line_index]["hold"]):
		return
	_line_index += 1
	if _line_index < LINES.size():
		_begin_line()
	else:
		line.visible = false
		_exit_x = _view_left() - OFFSCREEN_MARGIN
		_enter(Phase.WALK_OUT)


func _begin_line() -> void:
	_shown = 0
	line.text = ""
	line.visible = true
	_facing = LINES[_line_index]["face"]
	_enter(Phase.SPEAK)


func _enter(phase: Phase) -> void:
	_phase = phase
	_phase_time = 0.0


# --- Camera and framing -----------------------------------------------------

## How wide the backdrop is in world pixels, measured off the art itself so
## re-exporting `prologue.png` at another size moves the walk with it.
func _world_width() -> float:
	return background.texture.get_width() * background.scale.x


## The nearest and furthest the camera may sit: far enough in that the screen
## is always full of backdrop. They meet on a window wider than the art.
func _camera_limits() -> Vector2:
	var half := get_viewport_rect().size.x * 0.5
	return Vector2(half, maxf(_world_width() - half, half))


func _view_left() -> float:
	return camera.position.x - get_viewport_rect().size.x * 0.5


func _stand_x() -> float:
	return _world_width() - STAND_INSET


func _follow() -> void:
	var limits := _camera_limits()
	camera.position.x = snappedf(clampf(_actor_x, limits.x, limits.y), PIXEL)


## Pose the actor and hang the caption over his head. Facing is a negative
## x scale, exactly as Player does it, so the two wear the sheet the same way.
func _pose() -> void:
	actor.position = Vector2(snappedf(_actor_x, PIXEL), GROUND_Y)
	actor.scale.x = _actor_scale_x * _facing
	# Under his feet, which is where the actor's own origin sits: the sheet's
	# offset already centres him on it, so the shadow wants nothing of its
	# own. It takes the snapped position rather than `_actor_x` so the blob
	# and the man step along the grid together instead of sliding apart by a
	# pixel as he walks.
	shadow.position = actor.position
	var anim := STAND_ANIM if _phase == Phase.SPEAK else WALK_ANIM
	actor.animation = anim
	actor.frame = SpriteClock.frame_in_loop(actor.sprite_frames, anim, _walk_time)
	if line.visible:
		_place_line()


## The caption follows his head, but never off the side of the screen -- he
## stops talking at the right-hand edge of the art, where centred text would
## hang half of itself past it. A Control is placed by its top-left corner,
## so the centre it is really being given is undone here.
func _place_line() -> void:
	var view_width := get_viewport_rect().size.x
	var left := _view_left() + LINE_HALF_WIDTH + LINE_EDGE_MARGIN
	var right := _view_left() + view_width - LINE_HALF_WIDTH - LINE_EDGE_MARGIN
	var centre := clampf(_actor_x, left, right)
	line.position = Vector2(snappedf(centre - LINE_HALF_WIDTH, 1.0), LINE_Y - LINE_HEIGHT)


# --- Voice ------------------------------------------------------------------

## One blip, pitched off the character so a line reads as speech rather than a
## metronome. Punctuation and spaces are skipped: the dots in "..." are the
## exception, and get a blip of their own so the pause has a voice.
func _blip(code: int) -> void:
	if code == 32:
		return
	_voice.pitch_scale = 0.92 + float(code % 5) * 0.04
	_voice.play()


func _make_voice() -> AudioStreamWAV:
	var length := int(VOICE_RATE * VOICE_SECONDS)
	var period := float(VOICE_RATE) / VOICE_HZ
	var data := PackedByteArray()
	data.resize(length * 2)
	for i in length:
		var step := floorf(float(i) / float(length) * VOICE_STEPS)
		var level := 1.0 - step / float(VOICE_STEPS)
		var square := 1.0 if fmod(float(i), period) < period * 0.5 else -1.0
		data.encode_s16(i * 2, int(square * level * VOICE_LEVEL))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = VOICE_RATE
	stream.stereo = false
	stream.data = data
	return stream
