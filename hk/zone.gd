extends Node2D
## Vùng nguy hiểm/vật thể tạm do đòn riêng của boss tạo ra (con của boss, top_level => toạ độ thế giới; boss chết thì biến mất).
## Gây hại theo hình chữ nhật mỗi khung vật lý (không dùng Area2D nên không dính lỗi "flushing queries").
## kind: spikes (gai nền nứt) | firewave (sóng lửa chạy từ lò) | heat (bục nóng) | water (nước dâng, làm chậm) | pillar (cột rơi rồi thành vật cản).
## Trước khi có hiệu lực (`delay`) không vẽ vùng nào: tín hiệu là âm thanh + bụi/tia lửa do boss phát ra.
const SPRITES = preload("res://hk/sprites.gd")
const FX = preload("res://hk/fx.gd")
var kind: String = "spikes"
var rect: Rect2 = Rect2()       # vùng có hiệu lực (toạ độ thế giới); water: vùng khi nước dâng đủ cao
var delay: float = 0.0
var life: float = 3.0           # thời gian có hiệu lực sau delay
var vel: Vector2 = Vector2.ZERO # firewave
var floor_y: float = 0.0        # pillar: mặt sàn nơi cột đáp xuống
var fx_parent: Node             # nơi đặt hạt bụi (boss gán: cha của boss, toạ độ thế giới)
var _t: float = 0.0
var _landed: bool = false
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
	return delay <= 0.0 and _t < life

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
	if pr.intersects(current()):
		if kind == "water":
			p.slow_t = 0.1   # nước làm chậm (player áp dụng ở di chuyển): đứng bục cao thì an toàn
		else:
			p.take_damage(rect.get_center().x)
	queue_redraw()

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
		"heat":   # bục nóng đỏ: vầng sáng trên mặt bục
			draw_rect(Rect2(r.position.x, r.end.y - 6.0, r.size.x, 6.0), Color(1.0, 0.4, 0.1, flick))
			draw_rect(Rect2(r.position.x, r.position.y + 12.0, r.size.x, r.size.y - 18.0), Color(1.0, 0.45, 0.15, 0.22 * flick))
		"water":
			draw_rect(r, Color(0.25, 0.5, 0.9, 0.35))
			draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 3.0), Color(0.7, 0.9, 1.0, 0.8))
		"pillar":
			var base: Vector2 = Vector2(r.get_center().x, r.end.y)
			SPRITES.draw_body(self, "column", base, 2.0, false, Color(0.85, 0.85, 0.9))
