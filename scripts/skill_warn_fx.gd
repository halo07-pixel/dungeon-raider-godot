extends Node2D
## Vòng báo hiệu trên đất cho kỹ năng rơi từ trên xuống (Meteor Storm): vòng ngoài cố định, phần tô bên trong
## đầy dần tới lúc va chạm; ở `fall_time` giây cuối có quả cầu lửa rơi từ trên xuống. Tự huỷ sau `duration`.
## Chỉ vẽ — sát thương do ClassSkill xử lý.

var radius: float = 80.0
var duration: float = 0.8
var color: Color = Color(1.0, 0.45, 0.15)
const FALL_TIME: float = 0.25
const FALL_HEIGHT: float = 240.0
var _t: float = 0.0

func _ready() -> void:
	z_index = -1

func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var k: float = clampf(_t / duration, 0.0, 1.0)
	draw_circle(Vector2.ZERO, radius * k, Color(color, 0.16))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(color, 0.55 + 0.3 * sin(_t * 18.0)), 2.0)
	var fall_k: float = (_t - (duration - FALL_TIME)) / FALL_TIME
	if fall_k > 0.0:
		var y: float = -FALL_HEIGHT * (1.0 - fall_k)
		draw_line(Vector2(0.0, y - 40.0), Vector2(0.0, y), Color(color, 0.5), 8.0)
		draw_circle(Vector2(0.0, y), 11.0, Color(1.0, 0.85, 0.4))
		draw_circle(Vector2(0.0, y), 7.0, Color(1.0, 1.0, 0.9))
