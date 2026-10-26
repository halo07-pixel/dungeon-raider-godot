extends Node2D
## Điểm vào của bản Hollow Knight-style: màn hình tiêu đề -> world -> màn kết thúc -> tiêu đề.
## Cha lắng nghe signal của con (title.chosen, world.ending_reached, ending.finished), không gọi ngược lên.
const STATE = preload("res://hk/state.gd")
const InputSetup = preload("res://hk/input.gd")
const MUSIC = preload("res://hk/music.gd")
var _music: Node
var _world: Node2D
var _overlay: Node

func _ready() -> void:
	InputSetup.ensure()
	_music = MUSIC.new()
	add_child(_music)
	_show_title()

func _show_title() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	get_tree().paused = false
	_music.play("menu")
	var t := preload("res://hk/title.gd").new()
	t.chosen.connect(_start_game.bind(t))
	add_child(t)
	_overlay = t

func _start_game(mode: String, title: Node) -> void:
	STATE.boot = mode
	_music.stop()
	title.queue_free()
	_overlay = null
	_world = Node2D.new()
	_world.set_script(preload("res://hk/world.gd"))
	_world.ending_reached.connect(_show_ending)
	add_child(_world)

func _show_ending() -> void:
	_music.play("stinger_victory", false)
	var e := preload("res://hk/ending.gd").new()
	e.finished.connect(_show_title)
	add_child(e)
	_overlay = e
