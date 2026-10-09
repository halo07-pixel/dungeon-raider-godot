extends CharacterBody2D
## Boss đa loại (data-driven qua "kind", giống cách enemy.gd xử lý nhiều loại quái):
##   "warden"      : Dungeon Warden (Biome 1, tầng 1-3)  - brawler cận chiến, GIỮ NGUYÊN hành vi gốc.
##   "necromancer" : Dark Necromancer (Biome 2, tầng 4-6) - pháp sư tầm xa, dịch chuyển né cận chiến.
##   "frost"       : Frozen Horror (Biome 3, tầng 7-9)    - bruiser khống chế, làm chậm + gai băng.
##   "lord"        : Dungeon Lord (tầng 10, boss cuối)    - tổng hợp cả 3, 4 pha thay vì 3.
## Mọi đòn đều có TELEGRAPH (báo trước) bằng _draw() + Tween, không đòn nào "ăn gian" vô hình.
## Nhịp đánh: AttackTimer (Timer node). Chuỗi đòn: await create_timer / Tween.

signal died
signal summon_requested(kind: String, pos: Vector2)

const BULLET = preload("res://scenes/bullet.tscn")
const BOSS_HAZARD = preload("res://scripts/boss_hazard.gd")
const SLAM_RADIUS: float = 150.0
const BODY_RADIUS_BASE: float = 34.0

## Cấu hình riêng từng loại boss. "sprite" phải khớp tên file trong assets/dungeon/.
## "has_run": true nếu asset có sẵn animation "run" riêng, false thì dùng chung idle cho cả 2.
## "body_mult": tỉ lệ phóng to/nhỏ hitbox (Body capsule + Hitbox circle) so với Warden gốc,
## đã hiệu chỉnh BẰNG MẮT qua ảnh chụp debug overlay (không đoán từ kích thước ảnh gốc).
const BOSS_DATA: Dictionary = {
	"warden": {
		"name": "Dungeon Warden", "sprite": "orc_warrior",
		"scale": 4.3, "offset_y": -15.0, "base_hp": 700.0,
		"body_mult": 1.0, "has_run": true, "phases": 3,
	},
	"necromancer": {
		"name": "Dark Necromancer", "sprite": "necromancer",
		"scale": 4.3, "offset_y": -13.0, "base_hp": 620.0,
		"body_mult": 0.82, "has_run": false, "phases": 3,
	},
	"frost": {
		"name": "Frozen Horror", "sprite": "ice_zombie",
		"scale": 4.6, "offset_y": -2.0, "base_hp": 820.0,
		"body_mult": 0.85, "has_run": false, "phases": 3,
	},
	"lord": {
		"name": "Dungeon Lord", "sprite": "big_demon",
		"scale": 3.2, "offset_y": -20.0, "base_hp": 1500.0,
		"body_mult": 1.25, "has_run": false, "phases": 4,
	},
}
## Màu tint theo pha (dùng chung, Lord dùng cả 4 ô).
const PHASE_TINT: Array = [Color(0.6, 0.25, 0.8), Color(0.9, 0.5, 0.15), Color(1.0, 0.15, 0.15), Color(1.0, 1.0, 1.0)]
const COOLDOWN_TABLE: Array = [1.6, 1.15, 0.7, 0.5]
const SPEED_MULT_TABLE: Array = [0.85, 0.7, 0.5, 0.4]
## Khớp với position của node Body/Hitbox trong boss.tscn — dùng để vẽ telegraph
## đúng ngay thân Boss thay vì ở gốc chân (Vector2.ZERO).
const BODY_CENTER_OFFSET_BASE: Vector2 = Vector2(0, -43)

var kind: String = "warden"
var BOSS_NAME: String = "Dungeon Warden"
var BODY_RADIUS: float = BODY_RADIUS_BASE
var BODY_CENTER_OFFSET: Vector2 = BODY_CENTER_OFFSET_BASE

var max_hp: float = 700.0
var hp: float = 700.0
var phase: int = 1
var alive: bool = true
var active: bool = false
var busy: bool = false
var pending_roar: bool = false
var charging: bool = false
var charge_dir: Vector2 = Vector2.RIGHT
var tele_mode: String = ""
var tele_t: float = 0.0
var _t: float = 0.0
var armor: float = 0.0
var cc_resist: float = 0.0
var is_boss: bool = true
var blink_cd: float = 0.0 # riêng Necromancer: hồi chiêu dịch chuyển né cận chiến

@onready var hitbox: Area2D = $Hitbox
@onready var slam_area: Area2D = $SlamArea
@onready var attack_timer: Timer = $AttackTimer
@onready var sprite: AnimatedSprite2D = $Sprite


## Tâm hitbox thật (capsule Body, đã lệch lên) — dùng để tính trúng đòn cận chiến
## của Player và khoảng cách chống ôm, thay vì global_position (gốc chân).
func hurt_center() -> Vector2:
	return $Body.global_position


func setup(hp_mult: float = 1.0, p_kind: String = "warden") -> void:
	kind = p_kind if BOSS_DATA.has(p_kind) else "warden"
	var cfg: Dictionary = BOSS_DATA[kind]
	BOSS_NAME = cfg["name"]
	var floor_scale: float = 1.0 + 0.3 * float(Global.floor_num - 1)
	max_hp = float(cfg["base_hp"]) * hp_mult * floor_scale
	hp = max_hp
	armor = floor((Global.floor_num - 1) * 1.6) + 2.0
	cc_resist = minf(0.3 + (Global.floor_num - 1) * 0.2, 0.9)
	BODY_RADIUS = BODY_RADIUS_BASE * float(cfg["body_mult"])
	BODY_CENTER_OFFSET = BODY_CENTER_OFFSET_BASE * float(cfg["body_mult"])


func activate_boss() -> void:
	if not active:
		active = true
		create_tween().tween_property(self, "modulate:a", 1.0, 0.2)
		attack_timer.start(1.0)


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("boss")

	var cfg: Dictionary = BOSS_DATA[kind]
	var body_mult: float = float(cfg["body_mult"])
	if not is_equal_approx(body_mult, 1.0):
		var body_shape: CapsuleShape2D = $Body.shape.duplicate()
		body_shape.radius *= body_mult
		body_shape.height *= body_mult
		$Body.shape = body_shape
		var hit_shape: CircleShape2D = $Hitbox/Shape.shape.duplicate()
		hit_shape.radius *= body_mult
		$Hitbox/Shape.shape = hit_shape
	$Body.position = BODY_CENTER_OFFSET
	$Hitbox.position = BODY_CENTER_OFFSET

	hitbox.body_entered.connect(_on_hitbox_entered)
	slam_area.body_entered.connect(_on_slam_entered)
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	active = false
	modulate.a = 0.4
	sprite.sprite_frames = _build_sprite_frames()
	sprite.scale = Vector2(float(cfg["scale"]), float(cfg["scale"]))
	sprite.offset = Vector2(0.0, float(cfg["offset_y"]))
	sprite.modulate = PHASE_TINT[0]
	sprite.play("idle")


func _build_sprite_frames() -> SpriteFrames:
	var cfg: Dictionary = BOSS_DATA[kind]
	var prefix: String = cfg["sprite"]
	var has_run: bool = cfg["has_run"]
	var frames := SpriteFrames.new()
	_add_anim(frames, prefix, "idle", "idle", 4, 5.0, true)
	if has_run:
		_add_anim(frames, prefix, "run", "run", 4, 9.0, true)
	else:
		_add_anim(frames, prefix, "idle", "run", 4, 5.0, true) # không có run riêng -> dùng chung idle
	return frames


func _add_anim(frames: SpriteFrames, prefix: String, src_suffix: String, anim: String, count: int, fps: float, loop: bool) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, loop)
	for i in count:
		var path: String = "res://assets/dungeon/%s_%s_anim_f%d.png" % [prefix, src_suffix, i]
		var tex := Global.load_tex(path)
		if tex:
			frames.add_frame(anim, tex)


func _update_sprite() -> void:
	sprite.modulate = PHASE_TINT[mini(phase - 1, PHASE_TINT.size() - 1)]
	var look: Vector2 = Vector2.RIGHT
	var p = Global.player
	if is_instance_valid(p):
		look = (p.global_position - global_position).normalized()
	if look.x != 0.0:
		sprite.flip_h = look.x < 0.0
	var want_anim: String = "run" if velocity.length() > 5.0 else "idle"
	if sprite.animation != want_anim:
		sprite.play(want_anim)


func _cooldown() -> float:
	return COOLDOWN_TABLE[mini(phase - 1, COOLDOWN_TABLE.size() - 1)]


func _speed_mult() -> float:
	return SPEED_MULT_TABLE[mini(phase - 1, SPEED_MULT_TABLE.size() - 1)]


# ------------------------------------------------------------------ Vòng đời đòn đánh
func _attack_pool() -> Array:
	match kind:
		"necromancer":
			var pool: Array = ["necro_bolt", "necro_summon"]
			if phase >= 2:
				pool.append("necro_curse")
			if phase >= 3:
				pool.append("necro_bolt") # tăng tỉ lệ bolt ở pha cuối
			return pool
		"frost":
			var pool: Array = ["frost_breath", "spike_field"]
			if phase >= 2:
				pool.append("frost_charge")
			if phase >= 3:
				pool.append("blizzard")
			return pool
		"lord":
			var pool: Array = ["charge", "ring"]
			if phase >= 2:
				pool.append("necro_bolt")
				pool.append("necro_curse")
			if phase >= 3:
				pool.append("frost_breath")
				pool.append("spike_field")
			if phase >= 4:
				pool.append("judgement")
			return pool
		_: # warden
			var pool: Array = ["charge", "ring"]
			if phase >= 2:
				pool.append("slam")
				pool.append("summon")
			return pool


func _on_attack_timer_timeout() -> void:
	if not alive or busy or not active:
		return
	var p = Global.player
	if not is_instance_valid(p) or not p.alive:
		attack_timer.start(1.0)
		return
	busy = true
	if pending_roar:
		pending_roar = false
		await _roar()
		if not alive:
			return
	var attack: String = _attack_pool().pick_random()
	match attack:
		"charge": await _atk_charge()
		"ring": await _atk_ring()
		"slam": await _atk_slam()
		"summon": await _atk_summon()
		"necro_bolt": await _atk_necro_bolt()
		"necro_summon": await _atk_necro_summon()
		"necro_curse": await _atk_necro_curse()
		"frost_breath": await _atk_frost_breath()
		"spike_field": await _atk_frost_spike_field()
		"frost_charge": await _atk_frost_charge()
		"blizzard": await _atk_blizzard()
		"judgement": await _atk_judgement()
	if not alive:
		return
	busy = false
	attack_timer.start(_cooldown())


func _telegraph(mode: String, duration: float) -> void:
	tele_mode = mode
	tele_t = 0.0
	var tw := create_tween()
	tw.tween_method(_set_tele, 0.0, 1.0, duration)
	await tw.finished
	tele_mode = ""
	queue_redraw()


func _set_tele(v: float) -> void:
	tele_t = v
	queue_redraw()


func _roar() -> void:
	Global.sfx("roar")
	Global.shake(0.9, 0.6)
	Global.burst(global_position, Color(1.0, 0.3, 0.2), 40, 320.0, 2.5)
	Global.hitstop(0.1)
	await get_tree().create_timer(0.9).timeout


# ==============================================================================
# BỘ ĐÒN WARDEN (gốc, không đổi)
# ==============================================================================
func _atk_charge() -> void:
	var p = Global.player
	charge_dir = (p.global_position - global_position).normalized()
	await _telegraph("line", 0.85 * _speed_mult())
	if not alive:
		return
	Global.sfx("boss_charge")
	charging = true
	hitbox.set_deferred("monitoring", true)
	await get_tree().create_timer(0.5).timeout
	if not alive:
		return
	_end_charge()
	await get_tree().create_timer(0.35).timeout


func _end_charge() -> void:
	charging = false
	hitbox.set_deferred("monitoring", false)


func _atk_ring() -> void:
	await _telegraph("flash", 0.7 * _speed_mult())
	if not alive:
		return
	_fire_ring(12, 0.0, Color(1.0, 0.7, 0.2))
	if phase >= 2:
		await get_tree().create_timer(0.35).timeout
		if not alive:
			return
		_fire_ring(12, PI / 12.0, Color(1.0, 0.7, 0.2))
	await get_tree().create_timer(0.3).timeout


func _fire_ring(count: int, angle_offset: float, color: Color) -> void:
	Global.sfx("enemy_shoot")
	for i in count:
		var ang: float = angle_offset + TAU * float(i) / float(count)
		var b = BULLET.instantiate()
		b.setup(false, Vector2.from_angle(ang), 10, 230.0, 3.0, color, 7.0)
		Global.world.add_child(b)
		b.global_position = hurt_center() + Vector2.from_angle(ang) * (BODY_RADIUS + 6.0)


func _atk_slam() -> void:
	await _telegraph("ring", 0.9 * _speed_mult())
	if not alive:
		return
	Global.sfx("slam")
	Global.shake(0.8, 0.35)
	Global.burst(global_position, Color(1.0, 0.6, 0.2), 30, 300.0, 2.0)
	slam_area.set_deferred("monitoring", true)
	await get_tree().create_timer(0.12).timeout
	slam_area.set_deferred("monitoring", false)
	if not alive:
		return
	await get_tree().create_timer(0.5).timeout


func _atk_summon() -> void:
	await _telegraph("flash", 0.6 * _speed_mult())
	if not alive:
		return
	var n: int = 2 if phase == 2 else 3
	Global.sfx("door")
	for i in n:
		var ang: float = TAU * float(i) / float(n) + randf() * 0.5
		summon_requested.emit("slime", global_position + Vector2.from_angle(ang) * 90.0)
	await get_tree().create_timer(0.5).timeout


# ==============================================================================
# BỘ ĐÒN DARK NECROMANCER — pháp sư tầm xa, chống cận chiến
# ==============================================================================
func _atk_necro_bolt() -> void:
	await _telegraph("flash", 0.5 * _speed_mult())
	if not alive:
		return
	var p = Global.player
	if not is_instance_valid(p):
		return
	var count: int = 3 if phase >= 3 else 1
	Global.sfx("enemy_shoot")
	var base_dir: Vector2 = ((p.hurt_center() if p.has_method("hurt_center") else p.global_position) - hurt_center()).normalized()
	for i in count:
		var ang_off: float = 0.0 if count == 1 else deg_to_rad(lerpf(-18.0, 18.0, float(i) / float(count - 1)))
		var dir: Vector2 = base_dir.rotated(ang_off)
		var b = BULLET.instantiate()
		b.setup(false, dir, 16, 190.0, 3.5, Color(0.7, 0.3, 0.9), 8.0)
		b.homing = true
		b.homing_target = p
		Global.world.add_child(b)
		b.global_position = hurt_center() + dir * (BODY_RADIUS + 10.0)
	await get_tree().create_timer(0.3).timeout


func _atk_necro_summon() -> void:
	await _telegraph("flash", 0.6 * _speed_mult())
	if not alive:
		return
	Global.sfx("door")
	var n: int = 2
	for i in n:
		var ang: float = TAU * float(i) / float(n) + randf() * 0.5
		summon_requested.emit("archer", global_position + Vector2.from_angle(ang) * 90.0)
	await get_tree().create_timer(0.4).timeout


func _atk_necro_curse() -> void:
	var p = Global.player
	var target_pos: Vector2 = (p.hurt_center() if p.has_method("hurt_center") else p.global_position) if is_instance_valid(p) else global_position
	Global.sfx("door")
	var hz := Area2D.new()
	hz.set_script(BOSS_HAZARD)
	hz.damage = 8
	hz.tick_interval = 0.6
	hz.duration = 3.2
	hz.radius = 70.0
	hz.telegraph_time = 0.7 * _speed_mult()
	hz.color = Color(0.55, 0.15, 0.75, 0.45)
	Global.world.add_child(hz)
	hz.global_position = target_pos
	await get_tree().create_timer(0.7 * _speed_mult() + 0.1).timeout


func _necro_blink() -> void:
	blink_cd = 3.0
	var p = Global.player
	if not is_instance_valid(p):
		return
	var away_dir: Vector2 = (global_position - p.global_position).normalized()
	if away_dir == Vector2.ZERO:
		away_dir = Vector2.RIGHT
	global_position += away_dir * 260.0
	Global.sfx("dodge")
	Global.burst(global_position, Color(0.6, 0.2, 0.9), 20, 200.0, 1.5)


# ==============================================================================
# BỘ ĐÒN FROZEN HORROR — bruiser khống chế, kiểm soát khu vực
# ==============================================================================
func _atk_frost_breath() -> void:
	var p = Global.player
	if not is_instance_valid(p):
		return
	charge_dir = (p.global_position - global_position).normalized()
	await _telegraph("cone", 0.8 * _speed_mult())
	if not alive:
		return
	Global.sfx("boss_charge")
	Global.burst(global_position + charge_dir * 40.0, Color(0.4, 0.9, 1.0), 20, 200.0, 1.5)
	if is_instance_valid(p) and p.alive:
		var to_p: Vector2 = (p.hurt_center() if p.has_method("hurt_center") else p.global_position) - hurt_center()
		var dist: float = to_p.length()
		if dist < 150.0 and dist > 0.01:
			var ang: float = absf(charge_dir.angle_to(to_p.normalized()))
			if ang < deg_to_rad(40.0):
				p.take_damage(22, global_position, 260.0)
	await get_tree().create_timer(0.3).timeout


func _atk_frost_spike_field() -> void:
	var p = Global.player
	var center: Vector2 = p.global_position if is_instance_valid(p) else global_position
	Global.sfx("slam")
	var n: int = 5
	for i in n:
		var ang: float = TAU * float(i) / float(n) + randf() * 0.4
		var pos: Vector2 = center + Vector2.from_angle(ang) * randf_range(20.0, 110.0)
		var hz := Area2D.new()
		hz.set_script(BOSS_HAZARD)
		hz.single_shot = true
		hz.damage = 18
		hz.radius = 34.0
		hz.telegraph_time = 0.65
		hz.color = Color(0.5, 0.9, 1.0, 0.55)
		Global.world.add_child(hz)
		hz.global_position = pos
	await get_tree().create_timer(0.9).timeout


func _atk_frost_charge() -> void:
	var p = Global.player
	charge_dir = (p.global_position - global_position).normalized()
	await _telegraph("line", 1.1 * _speed_mult())
	if not alive:
		return
	Global.sfx("boss_charge")
	charging = true
	hitbox.set_deferred("monitoring", true)
	await get_tree().create_timer(0.65).timeout
	if not alive:
		return
	_end_charge()
	await get_tree().create_timer(0.3).timeout


func _atk_blizzard() -> void:
	await _telegraph("ring", 0.5 * _speed_mult())
	if not alive:
		return
	Global.sfx("roar")
	Global.shake(0.6, 0.4)
	var p = Global.player
	if is_instance_valid(p) and p.alive:
		var d: float = hurt_center().distance_to(p.hurt_center() if p.has_method("hurt_center") else p.global_position)
		if d < 260.0:
			p.take_damage(14, global_position, 180.0)
			if p.has_method("apply_status"):
				p.apply_status("slow", 1.2)
	Global.burst(global_position, Color(0.6, 0.9, 1.0), 30, 260.0, 2.0)
	var n: int = 2
	for i in n:
		var ang: float = TAU * float(i) / float(n) + randf() * 0.6
		summon_requested.emit("slime", global_position + Vector2.from_angle(ang) * 100.0)
	await get_tree().create_timer(0.5).timeout


# ==============================================================================
# ĐÒN ĐỘC QUYỀN DUNGEON LORD — "Phán Quyết" (pha 4, ultimate)
# ==============================================================================
func _atk_judgement() -> void:
	var p = Global.player
	var center: Vector2 = p.global_position if is_instance_valid(p) else global_position
	Global.message.emit("Dungeon Lord đang tụ sức mạnh...!", Color(1.0, 0.2, 0.2))
	Global.shake(0.3, 1.5)
	Global.sfx("roar")
	var hz := Area2D.new()
	hz.set_script(BOSS_HAZARD)
	hz.single_shot = true
	hz.damage = 42
	hz.radius = 170.0
	hz.telegraph_time = 1.6
	hz.color = Color(1.0, 0.15, 0.15, 0.5)
	Global.world.add_child(hz)
	hz.global_position = center
	await get_tree().create_timer(1.8).timeout


# ------------------------------------------------------------------ Va chạm (signal)
func _on_hitbox_entered(body: Node) -> void:
	if charging and body.is_in_group("player"):
		body.take_damage(26, global_position, 520.0)


func _on_slam_entered(body: Node) -> void:
	if body.is_in_group("player"):
		body.take_damage(24, global_position, 560.0)


# ------------------------------------------------------------------ Di chuyển
func _physics_process(delta: float) -> void:
	_t += delta
	if not alive:
		return
	var p = Global.player

	# === CƠ CHẾ CHỐNG ÔM BOSS ===
	if active and is_instance_valid(p) and p.alive:
		var p_center = p.hurt_center() if p.has_method("hurt_center") else p.global_position
		var dist_to_player = hurt_center().distance_to(p_center)
		if dist_to_player < BODY_RADIUS + 5.0:
			var dmg = 26 if charging else 15
			var knock = 600.0 if charging else 350.0
			p.take_damage(dmg, global_position, knock)
		# Hào Quang Đóng Băng (Frost, pha 2+): làm chậm Player đứng gần (không cần chạm hẳn)
		elif kind == "frost" and phase >= 2 and dist_to_player < BODY_RADIUS + 110.0:
			if p.has_method("apply_status"):
				p.apply_status("slow", 0.5)
		# Dịch chuyển né cận chiến (Necromancer): nếu Player áp sát thì blink ra xa
		if kind == "necromancer":
			blink_cd = maxf(0.0, blink_cd - delta)
			if dist_to_player < 130.0 and blink_cd <= 0.0 and active:
				_necro_blink()
	# ============================

	if charging:
		velocity = charge_dir * 640.0
	elif not busy and active and is_instance_valid(p) and p.alive:
		velocity = (p.global_position - global_position).normalized() * (55.0 + 20.0 * float(phase))
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	if charging and get_slide_collision_count() > 0:
		Global.shake(0.5, 0.2)
		_end_charge()
	_update_sprite()
	queue_redraw()


# ------------------------------------------------------------------ Sát thương / chết
func take_damage(amount: int, _from_pos: Vector2 = Vector2.ZERO, _knock: float = 0.0) -> void:
	if not alive or not active:
		return

	var cfg: Dictionary = BOSS_DATA[kind]
	var max_phase: int = int(cfg["phases"])
	var current_armor = armor
	if phase >= max_phase:
		current_armor += 3.0

	var actual_damage = maxi(1, amount - int(current_armor))
	hp = maxf(hp - float(actual_damage), 0.0)

	Global.sfx("hit")
	Global.float_text(global_position + Vector2(0.0, -30.0), str(actual_damage), Color(1.0, 0.95, 0.5), 18)

	Global.burst(global_position, Color(0.9, 0.4, 0.9), 5, 130.0, 1.0)
	modulate = Color(2.2, 2.2, 2.2)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.1)

	if hp <= 0.0:
		_die()
		return

	var ratio: float = hp / max_hp
	var new_phase: int = _phase_for_ratio(ratio, max_phase)
	if new_phase > phase:
		phase = new_phase
		pending_roar = true
	Global.boss_hp_changed.emit(hp, max_hp, phase, BOSS_NAME)


## Chia đều ngưỡng % máu theo số pha của từng loại boss (3 pha: 66/33, 4 pha: 75/50/25).
func _phase_for_ratio(ratio: float, max_phase: int) -> int:
	for ph in range(max_phase, 1, -1):
		var threshold: float = float(max_phase - ph + 1) / float(max_phase)
		if ratio <= threshold:
			return ph
	return 1


func _die() -> void:
	alive = false
	if Global.get("run_stats") != null and Global.run_stats.has("kills"):
		Global.run_stats["kills"] += 1
	charging = false
	tele_mode = ""
	hitbox.set_deferred("monitoring", false)
	slam_area.set_deferred("monitoring", false)
	$Body.set_deferred("disabled", true)
	Global.sfx("roar")
	Global.shake(1.0, 0.7)
	Global.burst(global_position, Color(1.0, 0.8, 0.3), 60, 380.0, 3.0)
	Global.hitstop(0.2)
	Global.message.emit("%s defeated!" % BOSS_NAME, Color(1.0, 0.9, 0.3))
	Global.boss_defeated.emit()
	died.emit()
	create_tween().tween_property(self, "modulate:a", 0.0, 1.2)
	await get_tree().create_timer(2.0).timeout
	queue_free()


# ------------------------------------------------------------------ Vẽ + telegraph
func _draw() -> void:
	match tele_mode:
		"line":
			draw_line(BODY_CENTER_OFFSET, BODY_CENTER_OFFSET + charge_dir * 520.0, Color(1.0, 0.1, 0.1, 0.15 + 0.45 * tele_t), 72.0)
			draw_line(BODY_CENTER_OFFSET, BODY_CENTER_OFFSET + charge_dir * 520.0, Color(1.0, 0.3, 0.3, 0.9), 3.0)
		"ring":
			draw_arc(Vector2.ZERO, SLAM_RADIUS, 0.0, TAU, 64, Color(1.0, 0.6, 0.1, 0.85), 3.0)
			draw_circle(Vector2.ZERO, SLAM_RADIUS * tele_t, Color(1.0, 0.5, 0.1, 0.28))
		"flash":
			if int(tele_t * 10.0) % 2 == 0:
				draw_arc(BODY_CENTER_OFFSET, BODY_RADIUS + 12.0, 0.0, TAU, 32, Color(1.0, 0.9, 0.2), 5.0)
		"cone":
			var half: float = deg_to_rad(40.0)
			var pts := PackedVector2Array()
			pts.append(BODY_CENTER_OFFSET)
			for i in range(13):
				var a: float = -half + (2.0 * half) * float(i) / 12.0
				pts.append(BODY_CENTER_OFFSET + charge_dir.rotated(a) * 150.0)
			draw_colored_polygon(pts, Color(0.3, 0.85, 1.0, 0.15 + 0.35 * tele_t))
