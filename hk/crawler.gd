extends CharacterBody2D
## Quái bò: đi tuần ngang, quay đầu khi gặp tường hoặc mép vực, chạm vào người chơi thì gây 1 mặt nạ.
const SPEED: float = 70.0
const GRAVITY: float = 2400.0
var hp: int = 3
var dir: int = -1
var _kb_t: float = 0.0
var _flash: float = 0.0
var _contact: Area2D

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	add_to_group("hk_enemy")
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(38, 24)
	cs.shape = sh
	add_child(cs)
	_contact = Area2D.new()
	_contact.collision_layer = 0
	_contact.collision_mask = 2
	var c2 := CollisionShape2D.new()
	c2.shape = sh
	_contact.add_child(c2)
	add_child(_contact)

func _physics_process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	velocity.y = minf(velocity.y + GRAVITY * delta, 900.0)
	if _kb_t > 0.0:
		_kb_t -= delta
		velocity.x = move_toward(velocity.x, 0.0, 700.0 * delta)
	else:
		velocity.x = float(dir) * SPEED
	move_and_slide()
	if _kb_t <= 0.0 and is_on_floor() and (is_on_wall() or not _ground_ahead()):
		dir = -dir
	for b in _contact.get_overlapping_bodies():
		if b.has_method("take_damage"):
			b.take_damage(global_position.x)
	queue_redraw()

func _ground_ahead() -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position + Vector2(float(dir) * 24.0, 0.0), global_position + Vector2(float(dir) * 24.0, 40.0), 1)
	return not get_world_2d().direct_space_state.intersect_ray(q).is_empty()

func take_hit(dmg: int, from_pos: Vector2) -> void:
	hp -= dmg
	_flash = 0.1
	_kb_t = 0.2
	velocity.x = signf(global_position.x - from_pos.x) * 260.0
	if hp <= 0:
		queue_free()

func _draw() -> void:
	draw_rect(Rect2(-19, -12, 38, 24), Color(1, 1, 1) if _flash > 0.0 else Color(0.75, 0.35, 0.3))
