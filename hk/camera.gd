extends Camera2D
## Camera bám người chơi, mượt, giới hạn theo phòng, rung khi trúng đòn (nhận tín hiệu từ player qua main).
var _shake: float = 0.0

func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = 8.0

func shake(strength: float) -> void:
	_shake = maxf(_shake, strength * 4.0)

func set_bounds(b: Rect2) -> void:
	limit_left = int(b.position.x)
	limit_right = int(b.end.x)
	limit_top = int(b.position.y)
	limit_bottom = int(b.end.y)

func _process(delta: float) -> void:
	_shake = maxf(0.0, _shake - 40.0 * delta)
	offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
