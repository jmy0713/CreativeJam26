class_name DashGhosts
extends Node2D
## The trail a dash leaves behind: a few silhouettes of the player standing
## where he was a moment ago, each stepping down a tone ramp as it ages.
##
## Same house rules as the other effects drawn here. The silhouettes are flat
## and fully opaque (`shaders/silhouette.gdshader` — modulate can only
## multiply, so it would tint the sprite rather than flatten it), they fade by
## stepping down `tones` rather than by going transparent, and they carry no
## z_index of their own: they layer with the player, and a node that leaves
## his z ends up behind the level's foreground tilemaps.
##
## There is no history buffer. A dash runs at a constant velocity, so where
## the player was `n` seconds ago is just arithmetic, which means the trail is
## a pure function of the dash's tick stamp and rewinds with a recall and
## freezes with a time stop for free.

const SILHOUETTE := preload("res://shaders/silhouette.gdshader")

## How many silhouettes trail the player.
@export var ghosts := 3
## Seconds between one silhouette and the next, which is what sets how far
## apart they sit.
@export var spacing := 0.035
## How long each silhouette lasts once it has been laid down.
@export var life := 0.17
## The clip a ghost wears — a dash always poses the player the same way.
@export var anim := &"dash"
## Tone ramp, brightest first. A ghost starts at the top and steps down as it
## ages, so the trail runs bright at the player and dark at the tail.
@export var tones: Array[Color] = [
	Color(1, 1, 1, 1),
	Color(0.62, 0.7, 1, 1),
	Color(0.29, 0.33, 0.62, 1),
]

var _ghosts: Array[AnimatedSprite2D] = []
## The player's own sprite, for the frames and the transform the ghosts copy.
var _source: AnimatedSprite2D = null


func _ready() -> void:
	for i in maxi(ghosts, 0):
		var ghost := AnimatedSprite2D.new()
		ghost.visible = false
		var material := ShaderMaterial.new()
		material.shader = SILHOUETTE
		ghost.material = material
		add_child(ghost)
		_ghosts.append(ghost)


## Hands over the sprite the ghosts are copies of. Called once by the owner.
func bind(source: AnimatedSprite2D) -> void:
	_source = source
	for ghost in _ghosts:
		ghost.sprite_frames = source.sprite_frames
		ghost.offset = source.offset


## How long the whole trail lasts, from the start of the dash until the last
## silhouette has gone. The owner stops posing after this.
func trail_seconds() -> float:
	return ghosts * spacing + life


func clear() -> void:
	for ghost in _ghosts:
		ghost.visible = false


## Lays the trail out for a dash that started `elapsed` seconds ago at
## `origin` and runs at `velocity` for `duration`. `reached` is where the
## player actually is now, which caps how far down the path a ghost may sit:
## a dash into a wall stops the body while its velocity stays up, and without
## the cap the trail would carry on through the wall.
func set_trail(elapsed: float, origin: Vector2, reached: Vector2, velocity: Vector2,
		duration: float, facing: float) -> void:
	if _source == null:
		return
	var covered := (reached - origin).length()
	for i in _ghosts.size():
		var ghost := _ghosts[i]
		# Laid down one `spacing` behind the one in front of it.
		var laid := (i + 1) * spacing
		var age := elapsed - laid
		if age < 0.0 or age >= life:
			ghost.visible = false
			continue
		# Where the player was at `laid`: constant velocity until the dash
		# ended, and never past where he has actually got to.
		var along := minf(laid, duration)
		var offset := velocity * along
		if offset.length() > covered:
			offset = offset.normalized() * covered
		ghost.visible = true
		ghost.global_position = origin + offset + _source.position
		ghost.animation = anim
		ghost.frame = SpriteClock.frame_at(_source.sprite_frames, anim, along)
		ghost.scale = Vector2(facing, _source.scale.y)
		var tone := mini(int(age / maxf(life, 0.001) * tones.size()), tones.size() - 1)
		(ghost.material as ShaderMaterial).set_shader_parameter("tint", tones[tone])
