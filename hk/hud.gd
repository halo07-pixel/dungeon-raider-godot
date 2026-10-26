extends Control
## Mặt nạ máu (masks) ở góc trên trái.
var hp: int = 5
var max_hp: int = 5

func set_health(h: int, m: int) -> void:
	hp = h
	max_hp = m
	queue_redraw()

func _draw() -> void:
	for i in max_hp:
		var c := Color(0.95, 0.95, 1.0) if i < hp else Color(0.25, 0.25, 0.32)
		draw_rect(Rect2(24 + i * 40, 24, 28, 32), c)
