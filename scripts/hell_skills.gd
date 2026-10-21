extends Node
## Kỹ năng riêng của quái Địa Ngục (tầng 11+), con của enemy.gd giống mimic_skills.gd. Một file, rẽ theo kind:
##   hell_ogre    - Lao Thẳng: đứng im báo trước (vạch đỏ chỉ hướng, khoá hướng ở 0.25s cuối) rồi lao theo
##                  đường thẳng, trúng thì gây sát thương + hất; để lại vệt lửa trên đường lao. Lăn né là tránh được.
##   hell_acolyte - Hộ Pháp: định kỳ cấp khiên tạm cho tối đa 2 quái gần nhất (không cấp cho Acolyte khác);
##                  hạ nó thì khiên tan ngay -> phải ưu tiên hạ Acolyte.
##   cinder_tiny  - Tro Tàn: tự nổ khi chạm (xử lý ở MeleeHitbox) và khi chết để lại vũng lửa có báo trước.
## Enemy gọi drive() mỗi khung vật lý để ghi đè hướng/tốc độ. Mọi con số cân bằng nằm ở đầu file.

const BOSS_HAZARD = preload("res://scripts/boss_hazard.gd")
const KINDS: Array = ["hell_ogre", "hell_acolyte", "cinder_tiny"]

# --- Ogre: Lao Thẳng ---
const CHARGE_RANGE: float = 300.0       # chỉ lao khi Player trong tầm này
const CHARGE_MIN_RANGE: float = 90.0    # quá gần thì đánh thường, không lao
const CHARGE_WINDUP: float = 0.7
const CHARGE_AIM_LOCK: float = 0.25     # giây cuối của báo trước: hướng đã khoá (cho người chơi né)
const CHARGE_TIME: float = 0.55
const CHARGE_SPEED: float = 380.0       # px/giây
const CHARGE_RECOVER: float = 0.6
const CHARGE_COOLDOWN: float = 4.5
const CHARGE_DAMAGE: int = 26
const CHARGE_KNOCK: float = 520.0
const CHARGE_HIT_REACH: float = 18.0    # cộng với bán kính quái = tầm trúng
const TRAIL_INTERVAL: float = 0.10
const TRAIL_RADIUS: float = 20.0
const TRAIL_DAMAGE: int = 4
const TRAIL_DURATION: float = 2.2
const TRAIL_BURN_TICKS: int = 2
const STALE_GAP_MS: int = 300           # drive() bị bỏ qua lâu hơn mức này (choáng) thì huỷ chiêu đang dở
const STALE_COOLDOWN: float = 1.5

# --- Acolyte: Hộ Pháp ---
const WARD_FIRST_DELAY: float = 1.5
const WARD_INTERVAL: float = 4.5
const WARD_DURATION: float = 3.5
const WARD_RADIUS: float = 200.0
const WARD_TARGETS: int = 2
const WARD_FRACTION: float = 0.40       # khiên = 40% máu tối đa của quái được che
const WARD_COLOR: Color = Color(0.95, 0.35, 0.5)

# --- Cinder: vũng lửa ---
const PUDDLE_RADIUS: float = 42.0
const PUDDLE_TELEGRAPH: float = 0.5
const PUDDLE_DURATION: float = 3.0
const PUDDLE_DAMAGE: int = 5
const PUDDLE_TICK: float = 0.6
const PUDDLE_BURN_TICKS: int = 2
const PUDDLE_COLOR: Color = Color(1.0, 0.4, 0.1, 0.45)

var _e: CharacterBody2D
var _state: String = "idle" # ogre: idle | windup | charge | recover
var _state_t: float = 0.0
var _cd: float = 1.5
var _dir: Vector2 = Vector2.RIGHT
var _hit: bool = false
var _trail_t: float = 0.0
var _line: Line2D = null
var _last_drive_ms: int = 0
var _ward_t: float = WARD_FIRST_DELAY
var _ward_left: float = 0.0
var _warded: Array = []

func attach(enemy: CharacterBody2D) -> void:
	_e = enemy
	_e.died.connect(_on_died)
	_last_drive_ms = Time.get_ticks_msec()

## Trả về [hướng_di_chuyển, hệ_số_tốc_độ]; enemy.gd dùng thay cho hướng thường.
func drive(delta: float, move: Vector2) -> Array:
	var now: int = Time.get_ticks_msec()
	var gap: int = now - _last_drive_ms
	_last_drive_ms = now
	match _e.kind:
		"hell_ogre":
			if gap > STALE_GAP_MS and _state != "idle":
				_cancel_charge()
			return _drive_ogre(delta, move)
		"hell_acolyte":
			_tick_ward(delta)
	return [move, 1.0]

# ------------------------------------------------------------------ Ogre
func _drive_ogre(delta: float, move: Vector2) -> Array:
	var p = Global.player
	var alive_p: bool = is_instance_valid(p) and p.alive
	_state_t += delta
	match _state:
		"idle":
			_cd -= delta
			if _cd <= 0.0 and _e.active and alive_p and _e.has_los:
				var dist: float = _e.global_position.distance_to(p.global_position)
				if dist <= CHARGE_RANGE and dist >= CHARGE_MIN_RANGE:
					_begin_windup(p)
		"windup":
			if alive_p and _state_t < CHARGE_WINDUP - CHARGE_AIM_LOCK:
				_dir = (p.global_position - _e.global_position).normalized()
				_update_line()
			if _state_t >= CHARGE_WINDUP:
				_begin_charge()
			return [Vector2.ZERO, 0.0]
		"charge":
			_trail_t -= delta
			if _trail_t <= 0.0:
				_trail_t = TRAIL_INTERVAL
				_drop_trail()
			if not _hit and alive_p:
				var reach: float = float(_e.data["radius"]) + CHARGE_HIT_REACH
				if _e.global_position.distance_to(p.global_position) <= reach:
					_hit = true
					p.take_damage(CHARGE_DAMAGE, _e.global_position, CHARGE_KNOCK, false, false, "enemy:hell_ogre")
			if _state_t >= CHARGE_TIME:
				_state = "recover"
				_state_t = 0.0
			return [_dir, CHARGE_SPEED / maxf(1.0, float(_e.data["speed"]))]
		"recover":
			if _state_t >= CHARGE_RECOVER:
				_state = "idle"
				_cd = CHARGE_COOLDOWN
			return [Vector2.ZERO, 0.0]
	return [move, 1.0]

func _begin_windup(p: Node) -> void:
	_state = "windup"
	_state_t = 0.0
	_dir = (p.global_position - _e.global_position).normalized()
	Global.sfx("ogre_windup")
	_line = Line2D.new()
	_line.width = 8.0
	_line.default_color = Color(1.0, 0.25, 0.1, 0.5)
	_line.z_index = -1
	_e.add_child(_line)
	_update_line()

func _update_line() -> void:
	if _line == null:
		return
	var reach: float = CHARGE_SPEED * CHARGE_TIME
	_line.clear_points()
	_line.add_point(Vector2.ZERO)
	_line.add_point(_dir * reach)

func _begin_charge() -> void:
	_state = "charge"
	_state_t = 0.0
	_hit = false
	_trail_t = 0.0
	_free_line()
	Global.sfx("ogre_charge")
	Global.shake(0.3, 0.15)

func _cancel_charge() -> void:
	_state = "idle"
	_cd = STALE_COOLDOWN
	_free_line()

func _free_line() -> void:
	if is_instance_valid(_line):
		_line.queue_free()
	_line = null

func _drop_trail() -> void:
	_spawn_hazard(_e.global_position, TRAIL_RADIUS, TRAIL_DAMAGE, 0.0, TRAIL_DURATION, TRAIL_BURN_TICKS, "")

# ------------------------------------------------------------------ Acolyte
func _tick_ward(delta: float) -> void:
	if _ward_left > 0.0:
		_ward_left -= delta
		if _ward_left <= 0.0:
			_clear_wards()
	_ward_t -= delta
	if _ward_t > 0.0 or not _e.active:
		return
	_ward_t = WARD_INTERVAL
	_grant_wards()

func _grant_wards() -> void:
	_clear_wards()
	var cands: Array = []
	for o in get_tree().get_nodes_in_group("enemies"):
		if o == _e or not is_instance_valid(o) or not o.alive or o.kind == "hell_acolyte":
			continue
		if o.hurtbox.ward > 0.0:
			continue
		var d: float = o.global_position.distance_to(_e.global_position)
		if d <= WARD_RADIUS:
			cands.append([d, o])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(WARD_TARGETS, cands.size()):
		var o: Node = cands[i][1]
		o.hurtbox.ward = maxf(o.hurtbox.ward, float(o.max_hp) * WARD_FRACTION)
		_warded.append(o)
		Global.burst(o.global_position, WARD_COLOR, 8, 120.0, 1.4)
	if not _warded.is_empty():
		_ward_left = WARD_DURATION
		Global.sfx("ward_cast")
		Global.burst(_e.global_position, WARD_COLOR, 10, 140.0, 1.5)

func _clear_wards() -> void:
	for o in _warded:
		if is_instance_valid(o) and o.get("hurtbox") != null:
			o.hurtbox.ward = 0.0
	_warded.clear()
	_ward_left = 0.0

# ------------------------------------------------------------------ chung
func _on_died(_enemy = null) -> void:
	match _e.kind:
		"hell_acolyte":
			_clear_wards() # giết Acolyte thì khiên tan ngay
		"cinder_tiny":
			# Nổ khi bị hạ bằng sát thương hoặc tự huỷ khi chạm; bị kill() ép chết lúc dọn phòng thì không.
			if _e.hurtbox.hp <= 0.0 or _e.has_meta("self_destruct"):
				# Hoãn sang khung kế: tự nổ xảy ra ngay trong callback vật lý (body_entered), lúc đó không thêm được Area2D.
				_spawn_hazard.call_deferred(_e.global_position, PUDDLE_RADIUS, PUDDLE_DAMAGE, PUDDLE_TELEGRAPH,
					PUDDLE_DURATION, PUDDLE_BURN_TICKS, "cinder_burst", "enemy:cinder_tiny")
		"hell_ogre":
			_free_line()

func _spawn_hazard(pos: Vector2, radius: float, dmg: int, telegraph: float, duration: float, burn_ticks: int, sfx_name: String, src: String = "enemy:hell_ogre") -> void:
	var hz := Area2D.new()
	hz.set_script(BOSS_HAZARD)
	hz.source = src
	hz.damage = dmg
	hz.radius = radius
	hz.telegraph_time = telegraph
	hz.duration = duration
	hz.tick_interval = PUDDLE_TICK
	hz.apply_burn_ticks = burn_ticks
	hz.color = PUDDLE_COLOR
	hz.fire_sfx = sfx_name
	Global.world.add_child(hz)
	hz.global_position = pos
