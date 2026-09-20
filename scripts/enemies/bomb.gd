class_name Bomb
extends Fireball
## What the plane drops instead of the dragon's Fireball. Released rather than
## fired: it leaves the plane with only the forward drift it was carrying and
## gravity does the rest, tipping nose-down as it falls, then goes off where
## it lands and leaves the same FirePatch behind.
##
## The Dragon takes the projectile as an export (`fireball_scene`), so the
## plane is the same enemy pointed at this scene — nothing in dragon.gd knows
## the difference.
##
## Position is arithmetic on the launch stamp rather than an accumulated
## velocity, so the arc is exactly reproducible: it rewinds with a recall and
## holds still through a time stop like everything else here.

const NEVER := GameManager.NEVER

## Area2D already owns `gravity` (its own area physics override), hence the
## name.
@export var fall_acceleration := 520.0
## Bounds on the estimated fall used to work the drift out. The minimum is
## what stops a shallow drop — a plane passing low over a ledge — from asking
## for an absurd sideways speed.
@export var min_fall_time := 0.45
@export var max_fall_time := 2.0
## Hard cap on the sideways speed. A bomb is dropped, not fired: past this it
## stops reading as falling, and a plane that can always place one exactly
## under the player is not one you can step out from under.
@export var max_drift := 150.0
## How long the blast stays up after it lands.
@export var blast_time := 0.26

## Horizontal drift, from the plane's aim; the fall is gravity alone.
var _drift := 0.0
var _fall_time := 0.0
var _explode_tick := NEVER

@onready var shell: PixelBomb = $Shell
@onready var blast: PuffCloud = $Blast


## Released towards `landing_position`: the height sets the fall time, and the
## drift is whatever gets it there in that time.
func launch_to_ground(from_position: Vector2, landing_position: Vector2) -> void:
	# The player is still handled by Projectile; the world is checked by hand
	# so the bomb stops on walls as well as floors.
	collision_mask = 2
	_origin = from_position
	_landing = landing_position
	var drop := maxf(landing_position.y - from_position.y, 1.0)
	_fall_time = clampf(sqrt(2.0 * drop / maxf(fall_acceleration, 1.0)),
		min_fall_time, max_fall_time)
	_drift = clampf((landing_position.x - from_position.x) / _fall_time,
		-max_drift, max_drift)
	lifetime = maxf(lifetime, max_fall_time + blast_time + 0.5)
	launch(from_position, landing_position)


func _physics_process(_delta: float) -> void:
	if not alive:
		return
	if _explode_tick != NEVER:
		_run_blast()
		return
	var t := GameManager.seconds_since(_launch_tick)
	var previous := global_position
	global_position = _origin + Vector2(_drift * t, 0.5 * fall_acceleration * t * t)
	# Nose follows the arc over, so it tips downwards as it picks up speed.
	shell.set_angle(Vector2(_drift, fall_acceleration * t).angle())
	var hit := _check_world_collision(previous, global_position)
	if hit:
		global_position = hit.position
		_land(hit.position)
		return
	if t >= lifetime:
		_vanish()


func _run_blast() -> void:
	var t := GameManager.seconds_since(_explode_tick) / maxf(blast_time, 0.001)
	if t >= 1.0:
		_vanish()
		return
	blast.set_pose(t)


## Goes off where it landed: the blast takes over from the shell, the Dragon
## hears `landed` and drops its FirePatch, and contact damage stops — the
## patch is what hurts from here.
func _land(at: Vector2) -> void:
	if _explode_tick != NEVER:
		return
	_explode_tick = GameManager.timeline_tick
	global_position = at
	shell.visible = false
	blast.visible = true
	blast.set_pose(0.0)
	set_deferred(&"monitoring", false)
	landed.emit(at)


func on_time_stop_ended(frozen_ticks: int) -> void:
	super(frozen_ticks)
	if _explode_tick != NEVER:
		_explode_tick += frozen_ticks


func on_recall_finished() -> void:
	# A blast in the undone future hasn't happened yet: put the shell back in
	# the air before Projectile decides whether this bomb still exists.
	if _explode_tick != NEVER and _explode_tick > GameManager.timeline_tick:
		_explode_tick = NEVER
		shell.visible = true
		blast.visible = false
		set_deferred(&"monitoring", true)
	super()
