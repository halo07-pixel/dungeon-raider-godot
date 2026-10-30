extends CharacterBody2D
## Quái thường. `kind` chọn hành vi: crawler (bò tuần), flyer (bay đuổi), spitter (đứng bắn), charger (húc),
## guard (khiên chặn đòn chính diện, húc khiên), dropper (treo trần, rơi xuống khi người chơi đi qua bên dưới).
## Quái riêng theo khu (dựa trên quái cũ, chỉ đổi hành vi): sentry (Gate; khiên, đứng yên, gọi 1 crawler con), reviver (Catacomb; nằm
## xuống 2s rồi đứng dậy một lần với nửa máu), cinder (Vault; húc như charger nhưng để lại vệt lửa 2s), bubbler (Archive; nhả bong bóng làm chậm).
## Gán `kind` TRƯỚC khi add_child.
signal died(pos: Vector2)
signal sfx(name: String)
const PROJECTILE = preload("res://hk/projectile.gd")
const FX = preload("res://hk/fx.gd")
const ZONE = preload("res://hk/zone.gd")
const STATE = preload("res://hk/state.gd")
const GRAVITY: float = 2400.0

const SPRITES = preload("res://hk/sprites.gd")
const LOOK: Dictionary = {   # sprite + hệ số phóng; đáy sprite khớp đáy hộp va chạm
	"crawler": {"anim": "slug_anim", "scale": 1.5},
	"flyer": {"anim": "hell_imp_idle_anim", "scale": 2.0},
	"spitter": {"anim": "orc_shaman_anim", "scale": 2.0},
	"charger": {"anim": "chort_anim", "scale": 2.0},
	"guard": {"anim": "orc_warrior_idle_anim", "scale": 2.0},
	"dropper": {"anim": "hell_acolyte_anim", "scale": 2.0},
	"sentry": {"anim": "orc_warrior_idle_anim", "scale": 2.0, "tint": Color(0.7, 0.85, 1.3)},
	"reviver": {"anim": "frost_zombie_anim", "scale": 1.8},
	"cinder": {"anim": "chort_anim", "scale": 2.0, "tint": Color(1.5, 0.7, 0.45)},
	"bubbler": {"anim": "orc_shaman_anim", "scale": 2.0, "tint": Color(0.6, 0.9, 1.4)},
}
const DATA: Dictionary = {
	"crawler": {"hp": 12, "geo": 2, "color": Color(0.75, 0.35, 0.3)},
	"flyer": {"hp": 10, "geo": 3, "color": Color(0.6, 0.4, 0.8)},
	"spitter": {"hp": 14, "geo": 3, "color": Color(0.5, 0.65, 0.3)},
	"charger": {"hp": 24, "geo": 5, "color": Color(0.85, 0.5, 0.2)},
	"guard": {"hp": 22, "geo": 6, "color": Color(0.6, 0.65, 0.78)},
	"dropper": {"hp": 12, "geo": 5, "color": Color(0.55, 0.35, 0.6)},
	"sentry": {"hp": 18, "geo": 4, "color": Color(0.5, 0.7, 0.95)},
	"reviver": {"hp": 10, "geo": 3, "color": Color(0.7, 0.85, 0.9)},
	"cinder": {"hp": 20, "geo": 5, "color": Color(0.95, 0.45, 0.2)},
	"bubbler": {"hp": 12, "geo": 3, "color": Color(0.5, 0.8, 1.0)},
}
const REVIVE_AFTER: float = 2.0   # reviver nằm bao lâu rồi đứng dậy
const FIRE_TRAIL: float = 2.0     # cinder: vệt lửa tồn tại bao lâu

var kind: String = "crawler"
var minion: bool = false       # quái do sentry gọi: không rơi Geo (chống cày)
var _revived: bool = false     # reviver: đã đứng dậy một lần
var _minion_ref: Node2D        # sentry: con crawler đang sống (tối đa 1)
var _trail_t: float = 0.0

## Hộp va chạm = phần nhìn thấy của sprite (xem hk/bodies.gd), nên hình và hộp luôn khớp.
static func body_size(k: String) -> Vector2:
	var look: Dictionary = LOOK[k]
	return SPRITES.BODIES.rect(String(look["anim"]), float(look["scale"])).size
var hp: int = 10
var dir: int = -1
var _prev_state: String = ""
var state: String = "idle"     # charger/spitter: idle | windup | lunge | recover
var _t: float = 0.0
var _kb_t: float = 0.0
var _flash: float = 0.0
var _contact: Area2D
var _home: Vector2
var _size: Vector2
var _time: float = 0.0
var _block_flash: float = 0.0

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
	if state == "windup" and _prev_state != "windup":
		sfx.emit("tell")   # âm báo trước đòn (không còn vùng cảnh báo màu); sprite vẫn nhấp nháy lúc windup
	_prev_state = state
	_time += delta
	_flash = maxf(0.0, _flash - delta)
	_block_flash = maxf(0.0, _block_flash - delta)
	_t -= delta
	if _kb_t > 0.0:
		_kb_t -= delta
	match kind:
		"crawler": _crawler(delta)
		"flyer": _flyer(delta)
		"spitter", "bubbler": _spitter(delta)
		"charger", "cinder": _charger(delta)
		"guard": _guard(delta)
		"sentry": _sentry(delta)
		"reviver": _reviver(delta)
		"dropper": _dropper(delta)
	for b in (_contact.get_overlapping_bodies() if state != "down" else []):
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
			if kind == "cinder":
				_trail_t -= delta
				if _trail_t <= 0.0:
					_trail_t = 0.12
					_drop_fire()
			if _t <= 0.0 or is_on_wall():
				state = "recover"
				_t = 0.7
		"recover":
			velocity.x = 0.0
			_gravity_and_move(delta)
			if _t <= 0.0:
				state = "idle"
				dir = -dir if randf() < 0.3 else dir

## Khiên chắn phía trước (hướng `dir`) trừ lúc đang hạ khiên (recover) và khi bị chém từ trên xuống (pogo) hoặc từ sau lưng.
func _blocks(from_pos: Vector2) -> bool:
	if state == "recover":
		return false
	if from_pos.y < global_position.y - _size.y * 0.5 - 6.0:
		return false
	return signf(from_pos.x - global_position.x) == float(dir)

func _guard(delta: float) -> void:
	var p := _player()
	var near: bool = p != null and absf(p.global_position.y - global_position.y) < 80.0 and absf(p.global_position.x - global_position.x) < 320.0
	match state:
		"idle":
			if near and _kb_t <= 0.0:
				dir = 1 if p.global_position.x > global_position.x else -1
				var gap: float = absf(p.global_position.x - global_position.x)
				if gap < 95.0 and _t <= 0.0:
					state = "windup"
					_t = 0.45
					velocity.x = 0.0
					_gravity_and_move(delta)
					return
				if gap > 60.0:
					velocity.x = float(dir) * 55.0
					_gravity_and_move(delta)
					if is_on_floor() and not _ground_ahead():
						velocity.x = 0.0
				else:
					velocity.x = 0.0
					_gravity_and_move(delta)
			else:
				_patrol(35.0, delta)
		"windup":
			velocity.x = 0.0
			_gravity_and_move(delta)
			if _t <= 0.0:
				state = "bash"
				sfx.emit("charge")
				_t = 0.25
		"bash":
			velocity.x = float(dir) * 340.0
			_gravity_and_move(delta)
			if _t <= 0.0 or is_on_wall() or (is_on_floor() and not _ground_ahead()):
				state = "recover"
				_t = 0.9
		"recover":
			velocity.x = 0.0
			_gravity_and_move(delta)
			if _t <= 0.0:
				state = "idle"
				_t = 0.8

## Treo trần (hang) -> rung (shake) khi người chơi ở ngay bên dưới -> rơi (drop) -> choáng (land) -> bò lên lại (rise).
func _dropper(delta: float) -> void:
	var p := _player()
	match state:
		"idle", "hang":
			state = "hang"
			velocity = Vector2.ZERO
			global_position = _home
			if p and _t <= 0.0 and absf(p.global_position.x - global_position.x) < 70.0 and p.global_position.y > global_position.y + _size.y and p.global_position.y - global_position.y < 760.0:
				state = "shake"
				_t = 0.4
		"shake":
			velocity = Vector2.ZERO
			if _t <= 0.0:
				state = "drop"
		"drop":
			velocity = Vector2(0.0, 760.0)
			move_and_slide()
			if is_on_floor():
				state = "land"
				_t = 0.9
				velocity = Vector2.ZERO
				sfx.emit("slam")
		"land":
			velocity = Vector2.ZERO
			if _t <= 0.0:
				state = "rise"
		"rise":
			velocity = Vector2(0.0, -110.0)
			move_and_slide()
			if global_position.y <= _home.y:
				state = "hang"
				_t = 1.2

## Sentry: đứng yên sau khiên (chặn như guard), khi người chơi vào tầm thì rung chuông gọi một crawler con (tối đa 1 con sống).
func _sentry(delta: float) -> void:
	velocity.x = 0.0
	_gravity_and_move(delta)
	var p := _player()
	if p == null:
		return
	if state != "windup":
		dir = 1 if p.global_position.x > global_position.x else -1
	match state:
		"idle":
			var near: bool = absf(p.global_position.y - global_position.y) < 140.0 and absf(p.global_position.x - global_position.x) < 420.0
			if near and _t <= 0.0 and not is_instance_valid(_minion_ref):
				state = "windup"
				_t = 0.7
		"windup":
			if _t <= 0.0:
				var e := CharacterBody2D.new()
				e.set_script(get_script())
				e.kind = "crawler"
				e.minion = true
				e.dir = dir
				get_parent().add_child.call_deferred(e)
				e.position = global_position + Vector2(float(dir) * (_size.x * 0.5 + 24.0), _size.y * 0.5 - body_size("crawler").y * 0.5)
				_minion_ref = e
				FX.burst(get_parent(), global_position + Vector2(float(dir) * _size.x * 0.5, 0.0), DATA[kind]["color"], 8, 140.0)
				state = "recover"
				_t = 0.9
		"recover":
			if _t <= 0.0:
				state = "idle"
				_t = 2.5

## Reviver: bò tuần như crawler; "chết" lần đầu thì nằm (down) REVIVE_AFTER giây rồi đứng dậy với nửa máu. Đánh nó lúc đang nằm là diệt hẳn.
func _reviver(delta: float) -> void:
	if state == "down":
		velocity.x = 0.0
		_gravity_and_move(delta)
		if _t <= 0.0:
			state = "idle"
			hp = maxi(1, int(DATA[kind]["hp"]) / 2)
		return
	_patrol(60.0, delta)

## Vệt lửa của cinder: vùng gây hại nằm trên sàn dưới chân (dùng lại zone.gd), tự tắt sau FIRE_TRAIL giây.
func _drop_fire() -> void:
	var z := Node2D.new()
	z.set_script(ZONE)
	z.kind = "flame"
	z.rect = Rect2(global_position.x - 14.0, global_position.y + _size.y * 0.5 - 22.0, 28.0, 22.0)
	z.life = FIRE_TRAIL
	z.fx_parent = get_parent()
	get_parent().add_child.call_deferred(z)

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
				if kind == "bubbler":   # bong bóng chậm, không gây sát thương: chỉ làm chậm người chơi
					s.slows = true
					s.radius = 12.0
					s.life = 4.0
					s.vel = (p.global_position - global_position).normalized() * 150.0
					s.color = Color(0.5, 0.8, 1.0, 0.7)
				else:
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

## Trả false khi khiên chặn (không mất máu, không cộng Soul); các trường hợp khác trả true.
func take_hit(dmg: int, from_pos: Vector2) -> bool:
	if hp <= 0:
		return false
	if (kind == "guard" or kind == "sentry") and _blocks(from_pos):
		_block_flash = 0.15
		FX.burst(get_parent(), global_position + Vector2(float(dir) * _size.x * 0.5, -_size.y * 0.2), Color(1, 1, 0.8), 4, 160.0)
		sfx.emit("clang")
		return false
	if state == "down":   # reviver đang nằm: đòn nào cũng diệt hẳn
		hp = 0
		_die()
		return true
	hp -= dmg
	_flash = 0.1
	_kb_t = 0.2
	if hp <= 0 and kind == "reviver" and not _revived:
		_revived = true
		hp = 1
		state = "down"
		_t = REVIVE_AFTER
		sfx.emit("enemy_die")
		FX.spark(get_parent(), global_position, Vector2(0.0, -1.0), DATA[kind]["color"])
		return true
	var away: float = signf(global_position.x - from_pos.x)
	if kind == "flyer":
		velocity = Vector2(away * 260.0, -60.0)
	elif kind == "guard":
		velocity.x = away * 120.0
	elif kind != "spitter" and kind != "dropper" and kind != "sentry" and kind != "bubbler":
		velocity.x = away * 260.0
	if (kind == "charger" or kind == "guard" or kind == "cinder") and state == "windup":
		state = "idle"
		_t = 0.6
	FX.spark(get_parent(), global_position, Vector2(away if away != 0.0 else 1.0, -0.2).normalized(), DATA[kind]["color"])
	if hp <= 0:
		_die()
	return true

func _die() -> void:
	if minion:   # quái do sentry gọi: không Geo
		FX.death(get_parent(), global_position, DATA[kind]["color"])
		sfx.emit("enemy_die")
		died.emit(global_position)
		queue_free()
		return
	var n: int = roundi(float(DATA[kind]["geo"]) * (STATE.geo_mult()) * (1.0 + randf() * 0.5))
	n = maxi(1, n)
	STATE.geo += n
	FX.float_text(get_parent(), global_position, "+%d" % n, Color(1.0, 0.9, 0.4))
	FX.death(get_parent(), global_position, DATA[kind]["color"])
	sfx.emit("enemy_die")
	died.emit(global_position)
	queue_free()

func _draw() -> void:
	var tint := Color.WHITE
	if _flash > 0.0:
		tint = Color(3, 3, 3)
	elif (state == "windup" or state == "shake") and int(_time * 30.0) % 2 == 0:
		tint = Color(1.6, 0.7, 0.7)
	elif state == "down":   # reviver nằm: xám; nhấp nháy sắp đứng dậy
		tint = Color(0.45, 0.45, 0.55) if _t > 0.5 or int(_time * 20.0) % 2 == 0 else Color(1.3, 1.3, 1.5)
	else:
		tint = Color(LOOK[kind].get("tint", Color.WHITE))
	var look: Dictionary = LOOK[kind]
	var jitter := Vector2(randf_range(-3.0, 3.0), 0.0) if state == "shake" else Vector2.ZERO
	SPRITES.draw_body(self, String(look["anim"]), Vector2(0, _size.y * 0.5) + jitter, float(look["scale"]), dir < 0, tint)
	if kind == "guard" or kind == "sentry":   # khiên: dựng đứng phía trước, hạ thấp khi recover
		var up: bool = state != "recover"
		var sh := Rect2(float(dir) * (_size.x * 0.5 + 2.0) - 3.0, -_size.y * (0.4 if up else 0.05), 6.0, _size.y * (0.8 if up else 0.4))
		draw_rect(sh, Color(1, 1, 1) if _block_flash > 0.0 else Color(0.62, 0.68, 0.82))
		draw_rect(sh, Color(0.12, 0.12, 0.2), false, 1.5)
