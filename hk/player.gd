extends CharacterBody2D
## Nhân vật kiểu Hollow Knight: chạy, nhảy cao thấp tuỳ giữ phím, dash, chém 4 hướng, pogo khi chém xuống.
## Hằng số tính bằng px/giây (khung 1280x720). Chỉnh cảm giác chơi ở đây.
signal hit_landed(strength: float)
signal health_changed(hp: int, max_hp: int)
signal died

const GRAVITY: float = 2400.0
const MAX_FALL: float = 900.0
const RUN_SPEED: float = 300.0
const JUMP_V: float = -780.0
const JUMP_CUT: float = 0.4          # nhả phím nhảy khi đang bay lên: giữ lại 40% vận tốc
const COYOTE: float = 0.1
const JUMP_BUFFER: float = 0.12
const DASH_SPEED: float = 760.0
const DASH_TIME: float = 0.18
const DASH_COOLDOWN: float = 0.4
const ATTACK_ACTIVE: float = 0.15
const ATTACK_COOLDOWN: float = 0.35
const POGO_V: float = -600.0
const RECOIL_SPEED: float = 220.0
const IFRAMES: float = 1.2
const STUN: float = 0.25

var max_hp: int = 5
var hp: int = 5
var facing: int = 1
var can_dash: bool = true
var invuln: float = 0.0
var attack_dir: Vector2 = Vector2.RIGHT
var _coyote: float = 0.0
var _buffer: float = 0.0
var _dash_t: float = 0.0
var _dash_cd: float = 0.0
var _attack_t: float = 0.0
var _attack_cd: float = 0.0
var _stun: float = 0.0
var _hit_set: Array = []
var _dead: bool = false
var _hitstop_n: int = 0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(26, 52)
	cs.shape = sh
	add_child(cs)
	add_to_group("hk_player")
	health_changed.emit(hp, max_hp)

func _physics_process(delta: float) -> void:
	if _dead:
		return
	invuln = maxf(0.0, invuln - delta)
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_buffer -= delta
	if Input.is_action_just_pressed("hk_jump"):
		_buffer = JUMP_BUFFER
	if is_on_floor():
		_coyote = COYOTE
		can_dash = true
	else:
		_coyote -= delta

	if _dash_t > 0.0:
		_dash_t -= delta
		velocity = Vector2(float(facing) * DASH_SPEED, 0.0)
		move_and_slide()
		_tick_attack(delta)
		queue_redraw()
		return

	if Input.is_action_just_pressed("hk_dash") and can_dash and _dash_cd <= 0.0 and _stun <= 0.0:
		can_dash = false
		_dash_t = DASH_TIME
		_dash_cd = DASH_COOLDOWN
		return

	var move: float = Input.get_axis("hk_left", "hk_right")
	if _stun > 0.0:
		_stun -= delta
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	else:
		velocity.x = move * RUN_SPEED
		if move != 0.0:
			facing = 1 if move > 0.0 else -1

	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_V
		_buffer = 0.0
		_coyote = 0.0
	if Input.is_action_just_released("hk_jump") and velocity.y < 0.0:
		velocity.y *= JUMP_CUT

	if Input.is_action_just_pressed("hk_attack") and _attack_cd <= 0.0 and _stun <= 0.0:
		_start_attack()
	move_and_slide()
	_tick_attack(delta)
	queue_redraw()

func _start_attack() -> void:
	if Input.is_action_pressed("hk_up"):
		attack_dir = Vector2.UP
	elif Input.is_action_pressed("hk_down") and not is_on_floor():
		attack_dir = Vector2.DOWN
	else:
		attack_dir = Vector2(float(facing), 0.0)
	_attack_t = ATTACK_ACTIVE
	_attack_cd = ATTACK_COOLDOWN
	_hit_set.clear()

func _tick_attack(delta: float) -> void:
	if _attack_t <= 0.0:
		return
	_attack_t -= delta
	var size: Vector2 = Vector2(84, 56) if attack_dir.y == 0.0 else Vector2(60, 80)
	var q := PhysicsShapeQueryParameters2D.new()
	var sh := RectangleShape2D.new()
	sh.size = size
	q.shape = sh
	q.transform = Transform2D(0.0, global_position + attack_dir * 52.0)
	q.collision_mask = 4
	for r in get_world_2d().direct_space_state.intersect_shape(q, 8):
		var c = r["collider"]
		if c in _hit_set or not c.has_method("take_hit"):
			continue
		_hit_set.append(c)
		c.take_hit(1, global_position)
		_on_nail_hit()

func _on_nail_hit() -> void:
	if attack_dir.y > 0.0:
		velocity.y = POGO_V # pogo: chém xuống trúng thì nảy lên và hồi dash
		can_dash = true
	elif attack_dir.y == 0.0:
		velocity.x = -attack_dir.x * RECOIL_SPEED
		_stun = 0.08
	hit_landed.emit(1.0)
	_hitstop(0.05)

func take_damage(from_x: float, dmg: int = 1) -> void:
	if invuln > 0.0 or _dead:
		return
	hp = maxi(0, hp - dmg)
	invuln = IFRAMES
	_stun = STUN
	_dash_t = 0.0
	_attack_t = 0.0
	velocity = Vector2(signf(global_position.x - from_x) * 320.0, -280.0)
	health_changed.emit(hp, max_hp)
	hit_landed.emit(2.0)
	_hitstop(0.08)
	if hp <= 0:
		_dead = true
		died.emit()

## Dừng hình thật ngắn khi trúng đòn (tính theo thời gian thực, không bị time_scale kéo dài).
func _hitstop(sec: float) -> void:
	_hitstop_n += 1
	Engine.time_scale = 0.05
	await get_tree().create_timer(sec, true, false, true).timeout
	_hitstop_n -= 1
	if _hitstop_n <= 0:
		Engine.time_scale = 1.0

func _draw() -> void:
	var a: float = 0.4 if invuln > 0.0 and int(invuln * 20.0) % 2 == 0 else 1.0
	draw_rect(Rect2(-13, -26, 26, 52), Color(0.85, 0.9, 1.0, a))
	draw_rect(Rect2(float(facing) * 5.0 - 3.0, -16, 6, 8), Color(0.05, 0.05, 0.1, a))
	if _attack_t > 0.0:
		var c := Color(1, 1, 1, 0.8)
		draw_rect(Rect2(attack_dir * 52.0 - (Vector2(42, 28) if attack_dir.y == 0.0 else Vector2(30, 40)), Vector2(84, 56) if attack_dir.y == 0.0 else Vector2(60, 80)), c)
