extends StaticBody2D
## Bóng ma giữ số Geo bạn đánh rơi khi chết. Chém trúng 4 lần để lấy lại.
signal recovered(amount: int)
const STATE = preload("res://hk/state.gd")
const FX = preload("res://hk/fx.gd")
const SPRITES = preload("res://hk/sprites.gd")
var hp: int = 4
var amount: int = 0
var _t: float = 0.0

func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = SPRITES.BODIES.rect("knight_m_idle_anim", 2.0).size
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
	# bóng ma = bóng hiệp sĩ mờ, nhấp nhô nhẹ; chân nằm ở đáy hộp va chạm
	var h: float = SPRITES.BODIES.rect("knight_m_idle_anim", 2.0).size.y
	SPRITES.draw_body(self, "knight_m_idle_anim", Vector2(0, h * 0.5 + sin(_t * 3.0) * 4.0), 2.0, false, Color(0.55, 0.7, 1.4, 0.55), 6.0)
