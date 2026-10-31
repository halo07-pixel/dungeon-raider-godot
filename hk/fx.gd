extends RefCounted
const STATE = preload("res://hk/state.gd")
const MAX_LIVE: int = 16   # trần số cụm bụi/nước cùng lúc (máy yếu không bị nặng)
static var _live: int = 0
## Hiệu ứng nhỏ dựng bằng code: chữ nổi, tia vụn, vòng lan, tia chém theo hướng, mảnh vỡ khi chết.
## Bụi/nước nhỏ dưới chân. Tự dọn; trả null (không tạo gì) khi tắt Atmosphere hoặc đã đủ MAX_LIVE cụm.
static func puff(parent: Node, pos: Vector2, n: int, color: Color, speed: float = 60.0, gravity_y: float = -20.0) -> CPUParticles2D:
	if not STATE.atmosphere_on or _live >= MAX_LIVE or not is_instance_valid(parent):
		return null
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = maxi(1, n)
	p.lifetime = 0.35
	p.explosiveness = 0.9
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.gravity = Vector2(0, gravity_y)
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.color = color
	p.emitting = true
	_live += 1
	p.tree_exited.connect(func(): _live -= 1)   # tree_exited: đúng cả khi phòng bị giải phóng giữa chừng
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	return p

static func float_text(parent: Node, pos: Vector2, text: String, color: Color = Color.WHITE) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 18)
	l.z_index = 50
	parent.add_child(l)
	l.global_position = pos - Vector2(16, 40)
	var t := l.create_tween()
	t.tween_property(l, "global_position:y", l.global_position.y - 36.0, 0.6)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)

static func burst(parent: Node, pos: Vector2, color: Color, n: int = 8, speed: float = 160.0) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = n
	p.lifetime = 0.4
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector2(0, 400)
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = color
	p.emitting = true
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)

## Vòng tròn nở ra rồi mờ dần (khi quái chết, boss đập đất).
static func ring(parent: Node, pos: Vector2, color: Color, radius: float = 50.0, dur: float = 0.3) -> void:
	var n := Node2D.new()
	n.z_index = 40
	n.draw.connect(func(): n.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 28, color, 3.0))
	parent.add_child(n)
	n.global_position = pos
	n.scale = Vector2(0.15, 0.15)
	var t := n.create_tween()
	t.tween_property(n, "scale", Vector2.ONE, dur).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(n, "modulate:a", 0.0, dur)
	t.tween_callback(n.queue_free)

## Tia lửa bắn ngược hướng đòn (`away`: vectơ đơn vị từ kẻ bị đánh ra xa người đánh).
static func spark(parent: Node, pos: Vector2, away: Vector2, color: Color) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = 7
	p.lifetime = 0.25
	p.explosiveness = 1.0
	p.direction = away
	p.spread = 35.0
	p.gravity = Vector2(0, 300)
	p.initial_velocity_min = 180.0
	p.initial_velocity_max = 340.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 3.5
	p.color = color.lightened(0.5)
	p.emitting = true
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)

## Cái chết: mảnh vỡ + chớp trắng + vòng lan. `big` cho boss.
static func death(parent: Node, pos: Vector2, color: Color, big: bool = false) -> void:
	burst(parent, pos, color, 40 if big else 14, 380.0 if big else 260.0)
	burst(parent, pos, Color(1, 1, 1), 8 if big else 4, 200.0)
	ring(parent, pos, color.lightened(0.4), 130.0 if big else 46.0, 0.45 if big else 0.28)
