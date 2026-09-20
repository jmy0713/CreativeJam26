extends Control
## The loading bar: a timeline of years, and the player hunting down the time
## period of the level they are travelling to. Used by scene_transition.gd,
## which feeds it progress.
##
## The bar is history laid out left to right, one tick per level at its own
## year (1437, 2100, 1980 ...), so the run visibly jumps back and forth
## through it. The level being left is marked, the destination glows.
##
## The player binary-searches for that destination: it starts on the year it
## is leaving and each hop lands in the middle of the window still in play,
## calling out the year it arrived in. Too early means look later, too late
## means look earlier. The bright window narrows to a sliver and the last step
## drops the player onto the destination year.
##
## A level with no year on record (the boss) sits past the right-hand end of
## the bar and reads out as "????".
##
## The hopping figure is the player himself, straight off player_sheet.png and
## drawn at 1:1 -- scaling a sprite by anything but a whole number is what
## makes pixel art go soft, so he is his own size and the bar is built around
## him rather than the other way round.
##
## The rest is drawn as pixel art by the rules in section 7 of ARCHITECTURE.md.
## One unit here is one game pixel, and the canvas scale blows those up with
## nearest filtering exactly like the sprites, so all that is needed is to stay
## on the grid: every rect goes through _fill(), no colour carries alpha (dim
## tones stand in for it), and the hop and the lock-on step through a few
## frames instead of sliding. The text is the exception -- it renders at the
## window's resolution, like the HUD's, so it stays readable at 7 px.

const WIDTH := 300.0
## Tall enough for the player to stand on the track with his jump and his year
## tag above him. TRACK_Y moves with it, so the track itself doesn't shift.
const HEIGHT := 96.0

## Probes before locking on. The window shrinks to 1/2^STEPS of the timeline.
const STEPS := 8
## Share of the loading time spent probing. The rest is the lock-on.
const SEARCH_SHARE := 0.86
## Share of each probe spent hopping. The rest shows the verdict.
const HOP_SHARE := 0.6
## Frames a hop is cut into. The player snaps between them, the way a jump is
## animated, rather than gliding along a curve.
const HOP_FRAMES := 6.0
## Frames the lock-on bracket closes in.
const LOCK_FRAMES := 4.0

const TRACK_Y := 66.0
const TRACK_HEIGHT := 12.0
const HOP_HEIGHT := 16.0

## The player, off his own sheet. 64x64 frames with his feet at ANCHOR and the
## character BODY_HEIGHT tall in them -- see tools/make_player_sprites.py.
const FRAMES := preload("res://scenes/assets/player_frames.tres")
const FRAME_SIZE := 64.0
const ANCHOR := Vector2(26.0, 46.0)
const BODY_HEIGHT := 32.0
## One pose per hop frame, plus a standing one at either end: he launches on
## the jump animation, is still tipping over at the apex, and comes down on the
## fall one. Snapping between seven poses is the animation -- there is no
## tweening here any more than there is in the sprite sheet.
const HOP_POSES := [
	["idle", 0], ["jump", 1], ["jump", 3], ["jump", 5], ["fall", 1], ["fall", 2], ["idle", 0]
]
## The idle animation's own frame rate, for while he is standing still.
const IDLE_FPS := 8.0

## Years of empty timeline kept either side of the outermost level.
const YEAR_PADDING := 60
## A gridline and a label every this many years.
const GRID_YEARS := 100
## Where a level with no year sits: hard right, past the padding.
const UNKNOWN_POS := 0.97
## Must match GameManager.UNKNOWN_YEAR.
const UNKNOWN_YEAR := 0

const LABEL_SIZE := 7
const TAG_SIZE := 8

# Nothing here is translucent: a dimmer tone does the job alpha would, so the
# bar never blends with the tunnel behind it.
const GOLD := Color(1.0, 0.9, 0.62)
const CYAN := Color(0.55, 0.9, 1.0)
const OUTLINE := Color(0.03, 0.04, 0.09)
const RULED_OUT := Color(0.14, 0.17, 0.30)
const GRID := Color(0.24, 0.28, 0.44)
const GRID_TEXT := Color(0.62, 0.68, 0.85)
const PROBE := Color(0.66, 0.72, 0.92)
const ORIGIN := Color(0.60, 0.54, 0.38)
## The lock-on bracket: one radius and one tone per frame, snapping shut.
const PULSE_RADIUS := [15.0, 11.0, 8.0, 6.0]
const PULSE_TONE := [
	Color(0.22, 0.42, 0.60), Color(0.36, 0.62, 0.80), CYAN, Color(1.0, 1.0, 1.0)
]

## Text for the line under the bar, e.g. "1682  TOO EARLY >>".
var status := ""
## True when the destination is later than the level being left. Used by
## scene_transition.gd to spin the clock the right way round.
var to_future := true

var _years: Array[int] = []
var _min_year := 0
var _max_year := 0
var _start := 0.0
var _target := 0.0
var _target_index := 0
var _from_index := 0
# One entry per probe: where it lands, the window left after its verdict, and
# whether the verdict was "too early" (search later).
var _mids: Array[float] = []
var _los: Array[float] = []
var _his: Array[float] = []
var _laters: Array[bool] = []

# What to draw right now (all set by set_progress).
var _lo := 0.0
var _hi := 1.0
var _pos := 0.0
var _hop := 0.0
var _decided := 0
var _lock := 0.0
## Which way he is facing, 1 right and -1 left: the way his last hop went.
var _facing := 1.0
## Where the idle animation has got to while he stands and waits.
var _idle_frame := 0
## What the last _draw() drew. Everything above snaps between a handful of
## values, so most frames have nothing new to say and are not redrawn at all.
var _drawn: Array = []


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Plan a search from level `from_index` to level `to_index`, where `years`
## holds the year of every level in order (GameManager.LEVEL_YEARS). The span
## of the bar comes from those years, so adding or re-dating a level needs no
## change here. Runs the search up front so set_progress() only replays it.
func setup(years: Array[int], from_index: int, to_index: int) -> void:
	_years.assign(years)
	if _years.is_empty():
		_years.append(UNKNOWN_YEAR)

	var known: Array[int] = []
	for year in _years:
		if year != UNKNOWN_YEAR:
			known.append(year)
	if known.is_empty():
		known.append(2000)
	_min_year = int(known.min()) - YEAR_PADDING
	_max_year = int(known.max()) + YEAR_PADDING

	_from_index = clampi(from_index, 0, _years.size() - 1)
	_target_index = clampi(to_index, 0, _years.size() - 1)
	_start = _year_pos(_years[_from_index])
	_target = _year_pos(_years[_target_index])
	to_future = _target >= _start

	_mids.clear()
	_los.clear()
	_his.clear()
	_laters.clear()
	var lo := 0.0
	var hi := 1.0
	for _i in STEPS:
		var mid := (lo + hi) * 0.5
		var later := mid < _target
		if later:
			lo = mid
		else:
			hi = mid
		_mids.append(mid)
		_los.append(lo)
		_his.append(hi)
		_laters.append(later)
	set_progress(0.0)


## Replay the search up to `progress` (0 = start, 1 = done). `elapsed` is how
## long the loading screen has been up, which is what the idle animation runs
## off while he is standing between hops.
func set_progress(progress: float, elapsed: float = 0.0) -> void:
	var s := clampf(progress / SEARCH_SHARE, 0.0, 1.0) * STEPS
	if s >= STEPS:
		# Search over: slide onto the exact year and pulse.
		_decided = STEPS
		var locking := clampf((progress - SEARCH_SHARE) / (1.0 - SEARCH_SHARE), 0.0, 1.0)
		_lock = roundf(locking * LOCK_FRAMES) / LOCK_FRAMES
		_hop = 0.0
		_pos = lerpf(_mids[STEPS - 1], _target, smoothstep(0.0, 1.0, minf(_lock * 3.0, 1.0)))
		if _target != _mids[STEPS - 1]:
			_facing = 1.0 if _target > _mids[STEPS - 1] else -1.0
		status = "%s  LOCKED" % target_year_text()
	else:
		_lock = 0.0
		var i := int(s)
		var f := s - float(i)
		var from_pos := _start if i == 0 else _mids[i - 1]
		# Rounded, not floored: the hop still starts at 0 and lands on 1.
		_hop = roundf(clampf(f / HOP_SHARE, 0.0, 1.0) * HOP_FRAMES) / HOP_FRAMES
		_pos = lerpf(from_pos, _mids[i], smoothstep(0.0, 1.0, _hop))
		if _mids[i] != from_pos:
			_facing = 1.0 if _mids[i] > from_pos else -1.0
		# The verdict lands when the hop does.
		var landed := f >= HOP_SHARE
		_decided = i + (1 if landed else 0)
		if landed:
			status = "%d AD  " % _year_at(_mids[i])
			status += ("TOO EARLY >>" if _laters[i] else "<< TOO LATE")
		else:
			status = "SCANNING %d AD" % _year_at(_pos)

	_lo = 0.0 if _decided == 0 else _los[_decided - 1]
	_hi = 1.0 if _decided == 0 else _his[_decided - 1]
	_idle_frame = int(elapsed * IDLE_FPS)

	# Nothing here slides, so most frames are the same picture as the last one.
	var state: Array = [_lo, _hi, _pos, _hop, _decided, _lock, _facing, _idle_frame]
	if state != _drawn:
		_drawn = state
		queue_redraw()


## The destination as text: "1437 AD", or "????" for a level with no year.
func target_year_text() -> String:
	var year: int = _years[_target_index]
	return "????" if year == UNKNOWN_YEAR else "%d AD" % year


## The oldest and newest years the bar covers, for the labels on its ends.
func min_year() -> int:
	return _min_year


func max_year() -> int:
	return _max_year


## Where a year sits on the timeline (0..1).
func _year_pos(year: int) -> float:
	if year == UNKNOWN_YEAR:
		return UNKNOWN_POS
	return clampf(inverse_lerp(float(_min_year), float(_max_year), float(year)), 0.0, 1.0)


## The year a point on the timeline falls in.
func _year_at(pos: float) -> int:
	return roundi(lerpf(float(_min_year), float(_max_year), clampf(pos, 0.0, 1.0)))


## An opaque rect on whole pixels. Everything on the bar goes through here:
## draw_rect and draw_line both happily straddle two pixels if you let them,
## and a straddled edge comes out soft.
func _fill(x: float, y: float, w: float, h: float, color: Color) -> void:
	var x0 := roundf(x)
	var y0 := roundf(y)
	draw_rect(
		Rect2(x0, y0, maxf(roundf(x + w) - x0, 1.0), maxf(roundf(y + h) - y0, 1.0)),
		color
	)


func _draw() -> void:
	var font := get_theme_default_font()
	var inner_x := 2.0
	var inner_w := size.x - 4.0
	var track_bottom := TRACK_Y + TRACK_HEIGHT

	# Frame, the ruled-out timeline, and the window still being searched.
	_fill(0.0, TRACK_Y, size.x, TRACK_HEIGHT, GOLD)
	_fill(inner_x, TRACK_Y + 2.0, inner_w, TRACK_HEIGHT - 4.0, RULED_OUT)
	_fill(
		inner_x + _lo * inner_w, TRACK_Y + 2.0,
		maxf((_hi - _lo) * inner_w, 1.0), TRACK_HEIGHT - 4.0, CYAN
	)

	# A century grid, so the bar reads as years rather than progress.
	var century := int(ceilf(float(_min_year) / float(GRID_YEARS))) * GRID_YEARS
	while century <= _max_year:
		var grid_x := inner_x + _year_pos(century) * inner_w
		_fill(grid_x, TRACK_Y + 2.0, 1.0, TRACK_HEIGHT - 4.0, GRID)
		if font != null:
			draw_string(
				font, Vector2(roundf(grid_x - 16.0), roundf(track_bottom + 17.0)), str(century),
				HORIZONTAL_ALIGNMENT_CENTER, 32.0, LABEL_SIZE, GRID_TEXT
			)
		century += GRID_YEARS

	# Where each earlier probe landed.
	for j in _decided:
		_fill(inner_x + _mids[j] * inner_w, TRACK_Y + 1.0, 1.0, TRACK_HEIGHT - 2.0, PROBE)

	# One tick per level, at its own year. The destination's is bigger and
	# cyan; the one being left keeps a dim marker so the jump reads as a jump.
	for level in _years.size():
		var tick_x := inner_x + _year_pos(_years[level]) * inner_w
		var is_target := level == _target_index
		var is_origin := level == _from_index and not is_target
		if is_target:
			_fill(tick_x - 1.0, track_bottom + 1.0, 2.0, 7.0, CYAN)
			# A flag on the destination year, standing above the timeline.
			_fill(tick_x, TRACK_Y - 9.0, 1.0, 9.0, CYAN)
			_fill(tick_x + 1.0, TRACK_Y - 9.0, 5.0, 4.0, CYAN)
		else:
			_fill(tick_x, track_bottom + 1.0, 1.0, 4.0, GOLD)
			if is_origin:
				_fill(tick_x - 1.0, TRACK_Y - 4.0, 3.0, 3.0, ORIGIN)

	# The player, hopping between years. Both the arc and the pose are sampled
	# at the hop's current frame, so he steps through the jump rather than
	# sliding along a curve, and he is drawn at 1:1 -- his own size, on whole
	# pixels, never scaled.
	var player_x := roundf(inner_x + _pos * inner_w)
	var feet_y := roundf(TRACK_Y - 1.0 - sin(PI * _hop) * HOP_HEIGHT)
	var body_y := feet_y - BODY_HEIGHT
	var pose: Array = HOP_POSES[clampi(int(roundf(_hop * HOP_FRAMES)), 0, HOP_POSES.size() - 1)]
	var anim: String = pose[0]
	var frame: int = pose[1]
	if anim == "idle":
		frame = _idle_frame % maxi(FRAMES.get_frame_count("idle"), 1)
	var tex := FRAMES.get_frame_texture(anim, frame)
	if tex != null:
		# Where the anchor column sits in the frame as drawn: ANCHOR.x from the
		# left normally, the same distance from the right once mirrored.
		var anchor_x := FRAME_SIZE - ANCHOR.x if _facing < 0.0 else ANCHOR.x
		var top := feet_y - ANCHOR.y
		# A negative width mirrors the frame IN PLACE: the rect's position is
		# its left edge either way and only the sampling flips, so both
		# facings are drawn from the same x. (It does not measure the span
		# back from that x -- assuming it did put him a frame's width to the
		# right of his own year.) Mirroring like this keeps him exactly on the
		# pixel grid, which rotating the draw would not.
		draw_texture_rect(
			tex, Rect2(player_x - anchor_x, top, FRAME_SIZE * _facing, FRAME_SIZE), false
		)

	# The year the player is standing in, carried above its head.
	if font != null:
		var tag := target_year_text() if _lock > 0.0 else str(_year_at(_pos))
		var tag_size := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_CENTER, -1.0, TAG_SIZE)
		var tag_x := roundf(clampf(player_x - tag_size.x * 0.5 - 3.0, 0.0, size.x - tag_size.x - 6.0))
		var tag_y := roundf(maxf(body_y - 13.0, 0.0))
		var tag_color := CYAN if _lock > 0.0 else GOLD
		_fill(tag_x, tag_y, roundf(tag_size.x) + 6.0, 11.0, OUTLINE)
		draw_string(
			font, Vector2(tag_x + 3.0, tag_y + 8.0), tag,
			HORIZONTAL_ALIGNMENT_CENTER, tag_size.x, TAG_SIZE, tag_color
		)

	# Lock-on: a bracket snapping shut on the destination year, one step per
	# frame, instead of a ring fading out.
	if _lock > 0.0:
		var pulse := clampi(int(roundf(_lock * LOCK_FRAMES)) - 1, 0, PULSE_RADIUS.size() - 1)
		var rad: float = PULSE_RADIUS[pulse]
		var tone: Color = PULSE_TONE[pulse]
		var cx := roundf(inner_x + _target * inner_w)
		var cy := roundf(TRACK_Y + TRACK_HEIGHT * 0.5)
		var span := rad * 2.0 + 1.0
		_fill(cx - rad, cy - rad, span, 1.0, tone)
		_fill(cx - rad, cy + rad, span, 1.0, tone)
		_fill(cx - rad, cy - rad, 1.0, span, tone)
		_fill(cx + rad, cy - rad, 1.0, span, tone)
