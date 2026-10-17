extends CharacterBody2D
## Player: Tích hợp bảng hiệu ứng Sử thi/Huyền thoại chi tiết, Combo Dao Găm & Chém Đạn.

signal died

const BULLET = preload("res://scenes/bullet.tscn")
const ClassSkillScript = preload("res://scripts/class_skill.gd")
const SPEED: float = 230.0
const ROLL_SPEED: float = 560.0
const KNOCK_DECAY: float = 1400.0
var has_revived: bool = false
var max_hp: int = 100
var hp: int = 100
## Giáp Ảo (kiểu Soul Knight): hấp thụ sát thương TRƯỚC máu, tự hồi sau một nhịp không bị đánh.
const SHIELD_BASE: int = 20
const SHIELD_PER_FLOOR: int = 4
const SHIELD_REGEN_DELAY: float = 2.5
const SHIELD_REGEN_RATE: float = 10.0
var max_shield: int = 20
var shield_nova_cd: float = 0.0
var class_skill: Node = null ## Kỹ năng class tiến hoá (null nếu chưa mở)
var counter_timer: float = 0.0   # Phản Công: cửa sổ x2 sát thương sau khi bị đánh
var swing_count: int = 0         # Lốc Xoáy
var shot_count: int = 0          # Loạt Đạn Vòng / Siêu Đạn
var still_time: float = 0.0      # Tập Trung
var arc_timer: float = 0.0       # Sét Lan
const ARC_INTERVAL: float = 2.5
const RING_HOMING_DELAY: float = 0.12
const WHIRL_WAVE_COUNT: int = 6
const ROLL_SLASH_BASE_RADIUS: float = 85.0   # tầm Lăn Chém tối thiểu (như bản cũ)
const ROLL_SLASH_RANGE_FACTOR: float = 1.55  # bán kính = tầm chém hiện tại x hệ số này (nếu lớn hơn mức tối thiểu)
var shield: float = 20.0
const FORTIFY_SHIELD_PER_HIT: float = 1.0 # buff Fortify: giáp ảo nhận được mỗi đòn trúng
const FORTIFY_COOLDOWN: float = 0.25      # giây giữa 2 lần nhận (đòn xuyên/lan nhiều mục tiêu không cộng nhiều lần)
var _fortify_ready_msec: int = 0
var shield_delay_timer: float = 0.0
var weapon_id: String = "pistol"
var weapon_rarity: String = "common"
var rarity_data: Dictionary = {}
var weapon: Dictionary = {}
var alive: bool = true
var rolling: bool = false
var roll_dir: Vector2 = Vector2.RIGHT
var aim_dir: Vector2 = Vector2.RIGHT
var knockback: Vector2 = Vector2.ZERO
var slow_timer: float = 0.0 # Bị làm chậm bởi hào quang băng / hiệu ứng boss
var slide_timer: float = 0.0 # Bị trượt mất kiểm soát hướng đi (Ô Băng - biome Frost)
var slide_dir: Vector2 = Vector2.RIGHT
var last_move_dir: Vector2 = Vector2.RIGHT # Hướng di chuyển gần nhất, dùng để xác định hướng trượt
var poison_ticks: int = 0 # Số nhịp độc còn lại (Orc Shaman / Chort - biome Đầm Lầy)
var poison_timer: float = 0.0
var poison_dmg: int = 0
var stun_timer: float = 0.0 # Choáng (đòn "Giam Băng" của Frozen Horror) — khoá di chuyển/tấn công

var swinging: bool = false
var swing_progress: float = 0.0
## Tầm/góc chém THẬT đã cộng buff + độ hiếm của cú chém đang diễn ra — _draw() và
## _update_weapon_visual() phải đọc từ đây (không đọc thẳng weapon["range"]/["cleave_angle"])
## để vệt chém hiển thị luôn khớp vùng gây sát thương thật. Set lại mỗi lần _swing().
var display_swing_range: float = 0.0
var display_swing_half_angle: float = 0.0
## Vệt chém phai dần sau khi vung xong (chỉ hiển thị).
const SLASH_FADE_TIME: float = 0.14
const HEAVY_HIT_RATIO: float = 0.25 # đòn >= 25% máu tối đa = "nặng": rung mạnh + khựng + nháy viền đỏ
var _slash_fade: float = 0.0
var _slash_ang: float = 0.0
var dagger_combo: int = 0
var dagger_timer: float = 0.0

## Buff "Đà Chiến Đấu" (Sử Thi): cộng 1 stack mỗi lần tấn công (bắn/chém), hết hạn nếu
## ngừng tấn công quá MOMENTUM_WINDOW giây. Đơn giản hoá: tính theo HÀNH ĐỘNG tấn công
## (không chờ xác nhận trúng đòn) để khỏi phải vòng về từ bullet.gd mỗi viên đạn.
var momentum_stacks: int = 0
var momentum_timer: float = 0.0
const MOMENTUM_WINDOW: float = 1.2
const MOMENTUM_MAX_STACKS: int = 5
const MOMENTUM_PER_STACK: float = 0.05

@onready var fire_timer: Timer = $FireTimer
@onready var dodge_timer: Timer = $DodgeTimer
@onready var dodge_cooldown: Timer = $DodgeCooldown
@onready var hurt_timer: Timer = $HurtTimer
@onready var sprite: AnimatedSprite2D = $Sprite
@onready var weapon_sprite: Sprite2D = $WeaponSprite

## Ánh xạ lớp nhân vật -> bộ sprite 0x72 (DungeonTilesetII) dùng làm thân người.
const SPRITE_SET: Dictionary = {
	"ranger": "elf_m",
	"brawler": "knight_m",
}
const SPRITE_SCALE: float = 2.0
const SPRITE_OFFSET_Y: float = -11.0

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("player")
	Global.player = self

	var cls: Dictionary = Global.classes[Global.current_class]

	# ÁP DỤNG KỸ NĂNG: Tăng HP tối đa
	max_hp = cls["max_hp"] + (Global.upgrades["hp_boost"] * 10)
	hp = max_hp

	refresh_max_shield()
	shield = float(max_shield)
	Global.room_cleared.connect(_on_room_cleared)
	Global.player_hit_landed.connect(_on_hit_landed_fortify)

	set_weapon_with_rarity(cls["default_weapon"], "common")
	_attach_class_skill()
	dodge_timer.timeout.connect(_on_dodge_finished)

	sprite.sprite_frames = _build_sprite_frames()
	sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	sprite.offset = Vector2(0.0, SPRITE_OFFSET_Y)
	sprite.play("idle")


## Class đã tiến hoá (meta-progression) → gắn Node kỹ năng riêng, bấm phím "skill" (Q).
func _attach_class_skill() -> void:
	var sid: String = Global.class_skill_id()
	if sid == "":
		return
	class_skill = ClassSkillScript.new()
	class_skill.name = "ClassSkill"
	add_child(class_skill)
	class_skill.setup(self, sid)

func _build_sprite_frames() -> SpriteFrames:
	var prefix: String = SPRITE_SET.get(Global.current_class, "knight_m")
	var frames := SpriteFrames.new()
	_add_sprite_anim(frames, prefix, "idle", 4, 6.0, true)
	_add_sprite_anim(frames, prefix, "run", 4, 10.0, true)
	_add_sprite_anim(frames, prefix, "hit", 1, 1.0, false)
	return frames


func _add_sprite_anim(frames: SpriteFrames, prefix: String, anim: String, count: int, fps: float, loop: bool) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, loop)
	for i in count:
		var path: String = "res://assets/dungeon/%s_%s_anim_f%d.png" % [prefix, anim, i]
		var tex := Global.load_tex(path)
		if tex:
			frames.add_frame(anim, tex)


func _update_sprite() -> void:
	sprite.flip_h = aim_dir.x < 0.0
	if not hurt_timer.is_stopped():
		if sprite.animation != "hit":
			sprite.play("hit")
		sprite.modulate = Color(2.2, 1.2, 1.2) if int(float(Time.get_ticks_msec()) / 70.0) % 2 == 0 else Color.WHITE
		return
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.6) if rolling else Color.WHITE
	if rolling or velocity.length() > 5.0:
		if sprite.animation != "run":
			sprite.play("run")
	else:
		if sprite.animation != "idle":
			sprite.play("idle")

func is_invulnerable() -> bool:
	return rolling or not hurt_timer.is_stopped()

func dodge_ratio() -> float:
	if dodge_cooldown.is_stopped(): return 1.0
	return 1.0 - dodge_cooldown.time_left / dodge_cooldown.wait_time

## Boss/hazard/quái có thể áp trạng thái lên Player ("slow" - Hào Quang Băng,
## "slide" - Ô Băng biome Frost khiến trượt mất kiểm soát hướng đi, "poison" -
## Orc Shaman/Chort biome Đầm Lầy gây sát thương liên tục theo nhịp).
## Tham số thứ 3 (amount) CHỈ dùng cho "poison": duration lúc này mang nghĩa
## SỐ NHỊP độc (không phải giây) để khớp timer tick cố định 0.5s bên dưới.
## Giữ cùng chữ ký (type, duration) với enemy.gd::apply_status() để code gọi dùng chung được.
func apply_status(type: String, duration: float, amount: float = 0.0) -> void:
	if type == "slow":
		slow_timer = maxf(slow_timer, duration)
	elif type == "slide":
		slide_timer = maxf(slide_timer, duration)
		slide_dir = last_move_dir
	elif type == "stun":
		stun_timer = maxf(stun_timer, duration)
	elif type == "poison":
		poison_ticks = maxi(poison_ticks, int(duration))
		poison_dmg = maxi(poison_dmg, int(amount))
		if poison_timer <= 0.0:
			poison_timer = 0.5

func _physics_process(delta: float) -> void:
	if not alive: return
	_tick_shield(delta)
	_tick_buff_timers(delta)

	if dagger_timer > 0:
		dagger_timer -= delta
		if dagger_timer <= 0: dagger_combo = 0 # Trôi combo dao găm
	if slow_timer > 0.0:
		slow_timer = maxf(0.0, slow_timer - delta)
	if slide_timer > 0.0:
		slide_timer = maxf(0.0, slide_timer - delta)
	if momentum_timer > 0.0:
		momentum_timer = maxf(0.0, momentum_timer - delta)
		if momentum_timer <= 0.0:
			momentum_stacks = 0
	if poison_ticks > 0:
		poison_timer -= delta
		if poison_timer <= 0.0:
			poison_timer = 0.5
			poison_ticks -= 1
			# Độc BỎ QUA khung bất tử vật lý (hurt_timer) — venom không quan tâm bạn vừa
			# trúng đòn thường hay chưa, khác hẳn sát thương tiếp xúc thông thường.
			take_damage(poison_dmg, global_position, 0.0, true, true)

	if stun_timer > 0.0:
		stun_timer = maxf(0.0, stun_timer - delta)
		velocity = knockback
		knockback = knockback.move_toward(Vector2.ZERO, KNOCK_DECAY * delta)
		move_and_slide()
		_update_sprite()
		_update_weapon_visual()
		queue_redraw()
		return

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir != Vector2.ZERO:
		last_move_dir = input_dir.normalized()
	aim_dir = (get_global_mouse_position() - global_position).normalized()
	if aim_dir == Vector2.ZERO: aim_dir = Vector2.RIGHT

	if Input.is_action_just_pressed("dodge") and not rolling and dodge_cooldown.is_stopped():
		_start_roll(input_dir if input_dir != Vector2.ZERO else aim_dir)

	var speed_mult: float = 0.55 if slow_timer > 0.0 else 1.0
	if rolling: velocity = roll_dir * ROLL_SPEED
	elif slide_timer > 0.0: velocity = slide_dir * SPEED # Trượt: giữ nguyên hướng cũ, bỏ qua input mới
	else: velocity = input_dir * SPEED * speed_mult

	velocity += knockback
	knockback = knockback.move_toward(Vector2.ZERO, KNOCK_DECAY * delta)
	move_and_slide()

	if Input.is_action_pressed("shoot") and not rolling and fire_timer.is_stopped() and not swinging:
		if weapon.get("is_melee", false): _swing()
		else: _shoot()
	_update_sprite()
	_update_weapon_visual()
	queue_redraw()

## Gắn thuộc tính buff tầm xa lên viên đạn vừa tạo (Đạn Nảy / Phân Tách / Tầm Nhiệt).
func _apply_ranged_buffs(b) -> void:
	b.bounces_left = Global.buff_stack("buff_bounce")
	b.split_on_hit = Global.buff_stack("buff_split") > 0
	b.homing = Global.buff_stack("buff_homing") > 0

func _start_roll(dir: Vector2) -> void:
	rolling = true
	roll_dir = dir.normalized()
	PlayerProfiler.record_dodge(roll_dir.x) # AI Tầng 1: ghi nhận thói quen né trái/phải
	dodge_timer.start()
	dodge_cooldown.start()
	Global.sfx("dodge")
	Global.burst(global_position, Color(0.6, 0.8, 1.0), 6, 80.0, 1.0)
	# Buff "Né Hồi Phục": né thành công hồi máu (dodge_cooldown sẵn có đã tự giới hạn tần suất)
	if Global.buff_stack("buff_dodge_heal") > 0:
		heal(3 * Global.buff_stack("buff_dodge_heal"))

func _on_dodge_finished() -> void:
	rolling = false
	_roll_slash()

## Hệ số sát thương cộng thêm từ buff dùng chung (Sức Mạnh / Đà Chiến Đấu / Cuồng Nộ) — cho các
## nguồn sát thương PHỤ (Lăn Chém, Sét Lan, Giáp Phản Chấn) để buff không bị bỏ qua.
func _secondary_dmg_mult() -> float:
	var m: float = 1.0 + 0.08 * float(Global.buff_stack("buff_dmg"))
	if Global.buff_stack("buff_momentum") > 0:
		m += MOMENTUM_PER_STACK * float(momentum_stacks)
	if Global.buff_stack("buff_berserk") > 0 and max_hp > 0:
		m += 0.4 * (1.0 - float(hp) / float(max_hp))
	return m

## Tầm chém hiện tại của vũ khí cận chiến (đã cộng độ hiếm + Tầm Đánh + Càn Quét) — cùng công thức _swing().
func current_melee_range() -> float:
	var r: float = float(weapon.get("range", 40.0))
	if weapon_id == "broadsword" and weapon_rarity == "rare": r *= 1.2
	elif weapon_id == "hammer":
		if weapon_rarity == "rare": r *= 1.25
		elif weapon_rarity == "legendary": r *= 1.5
	if Global.buff_stack("buff_reach") > 0:
		r *= 1.0 + 0.15 * float(Global.buff_stack("buff_reach"))
	if Global.buff_stack("buff_sweep") > 0:
		r *= 1.5
	return r

## Bán kính Lăn Chém: tối thiểu 85 như cũ, nhưng tăng theo tầm chém (Tầm Đánh / Càn Quét / độ hiếm).
func roll_slash_radius() -> float:
	return maxf(ROLL_SLASH_BASE_RADIUS, current_melee_range() * ROLL_SLASH_RANGE_FACTOR)

## Buff Lăn Chém (cận chiến): kết thúc cú lăn chém vòng quanh.
func _roll_slash() -> void:
	var stacks: int = Global.buff_stack("buff_rollslash")
	if stacks <= 0 or not weapon.get("is_melee", false):
		return
	var dmg: int = maxi(1, int(float(weapon["damage"]) * rarity_data["mult"] * 1.2 * (1.0 + 0.25 * float(stacks - 1)) * _secondary_dmg_mult()))
	var rad: float = roll_slash_radius()
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.alive and e.global_position.distance_to(global_position) <= rad:
			e.take_damage(dmg, global_position, 320.0)
			Global.on_secondary_hit(e, dmg)
	for b in get_tree().get_nodes_in_group("boss"):
		if is_instance_valid(b) and b.alive and b.global_position.distance_to(global_position) <= rad + 25.0:
			b.take_damage(dmg, global_position, 0.0)
			Global.on_secondary_hit(b, dmg)
	Global.burst(global_position, Color(0.8, 0.9, 1.0), 14, 220.0, 1.5)

# ==============================================================================
# HỆ THỐNG HIỆU ỨNG VŨ KHÍ TẦM XA
# ==============================================================================
func _shoot() -> void:
	var w: Dictionary = weapon
	var base_dmg = int(w["damage"])
	var mult = rarity_data["mult"]
	# ÁP DỤNG KỸ NĂNG: Cộng % sát thương (mastery)
	mult += Global.upgrades["mastery"] * 0.05
	# ÁP DỤNG BUFF: Sức Mạnh / Đà Chiến Đấu / Cuồng Nộ
	mult += 0.08 * float(Global.buff_stack("buff_dmg"))
	if Global.buff_stack("buff_momentum") > 0:
		mult += MOMENTUM_PER_STACK * float(momentum_stacks)
	if Global.buff_stack("buff_berserk") > 0 and max_hp > 0:
		mult += 0.4 * (1.0 - float(hp) / float(max_hp))
	# Buff "Tập Trung": đứng yên đủ lâu -> tăng sát thương
	if Global.buff_stack("buff_focus") > 0 and still_time >= 0.6:
		mult += 0.2 * float(Global.buff_stack("buff_focus"))
	var dmg = int(base_dmg * mult)

	var pellets: int = w["pellets"]
	var spread: float = w["spread"]
	var speed: float = w["speed"]
	var cd: float = w["cooldown"]
	var life: float = w["life"]
	var is_pierce: bool = w["pierce"]
	var w_knock: float = w["recoil"]
	var eff: String = ""
	var p_color: Color = w["color"]
	var is_crit: bool = false

	# LOGIC ĐỘ HIẾM TẦM XA CHUYÊN SÂU
	if weapon_id == "pistol":
		if weapon_rarity == "rare": cd *= 0.85
		elif weapon_rarity == "epic": is_pierce = true
		elif weapon_rarity == "legendary":
			pellets = 3; spread = 15.0; dmg = base_dmg * 2
	elif weapon_id == "shotgun":
		if weapon_rarity == "rare": pellets = 7; life *= 1.15
		elif weapon_rarity == "epic": w_knock *= 2.0
		elif weapon_rarity == "legendary": eff = "explode"; pellets = 10; p_color = Color(1.0, 0.3, 0.1)
	elif weapon_id == "laser":
		if weapon_rarity == "rare": cd *= 0.7; dmg = int(base_dmg * 1.3)
		elif weapon_rarity == "epic": eff = "slow"
		elif weapon_rarity == "legendary": eff = "chain"; p_color = Color.RED; dmg = base_dmg * 2

	# ÁP DỤNG BUFF: Nhanh Nhẹn / Chí Mạng / Tầm Đánh (tầm xa = bay xa+nhanh hơn) / Vung Kiếm Càn Quét (tầm xa = xuyên)
	cd *= pow(0.9, float(Global.buff_stack("buff_haste")))
	if randf() < 0.08 * float(Global.buff_stack("buff_crit")):
		is_crit = true
	if Global.buff_stack("buff_reach") > 0:
		life *= 1.0 + 0.15 * float(Global.buff_stack("buff_reach"))
		speed *= 1.0 + 0.08 * float(Global.buff_stack("buff_reach"))
	if Global.buff_stack("buff_sweep") > 0:
		is_pierce = true
	if is_crit: dmg *= 2

	# Siêu Đạn / Loạt Đạn Vòng: đếm phát bắn
	shot_count += 1
	var is_super: bool = Global.buff_stack("buff_super") > 0 and shot_count % 6 == 0
	var do_ring: bool = Global.buff_stack("buff_ring") > 0 and shot_count % 5 == 0
	var bullet_radius: float = float(w["radius"])
	if is_super:
		dmg *= 3
		is_pierce = true
		bullet_radius *= 2.0
		p_color = Color(1.0, 0.85, 0.2)

	PlayerProfiler.record_attack(false) # AI Tầng 1: ghi nhận lối chơi tầm xa
	fire_timer.start(cd)
	spread = deg_to_rad(spread)
	var base_ang: float = aim_dir.angle()
	
	for i in pellets:
		var off: float = 0.0
		if pellets > 1:
			off = lerpf(-spread * 0.5, spread * 0.5, float(i) / float(pellets - 1))
			off += randf_range(-spread, spread) * 0.08
		var dir: Vector2 = Vector2.from_angle(base_ang + off)
		var b = BULLET.instantiate()
		b.setup(true, dir, dmg, speed, life, p_color, bullet_radius, is_pierce, eff)
		_apply_ranged_buffs(b)
		b.is_crit = is_crit
		Global.world.add_child(b)
		b.global_position = global_position + aim_dir * 24.0

	if do_ring:
		for k in 8:
			var rb = BULLET.instantiate()
			rb.setup(true, Vector2.from_angle(TAU * float(k) / 8.0), maxi(1, int(float(dmg) * 0.5)), speed * 0.8, life * 0.8, Color(0.6, 0.9, 1.0), 5.0)
			# Synergy Loạt Đạn Vòng + Tầm Nhiệt / Đạn Nảy: bung ra 0.12s rồi mới chụm vào quái
			if Global.buff_stack("buff_homing") > 0:
				rb.homing = true
				rb.homing_delay = RING_HOMING_DELAY
			rb.bounces_left = Global.buff_stack("buff_bounce")
			Global.world.add_child(rb)
			rb.global_position = global_position
		
	knockback -= aim_dir * w_knock
	Global.sfx(w["sfx"])
	Global.burst(global_position + aim_dir * 28.0, p_color, 4, 90.0, 1.0)
	Global.shake(0.10 if pellets > 1 else 0.04, 0.1)
	if Global.buff_stack("buff_momentum") > 0:
		momentum_stacks = mini(momentum_stacks + 1, MOMENTUM_MAX_STACKS)
		momentum_timer = MOMENTUM_WINDOW

# ==============================================================================
# HỆ THỐNG HIỆU ỨNG CẬN CHIẾN & CHÉM ĐẠN
# ==============================================================================
func _swing() -> void:
	var w: Dictionary = weapon
	var base_dmg = int(w["damage"])
	var mult = rarity_data["mult"]
	# ÁP DỤNG KỸ NĂNG: Cộng % sát thương (mastery)
	mult += Global.upgrades["mastery"] * 0.05
	# ÁP DỤNG BUFF: Sức Mạnh / Đà Chiến Đấu / Cuồng Nộ
	mult += 0.08 * float(Global.buff_stack("buff_dmg"))
	if Global.buff_stack("buff_momentum") > 0:
		mult += MOMENTUM_PER_STACK * float(momentum_stacks)
	if Global.buff_stack("buff_berserk") > 0 and max_hp > 0:
		mult += 0.4 * (1.0 - float(hp) / float(max_hp))
	var dmg = int(base_dmg * mult)

	var cd = float(w["cooldown"])
	var aoe_range = float(w["range"])
	var aoe_angle = float(w["cleave_angle"])
	var knock = float(w["knock"])
	var lifesteal = rarity_data["lifesteal"] # Hút máu từ Gacha
	lifesteal *= Global.MELEE_LIFESTEAL_MULT # cận chiến hút máu yếu hơn tầm xa

	var is_crit = false
	var apply_bleed = false
	var apply_stun = false
	var stun_duration = 0.0
	
	# LOGIC ĐỘ HIẾM CẬN CHIẾN CHUYÊN SÂU
	if weapon_id == "broadsword":
		if weapon_rarity == "rare": aoe_range *= 1.2
		elif weapon_rarity == "legendary": aoe_angle = 300.0; dmg = base_dmg * 2
	elif weapon_id == "daggers":
		if weapon_rarity == "rare": cd *= 0.75; if randf() < 0.2: is_crit = true
		elif weapon_rarity == "epic":
			dagger_combo += 1; dagger_timer = 1.0
			if dagger_combo >= 4: apply_bleed = true; dagger_combo = 0; Global.sfx("hit")
		elif weapon_rarity == "legendary":
			cd *= 0.4; if randf() < 0.5: is_crit = true
	elif weapon_id == "hammer":
		if weapon_rarity == "rare": aoe_range *= 1.25; knock *= 1.5
		elif weapon_rarity == "epic": apply_stun = true; stun_duration = 1.0
		elif weapon_rarity == "legendary": apply_stun = true; stun_duration = 1.5; aoe_range *= 1.5

	# ÁP DỤNG BUFF: Nhanh Nhẹn / Chí Mạng / Tầm Đánh / Vung Kiếm Càn Quét
	cd *= pow(0.9, float(Global.buff_stack("buff_haste")))
	if randf() < 0.08 * float(Global.buff_stack("buff_crit")):
		is_crit = true
	if Global.buff_stack("buff_reach") > 0:
		aoe_range *= 1.0 + 0.15 * float(Global.buff_stack("buff_reach"))
	if Global.buff_stack("buff_sweep") > 0:
		aoe_range *= 1.5
		aoe_angle += 40.0

	if is_crit: dmg *= 2

	# Phản Công: sau khi bị đánh, đòn chém kế tiếp x2 sát thương
	if Global.buff_stack("buff_counter") > 0 and counter_timer > 0.0:
		dmg *= 2
		counter_timer = 0.0
		Global.float_text(global_position + Vector2(0, -36), "COUNTER", Color(1.0, 0.6, 0.2), 18)
	# Lốc Xoáy: mỗi đòn thứ 4 chém vòng 360 độ
	swing_count += 1
	var is_whirl: bool = Global.buff_stack("buff_whirl") > 0 and swing_count % 4 == 0
	if is_whirl:
		aoe_angle = 360.0
		aoe_range *= 1.15

	# Lưu lại tầm/góc THẬT (đã cộng buff + độ hiếm) để _draw()/_update_weapon_visual()
	# vẽ đúng vệt chém khớp vùng gây sát thương — xem khai báo display_swing_range/half_angle.
	display_swing_range = aoe_range
	display_swing_half_angle = deg_to_rad(aoe_angle) * 0.5

	PlayerProfiler.record_attack(true) # AI Tầng 1: ghi nhận lối chơi cận chiến
	fire_timer.start(cd)
	swinging = true
	swing_progress = 0.0
	var tw = create_tween()
	tw.tween_property(self, "swing_progress", 1.0, cd * 0.4)
	tw.tween_callback(func(): swinging = false)
	
	Global.sfx(w["sfx"])
	Global.shake(0.15, 0.1)
	knockback += aim_dir * 120.0 
	
	var hit_something = false
	var total_heal = 0
	var rad_angle = deg_to_rad(aoe_angle)
	
	# CƠ CHẾ DAO GĂM: CHÉM XÓA ĐẠN QUÁI (chỉ Dao Găm)
	if weapon_id == "daggers":
		for b in get_tree().get_nodes_in_group("enemy_bullets"):
			var to_b = b.global_position - global_position
			if to_b.length() <= aoe_range + 10.0:
				if absf(aim_dir.angle_to(to_b)) <= rad_angle * 0.5:
					Global.burst(b.global_position, Color.WHITE, 4, 60.0, 0.6)
					b.queue_free() # Xóa đạn!
					Global.sfx("dodge")
					
	# CHÉM QUÁI VÀ BOSS
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("kill") and e.alive:
			var e_center = e.hurt_center() if e.has_method("hurt_center") else e.global_position
			var to_e = e_center - global_position
			if to_e.length() <= aoe_range + float(e.data["radius"]):
				if absf(aim_dir.angle_to(to_e)) <= rad_angle * 0.5:
					e.take_damage(dmg, global_position, knock)
					Global.on_player_hit(e, dmg, is_crit)
					hit_something = true
					Global.burst(e_center, Color(1.0, 0.95, 0.7), 5, 150.0, 1.2) # tia lửa chỗ trúng
					if apply_bleed and e.has_method("apply_status"): e.apply_status("bleed", 0.0)
					if apply_stun and e.has_method("apply_status"): e.apply_status("stun", stun_duration)
					if lifesteal > 0.0: total_heal += maxi(1, int(float(dmg) * lifesteal))
					# ÁP DỤNG BUFF: Phá Giáp / Lưỡi Rỉ Máu / Đạn Băng
					if Global.buff_stack("buff_sunder") > 0 and e.has_method("apply_sunder"): e.apply_sunder()
					if e.has_method("apply_status"):
						if randf() < minf(0.6, 0.15 * float(Global.buff_stack("buff_bleed_proc"))): e.apply_status("bleed", 0.0)
						if randf() < minf(0.6, 0.20 * float(Global.buff_stack("buff_slow_proc"))): e.apply_status("slow", 1.5)
					if weapon_id == "hammer" and weapon_rarity == "legendary":
						e.take_damage(20, global_position, 0.0, true) # Lava phụ trợ
						
	for b in get_tree().get_nodes_in_group("boss"):
		if b.has_method("take_damage") and b.alive:
			var b_center = b.hurt_center() if b.has_method("hurt_center") else b.global_position
			var to_b = b_center - global_position
			if to_b.length() <= aoe_range + 34.0:
				if absf(aim_dir.angle_to(to_b)) <= rad_angle * 0.5:
					b.take_damage(dmg, global_position, knock)
					Global.on_player_hit(b, dmg, is_crit)
					hit_something = true
					Global.burst(b_center, Color(1.0, 0.95, 0.7), 5, 150.0, 1.2) # tia lửa chỗ trúng
					if lifesteal > 0.0: total_heal += maxi(1, int(float(dmg) * lifesteal * 0.5))
					if Global.buff_stack("buff_sunder") > 0 and b.has_method("apply_sunder"): b.apply_sunder()

	# Buff Kiếm Khí: mỗi đòn chém phóng thêm luồng kiếm khí xuyên
	if Global.buff_stack("buff_wave") > 0:
		# Synergy Lốc Xoáy + Kiếm Khí: nhát 360° phóng 6 luồng tỏa đều thay vì 1 luồng phía trước
		var wave_dirs: Array = [aim_dir]
		if is_whirl:
			wave_dirs.clear()
			for k in WHIRL_WAVE_COUNT:
				wave_dirs.append(aim_dir.rotated(TAU * float(k) / float(WHIRL_WAVE_COUNT)))
		for wd in wave_dirs:
			var wb = BULLET.instantiate()
			wb.setup(true, wd, maxi(1, int(float(dmg) * 0.35 * float(Global.buff_stack("buff_wave")))), 480.0, 0.4, Color(0.7, 0.9, 1.0), 9.0, true)
			wb.is_crit = is_crit
			Global.world.add_child(wb)
			wb.global_position = global_position + wd * 25.0

	# Kiếm Dài Sử Thi: Phóng Kiếm Khí
	if weapon_id == "broadsword" and (weapon_rarity == "epic" or weapon_rarity == "legendary"):
		var b = BULLET.instantiate()
		b.setup(true, aim_dir, dmg/2, 450.0, 0.35, w["color"], 10.0, true)
		Global.world.add_child(b)
		b.global_position = global_position + aim_dir * 25.0

	if hit_something: Global.hitstop(0.04)
	if total_heal > 0: heal(total_heal)
	if Global.buff_stack("buff_momentum") > 0:
		momentum_stacks = mini(momentum_stacks + 1, MOMENTUM_MAX_STACKS)
		momentum_timer = MOMENTUM_WINDOW

# ==============================================================================
# HỆ THỐNG TIỆN ÍCH
# ==============================================================================
func set_weapon_with_rarity(id: String, rarity: String) -> void:
	weapon_id = id
	weapon_rarity = rarity
	weapon = Global.weapons[id]
	rarity_data = Global.rarities[rarity]
	weapon_sprite.texture = Global.load_tex("res://assets/dungeon/weapon_%s.png" % id)
	var display_name = weapon["name"] + " (" + rarity_data["name"] + ")"
	Global.message.emit("Picked up: " + display_name, rarity_data["color"])

func _tick_buff_timers(delta: float) -> void:
	_tick_arc(delta)
	shield_nova_cd = maxf(0.0, shield_nova_cd - delta)
	counter_timer = maxf(0.0, counter_timer - delta)
	if velocity.length() < 5.0 and not rolling:
		still_time += delta
	else:
		still_time = 0.0

## Buff Sét Lan: mỗi ARC_INTERVAL giây đánh tối đa 3 quái gần nhất trong 220px.
func _tick_arc(delta: float) -> void:
	if Global.buff_stack("buff_arc") <= 0:
		return
	arc_timer -= delta
	if arc_timer > 0.0:
		return
	_arc_strike()

## Một nhịp Sét Lan (đánh tối đa 3 quái gần nhất trong 220px). Trả về true nếu có mục tiêu.
## Giáp Phản Chấn cũng gọi hàm này để phóng sét ngay khi giáp vỡ.
func _arc_strike() -> bool:
	var cands: Array = []
	for e in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("boss"):
		if is_instance_valid(e) and e.alive and e.get("active") != false and e.global_position.distance_to(global_position) <= 220.0:
			cands.append(e)
	if cands.is_empty():
		arc_timer = 0.3 # chưa có mục tiêu: thử lại sớm
		return false
	arc_timer = ARC_INTERVAL
	cands.sort_custom(func(a, b): return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position))
	var dmg: int = maxi(6, int(float(weapon["damage"]) * rarity_data["mult"] * 0.8 * _secondary_dmg_mult()))
	for i in mini(3, cands.size()):
		cands[i].take_damage(dmg, global_position, 100.0)
		Global.on_secondary_hit(cands[i], dmg, false)
		Global.burst(cands[i].global_position, Color(1.0, 0.95, 0.3), 6, 140.0, 1.2)
	Global.shake(0.1, 0.08)
	return true

## Buff Thực Khách Hầm Ngục: dọn sạch phòng hồi % máu tối đa.
func _on_room_cleared() -> void:
	var stacks: int = Global.buff_stack("buff_gourmand")
	if stacks > 0 and alive:
		heal(maxi(1, int(float(max_hp) * 0.08 * float(stacks))))

## Giáp tối đa tăng theo tầng + buff Lá Chắn Lớn; gọi lại khi sang tầng mới.
func refresh_max_shield() -> void:
	var new_max: int = SHIELD_BASE + SHIELD_PER_FLOOR * maxi(0, Global.floor_num - 1) + 10 * Global.buff_stack("buff_shield_cap")
	shield += float(new_max - max_shield) if new_max > max_shield else 0.0
	max_shield = new_max
	shield = minf(shield, float(max_shield))

func _tick_shield(delta: float) -> void:
	if shield_delay_timer > 0.0:
		shield_delay_timer = maxf(0.0, shield_delay_timer - delta)
	elif shield < float(max_shield):
		shield = minf(float(max_shield), shield + SHIELD_REGEN_RATE * (1.0 + 0.25 * float(Global.buff_stack("buff_shield_regen"))) * delta)

## Buff Fortify: mỗi đòn của Player trúng quái/boss cộng FORTIFY_SHIELD_PER_HIT giáp ảo (không vượt max_shield).
## Nghe signal Global.player_hit_landed; hồi chiêu đo bằng đồng hồ hệ thống nên không cần tick mỗi frame.
func _on_hit_landed_fortify(_target: Node, _dmg: int, _is_crit: bool) -> void:
	if not alive or Global.buff_stack("buff_fortify") <= 0 or shield >= float(max_shield):
		return
	var now: int = Time.get_ticks_msec()
	if now < _fortify_ready_msec:
		return
	_fortify_ready_msec = now + int(FORTIFY_COOLDOWN * 1000.0)
	shield = minf(float(max_shield), shield + FORTIFY_SHIELD_PER_HIT)

## Trả về lượng sát thương còn lại sau khi giáp hấp thụ. Luôn reset nhịp hồi giáp.
func _absorb_with_shield(amount: int) -> int:
	shield_delay_timer = maxf(1.0, SHIELD_REGEN_DELAY - 0.4 * float(Global.buff_stack("buff_shield_regen")))
	if shield <= 0.0:
		return amount
	var absorbed: int = mini(amount, int(ceil(shield)))
	shield = maxf(0.0, shield - float(absorbed))
	if shield <= 0.0:
		_on_shield_broken()
	return amount - absorbed

## Buff Giáp Phản Chấn: giáp vỡ -> xung chấn quanh Player (có hồi chiêu).
func _on_shield_broken() -> void:
	if Global.buff_stack("buff_shield_nova") <= 0 or shield_nova_cd > 0.0:
		return
	shield_nova_cd = 6.0
	var dmg: int = int(float(25 + 3 * Global.floor_num) * _secondary_dmg_mult())
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.alive and e.global_position.distance_to(global_position) <= 140.0:
			e.take_damage(dmg, global_position, 450.0)
			Global.on_secondary_hit(e, dmg, false)
			# Synergy Giáp Phản Chấn + Băng Giá: xung chấn đóng băng mọi quái trúng
			var freeze_lv: int = Global.buff_stack("buff_freeze")
			if freeze_lv > 0 and e.alive and e.has_method("apply_element"):
				var need: int = 3 if freeze_lv < 2 else 2
				for k in need:
					e.apply_element("frost", 0, need)
	for b in get_tree().get_nodes_in_group("boss"):
		if is_instance_valid(b) and b.alive and b.global_position.distance_to(global_position) <= 160.0:
			b.take_damage(dmg, global_position, 0.0)
			Global.on_secondary_hit(b, dmg, false)
	for eb in get_tree().get_nodes_in_group("enemy_bullets"):
		if is_instance_valid(eb) and eb.global_position.distance_to(global_position) <= 160.0:
			eb.queue_free()
	Global.burst(global_position, Color(0.55, 0.75, 1.0), 30, 320.0, 2.0)
	Global.shake(0.4, 0.2)
	# Synergy Giáp Phản Chấn + Sét Lan: phóng ngay một nhịp sét, không chờ timer 2.5s
	if Global.buff_stack("buff_arc") > 0:
		_arc_strike()

func take_damage(amount: int, from_pos: Vector2 = Vector2.ZERO, knock: float = 300.0, ignore_invuln: bool = false, bypass_shield: bool = false) -> void:
	if not alive: return
	if not ignore_invuln and is_invulnerable(): return
	# Hệ số sát thương quái/boss/bẫy theo tầng (xem Global.enemy_dmg_mult_for_floor) —
	# chặn điểm chung duy nhất mà MỌI nguồn sát thương từ môi trường đổ vào Player.
	amount = maxi(1, int(float(amount) * Global.enemy_dmg_mult_for_floor(Global.floor_num)))
	counter_timer = 3.0 # Phản Công: bị đánh trúng mở cửa sổ x2 sát thương
	Global.player_damaged.emit(amount, max_hp) # HUD nghe: nháy viền đỏ khi đòn nặng
	if max_hp > 0 and float(amount) >= HEAVY_HIT_RATIO * float(max_hp):
		Global.shake(0.9, 0.35)
		Global.hitstop(0.05)
	var hp_damage: int = amount if bypass_shield else _absorb_with_shield(amount)
	hp = maxi(hp - hp_damage, 0)
	if not ignore_invuln:
		hurt_timer.start()
	knockback += (global_position - from_pos).normalized() * knock
	Global.shake(0.5, 0.25)
	Global.sfx("hurt")
	Global.burst(global_position, Color(1.0, 0.3, 0.3), 12, 180.0, 1.5)
	Global.float_text(global_position, str(amount), Color(1.0, 0.4, 0.4), 20)
	modulate = Color(2.5, 1.2, 1.2)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.2)
	if hp <= 0:
		# Nếu có kỹ năng Phượng Hoàng Lửa (>0) và chưa dùng lần nào
		if Global.upgrades.has("revive") and Global.upgrades["revive"] > 0 and not has_revived:
			_trigger_revive()
		else:
			_die()
func _trigger_revive() -> void:
	has_revived = true
	hp = int(float(max_hp) * 0.5) # Hồi 50% Máu tối đa
	
	# Kích hoạt BẤT TỬ trong 2 giây để tránh bị quái đấm bồi chết luôn
	hurt_timer.start(2.0)
	
	# Hiệu ứng nổ âm thanh và khựng màn hình
	Global.sfx("slam")
	Global.shake(1.0, 0.5)
	Global.hitstop(0.15)
	
	# Bùng nổ Hạt (Lửa đỏ cam văng tung tóe)
	Global.burst(global_position, Color(1.0, 0.4, 0.0), 60, 450.0, 3.0)
	Global.burst(global_position, Color(1.0, 0.8, 0.2), 30, 200.0, 2.0)
	
	# Chữ bay lên
	Global.float_text(global_position + Vector2(0, -40), "PHOENIX REBIRTH!", Color(1.0, 0.5, 0.1), 24)
	
	# Hiệu ứng chớp nháy liên tục báo hiệu đang trong khung hình bất tử (i-frames)
	var tw = create_tween().set_loops(10)
	tw.tween_property(self, "modulate:a", 0.2, 0.1)
	tw.tween_property(self, "modulate:a", 1.0, 0.1)

## Tâm hitbox thật (capsule Body) — dùng để tính trúng đòn/ngắm bắn chính xác,
## khác với global_position (gốc chân, dùng cho AI/di chuyển).
func hurt_center() -> Vector2:
	return $Body.global_position

func heal(amount: int) -> void:
	if hp >= max_hp: return
	hp = mini(hp + amount, max_hp)
	Global.float_text(global_position, "+%d" % amount, Color(0.4, 1.0, 0.5), 18)

func _die() -> void:
	alive = false
	Global.shake(1.0, 0.5)
	Global.burst(global_position, Color(0.4, 0.7, 1.0), 40, 300.0, 2.5)
	hide()
	died.emit()
	Global.player_died.emit()

## Nửa góc quạt chém hiện tại — dùng chung bởi _draw() (vệt chém) và
## _update_weapon_visual() (xoay icon) để khỏi lặp logic 2 nơi.
## Đọc display_swing_half_angle (đã cộng buff Tầm Đánh/Vung Kiếm Càn Quét + độ hiếm,
## set bởi _swing()) để vệt chém LUÔN khớp vùng gây sát thương thật — không đọc thẳng
## weapon["cleave_angle"] gốc nữa (bug cũ: vệt chém hiển thị nhỏ hơn tầm đánh thật).
func _melee_half_angle() -> float:
	if swinging and display_swing_half_angle > 0.0:
		return display_swing_half_angle
	var half_angle = deg_to_rad(float(weapon["cleave_angle"])) * 0.5
	if weapon_id == "broadsword" and weapon_rarity == "legendary": half_angle = deg_to_rad(300.0) * 0.5
	return half_angle

## Icon vũ khí thật (WeaponSprite, res://assets/dungeon/weapon_<id>.png) được xoay/lật
## theo hướng ngắm mỗi khung hình tại đây. Vẽ chếch phải lúc 0 độ nên chỉ cần rotation =
## góc ngắm; flip_v khi hướng ngả sang trái (cos < 0) để báng/chuôi không bị lộn ngược.
func _update_weapon_visual() -> void:
	if swinging and weapon.get("is_melee", false):
		_slash_ang = aim_dir.angle()
		_slash_fade = SLASH_FADE_TIME
	elif _slash_fade > 0.0:
		_slash_fade = maxf(0.0, _slash_fade - get_physics_process_delta_time())
	var ang: float = aim_dir.angle()
	if weapon.get("is_melee", false) and swinging:
		var half_angle = _melee_half_angle()
		var start_ang = aim_dir.angle() - half_angle
		var end_ang = aim_dir.angle() + half_angle
		ang = lerp(start_ang, end_ang, swing_progress)
	weapon_sprite.rotation = ang
	weapon_sprite.flip_v = cos(ang) < 0.0
	var offset: float = 14.0 if weapon.get("is_melee", false) else 17.0
	weapon_sprite.position = Vector2.from_angle(ang) * offset

func _draw() -> void:
	if weapon.get("is_melee", false) and (swinging or _slash_fade > 0.0):
		var gun_c: Color = weapon.get("color", Color.WHITE)
		if rarity_data.has("color"): gun_c = rarity_data["color"].lerp(gun_c, 0.5)
		var r = display_swing_range if display_swing_range > 0.0 else float(weapon["range"])
		var half_angle: float = _melee_half_angle() if swinging else display_swing_half_angle
		var center_ang: float = aim_dir.angle() if swinging else _slash_ang
		var progress: float = swing_progress if swinging else 1.0
		var alpha: float = 1.0 if swinging else clampf(_slash_fade / SLASH_FADE_TIME, 0.0, 1.0)
		_draw_slash(r, center_ang, half_angle, progress, gun_c, alpha)

## Vệt chém hình lưỡi liềm: đuôi mảnh + mờ, đầu dày + sáng, quét theo tiến độ vung. Tầm ngoài đúng
## bằng tầm gây sát thương (display_swing_range) nên vệt luôn khớp vùng trúng thật.
func _draw_slash(r: float, center_ang: float, half_angle: float, progress: float, col: Color, alpha: float) -> void:
	var start_ang: float = center_ang - half_angle
	var span: float = half_angle * 2.0 * clampf(progress, 0.0, 1.0)
	if span < 0.05 or r <= 1.0:
		return
	var steps: int = clampi(int(span / 0.1) + 2, 6, 40)
	var max_thick: float = clampf(r * 0.5, 10.0, 30.0)
	for layer in 2: # 0 = quầng sáng ngoài, 1 = vệt chính
		var grow: float = 1.35 if layer == 0 else 1.0
		var outer_extra: float = 3.0 if layer == 0 else 0.0
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		var inner_pts: Array = []
		var inner_cols: Array = []
		for i in steps + 1:
			var u: float = float(i) / float(steps)
			var ang: float = start_ang + span * u
			var thick: float = max_thick * grow * pow(u, 0.9)
			var a_u: float = pow(u, 1.4) * alpha
			var dir: Vector2 = Vector2.from_angle(ang)
			var base_a: float = 0.22 if layer == 0 else 0.6
			pts.append(dir * (r + outer_extra))
			cols.append(Color(col.lerp(Color.WHITE, 0.35 * u), base_a * a_u))
			inner_pts.append(dir * maxf(2.0, r - thick))
			inner_cols.append(Color(col, 0.04 * a_u))
		for i in range(steps, -1, -1):
			pts.append(inner_pts[i])
			cols.append(inner_cols[i])
		draw_polygon(pts, cols)
	# lõi sáng mảnh dọc mép ngoài + vạch sáng ở đầu lưỡi
	var core := PackedVector2Array()
	var core_cols := PackedColorArray()
	for i in steps + 1:
		var u2: float = float(i) / float(steps)
		core.append(Vector2.from_angle(start_ang + span * u2) * (r - 1.0))
		core_cols.append(Color(1.0, 1.0, 1.0, 0.85 * pow(u2, 1.6) * alpha))
	draw_polyline_colors(core, core_cols, 2.0)
	var head: Vector2 = Vector2.from_angle(start_ang + span)
	draw_line(head * maxf(2.0, r - max_thick), head * (r + 2.0), Color(1.0, 1.0, 1.0, 0.9 * alpha), 2.5)
