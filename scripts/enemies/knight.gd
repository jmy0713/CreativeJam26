class_name Knight
extends Walker
## Hollow Knight "shield fool" style enemy: patrols like a Walker, but when
## the player is nearby it turns to face them and raises a shield that blocks
## any hit landing on its front side. Periodically it lowers the shield to
## swing its sword, dealing damage if the player is in reach; the swing
## window is also its one vulnerable moment (front hits land normally).
##
## Facing/patrol direction is shared: `direction` (from Walker) is repurposed
## as the shield-facing side while engaged.

const NEVER := GameManager.NEVER

@export_group("Combat")
## How far away (and how much vertical offset) counts as "sees the player".
@export var detection_range := 66.7
@export var detection_height := 25.0
## Stops closing the distance once this close, so the sword can reach.
@export var attack_range := 12.8
@export var approach_speed := 19.4
@export var swing_windup := 0.35
@export var swing_active := 0.15
## Shield goes back up for at least this long after a swing before the next one.
@export var swing_cooldown := 1.1
@export var sword_damage := 1

var engaged := false
var attack_start_tick := NEVER
var last_swing_end_tick := NEVER
var _swing_hit_player := false

@onready var sword_area: Area2D = $SwordArea
@onready var sword_visual: ColorRect = $SwordArea/SwordVisual
@onready var shield_visual: ColorRect = $ShieldVisual


func _behave(delta: float) -> void:
	var player := GameManager.player
	engaged = player != null and player.health > 0 and _can_see(player)

	if engaged:
		var dx := player.global_position.x - global_position.x
		direction = 1 if dx >= 0.0 else -1
		if is_swinging():
			velocity.x = move_toward(velocity.x, 0.0, 250.0 * delta)
		elif absf(dx) > attack_range:
			velocity.x = signf(dx) * approach_speed
		else:
			velocity.x = move_toward(velocity.x, 0.0, 250.0 * delta)
		_update_attack(player)
	else:
		attack_start_tick = NEVER
		_swing_hit_player = false
		super(delta)

	_position_combat_parts()
	_update_combat_visuals()


func is_swinging() -> bool:
	return attack_start_tick != NEVER


## True while the shield is up and would block a hit from the front.
func shield_up() -> bool:
	return engaged and not is_swinging()


func take_hit(damage: int, from_position: Vector2) -> void:
	if not alive:
		return
	if shield_up() and _is_frontal(from_position):
		# Blocked: a brief clang stagger, but no damage and no death check.
		last_hit_tick = GameManager.timeline_tick
		return
	super(damage, from_position)


func on_recall_finished() -> void:
	super()
	var now := GameManager.timeline_tick
	if attack_start_tick > now:
		attack_start_tick = NEVER
	if last_swing_end_tick > now:
		last_swing_end_tick = NEVER
	engaged = false
	_swing_hit_player = false
	_update_combat_visuals()


# --- Internals ----------------------------------------------------------

func _can_see(player: Player) -> bool:
	var offset := player.global_position - global_position
	return absf(offset.x) <= detection_range and absf(offset.y) <= detection_height


func _is_frontal(from_position: Vector2) -> bool:
	var side := signf(from_position.x - global_position.x)
	return side == 0.0 or side == float(direction)


func _is_windup() -> bool:
	return is_swinging() and GameManager.ticks_since(attack_start_tick) < _ticks(swing_windup)


func _is_active() -> bool:
	if not is_swinging():
		return false
	var t := GameManager.ticks_since(attack_start_tick)
	return t >= _ticks(swing_windup) and t < _ticks(swing_windup + swing_active)


func _update_attack(player: Player) -> void:
	if is_swinging():
		if _is_active() and not _swing_hit_player:
			for node in sword_area.get_overlapping_bodies():
				if node == player:
					player.take_damage(sword_damage, global_position)
					_swing_hit_player = true
					break
		if GameManager.ticks_since(attack_start_tick) >= _ticks(swing_windup + swing_active):
			attack_start_tick = NEVER
			last_swing_end_tick = GameManager.timeline_tick
		return

	var in_reach := absf(player.global_position.x - global_position.x) <= attack_range + 3.3
	if in_reach and GameManager.ticks_since(last_swing_end_tick) >= _ticks(swing_cooldown):
		attack_start_tick = GameManager.timeline_tick
		_swing_hit_player = false


func _position_combat_parts() -> void:
	sword_area.position.x = 10.6 * direction
	shield_visual.position.x = 4.4 * direction


func _update_combat_visuals() -> void:
	shield_visual.visible = shield_up()
	sword_visual.visible = is_swinging()
	if _is_windup():
		sword_visual.color = Color(1, 0.6, 0.2, 0.6)
	elif _is_active():
		sword_visual.color = Color(1, 0.9, 0.3, 0.9)


func _ticks(seconds: float) -> int:
	return GameManager.seconds_to_ticks(seconds)
