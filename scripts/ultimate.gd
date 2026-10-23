extends Node
## ULTIMATE: thanh nộ nạp bằng cách gây sát thương / hạ gục / nhận sát thương; đầy thì bấm phím "ultimate" (X) tung chiêu cuối
## riêng của class rồi thanh về 0. Node con của Player; tách khỏi vật lý của Player — chỉ nghe tín hiệu Global:
##   player_hit_landed (nạp khi gây sát thương), player_damaged (nạp khi bị đánh). HUD đọc meter()/is_ready()/name.
## Thanh nộ lưu ở Global.run_ult_meter (qua tầng + saved_run). Thêm chiêu = thêm 1 dòng ULTIMATES + 1 hàm _start_<id>/_tick_<id>.

const MinionScript = preload("res://scripts/minion.gd")
const RingFx = preload("res://scripts/skill_ring_fx.gd")
const WarnFx = preload("res://scripts/skill_warn_fx.gd")
const BULLET = preload("res://scenes/bullet.tscn")

signal ultimate_used(ult_id: String)
signal ultimate_ready

const ULTIMATES: Dictionary = {
	"bullet_storm": {"name": "Bullet Storm", "desc": "For 4s you unleash rings of bullets in every direction."},
	"earthquake": {"name": "Earthquake", "desc": "Three crushing shockwaves that stun everything nearby and clear enemy bullets."},
	"starfall": {"name": "Starfall", "desc": "For 4s meteors rain down around you."},
	"blade_tempest": {"name": "Blade Tempest", "desc": "For 3s you are invulnerable and spin, shredding everything close."},
	"horde": {"name": "Summon Horde", "desc": "Call 3 Spirits, 2 Wisps and a Guardian at once, stronger than usual."},
}

const METER_MAX: float = 100.0
const HIT_CHARGE: float = 0.7           # mỗi đòn trúng
const KILL_CHARGE: float = 2.0          # thưởng thêm khi hạ gục
const HIT_BUDGET_MAX: float = 6.0       # nạp từ đòn trúng tối đa 6 điểm/giây (chống AoE/đạn rải nạp quá nhanh)
const TAKEN_FACTOR: float = 0.6         # nhận 10% máu tối đa -> +6 điểm
const TAKEN_CAP: float = 15.0           # tối đa mỗi cú đánh

var player: Node = null
var ult_id: String = ""
var ult_name: String = ""
var active_left: float = 0.0
var _budget: float = HIT_BUDGET_MAX
var _tick: float = 0.0
var _spin: float = 0.0
var _count: int = 0

static func id_for_class(cid: String) -> String:
	return String(Global.classes.get(cid, {}).get("ultimate", ""))

static func exists(id: String) -> bool:
	return ULTIMATES.has(id)

func setup(p_player: Node, id: String) -> void:
	player = p_player
	ult_id = id
	ult_name = String(ULTIMATES.get(id, {}).get("name", ""))
	Global.player_hit_landed.connect(_on_hit_landed)
	Global.player_damaged.connect(_on_player_damaged)

func _exit_tree() -> void:
	if Global.player_hit_landed.is_connected(_on_hit_landed):
		Global.player_hit_landed.disconnect(_on_hit_landed)
	if Global.player_damaged.is_connected(_on_player_damaged):
		Global.player_damaged.disconnect(_on_player_damaged)

# ---------------------------------------------------------------- Thanh nộ
func meter() -> float:
	return Global.run_ult_meter

func ratio() -> float:
	return clampf(Global.run_ult_meter / METER_MAX, 0.0, 1.0)

func is_ready() -> bool:
	return Global.run_ult_meter >= METER_MAX and active_left <= 0.0

func add_charge(amount: float) -> void:
	if amount <= 0.0 or active_left > 0.0:
		return
	var was_ready: bool = Global.run_ult_meter >= METER_MAX
	Global.run_ult_meter = minf(METER_MAX, Global.run_ult_meter + amount)
	if not was_ready and Global.run_ult_meter >= METER_MAX:
		ultimate_ready.emit()
		Global.message.emit("ULTIMATE READY  [%s]" % Global.key_name_for_action("ultimate"), Color(1.0, 0.85, 0.3))
		Global.sfx("pickup", 0.6)

func _on_hit_landed(target: Node, _dmg: int, _crit: bool) -> void:
	var gain: float = minf(HIT_CHARGE, _budget)
	_budget -= gain
	if is_instance_valid(target) and not bool(target.get("alive")):
		gain += KILL_CHARGE
	add_charge(gain)

func _on_player_damaged(amount: int, max_hp: int) -> void:
	if max_hp <= 0:
		return
	add_charge(minf(TAKEN_CAP, float(amount) / float(max_hp) * 100.0 * TAKEN_FACTOR))

# ---------------------------------------------------------------- Tung chiêu
func _physics_process(delta: float) -> void:
	_budget = minf(HIT_BUDGET_MAX, _budget + HIT_BUDGET_MAX * delta)
	if active_left > 0.0:
		active_left = maxf(0.0, active_left - delta)
		if is_instance_valid(player) and player.alive:
			_tick_active(delta)
		else:
			active_left = 0.0
	if is_instance_valid(player) and player.alive and Input.is_action_just_pressed("ultimate"):
		try_activate()

func try_activate() -> bool:
	if ult_id == "" or not is_ready() or not is_instance_valid(player) or not player.alive:
		return false
	Global.run_ult_meter = 0.0
	_tick = 0.0
	_count = 0
	Global.message.emit(ult_name.to_upper() + "!", Color(1.0, 0.85, 0.3))
	Global.shake(0.8, 0.4)
	Global.hitstop(0.08)
	ultimate_used.emit(ult_id)
	call("_start_" + ult_id)
	return true

func _tick_active(delta: float) -> void:
	_tick -= delta
	call("_tick_" + ult_id, delta)

## Hệ số sát thương chung: sát thương phụ của class × Skill Power × nút Honed Technique.
func _power() -> float:
	return float(player._secondary_dmg_mult()) * (1.0 + float(player.skill_power())) * Global.SkillTree.skill_damage_mult(Global.upgrades)

func _dmg(base: float, per_floor: float) -> int:
	return maxi(1, int((base + per_floor * float(Global.floor_num)) * _power()))

func _ring(pos: Vector2, radius: float, color: Color, duration: float = 0.4) -> void:
	var fx := Node2D.new()
	fx.set_script(RingFx)
	fx.max_radius = radius
	fx.color = color
	fx.duration = duration
	Global.world.add_child(fx)
	fx.global_position = pos

## Sát thương + đẩy lùi + (tuỳ chọn) choáng mọi quái/boss quanh `origin`.
func _damage_area(origin: Vector2, radius: float, dmg: int, knock: float, stun: float = 0.0) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.alive and e.global_position.distance_to(origin) <= radius:
			e.take_damage(dmg, origin, knock)
			if stun > 0.0 and e.alive and e.has_method("apply_status"):
				e.apply_status("stun", stun)
			Global.on_secondary_hit(e, dmg, false, "ult")
	for b in get_tree().get_nodes_in_group("boss"):
		if is_instance_valid(b) and b.alive and b.global_position.distance_to(origin) <= radius + 20.0:
			b.take_damage(dmg, origin, 0.0)
			Global.on_secondary_hit(b, dmg, false, "ult")

# ---------------------------------------------------------------- Ranger: Bullet Storm
const STORM_DURATION: float = 4.0
const STORM_PULSE: float = 0.25
const STORM_BULLETS: int = 12
const STORM_COLOR: Color = Color(1.0, 0.85, 0.4)

func _start_bullet_storm() -> void:
	active_left = STORM_DURATION
	_spin = randf() * TAU

func _tick_bullet_storm(_delta: float) -> void:
	if _tick > 0.0:
		return
	_tick = STORM_PULSE
	_spin += 0.21
	var dmg: int = _dmg(6.0, 0.8)
	for i in STORM_BULLETS:
		var dir: Vector2 = Vector2.from_angle(_spin + TAU * float(i) / float(STORM_BULLETS))
		var b = BULLET.instantiate()
		b.setup(true, dir, dmg, 520.0, 0.9, STORM_COLOR, 5.0)
		Global.world.add_child(b)
		b.global_position = player.global_position + dir * 20.0
	Global.sfx("barrage_volley", 0.9 + 0.1 * float(_count % 3))
	_count += 1

# ---------------------------------------------------------------- Brawler: Earthquake
const QUAKE_PULSES: int = 3
const QUAKE_GAP: float = 0.5
const QUAKE_RADIUS: float = 230.0
const QUAKE_KNOCK: float = 520.0
const QUAKE_STUN: float = 1.2
const QUAKE_SHIELD: float = 30.0
const QUAKE_COLOR: Color = Color(1.0, 0.7, 0.3)

func _start_earthquake() -> void:
	active_left = QUAKE_GAP * float(QUAKE_PULSES - 1) + 0.05
	player.shield = minf(float(player.max_shield), player.shield + QUAKE_SHIELD)
	_quake_pulse()
	_tick = QUAKE_GAP

func _tick_earthquake(_delta: float) -> void:
	if _tick <= 0.0:
		_tick = QUAKE_GAP
		_quake_pulse()

func _quake_pulse() -> void:
	var origin: Vector2 = player.global_position
	_damage_area(origin, QUAKE_RADIUS, _dmg(34.0, 3.5), QUAKE_KNOCK, QUAKE_STUN)
	for eb in get_tree().get_nodes_in_group("enemy_bullets"):
		if is_instance_valid(eb) and eb.global_position.distance_to(origin) <= QUAKE_RADIUS + 10.0:
			eb.queue_free()
	_ring(origin, QUAKE_RADIUS, QUAKE_COLOR, 0.5)
	Global.burst(origin, QUAKE_COLOR, 28, 340.0, 2.0)
	Global.shake(0.7, 0.35)
	Global.sfx("shockwave", 0.8)

# ---------------------------------------------------------------- Mage: Starfall
const FALL_DURATION: float = 4.0
const FALL_GAP: float = 0.33
const FALL_DELAY: float = 0.55
const FALL_RADIUS: float = 85.0
const FALL_SPREAD: float = 300.0
const FALL_COLOR: Color = Color(0.7, 0.5, 1.0)

func _start_starfall() -> void:
	active_left = FALL_DURATION
	_tick = 0.0

func _tick_starfall(_delta: float) -> void:
	if _tick > 0.0:
		return
	_tick = FALL_GAP
	var pos: Vector2 = player.global_position + Vector2.from_angle(randf() * TAU) * randf_range(60.0, FALL_SPREAD)
	var warn := Node2D.new()
	warn.set_script(WarnFx)
	warn.radius = FALL_RADIUS
	warn.duration = FALL_DELAY
	warn.color = FALL_COLOR
	Global.world.add_child(warn)
	warn.global_position = pos
	_star_land(pos)

func _star_land(pos: Vector2) -> void:
	await get_tree().create_timer(FALL_DELAY).timeout
	if not is_instance_valid(player) or not player.alive or not is_inside_tree():
		return
	_damage_area(pos, FALL_RADIUS, _dmg(46.0, 4.2), 280.0)
	_ring(pos, FALL_RADIUS, FALL_COLOR, 0.35)
	Global.burst(pos, FALL_COLOR, 16, 240.0, 1.8)
	Global.shake(0.3, 0.2)
	Global.sfx("meteor_impact", 1.1)

# ---------------------------------------------------------------- Rogue: Blade Tempest
const TEMPEST_DURATION: float = 3.0
const TEMPEST_TICK: float = 0.2
const TEMPEST_RADIUS: float = 120.0
const TEMPEST_COLOR: Color = Color(0.7, 1.0, 0.7)

func _start_blade_tempest() -> void:
	active_left = TEMPEST_DURATION
	player.hurt_timer.start(TEMPEST_DURATION) # bất tử suốt thời gian xoay
	_tick = 0.0

func _tick_blade_tempest(_delta: float) -> void:
	if player.hurt_timer.time_left < active_left + 0.05:
		player.hurt_timer.start(active_left + 0.05)
	if _tick > 0.0:
		return
	_tick = TEMPEST_TICK
	_damage_area(player.global_position, TEMPEST_RADIUS, int(float(_dmg(11.0, 1.2)) * 1.5), 140.0)
	_ring(player.global_position, TEMPEST_RADIUS, TEMPEST_COLOR, 0.2)
	if _count % 3 == 0:
		Global.sfx("shadow_dash", 1.0 + 0.1 * float(_count % 5))
	_count += 1

# ---------------------------------------------------------------- Summoner: Summon Horde
const HORDE_KINDS: Array = ["spirit", "spirit", "spirit", "wisp", "wisp", "guardian"]
const HORDE_POWER: float = 1.5

func _start_horde() -> void:
	active_left = 0.1
	var power: float = _power() * float(player.minion_dmg_mult()) * HORDE_POWER
	for i in HORDE_KINDS.size():
		var ang: float = TAU * float(i) / float(HORDE_KINDS.size())
		MinionScript.spawn(player, String(HORDE_KINDS[i]), player.global_position + Vector2.from_angle(ang) * 36.0, power, 0.85, i % 3, "ult")
	_ring(player.global_position, 90.0, Color(0.85, 0.5, 0.95), 0.5)
	Global.burst(player.global_position, Color(0.85, 0.5, 0.95), 24, 260.0, 1.8)
	Global.sfx("barrage_cast", 0.7)

func _tick_horde(_delta: float) -> void:
	pass
