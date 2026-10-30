extends Camera2D
## Camera bám người chơi, mượt, giới hạn theo phòng, rung khi trúng đòn (nhận tín hiệu từ player qua main).
const STATE = preload("res://hk/state.gd")
const ENGAGE: float = 1.7      # vào trận boss: zoom vào
const WIDE: float = 1.3         # boss lớn: zoom ra để thấy trọn boss
const DEATH: float = 1.9        # lúc chết: zoom chậm vào người chơi
const PUNCH: float = 0.06       # đòn nặng của boss: giật zoom ngắn
var base: float = 1.5           # zoom thường (đọc từ zoom lúc dựng)
var _shake: float = 0.0
var _target: float = 1.5
var _cur: float = 1.5
var _speed: float = 3.0
var _punch: float = 0.0
var _min_zoom: float = 0.0      # nhỏ hơn mức này thì khung nhìn lớn hơn phòng (lộ rìa)
var _vp: Vector2 = Vector2(1280, 720)

func _ready() -> void:
	base = zoom.x
	_target = base
	_cur = base
	_vp = get_viewport().get_visible_rect().size
	position_smoothing_enabled = true
	position_smoothing_speed = 8.0

func shake(strength: float) -> void:
	if not STATE.shake_on:
		return
	_shake = maxf(_shake, strength * 4.0)

## Đổi zoom mục tiêu (mượt, `speed` lớn = nhanh); snap = đặt ngay. Tắt Zoom effects thì luôn về zoom thường.
func zoom_to(z: float, speed: float = 3.0, snap: bool = false) -> void:
	_target = z
	_speed = speed
	if snap:
		_cur = z
		_punch = 0.0
		_apply()

## Giật zoom ngắn rồi trả lại (đòn nặng).
func punch(amount: float = PUNCH) -> void:
	if STATE.zoom_on:
		_punch = maxf(_punch, amount)

func _apply() -> void:
	var z: float = maxf((_cur if STATE.zoom_on else base) + (_punch if STATE.zoom_on else 0.0), _min_zoom)
	zoom = Vector2(z, z)

func set_bounds(b: Rect2) -> void:
	_min_zoom = maxf(_vp.x / maxf(b.size.x, 1.0), _vp.y / maxf(b.size.y, 1.0))
	limit_left = int(b.position.x)
	limit_right = int(b.end.x)
	limit_top = int(b.position.y)
	limit_bottom = int(b.end.y)

func _process(delta: float) -> void:
	_cur = lerpf(_cur, _target, 1.0 - exp(-_speed * delta))
	_punch = maxf(0.0, _punch - PUNCH * 7.0 * delta)
	_apply()
	_shake = maxf(0.0, _shake - 40.0 * delta)
	offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
