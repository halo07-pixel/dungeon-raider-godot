extends CharacterBody2D
## Quái thường. `kind` chọn hành vi: crawler (bò tuần), flyer (bay đuổi), spitter (đứng bắn), charger (húc).
## Gán `kind` TRƯỚC khi add_child.
signal died(pos: Vector2)
signal sfx(name: String)
const PROJECTILE = preload("res://hk/projectile.gd")
const FX = preload("res://hk/fx.gd")
const STATE = preload("res://hk/state.gd")
const GRAVITY: float = 2400.0

const SPRITES = preload("res://hk/sprites.gd")
const LOOK: Dictionary = {   # sprite + hệ số phóng; đáy sprite khớp đáy hộp va chạm
	"crawler": {"anim": "slug_anim", "scale": 1.5},
	"flyer": {"anim": "hell_imp_idle_anim", "scale": 2.0},
	"spitter": {"anim": "orc_shaman_anim", "scale": 2.0},
	"charger": {"anim": "chort_anim", "scale": 2.0},
}
const DATA: Dictionary = {
	"crawler": {"hp": 12, "geo": 1, "color": Color(0.75, 0.35, 0.3)},
	"flyer": {"hp": 10, "geo": 2, "color": Color(0.6, 0.4, 0.8)},
	"spitter": {"hp": 14, "geo": 2, "color": Color(0.5, 0.65, 0.3)},
	"charger": {"hp": 24, "geo": 3, "color": Color(0.85, 0.5, 0.2)},
}

var kind: String = "crawler"

## Hộp va chạm = phần nhìn thấy của sprite (xem hk/bodies.gd), nên hình và hộp luôn khớp.
static func body_size(k: String) -> Vector2:
	var look: Dictionary = LOOK[k]
	return SPRITES.BODIES.rect(String(look["anim"]), float(look["scale"])).size
var hp: int = 10
var dir: int = -1
var state: String = "idle"     # charger/spitter: idle | windup | lunge | recover
var _t: float = 0.0
var _kb_t: float = 0.0
var _flash: float = 0.0
var _contact: Area2D
var _home: Vector2
var _size: Vector2
var _time: float = 0.0

func _ready() -> void:
	var d: Dictionary = DATA[kind]
	hp = int(d["hp"])
	_size = body_size(kind)
	collision_layer = 4
	collision_mask = 1
	add_to_group("hk_enemy")
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = _size
	cs.shape = sh
	add_child(cs)
	_contact = Area2D.new()
	_contact.collision_layer = 0
	_contact.collision_mask = 2
	var c2 := CollisionShape2D.new()
	var hs := RectangleShape2D.new()
	hs.size = _size * 0.85   # vùng gây sát thương nhỏ hơn thân một chút
	c2.shape = hs
	_contact.add_child(c2)
	add_child(_contact)
	_home = position

func _player() -> Node2D:
	var ps := get_tree().get_nodes_in_group("hk_player")
	return ps[0] if not ps.is_empty() else null

func _physics_process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta)
	_t -= delta
	if _kb_t > 0.0:
		_kb_t -= delta
	match kind:
		"crawler": _crawler(delta)
		"flyer": _flyer(delta)
		"spitter": _spitter(delta)
		"charger": _charger(delta)
	for b in _contact.get_overlapping_bodies():
		if b.has_method("take_damage"):
			b.take_damage(global_position.x)
	queue_redraw()

func body_rect() -> Rect2:
	return Rect2(global_position - _size * 0.5, _size)

func contact_rect() -> Rect2:
	return Rect2(global_position - _size * 0.425, _size * 0.85)

func _gravity_and_move(delta: float) -> void:
	velocity.y = minf(velocity.y + GRAVITY * delta, 900.0)
	move_and_slide()

func _patrol(speed: float, delta: float) -> void:
	if _kb_t > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 700.0 * delta)
	else:
		velocity.x = float(dir) * speed
	_gravity_and_move(delta)
	if _kb_t <= 0.0 and is_on_floor() and (is_on_wall() or not _ground_ahead()):
		dir = -dir

func _crawler(delta: float) -> void:
	_patrol(70.0, delta)

func _charger(delta: float) -> void:
	var p := _player()
	match state:
		"idle":
			_patrol(50.0, delta)
			if p and _kb_t <= 0.0 and absf(p.global_position.y - global_position.y) < 60.0 and absf(p.global_position.x - global_position.x) < 340.0 and signf(p.global_position.x - global_position.x) == float(dir):
				state = "windup"
				_t = 0.5
		"windup":
			velocity.x = 0.0
			_gravity_and_move(delta)
			if _t <= 0.0:
				state = "lunge"
				sfx.emit("charge")
				_t = 0.55
		"lunge":
			velocity.x = float(dir) * 520.0
			_gravity_and_move(delta)
			if _t <= 0.0 or is_on_wall():
				state = "recover"
				_t = 0.7
		"recover":
			velocity.x = 0.0
			_gravity_and_move(delta)
			if _t <= 0.0:
				state = "idle"
				dir = -dir if randf() < 0.3 else dir

func _flyer(delta: float) -> void:
	var p := _player()
	var target: Vector2 = _home + Vector2(0, sin(_time * 2.0) * 14.0)
	var speed: float = 60.0
	if p and p.global_position.distance_to(global_position) < 380.0:
		target = p.global_position + Vector2(0, -20)
		speed = 120.0
	var want: Vector2 = (target - global_position)
	want = want.normalized() * minf(speed, want.length() * 4.0)
	if _kb_t > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
	else:
		velocity = velocity.move_toward(want, 500.0 * delta)
	move_and_slide()

func _spitter(delta: float) -> void:
	velocity.x = 0.0
	_gravity_and_move(delta)
	var p := _player()
	if p == null:
		return
	dir = 1 if p.global_position.x > global_position.x else -1
	match state:
		"idle":
			if _t <= 0.0 and p.global_position.distance_to(global_position) < 460.0:
				state = "windup"
				_t = 0.6
		"windup":
			if _t <= 0.0:
				var s := PROJECTILE.new()
				s.set_script(PROJECTILE)
				s.friendly = false
				s.vel = (p.global_position - global_position).normalized() * 280.0
				s.color = Color(0.6, 0.9, 0.3)
				get_parent().add_child.call_deferred(s)
				s.position = position + Vector2(0, -8)
				sfx.emit("spit")
				state = "idle"
				_t = 2.0

func _ground_ahead() -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position + Vector2(float(dir) * (_size.x * 0.5 + 6.0), 0.0), global_position + Vector2(float(dir) * (_size.x * 0.5 + 6.0), _size.y * 0.5 + 24.0), 1)
	return not get_world_2d().direct_space_state.intersect_ray(q).is_empty()

func take_hit(dmg: int, from_pos: Vector2) -> void:
	if hp <= 0:
		return
	hp -= dmg
	_flash = 0.1
	_kb_t = 0.2
	var away: float = signf(global_position.x - from_pos.x)
	if kind == "flyer":
		velocity = Vector2(away * 260.0, -60.0)
	elif kind != "spitter":
		velocity.x = away * 260.0
	if kind == "charger" and state == "windup":
		state = "idle"
	FX.burst(get_parent(), global_position, DATA[kind]["color"], 5, 120.0)
	if hp <= 0:
		_die()

func _die() -> void:
	var n: int = roundi(float(DATA[kind]["geo"]) * (STATE.geo_mult()) * (1.0 + randf() * 0.5))
	n = maxi(1, n)
	STATE.geo += n
	FX.float_text(get_parent(), global_position, "+%d" % n, Color(1.0, 0.9, 0.4))
	FX.burst(get_parent(), global_position, DATA[kind]["color"], 12, 220.0)
	sfx.emit("enemy_die")
	died.emit(global_position)
	queue_free()

func _draw() -> void:
	var tint := Color.WHITE
	if _flash > 0.0:
		tint = Color(3, 3, 3)
	elif state == "windup" and int(_time * 30.0) % 2 == 0:
		tint = Color(1.6, 0.7, 0.7)
	var look: Dictionary = LOOK[kind]
	SPRITES.draw_body(self, String(look["anim"]), Vector2(0, _size.y * 0.5), float(look["scale"]), dir < 0, tint)
