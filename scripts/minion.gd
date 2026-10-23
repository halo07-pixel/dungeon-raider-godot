extends CharacterBody2D
## Khung "lính" dùng chung (Tome + class Summoner): thực thể do Player triệu hồi, tự hành động trong `life` giây rồi biến mất.
## Va chạm CHỈ với tường (layer 0, mask = L_WORLD) nên đạn/quái không đụng được lính (v1: lính không bị giết, quái không nhắm lính).
## Dữ liệu từng loại nằm ở KINDS; thêm loại = thêm 1 dòng + (nếu cần) 1 mode mới trong _think().
## Tách bạch: vật lý/di chuyển ở _physics_process, vẽ ở _draw, tín hiệu `expired` cho UI/âm thanh/hiệu ứng khi hết hạn.

const BULLET = preload("res://scenes/bullet.tscn")

signal expired(kind: String, pos: Vector2)

## mode: chase (đuổi + đánh cận chiến) | shoot (bắn tầm xa) | guard (chặn đạn địch) | totem (hồi máu chủ) | orbit (lưỡi quay quanh chủ).
## stationary: đứng yên tại chỗ đặt. dmg_k: hệ số so với sát thương lính cơ bản.
const KINDS: Dictionary = {
	"spirit": {"name": "Spirit", "mode": "chase", "speed": 185.0, "life": 12.0, "hit_cd": 0.55, "reach": 20.0, "dmg_k": 1.0, "color": Color(0.55, 0.85, 1.0), "size": 9.0},
	"wisp": {"name": "Wisp", "mode": "shoot", "speed": 130.0, "life": 12.0, "shot_cd": 0.85, "range": 340.0, "keep": 150.0, "bullet_speed": 520.0, "dmg_k": 0.8, "color": Color(0.8, 0.6, 1.0), "size": 8.0},
	"guardian": {"name": "Guardian", "mode": "guard", "speed": 150.0, "life": 12.0, "block_radius": 54.0, "dmg_k": 0.0, "color": Color(1.0, 0.85, 0.4), "size": 12.0},
	"turret": {"name": "Arc Turret", "mode": "shoot", "stationary": true, "life": 10.0, "shot_cd": 0.4, "range": 380.0, "bullet_speed": 600.0, "dmg_k": 0.6, "color": Color(0.5, 1.0, 0.7), "size": 11.0},
	"totem": {"name": "Mending Totem", "mode": "totem", "stationary": true, "life": 8.0, "pulse": 1.5, "heal": 4, "radius": 130.0, "dmg_k": 0.0, "color": Color(0.5, 1.0, 0.5), "size": 11.0},
	"ward": {"name": "Ward Barrier", "mode": "guard", "stationary": true, "life": 6.0, "block_radius": 80.0, "dmg_k": 0.0, "color": Color(0.6, 0.8, 1.0), "size": 13.0},
	"mini": {"name": "Spiteling", "mode": "chase", "speed": 215.0, "life": 8.0, "hit_cd": 0.5, "reach": 16.0, "dmg_k": 0.7, "color": Color(1.0, 0.55, 0.4), "size": 6.0, "explode_radius": 80.0, "explode_k": 3.5},
	"blades": {"name": "Blade Dance", "mode": "orbit", "life": 6.0, "hit_cd": 0.45, "orbit": 72.0, "spin": 4.2, "count": 3, "dmg_k": 0.9, "color": Color(0.9, 0.95, 1.0), "size": 9.0},
}

## Sát thương lính cơ bản: BASE + PER_FLOOR * tầng, nhân dmg_k của loại và hệ số `power` (Skill Power...).
const BASE_DMG: float = 8.0
const DMG_PER_FLOOR: float = 0.45
const FOLLOW_DIST: float = 70.0
const WARN_SECONDS: float = 2.0 # nhấp nháy báo sắp biến mất

var kind: String = "spirit"
var cfg: Dictionary = {}
var owner_player: Node = null
var dmg: int = 1
var life: float = 10.0
var _t: float = 0.0
var _hit_t: float = 0.0
var _spin: float = 0.0
var _pulse_t: float = 0.0
var _blade_hit: Dictionary = {} # enemy instance id -> giây chờ trước lần đánh kế
var _slot: int = 0
## Nguồn đòn cho Sigil: "class" (Summoner) hoặc "tome".
var src: String = ""
var _target_cache: Node = null
var _retarget: float = 0.0

## Tạo lính tại `pos`. `power` = hệ số sát thương (mặc định 1). `life_mult` kéo dài/rút ngắn thời gian tồn tại.
static func spawn(p_player: Node, p_kind: String, pos: Vector2, power: float = 1.0, life_mult: float = 1.0, slot: int = 0, p_src: String = "") -> Node:
	var m = new()
	m.src = p_src
	m.setup(p_player, p_kind, power, life_mult, slot)
	Global.world.add_child(m)
	m.global_position = pos
	return m

func setup(p_player: Node, p_kind: String, power: float, life_mult: float, slot: int) -> void:
	owner_player = p_player
	kind = p_kind if KINDS.has(p_kind) else "spirit"
	cfg = KINDS[kind]
	life = float(cfg["life"]) * life_mult
	_slot = slot
	dmg = maxi(0, int((BASE_DMG + DMG_PER_FLOOR * float(Global.floor_num)) * float(cfg["dmg_k"]) * power)) if float(cfg["dmg_k"]) > 0.0 else 0

func _ready() -> void:
	add_to_group("minions")
	collision_layer = 0
	collision_mask = Global.L_WORLD
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 8.0
	cs.shape = shape
	add_child(cs)
	z_index = 2

# ---------------------------------------------------------------- Vòng đời & hành vi
func _physics_process(delta: float) -> void:
	_t += delta
	life -= delta
	if life <= 0.0 or not is_instance_valid(owner_player) or not owner_player.alive:
		_expire()
		return
	_hit_t = maxf(0.0, _hit_t - delta)
	_retarget = maxf(0.0, _retarget - delta)
	_think(delta)
	queue_redraw()

func _expire() -> void:
	if cfg.has("explode_radius") and is_instance_valid(owner_player) and owner_player.alive:
		_explode()
	expired.emit(kind, global_position)
	Global.burst(global_position, cfg["color"], 6, 90.0, 1.0)
	queue_free()

## Nổ khi hết hạn (Spiteling của Legion): sát thương diện rộng quanh vị trí lính.
func _explode() -> void:
	var r: float = float(cfg["explode_radius"])
	var amount: int = maxi(1, int(float(dmg) * float(cfg["explode_k"])))
	for grp in ["enemies", "boss"]:
		for e in get_tree().get_nodes_in_group(grp):
			if is_instance_valid(e) and e.alive and e.global_position.distance_to(global_position) <= r + (_target_radius(e) if grp == "boss" else 0.0):
				_strike(e, amount, 260.0)
	var fx := Node2D.new()
	fx.set_script(load("res://scripts/skill_ring_fx.gd"))
	fx.max_radius = r
	fx.color = cfg["color"]
	fx.duration = 0.3
	Global.world.add_child(fx)
	fx.global_position = global_position
	Global.burst(global_position, cfg["color"], 14, 220.0, 1.6)
	Global.sfx("shockwave", 1.4)

func _think(delta: float) -> void:
	match String(cfg["mode"]):
		"chase": _think_chase(delta)
		"shoot": _think_shoot(delta)
		"guard": _think_guard(delta)
		"totem": _think_totem(delta)
		"orbit": _think_orbit(delta)

## Mục tiêu gần nhất (quái hoặc boss còn sống, đã active) trong tầm `max_range`; cache 0.2s cho đỡ tốn.
func _nearest_target(max_range: float) -> Node:
	if _retarget <= 0.0 or not is_instance_valid(_target_cache) or not _target_cache.alive:
		_retarget = 0.2
		_target_cache = null
		var best: float = max_range
		for grp in ["enemies", "boss"]:
			for e in get_tree().get_nodes_in_group(grp):
				if not is_instance_valid(e) or not e.alive or not bool(e.get("active")):
					continue
				var d: float = e.global_position.distance_to(global_position)
				if d < best:
					best = d
					_target_cache = e
	if is_instance_valid(_target_cache) and _target_cache.global_position.distance_to(global_position) > max_range:
		return null
	return _target_cache

func _move_toward(dest: Vector2, speed: float, stop_dist: float = 4.0) -> void:
	var to: Vector2 = dest - global_position
	if to.length() <= stop_dist:
		velocity = Vector2.ZERO
		return
	velocity = to.normalized() * speed
	move_and_slide()

func _follow_player(speed: float) -> void:
	# mỗi lính một "chỗ" quanh chủ để khỏi chồng lên nhau
	var ang: float = TAU * float(_slot) / 3.0 + _t * 0.6
	_move_toward(owner_player.global_position + Vector2.from_angle(ang) * FOLLOW_DIST, speed, 10.0)

func _think_chase(_delta: float) -> void:
	var tgt: Node = _nearest_target(420.0)
	if tgt == null:
		_follow_player(float(cfg["speed"]))
		return
	var reach: float = float(cfg["reach"]) + _target_radius(tgt)
	if tgt.global_position.distance_to(global_position) > reach:
		_move_toward(tgt.global_position, float(cfg["speed"]))
	elif _hit_t <= 0.0:
		_hit_t = float(cfg["hit_cd"])
		_strike(tgt, dmg, 160.0)

func _think_shoot(_delta: float) -> void:
	var stationary: bool = bool(cfg.get("stationary", false))
	var tgt: Node = _nearest_target(float(cfg["range"]))
	if not stationary:
		if tgt != null and tgt.global_position.distance_to(global_position) < float(cfg["keep"]):
			velocity = (global_position - tgt.global_position).normalized() * float(cfg["speed"])
			move_and_slide()
		elif owner_player.global_position.distance_to(global_position) > FOLLOW_DIST * 1.6:
			_follow_player(float(cfg["speed"]))
	if tgt != null and _hit_t <= 0.0:
		_hit_t = float(cfg["shot_cd"])
		var dir: Vector2 = (tgt.global_position - global_position).normalized()
		var b = BULLET.instantiate()
		b.setup(true, dir, dmg, float(cfg["bullet_speed"]), 0.9, cfg["color"], 4.5)
		b.skill_src = src
		Global.world.add_child(b)
		b.global_position = global_position + dir * 12.0

func _think_guard(_delta: float) -> void:
	if not bool(cfg.get("stationary", false)):
		var ahead: Vector2 = owner_player.global_position + owner_player.aim_dir * 46.0
		_move_toward(ahead, float(cfg["speed"]), 6.0)
	var r: float = float(cfg["block_radius"])
	for eb in get_tree().get_nodes_in_group("enemy_bullets"):
		if is_instance_valid(eb) and eb.global_position.distance_to(global_position) <= r:
			Global.burst(eb.global_position, cfg["color"], 4, 80.0, 0.8)
			eb.queue_free()

func _think_totem(delta: float) -> void:
	_pulse_t += delta
	if _pulse_t < float(cfg["pulse"]):
		return
	_pulse_t = 0.0
	if owner_player.global_position.distance_to(global_position) <= float(cfg["radius"]):
		owner_player.heal(int(cfg["heal"]))
		Global.burst(owner_player.global_position, cfg["color"], 6, 90.0, 1.0)

## Lưỡi quay: các lưỡi chia đều trên vòng quanh chủ, chạm quái thì gây sát thương (mỗi quái có hồi riêng).
func _think_orbit(delta: float) -> void:
	_spin += float(cfg["spin"]) * delta
	global_position = owner_player.global_position
	for k in _blade_hit.keys():
		_blade_hit[k] = float(_blade_hit[k]) - delta
		if float(_blade_hit[k]) <= 0.0:
			_blade_hit.erase(k)
	var n: int = int(cfg["count"])
	for i in n:
		var bp: Vector2 = global_position + Vector2.from_angle(_spin + TAU * float(i) / float(n)) * float(cfg["orbit"])
		for grp in ["enemies", "boss"]:
			for e in get_tree().get_nodes_in_group(grp):
				if not is_instance_valid(e) or not e.alive or not bool(e.get("active")):
					continue
				var id: int = e.get_instance_id()
				if _blade_hit.has(id):
					continue
				if e.global_position.distance_to(bp) <= float(cfg["size"]) + _target_radius(e):
					_blade_hit[id] = float(cfg["hit_cd"])
					_strike(e, dmg, 220.0)

func _target_radius(e: Node) -> float:
	var d = e.get("data")
	return float(d.get("radius", 12.0)) if d is Dictionary else 34.0

func _strike(e: Node, amount: int, knock: float) -> void:
	e.take_damage(amount, global_position, knock if not e.is_in_group("boss") else 0.0)
	Global.burst(e.global_position, cfg["color"], 4, 100.0, 1.0)
	Global.on_secondary_hit(e, amount, false, src)

# ---------------------------------------------------------------- Vẽ (bằng code)
func _draw() -> void:
	var col: Color = cfg["color"]
	var size: float = float(cfg["size"])
	if life < WARN_SECONDS and int(_t * 8.0) % 2 == 0:
		col = Color(col, 0.35)
	match String(cfg["mode"]):
		"orbit":
			var n: int = int(cfg["count"])
			for i in n:
				var p: Vector2 = Vector2.from_angle(_spin + TAU * float(i) / float(n)) * float(cfg["orbit"])
				draw_circle(p, size, Color(col, 0.35))
				draw_circle(p, size * 0.55, col)
			draw_arc(Vector2.ZERO, float(cfg["orbit"]), 0.0, TAU, 40, Color(col, 0.15), 1.5)
		"guard":
			draw_arc(Vector2.ZERO, float(cfg["block_radius"]), 0.0, TAU, 40, Color(col, 0.55), 2.0)
			draw_circle(Vector2.ZERO, float(cfg["block_radius"]), Color(col, 0.08))
			draw_circle(Vector2.ZERO, size, col)
		"totem":
			draw_arc(Vector2.ZERO, float(cfg["radius"]), 0.0, TAU, 40, Color(col, 0.25), 1.5)
			draw_rect(Rect2(Vector2(-size * 0.5, -size), Vector2(size, size * 1.8)), col)
			draw_circle(Vector2(0.0, -size), size * 0.6, Color(1, 1, 1, 0.8))
		_:
			var bob: float = sin(_t * 7.0) * 2.0
			draw_circle(Vector2(0.0, bob), size + 3.0, Color(col, 0.25))
			draw_circle(Vector2(0.0, bob), size, col)
			draw_circle(Vector2(-3.0, bob - 2.0), 1.8, Color(0.05, 0.05, 0.1))
			draw_circle(Vector2(3.0, bob - 2.0), 1.8, Color(0.05, 0.05, 0.1))
