extends Node2D
## Vùng nguy hiểm/vật thể tạm do đòn riêng của boss tạo ra (con của boss, top_level => toạ độ thế giới; boss chết thì biến mất).
## Gây hại theo hình chữ nhật mỗi khung vật lý (không dùng Area2D nên không dính lỗi "flushing queries").
## kind: undertow (xoáy nước của Colossus, kéo về pull_x, không sát thương) | spikes (gai nền nứt) | firewave (sóng lửa chạy từ lò) | heat (bục nóng) | water (nước dâng, làm chậm) | pillar (cột rơi rồi thành vật cản) | sweep (sóng đá quét sàn của Warden) | spore | vine
## | spore (đám bào tử: cố định theo nhịp period/on_from, hoặc đám nổ từ sporeling) | vine (dây leo trồi lên sàn, như gai) | flame (vệt lửa nằm yên trên sàn do quái cinder để lại; con của room, không phải của boss).
## Trước khi có hiệu lực (`delay`) không vẽ vùng nào: tín hiệu là âm thanh + bụi/tia lửa do boss phát ra.
const SPRITES = preload("res://hk/sprites.gd")
const FX = preload("res://hk/fx.gd")
const DROWN_TIME: float = 2.0   # ở trong nước chừng này giây thì mất 1 mặt nạ, rồi đếm lại
const MAX_DROWN: int = 2        # trần số mặt nạ mất vì chìm mỗi đợt nước
const UNDERTOW_PULL: float = 220.0   # px/s xoáy của Colossus kéo về phía boss
const PULL: float = 80.0        # px/s dòng chảy kéo về phía boss
var kind: String = "spikes"
var rect: Rect2 = Rect2()       # vùng có hiệu lực (toạ độ thế giới); water: vùng khi nước dâng đủ cao
var delay: float = 0.0
var life: float = 3.0           # thời gian có hiệu lực sau delay
var vel: Vector2 = Vector2.ZERO # firewave
var period: float = 0.0         # spore: chu kỳ bật/tắt (0 = luôn bật khi có hiệu lực)
var on_from: float = 0.0        # spore: trong mỗi chu kỳ, từ giây này mới gây hại (trước đó chỉ là mây mờ báo hiệu)
var drown: bool = false         # water: ở trong nước quá DROWN_TIME thì mất mặt nạ (chỉ khi phòng có bục để trú)
var pull_x: float = 0.0         # water (drown): dòng chảy kéo người chơi về phía x này (boss)
var floor_y: float = 0.0        # pillar: mặt sàn nơi cột đáp xuống
var fx_parent: Node             # nơi đặt hạt bụi (boss gán: cha của boss, toạ độ thế giới)
var _t: float = 0.0
var _landed: bool = false
var _in_water: bool = false   # water: người chơi đang ở trong nước (để bắn nước khi vào/ra)
var _ripple: float = 0.0
var _drown_t: float = 0.0     # giây liên tục ở trong nước; đứng trên nền khô thì về 0, nhảy trong không khí thì đứng yên
var _drowns: int = 0          # số mặt nạ đã mất vì chìm ở đợt nước này (tối đa MAX_DROWN)
var _body: StaticBody2D

func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO

func _player() -> Node2D:
	var ps := get_tree().get_nodes_in_group("hk_player")
	return ps[0] if not ps.is_empty() else null

## Vùng hiện tại: nước dâng/hạ dần, cột rơi xuống.
func current() -> Rect2:
	if kind == "water":
		var k: float = minf(minf(_t / 0.8, 1.0), clampf((life - _t) / 0.6, 0.0, 1.0))
		return Rect2(rect.position.x, rect.end.y - rect.size.y * k, rect.size.x, rect.size.y * k)
	return rect

func active() -> bool:
	return delay <= 0.0 and _t < life and _spore_on()

func _spore_on() -> bool:   # kind khác spore: luôn true
	return kind != "spore" or period <= 0.0 or fmod(_t, period) >= on_from

func _physics_process(delta: float) -> void:
	if delay > 0.0:
		delay -= delta
		return
	_t += delta
	rect.position += vel * delta
	if kind == "pillar" and not _landed:
		rect.position.y += 900.0 * delta
		if rect.end.y >= floor_y:
			rect.position.y = floor_y - rect.size.y
			_landed = true
			_t = 0.0
			_make_body()
			if fx_parent:
				FX.burst(fx_parent, Vector2(rect.get_center().x, floor_y), Color(0.6, 0.55, 0.5), 10, 120.0)
	elif _t >= life:
		if kind == "pillar" and fx_parent:
			FX.burst(fx_parent, rect.get_center(), Color(0.6, 0.55, 0.5), 10, 120.0)
		queue_free()
		return
	var p := _player()
	if p == null or kind == "pillar" and _landed:
		queue_redraw()
		return
	var pr := Rect2(p.global_position - p.BODY * 0.5, p.BODY)
	var inside: bool = pr.intersects(current())
	if kind == "water" and not inside and p.is_on_floor():   # đứng trên nền khô (bục cao): hết chìm
		_drown_t = 0.0
	if kind == "water" and _in_water and not inside:   # ra khỏi nước
		_splash(p, 8)
		_in_water = false
	if inside:
		if kind == "water":
			p.slow_t = 0.1   # nước làm chậm (player áp dụng ở di chuyển): đứng bục cao thì an toàn
			_ripple -= delta
			if not _in_water:   # vừa xuống nước
				_splash(p, 8)
			elif _ripple <= 0.0 and absf(p.velocity.x) > 20.0:   # gợn nước khi lội
				_ripple = 0.3
				_splash(p, 2)
			_in_water = true
			if drown:
				p.drift = signf(pull_x - p.global_position.x) * PULL
				_drown_t += delta
				if _drown_t >= DROWN_TIME and _drowns < MAX_DROWN:
					_drown_t = 0.0
					_drowns += 1
					p.take_damage(rect.get_center().x, 1, false)   # chìm: không đỡ được
		elif kind == "undertow":
			p.drift = signf(pull_x - p.global_position.x) * UNDERTOW_PULL   # xoáy: chỉ kéo, không sát thương
		elif _spore_on() and not (kind == "spore" and float(p.get("spore_t")) > 0.0):   # Spore Ward: dash miễn nhiễm bào tử
			p.take_damage(rect.get_center().x, 1, false)   # vùng gây hại: không đỡ được
	queue_redraw()

## Nước bắn quanh chân người chơi (chỉ trang trí; FX.puff tự tắt theo Atmosphere).
func _splash(p: Node2D, n: int) -> void:
	FX.puff(fx_parent, p.global_position + Vector2(0, p.BODY.y * 0.5), n, Color(0.6, 0.8, 1.0, 0.85), 130.0, 500.0)

func _make_body() -> void:
	_body = StaticBody2D.new()
	_body.collision_layer = 1
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = rect.size
	cs.shape = sh
	cs.position = rect.get_center()
	_body.add_child(cs)
	add_child(_body)

func _draw() -> void:
	if delay > 0.0:
		return
	var r: Rect2 = current()
	var flick: float = 0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.03)
	match kind:
		"spore":   # mây bào tử: mờ khi chưa gây hại (có chu kỳ), đậm khi đang gây hại
			var on: bool = _spore_on()
			var warn: bool = not on and period > 0.0 and fmod(_t, period) >= on_from - 0.4
			var a: float = 0.5 if on else (0.3 + 0.1 * sin(Time.get_ticks_msec() * 0.03) if warn else 0.14)
			var n2: int = maxi(3, int(r.size.x / 18.0))
			for k in n2:
				var ph: float = Time.get_ticks_msec() * 0.002 + float(k) * 1.7
				var cx2: float = r.position.x + r.size.x * (float(k) + 0.5) / float(n2)
				var cy2: float = r.end.y - r.size.y * (0.3 + 0.35 * (0.5 + 0.5 * sin(ph)))
				draw_circle(Vector2(cx2, cy2), minf(r.size.y * 0.42, 26.0), Color(0.55, 0.9, 0.25, a))
				draw_circle(Vector2(cx2 + 4.0, cy2 - 3.0), minf(r.size.y * 0.25, 14.0), Color(0.8, 1.0, 0.5, a * 0.8))
		"vine":   # dây leo trồi lên từ sàn
			var nv: int = maxi(1, int(r.size.x / 16.0))
			for k in nv:
				var x1: float = r.position.x + k * (r.size.x / nv)
				var w1: float = r.size.x / nv
				draw_colored_polygon(PackedVector2Array([Vector2(x1, r.end.y), Vector2(x1 + w1 * 0.5 + sin(Time.get_ticks_msec() * 0.02) * 3.0, r.position.y), Vector2(x1 + w1, r.end.y)]), Color(0.35, 0.7, 0.25))
		"spikes":   # gai xương trồi lên từ nền nứt
			var n: int = maxi(1, int(r.size.x / 16.0))
			for k in n:
				var x0: float = r.position.x + k * (r.size.x / n)
				var w: float = r.size.x / n
				draw_colored_polygon(PackedVector2Array([Vector2(x0, r.end.y), Vector2(x0 + w * 0.5, r.position.y), Vector2(x0 + w, r.end.y)]), Color(0.9, 0.88, 0.78))
		"firewave":
			for k in 3:
				var cx: float = r.position.x + r.size.x * (0.2 + 0.3 * k)
				var hh: float = r.size.y * (0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.02 + k * 2.0))
				draw_colored_polygon(PackedVector2Array([Vector2(cx - 10, r.end.y), Vector2(cx, r.end.y - hh), Vector2(cx + 10, r.end.y)]), Color(1.0, 0.45, 0.1, 0.95))
				draw_colored_polygon(PackedVector2Array([Vector2(cx - 5, r.end.y), Vector2(cx, r.end.y - hh * 0.6), Vector2(cx + 5, r.end.y)]), Color(1.0, 0.85, 0.3))
		"sweep":   # sóng đá thấp của Warden: mảnh đá nhấp nhô
			for k in 3:
				var sx: float = r.position.x + r.size.x * (0.2 + 0.3 * float(k))
				var sh: float = r.size.y * (0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.02 + float(k) * 2.0))
				draw_colored_polygon(PackedVector2Array([Vector2(sx - 11.0, r.end.y), Vector2(sx, r.end.y - sh), Vector2(sx + 11.0, r.end.y)]), Color(0.75, 0.72, 0.65, 0.95))
		"flame":
			var hh2: float = r.size.y * (0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.025 + r.position.x))
			draw_colored_polygon(PackedVector2Array([Vector2(r.position.x, r.end.y), Vector2(r.get_center().x, r.end.y - hh2), Vector2(r.end.x, r.end.y)]), Color(1.0, 0.45, 0.1, 0.9))
			draw_colored_polygon(PackedVector2Array([Vector2(r.position.x + 7.0, r.end.y), Vector2(r.get_center().x, r.end.y - hh2 * 0.55), Vector2(r.end.x - 7.0, r.end.y)]), Color(1.0, 0.85, 0.3))
		"heat":   # bục nóng đỏ: vầng sáng trên mặt bục
			draw_rect(Rect2(r.position.x, r.end.y - 6.0, r.size.x, 6.0), Color(1.0, 0.4, 0.1, flick))
			draw_rect(Rect2(r.position.x, r.position.y + 12.0, r.size.x, r.size.y - 18.0), Color(1.0, 0.45, 0.15, 0.22 * flick))
		"undertow":   # xoáy nước: các vòng cung xanh quay quanh tâm
			var cx3: float = pull_x
			for k in 4:
				var rr: float = r.size.x * 0.5 * (0.35 + 0.2 * float(k)) * (0.9 + 0.1 * sin(Time.get_ticks_msec() * 0.01 + float(k)))
				draw_arc(Vector2(cx3, r.end.y), rr, PI, TAU, 24, Color(0.5, 0.8, 1.0, 0.55), 3.0)
		"water":
			draw_rect(r, Color(0.25, 0.5, 0.9, 0.35))
			draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 3.0), Color(0.7, 0.9, 1.0, 0.8))
		"pillar":
			var base: Vector2 = Vector2(r.get_center().x, r.end.y)
			SPRITES.draw_body(self, "column", base, 2.0, false, Color(0.85, 0.85, 0.9))
