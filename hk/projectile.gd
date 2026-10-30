extends Area2D
## Đạn: của người chơi (Soul Bolt, trúng quái) hoặc của quái (trúng người chơi). Chạm tường thì biến mất.
var vel: Vector2 = Vector2.ZERO
var friendly: bool = false
var damage: int = 1
var life: float = 2.5
var radius: float = 9.0
var color: Color = Color(1, 0.6, 0.3)
var pierce: bool = false
signal popped   # bong bóng (slows) trúng người chơi: nơi tạo ra nó phát âm
var slows: bool = false   # bong bóng (bubbler): không sát thương, chỉ làm chậm người chơi

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | (4 if friendly else 2)
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = radius
	cs.shape = sh
	add_child(cs)
	body_entered.connect(_on_body)

func _physics_process(delta: float) -> void:
	position += vel * delta
	life -= delta
	if life <= 0.0:
		queue_free()
	queue_redraw()

func _on_body(b: Node) -> void:
	if friendly and b.has_method("take_hit"):
		b.take_hit(damage, global_position)
		if not pierce:
			queue_free()
	elif not friendly and b.has_method("take_damage"):
		if slows:
			b.slow_t = 2.0
			popped.emit()
		else:
			b.take_damage(global_position.x)
		queue_free()
	elif b is StaticBody2D and not b.has_meta("oneway"):   # bục một chiều không chặn đạn
		queue_free()

func _draw() -> void:
	if slows:   # bong bóng: viền sáng, nhấp nháy khi sắp tan
		if life < 0.8 and int(life * 14.0) % 2 == 0:
			return
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color(0.85, 0.95, 1.0, 0.9), 2.0)
	draw_circle(Vector2.ZERO, radius, color)
	draw_circle(Vector2.ZERO, radius * 0.5, Color(1, 1, 1, 0.8))
