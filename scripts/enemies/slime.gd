class_name Slime
extends Knight
## Level 1's slime: the Knight's fight, wearing the slime art and casting its
## guard instead of holding one.
##
## Almost all of the fight is inherited — patrol, engage, the guard that blocks
## from every side but overhead, the telegraphed swing, the parry that drops
## the guard for the punish window. **One rule differs from the Knight's**: the
## guard is a spell, not a plate, and winding up to swing spends it (see
## `shield_up()`), so a hit landed from `guard_drop_lead` before the sweep to
## the end of it gets through without a parry. Everything else that changes is
## what you look at:
##
## * **Defending** — a MagicBarrier raises a half-transparent panel on *both*
##   sides (the Knight's block was never one-sided; its single ColorRect shield
##   just drew it that way), and the body plays the `guard` loop: the
##   slimesword frames, the blade held inside the blob.
## * **Attacking** — the panels burst apart part-way through the windup, a beat
##   before the sword leaves the body and becomes the player's own sweep: a
##   SlashArc thrown over the active window. The dissolve is the real
##   telegraph, and the opening it leaves opens with it, not with the blade. There is no sword in hand to draw, so the
##   body drops to the plain `blob` loop, stretched over windup + sweep so the
##   wobble is the telegraph the raised sword used to be.
## * **Patrolling** — the plain `blob` loop, off the level clock.
##
## Nothing here calls play(): frames come from tick stamps through SpriteClock
## and the barrier's shimmer is clocked off the level time, so the whole thing
## rewinds with a recall and holds still during a time stop, in step with the
## hitboxes it illustrates (ARCHITECTURE.md sections 4 and 7).

@export_group("Guard")
## The even checker that reads as half transparent while the guard just sits
## there. The barrier is opaque pixels with holes dithered through it, not an
## alpha — see magic_barrier.gd.
@export_range(0.0, 1.0) var guard_solidity := 0.5
## Thicker while the spell gathers for a swing, right up until it is spent.
@export_range(0.0, 1.0) var charge_solidity := 0.8
## How long before the sweep the guard goes down. The slime can't hold the
## panels and throw the sweep at once, and it lets go first: this is the beat
## between the guard coming apart and the blade arriving, and the whole of the
## opening a player gets without parrying. Defaults to a touch more than
## `guard_fade_time`, so the panels are gone by the time the sweep lands.
@export var guard_drop_lead := 0.15
## How long the panels take to come apart once the guard drops. They lose
## pixels to the dither — outline included — rather than blinking out or
## fading to transparent, the same way SlashArc's slice dissipates.
@export var guard_fade_time := 0.14
## How many poses that dissolve is cut into. Chunky on purpose: a smooth ramp
## would be the one tweened thing among effects that all snap between frames.
@export var guard_fade_steps := 3
## How fast the barrier's shimmer steps through its poses.
@export var shimmer_fps := 8.0

## When the guard last went down, so the dissolve has something to run from.
## Kept here rather than derived, because the guard drops for three different
## reasons (a windup, a parry, losing sight of the player) and only the tick
## matters to the fade.
var guard_dropped_tick := NEVER
var _guard_was_up := false
## How solid the panels were on the frame they dropped, so the dissolve starts
## from what was on screen. A guard spent on a windup goes out from its charged
## thickness, not from the thinner resting one.
var _guard_dropped_from := 0.5

var _attack_sound_tick := NEVER

@onready var sprite: AnimatedSprite2D = $Body
@onready var barrier: MagicBarrier = $Barrier
@onready var slash_fx: SlashArc = $SlashFx
@onready var attack_sound: AudioStreamPlayer2D = $AttackSound
@onready var protect_sound: AudioStreamPlayer2D = $BlockSound


# --- The guard ---------------------------------------------------------------

## The one rule a slime doesn't inherit. A Knight's shield is a plate it holds
## through its own swing, so a parry is the only way past it; a slime's guard
## is the same magic the sweep is made of, and it can't hold both at once — so
## it lets go of the panels `guard_drop_lead` before the blade comes out, and
## is open from then until the sweep ends.
##
## Everything downstream follows from this one override: Knight.take_hit()
## blocks on shield_up(), and _pose_barrier() shows the panels on it. Parrying
## still works and still buys the longer `shield_break_time` opening, which is
## the whole of the punish window a Knight gives you.
func shield_up() -> bool:
	return super() and not _is_guard_spent()


## True from `guard_drop_lead` before the sweep to the end of it. The same
## window as _is_active(), opened early — a swing that hasn't reached its lead
## yet still has the guard up in front of it.
func _is_guard_spent() -> bool:
	if not is_swinging():
		return false
	var t := GameManager.ticks_since(attack_start_tick)
	return (t >= _ticks(maxf(swing_windup - guard_drop_lead, 0.0))
		and t < _ticks(swing_windup + swing_active))


# --- Visuals ----------------------------------------------------------------

## Overridden rather than left to _behave(), which Enemy skips while this slime
## is hit-stunned — a stunned slime still has its guard up and should still be
## drawn holding it.
func _update_visuals() -> void:
	super()
	_update_combat_visuals()


## The Knight's seam for "draw the fight". Its own version poses a ColorRect
## shield and a code-drawn sword, neither of which exists here.
func _update_combat_visuals() -> void:
	_pose_sprite()
	_pose_barrier()
	_pose_slash_fx()


## The only part of the Knight's layout a slime keeps: the reach of the swing
## follows the side it is facing.
func _position_combat_parts() -> void:
	sword_area.position.x = absf(sword_area.position.x) * direction


func _pose_sprite() -> void:
	var frames := sprite.sprite_frames
	# The slime art is drawn facing LEFT (unlike the player sheet), so the flip
	# is the mirror of the usual `direction < 0`. The hitbox and the sweep are
	# unaffected: those follow `direction` straight, toward the player.
	sprite.flip_h = direction > 0
	if is_swinging():
		# Stretched over windup + sweep rather than run at the clip's own fps,
		# so what you see winding up is the window you have to parry in.
		sprite.animation = &"blob"
		sprite.frame = SpriteClock.frame_over(frames, &"blob", attack_start_tick,
			swing_windup + swing_active)
		return
	var anim: StringName = &"guard" if shield_up() else &"blob"
	sprite.animation = anim
	# Both are loops, so SpriteClock reads them off the level clock and the
	# stamp goes unused.
	sprite.frame = SpriteClock.frame_for(frames, anim, NEVER)


## The panels are up for exactly as long as the block is — that is the point of
## reading shield_up() here rather than tracking the state twice — and for the
## fade after it, which is the only thing that outlives the block itself.
func _pose_barrier() -> void:
	var up := shield_up()
	if up != _guard_was_up:
		if not up:
			# Caught before the state moves on, so the dissolve can start from
			# the thickness that was actually on screen.
			_guard_dropped_from = _guard_solidity()
			guard_dropped_tick = GameManager.timeline_tick
		else:
			guard_dropped_tick = NEVER
		_guard_was_up = up
	if up:
		barrier.visible = true
		barrier.set_pose(_shimmer_step(), _guard_solidity())
		return
	_pose_guard_fade()


## The guard coming apart: `guard_fade_steps` poses that eat the interior and
## then the outline, so the panels dissolve where they stood instead of
## vanishing between one frame and the next. A negative elapsed is a drop in
## the undone future, part-way through a recall.
func _pose_guard_fade() -> void:
	var elapsed := GameManager.seconds_since(guard_dropped_tick)
	barrier.visible = (guard_dropped_tick != NEVER
		and elapsed >= 0.0 and elapsed < guard_fade_time)
	if not barrier.visible:
		return
	var last := maxi(guard_fade_steps, 1)
	var step := mini(int(elapsed / guard_fade_time * last), last - 1)
	# 1 -> 0 across the dissolve, one stop per pose.
	var left := 1.0 - float(step + 1) / last
	# The outline trails the interior: it is still legible on the last pose,
	# so the panel reads as breaking up rather than as an empty frame.
	barrier.set_pose(_shimmer_step(), _guard_dropped_from * left, lerpf(1.0, 0.25, 1.0 - left))


## Clocked off the level time, so the shimmer rewinds and freezes with
## everything else instead of running on real seconds.
func _shimmer_step() -> int:
	return int(GameManager.level_time_seconds() * shimmer_fps)


## Only two states left for a standing guard: the swing doesn't thin the
## panels, it spends them.
func _guard_solidity() -> float:
	return charge_solidity if _is_windup() else guard_solidity


## The player's slice of air, thrown over the sweep — the same effect on the
## same terms, just aimed by `direction` instead of by an input. It draws
## unrotated so its pixels stay on the grid, so the angle goes in as data.
func _pose_slash_fx() -> void:
	var elapsed := GameManager.seconds_since(attack_start_tick) - swing_windup
	slash_fx.visible = is_swinging() and elapsed >= 0.0 and elapsed < swing_active
	if slash_fx.visible:
		if attack_start_tick != _attack_sound_tick:
			attack_sound.pitch_scale = randf_range(0.85, 1.15)
			attack_sound.play()
			_attack_sound_tick = attack_start_tick
			
		slash_fx.set_pose(elapsed / swing_active, float(direction),
			0.0 if direction > 0 else PI)


# --- Recall and time stop ---------------------------------------------------

func on_time_stop_ended(frozen_ticks: int) -> void:
	super(frozen_ticks)
	guard_dropped_tick = _shift_stamp(guard_dropped_tick, frozen_ticks)


func on_recall_finished() -> void:
	super()
	guard_dropped_tick = _expire_future(guard_dropped_tick)
	# super() clears `engaged` and redraws, so a slime that was guarding has
	# already logged the drop and will dissolve from here — which is what a
	# rewound slime losing sight of the player should look like anyway.
	_guard_was_up = shield_up()

func take_hit(amount: int, from_position: Vector2) -> void:
	var blocked := shield_up()
	super(amount, from_position)
	
	if blocked:
		protect_sound.pitch_scale = randf_range(0.85, 1.15)
		protect_sound.play()
