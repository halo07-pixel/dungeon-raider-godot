extends Control
## Thanh Giáp Ảo của HUD (thay ProgressBar phẳng): khung tối, 2 tông xanh + sáng mép trên,
## vạch chia mỗi 10 giáp, "chip" trắng tụt dần khi mất giáp, nháy sáng khi giáp vỡ.
## Không có chữ số (HUD tối giản).

var max_value: float = 1.0
var value: float = 0.0

const FLASH_TIME: float = 0.4
const CHIP_HOLD: float = 0.25
const CHIP_SPEED: float = 0.7

var _chip: float = 0.0
var _hold: float = 0.0
var _prev: float = 0.0
var _flash: float = 0.0


func _process(delta: float) -> void:
	if value < _prev - 0.01:
		_hold = CHIP_HOLD
		if value <= 0.0 and _prev > 0.0:
			_flash = FLASH_TIME
	elif value > _chip:
		_chip = value
	_prev = value
	if _hold > 0.0:
		_hold -= delta
	elif _chip > value:
		_chip = maxf(value, _chip - max_value * CHIP_SPEED * delta)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	queue_redraw()


func _draw() -> void:
	if max_value <= 0.0:
		return
	var w: float = size.x
	var h: float = size.y
	draw_rect(Rect2(0, 0, w, h), Color(0.03, 0.06, 0.12, 0.9))                        # nền
	var inner := Rect2(2, 2, w - 4.0, h - 4.0)
	var ratio: float = clampf(value / max_value, 0.0, 1.0)
	var chip_ratio: float = clampf(_chip / max_value, 0.0, 1.0)
	if chip_ratio > ratio:
		draw_rect(Rect2(inner.position, Vector2(inner.size.x * chip_ratio, inner.size.y)), Color(1, 1, 1, 0.65))
	if ratio > 0.0:
		var fw: float = inner.size.x * ratio
		draw_rect(Rect2(inner.position, Vector2(fw, inner.size.y)), Color(0.28, 0.52, 0.95))            # tông đậm
		draw_rect(Rect2(inner.position, Vector2(fw, inner.size.y * 0.45)), Color(0.62, 0.84, 1.0))      # sáng mép trên
	# vạch chia: mỗi 10 giáp (thưa ra 20 nếu quá dày)
	var step: float = 10.0 if max_value / 10.0 <= 30.0 else 20.0
	var n: int = int(max_value / step)
	for i in range(1, n + 1):
		var gx: float = inner.position.x + inner.size.x * (float(i) * step / max_value)
		if gx < inner.position.x + inner.size.x - 1.0:
			draw_line(Vector2(gx, inner.position.y), Vector2(gx, inner.position.y + inner.size.y), Color(0.02, 0.05, 0.1, 0.55), 1.0)
	draw_rect(Rect2(0, 0, w, h), Color(0.35, 0.5, 0.75, 0.9), false, 1.0)               # viền
	if _flash > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.85 * _flash / FLASH_TIME))
