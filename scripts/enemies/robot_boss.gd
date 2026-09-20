class_name RobotBoss
extends Robot
## Mini-boss guard-bot: same swing moveset as Robot (see Robot for that, and
## for how it is animated), plus laser eyes. Bigger, and it raises its blade
## overhead (`windup_heavy`) before it cuts down, where a regular robot only
## cocks it back.
##
## LASER: while engaged, not already busy (punching or lasering) and with a
## clear line of sight, it periodically charges up — its arm comes up and the
## cannon glows (the `shot` clip), a telegraph line shows exactly where the shot
## will go — then fires a Laser from the cannon (`laser_muzzle`) straight at
## wherever the player was standing when the charge started (so the beam
## itself is dodgeable: moving out of the telegraphed line during the charge
## is enough). It won't start a charge through a wall.
##
## REFLECT: slashing a Laser doesn't destroy it like a normal projectile —
## it reverses direction and switches to targeting enemies (see Laser). A
## reflected laser that reaches this robot damages it like any other hit
## (Laser calls hit_through_guard(), which is now just take_hit()).
##
## Same tick-stamp / recall / time-stop discipline as Robot: everything is a
## stamp, shifted in on_time_stop_ended(), cleared in on_recall_finished().

## The `shot` clip: frames 0-5 are the arm coming up and the cannon charging,
## and are stretched over `laser_windup`. Frame 6 is the burst, on screen as the
## beam leaves; frame 7 is the arm held out afterwards.
const SHOT_CHARGE_FRAMES := 6
const SHOT_BURST_FRAME := 6
const SHOT_RECOVER_FRAME := 7
## How long the burst frame shows before the recovery frame takes over.
const SHOT_BURST_TIME := 0.1

@export_group("Laser")
@export var laser_scene: PackedScene
## Glow + telegraph line before the shot; the beam itself is instant.
@export var laser_windup := 0.7
## Minimum time between laser shots, start to start.
@export var laser_cooldown := 2.4
@export var laser_speed := 155.6
@export var laser_damage := 1
## Where the beam leaves the cannon (right-facing; mirrored by `direction`),
## measured from the boss's origin. Also where the telegraph line starts.
@export var laser_muzzle := Vector2(22.0, -22.0)
## How long the arm stays out after the shot.
@export var laser_follow_time := 0.25

var laser_start_tick := NEVER
var last_laser_tick := NEVER
## Player position captured when the charge starts; the beam is fired at
## this fixed point regardless of where the player moves to during the charge.
var _laser_aim := Vector2.ZERO

## Optional telegraph line from the eye to the aim point. Safe to omit from
## the scene (get_node_or_null), same pattern as DJ's deck_glow.
@onready var laser_telegraph: Line2D = get_node_or_null("LaserTelegraph")
@onready var laser_sound: AudioStreamPlayer2D = $LaserSound


## True while charging or the beam is out (the shot itself is instantaneous,
## so this really only covers the charge, but kept as its own predicate for
## clarity and future use).
func is_lasering() -> bool:
	return laser_start_tick != NEVER


func is_busy() -> bool:
	return super() or is_lasering()


func _can_start_punch() -> bool:
	return super() and not is_lasering()


func _update_attack(player: Player) -> void:
	if is_lasering():
		if GameManager.ticks_since(laser_start_tick) >= _ticks(laser_windup):
			_fire_laser()
			laser_start_tick = NEVER
			last_laser_tick = GameManager.timeline_tick
		return

	super(player)

	# Only start a charge once the punch logic above didn't just claim this
	# frame (is_busy() covers is_punching() too), and only with a clear shot.
	if not is_busy() and GameManager.ticks_since(last_laser_tick) >= _ticks(laser_cooldown) \
			and _has_line_of_sight(player):
		laser_start_tick = GameManager.timeline_tick
		_laser_aim = player.global_position


func _cancel_attacks() -> void:
	super()
	laser_start_tick = NEVER


## Getting hit interrupts a charge too, same as it interrupts a punch.
func _on_damaged() -> void:
	super()
	laser_start_tick = NEVER


func on_time_stop_ended(frozen_ticks: int) -> void:
	super(frozen_ticks)
	laser_start_tick = _shift_stamp(laser_start_tick, frozen_ticks)
	last_laser_tick = _shift_stamp(last_laser_tick, frozen_ticks)


func on_recall_finished() -> void:
	super()
	laser_start_tick = _expire_future(laser_start_tick)
	last_laser_tick = _expire_future(last_laser_tick)


func _update_combat_visuals() -> void:
	super()
	var charging := is_lasering()
	if laser_telegraph:
		laser_telegraph.visible = charging
		if charging:
			laser_telegraph.points = PackedVector2Array([_muzzle_local(), to_local(_laser_aim)])


## The laser's own poses: the arm comes up and the cannon charges across the
## windup, the burst frame shows as the beam leaves, then the arm is held out.
func _pose_special() -> bool:
	if is_lasering():
		var t := clampf(GameManager.ticks_to_seconds(_pose_tick - laser_start_tick) / maxf(laser_windup, 0.001), 0.0, 1.0)
		_show(&"shot", mini(int(t * SHOT_CHARGE_FRAMES), SHOT_CHARGE_FRAMES - 1))
		return true
	var since := _pose_tick - last_laser_tick
	if since < 0:
		return false
	var seconds := GameManager.ticks_to_seconds(since)
	if seconds < SHOT_BURST_TIME:
		_show(&"shot", SHOT_BURST_FRAME)
		return true
	if seconds < laser_follow_time:
		_show(&"shot", SHOT_RECOVER_FRAME)
		return true
	return false


## The cannon's mouth relative to the boss, on the side it is facing.
func _muzzle_local() -> Vector2:
	return Vector2(laser_muzzle.x * direction, laser_muzzle.y)


## False when world geometry sits between the boss and the player. Without
## it the boss charges and fires straight through level 2's middle wall.
## Only checked when the charge STARTS — once it is committed the shot is
## aimed at a fixed point, and stepping out of the line is the dodge.
func _has_line_of_sight(player: Player) -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, player.global_position)
	# World only. The boss sits on the enemy layer, so it can't block itself.
	query.collision_mask = 1
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _fire_laser() -> void:
	if laser_scene == null:
		return
	var laser := laser_scene.instantiate() as Laser
	if laser == null:
		return
	get_parent().add_child(laser)
	laser.speed = laser_speed
	laser.damage = laser_damage
	laser.launch(global_position + _muzzle_local(), _laser_aim)
	laser_sound.play()
