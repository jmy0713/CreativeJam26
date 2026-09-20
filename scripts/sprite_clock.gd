class_name SpriteClock
## Drives an AnimatedSprite2D from the timeline instead of play().
##
## Nothing that uses this ever calls play(): a frame index is derived from a
## tick stamp every physics frame, so sprites rewind with a recall and hold
## still during a time stop, exactly like the hitboxes they illustrate.
##
## Looping animations ride the level clock, so they rewind too. One-shots count
## from their own stamp and hold the last frame once they run out, which is how
## an action that outlasts its animation (an attack's recovery, a long fall)
## keeps the pose instead of snapping back to idle.
##
## Shared by Player and Echo, which wear the same sheet.


## Frame index to show for `anim` right now, given when it started.
static func frame_for(frames: SpriteFrames, anim: StringName, stamp: int) -> int:
	var count := frames.get_frame_count(anim)
	var fps := frames.get_animation_speed(anim)
	if frames.get_animation_loop(anim):
		return posmod(int(GameManager.level_time_seconds() * fps), count)
	return mini(int(maxf(GameManager.seconds_since(stamp), 0.0) * fps), count - 1)


## Like frame_for(), but the clip freezes on `hold_frame` for `hold_seconds`
## before the rest of it plays out. For a pose gameplay wants to linger on:
## the down slash's blade-down frame stays up for as long as the plunge reads
## for, however few frames the art spends on it.
static func frame_for_held(frames: SpriteFrames, anim: StringName, stamp: int,
		hold_frame: int, hold_seconds: float) -> int:
	var count := frames.get_frame_count(anim)
	var fps := frames.get_animation_speed(anim)
	if hold_seconds <= 0.0 or count <= 0 or fps <= 0.0:
		return frame_for(frames, anim, stamp)
	var held := clampi(hold_frame, 0, count - 1)
	var elapsed := maxf(GameManager.seconds_since(stamp), 0.0)
	var hold_start := held / fps
	if elapsed < hold_start:
		return mini(int(elapsed * fps), count - 1)
	if elapsed < hold_start + hold_seconds:
		return held
	# Past the hold, rejoin the clip where it paused.
	return mini(int((elapsed - hold_seconds) * fps), count - 1)


## Frame index for an animation stretched (or squeezed) to fill `duration`
## instead of running at the resource's own fps. For an action whose timing is
## set by gameplay rather than by the clip: an enemy swing has to telegraph for
## as long as its windup lasts, however many frames the art happens to have.
static func frame_over(frames: SpriteFrames, anim: StringName, stamp: int, duration: float) -> int:
	var count := frames.get_frame_count(anim)
	var t := clampf(GameManager.seconds_since(stamp) / maxf(duration, 0.001), 0.0, 1.0)
	return mini(int(t * count), count - 1)


## How long `anim` runs at its own speed. Frame counts and fps live in the
## SpriteFrames resource alone; read them back rather than restating them.
static func seconds(frames: SpriteFrames, anim: StringName) -> float:
	return frames.get_frame_count(anim) / frames.get_animation_speed(anim)
