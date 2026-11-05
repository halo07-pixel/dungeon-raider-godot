extends CharacterBody2D
## The Stalker (nightmare): bóng đen đuổi người chơi khi đi quá lâu không nghỉ ở bench. Bay xuyên tường, chậm hơn người chơi,
## không giết được: một nhát chém hoặc đỡ làm choáng STUN giây. Chạm thì mất 1 mặt nạ (đỡ được), rồi biến mất tới khi world gọi lại.
signal touched
signal sfx(name: String)
const SIZE: Vector2 = Vector2(26.0, 46.0)
const SPEED: float = 90.0
const STUN: float = 3.0
const APPEAR: float = 1.5   # mờ dần hiện ra, chưa gây hại
var arena: Rect2 = Rect2(0, 0, 1280, 720)
var state: String = "appear"   # appear | chase | stun | gone
var hp: int = 1                # để player._on_nail_hit không coi là hạ gục
var _t: float = APPEAR
var _time: float = 0.0
var _placed: bool = false
var frozen: bool = false       # world đặt: không chạy khi chuyển phòng/chết

func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	add_to_group("hk_stalker")
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = SIZE
	cs.shape = sh
	add_child(cs)

func _player() -> Node2D:
	var ps := get_tree().get_nodes_in_group("hk_player")
	return ps[0] if not ps.is_empty() else null

func _physics_process(delta: float) -> void:
	var p := _player()
	if p == null:
		return
	if frozen:
		return
	_time += delta
	_t -= delta
	if not _placed:   # hiện ở phía xa nhất của phòng so với người chơi
		_placed = true
		var far_x: float = arena.end.x - 90.0 if p.global_position.x < arena.get_center().x else arena.position.x + 90.0
		global_position = Vector2(far_x, clampf(p.global_position.y - 20.0, arena.position.y + 60.0, arena.end.y - 60.0))
		sfx.emit("stalk")
	match state:
		"appear":
			if _t <= 0.0:
				state = "chase"
		"chase":
			global_position += (p.global_position + Vector2(0, -6) - global_position).limit_length(SPEED * delta)
			if Rect2(global_position - SIZE * 0.5, SIZE).intersects(Rect2(p.global_position - Vector2(12, 22), Vector2(24, 44))):
				p.take_damage(global_position.x)
				state = "gone"
				touched.emit()
		"stun":
			if _t <= 0.0:
				state = "chase"
	collision_layer = 0 if state == "gone" else 4
	queue_redraw()

## Bị chém hoặc đỡ: choáng STUN giây (không mất máu, không chết).
func stagger(_sec: float = 0.0) -> void:
	if state == "chase" or state == "appear":
		state = "stun"
		_t = STUN

func take_hit(_dmg: int, _from: Vector2) -> bool:
	stagger()
	return true

func _draw() -> void:
	if state == "gone":
		return
	var a: float = clampf(1.0 - _t / APPEAR, 0.0, 1.0) * 0.8 if state == "appear" else (0.35 if state == "stun" else 0.8)
	var h: Vector2 = SIZE * 0.5
	var wob: float = sin(_time * 5.0) * 3.0
	draw_rect(Rect2(-h.x, -h.y + wob, SIZE.x, SIZE.y), Color(0.02, 0.0, 0.05, a))
	draw_rect(Rect2(-8.0, -h.y + 10.0 + wob, 5.0, 4.0), Color(0.9, 0.9, 1.0, a))
	draw_rect(Rect2(3.0, -h.y + 10.0 + wob, 5.0, 4.0), Color(0.9, 0.9, 1.0, a))
