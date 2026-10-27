extends CharacterBody2D
## Nhân vật kiểu Hollow Knight: chạy, nhảy cao thấp tuỳ giữ phím, dash, chém 4 hướng, pogo, Focus hồi máu, Soul Bolt,
## double jump và bám tường (mở khoá bằng kỹ năng). Máu/soul/kỹ năng nằm trong HKState (sống qua các phòng).
signal hit_landed(strength: float)
signal health_changed(hp: int, max_hp: int)
signal soul_changed(soul: int)
signal died
signal hazard_hit
signal sfx(name: String)   # báo lên world để phát âm thanh

const STATE = preload("res://hk/state.gd")
const PROJECTILE = preload("res://hk/projectile.gd")
const FX = preload("res://hk/fx.gd")
const SPRITES = preload("res://hk/sprites.gd")
## Hộp va chạm: rộng = 80% phần nhìn thấy (30px), cao = phần nhìn thấy (42px) + 2. Đáy hộp = chân nhân vật.
const BODY: Vector2 = Vector2(24, 44)
const FOOT: float = 22.0   # BODY.y / 2
const GROUND_ACCEL: float = 6000.0   # đạt RUN_SPEED trong 0.05s trên mặt đất; trên không giữ điều khiển tức thì

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
const POGO_V: float = -600.0
const RECOIL_SPEED: float = 220.0
const IFRAMES: float = 1.2
const STUN: float = 0.25
const WALL_SLIDE: float = 90.0
const WALL_LOCK: float = 0.18
const SPELL_COST: int = 33
const SPELL_DAMAGE: int = 15
const SPELL_COOLDOWN: float = 0.45

var hp: int:
	get: return STATE.hp
	set(v): STATE.hp = v
var max_hp: int:
	get: return STATE.max_hp()
var soul: int:
	get: return STATE.soul
var facing: int = 1
var can_dash: bool = true
var invuln: float = 0.0
var attack_dir: Vector2 = Vector2.RIGHT
var controls_enabled: bool = true
var focusing: bool = false
var _air_jumps: int = 1
var _coyote: float = 0.0
var _buffer: float = 0.0
var _dash_t: float = 0.0
var _dash_cd: float = 0.0
var _attack_t: float = 0.0
var _attack_cd: float = 0.0
var _spell_cd: float = 0.0
var _stun: float = 0.0
var _wall_lock: float = 0.0
var _wall_coyote: float = 0.0
var _wall_dir: int = 0
var _focus_t: float = 0.0
var _hit_set: Array = []
var _dead: bool = false
var _hitstop_n: int = 0
var _air_t: float = 0.0
var _trail: Array = []   # bóng mờ khi dash: {p, t, f}

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = BODY
	cs.shape = sh
	add_child(cs)
	add_to_group("hk_player")
	health_changed.emit(hp, max_hp)
	soul_changed.emit(soul)

func _physics_process(delta: float) -> void:
	if _dead:
		return
	invuln = maxf(0.0, invuln - delta)
	for g in _trail:
		g["t"] -= delta
	_trail = _trail.filter(func(g): return g["t"] > 0.0)
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_spell_cd = maxf(0.0, _spell_cd - delta)
	_wall_lock = maxf(0.0, _wall_lock - delta)
	_wall_coyote -= delta
	if not controls_enabled:
		velocity.x = 0.0
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
		move_and_slide()
		return
	_buffer -= delta
	if Input.is_action_just_pressed("hk_jump"):
		_buffer = JUMP_BUFFER
	if is_on_floor():
		_coyote = COYOTE
		can_dash = true
		_air_jumps = 1
	else:
		_coyote -= delta

	if _focus(delta):
		queue_redraw()
		return

	if _dash_t > 0.0:
		_dash_t -= delta
		velocity = Vector2(float(facing) * DASH_SPEED, 0.0)
		_trail.append({"p": global_position, "t": 0.18, "f": facing})
		move_and_slide()
		_tick_attack(delta)
		queue_redraw()
		return

	if Input.is_action_just_pressed("hk_dash") and STATE.has_ability("dash") and can_dash and _dash_cd <= 0.0 and _stun <= 0.0:
		can_dash = false
		sfx.emit("dash")
		_dash_t = DASH_TIME
		_dash_cd = DASH_COOLDOWN
		return

	var move: float = Input.get_axis("hk_left", "hk_right")
	if _stun > 0.0:
		_stun -= delta
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	elif _wall_lock <= 0.0:
		var target: float = move * RUN_SPEED
		velocity.x = move_toward(velocity.x, target, GROUND_ACCEL * delta) if is_on_floor() else target
		if move != 0.0:
			facing = 1 if move > 0.0 else -1

	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
	var clinging: bool = _update_wall(move)
	if clinging:
		velocity.y = minf(velocity.y, WALL_SLIDE)

	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_V
		_buffer = 0.0
		_coyote = 0.0
		sfx.emit("jump")
	elif _buffer > 0.0 and _wall_coyote > 0.0 and STATE.has_ability("wall_cling"):
		velocity = Vector2(-float(_wall_dir) * 320.0, JUMP_V * 0.95)
		facing = -_wall_dir
		sfx.emit("wall_jump")
		_wall_lock = WALL_LOCK
		_buffer = 0.0
		_wall_coyote = 0.0
	elif _buffer > 0.0 and _air_jumps > 0 and STATE.has_ability("double_jump"):
		velocity.y = JUMP_V * 0.92
		_air_jumps -= 1
		sfx.emit("double_jump")
		_buffer = 0.0
		FX.burst(get_parent(), global_position + Vector2(0, FOOT), Color(0.8, 0.85, 1.0), 6, 100.0)
	if Input.is_action_just_released("hk_jump") and velocity.y < 0.0:
		velocity.y *= JUMP_CUT

	if Input.is_action_just_pressed("hk_attack") and _attack_cd <= 0.0 and _stun <= 0.0:
		_start_attack()
	if Input.is_action_just_pressed("hk_spell") and _spell_cd <= 0.0 and _stun <= 0.0 and STATE.soul >= SPELL_COST:
		_cast_spell()
	move_and_slide()
	_track_air(delta)
	_tick_attack(delta)
	queue_redraw()

## Theo dõi thời gian trên không: tiếp đất sau cú rơi đủ dài thì bụi + tiếng.
func _track_air(delta: float) -> void:
	if is_on_floor():
		if _air_t > 0.18:
			sfx.emit("land")
			FX.burst(get_parent(), global_position + Vector2(0, FOOT), Color(0.7, 0.7, 0.75), 5, 90.0)
		_air_t = 0.0
	else:
		_air_t += delta

## Bám tường: cần kỹ năng, đang ở trên không, ép vào tường. Trả về true nếu đang bám.
func _update_wall(move: float) -> bool:
	if not STATE.has_ability("wall_cling") or is_on_floor() or not is_on_wall():
		return false
	var n: Vector2 = get_wall_normal()
	var toward: int = -int(signf(n.x))
	_wall_dir = toward
	_wall_coyote = 0.1
	can_dash = true
	_air_jumps = 1
	return int(signf(move)) == toward and velocity.y > 0.0

## Focus: giữ phím khi đứng yên trên đất, đủ Soul thì hồi 1 mặt nạ. Trả về true nếu đang chiếm điều khiển.
func _focus(delta: float) -> bool:
	var want: bool = Input.is_action_pressed("hk_focus") and is_on_floor() and _stun <= 0.0 and STATE.soul >= SPELL_COST and hp < max_hp
	if not want:
		focusing = false
		_focus_t = 0.0
		return false
	focusing = true
	velocity.x = 0.0
	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
	move_and_slide()
	_focus_t += delta
	if _focus_t >= STATE.focus_time():
		_focus_t = 0.0
		STATE.soul -= SPELL_COST
		hp = mini(max_hp, hp + 1)
		health_changed.emit(hp, max_hp)
		soul_changed.emit(soul)
		FX.burst(get_parent(), global_position, Color(1, 1, 1), 10, 140.0)
		sfx.emit("heal")
	return true

func _cast_spell() -> void:
	sfx.emit("spell")
	STATE.soul -= SPELL_COST
	soul_changed.emit(soul)
	_spell_cd = SPELL_COOLDOWN
	var s := Area2D.new()
	s.set_script(PROJECTILE)
	s.friendly = true
	s.pierce = true
	s.damage = SPELL_DAMAGE
	s.radius = 14.0
	s.life = 0.7
	s.vel = Vector2(float(facing) * 700.0, 0.0)
	s.color = Color(0.6, 0.8, 1.0)
	get_parent().add_child.call_deferred(s)
	s.position = position + Vector2(float(facing) * 24.0, -6.0)
	_stun = 0.1
	velocity.x = -float(facing) * 120.0

func _start_attack() -> void:
	if Input.is_action_pressed("hk_up"):
		attack_dir = Vector2.UP
	elif Input.is_action_pressed("hk_down") and not is_on_floor():
		attack_dir = Vector2.DOWN
	else:
		attack_dir = Vector2(float(facing), 0.0)
	_attack_t = ATTACK_ACTIVE
	sfx.emit("slash")
	_attack_cd = STATE.attack_cooldown()
	_hit_set.clear()

## Vùng đánh thật (toạ độ thế giới) theo hướng chém hiện tại. Vùng truy vấn va chạm, vệt chém và debug đều dùng hàm này.
func is_attacking() -> bool:
	return _attack_t > 0.0

func attack_rect() -> Rect2:
	var size: Vector2 = _attack_size()
	var c: Vector2 = global_position + attack_dir * (10.0 + (size.x if attack_dir.y == 0.0 else size.y) * 0.5)
	return Rect2(c - size * 0.5, size)

func _attack_size() -> Vector2:
	var r: float = STATE.nail_reach_mult()
	return Vector2(84.0 * r, 56.0) if attack_dir.y == 0.0 else Vector2(60.0, 80.0 * r)

func _tick_attack(delta: float) -> void:
	if _attack_t <= 0.0:
		return
	_attack_t -= delta
	var rc: Rect2 = attack_rect()
	var q := PhysicsShapeQueryParameters2D.new()
	var sh := RectangleShape2D.new()
	sh.size = rc.size
	q.shape = sh
	q.transform = Transform2D(0.0, rc.get_center())
	q.collision_mask = 4
	for r in get_world_2d().direct_space_state.intersect_shape(q, 8):
		var c = r["collider"]
		if c in _hit_set or not c.has_method("take_hit"):
			continue
		_hit_set.append(c)
		if c.take_hit(STATE.nail_damage(), global_position) == false:
			_on_blocked()
		else:
			_on_nail_hit()

func _on_blocked() -> void:   # khiên chặn: bật lùi như chém trúng nhưng không cộng Soul/pogo
	if attack_dir.y == 0.0:
		velocity.x = -attack_dir.x * RECOIL_SPEED
		_stun = 0.08
	_attack_t = 0.0

func _on_nail_hit() -> void:
	sfx.emit("hit")
	if attack_dir.y > 0.0:
		velocity.y = POGO_V # pogo: chém xuống trúng thì nảy lên và hồi dash
		can_dash = true
		_air_jumps = 1
	elif attack_dir.y == 0.0:
		velocity.x = -attack_dir.x * RECOIL_SPEED
		_stun = 0.08
	STATE.soul = mini(STATE.SOUL_MAX, STATE.soul + STATE.soul_per_hit())
	soul_changed.emit(soul)
	hit_landed.emit(1.0)
	_hitstop(0.05)

func take_damage(from_x: float, dmg: int = 1) -> void:
	if invuln > 0.0 or _dead or not controls_enabled:
		return
	hp = maxi(0, hp - dmg)
	invuln = IFRAMES
	_stun = STUN
	_dash_t = 0.0
	_attack_t = 0.0
	_focus_t = 0.0
	velocity = Vector2(signf(global_position.x - from_x) * 320.0, -280.0)
	health_changed.emit(hp, max_hp)
	hit_landed.emit(2.0)
	sfx.emit("hurt" if hp > 0 else "die")
	_hitstop(0.08)
	if hp <= 0:
		_dead = true
		died.emit()

## Gai/hầm: mất 1 mặt nạ rồi world đưa về chỗ an toàn.
func hazard_damage(from_x: float) -> void:
	if invuln > 0.0 or _dead:
		return
	take_damage(from_x)
	if not _dead:
		hazard_hit.emit()

func respawn_at(pos: Vector2, refill: bool = false) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	_stun = 0.0
	_dash_t = 0.0
	_attack_t = 0.0
	if refill:
		hp = max_hp
		_dead = false
		invuln = 1.0
		health_changed.emit(hp, max_hp)

func is_dead() -> bool:
	return _dead

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
	if focusing:
		draw_circle(Vector2.ZERO, 34.0 + sin(_focus_t * 20.0) * 3.0, Color(1, 1, 1, 0.25))
	var foot := Vector2(0, FOOT)
	for g in _trail:
		SPRITES.draw_body(self, "knight_m_run_anim", Vector2(g["p"]) - global_position + foot, 2.0, int(g["f"]) < 0, Color(0.5, 0.8, 1.5, 0.5 * float(g["t"]) / 0.18))
	var base: String = "knight_m_idle_anim"
	if _stun > 0.0:
		base = "knight_m_hit_anim"
	elif is_on_floor() and absf(velocity.x) > 20.0:
		base = "knight_m_run_anim"
	var tint := Color(1.6, 1.6, 2.0, a) if _dash_t > 0.0 else Color(1, 1, 1, a)
	SPRITES.draw_body(self, base, foot, 2.0, facing < 0, tint, 10.0)
	if _attack_t > 0.0:
		# vệt chém = nửa elip nằm trọn trong vùng đánh thật (attack_rect)
		var rc: Rect2 = attack_rect()
		var horiz: bool = attack_dir.y == 0.0
		var f: Vector2 = attack_dir
		var pdir := Vector2(-f.y, f.x)
		var ea: float = (rc.size.x if horiz else rc.size.y) * 0.5
		var eb: float = (rc.size.y if horiz else rc.size.x) * 0.5
		var c: Vector2 = rc.get_center() - global_position - f * ea
		var fade: float = clampf(_attack_t / ATTACK_ACTIVE, 0.0, 1.0)
		var pts := PackedVector2Array()
		for k in 13:
			var th: float = -PI * 0.5 + PI * float(k) / 12.0
			pts.append(c + f * cos(th) * ea + pdir * sin(th) * eb)
		draw_polyline(pts, Color(1, 1, 1, 0.85 * fade), 6.0)
		var pts2 := PackedVector2Array()
		for k in 13:
			var th2: float = -PI * 0.5 + PI * float(k) / 12.0
			pts2.append(c + f * cos(th2) * ea * 0.82 + pdir * sin(th2) * eb * 0.82)
		draw_polyline(pts2, Color(0.7, 0.85, 1, 0.5 * fade), 3.0)
