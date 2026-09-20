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

const WIDTH := 300.0
const HEIGHT := 76.0

## Probes before locking on. The window shrinks to 1/2^STEPS of the timeline.
const STEPS := 8
## Share of the loading time spent probing. The rest is the lock-on.
const SEARCH_SHARE := 0.86
## Share of each probe spent hopping. The rest shows the verdict.
const HOP_SHARE := 0.6

const TRACK_Y := 46.0
const TRACK_HEIGHT := 12.0
## Two-thirds the size of the real player (12 x 24, light grey).
const PLAYER_SIZE := Vector2(8.0, 16.0)
const HOP_HEIGHT := 16.0

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

const GOLD := Color(1.0, 0.9, 0.62)
const CYAN := Color(0.55, 0.9, 1.0)
const PLAYER_COLOR := Color(0.8, 0.8, 0.8)
const OUTLINE := Color(0.03, 0.04, 0.09)
const RULED_OUT := Color(0.14, 0.17, 0.30)
const GRID := Color(1.0, 1.0, 1.0, 0.13)
const GRID_TEXT := Color(0.62, 0.68, 0.85)

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


## Replay the search up to `progress` (0 = start, 1 = done).
func set_progress(progress: float) -> void:
	var s := clampf(progress / SEARCH_SHARE, 0.0, 1.0) * STEPS
	if s >= STEPS:
		# Search over: slide onto the exact year and pulse.
		_decided = STEPS
		_lock = clampf((progress - SEARCH_SHARE) / (1.0 - SEARCH_SHARE), 0.0, 1.0)
		_hop = 0.0
		_pos = lerpf(_mids[STEPS - 1], _target, smoothstep(0.0, 1.0, minf(_lock * 3.0, 1.0)))
		status = "%s  LOCKED" % target_year_text()
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
		if landed:
			status = "%d AD  " % _year_at(_mids[i])
			status += ("TOO EARLY >>" if _laters[i] else "<< TOO LATE")
		else:
			status = "SCANNING %d AD" % _year_at(_pos)

	_lo = 0.0 if _decided == 0 else _los[_decided - 1]
	_hi = 1.0 if _decided == 0 else _his[_decided - 1]
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


func _draw() -> void:
	var font := get_theme_default_font()
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

	# A century grid, so the bar reads as years rather than progress.
	var century := int(ceilf(float(_min_year) / float(GRID_YEARS))) * GRID_YEARS
	while century <= _max_year:
		var grid_x := inner_x + _year_pos(century) * inner_w
		draw_line(Vector2(grid_x, TRACK_Y + 2.0), Vector2(grid_x, track_bottom - 2.0), GRID, 1.0)
		if font != null:
			draw_string(
				font, Vector2(grid_x - 16.0, track_bottom + 17.0), str(century),
				HORIZONTAL_ALIGNMENT_CENTER, 32.0, LABEL_SIZE, GRID_TEXT
			)
		century += GRID_YEARS

	# Where each earlier probe landed.
	for j in _decided:
		var probe_x := inner_x + _mids[j] * inner_w
		draw_line(Vector2(probe_x, TRACK_Y + 1.0), Vector2(probe_x, track_bottom - 1.0), Color(1.0, 1.0, 1.0, 0.55), 1.0)

	# One tick per level, at its own year. The destination's is bigger and
	# cyan; the one being left keeps a dim marker so the jump reads as a jump.
	for level in _years.size():
		var tick_x := inner_x + _year_pos(_years[level]) * inner_w
		var is_target := level == _target_index
		var is_origin := level == _from_index and not is_target
		var tick_len := 7.0 if is_target else 4.0
		var tick_color := CYAN if is_target else GOLD
		draw_line(
			Vector2(tick_x, track_bottom + 1.0), Vector2(tick_x, track_bottom + tick_len),
			tick_color, 2.0 if is_target else 1.0
		)
		if is_target:
			# A flag on the destination year, standing above the timeline.
			draw_line(Vector2(tick_x, TRACK_Y - 9.0), Vector2(tick_x, TRACK_Y), CYAN, 1.0)
			draw_rect(Rect2(tick_x + 1.0, TRACK_Y - 9.0, 5.0, 4.0), CYAN)
		elif is_origin:
			draw_rect(Rect2(tick_x - 1.5, TRACK_Y - 4.0, 3.0, 3.0), Color(GOLD, 0.7))

	# The player, hopping between years.
	var player_x := inner_x + _pos * inner_w
	var feet_y := TRACK_Y - 1.0 - sin(PI * _hop) * HOP_HEIGHT
	var body := Rect2(player_x - PLAYER_SIZE.x * 0.5, feet_y - PLAYER_SIZE.y, PLAYER_SIZE.x, PLAYER_SIZE.y)
	draw_rect(body.grow(1.0), OUTLINE)
	draw_rect(body, PLAYER_COLOR)

	# The year the player is standing in, carried above its head.
	if font != null:
		var tag := target_year_text() if _lock > 0.0 else str(_year_at(_pos))
		var tag_size := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_CENTER, -1.0, TAG_SIZE)
		var tag_x := clampf(player_x - tag_size.x * 0.5 - 3.0, 0.0, size.x - tag_size.x - 6.0)
		var tag_y := maxf(body.position.y - 13.0, 0.0)
		var tag_color := CYAN if _lock > 0.0 else GOLD
		draw_rect(Rect2(tag_x, tag_y, tag_size.x + 6.0, 11.0), Color(OUTLINE, 0.85))
		draw_string(
			font, Vector2(tag_x + 3.0, tag_y + 8.0), tag,
			HORIZONTAL_ALIGNMENT_CENTER, tag_size.x, TAG_SIZE, tag_color
		)

	# Lock-on pulse around the destination year.
	if _lock > 0.0:
		var target_x := inner_x + _target * inner_w
		var centre := Vector2(target_x, TRACK_Y + TRACK_HEIGHT * 0.5)
		draw_arc(centre, lerpf(3.0, 14.0, _lock), 0.0, TAU, 24, Color(CYAN, 1.0 - _lock), 1.5)
