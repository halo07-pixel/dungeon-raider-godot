extends Node2D
## Thanh máu nổi của quái — node RIÊNG (z_index cao) thay cho phần vẽ trong enemy._draw():
## trước đây sprite (node con) vẽ đè lên thanh máu nên thanh bị chìm sau thân quái.
## top_level = true: không thừa hưởng modulate/flip của quái (nháy trắng khi trúng đòn
## không làm thanh máu bị chói), tự bám theo vị trí quái mỗi khung hình.

const MIN_W: float = 24.0
const MAX_W: float = 72.0
const H: float = 5.0
const CHIP_HOLD: float = 0.25
const CHIP_SPEED: float = 0.9 # tỉ lệ máu tối đa mất đi mỗi giây khi chip tụt xuống

var enemy: Node2D = null
var top_y: float = -40.0 # khoảng cách từ gốc quái lên đỉnh sprite (âm)
var bar_w: float = 32.0
var elite: bool = false
var _chip: float = 1.0
var _hold: float = 0.0
var _last_ratio: float = 1.0


func setup(p_enemy: Node2D, p_top_y: float, radius: float, p_elite: bool) -> void:
	enemy = p_enemy
	top_y = p_top_y
	bar_w = clampf(radius * 2.0 + 8.0, MIN_W, MAX_W)
	elite = p_elite
	top_level = true
	z_as_relative = false
	z_index = 50
	visible = false


func _ratio() -> float:
	var mh: float = float(enemy.get("max_hp"))
	if mh <= 0.0:
		return 1.0
	return clampf(float(enemy.get("hp")) / mh, 0.0, 1.0)


func _process(delta: float) -> void:
	if not is_instance_valid(enemy) or not bool(enemy.get("alive")):
		visible = false
		return
	global_position = enemy.global_position + Vector2(0.0, top_y)
	var ratio: float = _ratio()
	visible = ratio < 0.999
	if ratio < _last_ratio:
		_hold = CHIP_HOLD
	elif ratio > _chip:
		_chip = ratio
	_last_ratio = ratio
	if _hold > 0.0:
		_hold -= delta
	elif _chip > ratio:
		_chip = maxf(ratio, _chip - CHIP_SPEED * delta)
	if visible:
		queue_redraw()


func _draw() -> void:
	if not is_instance_valid(enemy):
		return
	var ratio: float = _ratio()
	var x0: float = -bar_w * 0.5
	var frame: Color = Color(0.85, 0.35, 0.95) if elite else Color(0.0, 0.0, 0.0)
	draw_rect(Rect2(x0 - 1.0, -1.0, bar_w + 2.0, H + 2.0), Color(frame, 0.9))   # viền
	draw_rect(Rect2(x0, 0.0, bar_w, H), Color(0.12, 0.02, 0.02))                  # nền
	if _chip > ratio:
		draw_rect(Rect2(x0, 0.0, bar_w * _chip, H), Color(1.0, 1.0, 1.0, 0.7))   # chip: máu vừa mất
	draw_rect(Rect2(x0, 0.0, bar_w * ratio, H), Color(0.88, 0.2, 0.2))            # máu
	draw_rect(Rect2(x0, 0.0, bar_w * ratio, 2.0), Color(1.0, 0.5, 0.45))          # sáng mép trên
