extends Node2D
## Phòng thử nghiệm cảm giác chơi (giai đoạn 1). A/D di chuyển, Z nhảy, X chém (giữ W/S để chém lên/xuống), C dash.
const PlayerScript = preload("res://hk/player.gd")
const InputSetup = preload("res://hk/input.gd")
const SPAWN := Vector2(100, 560)

func _ready() -> void:
	InputSetup.ensure()
	var room := Node2D.new()
	room.set_script(preload("res://hk/room.gd"))
	room.rects = [
		Rect2(-200, 600, 2800, 200), Rect2(-200, -400, 200, 1200), Rect2(2400, -400, 200, 1200), Rect2(-200, -400, 2800, 100),
		Rect2(500, 500, 200, 24), Rect2(800, 410, 200, 24), Rect2(1100, 320, 200, 24), Rect2(1500, 480, 120, 120),
	]
	add_child(room)
	var player := CharacterBody2D.new()
	player.set_script(PlayerScript)
	player.position = SPAWN
	add_child(player)
	for x in [900.0, 1300.0, 1900.0]:
		var e := CharacterBody2D.new()
		e.set_script(preload("res://hk/crawler.gd"))
		e.position = Vector2(x, 570)
		add_child(e)
	var cam := Camera2D.new()
	cam.set_script(preload("res://hk/camera.gd"))
	add_child(cam)
	cam.set_bounds(room.bounds())
	cam.make_current()
	cam.position = player.position
	var hud_layer := CanvasLayer.new()
	var hud := Control.new()
	hud.set_script(preload("res://hk/hud.gd"))
	hud_layer.add_child(hud)
	add_child(hud_layer)
	player.hit_landed.connect(cam.shake)
	player.health_changed.connect(hud.set_health)
	player.died.connect(func(): get_tree().call_deferred("reload_current_scene"))
	set_process(true)
	_cam = cam
	_player = player

var _cam: Camera2D
var _player: Node2D

func _process(_d: float) -> void:
	if is_instance_valid(_player):
		_cam.global_position = _player.global_position
