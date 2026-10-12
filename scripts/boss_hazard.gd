extends Area2D
## Vùng nguy hiểm trên sàn dùng chung cho các đòn "để lại hiệu ứng tại chỗ" của boss:
##   - Vùng Nguyền Rủa (Necromancer): bán kính vừa, kéo dài, giật sát thương định kỳ.
##   - Gai Băng (Frost): bán kính nhỏ, 1 lần duy nhất sau khi báo trước (telegraph).
##   - Phán Quyết (Dungeon Lord): bán kính lớn, 1 lần, sát thương cao.
## Viết thuần bằng code (giống spike_trap.gd) nên không cần file .tscn riêng.

var damage: int = 10
var tick_interval: float = 0.6
var duration: float = 3.0
var color: Color = Color(0.6, 0.2, 0.8, 0.45)
var radius: float = 60.0
var telegraph_time: float = 0.0 # >0: chờ bấy nhiêu giây rồi mới kích hoạt (đòn 1 lần)
var single_shot: bool = false
var apply_slow: bool = false # true: ngoài sát thương còn làm chậm Player khi đứng trong vùng

var _t: float = 0.0
var _tick_t: float = 0.0
var _armed: bool = false
var player_inside: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = Global.L_PLAYER
	var shape := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = radius
	shape.shape = circ
	add_child(shape)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_armed = telegraph_time <= 0.0


func _on_body_entered(b: Node) -> void:
	if b.is_in_group("player"):
		player_inside = true


func _on_body_exited(b: Node) -> void:
	if b.is_in_group("player"):
		player_inside = false


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

	if not _armed:
		if _t >= telegraph_time:
			_armed = true
			_t = 0.0
			if single_shot and player_inside:
				_deal_damage()
		return

	if single_shot:
		queue_free()
		return

	if _t >= duration:
		queue_free()
		return

	_tick_t += delta
	if _tick_t >= tick_interval:
		_tick_t = 0.0
		if player_inside:
			_deal_damage()


func _deal_damage() -> void:
	var p = Global.player
	if is_instance_valid(p) and p.has_method("take_damage"):
		if not (p.has_method("is_invulnerable") and p.is_invulnerable()):
			p.take_damage(damage, global_position, 60.0)
			if apply_slow and p.has_method("apply_status"):
				p.apply_status("slow", 1.0)


func _draw() -> void:
	if not _armed:
		# Báo trước: viền nhấp nháy dần đậm theo thời gian chờ
		var ratio: float = clampf(_t / maxf(telegraph_time, 0.01), 0.0, 1.0)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(color, 0.25 + 0.5 * ratio), 3.0)
		draw_circle(Vector2.ZERO, radius * ratio, Color(color, 0.18))
	else:
		draw_circle(Vector2.ZERO, radius, color)
