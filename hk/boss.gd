extends CharacterBody2D
## Boss: warden / lord (đi bộ, chém lao, nhảy đập, triệu hồi, mưa đá) và wraith (bay, bắn quạt, bổ nhào, chớp dịch chuyển).
## Mini-boss: brute (đi bộ, đập đất + chém, như warden nhẹ) và hexer (bay, bắn quạt, chớp dịch chuyển, triệu hồi quỷ nhỏ).
## Boss bí mật many_faced: biến hình (`form`) qua các bộ đòn của boss khác, 3 pha; pha 3 là dạng thật `sovereign`.
## Mỗi đòn có thời gian báo trước (nhấp nháy). Gán `kind` TRƯỚC khi add_child, `arena` sau khi add.
signal engaged
signal defeated
signal shake(strength: float)
signal sfx(name: String)
signal darkness(on: bool)   # Wraith tối phòng; world nối vào Atmosphere

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
	"colossus": {"anim": "hell_ogre_idle_anim", "scale": 2.5},
	"many_faced": {"anim": "ogre_idle_anim", "scale": 3.0},   # hộp ban đầu = dạng warden; hộp thật theo `form`
	"sovereign": {"anim": "big_demon_idle_anim", "scale": 3.6},
}
const FLYERS: Array = ["wraith", "hexer"]
const ZONE = preload("res://hk/zone.gd")
## Đòn riêng của mỗi dạng (tương tác với biom của boss): state báo trước -> hàm tung đòn trong `_cast`.
const SKILL: Dictionary = {
	"warden": "wind_pillar", "brute": "wind_fissure", "wraith": "wind_veil", "hexer": "wind_torch",
	"lord": "wind_heat", "sovereign": "wind_heat", "colossus": "wind_tide",
}
const GRAVITY: float = 2400.0
const PERCH_WAIT: float = 1.0   # giây người chơi đứng cao hơn boss trước khi boss nhảy lên

const DATA: Dictionary = {
	"warden": {"title": "Gate Warden", "hp": 220, "color": Color(0.55, 0.62, 0.78), "speed": 95.0},
	"wraith": {"title": "Hollow Wraith", "hp": 260, "color": Color(0.75, 0.82, 0.98), "speed": 200.0},
	"lord": {"title": "Dungeon Lord", "hp": 420, "color": Color(0.82, 0.36, 0.30), "speed": 115.0},
	"brute": {"title": "Bone Brute", "hp": 110, "color": Color(0.55, 0.75, 0.85), "speed": 85.0},
	"hexer": {"title": "Ash Hexer", "hp": 90, "color": Color(0.85, 0.45, 0.35), "speed": 170.0},
	"colossus": {"title": "Drowned Colossus", "hp": 130, "color": Color(0.6, 0.5, 0.8), "speed": 100.0},
	"many_faced": {"title": "The Many-Faced", "hp": 480, "color": Color(0.7, 0.45, 0.9), "speed": 0.0},
	"sovereign": {"title": "The Many-Faced", "hp": 0, "color": Color(0.7, 0.45, 0.9), "speed": 125.0},
}
## Geo thưởng một lần khi hạ boss lần đầu (cờ boss_<id> chưa đặt).
const BOUNTY: Dictionary = {"warden": 60, "hexer": 40, "brute": 40, "wraith": 80, "colossus": 50, "lord": 150, "many_faced": 0}
const SHIFT_P1: Array = ["warden", "brute", "wraith", "hexer"]
const SHIFT_P2: Array = ["warden", "brute", "wraith", "hexer", "colossus", "lord"]

var kind: String = "warden"
var form: String = ""             # dạng đang dùng (= kind với boss thường); quyết định bộ đòn, hộp, bay/đi
var _shape: RectangleShape2D
var _form_t: float = 0.0          # còn bao lâu thì đổi dạng (chỉ many_faced)

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
var _perch_t: float = 0.0
var _prev_state: String = ""
var braziers: Array = []     # chân các lò lửa trong phòng (world gán) — nguồn sóng lửa của Hexer
var platforms: Array = []    # Rect2 các bục một chiều trong phòng (world gán) — Lord làm nóng bục
var _dark_t: float = 0.0

func _ready() -> void:
	var d: Dictionary = DATA[kind]
	max_hp = int(d["hp"])
	hp = max_hp
	form = "warden" if kind == "many_faced" else kind
	_form_t = 7.0
	_size = body_size(form)
	collision_layer = 4
	collision_mask = 0 if form in FLYERS else 1
	add_to_group("hk_boss")
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = _size
	_shape = sh
	cs.shape = sh
	add_child(cs)

func title() -> String:
	return String(DATA[kind]["title"])

func _player() -> Node2D:
	var ps := get_tree().get_nodes_in_group("hk_player")
	return ps[0] if not ps.is_empty() else null

func _exit_tree() -> void:
	if _dark_t > 0.0:
		darkness.emit(false)

func _physics_process(delta: float) -> void:
	if _dark_t > 0.0:
		_dark_t -= delta
		if _dark_t <= 0.0:
			darkness.emit(false)
	_time += delta
	_flash = maxf(0.0, _flash - delta)
	_t -= delta
	var p := _player()
	if p == null:
		return
	if state == "dormant":
		velocity = Vector2(0, velocity.y)
		if not (form in FLYERS):
			velocity.y = minf(velocity.y + GRAVITY * delta, 900.0)
			move_and_slide()
		if absf(p.global_position.x - global_position.x) < 480.0 and absf(p.global_position.y - global_position.y) < 260.0:
			state = "intro"
			_t = 1.1
			engaged.emit()
		queue_redraw()
		return
	if kind == "many_faced" and state != "wind_shift" and state != "intro":
		_form_t -= delta
	if state == "intro":
		if not (form in FLYERS):
			velocity.y = minf(velocity.y + GRAVITY * delta, 900.0)
			velocity.x = 0.0
			move_and_slide()
		if _t <= 0.0:
			_next()
	elif state == "wind_shift":
		velocity = Vector2(0, minf(velocity.y + GRAVITY * delta, 900.0)) if not (form in FLYERS) else Vector2.ZERO
		if not (form in FLYERS):
			move_and_slide()
		if _t <= 0.0:
			_set_form(_pick_form())
			_next()
	elif form in FLYERS:
		_wraith(delta, p)
	else:
		_ground(delta, p)
	if state != _prev_state and state.begins_with("wind"):   # báo hiệu đòn bằng âm riêng (thay vùng cảnh báo màu)
		sfx.emit("tell_" + state.substr(5))
	_prev_state = state
	_touch_damage(p)
	_update_markers(delta)
	queue_redraw()

func _lordlike() -> bool:
	return form == "lord" or form == "sovereign"

## many_faced: hết giờ dạng thì báo trước ~0.9s (vòng + nhấp nháy, không nhận đòn, không gây chạm) rồi đổi dạng. Pha 3 giữ dạng thật.
func _maybe_shift() -> bool:
	if kind != "many_faced" or phase >= 3 or _form_t > 0.0:
		return false
	state = "wind_shift"
	_t = 0.9
	velocity = Vector2.ZERO
	shake.emit(1.0)
	return true

func _pick_form() -> String:
	var pool: Array = (SHIFT_P1 if phase == 1 else SHIFT_P2).duplicate()
	pool.erase(form)
	return String(pool[randi() % pool.size()])

func _set_form(f: String) -> void:
	var old_h: float = _size.y
	form = f
	_size = body_size(f)
	_shape.set_deferred("size", _size)
	set_deferred("collision_mask", 0 if f in FLYERS else 1)
	global_position.y += (old_h - _size.y) * 0.5   # chân giữ nguyên chỗ khi đổi cỡ hộp
	velocity = Vector2.ZERO
	_alpha = 1.0
	_form_t = (6.5 if phase == 1 else 4.0) + randf_range(0.0, 1.5)

func _face(p: Node2D) -> void:
	dir = 1 if p.global_position.x > global_position.x else -1

func _next() -> void:
	state = "hover" if form in FLYERS else "walk"
	_t = randf_range(1.0, 1.6) if form in FLYERS else randf_range(0.5, 1.0)

# ------------------------------------------------------------ đi bộ (warden, lord)
func _ground(delta: float, p: Node2D) -> void:
	var speed: float = float(DATA[form]["speed"]) * (1.25 if phase >= 2 else 1.0)
	match state:
		"walk":
			_face(p)
			velocity.x = float(dir) * speed
			_perch_t = _perch_t + delta if (is_on_floor() and p.global_position.y < global_position.y - 90.0) else 0.0
			if _perch_t >= PERCH_WAIT:   # người chơi nấp trên bục cao: boss nhảy lên đuổi (đáp xuống gây sóng đập)
				_perch_t = 0.0
				var dy: float = global_position.y - p.global_position.y
				velocity = Vector2(clampf((p.global_position.x - global_position.x) / 0.9, -360.0, 360.0), -minf(sqrt(2.0 * GRAVITY * (dy + 48.0)), 1400.0))
				state = "air"
				_was_air = false
			elif _t <= 0.0 and not _maybe_shift():
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
		"wind_bolt":
			velocity.x = 0.0
			_face(p)
			if _t <= 0.0:
				_fire_fan(p)
				state = "recover"
				_t = 0.6
		"wind_summon":
			velocity.x = 0.0
			if _t <= 0.0:
				_summon()
				state = "recover"
				_t = 0.6
		"wind_pillar", "wind_fissure", "wind_heat", "wind_tide":
			velocity.x = 0.0
			_face(p)
			if _t <= 0.0:
				_cast(p)
				state = "recover"
				_t = 0.9
		"rain":
			velocity.x = 0.0
			_rain_t -= delta
			if _rain_t <= 0.0:
				_rain_t = 0.4
				var rx: float = randf_range(arena.position.x + 70.0, arena.end.x - 70.0)
				_markers.append({"x": rx, "t": 0.8})
				FX.burst(get_parent(), Vector2(rx, arena.position.y + 36.0), Color(0.6, 0.55, 0.5), 5, 60.0)   # bụi rơi từ trần báo hiệu đá sắp rụng
				sfx.emit("rumble")
			if _t <= 0.0:
				state = "recover"
				_t = 0.7
	velocity.y = minf(velocity.y + GRAVITY * delta, 900.0)
	move_and_slide()
	global_position.x = clampf(global_position.x, arena.position.x + 50.0, arena.end.x - 50.0)

func _pick_attack() -> void:
	var opts: Array = ["slash", "slam"]
	if form == "brute":   # nhiều đập đất hơn chém: đòn chậm, báo trước dài
		opts = ["slam", "slam", "slash"]
		if phase >= 2:
			opts.append("combo")
	elif _lordlike():
		opts.append("summon")
		if phase >= 2:
			opts.append("rain")
			opts.append("rain")
	elif phase >= 2:
		opts.append("combo")
	if SKILL.has(form):   # đòn riêng của dạng này (nhiều hơn ở pha 2)
		opts.append("skill")
		if phase >= 2:
			opts.append("skill")
	if kind == "many_faced" and phase >= 2:   # đòn lai: mọi dạng đi bộ biết bắn quạt từ pha 2
		opts.append("bolt")
		if form == "sovereign":
			opts.append("bolt")
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
		"bolt":
			state = "wind_bolt"
			_t = 0.55
		"rain":
			state = "rain"
			_t = 3.0
			_rain_t = 0.1
		"skill":
			state = String(SKILL[form])
			_t = 0.8

# ------------------------------------------------------------ đòn riêng theo biom
func _floor_y() -> float:
	return global_position.y + _size.y * 0.5 if not (form in FLYERS) else arena.end.y - 64.0

func _zone(k: String, r: Rect2, delay: float, life: float, v: Vector2 = Vector2.ZERO) -> Node2D:
	var z := Node2D.new()
	z.set_script(ZONE)
	z.kind = k
	z.rect = r
	z.delay = delay
	z.life = life
	z.vel = v
	z.fx_parent = get_parent()
	add_child.call_deferred(z)
	return z

func _dust(pos: Vector2) -> void:   # tín hiệu thay vùng cảnh báo: bụi/tia lửa + âm rung tại chỗ sắp có đòn
	FX.burst(get_parent(), pos, Color(0.6, 0.55, 0.5), 6, 70.0)
	sfx.emit("rumble")

func _cast(p: Node2D) -> void:
	var fy: float = _floor_y()
	match state:
		"wind_pillar":   # Gate Warden: đập sập cột ngay chỗ người chơi; rơi gây sát thương, đáp xuống thành vật cản/chỗ nấp 6s
			var x: float = clampf(p.global_position.x, arena.position.x + 60.0, arena.end.x - 60.0)
			_dust(Vector2(x, arena.position.y + 40.0))
			_zone("pillar", Rect2(x - 16.0, arena.position.y + 40.0, 32.0, 96.0), 0.7, 6.0).floor_y = fy
		"wind_fissure":   # Bone Brute: nền nứt, gai xương trồi lên quanh người chơi và tồn tại 3.5s
			for dx in [-120.0, 0.0, 120.0]:
				var x2: float = clampf(p.global_position.x + dx, arena.position.x + 60.0, arena.end.x - 60.0)
				_dust(Vector2(x2, fy))
				_zone("spikes", Rect2(x2 - 20.0, fy - 44.0, 40.0, 44.0), 0.6, 3.5)
			shake.emit(2.0)
		"wind_torch":   # Ash Hexer: nhóm lửa từ các lò chạy dọc sàn vào giữa phòng
			var src: Array = braziers if not braziers.is_empty() else [Vector2(arena.position.x + 60.0, fy), Vector2(arena.end.x - 60.0, fy)]
			for b in src:
				var dirx: float = 1.0 if float(b.x) < arena.get_center().x else -1.0
				FX.burst(get_parent(), Vector2(b.x, b.y - 20.0), Color(1.0, 0.6, 0.2), 10, 120.0)
				_zone("firewave", Rect2(float(b.x) - 20.0, float(b.y) - 48.0, 40.0, 48.0), 0.5, 3.2, Vector2(dirx * 230.0, 0.0))
		"wind_veil":   # Hollow Wraith: tắt đèn phòng, biến mất rồi hiện sau lưng người chơi
			_dark_t = 5.0
			darkness.emit(true)
			state = "fade_out"
			_t = 0.3
		"wind_heat":   # Dungeon Lord: một số bục nóng đỏ gây sát thương, buộc phải đổi chỗ đứng
			if platforms.is_empty():
				_summon()
				return
			var pool: Array = platforms.duplicate()
			pool.shuffle()
			for i in maxi(1, int(ceil(pool.size() * 0.6))):
				var r: Rect2 = pool[i]
				_dust(Vector2(r.get_center().x, r.position.y))
				_zone("heat", Rect2(r.position.x, r.position.y - 40.0, r.size.x, 44.0), 0.9, 3.0)
		"wind_tide":   # Drowned Colossus: nước dâng 80px trong 0.8s, giữ rồi rút; làm chậm người chơi, bục cao thì an toàn
			sfx.emit("rumble")
			_zone("water", Rect2(arena.position.x + 32.0, fy - 80.0, arena.size.x - 64.0, 80.0), 0.6, 4.5)
			shake.emit(1.5)

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
	var speed: float = float(DATA[form]["speed"]) * (1.3 if phase >= 2 else 1.0)
	match state:
		"hover":
			_face(p)
			var target := Vector2(p.global_position.x + sin(_time * 1.3) * 200.0, p.global_position.y - 140.0)   # cũ 150 với hộp 70 cao; hộp mới thấp hơn nên hạ 10 để đáy giữ nguyên tầm nhảy-chém (~-115)
			target = _clamp_arena(target)
			velocity = (target - global_position).limit_length(speed)
			if _t <= 0.0 and not _maybe_shift():
				var r: int = randi() % 3
				if form == "hexer" and r == 1:   # hexer không bổ nhào: thay bằng triệu hồi
					r = 3
				if SKILL.has(form) and _dark_t <= 0.0 and randf() < (0.45 if phase >= 2 else 0.3):   # đòn riêng
					r = 4
				if r == 0:
					state = "wind_bolt"
					_t = 0.55
				elif r == 1:
					state = "wind_dive"
					_t = 0.75
					_dive_x = p.global_position.x
					_markers.append({"x": _dive_x, "t": 0.75})
				elif r == 4:
					state = String(SKILL[form])
					_t = 0.8
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
		"wind_torch", "wind_veil":
			velocity = Vector2.ZERO
			_face(p)
			if _t <= 0.0:
				_cast(p)
				if state != "fade_out":
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
				if phase >= 2 and randf() < 0.5:
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
			if _lordlike():
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
	if state == "dormant" or state == "intro" or state == "wind_shift" or _alpha < 0.9:
		return
	var pr := Rect2(p.global_position - p.BODY * 0.5, p.BODY)
	var body := Rect2(global_position - _size * 0.5, _size)
	if pr.intersects(body) or (state == "lunge" and pr.intersects(_attack_rect())):
		p.take_damage(global_position.x)

func take_hit(dmg: int, _from: Vector2) -> bool:   # luôn true (không có khiên); thống nhất chữ ký với enemy.take_hit
	if hp <= 0 or state == "dormant" or state == "intro" or state == "wind_shift":
		return true
	hp -= dmg
	_flash = 0.08
	var want: int = phase
	if kind == "many_faced":   # 3 pha: 66% và 33% máu
		want = 3 if hp * 3 <= max_hp else (2 if hp * 3 <= max_hp * 2 else 1)
	elif hp <= max_hp / 2:
		want = 2
	if want > phase:
		phase = want
		state = "intro"
		_t = 0.7
		shake.emit(3.0)
		_markers.clear()
		if kind == "many_faced":
			if phase == 3:
				_set_form("sovereign")
			else:
				_form_t = 0.0
	if hp <= 0:
		FX.death(get_parent(), global_position, DATA[kind]["color"], true)
		shake.emit(5.0)
		defeated.emit()
		queue_free()
	return true

## Báo hiệu "đổi dạng" của many_faced: vòng nở quanh người (không phải vùng cảnh báo đòn đánh; các vùng/vạch đỏ đã bỏ).
func _draw_shift_ring(h: Vector2) -> void:
	if state == "wind_shift":
		var ks: float = 1.0 - clampf(_t / 0.9, 0.0, 1.0)
		draw_arc(Vector2.ZERO, lerpf(24.0, maxf(h.x, h.y) + 50.0, ks), 0.0, TAU, 32, Color(0.75, 0.5, 1.0, 0.3 + 0.5 * ks), 3.0)

func _draw() -> void:
	var tint := Color.WHITE
	if _flash > 0.0:
		tint = Color(3, 3, 3, _alpha)
	elif (state.begins_with("wind") or state == "fade_out") and int(_time * 30.0) % 2 == 0:
		tint = Color(1.6, 0.8, 0.8, _alpha)
	else:
		tint.a = _alpha
	var h: Vector2 = _size * 0.5
	var look: Dictionary = LOOK[form]
	SPRITES.draw_body(self, String(look["anim"]), Vector2(0, h.y), float(look["scale"]), dir < 0, tint, 6.0)
	if not (form in FLYERS) and state == "lunge":
		draw_rect(Rect2(float(dir) * (h.x + 45.0) - 45.0, -h.y * 0.8, 90, _size.y * 0.8), Color(1, 1, 1, 0.55))
	_draw_shift_ring(h)
	if state != "dormant":
		var w: float = clampf(_size.x * 1.6, 120.0, 220.0)   # thanh máu ngay trên đỉnh phần nhìn thấy, rộng theo cỡ boss
		draw_rect(Rect2(-w * 0.5, -h.y - 18, w, 8), Color(0.05, 0.05, 0.1, 0.85))
		draw_rect(Rect2(-w * 0.5 + 1.0, -h.y - 17, (w - 2.0) * float(hp) / float(max_hp), 6), Color(0.95, 0.4, 0.35))
