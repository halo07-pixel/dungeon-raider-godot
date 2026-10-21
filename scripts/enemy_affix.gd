extends Node2D
## Biến thể (affix) của quái thường: gắn 1 cơ chế riêng lên quái, tách khỏi enemy.gd (component con).
##   volatile — chết thì nổ (vùng báo trước 0.5s rồi gây sát thương)
##   summoner — định kỳ triệu hồi quái nhỏ (tối đa MAX_MINIONS con đang sống)
##   warden   — định kỳ cấp khiên tạm cho quái xung quanh; giết warden thì khiên tan ngay
##   splitter — chết (do sát thương) thì tách thành 2 quái nhỏ cùng loại (máu thấp, không rơi xu, không tách tiếp)
##   frenzy   — mỗi quái khác chết thì nhanh thêm một chút (có trần)
##   blink    — định kỳ báo trước rồi dịch chuyển ra sau lưng người chơi
##   leech    — mỗi lần gây sát thương cho người chơi thì hồi một phần sát thương đó
## Tinh Anh Q-learning (archer/shaman) KHÔNG nhận affix. Mọi hằng số cân bằng nằm ở đầu file.

signal summon_requested(owner_enemy: Node)
signal split_requested(owner_enemy: Node)

const BOSS_HAZARD = preload("res://scripts/boss_hazard.gd")

## min_floor: tầng thấp nhất xuất hiện · kinds: loại quái hợp lệ · color: nhận diện (tint, viền thanh HP)
const AFFIXES: Dictionary = {
	"volatile": {"label": "Volatile", "color": Color(1.0, 0.55, 0.15), "min_floor": 2,
		"kinds": ["slime", "brute", "chort", "masked_orc", "frost_zombie", "frost_big_zombie", "hell_ogre"]},
	"warden": {"label": "Warden", "color": Color(0.35, 0.7, 1.0), "min_floor": 3,
		"kinds": ["archer", "shaman", "brute", "masked_orc", "frost_big_zombie", "hell_ogre", "hell_imp"]},
	"summoner": {"label": "Summoner", "color": Color(0.75, 0.4, 1.0), "min_floor": 4,
		"kinds": ["archer", "shaman", "brute", "masked_orc", "frost_big_zombie", "hell_ogre", "hell_imp"]},
	"splitter": {"label": "Splitter", "color": Color(0.5, 0.95, 0.45), "min_floor": 3,
		"kinds": ["slime", "chort", "frost_zombie", "brute", "masked_orc"]},
	"frenzy": {"label": "Frenzy", "color": Color(1.0, 0.25, 0.25), "min_floor": 4,
		"kinds": ["slime", "brute", "chort", "masked_orc", "frost_zombie", "frost_big_zombie", "hell_ogre", "cinder_tiny"]},
	"leech": {"label": "Leech", "color": Color(0.85, 0.2, 0.55), "min_floor": 5,
		"kinds": ["slime", "brute", "chort", "masked_orc", "frost_zombie", "frost_big_zombie", "hell_ogre"]},
	"blink": {"label": "Blink", "color": Color(0.4, 0.9, 0.95), "min_floor": 6,
		"kinds": ["slime", "brute", "chort", "masked_orc", "frost_zombie", "frost_big_zombie"]},
}
const CHANCE_BASE: float = 0.05   # tỉ lệ ở tầng 2
const CHANCE_PER_FLOOR: float = 0.02
const CHANCE_MAX: float = 0.22
const HELL_MIN_FLOOR: int = 11    # Chương Địa Ngục: quái có affix nhiều hơn
const HELL_CHANCE: float = 0.32
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
const SPLIT_COUNT: int = 2
const SPLIT_HP_FRACTION: float = 0.35  # máu mỗi quái con so với quái gốc cùng loại/tầng
const FRENZY_PER_KILL: float = 0.08    # +8% tốc độ cho mỗi quái khác chết
const FRENZY_MAX: float = 0.40
const BLINK_INTERVAL_MIN: float = 5.0
const BLINK_INTERVAL_MAX: float = 7.0
const BLINK_MIN_DIST: float = 120.0    # chỉ dịch chuyển khi người chơi ở xa hơn mức này
const BLINK_TELEGRAPH: float = 0.5
const BLINK_BEHIND_DIST: float = 60.0  # đáp xuống sau lưng người chơi bấy nhiêu px
const LEECH_FRACTION: float = 0.30     # hồi 30% sát thương đã gây

var enemy: Node2D = null
var id: String = ""
var _timer: float = 0.0
var _ward_left: float = 0.0
var _warded: Array = []
var _t: float = 0.0
var _frenzy: float = 0.0
var _last_alive: int = -1
var _blink_target: Vector2 = Vector2.ZERO
var _blink_left: float = 0.0

## Tỉ lệ có affix ở một tầng (0 ở tầng 1).
static func chance_for_floor(floor_num: int) -> float:
	if floor_num < 2:
		return 0.0
	if floor_num >= HELL_MIN_FLOOR:
		return HELL_CHANCE
	return clampf(CHANCE_BASE + CHANCE_PER_FLOOR * float(floor_num - 2), 0.0, CHANCE_MAX)

## Số quái có affix tối đa mỗi phòng (Heat Veteran Packs cộng thêm).
static func max_per_room() -> int:
	return MAX_PER_ROOM + (Global.HeatScript.AFFIX_EXTRA_PER_ROOM if Global.heat_on("elite_pack") else 0)

## Chọn affix cho 1 quái: "" nếu không trúng / không có affix hợp lệ.
static func roll(kind: String, floor_num: int) -> String:
	var chance: float = chance_for_floor(floor_num)
	if chance > 0.0 and Global.heat_on("elite_pack"):
		chance = minf(1.0, chance + Global.HeatScript.AFFIX_CHANCE_BONUS) # Heat: Veteran Packs
	if randf() >= chance:
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
	elif id == "splitter":
		enemy.died.connect(_on_splitter_died)
	elif id == "blink":
		_timer = randf_range(BLINK_INTERVAL_MIN, BLINK_INTERVAL_MAX)

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
					Global.sfx("affix_summon")
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
		"frenzy":
			_tick_frenzy()
			queue_redraw()
		"blink":
			_tick_blink(delta)
			queue_redraw()

func _tick_frenzy() -> void:
	var n: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.alive:
			n += 1
	if _last_alive >= 0 and n < _last_alive:
		_frenzy = minf(FRENZY_MAX, _frenzy + FRENZY_PER_KILL * float(_last_alive - n))
		enemy.speed_mult = 1.0 + _frenzy
		Global.sfx("affix_frenzy")
	_last_alive = n

func _tick_blink(delta: float) -> void:
	if _blink_left > 0.0: # đang báo trước
		_blink_left -= delta
		if _blink_left <= 0.0:
			Global.burst(enemy.global_position, color_of(id), 10, 160.0, 1.5)
			enemy.global_position = _blink_target
			Global.burst(_blink_target, color_of(id), 10, 160.0, 1.5)
			Global.sfx("affix_blink")
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = randf_range(BLINK_INTERVAL_MIN, BLINK_INTERVAL_MAX)
	var p = Global.player
	if not is_instance_valid(p) or not p.alive:
		return
	if enemy.global_position.distance_to(p.global_position) < BLINK_MIN_DIST:
		return
	var dir: Vector2 = (p.global_position - enemy.global_position).normalized()
	var target: Vector2 = p.global_position + dir * BLINK_BEHIND_DIST
	# Không đáp vào tường: nếu có vật cản giữa người chơi và điểm đáp thì dừng trước vật cản.
	var q := PhysicsRayQueryParameters2D.create(p.global_position, target, Global.L_WORLD)
	var hit: Dictionary = enemy.get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		target = Vector2(hit["position"]) - dir * 16.0
	_blink_target = target
	_blink_left = BLINK_TELEGRAPH
	Global.sfx("affix_blink_warn")

## Splitter: chỉ tách khi bị hạ bằng sát thương; bị kill() ép chết thì không (dọn phòng).
func _on_splitter_died(_e = null) -> void:
	if not is_instance_valid(enemy) or enemy.hurtbox.hp > 0.0:
		return
	Global.sfx("affix_split")
	split_requested.emit(enemy)

## Leech: melee_hitbox_component gọi khi quái gây sát thương cho người chơi.
func on_hit_player(damage: int) -> void:
	if id != "leech" or not is_instance_valid(enemy) or not bool(enemy.get("alive")):
		return
	var heal: float = float(damage) * LEECH_FRACTION
	enemy.hurtbox.hp = minf(enemy.hurtbox.max_hp, enemy.hurtbox.hp + heal)
	Global.burst(enemy.global_position, color_of(id), 6, 110.0, 1.0)
	Global.sfx("affix_leech")

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
		Global.sfx("ward_cast")

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
	hz.fire_sfx = "volatile_boom"
	hz.source = "affix:volatile"
	hz.color = Color(1.0, 0.5, 0.1, 0.5)
	Global.world.add_child(hz)
	hz.global_position = enemy.global_position

func _draw() -> void:
	if id == "frenzy" and is_instance_valid(enemy) and _frenzy > 0.0:
		var k: float = _frenzy / FRENZY_MAX
		draw_arc(Vector2.ZERO, 16.0 + 3.0 * sin(_t * 10.0), 0.0, TAU, 24, Color(color_of(id), 0.25 + 0.5 * k), 2.0)
	if id == "blink" and _blink_left > 0.0:
		var pos: Vector2 = to_local(_blink_target)
		var ratio: float = 1.0 - _blink_left / BLINK_TELEGRAPH
		draw_arc(pos, 18.0, 0.0, TAU, 24, Color(color_of(id), 0.4 + 0.5 * ratio), 2.0)
		draw_circle(pos, 18.0 * ratio, Color(color_of(id), 0.25))
	if id == "warden" and is_instance_valid(enemy) and bool(enemy.get("alive")):
		var pulse: float = 0.5 + 0.5 * sin(_t * 3.0)
		var c: Color = color_of(id)
		draw_arc(Vector2.ZERO, WARD_RADIUS, 0.0, TAU, 48, Color(c, 0.12 + 0.10 * pulse), 2.0)
		if _ward_left > 0.0:
			draw_circle(Vector2.ZERO, WARD_RADIUS, Color(c, 0.05))
