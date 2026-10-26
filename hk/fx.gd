extends RefCounted
## Hiệu ứng nhỏ dựng bằng code: chữ nổi và tia vụn.
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
