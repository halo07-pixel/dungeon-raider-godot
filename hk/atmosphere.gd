extends Node2D
## Không khí: ánh sáng theo khu (CanvasModulate + PointLight2D quanh người chơi/bench/bàn thờ/lò lửa) và hạt môi trường. Chỉ trang trí:
## không đụng vật lý hay hộp va chạm. `STATE.atmosphere_on` tắt hết. Cha (world) gọi `set_room` khi đổi phòng và `follow` mỗi khung.
const STATE = preload("res://hk/state.gd")
const AREAS: Dictionary = {   # ambient không tối hơn ~0.72 mỗi kênh để vùng báo hiệu đòn và gai vẫn rõ
	"gate": {"ambient": Color(0.80, 0.84, 1.0), "p": Color(0.75, 0.8, 0.95, 0.45), "grav": Vector2(2, -3), "n": 36},
	"catacomb": {"ambient": Color(0.96, 0.76, 0.76), "p": Color(1.0, 0.5, 0.3, 0.75), "grav": Vector2(0, -14), "n": 44},
	"vault": {"ambient": Color(0.74, 0.88, 0.95), "p": Color(0.7, 0.8, 0.85, 0.45), "grav": Vector2(3, 12), "n": 36},
	"archive": {"ambient": Color(0.84, 0.77, 1.0), "p": Color(0.75, 0.6, 1.0, 0.65), "grav": Vector2(0, -10), "n": 40},
}
const TILE: float = 32.0
var _mod: CanvasModulate
var _tint: Color = Color.WHITE   # boss nhuộm màu phòng (Many-Faced pha 3)
var _dark: bool = false   # boss Wraith tối phòng (chỉ có tác dụng khi Atmosphere bật)
var _dust: CPUParticles2D
var _player_light: PointLight2D
var _lights: Array = []      # đèn của phòng hiện tại: {l: PointLight2D, base: float, flicker: bool}
var _pp: Vector2 = Vector2.ZERO   # vị trí người chơi (đèn vật tương tác sáng dần khi lại gần)
var _mood: String = ""   # "" | focus | danger: đèn người chơi đổi sắc
var _braziers: Array = []    # vị trí chân lò lửa (px)
var _area: String = "gate"
var _tex: GradientTexture2D

func _ready() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	_tex = GradientTexture2D.new()
	_tex.gradient = g
	_tex.fill = GradientTexture2D.FILL_RADIAL
	_tex.fill_from = Vector2(0.5, 0.5)
	_tex.fill_to = Vector2(1.0, 0.5)
	_tex.width = 256
	_tex.height = 256
	_mod = CanvasModulate.new()
	add_child(_mod)
	_dust = CPUParticles2D.new()
	_dust.local_coords = false
	_dust.lifetime = 8.0
	_dust.preprocess = 8.0
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dust.emission_rect_extents = Vector2(760, 440)
	_dust.direction = Vector2.UP
	_dust.spread = 180.0
	_dust.initial_velocity_min = 2.0
	_dust.initial_velocity_max = 9.0
	_dust.scale_amount_min = 1.5
	_dust.scale_amount_max = 3.0
	add_child(_dust)
	_player_light = _make_light(Color(1.0, 0.92, 0.8), 0.5, 2.2)
	apply()

func _make_light(col: Color, energy: float, scale_: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = _tex
	l.color = col
	l.energy = energy
	l.texture_scale = scale_
	add_child(l)
	return l

func is_on() -> bool:
	return STATE.atmosphere_on

## Boss bật/tắt bóng tối trong phòng.
func set_tint(c: Color) -> void:
	_tint = c
	apply()

func set_dark(on: bool) -> void:
	_dark = on
	apply()

## Áp lại cài đặt bật/tắt và màu theo khu.
func apply() -> void:
	var on: bool = STATE.atmosphere_on
	var cfg: Dictionary = AREAS[_area]
	_mod.color = (cfg["ambient"] * _tint * (0.4 if _dark else 1.0) if on else Color.WHITE)
	_dust.visible = on
	_dust.emitting = on
	_dust.color = cfg["p"]
	_dust.gravity = cfg["grav"]
	_dust.amount = int(cfg["n"])
	_player_light.visible = on
	for it in _lights:
		it["l"].visible = on
	queue_redraw()

func set_room(data: Dictionary, interactables: Array) -> void:
	for it in _lights:
		it["l"].queue_free()
	_lights = []
	_braziers = []
	var area: String = String(data.get("area", "gate"))
	_area = area if AREAS.has(area) else "gate"
	for t in data.get("torches", []):
		var foot := Vector2((float(t["col"]) + 0.5) * TILE, (float(t["row"]) + 1.0) * TILE)
		_braziers.append(foot)
		_lights.append({"l": _make_light(Color(1.0, 0.65, 0.3), 0.8, 2.0), "base": 0.8, "flicker": true, "pos": foot + Vector2(0, -22)})
	for it in interactables:
		var vis: Rect2 = it["vis"]
		match String(it["kind"]):
			"bench":
				_lights.append({"l": _make_light(Color(1.0, 0.85, 0.55), 0.55, 1.3), "base": 0.55, "flicker": false, "pos": vis.get_center()})
			"altar":
				_lights.append({"l": _make_light(Color(1.0, 0.85, 0.4), 0.7, 1.5), "base": 0.7, "flicker": false, "pos": Vector2(vis.get_center().x, vis.position.y)})
			"charm":
				_lights.append({"l": _make_light(Color(0.5, 0.95, 0.85), 0.7, 1.4), "base": 0.7, "flicker": false, "pos": Vector2(vis.get_center().x, vis.position.y)})
			"merchant":
				_lights.append({"l": _make_light(Color(0.6, 0.8, 1.0), 0.5, 1.3), "base": 0.5, "flicker": false, "pos": vis.get_center()})
	for it in _lights:
		it["l"].position = it["pos"]
	apply()

## Hạt đi theo camera; đèn người chơi đi theo người chơi.
func follow(cam_pos: Vector2, player_pos: Vector2) -> void:
	_dust.global_position = cam_pos
	_player_light.global_position = player_pos + Vector2(0, -8)
	_pp = player_pos

## Tâm trạng đèn người chơi: focus = sáng trắng hơn, danger (còn 1 mặt nạ) = đỏ nhấp nháy.
func set_mood(m: String) -> void:
	_mood = m

func _process(_d: float) -> void:
	if not STATE.atmosphere_on:
		return
	var t: float = Time.get_ticks_msec() * 0.001
	for i in _lights.size():
		var it: Dictionary = _lights[i]
		if it["flicker"]:
			it["l"].energy = float(it["base"]) * (0.85 + 0.15 * sin(t * 11.0 + i * 1.7) + 0.05 * sin(t * 23.0 + i))
		else:   # bench/bàn thờ/bùa/thương nhân: sáng dần tới +80% khi người chơi lại gần
			it["l"].energy = float(it["base"]) * (1.0 + 0.8 * clampf(1.0 - _pp.distance_to(it["pos"]) / 160.0, 0.0, 1.0))
	match _mood:
		"focus":
			_player_light.color = Color(1.0, 1.0, 1.0)
			_player_light.energy = 0.9
		"danger":
			_player_light.color = Color(1.0, 0.45, 0.4)
			_player_light.energy = 0.5 + 0.25 * sin(t * 8.0)
		_:
			_player_light.color = Color(1.0, 0.92, 0.8)
			_player_light.energy = 0.5
	if not _braziers.is_empty():
		queue_redraw()

func _draw() -> void:
	if not STATE.atmosphere_on:
		return
	var t: float = Time.get_ticks_msec() * 0.001
	for i in _braziers.size():
		var f: Vector2 = _braziers[i]
		draw_rect(Rect2(f.x - 3, f.y - 16, 6, 16), Color(0.28, 0.24, 0.22))
		draw_rect(Rect2(f.x - 8, f.y - 22, 16, 7), Color(0.4, 0.34, 0.3))
		var h: float = 20.0 + 4.0 * sin(t * 12.0 + i * 2.0)
		draw_colored_polygon(PackedVector2Array([Vector2(f.x - 8, f.y - 22), Vector2(f.x, f.y - 22 - h), Vector2(f.x + 8, f.y - 22)]), Color(1.0, 0.55, 0.2, 0.95))
		draw_colored_polygon(PackedVector2Array([Vector2(f.x - 4, f.y - 22), Vector2(f.x, f.y - 22 - h * 0.6), Vector2(f.x + 4, f.y - 22)]), Color(1.0, 0.9, 0.5, 0.95))
