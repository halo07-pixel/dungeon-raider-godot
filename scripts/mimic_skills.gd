extends Node
## Kỹ năng riêng của Mimic (con của enemy.gd, giống cách enemy_affix.gd gắn vào):
##   Lao Cắn  - đứng im báo trước (đỏ) rồi lao thẳng vào Player; lăn né là tránh được.
##   Cướp Vàng - đòn trúng cướp một phần vàng; trả lại ngay khi Mimic bị hạ.
##   Phun Xu  - ở xa thì thả vài quả xu nổ chậm quanh Player (vùng báo trước, né được).
##   Nổi giận - dưới 50% máu: nhanh hơn, hồi chiêu ngắn hơn, báo trước ngắn hơn.
## Enemy gọi drive() mỗi khung vật lý để ghi đè hướng/tốc độ; mọi con số cân bằng ở đầu file.

const BOSS_HAZARD = preload("res://scripts/boss_hazard.gd")

const LUNGE_RANGE: float = 260.0        # chỉ lao khi Player trong tầm này
const LUNGE_WINDUP: float = 0.6
const LUNGE_TIME: float = 0.35
const LUNGE_SPEED_MULT: float = 4.5     # nhân tốc độ gốc của Mimic
const LUNGE_RECOVER: float = 0.5
const LUNGE_DAMAGE: int = 28
const LUNGE_KNOCK: float = 420.0
const LUNGE_COOLDOWN: float = 3.5
const STEAL_FRACTION: float = 0.2       # tối đa 20% vàng hiện có
const STEAL_MIN_COINS: int = 5          # có ít hơn thì không cướp
const SPIT_MIN_RANGE: float = 220.0     # chỉ phun khi Player ở xa hơn tầm này
const SPIT_COUNT: int = 3
const SPIT_FUSE: float = 1.1            # thời gian báo trước trước khi nổ
const SPIT_RADIUS: float = 38.0
const SPIT_DAMAGE: int = 12
const SPIT_COOLDOWN: float = 5.0
const SPIT_SPREAD: float = 90.0         # xu rơi cách Player tối đa bấy nhiêu px
const RAGE_HP_FRACTION: float = 0.5
const RAGE_SPEED_MULT: float = 1.3
const RAGE_COOLDOWN_MULT: float = 0.6   # hồi chiêu và báo trước nhân hệ số này
const RAGE_TINT: Color = Color(1.5, 0.7, 0.6)

var _e: CharacterBody2D
var _state: String = "idle" # idle | windup | lunge | recover
var _state_t: float = 0.0
var _lunge_dir: Vector2 = Vector2.RIGHT
var _lunge_hit: bool = false
var _lunge_cd: float = 1.5
var _spit_cd: float = 2.0
var stolen: int = 0
var enraged: bool = false

func attach(enemy: CharacterBody2D) -> void:
	_e = enemy
	_e.died.connect(_on_died)

func _rage_mult() -> float:
	return RAGE_COOLDOWN_MULT if enraged else 1.0

func _check_rage() -> void:
	if enraged:
		return
	if _e.max_hp > 0.0 and _e.hp <= _e.max_hp * RAGE_HP_FRACTION:
		enraged = true
		_e.modulate = RAGE_TINT
		Global.sfx("mimic_rage")
		Global.burst(_e.global_position, Color(1.0, 0.3, 0.2), 14, 200.0, 1.5)

## Trả về [hướng_di_chuyển, hệ_số_tốc_độ]; enemy.gd dùng thay cho hướng thường.
func drive(delta: float, move: Vector2) -> Array:
	_check_rage()
	_lunge_cd = maxf(0.0, _lunge_cd - delta)
	_spit_cd = maxf(0.0, _spit_cd - delta)
	var p = Global.player
	var have_p: bool = is_instance_valid(p) and p.alive
	var speed_mult: float = RAGE_SPEED_MULT if enraged else 1.0
	match _state:
		"idle":
			if enraged and _e.modulate.is_equal_approx(Color.WHITE): # flash trúng đòn tự về trắng
				_e.modulate = RAGE_TINT
			if have_p and _e.active:
				var dist: float = _e.global_position.distance_to(p.global_position)
				if _lunge_cd <= 0.0 and dist <= LUNGE_RANGE:
					_begin("windup")
					Global.sfx("mimic_windup")
					_lunge_dir = (p.global_position - _e.global_position).normalized()
				elif _spit_cd <= 0.0 and dist >= SPIT_MIN_RANGE:
					_spit(p)
		"windup":
			_state_t -= delta
			if have_p: # nhìn theo Player trong lúc nạp, khóa hướng lúc bắt đầu lao
				_lunge_dir = (p.global_position - _e.global_position).normalized()
			_e.modulate = Color(2.0, 0.5, 0.5) if int(_state_t * 14.0) % 2 == 0 else (RAGE_TINT if enraged else Color.WHITE)
			if _state_t <= 0.0:
				_begin("lunge")
				Global.sfx("mimic_lunge")
			return [Vector2.ZERO, 0.0]
		"lunge":
			_state_t -= delta
			if have_p and not _lunge_hit and _e.global_position.distance_to(p.global_position) <= 30.0:
				_lunge_hit = true
				var dodged: bool = p.has_method("is_invulnerable") and p.is_invulnerable()
				p.take_damage(LUNGE_DAMAGE, _e.global_position, LUNGE_KNOCK, false, false, "enemy:mimic")
				if not dodged:
					Global.sfx("mimic_bite")
					steal_from(p)
			if _state_t <= 0.0:
				_e.modulate = RAGE_TINT if enraged else Color.WHITE
				_begin("recover")
			return [_lunge_dir, LUNGE_SPEED_MULT * speed_mult]
		"recover":
			_state_t -= delta
			if _state_t <= 0.0:
				_state = "idle"
				_lunge_cd = LUNGE_COOLDOWN * _rage_mult()
			return [Vector2.ZERO, 0.0]
	return [move, speed_mult]

func _begin(s: String) -> void:
	_state = s
	_lunge_hit = false
	match s:
		"windup": _state_t = LUNGE_WINDUP * _rage_mult()
		"lunge": _state_t = LUNGE_TIME
		"recover": _state_t = LUNGE_RECOVER

## Cướp Vàng: gọi khi Mimic đánh trúng (chạm thường hoặc Lao Cắn).
func steal_from(p) -> void:
	if Global.coins < STEAL_MIN_COINS:
		return
	var amount: int = maxi(1, int(float(Global.coins) * STEAL_FRACTION))
	Global.coins -= amount
	stolen += amount
	Global.stolen_gold_held += amount
	Global.message.emit("Mimic stole %d gold! Kill it to get it back" % amount, Color(1.0, 0.8, 0.2))
	Global.sfx("mimic_steal")

func _spit(p) -> void:
	_spit_cd = SPIT_COOLDOWN * _rage_mult()
	Global.sfx("mimic_spit")
	for i in SPIT_COUNT:
		var hz := Area2D.new()
		hz.set_script(BOSS_HAZARD)
		hz.source = "enemy:mimic"
		hz.damage = SPIT_DAMAGE
		hz.duration = 0.3
		hz.single_shot = true
		hz.radius = SPIT_RADIUS
		hz.telegraph_time = SPIT_FUSE * _rage_mult()
		hz.fire_sfx = "spit_pop" if i == 0 else "" # một tiếng nổ cho cả loạt
		hz.color = Color(1.0, 0.8, 0.2, 0.5)
		Global.world.add_child(hz)
		hz.global_position = p.global_position + Vector2.from_angle(randf() * TAU) * randf_range(0.0, SPIT_SPREAD)

func _on_died(_enemy) -> void:
	if stolen > 0:
		var back: int = _return_gold()
		Global.message.emit("Recovered %d gold" % back, Color(1.0, 0.85, 0.3))

## Trả vàng đã cướp về cho người chơi (chết, hoặc bị dọn đi cùng tầng/cảnh khi còn sống).
func _return_gold() -> int:
	var back: int = stolen
	Global.coins += back
	Global.stolen_gold_held = maxi(0, Global.stolen_gold_held - back)
	stolen = 0
	return back

func _exit_tree() -> void:
	if stolen > 0:
		_return_gold() # tầng mới / thoát về menu khi Mimic còn sống: không để mất vàng
