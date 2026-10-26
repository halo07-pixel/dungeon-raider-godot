extends Control
## HUD: mặt nạ máu, ống Soul, Geo, biểu ngữ tên khu vực/thông báo.
const STATE = preload("res://hk/state.gd")
var hp: int = 5
var max_hp: int = 5
var soul: int = 0
var geo: int = 0
var banner_text: String = ""
var banner_sub: String = ""
var banner_a: float = 0.0
var _tween: Tween

func set_health(h: int, m: int) -> void:
	hp = h
	max_hp = m
	queue_redraw()

func set_soul(s: int) -> void:
	soul = s
	queue_redraw()

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

func _process(_d: float) -> void:
	geo = STATE.geo
	queue_redraw()

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	# ống soul
	draw_circle(Vector2(52, 52), 30, Color(0.1, 0.12, 0.2))
	var fill: float = float(soul) / float(STATE.SOUL_MAX)
	draw_rect(Rect2(22, 52 + 30 - 60.0 * fill, 60, 60.0 * fill), Color(0.85, 0.92, 1.0, 0.9))
	draw_arc(Vector2(52, 52), 30, 0, TAU, 32, Color(0.7, 0.75, 0.9), 3.0)
	for i in max_hp:
		var c := Color(0.95, 0.95, 1.0) if i < hp else Color(0.22, 0.22, 0.3)
		var p := Vector2(104 + i * 36, 30)
		draw_colored_polygon(PackedVector2Array([p, p + Vector2(26, 0), p + Vector2(26, 20), p + Vector2(13, 34), p + Vector2(0, 20)]), c)
	draw_circle(Vector2(116, 78), 7, Color(0.95, 0.85, 0.4))
	draw_string(font, Vector2(130, 85), str(geo), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.95, 0.9, 0.7))
	if banner_a > 0.01:
		var w: float = size.x
		draw_string(font, Vector2(0, size.y * 0.78), banner_text, HORIZONTAL_ALIGNMENT_CENTER, w, 42, Color(1, 1, 1, banner_a))
		if banner_sub != "":
			draw_string(font, Vector2(0, size.y * 0.78 + 34), banner_sub, HORIZONTAL_ALIGNMENT_CENTER, w, 20, Color(0.8, 0.85, 0.95, banner_a))
