extends Node2D
## Vùng lửa Aftershock (buff Gậy Phép): để lại sau vụ nổ, gây sát thương theo nhịp lên quái trong vùng rồi tự tan.
## Chỉ gây sát thương (không qua Global.on_player_hit) để không kích hoạt dây chuyền buff.

var radius: float = 64.0
var tick_damage: int = 5
var color: Color = Color(1.0, 0.5, 0.2)
var duration: float = 2.0
const TICK_INTERVAL: float = 0.5

var _t: float = 0.0
var _tick_t: float = 0.0

func _ready() -> void:
	z_index = -1

func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	_tick_t += delta
	if _tick_t >= TICK_INTERVAL:
		_tick_t -= TICK_INTERVAL
		_tick()
	queue_redraw()

func _tick() -> void:
	for e in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("boss"):
		if not is_instance_valid(e) or not bool(e.get("alive")) or e.get("active") == false:
			continue
		if e.global_position.distance_to(global_position) <= radius + 12.0:
			e.take_damage(tick_damage, global_position, 0.0, true)

func _draw() -> void:
	var a: float = 1.0 - clampf(_t / duration, 0.0, 1.0)
	draw_circle(Vector2.ZERO, radius, Color(color, 0.12 * a + 0.04))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(color, 0.6 * a), 2.0)
