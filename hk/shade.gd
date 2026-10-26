extends StaticBody2D
## Bóng ma giữ số Geo bạn đánh rơi khi chết. Chém trúng 4 lần để lấy lại.
signal recovered(amount: int)
const STATE = preload("res://hk/state.gd")
const FX = preload("res://hk/fx.gd")
var hp: int = 4
var amount: int = 0
var _t: float = 0.0

func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(34, 52)
	cs.shape = sh
	add_child(cs)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func take_hit(_dmg: int, _from: Vector2) -> void:
	hp -= 1
	FX.burst(get_parent(), global_position, Color(0.7, 0.8, 1.0), 6, 120.0)
	if hp <= 0:
		STATE.geo += amount
		STATE.shade = {}
		FX.float_text(get_parent(), global_position, "+%d" % amount, Color(1, 0.9, 0.4))
		recovered.emit(amount)
		queue_free()

func _draw() -> void:
	var b: float = sin(_t * 3.0) * 4.0
	draw_rect(Rect2(-14, -26 + b, 28, 52), Color(0.55, 0.65, 0.9, 0.55))
	draw_rect(Rect2(-8, -14 + b, 5, 8), Color(0.05, 0.05, 0.12))
	draw_rect(Rect2(3, -14 + b, 5, 8), Color(0.05, 0.05, 0.12))
