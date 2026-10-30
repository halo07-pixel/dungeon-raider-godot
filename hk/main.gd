extends Node2D
## Điểm vào của bản Hollow Knight-style: màn hình tiêu đề -> world -> màn kết thúc -> tiêu đề.
## Cha lắng nghe signal của con (title.chosen, world.ending_reached, ending.finished), không gọi ngược lên.
const STATE = preload("res://hk/state.gd")
const InputSetup = preload("res://hk/input.gd")
const MUSIC = preload("res://hk/music.gd")
const SFX = preload("res://hk/sfx.gd")
var _music: Node
var _sfx: Node
var _world: Node2D
var _overlay: Node

func _ready() -> void:
	InputSetup.ensure()
	_music = MUSIC.new()
	add_child(_music)
	_sfx = SFX.new()
	add_child(_sfx)
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
	t.sfx.connect(_sfx.play)
	add_child(t)
	_overlay = t

func _start_game(mode: String, slot: int, title: Node) -> void:
	STATE.save_path = STATE.slot_path(slot)   # Boss Rush: world đổi sang save tạm
	STATE.boot = mode
	_music.stop()
	title.queue_free()
	_overlay = null
	_world = Node2D.new()
	_world.set_script(preload("res://hk/world.gd"))
	_world.ending_reached.connect(_show_ending)
	_world.rush_finished.connect(_show_rush_result)
	add_child(_world)

func _show_ending() -> void:
	_music.play("stinger_victory", false)
	var e := preload("res://hk/ending.gd").new()
	e.finished.connect(_show_title)
	add_child(e)
	_overlay = e

func _show_rush_result(time: float, deaths: int, record: bool) -> void:
	_music.play("stinger_victory", false)
	var e := preload("res://hk/ending.gd").new()
	e.rush = [time, deaths, record]
	e.finished.connect(_show_title)
	add_child(e)
	_overlay = e
