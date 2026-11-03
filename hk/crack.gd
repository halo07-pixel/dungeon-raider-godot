extends StaticBody2D
## Mảnh tường nứt: người chơi chém một nhát là vỡ. Chỉ báo lên bằng signal `broken`; room quyết định phần còn lại (cờ, mở cả cụm).
signal broken
var hp: int = 1   # _on_nail_hit của người chơi đọc hp của mục tiêu (hạ gục = đòn nặng); tường nứt không có máu

func take_hit(_dmg: int, _from: Vector2) -> bool:
	broken.emit()
	return true

const HINT_RANGE: float = 140.0   # người chơi lại gần trong tầm này thì vết nứt sáng dần (gợi ý, không đổi va chạm)
var _glow: float = 0.0

func _process(_delta: float) -> void:
	var p := get_tree().get_first_node_in_group("hk_player") as Node2D
	var g: float = 0.0
	if p != null:
		g = clampf(1.0 - global_position.distance_to(p.global_position) / HINT_RANGE, 0.0, 1.0)
	if absf(g - _glow) > 0.01:
		_glow = g
		queue_redraw()

func _draw() -> void:
	if _glow <= 0.0:
		return
	var c := Color(1.0, 0.9, 0.6, 0.7 * _glow)
	draw_polyline(PackedVector2Array([Vector2(0, -16), Vector2(-5, -6), Vector2(3, 2), Vector2(-3, 16)]), c, 2.0)
	draw_polyline(PackedVector2Array([Vector2(-5, -6), Vector2(-13, -2)]), c, 2.0)
