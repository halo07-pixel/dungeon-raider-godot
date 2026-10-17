extends Node2D
## Biến thể (affix) của quái thường: gắn 1 cơ chế riêng lên quái, tách khỏi enemy.gd (component con).
##   volatile — chết thì nổ (vùng báo trước 0.5s rồi gây sát thương)
##   summoner — định kỳ triệu hồi quái nhỏ (tối đa MAX_MINIONS con đang sống)
##   warden   — định kỳ cấp khiên tạm cho quái xung quanh; giết warden thì khiên tan ngay
## Tinh Anh Q-learning (archer/shaman) KHÔNG nhận affix. Mọi hằng số cân bằng nằm ở đầu file.

signal summon_requested(owner_enemy: Node)

const BOSS_HAZARD = preload("res://scripts/boss_hazard.gd")

## min_floor: tầng thấp nhất xuất hiện · kinds: loại quái hợp lệ · color: nhận diện (tint, viền thanh HP)
const AFFIXES: Dictionary = {
	"volatile": {"label": "Volatile", "color": Color(1.0, 0.55, 0.15), "min_floor": 2,
		"kinds": ["slime", "brute", "chort", "masked_orc", "frost_zombie", "frost_big_zombie"]},
	"warden": {"label": "Warden", "color": Color(0.35, 0.7, 1.0), "min_floor": 3,
		"kinds": ["archer", "shaman", "brute", "masked_orc", "frost_big_zombie"]},
	"summoner": {"label": "Summoner", "color": Color(0.75, 0.4, 1.0), "min_floor": 4,
		"kinds": ["archer", "shaman", "brute", "masked_orc", "frost_big_zombie"]},
}
const CHANCE_BASE: float = 0.05   # tỉ lệ ở tầng 2
const CHANCE_PER_FLOOR: float = 0.02
const CHANCE_MAX: float = 0.22
const MAX_PER_ROOM: int = 2

const VOLATILE_RADIUS: float = 58.0
const VOLATILE_DAMAGE: int = 14
const VOLATILE_TELEGRAPH: float = 0.5
const SUMMON_INTERVAL: float = 5.5
const MAX_MINIONS: int = 2
const WARD_INTERVAL: float = 7.0
const WARD_DURATION: float = 4.0
const WARD_RADIUS: float = 170.0
const WARD_FRACTION: float = 0.35 # khiên = 35% máu tối đa của quái được che

var enemy: Node2D = null
var id: String = ""
var _timer: float = 0.0
var _ward_left: float = 0.0
var _warded: Array = []
var _t: float = 0.0

## Tỉ lệ có affix ở một tầng (0 ở tầng 1).
static func chance_for_floor(floor_num: int) -> float:
	if floor_num < 2:
		return 0.0
	return clampf(CHANCE_BASE + CHANCE_PER_FLOOR * float(floor_num - 2), 0.0, CHANCE_MAX)

## Chọn affix cho 1 quái: "" nếu không trúng / không có affix hợp lệ.
static func roll(kind: String, floor_num: int) -> String:
	if randf() >= chance_for_floor(floor_num):
		return ""
	var valid: Array = []
	for aid in AFFIXES:
		var a: Dictionary = AFFIXES[aid]
		if floor_num >= int(a["min_floor"]) and (a["kinds"] as Array).has(kind):
			valid.append(aid)
	if valid.is_empty():
		return ""
	return String(valid[randi() % valid.size()])

static func color_of(affix_id: String) -> Color:
	return AFFIXES[affix_id]["color"] if AFFIXES.has(affix_id) else Color.WHITE

static func label_of(affix_id: String) -> String:
	return String(AFFIXES[affix_id]["label"]) if AFFIXES.has(affix_id) else ""

func attach(p_enemy: Node2D, p_id: String) -> void:
	enemy = p_enemy
	id = p_id
	_timer = 2.0 # trễ nhẹ sau khi quái thức dậy
	if id == "volatile":
		enemy.died.connect(_on_volatile_died)
	elif id == "warden":
		enemy.died.connect(_clear_wards)

func _process(delta: float) -> void:
	_t += delta
	if not is_instance_valid(enemy) or not bool(enemy.get("alive")) or not bool(enemy.get("active")):
		return
	match id:
		"summoner":
			_timer -= delta
			if _timer <= 0.0:
				_timer = SUMMON_INTERVAL
				if _minion_count() < MAX_MINIONS:
					Global.burst(enemy.global_position, color_of(id), 8, 120.0, 1.5)
					summon_requested.emit(enemy)
		"warden":
			_timer -= delta
			if _timer <= 0.0:
				_timer = WARD_INTERVAL
				_grant_wards()
			if _ward_left > 0.0:
				_ward_left -= delta
				if _ward_left <= 0.0:
					_clear_wards(null)
			queue_redraw()

func _minion_count() -> int:
	var n: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.alive and e.has_meta("summoner") and e.get_meta("summoner") == enemy:
			n += 1
	return n

func _grant_wards() -> void:
	_clear_wards(null)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == enemy or not is_instance_valid(e) or not e.alive:
			continue
		if e.global_position.distance_to(enemy.global_position) <= WARD_RADIUS:
			e.hurtbox.ward = maxf(e.hurtbox.ward, float(e.max_hp) * WARD_FRACTION)
			_warded.append(e)
	if not _warded.is_empty():
		_ward_left = WARD_DURATION
		Global.burst(enemy.global_position, color_of(id), 10, 140.0, 1.5)

func _clear_wards(_e) -> void:
	for e in _warded:
		if is_instance_valid(e) and e.get("hurtbox") != null:
			e.hurtbox.ward = 0.0
	_warded.clear()
	_ward_left = 0.0

## Chỉ nổ khi bị hạ bằng sát thương (hp <= 0); bị kill() ép chết (vd. dọn phòng khi boss chết) thì không.
func _on_volatile_died(_e = null) -> void:
	if not is_instance_valid(enemy) or enemy.hurtbox.hp > 0.0:
		return
	var hz := Area2D.new()
	hz.set_script(BOSS_HAZARD)
	hz.damage = VOLATILE_DAMAGE
	hz.radius = VOLATILE_RADIUS
	hz.telegraph_time = VOLATILE_TELEGRAPH
	hz.single_shot = true
	hz.color = Color(1.0, 0.5, 0.1, 0.5)
	Global.world.add_child(hz)
	hz.global_position = enemy.global_position

func _draw() -> void:
	if id == "warden" and is_instance_valid(enemy) and bool(enemy.get("alive")):
		var pulse: float = 0.5 + 0.5 * sin(_t * 3.0)
		var c: Color = color_of(id)
		draw_arc(Vector2.ZERO, WARD_RADIUS, 0.0, TAU, 48, Color(c, 0.12 + 0.10 * pulse), 2.0)
		if _ward_left > 0.0:
			draw_circle(Vector2.ZERO, WARD_RADIUS, Color(c, 0.05))
