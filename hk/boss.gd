extends CharacterBody2D
## Boss: warden / lord (đi bộ, chém lao, nhảy đập, triệu hồi, mưa đá) và wraith (bay, bắn quạt, bổ nhào, chớp dịch chuyển).
## Mini-boss: brute (đi bộ, đập đất + chém, như warden nhẹ) và hexer (bay, bắn quạt, chớp dịch chuyển, triệu hồi quỷ nhỏ).
## Mỗi đòn có thời gian báo trước (nhấp nháy). Gán `kind` TRƯỚC khi add_child, `arena` sau khi add.
signal engaged
signal defeated
signal shake(strength: float)

const PROJECTILE = preload("res://hk/projectile.gd")
const ENEMY = preload("res://hk/enemy.gd")
const FX = preload("res://hk/fx.gd")
const SPRITES = preload("res://hk/sprites.gd")
const LOOK: Dictionary = {
	"warden": {"anim": "ogre_idle_anim", "scale": 3.0},
	"wraith": {"anim": "necromancer_idle_anim", "scale": 3.0},
	"lord": {"anim": "big_demon_idle_anim", "scale": 3.0},
	"brute": {"anim": "frost_big_zombie_anim", "scale": 2.5},
	"hexer": {"anim": "hell_acolyte_anim", "scale": 3.0},
}
const FLYERS: Array = ["wraith", "hexer"]
const GRAVITY: float = 2400.0

const DATA: Dictionary = {
	"warden": {"title": "Gate Warden", "hp": 220, "color": Color(0.55, 0.62, 0.78), "speed": 95.0},
	"wraith": {"title": "Hollow Wraith", "hp": 260, "color": Color(0.75, 0.82, 0.98), "speed": 200.0},
	"lord": {"title": "Dungeon Lord", "hp": 420, "color": Color(0.82, 0.36, 0.30), "speed": 115.0},
	"brute": {"title": "Bone Brute", "hp": 110, "color": Color(0.55, 0.75, 0.85), "speed": 85.0},
	"hexer": {"title": "Ash Hexer", "hp": 90, "color": Color(0.85, 0.45, 0.35), "speed": 170.0},
}

var kind: String = "warden"

## Hộp va chạm = phần nhìn thấy của sprite (hk/bodies.gd).
static func body_size(k: String) -> Vector2:
	var look: Dictionary = LOOK[k]
	return SPRITES.BODIES.rect(String(look["anim"]), float(look["scale"])).size
var arena: Rect2 = Rect2(0, 0, 1280, 720)
var hp: int = 100
var max_hp: int = 100
var state: String = "dormant"
var dir: int = -1
var phase: int = 1
var _t: float = 0.0
var _flash: float = 0.0
var _time: float = 0.0
var _combo: int = 0
var _size: Vector2
var _markers: Array = []       # {x, t}: cảnh báo trước khi rơi đá / bổ nhào
var _rain_t: float = 0.0
var _dive_x: float = 0.0
var _alpha: float = 1.0
var _was_air: bool = false

func _ready() -> void:
	var d: Dictionary = DATA[kind]
	max_hp = int(d["hp"])
	hp = max_hp
	_size = body_size(kind)
	collision_layer = 4
	collision_mask = 0 if kind in FLYERS else 1
	add_to_group("hk_boss")
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = _size
	cs.shape = sh
	add_child(cs)

func title() -> String:
	return String(DATA[kind]["title"])

func _player() -> Node2D:
	var ps := get_tree().get_nodes_in_group("hk_player")
	return ps[0] if not ps.is_empty() else null

func _physics_process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta)
	_t -= delta
	var p := _player()
	if p == null:
		return
	if state == "dormant":
		velocity = Vector2(0, velocity.y)
		if not (kind in FLYERS):
			velocity.y = minf(velocity.y + GRAVITY * delta, 900.0)
			move_and_slide()
		if absf(p.global_position.x - global_position.x) < 480.0 and absf(p.global_position.y - global_position.y) < 260.0:
			state = "intro"
			_t = 1.1
			engaged.emit()
		queue_redraw()
		return
	if state == "intro":
		if not (kind in FLYERS):
			velocity.y = minf(velocity.y + GRAVITY * delta, 900.0)
			velocity.x = 0.0
			move_and_slide()
		if _t <= 0.0:
			_next()
	elif kind in FLYERS:
		_wraith(delta, p)
	else:
		_ground(delta, p)
	_touch_damage(p)
	_update_markers(delta)
	queue_redraw()

func _face(p: Node2D) -> void:
	dir = 1 if p.global_position.x > global_position.x else -1

func _next() -> void:
	state = "hover" if kind in FLYERS else "walk"
	_t = randf_range(1.0, 1.6) if kind in FLYERS else randf_range(0.5, 1.0)

# ------------------------------------------------------------ đi bộ (warden, lord)
func _ground(delta: float, p: Node2D) -> void:
	var speed: float = float(DATA[kind]["speed"]) * (1.25 if phase == 2 else 1.0)
	match state:
		"walk":
			_face(p)
			velocity.x = float(dir) * speed
			if _t <= 0.0:
				_pick_attack()
		"wind_slash":
			velocity.x = 0.0
			if _t <= 0.0:
				state = "lunge"
				_t = 0.28
				shake.emit(1.0)
		"lunge":
			velocity.x = float(dir) * 470.0
			if _t <= 0.0:
				state = "recover"
				_t = 0.5
		"recover":
			velocity.x = 0.0
			if _t <= 0.0:
				if _combo > 0:
					_combo -= 1
					_face(p)
					state = "wind_slash"
					_t = 0.3
				else:
					_next()
		"wind_slam":
			velocity.x = 0.0
			if _t <= 0.0:
				state = "air"
				_face(p)
				velocity = Vector2(clampf((p.global_position.x - global_position.x) / 0.75, -320.0, 320.0), -950.0)
				_was_air = false
		"air":
			if not is_on_floor():
				_was_air = true
			elif _was_air:
				_shockwave()
				state = "recover"
				_t = 0.8
		"wind_summon":
			velocity.x = 0.0
			if _t <= 0.0:
				_summon()
				state = "recover"
				_t = 0.6
		"rain":
			velocity.x = 0.0
			_rain_t -= delta
			if _rain_t <= 0.0:
				_rain_t = 0.4
				_markers.append({"x": randf_range(arena.position.x + 70.0, arena.end.x - 70.0), "t": 0.8})
			if _t <= 0.0:
				state = "recover"
				_t = 0.7
	velocity.y = minf(velocity.y + GRAVITY * delta, 900.0)
	move_and_slide()
	global_position.x = clampf(global_position.x, arena.position.x + 50.0, arena.end.x - 50.0)

func _pick_attack() -> void:
	var opts: Array = ["slash", "slam"]
	if kind == "brute":   # nhiều đập đất hơn chém: đòn chậm, báo trước dài
		opts = ["slam", "slam", "slash"]
		if phase == 2:
			opts.append("combo")
	elif kind == "lord":
		opts.append("summon")
		if phase == 2:
			opts.append("rain")
			opts.append("rain")
	elif phase == 2:
		opts.append("combo")
	match String(opts[randi() % opts.size()]):
		"slash":
			state = "wind_slash"
			_t = 0.5
		"combo":
			_combo = 2
			state = "wind_slash"
			_t = 0.5
		"slam":
			state = "wind_slam"
			_t = 0.45
		"summon":
			state = "wind_summon"
			_t = 1.0
		"rain":
			state = "rain"
			_t = 3.0
			_rain_t = 0.1

func _shockwave() -> void:
	shake.emit(3.0)
	var speed: float = 360.0 if phase == 1 else 440.0
	for sgn in [-1.0, 1.0]:
		var s := Area2D.new()
		s.set_script(PROJECTILE)
		s.friendly = false
		s.radius = 14.0
		s.life = 1.8
		s.color = Color(1.0, 0.75, 0.4)
		s.vel = Vector2(float(sgn) * speed, 0.0)
		get_parent().add_child.call_deferred(s)
		s.position = Vector2(global_position.x + float(sgn) * 40.0, global_position.y + _size.y * 0.5 - 14.0)

## Hexer triệu một quỷ bay nhỏ cạnh mình (tối đa 3 con sống cùng lúc).
func _conjure() -> void:
	if get_tree().get_nodes_in_group("hk_enemy").size() >= 3:
		return
	var e := CharacterBody2D.new()
	e.set_script(ENEMY)
	e.kind = "flyer"
	get_parent().add_child.call_deferred(e)
	e.position = _clamp_arena(global_position + Vector2(float(-dir) * 70.0, 20.0))
	FX.burst(get_parent(), global_position, DATA[kind]["color"], 10, 180.0)

func _summon() -> void:
	var alive: int = get_tree().get_nodes_in_group("hk_enemy").size()
	for sgn in [-1.0, 1.0]:
		if alive >= 4:
			break
		var e := CharacterBody2D.new()
		e.set_script(ENEMY)
		e.kind = "crawler"
		get_parent().add_child.call_deferred(e)
		e.position = Vector2(clampf(global_position.x + float(sgn) * 150.0, arena.position.x + 60.0, arena.end.x - 60.0), global_position.y + _size.y * 0.5 - 12.0)
		alive += 1
	FX.burst(get_parent(), global_position, Color(0.8, 0.3, 0.3), 14, 200.0)

# ------------------------------------------------------------ bay (wraith)
func _wraith(delta: float, p: Node2D) -> void:
	var speed: float = float(DATA[kind]["speed"]) * (1.3 if phase == 2 else 1.0)
	match state:
		"hover":
			_face(p)
			var target := Vector2(p.global_position.x + sin(_time * 1.3) * 200.0, p.global_position.y - 140.0)   # cũ 150 với hộp 70 cao; hộp mới thấp hơn nên hạ 10 để đáy giữ nguyên tầm nhảy-chém (~-115)
			target = _clamp_arena(target)
			velocity = (target - global_position).limit_length(speed)
			if _t <= 0.0:
				var r: int = randi() % 3
				if kind == "hexer" and r == 1:   # hexer không bổ nhào: thay bằng triệu hồi
					r = 3
				if r == 0:
					state = "wind_bolt"
					_t = 0.55
				elif r == 1:
					state = "wind_dive"
					_t = 0.75
					_dive_x = p.global_position.x
					_markers.append({"x": _dive_x, "t": 0.75})
				elif r == 3:
					state = "wind_conjure"
					_t = 0.8
				else:
					state = "fade_out"
					_t = 0.3
		"wind_conjure":
			velocity = Vector2.ZERO
			_face(p)
			if _t <= 0.0:
				_conjure()
				state = "hover"
				_t = 1.4
		"wind_bolt":
			velocity = Vector2.ZERO
			_face(p)
			if _t <= 0.0:
				_fire_fan(p)
				state = "hover"
				_t = 1.3
		"wind_dive":
			velocity = Vector2.ZERO
			if _t <= 0.0:
				state = "dive"
				_t = 1.5
		"dive":
			var tx: float = move_toward(global_position.x, _dive_x, 500.0 * delta)
			global_position.x = tx
			velocity = Vector2(0, 820.0)
			if global_position.y > arena.end.y - 90.0 or _t <= 0.0 or _hits_floor():
				shake.emit(2.0)
				state = "dive_land"
				_t = 0.5
				velocity = Vector2.ZERO
		"dive_land":
			velocity = Vector2.ZERO
			if _t <= 0.0:
				if phase == 2 and randf() < 0.5:
					_dive_x = p.global_position.x
					_markers.append({"x": _dive_x, "t": 0.5})
					state = "wind_dive"
					_t = 0.5
					global_position.y = arena.position.y + 120.0
				else:
					state = "hover"
					_t = 1.0
		"fade_out":
			velocity = Vector2.ZERO
			_alpha = clampf(_t / 0.3, 0.0, 1.0)
			if _t <= 0.0:
				var side: float = -1.0 if p.global_position.x > arena.get_center().x else 1.0
				global_position = _clamp_arena(Vector2(arena.get_center().x + side * minf(arena.size.x * 0.3, 380.0), p.global_position.y - 120.0))
				state = "fade_in"
				_t = 0.3
		"fade_in":
			_alpha = clampf(1.0 - _t / 0.3, 0.0, 1.0)
			if _t <= 0.0:
				_alpha = 1.0
				state = "wind_bolt"
				_t = 0.4
	global_position += velocity * delta
	global_position = _clamp_arena(global_position)

func _hits_floor() -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2(0, _size.y * 0.5 + 6.0), 1)
	return not get_world_2d().direct_space_state.intersect_ray(q).is_empty()

func _clamp_arena(v: Vector2) -> Vector2:
	return Vector2(clampf(v.x, arena.position.x + 60.0, arena.end.x - 60.0), clampf(v.y, arena.position.y + 70.0, arena.end.y - 60.0))

func _fire_fan(p: Node2D) -> void:
	var n: int = 3 if phase == 1 else 5
	var base: Vector2 = (p.global_position - global_position).normalized()
	for i in n:
		var ang: float = (float(i) - float(n - 1) * 0.5) * 0.28
		var s := Area2D.new()
		s.set_script(PROJECTILE)
		s.friendly = false
		s.radius = 10.0
		s.life = 2.2
		s.color = Color(0.7, 0.85, 1.0)
		s.vel = base.rotated(ang) * 330.0
		get_parent().add_child.call_deferred(s)
		s.position = position

# ------------------------------------------------------------ chung
func _update_markers(delta: float) -> void:
	for m in _markers:
		m["t"] = float(m["t"]) - delta
	for m in _markers.duplicate():
		if float(m["t"]) <= 0.0:
			_markers.erase(m)
			if kind == "lord":
				var s := Area2D.new()
				s.set_script(PROJECTILE)
				s.friendly = false
				s.radius = 16.0
				s.life = 2.5
				s.color = Color(0.6, 0.5, 0.45)
				s.vel = Vector2(0, 720.0)
				get_parent().add_child.call_deferred(s)
				s.position = Vector2(float(m["x"]), arena.position.y + 40.0)

func body_rect() -> Rect2:
	return Rect2(global_position - _size * 0.5, _size)

func attack_rect() -> Rect2:
	return _attack_rect()

func _attack_rect() -> Rect2:
	if state == "lunge":
		return Rect2(global_position + Vector2(float(dir) * (_size.x * 0.5 + 45.0) - 45.0, -_size.y * 0.4), Vector2(90, _size.y * 0.8))
	return Rect2()

func _touch_damage(p: Node2D) -> void:
	if state == "dormant" or state == "intro" or _alpha < 0.9:
		return
	var pr := Rect2(p.global_position - p.BODY * 0.5, p.BODY)
	var body := Rect2(global_position - _size * 0.5, _size)
	if pr.intersects(body) or (state == "lunge" and pr.intersects(_attack_rect())):
		p.take_damage(global_position.x)

func take_hit(dmg: int, _from: Vector2) -> void:
	if hp <= 0 or state == "dormant" or state == "intro":
		return
	hp -= dmg
	_flash = 0.08
	if phase == 1 and hp <= max_hp / 2:
		phase = 2
		state = "intro"
		_t = 0.7
		shake.emit(3.0)
		_markers.clear()
	if hp <= 0:
		FX.death(get_parent(), global_position, DATA[kind]["color"], true)
		shake.emit(5.0)
		defeated.emit()
		queue_free()

## Vạch báo trước đòn (chỉ vẽ trong lúc "wind_*"), khớp với cách đòn thật di chuyển/ra đòn.
func _draw_telegraph(h: Vector2) -> void:
	var p := _player()
	var k: float = 1.0 - clampf(_t / 0.5, 0.0, 1.0)   # tiến độ báo trước (0 -> 1)
	var a: float = 0.12 + 0.25 * k
	match state:
		"wind_slash":   # lao tới: quãng đường 470x0.28s + tầm chém 90
			var reach: float = 470.0 * 0.28 + 90.0
			draw_rect(Rect2(minf(float(dir) * h.x, float(dir) * (h.x + reach)), -h.y * 0.8, reach, _size.y * 0.8), Color(1, 0.25, 0.2, a))
		"wind_slam":   # nhảy đập: rơi gần chỗ người chơi (tối đa 240px), vòng co lại ở chỗ rơi
			if p:
				var lx: float = clampf(p.global_position.x - global_position.x, -240.0, 240.0)
				var fy: float = h.y
				draw_arc(Vector2(lx, fy - 4.0), lerpf(70.0, 24.0, k), 0.0, TAU, 24, Color(1, 0.3, 0.2, 0.35 + 0.4 * k), 3.0)
				draw_line(Vector2(lx - 36.0, fy - 2.0), Vector2(lx + 36.0, fy - 2.0), Color(1, 0.3, 0.2, 0.5), 4.0)
		"wind_bolt":   # nhắm người chơi
			if p:
				var d: Vector2 = (p.global_position - global_position).normalized()
				draw_line(d * h.x, d * 320.0, Color(0.7, 0.85, 1.0, a * 2.0), 2.0)
		"wind_conjure":
			draw_arc(Vector2(float(-dir) * 70.0, 20.0), lerpf(40.0, 10.0, k), 0.0, TAU, 16, Color(0.9, 0.5, 0.3, 0.6), 2.0)

func _draw() -> void:
	var tint := Color.WHITE
	if _flash > 0.0:
		tint = Color(3, 3, 3, _alpha)
	elif (state.begins_with("wind") or state == "fade_out") and int(_time * 30.0) % 2 == 0:
		tint = Color(1.6, 0.8, 0.8, _alpha)
	else:
		tint.a = _alpha
	var h: Vector2 = _size * 0.5
	var look: Dictionary = LOOK[kind]
	SPRITES.draw_body(self, String(look["anim"]), Vector2(0, h.y), float(look["scale"]), dir < 0, tint, 6.0)
	if not (kind in FLYERS) and state == "lunge":
		draw_rect(Rect2(float(dir) * (h.x + 45.0) - 45.0, -h.y * 0.8, 90, _size.y * 0.8), Color(1, 1, 1, 0.55))
	_draw_telegraph(h)
	for m in _markers:
		var gx: float = float(m["x"]) - global_position.x
		var a: float = 0.25 + 0.35 * (1.0 - float(m["t"]))
		draw_rect(Rect2(gx - 14.0, -global_position.y + arena.position.y, 28.0, arena.size.y), Color(1, 0.3, 0.3, a * 0.5))
	if state != "dormant":
		var w: float = clampf(_size.x * 1.6, 120.0, 220.0)   # thanh máu ngay trên đỉnh phần nhìn thấy, rộng theo cỡ boss
		draw_rect(Rect2(-w * 0.5, -h.y - 18, w, 8), Color(0.05, 0.05, 0.1, 0.85))
		draw_rect(Rect2(-w * 0.5 + 1.0, -h.y - 17, (w - 2.0) * float(hp) / float(max_hp), 6), Color(0.95, 0.4, 0.35))
