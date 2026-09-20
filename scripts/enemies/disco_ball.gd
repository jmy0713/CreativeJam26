class_name DiscoBall
extends DJ
## Level 3's boss: a disco ball hanging in the middle of the arena. It keeps
## none of the DJ's attacks — no Vinyl throws, no Backup Dancer waves — and
## fights with three of its own, in a fixed rotation with `attack_rest`
## seconds of standing still between them, which is the window to hit it.
##
## **1, the spray.** `spray_waves` rings of `ring_bullets` slow bullets, each
## ring turned `wave_offset` of a gap from the last, so at the default half a
## gap every ring threads the holes the one before it left.
##
## **2, the lasers.** The ball rises out of the arena, then one beam sweeps
## each lane in turn, alternating direction — top left-to-right, middle
## right-to-left, and so on down. Each is announced by a warning line along
## its lane, and there is a gap after each sweep, so the attack is a run of
## "leave this lane" calls. The last lane is the ground, or standing on the
## floor would sit the whole attack out. Then the ball comes back down.
##
## **3, the machine gun.** A stream of fast bullets straight at the player
## for `gun_duration`, re-aimed every shot, with a small fixed spread. The
## spray asks you to find a gap and the lasers ask you to pick a lane; this
## one just asks you to keep moving.
##
## None of the three can be slashed or parried — see DiscoBullet and
## DiscoLaser. Every stamp is against GameManager.timeline_tick rather than a
## Timer, so the whole rotation rewinds with a recall and holds still through
## a parry time stop.
##
## Body is an AnimatedSprite2D looping the 3 fps "sparkle" animation; it spins
## up while an attack is charging, which is the tell that one is coming.

enum Attack { SPRAY, LASERS, GUN }

## Fixed spread for the machine gun, in multiples of `gun_spread`. A table
## rather than a roll, so a burst replayed by a recall is the same burst.
const GUN_SPREAD := [0.0, 0.62, -0.45, 0.24, -0.78, 0.4, -0.19, 0.57]

@export_group("Rotation")
## Standing still between attacks — the window to get a hit or two in.
@export var attack_rest := 2.5

@export_group("1 - Bullet Spray")
@export var bullet_scene: PackedScene
## Bullets in one ring. Their spacing is a full turn divided by this, so
## fewer bullets means wider gaps — the attack's real difficulty dial.
@export var ring_bullets := 12
@export var spray_waves := 4
## Charge before the first ring leaves the ball.
@export var spray_windup := 0.7
## Time between one ring leaving and the next. Times the speed, this is how
## far apart the rings sit on screen — keep the product wide enough that they
## read as separate rings and not one thick band.
@export var wave_interval := 0.8
## How far each ring is turned from the one before, as a fraction of the gap
## between two bullets. 0.5 puts every bullet exactly between two of the
## last ring's.
@export_range(0.0, 1.0) var wave_offset := 0.5
## Angle of the first ring's first bullet.
@export var ring_angle := 0.0
## Bullets start this far out, so they leave the ball's surface instead of
## appearing inside it. The ball's own collision circle is 36 (radius 24 at
## the scene's 1.5 scale), so anything under that spawns inside the boss.
@export var ring_radius := 42.0
@export var bullet_speed := 60.0
@export var bullet_damage := 1

@export_group("2 - Lasers")
@export var laser_scene: PackedScene
## Centre height of each beam, top lane first. These are the player's own
## centre standing on each tier (platform y, less 5.56 for the surface and
## 9.6 for half the player), not the platform's, so a beam covers whoever is
## standing in its lane and clears the tiers either side. The last is the
## ground, which is why there are four of them for three tiers.
@export var lane_ys: Array[float] = [104.8, 184.8, 264.8, 320.0]
## The lane's span. A beam starts and ends its own half-length plus
## `lane_margin` outside it, so a screen-wide beam is fully off one side
## before the sweep and fully off the other after it, instead of being seen
## appearing or cut off mid-lane.
@export var lane_left := 0.0
@export var lane_right := 640.0
@export var lane_margin := 24.0
## How far the ball climbs out of the arena, and how long each leg takes.
@export var rise_height := 300.0
@export var rise_time := 0.6
## Warning line before a beam, the sweep itself, and the pause after it.
## Telegraph plus gap is how long there is to change lanes.
@export var beam_telegraph := 0.45
@export var beam_sweep_time := 1.0
@export var beam_gap := 0.3
@export var laser_damage := 1

@export_group("3 - Machine Gun")
@export var gun_windup := 0.6
@export var gun_duration := 2.2
@export var gun_interval := 0.09
@export var gun_bullet_speed := 130.0
## Half-width of the spread, in degrees.
@export var gun_spread := 5.0
@export var gun_damage := 1
## Shots leave from here, out past the ball's own collision circle.
@export var gun_radius := 42.0

@export var windup_sparkle_speed := 3.0

## Which attack is running, or the one that runs next while resting.
var attack := Attack.SPRAY
## NEVER while resting; the tick the current attack began.
var attack_start_tick := NEVER
## The tick the last attack finished, which the rest is timed from.
var last_attack_tick := NEVER

## Rings fired, beams armed or shots fired, depending on the attack.
var _steps_done := 0
## Where the ball hangs when it is not away doing the laser attack.
var _home_position := Vector2.ZERO
## The layer it sits on while it is in the arena, dropped while it is away.
var _home_layer := 0

@onready var sprite: AnimatedSprite2D = $Body


func _ready() -> void:
	super()
	_home_position = global_position
	_home_layer = collision_layer


## The ball is placed, not walked: no gravity, no move_and_slide, and none of
## the DJ's attack updates.
func _physics_process(_delta: float) -> void:
	if alive and not is_stunned():
		_update_attacks()
	_apply_presence()
	_update_visuals()


## True while the ball has left the arena for the laser attack.
func is_away() -> bool:
	return attack == Attack.LASERS and attack_start_tick != NEVER


## A ball that has left the arena is not in the fight: it deals no contact
## damage and cannot be hit. Dropping the collision layer does both at once,
## since the player finds it through the Hurtbox and the SlashArea, and both
## look for layer 3. It matters on the way out and back as much as while it
## is gone — the climb passes straight through the top tier, so a player
## standing there used to eat a hit from a boss that was busy leaving.
##
## Derived from the attack state every frame rather than toggled on the way
## past, so a recall landing mid-attack cannot strand it on the wrong layer.
func _apply_presence() -> void:
	if not alive:
		return
	var want := 0 if is_away() else _home_layer
	if collision_layer != want:
		collision_layer = want


## True while an attack is charging and has not thrown anything yet — the
## window the sparkle spins up for.
func is_charging() -> bool:
	return attack_start_tick != NEVER and _steps_done == 0


func _update_visuals() -> void:
	super()
	sprite.speed_scale = windup_sparkle_speed if is_charging() else 1.0


# --- Rotation ---------------------------------------------------------------

func _update_attacks() -> void:
	var player := GameManager.player
	if player == null or player.health <= 0:
		if attack_start_tick != NEVER:
			_end_attack()
		return

	if attack_start_tick == NEVER:
		if GameManager.ticks_since(last_attack_tick) >= _ticks(attack_rest):
			_set_attack_state(attack, GameManager.timeline_tick, last_attack_tick, 0)
		return

	match attack:
		Attack.SPRAY: _run_spray()
		Attack.LASERS: _run_lasers()
		Attack.GUN: _run_gun(player)


## Back to resting, with the next attack in the rotation queued up.
func _end_attack() -> void:
	var next: Attack = ((attack + 1) % Attack.size()) as Attack
	_set_attack_state(next, NEVER, GameManager.timeline_tick, 0)


## Every change to the rotation goes through here so it can be undone, the
## same way Enemy.take_hit records a hit. Without it, a recall crossing an
## attack boundary would leave the boss part-way through the wrong attack.
func _set_attack_state(to_attack: Attack, start_tick: int, end_tick: int, steps: int) -> void:
	Recall.record(self, &"attack_state",
		_apply_attack_state.bind(attack, attack_start_tick, last_attack_tick, _steps_done))
	_apply_attack_state(to_attack, start_tick, end_tick, steps)


func _apply_attack_state(to_attack: Attack, start_tick: int, end_tick: int, steps: int) -> void:
	attack = to_attack
	attack_start_tick = start_tick
	last_attack_tick = end_tick
	_steps_done = steps


## Ticks since the current attack began.
func _elapsed() -> int:
	return GameManager.ticks_since(attack_start_tick)


# --- 1: the spray -----------------------------------------------------------

func _run_spray() -> void:
	var elapsed := _elapsed()
	# A frame that runs long can owe more than one ring; each still goes out
	# at its own angle, so the pattern never loses a step.
	while _steps_done < spray_waves and elapsed >= _spray_step_ticks(_steps_done):
		_fire_ring(_steps_done)
		_steps_done += 1
	if _steps_done >= spray_waves:
		_end_attack()


func _spray_step_ticks(index: int) -> int:
	return _ticks(spray_windup + wave_interval * index)


func _fire_ring(index: int) -> void:
	if bullet_scene == null or ring_bullets <= 0:
		return
	var step := TAU / ring_bullets
	var base := ring_angle + step * wave_offset * index
	for i in ring_bullets:
		_fire_bullet(base + step * i, bullet_speed, bullet_damage, ring_radius)


func _fire_bullet(angle: float, speed: float, damage: int, radius: float) -> void:
	if bullet_scene == null:
		return
	var bullet := bullet_scene.instantiate() as DiscoBullet
	if bullet == null:
		return
	get_parent().add_child(bullet)
	bullet.speed = speed
	bullet.damage = damage
	var heading := Vector2.from_angle(angle)
	var from := global_position + heading * radius
	bullet.launch(from, from + heading)


# --- 2: the lasers ----------------------------------------------------------

func _run_lasers() -> void:
	var elapsed := _elapsed()
	var lanes := lane_ys.size()
	while _steps_done < lanes and elapsed >= _lane_step_ticks(_steps_done):
		_arm_lane(_steps_done)
		_steps_done += 1
	_place_for_lasers(elapsed, lanes)
	if elapsed >= _laser_total_ticks(lanes):
		global_position = _home_position
		_end_attack()


## One lane's slot: its warning line starts here, and the next lane's starts
## a sweep and a gap later.
func _lane_step_ticks(index: int) -> int:
	return _ticks(rise_time + _lane_cycle() * index)


func _lane_cycle() -> float:
	return beam_telegraph + beam_sweep_time + beam_gap


## Rise, every lane, then the drop back home.
func _laser_total_ticks(lanes: int) -> int:
	return _ticks(rise_time + _lane_cycle() * lanes + rise_time)


## The ball's height is a function of how far into the attack it is, so a
## recall landing mid-attack puts it back on the arc with no state to fix.
func _place_for_lasers(elapsed: int, lanes: int) -> void:
	var t := GameManager.ticks_to_seconds(elapsed)
	var up_for := rise_time + _lane_cycle() * lanes
	var climb := 1.0
	if t < rise_time:
		climb = t / maxf(rise_time, 0.001)
	elif t >= up_for:
		climb = 1.0 - (t - up_for) / maxf(rise_time, 0.001)
	global_position = _home_position - Vector2(0.0, rise_height * clampf(climb, 0.0, 1.0))


## Lane 0 runs left to right, lane 1 back the other way, and so on down.
func _arm_lane(index: int) -> void:
	if laser_scene == null or index >= lane_ys.size():
		return
	var beam := laser_scene.instantiate() as DiscoLaser
	if beam == null:
		return
	get_parent().add_child(beam)
	beam.damage = laser_damage
	var rightwards := index % 2 == 0
	# The beam's own length sets how far off screen it has to start, so
	# changing beam_length in the laser scene never breaks the sweep.
	var clear := beam.half_length() + lane_margin
	var from_x := lane_left - clear if rightwards else lane_right + clear
	var to_x := lane_right + clear if rightwards else lane_left - clear
	var centre := Vector2((lane_left + lane_right) / 2.0, lane_ys[index])
	beam.arm(centre, lane_right - lane_left, from_x, to_x, beam_telegraph, beam_sweep_time)


# --- 3: the machine gun -----------------------------------------------------

func _run_gun(player: Player) -> void:
	var elapsed := _elapsed()
	var shots := _gun_shots()
	while _steps_done < shots and elapsed >= _gun_step_ticks(_steps_done):
		_fire_at_player(player, _steps_done)
		_steps_done += 1
	if _steps_done >= shots:
		_end_attack()


func _gun_step_ticks(index: int) -> int:
	return _ticks(gun_windup + gun_interval * index)


func _gun_shots() -> int:
	return maxi(int(gun_duration / maxf(gun_interval, 0.001)), 1)


func _fire_at_player(player: Player, index: int) -> void:
	var to_player := player.global_position - global_position
	if to_player == Vector2.ZERO:
		to_player = Vector2.RIGHT
	var spread: float = GUN_SPREAD[index % GUN_SPREAD.size()] * gun_spread
	_fire_bullet(to_player.angle() + deg_to_rad(spread),
		gun_bullet_speed, gun_damage, gun_radius)


# --- Recall / time stop -----------------------------------------------------

func on_recall_finished() -> void:
	super()
	attack_start_tick = _expire_future(attack_start_tick)
	last_attack_tick = _expire_future(last_attack_tick)
	# Anything thrown in the undone future went with the recall, so work out
	# again how much of this attack has happened by now and let the rest run
	# on the way back — a rewound attack plays out a second time.
	_steps_done = 0 if attack_start_tick == NEVER else _steps_due(_elapsed())
	if attack != Attack.LASERS or attack_start_tick == NEVER:
		global_position = _home_position


## How many steps of the current attack an attack `elapsed` ticks old owes.
func _steps_due(elapsed: int) -> int:
	var due := 0
	match attack:
		Attack.SPRAY:
			while due < spray_waves and elapsed >= _spray_step_ticks(due):
				due += 1
		Attack.LASERS:
			while due < lane_ys.size() and elapsed >= _lane_step_ticks(due):
				due += 1
		Attack.GUN:
			while due < _gun_shots() and elapsed >= _gun_step_ticks(due):
				due += 1
	return due


func on_time_stop_ended(frozen_ticks: int) -> void:
	super(frozen_ticks)
	attack_start_tick = _shift_stamp(attack_start_tick, frozen_ticks)
	last_attack_tick = _shift_stamp(last_attack_tick, frozen_ticks)
