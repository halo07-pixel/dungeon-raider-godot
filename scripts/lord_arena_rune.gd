extends Node2D
## Trang trí vòng rune phép dưới chân Dungeon Lord — vẽ THỦ TỤC bằng code, không dùng asset
## ảnh ngoài: đã thử tìm asset CC0 phù hợp (được người dùng cho phép) nhưng môi trường sandbox
## không tải được file nhị phân từ các nguồn asset ngoài GitHub (itch.io/opengameart không nằm
## trong allowlist mạng) — vẽ thủ tục tránh rủi ro placeholder sai bản quyền/thiếu rõ nguồn gốc.
## 2 vòng tròn lồng nhau nhấp nháy + tia sáng toả ra, tông lửa địa ngục (đỏ/cam/vàng) hợp biome Hell.
var _t: float = 0.0
const RADIUS: float = 150.0

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_t * 1.4)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 64, Color(0.9, 0.2, 0.05, 0.4 + 0.2 * pulse), 4.0)
	draw_arc(Vector2.ZERO, RADIUS * 0.72, 0.0, TAU, 48, Color(1.0, 0.55, 0.1, 0.3 + 0.25 * pulse), 2.0)
	var spikes: int = 12
	for i in spikes:
		var ang: float = TAU * float(i) / float(spikes) + _t * 0.15
		var inner: Vector2 = Vector2.from_angle(ang) * RADIUS * 0.72
		var outer: Vector2 = Vector2.from_angle(ang) * (RADIUS * 0.72 + 18.0 + 6.0 * pulse)
		draw_line(inner, outer, Color(1.0, 0.8, 0.25, 0.45 + 0.25 * pulse), 2.0)
