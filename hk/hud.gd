extends Control
## HUD: mặt nạ máu, ống Soul, Geo, biểu ngữ tên khu vực/thông báo.
const STATE = preload("res://hk/state.gd")
const SPRITES = preload("res://hk/sprites.gd")
const PIXEL: float = 3.0   # cùng mật độ pixel với thế giới (sprite x2, camera x1.5)
var hp: int = 5
var max_hp: int = 5
var soul: int = 0
var geo: int = 0
var banner_text: String = ""
var banner_sub: String = ""
var banner_a: float = 0.0
var _tween: Tween
var boss: Node2D                 # world gán khi vào phòng có boss, gỡ khi hạ: hiện thanh máu lớn ở giữa dưới
var _t: float = 0.0
var _hurt: float = 0.0           # vừa mất mặt nạ: chớp trắng + rung (giây còn lại)
var _pop: float = 0.0            # vừa hồi mặt nạ: phồng lên
var _soul_flash: float = 0.0     # vừa nhận soul
var _geo_shown: float = -1.0     # số Geo đang hiện (đếm tăng dần tới STATE.geo)
var _geo_seen: int = -1         # STATE.geo ở khung trước (phát hiện tăng/giảm)
var _geo_gain: int = 0           # tổng Geo vừa nhận, hiện "+N" rồi mờ
var _gain_t: float = 0.0
var _boss_frac: float = 1.0      # thanh máu boss hiện (trượt mượt tới hp thật)
const HURT_TIME: float = 0.45
const POP_TIME: float = 0.3
const GAIN_TIME: float = 1.2

func set_health(h: int, m: int) -> void:
	if h < hp:
		_hurt = HURT_TIME
	elif h > hp:
		_pop = POP_TIME
	hp = h
	max_hp = m
	queue_redraw()

func set_soul(s: int) -> void:
	if s > soul:
		_soul_flash = 0.35
	soul = s
	queue_redraw()

## Chữ có viền tối cho dễ đọc trên nền sáng.
func _text(font: Font, pos: Vector2, text: String, fsize: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	draw_string_outline(font, pos, text, align, width, fsize, maxi(3, fsize / 6), Color(0, 0, 0, color.a * 0.85))
	draw_string(font, pos, text, align, width, fsize, color)

func banner(text: String, sub: String = "") -> void:
	banner_text = text
	banner_sub = sub
	banner_a = 0.0
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "banner_a", 1.0, 0.4)
	_tween.tween_interval(1.8)
	_tween.tween_property(self, "banner_a", 0.0, 0.6)

func _process(d: float) -> void:
	_t += d
	_hurt = maxf(0.0, _hurt - d)
	_pop = maxf(0.0, _pop - d)
	_soul_flash = maxf(0.0, _soul_flash - d)
	_gain_t = maxf(0.0, _gain_t - d)
	if _gain_t <= 0.0:
		_geo_gain = 0
	var g: int = STATE.geo
	if _geo_seen < 0 or g < _geo_seen:   # lần đầu hoặc giảm (mua đồ, chết): hiện ngay
		_geo_shown = float(g)
	elif g > _geo_seen:   # tăng: "+N" cộng dồn, số đếm dần
		_geo_gain += g - _geo_seen
		_gain_t = GAIN_TIME
	_geo_seen = g
	_geo_shown = move_toward(_geo_shown, float(g), maxf(1.0, absf(float(g) - _geo_shown) * 8.0 * d))
	geo = int(_geo_shown)
	if is_instance_valid(boss):
		_boss_frac = move_toward(_boss_frac, clampf(float(boss.hp) / float(maxi(1, boss.max_hp)), 0.0, 1.0), 1.2 * d)
	else:
		_boss_frac = 1.0
	queue_redraw()

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	# ống soul
	draw_circle(Vector2(52, 52), 30, Color(0.1, 0.12, 0.2))
	var fill: float = float(soul) / float(STATE.SOUL_MAX)
	draw_rect(Rect2(22, 52 + 30 - 60.0 * fill, 60, 60.0 * fill), Color(0.85, 0.92, 1.0, 0.9))
	draw_arc(Vector2(52, 52), 30, 0, TAU, 32, Color(0.7, 0.75, 0.9), 3.0)
	if soul >= STATE.spell_cost():   # đủ soul để Focus/Soul Bolt: viền sáng nhịp thở
		draw_arc(Vector2(52, 52), 34.0, 0, TAU, 32, Color(1.0, 0.95, 0.6, 0.5 + 0.3 * sin(_t * 4.0)), 3.0)
	if _soul_flash > 0.0:
		draw_circle(Vector2(52, 52), 30, Color(1, 1, 1, _soul_flash * 1.2))
	var shake: float = sin(_t * 90.0) * 6.0 * (_hurt / HURT_TIME)
	for i in max_hp:
		var hp_pos := Vector2(120.0 + i * 46.0 + shake, 62.0)
		var sc: float = PIXEL
		if _pop > 0.0 and i == hp - 1:   # mặt nạ vừa hồi: phồng lên rồi về cỡ thường
			sc = PIXEL * (1.0 + 0.35 * sin(PI * (1.0 - _pop / POP_TIME)))
		if _hurt > 0.0 and i == hp:   # mặt nạ vừa mất: chớp trắng rồi mờ
			SPRITES.draw_body(self, "ui_heart_full", hp_pos, PIXEL, false, Color(2, 2, 2, _hurt / HURT_TIME))
		SPRITES.draw_body(self, "ui_heart_full" if i < hp else "ui_heart_empty", hp_pos, sc)
	if hp == 1 and max_hp > 1:   # còn 1 mặt nạ: viền đỏ nhấp nháy quanh mặt nạ cuối
		draw_arc(Vector2(120.0 + shake, 44.0), 24.0, 0, TAU, 24, Color(1.0, 0.25, 0.2, 0.4 + 0.4 * sin(_t * 8.0)), 3.0)
	SPRITES.draw_body(self, "coin_anim", Vector2(120.0, 96.0), PIXEL, false, Color.WHITE, 8.0)
	_text(font, Vector2(138, 94), str(geo), 22, Color(0.95, 0.9, 0.7))
	if _gain_t > 0.0 and _geo_gain > 0:   # "+N" nổi cạnh số Geo
		var ga: float = clampf(_gain_t / GAIN_TIME * 2.0, 0.0, 1.0)
		_text(font, Vector2(138.0 + 14.0 * str(geo).length() + 16.0, 94.0 - 8.0 * (1.0 - _gain_t / GAIN_TIME)), "+%d" % _geo_gain, 18, Color(1.0, 0.9, 0.4, ga))
	if banner_a > 0.01:
		var w: float = size.x
		_text(font, Vector2(0, size.y * 0.2), banner_text, 42, Color(1, 1, 1, banner_a), HORIZONTAL_ALIGNMENT_CENTER, w)
		if banner_sub != "":
			_text(font, Vector2(0, size.y * 0.2 + 34), banner_sub, 20, Color(0.8, 0.85, 0.95, banner_a), HORIZONTAL_ALIGNMENT_CENTER, w)
	if is_instance_valid(boss) and boss.state != "dormant":   # thanh máu boss lớn, giữa dưới màn hình
		var bw: float = minf(size.x * 0.5, 560.0)
		var bx: float = (size.x - bw) * 0.5
		var by: float = size.y - 56.0
		_text(font, Vector2(0, by - 10.0), String(boss.title()), 22, Color(1, 0.95, 0.9), HORIZONTAL_ALIGNMENT_CENTER, size.x)
		draw_rect(Rect2(bx - 2.0, by - 2.0, bw + 4.0, 16.0), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(bx, by, bw, 12.0), Color(0.18, 0.06, 0.07))
		draw_rect(Rect2(bx, by, bw * _boss_frac, 12.0), Color(0.9, 0.3, 0.28))
		draw_rect(Rect2(bx, by, bw * clampf(float(boss.hp) / float(maxi(1, boss.max_hp)), 0.0, 1.0), 12.0), Color(1.0, 0.45, 0.4))
