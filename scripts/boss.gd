extends CharacterBody2D
## Boss "Vệ Binh Hầm Ngục" - 3 pha theo % máu, mọi đòn đều có TELEGRAPH (vẽ bằng _draw + Tween).
##   Pha 1 (>66%)  : Lao thẳng + Bắn toả tròn 12 viên
##   Pha 2 (>33%)  : + Dập đất + Triệu hồi Slime, bắn 2 vòng, nhanh hơn
##   Pha 3 (<=33%) : cuồng nộ - đổi màu đỏ, nhịp đánh nhanh nhất
## Nhịp đánh: AttackTimer (Timer node). Chuỗi đòn: await create_timer / Tween.

signal died
signal summon_requested(kind: String, pos: Vector2)

const BULLET = preload("res://scenes/bullet.tscn")
const BOSS_NAME: String = "Dungeon Warden"
const SLAM_RADIUS: float = 150.0
const BODY_RADIUS: float = 34.0

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
@onready var hitbox: Area2D = $Hitbox
@onready var slam_area: Area2D = $SlamArea
@onready var attack_timer: Timer = $AttackTimer
@onready var sprite: AnimatedSprite2D = $Sprite

const SPRITE_PREFIX: String = "orc_warrior"
const SPRITE_SCALE: float = 4.3
const SPRITE_OFFSET_Y: float = -15.0
## Khớp với position của node Body/Hitbox trong boss.tscn — dùng để vẽ telegraph
## đúng ngay thân Boss thay vì ở gốc chân (Vector2.ZERO).
const BODY_CENTER_OFFSET: Vector2 = Vector2(0, -43)
## Màu theo pha (khớp bảng palette trong _draw gốc) — tint lên sprite để vẫn báo pha rõ ràng.
const PHASE_TINT: Array = [Color(0.6, 0.25, 0.8), Color(0.9, 0.5, 0.15), Color(1.0, 0.15, 0.15)]


## Tâm hitbox thật (capsule Body, đã lệch lên BODY_CENTER_OFFSET) — dùng để tính
## trúng đòn cận chiến của Player và khoảng cách chống ôm, thay vì global_position
## (gốc chân) vốn gây lệch "đánh từ trên xuống dễ hụt, dưới lên dễ trúng".
func hurt_center() -> Vector2:
	return $Body.global_position

func setup(hp_mult: float = 1.0) -> void:
	# === THAY THẾ LOGIC TÍNH HP GỐC BẰNG THUẬT TOÁN NÀY ===
	var floor_scale: float = 1.0 + 0.3 * float(Global.floor_num - 1)
	max_hp = 700.0 * hp_mult * floor_scale
	hp = max_hp
	armor = floor((Global.floor_num - 1) * 1.6) + 2.0
	cc_resist = minf(0.3 + (Global.floor_num - 1) * 0.2, 0.9)
	# ======================================================
func activate_boss() -> void:
	if not active:
		active = true
		create_tween().tween_property(self, "modulate:a", 1.0, 0.2)
		print("Boss đã thức tỉnh!")
		attack_timer.start(1.0)


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("boss")
	hitbox.body_entered.connect(_on_hitbox_entered)
	slam_area.body_entered.connect(_on_slam_entered)
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	active = false
	modulate.a = 0.4
	sprite.sprite_frames = _build_sprite_frames()
	sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	sprite.offset = Vector2(0.0, SPRITE_OFFSET_Y)
	sprite.modulate = PHASE_TINT[0]
	sprite.play("idle")


func _build_sprite_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	_add_anim(frames, "idle", 4, 5.0, true)
	_add_anim(frames, "run", 4, 9.0, true)
	return frames


func _add_anim(frames: SpriteFrames, anim: String, count: int, fps: float, loop: bool) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, loop)
	for i in count:
		var path: String = "res://assets/dungeon/%s_%s_anim_f%d.png" % [SPRITE_PREFIX, anim, i]
		var tex := Global.load_tex(path)
		if tex:
			frames.add_frame(anim, tex)


func _update_sprite() -> void:
	sprite.modulate = PHASE_TINT[phase - 1]
	var look: Vector2 = Vector2.RIGHT
	var p = Global.player
	if is_instance_valid(p):
		look = (p.global_position - global_position).normalized()
	if look.x != 0.0:
		sprite.flip_h = look.x < 0.0
	var want_anim: String = "run" if velocity.length() > 5.0 else "idle"
	if sprite.animation != want_anim:
		sprite.play(want_anim)


func _on_intro_done() -> void:
	active = true
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)


func _cooldown() -> float:
	var table: Array = [1.6, 1.15, 0.7]
	return float(table[phase - 1])


func _speed_mult() -> float:
	var table: Array = [ 0.85, 0.7,0.5]
	return float(table[phase - 1])


# ------------------------------------------------------------------ Vòng đời đòn đánh
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
	var pool: Array = ["charge", "ring"]
	if phase >= 2:
		pool.append("slam")
		pool.append("summon")
	var attack: String = pool.pick_random()
	match attack:
		"charge":
			await _atk_charge()
		"ring":
			await _atk_ring()
		"slam":
			await _atk_slam()
		"summon":
			await _atk_summon()
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


# ---- Đòn 1: Lao thẳng (vạch đỏ báo hướng)
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


# ---- Đòn 2: Bắn toả tròn (viền vàng nhấp nháy báo trước)
func _atk_ring() -> void:
	await _telegraph("flash", 0.7 * _speed_mult())
	if not alive:
		return
	_fire_ring(12, 0.0)
	if phase >= 2:
		await get_tree().create_timer(0.35).timeout
		if not alive:
			return
		_fire_ring(12, PI / 12.0)
	await get_tree().create_timer(0.3).timeout


func _fire_ring(count: int, angle_offset: float) -> void:
	Global.sfx("enemy_shoot")
	for i in count:
		var ang: float = angle_offset + TAU * float(i) / float(count)
		var b = BULLET.instantiate()
		b.setup(false, Vector2.from_angle(ang), 10, 230.0, 3.0, Color(1.0, 0.7, 0.2), 7.0)
		Global.world.add_child(b)
		b.global_position = global_position + Vector2.from_angle(ang) * (BODY_RADIUS + 6.0)


# ---- Đòn 3: Dập đất (vòng cam mở rộng báo trước)
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


# ---- Đòn 4: Triệu hồi Slime
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
		if dist_to_player < BODY_RADIUS + 5.0: # Cộng thêm 5 pixel sai số
			var dmg = 26 if charging else 15
			var knock = 600.0 if charging else 350.0
			# Gọi hàm take_damage của player, ép văng ra ngoài
			p.take_damage(dmg, global_position, knock)
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
		
	# === THAY THẾ ĐOẠN TRỪ MÁU GỐC BẰNG ĐOẠN NÀY ===
	var current_armor = armor
	if phase == 3:
		current_armor += 3.0
		
	var actual_damage = maxi(1, amount - int(current_armor))
	hp = maxf(hp - float(actual_damage), 0.0)
	
	Global.sfx("hit")
	Global.float_text(global_position + Vector2(0.0, -30.0), str(actual_damage), Color(1.0, 0.95, 0.5), 18)
	# ===============================================
	
	Global.burst(global_position, Color(0.9, 0.4, 0.9), 5, 130.0, 1.0)
	modulate = Color(2.2, 2.2, 2.2)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.1)
	
	if hp <= 0.0:
		_die()
		return
		
	var ratio: float = hp / max_hp
	var new_phase: int = 1
	if ratio <= 0.33:
		new_phase = 3
	elif ratio <= 0.66:
		new_phase = 2
	if new_phase > phase:
		phase = new_phase
		pending_roar = true
	Global.boss_hp_changed.emit(hp, max_hp, phase, BOSS_NAME)


func _die() -> void:
	alive = false
	# Bổ sung: Ghi nhận 1 mạng hạ gục Boss vào sổ thống kê
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
	# Thân Boss giờ do $Sprite vẽ (tint theo pha); _draw() chỉ còn giữ nguyên các
	# hiệu ứng TELEGRAPH báo trước đòn đánh — đây là cơ chế gameplay cốt lõi, không đổi.
	match tele_mode:
		"line":
			# Vạch báo lao thẳng: xuất phát từ tâm thân thật, không phải gốc chân.
			draw_line(BODY_CENTER_OFFSET, BODY_CENTER_OFFSET + charge_dir * 520.0, Color(1.0, 0.1, 0.1, 0.15 + 0.45 * tele_t), 72.0)
			draw_line(BODY_CENTER_OFFSET, BODY_CENTER_OFFSET + charge_dir * 520.0, Color(1.0, 0.3, 0.3, 0.9), 3.0)
		"ring":
			# Hiệu ứng dộng đất — đúng ra phải ở gốc chân/mặt đất, giữ nguyên Vector2.ZERO.
			draw_arc(Vector2.ZERO, SLAM_RADIUS, 0.0, TAU, 64, Color(1.0, 0.6, 0.1, 0.85), 3.0)
			draw_circle(Vector2.ZERO, SLAM_RADIUS * tele_t, Color(1.0, 0.5, 0.1, 0.28))
		"flash":
			# Viền cảnh báo quanh THÂN Boss (trước đòn bắn toả tròn) — neo theo tâm thân thật.
			if int(tele_t * 10.0) % 2 == 0:
				draw_arc(BODY_CENTER_OFFSET, BODY_RADIUS + 12.0, 0.0, TAU, 32, Color(1.0, 0.9, 0.2), 5.0)
