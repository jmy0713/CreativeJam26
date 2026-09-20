extends Control
## The loading bar: the player binary-searching a timeline for the level they
## are travelling to. Used by scene_transition.gd, which feeds it progress.
##
## The bar is the whole timeline, past on the left and future on the right,
## with a tick for each level. The player starts on the level they're leaving
## and hops to the middle of the window still being searched. Each landing
## rules out half of it: too early means look later, too late means look
## earlier. The bright window narrows to a sliver around the destination, and
## the last step locks onto it.

const WIDTH := 300.0
const HEIGHT := 56.0

## Probes before locking on. The window shrinks to 1/2^STEPS of the timeline.
const STEPS := 8
## Share of the loading time spent probing. The rest is the lock-on.
const SEARCH_SHARE := 0.86
## Share of each probe spent hopping. The rest shows the verdict.
const HOP_SHARE := 0.6

const TRACK_Y := 34.0
const TRACK_HEIGHT := 12.0
## Two-thirds the size of the real player (12 x 24, light grey).
const PLAYER_SIZE := Vector2(8.0, 16.0)
const HOP_HEIGHT := 16.0

const GOLD := Color(1.0, 0.9, 0.62)
const CYAN := Color(0.55, 0.9, 1.0)
const PLAYER_COLOR := Color(0.8, 0.8, 0.8)
const OUTLINE := Color(0.03, 0.04, 0.09)
const RULED_OUT := Color(0.14, 0.17, 0.30)

## Text for the line under the bar, e.g. "PROBE 3 / 8  TOO EARLY >>".
var status := ""

var _levels := 1
var _start := 0.0
var _target := 0.0
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


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Plan a search from level `from_index` to level `to_index` (indices into a
## list of `level_count` levels). Runs the search up front so set_progress()
## only has to replay it.
func setup(level_count: int, from_index: int, to_index: int) -> void:
	_levels = maxi(level_count, 1)
	_start = _level_pos(from_index)
	_target = _level_pos(to_index)

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


## Replay the search up to `progress` (0 = start, 1 = done).
func set_progress(progress: float) -> void:
	var s := clampf(progress / SEARCH_SHARE, 0.0, 1.0) * STEPS
	if s >= STEPS:
		# Search over: slide onto the exact destination and pulse.
		_decided = STEPS
		_lock = clampf((progress - SEARCH_SHARE) / (1.0 - SEARCH_SHARE), 0.0, 1.0)
		_hop = 0.0
		_pos = lerpf(_mids[STEPS - 1], _target, smoothstep(0.0, 1.0, minf(_lock * 3.0, 1.0)))
		status = "TIME FOUND"
	else:
		_lock = 0.0
		var i := int(s)
		var f := s - float(i)
		var from_pos := _start if i == 0 else _mids[i - 1]
		_hop = clampf(f / HOP_SHARE, 0.0, 1.0)
		_pos = lerpf(from_pos, _mids[i], smoothstep(0.0, 1.0, _hop))
		# The verdict lands when the hop does.
		var landed := f >= HOP_SHARE
		_decided = i + (1 if landed else 0)
		status = "PROBE %d / %d" % [i + 1, STEPS]
		if landed:
			status += ("  TOO EARLY >>" if _laters[i] else "  << TOO LATE")

	_lo = 0.0 if _decided == 0 else _los[_decided - 1]
	_hi = 1.0 if _decided == 0 else _his[_decided - 1]
	queue_redraw()


## Where a level sits on the timeline (0..1). Offset from the exact middle of
## its slot so no level lands dead on a probe and ends the search early.
func _level_pos(index: int) -> float:
	return (float(clampi(index, 0, _levels - 1)) + 0.4) / float(_levels)


func _draw() -> void:
	var inner_x := 2.0
	var inner_w := size.x - 4.0
	var track_bottom := TRACK_Y + TRACK_HEIGHT

	# Frame, the ruled-out timeline, and the window still being searched.
	draw_rect(Rect2(0.0, TRACK_Y, size.x, TRACK_HEIGHT), GOLD)
	draw_rect(Rect2(inner_x, TRACK_Y + 2.0, inner_w, TRACK_HEIGHT - 4.0), RULED_OUT)
	draw_rect(
		Rect2(inner_x + _lo * inner_w, TRACK_Y + 2.0, maxf((_hi - _lo) * inner_w, 1.0), TRACK_HEIGHT - 4.0),
		CYAN
	)

	# Where each earlier probe landed.
	for j in _decided:
		var probe_x := inner_x + _mids[j] * inner_w
		draw_line(Vector2(probe_x, TRACK_Y + 1.0), Vector2(probe_x, track_bottom - 1.0), Color(1.0, 1.0, 1.0, 0.55), 1.0)

	# One tick per level under the bar. The destination's is bigger and cyan.
	for level in _levels:
		var level_pos := _level_pos(level)
		var tick_x := inner_x + level_pos * inner_w
		var is_target := absf(level_pos - _target) < 0.0001
		var tick_len := 7.0 if is_target else 4.0
		var tick_color := CYAN if is_target else GOLD
		draw_line(Vector2(tick_x, track_bottom + 1.0), Vector2(tick_x, track_bottom + tick_len), tick_color, 2.0 if is_target else 1.0)

	# The player, hopping between probes.
	var player_x := inner_x + _pos * inner_w
	var feet_y := TRACK_Y - 1.0 - sin(PI * _hop) * HOP_HEIGHT
	var body := Rect2(player_x - PLAYER_SIZE.x * 0.5, feet_y - PLAYER_SIZE.y, PLAYER_SIZE.x, PLAYER_SIZE.y)
	draw_rect(body.grow(1.0), OUTLINE)
	draw_rect(body, PLAYER_COLOR)

	# Lock-on pulse around the destination.
	if _lock > 0.0:
		var target_x := inner_x + _target * inner_w
		var centre := Vector2(target_x, TRACK_Y + TRACK_HEIGHT * 0.5)
		draw_arc(centre, lerpf(3.0, 14.0, _lock), 0.0, TAU, 24, Color(CYAN, 1.0 - _lock), 1.5)
