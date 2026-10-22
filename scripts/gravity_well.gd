extends Node2D
## Gravity Well (kỹ năng khởi đầu của Mage): vùng hút đặt tại điểm ngắm. Quái thường trong vùng bị kéo vào tâm và làm chậm,
## mọi quái/boss trong vùng nhận sát thương theo nhịp. Tự biến mất sau `duration` giây. Dữ liệu do ClassSkill điền trước khi add_child.

const PULL_ACCEL: float = 1700.0   # gia tốc kéo (px/s^2) cộng vào "knockback" của quái
const PULL_MAX: float = 190.0      # tốc độ kéo tối đa (px/s) — không ghi đè knockback mạnh hơn từ nguồn khác
const TICK_SECONDS: float = 0.5
const SLOW_SECONDS: float = 1.0

var radius: float = 130.0
var duration: float = 3.0
var tick_damage: int = 6
var color: Color = Color(0.6, 0.4, 1.0)
## Black Hole (Tome): kéo mạnh hơn và nổ khi hết giờ (end_dmg > 0).
var pull_mult: float = 1.0
var end_dmg: int = 0
var end_radius: float = 0.0
var end_knock: float = 380.0
## Nguồn đòn cho Sigil: "class" (Gravity Well) hoặc "tome" (Black Hole).
var src: String = "class"
var _t: float = 0.0
var _tick: float = 0.0

func _ready() -> void:
	z_index = -1

func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		if end_dmg > 0:
			_explode()
		queue_free()
		return
	_tick += delta
	var do_tick: bool = false
	if _tick >= TICK_SECONDS:
		_tick -= TICK_SECONDS
		do_tick = true
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not e.alive:
			continue
		var to: Vector2 = global_position - e.global_position
		if to.length() > radius:
			continue
		if to.length() > 10.0 and e.get("knockback") != null and (e.knockback as Vector2).length() < PULL_MAX * pull_mult:
			e.knockback = (e.knockback + to.normalized() * PULL_ACCEL * pull_mult * delta).limit_length(PULL_MAX * pull_mult)
		if do_tick:
			e.take_damage(tick_damage, global_position, 0.0)
			if e.alive and e.has_method("apply_status"):
				e.apply_status("slow", SLOW_SECONDS)
			Global.on_secondary_hit(e, tick_damage, false, src)
	if do_tick:
		for b in get_tree().get_nodes_in_group("boss"):
			if is_instance_valid(b) and b.alive and b.global_position.distance_to(global_position) <= radius + 20.0:
				b.take_damage(tick_damage, global_position, 0.0)
				Global.on_secondary_hit(b, tick_damage, false, src)
	queue_redraw()

## Nổ cuối vòng đời: sát thương + đẩy lùi mọi quái/boss trong end_radius.
func _explode() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.alive and e.global_position.distance_to(global_position) <= end_radius:
			e.take_damage(end_dmg, global_position, end_knock)
			Global.on_secondary_hit(e, end_dmg, false, src)
	for b in get_tree().get_nodes_in_group("boss"):
		if is_instance_valid(b) and b.alive and b.global_position.distance_to(global_position) <= end_radius + 20.0:
			b.take_damage(end_dmg, global_position, 0.0)
			Global.on_secondary_hit(b, end_dmg, false, src)
	Global.burst(global_position, color, 24, 300.0, 2.0)
	Global.shake(0.45, 0.3)
	Global.sfx("meteor_impact")

func _draw() -> void:
	var life: float = clampf(1.0 - _t / maxf(duration, 0.01), 0.0, 1.0)
	var pulse: float = 0.5 + 0.5 * sin(_t * 8.0)
	draw_circle(Vector2.ZERO, radius, Color(color, 0.10 + 0.05 * pulse))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(color, 0.55 * life + 0.15), 2.0)
	for i in 3: # vòng thu nhỏ dần về tâm tạo cảm giác hút
		var k: float = fposmod(_t * 0.9 + float(i) / 3.0, 1.0)
		draw_arc(Vector2.ZERO, radius * (1.0 - k), 0.0, TAU, 32, Color(color, 0.45 * (1.0 - k)), 1.5)
	draw_circle(Vector2.ZERO, 7.0 + 2.0 * pulse, Color(0.1, 0.05, 0.2, 0.9))
