extends Area2D
## Đạn: của người chơi (Soul Bolt, trúng quái) hoặc của quái (trúng người chơi). Chạm tường thì biến mất.
var vel: Vector2 = Vector2.ZERO
var friendly: bool = false
var damage: int = 1
var life: float = 2.5
var radius: float = 9.0
var color: Color = Color(1, 0.6, 0.3)
var pierce: bool = false

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
		b.take_damage(global_position.x)
		queue_free()
	elif b is StaticBody2D and not b.has_meta("oneway"):   # bục một chiều không chặn đạn
		queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)
	draw_circle(Vector2.ZERO, radius * 0.5, Color(1, 1, 1, 0.8))
