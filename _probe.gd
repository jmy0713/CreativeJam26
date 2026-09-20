extends Node
## TEMPORARY dev probe -- deleted after use. Runs the prologue and saves a
## screenshot at each beat so the framing can be checked without sitting
## through it.

const SHOTS := "user://shots"

var menu: Node
var prologue: Node
var _taken := {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	menu = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	prologue = menu.get_node("Prologue")
	await _shot("00_menu")
	menu._on_play_pressed()
	Engine.time_scale = 3.0


func _process(_delta: float) -> void:
	if prologue == null:
		return
	var phase: int = prologue._phase
	var x: float = prologue._actor_x
	var cam: float = prologue.get_node("Camera2D").position.x
	if phase == 2:
		if x > 200.0:
			_once("01_walk_in_left")
		if cam > 400.0:
			_once("02_scrolling")
		if x > 1100.0:
			_once("03_near_end")
	elif phase == 3:
		if prologue._line_index == 0 and prologue._shown >= 2:
			_once("04_line_dots")
		if prologue._line_index == 1 and prologue._shown >= 10:
			_once("05_line_two")
	elif phase == 4:
		if x < 1100.0:
			_once("06_walk_out")
	elif phase == 5:
		_once("07_done")
		print("PHASES OK  camera=%.1f actor=%.1f" % [cam, x])
		prologue = null
		_watch()


## A node parented to the root rather than to the scene, so it survives the
## change into level 1 and can report that it happened.
func _watch() -> void:
	var watcher := Node.new()
	watcher.set_script(preload("res://_watch.gd"))
	get_tree().root.add_child(watcher)


func _once(name: String) -> void:
	if _taken.has(name):
		return
	_taken[name] = true
	print("%s  actor=%.1f cam=%.1f" % [name, prologue._actor_x, prologue.get_node("Camera2D").position.x])
	_shot(name)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [SHOTS, name])
