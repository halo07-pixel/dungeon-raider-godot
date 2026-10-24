extends Node2D
## Hiệu ứng vòng xung kích: vòng sáng nở dần từ tâm tới `max_radius` rồi mờ đi, tự huỷ.

var max_radius: float = 190.0
var color: Color = Color(1.0, 0.8, 0.4)
var duration: float = 0.35
var _t: float = 0.0

func _ready() -> void:
	z_index = 40

func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var k: float = clampf(_t / duration, 0.0, 1.0)
	var r: float = max_radius * (1.0 - pow(1.0 - k, 3.0))
	var a: float = 1.0 - k
	draw_circle(Vector2.ZERO, r, Color(color, 0.10 * a))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(color, 0.35 * a), 10.0)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, 0.9 * a), 3.0)
	draw_arc(Vector2.ZERO, r * 0.82, 0.0, TAU, 64, Color(color, 0.22 * a), 4.0) # vòng trong mờ đuổi theo
	for i in 12: # hạt sáng chạy dọc mép sóng
		var p: Vector2 = Vector2.from_angle(TAU * float(i) / 12.0 + k * 1.6) * r
		draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), Color(1.0, 1.0, 1.0, 0.85 * a))
