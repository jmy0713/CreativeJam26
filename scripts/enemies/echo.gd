class_name Echo
extends Walker
## The echo/clone spawned when the player recalls. Buffed version of Walker
## with double jump, increased speed, and chases the player.

@export var jump_velocity := -244.4
@export var double_jump_velocity := -200.0
@export var chase_range := 300.0  # How far away the echo will chase from

var air_jumps_left := 0
var max_air_jumps := 1
var last_floor_tick := GameManager.NEVER


func _ready() -> void:
	super()
	air_jumps_left = max_air_jumps
	# Increase speed from default 38.8 to ~77.6 (double)
	speed = 77.6


func _behave(delta: float) -> void:
	# Chase the player if in range
	_chase_player()
	
	# Handle jump logic
	_handle_jump()
	
	# Apply gravity
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
	else:
		last_floor_tick = GameManager.timeline_tick
		air_jumps_left = max_air_jumps
	
	# Wall/ledge turning logic (from parent Walker)
	if is_on_wall() or (is_on_floor() and not ledge_check.is_colliding()):
		direction = -direction
	ledge_check.position.x = absf(ledge_check.position.x) * direction
	velocity.x = direction * speed


func _chase_player() -> void:
	# Chase the player if they're in range
	if GameManager.player == null:
		return
	
	var distance_to_player := global_position.distance_to(GameManager.player.global_position)
	if distance_to_player > chase_range:
		return
	
	# Move towards the player
	var player_direction := signf(GameManager.player.global_position.x - global_position.x)
	if player_direction != 0.0:
		direction = player_direction
	
	# Jump if player is above us
	var player_above := GameManager.player.global_position.y < global_position.y - 30.0
	if player_above and is_on_floor():
		velocity.y = jump_velocity
		last_floor_tick = GameManager.NEVER


func _handle_jump() -> void:
	# Echo randomly jumps to make it more challenging
	var should_jump := randf() < 0.01  # 1% chance per frame to attempt random jump
	
	if should_jump:
		if is_on_floor():
			velocity.y = jump_velocity
			last_floor_tick = GameManager.NEVER
		elif air_jumps_left > 0:
			velocity.y = double_jump_velocity
			air_jumps_left -= 1


func recall_sample() -> Dictionary:
	var sample := super()
	sample.air_jumps_left = air_jumps_left
	sample.last_floor_tick = last_floor_tick
	return sample


func apply_recall_sample(sample: Dictionary) -> void:
	super(sample)
	air_jumps_left = sample.get("air_jumps_left", max_air_jumps)
	last_floor_tick = sample.get("last_floor_tick", GameManager.NEVER)


func on_recall_finished() -> void:
	super()
	air_jumps_left = max_air_jumps
	last_floor_tick = GameManager.NEVER
