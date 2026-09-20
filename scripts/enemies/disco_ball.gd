class_name DiscoBall
extends DJ
## Level 3's boss: a disco ball hanging in the middle of the arena. It keeps
## none of the DJ's attacks — no Vinyl throws, no Backup Dancer waves — and
## fights with bullet hell fired from where it hangs. Two more attacks are
## still to come; this is the first.
##
## **Attack 1, the spray.** `burst_waves` rings of `ring_bullets` slow
## bullets, fired one after another, each ring turned `wave_offset` of a gap
## from the ring before it — at the default half a gap, every bullet threads
## the hole the last ring left, so standing in a gap only buys you one wave.
## The bullets are slow on purpose: they are meant to be outrun, cut across
## and stood between, and none of them can be slashed or parried (see
## DiscoBullet), so the whole attack is footwork.
##
## The rings never track the player. The pattern is the same every burst,
## which is what makes a bullet hell learnable rather than a coin flip.
##
## Every stamp is against GameManager.timeline_tick rather than a Timer, so
## a burst rewinds and fires again with a recall, and holds still through a
## parry time stop, like the rest of the fight.
##
## Body is an AnimatedSprite2D looping the 3 fps "sparkle" animation; it
## spins up while a burst charges, and that spin-up is the only tell.

@export_group("Bullet Spray")
@export var bullet_scene: PackedScene
## Bullets in one ring. The spacing is a full turn divided by this, so fewer
## bullets means wider gaps to stand in — this is the attack's difficulty
## dial, far more than the speed is.
@export var ring_bullets := 12
## Rings per burst.
@export var burst_waves := 4
## Charge before the first ring of a burst leaves the ball.
@export var burst_windup := 0.7
## Time between one ring leaving and the next. Times the speed, this is how
## far apart the rings sit on screen — keep the product wide enough that
## they read as separate rings and not one thick band.
@export var wave_interval := 0.8
## Rest between the last ring of a burst and the next burst's charge.
@export var burst_interval := 3.0
## How far each ring is turned from the one before, as a fraction of the gap
## between two bullets. 0.5 puts every bullet exactly between two of the
## last ring's, so odd and even rings alternate between two fixed patterns.
@export_range(0.0, 1.0) var wave_offset := 0.5
## Angle of the first ring's first bullet.
@export var ring_angle := 0.0
## Bullets start this far out, so they leave the ball's surface instead of
## appearing inside it. The ball's own collision circle is 36 (radius 24 at
## the scene's 1.5 scale), so anything under that spawns inside the boss.
@export var ring_radius := 42.0
@export var bullet_speed := 60.0
@export var bullet_damage := 1

@export var windup_sparkle_speed := 3.0

## NEVER while resting; the tick the current burst started charging on.
var burst_start_tick := NEVER
## The tick the last burst's final ring left, which the rest is timed from.
var last_burst_tick := NEVER

## Rings of the current burst already in the air.
var _waves_fired := 0

@onready var sprite: AnimatedSprite2D = $Body


## The ball hangs where it is placed: no gravity, no move_and_slide, and
## none of the DJ's attack updates.
func _physics_process(_delta: float) -> void:
	if alive and not is_stunned():
		_update_bullet_spray()
	_update_visuals()


## True while a burst is charging and its first ring has not left yet — the
## window the sparkle spins up for.
func is_charging_burst() -> bool:
	return burst_start_tick != NEVER and _waves_fired == 0


func _update_visuals() -> void:
	super()
	sprite.speed_scale = windup_sparkle_speed if is_charging_burst() else 1.0


# --- Attack 1: the spray ----------------------------------------------------

func _update_bullet_spray() -> void:
	var player := GameManager.player
	if player == null or player.health <= 0:
		burst_start_tick = NEVER
		_waves_fired = 0
		return

	if burst_start_tick == NEVER:
		if GameManager.ticks_since(last_burst_tick) >= _ticks(burst_interval):
			burst_start_tick = GameManager.timeline_tick
			_waves_fired = 0
		return

	var elapsed := GameManager.ticks_since(burst_start_tick)
	# A frame that runs long can owe more than one ring; each still goes out
	# at its own angle, so the pattern never loses a step.
	while _waves_fired < burst_waves and elapsed >= _wave_ticks(_waves_fired):
		_fire_ring(_waves_fired)
		_waves_fired += 1
	if _waves_fired >= burst_waves:
		last_burst_tick = GameManager.timeline_tick
		burst_start_tick = NEVER
		_waves_fired = 0


## Ticks from the start of a burst to ring `index` leaving.
func _wave_ticks(index: int) -> int:
	return _ticks(burst_windup + wave_interval * index)


func _fire_ring(index: int) -> void:
	if bullet_scene == null or ring_bullets <= 0:
		return
	var step := TAU / ring_bullets
	var base := ring_angle + step * wave_offset * index
	for i in ring_bullets:
		_fire_bullet(base + step * i)


func _fire_bullet(angle: float) -> void:
	var bullet := bullet_scene.instantiate() as DiscoBullet
	if bullet == null:
		return
	get_parent().add_child(bullet)
	bullet.speed = bullet_speed
	bullet.damage = bullet_damage
	var heading := Vector2.from_angle(angle)
	var from := global_position + heading * ring_radius
	bullet.launch(from, from + heading)


# --- Recall / time stop -----------------------------------------------------

func on_recall_finished() -> void:
	super()
	burst_start_tick = _expire_future(burst_start_tick)
	last_burst_tick = _expire_future(last_burst_tick)
	# Rings from the undone future went with the recall, so work out again
	# how much of the burst has actually happened by now and let the rest
	# fire on the way back — a rewound burst plays out a second time.
	_waves_fired = 0 if burst_start_tick == NEVER \
		else _waves_due(GameManager.ticks_since(burst_start_tick))


## How many rings of a burst `elapsed` ticks old should be in the air.
func _waves_due(elapsed: int) -> int:
	var due := 0
	while due < burst_waves and elapsed >= _wave_ticks(due):
		due += 1
	return due


func on_time_stop_ended(frozen_ticks: int) -> void:
	super(frozen_ticks)
	burst_start_tick = _shift_stamp(burst_start_tick, frozen_ticks)
	last_burst_tick = _shift_stamp(last_burst_tick, frozen_ticks)
