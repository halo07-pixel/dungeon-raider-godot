extends CharacterBody2D
## Player: Tích hợp bảng hiệu ứng Sử thi/Huyền thoại chi tiết, Combo Dao Găm & Chém Đạn.

signal died

const BULLET = preload("res://scenes/bullet.tscn")
const SPEED: float = 230.0
const ROLL_SPEED: float = 560.0
const KNOCK_DECAY: float = 1400.0
var has_revived: bool = false
var max_hp: int = 100
var hp: int = 100
var weapon_id: String = "pistol"
var weapon_rarity: String = "common"
var rarity_data: Dictionary = {}
var weapon: Dictionary = {}
var alive: bool = true
var rolling: bool = false
var roll_dir: Vector2 = Vector2.RIGHT
var aim_dir: Vector2 = Vector2.RIGHT
var knockback: Vector2 = Vector2.ZERO

var swinging: bool = false
var swing_progress: float = 0.0
var dagger_combo: int = 0
var dagger_timer: float = 0.0

@onready var fire_timer: Timer = $FireTimer
@onready var dodge_timer: Timer = $DodgeTimer
@onready var dodge_cooldown: Timer = $DodgeCooldown
@onready var hurt_timer: Timer = $HurtTimer
@onready var sprite: AnimatedSprite2D = $Sprite

## Ánh xạ lớp nhân vật -> bộ sprite 0x72 (DungeonTilesetII) dùng làm thân người.
const SPRITE_SET: Dictionary = {
	"ranger": "elf_m",
	"brawler": "knight_m",
}
const SPRITE_SCALE: float = 2.0
const SPRITE_OFFSET_Y: float = -20.0

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("player")
	Global.player = self

	var cls: Dictionary = Global.classes[Global.current_class]

	# ÁP DỤNG KỸ NĂNG: Tăng HP tối đa
	max_hp = cls["max_hp"] + (Global.upgrades["hp_boost"] * 10)
	hp = max_hp

	set_weapon_with_rarity(cls["default_weapon"], "common")
	dodge_timer.timeout.connect(_on_dodge_finished)

	sprite.sprite_frames = _build_sprite_frames()
	sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	sprite.offset = Vector2(0.0, SPRITE_OFFSET_Y)
	sprite.play("idle")


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
		var img := Image.new()
		if img.load(path) != OK:
			push_error("Không tải được sprite người chơi: " + path)
			continue
		frames.add_frame(anim, ImageTexture.create_from_image(img))


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

func _physics_process(delta: float) -> void:
	if not alive: return
	
	if dagger_timer > 0:
		dagger_timer -= delta
		if dagger_timer <= 0: dagger_combo = 0 # Trôi combo dao găm
		
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	aim_dir = (get_global_mouse_position() - global_position).normalized()
	if aim_dir == Vector2.ZERO: aim_dir = Vector2.RIGHT

	if Input.is_action_just_pressed("dodge") and not rolling and dodge_cooldown.is_stopped():
		_start_roll(input_dir if input_dir != Vector2.ZERO else aim_dir)

	if rolling: velocity = roll_dir * ROLL_SPEED
	else: velocity = input_dir * SPEED
	
	velocity += knockback
	knockback = knockback.move_toward(Vector2.ZERO, KNOCK_DECAY * delta)
	move_and_slide()

	if Input.is_action_pressed("shoot") and not rolling and fire_timer.is_stopped() and not swinging:
		if weapon.get("is_melee", false): _swing()
		else: _shoot()
	_update_sprite()
	queue_redraw()

func _start_roll(dir: Vector2) -> void:
	rolling = true
	roll_dir = dir.normalized()
	dodge_timer.start()      
	dodge_cooldown.start()   
	Global.sfx("dodge")
	Global.burst(global_position, Color(0.6, 0.8, 1.0), 6, 80.0, 1.0)

func _on_dodge_finished() -> void:
	rolling = false

# ==============================================================================
# HỆ THỐNG HIỆU ỨNG VŨ KHÍ TẦM XA
# ==============================================================================
func _shoot() -> void:
	var w: Dictionary = weapon
	var base_dmg = int(w["damage"])
	var mult = rarity_data["mult"]
	# ÁP DỤNG KỸ NĂNG: Cộng % sát thương (mastery)
	mult += Global.upgrades["mastery"] * 0.05
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
		b.setup(true, dir, dmg, speed, life, p_color, float(w["radius"]), is_pierce, eff)
		Global.world.add_child(b)
		b.global_position = global_position + aim_dir * 24.0
		
	knockback -= aim_dir * w_knock
	Global.sfx(w["sfx"])
	Global.burst(global_position + aim_dir * 28.0, p_color, 4, 90.0, 1.0)
	Global.shake(0.10 if pellets > 1 else 0.04, 0.1)

# ==============================================================================
# HỆ THỐNG HIỆU ỨNG CẬN CHIẾN & CHÉM ĐẠN
# ==============================================================================
func _swing() -> void:
	var w: Dictionary = weapon
	var base_dmg = int(w["damage"])
	var mult = rarity_data["mult"]
	# ÁP DỤNG KỸ NĂNG: Cộng % sát thương (mastery)
	mult += Global.upgrades["mastery"] * 0.05
	var dmg = int(base_dmg * mult)
	
	var cd = float(w["cooldown"])
	var aoe_range = float(w["range"])
	var aoe_angle = float(w["cleave_angle"])
	var knock = float(w["knock"])
	var lifesteal = rarity_data["lifesteal"] # Hút máu từ Gacha
	
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
	
	if is_crit: dmg *= 2
	
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
	
	# CƠ CHẾ DAO GĂM: CHÉM XÓA ĐẠN QUÁI
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
			var to_e = e.global_position - global_position
			if to_e.length() <= aoe_range + float(e.data["radius"]):
				if absf(aim_dir.angle_to(to_e)) <= rad_angle * 0.5:
					e.take_damage(dmg, global_position, knock)
					hit_something = true
					if apply_bleed and e.has_method("apply_status"): e.apply_status("bleed", 0.0)
					if apply_stun and e.has_method("apply_status"): e.apply_status("stun", stun_duration)
					if lifesteal > 0.0: total_heal += maxi(1, int(float(dmg) * lifesteal))
					if weapon_id == "hammer" and weapon_rarity == "legendary":
						e.take_damage(20, global_position, 0.0, true) # Lava phụ trợ
						
	for b in get_tree().get_nodes_in_group("boss"):
		if b.has_method("take_damage") and b.alive:
			var to_b = b.global_position - global_position
			if to_b.length() <= aoe_range + 34.0:
				if absf(aim_dir.angle_to(to_b)) <= rad_angle * 0.5:
					b.take_damage(dmg, global_position, knock)
					hit_something = true
					if lifesteal > 0.0: total_heal += maxi(1, int(float(dmg) * lifesteal * 0.5))

	# Kiếm Dài Sử Thi: Phóng Kiếm Khí
	if weapon_id == "broadsword" and (weapon_rarity == "epic" or weapon_rarity == "legendary"):
		var b = BULLET.instantiate()
		b.setup(true, aim_dir, dmg/2, 450.0, 0.35, w["color"], 10.0, true)
		Global.world.add_child(b)
		b.global_position = global_position + aim_dir * 25.0

	if hit_something: Global.hitstop(0.04)
	if total_heal > 0: heal(total_heal)

# ==============================================================================
# HỆ THỐNG TIỆN ÍCH
# ==============================================================================
func set_weapon_with_rarity(id: String, rarity: String) -> void:
	weapon_id = id
	weapon_rarity = rarity
	weapon = Global.weapons[id]
	rarity_data = Global.rarities[rarity]
	var display_name = weapon["name"] + " (" + rarity_data["name"] + ")"
	Global.message.emit("Picked up: " + display_name, rarity_data["color"])

func take_damage(amount: int, from_pos: Vector2 = Vector2.ZERO, knock: float = 300.0) -> void:
	if not alive or is_invulnerable(): return
	hp = maxi(hp - amount, 0)
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

func _draw() -> void:
	var gun_c: Color = weapon.get("color", Color.WHITE)
	if rarity_data.has("color"): gun_c = rarity_data["color"].lerp(gun_c, 0.5)

	if weapon.get("is_melee", false):
		if swinging:
			var r = float(weapon["range"])
			var half_angle = deg_to_rad(float(weapon["cleave_angle"])) * 0.5
			if weapon_id == "broadsword" and weapon_rarity == "legendary": half_angle = deg_to_rad(300.0) * 0.5
			var start_ang = aim_dir.angle() - half_angle
			var end_ang = aim_dir.angle() + half_angle
			var cur_ang = lerp(start_ang, end_ang, swing_progress)
			
			draw_arc(Vector2.ZERO, r, start_ang, end_ang, 16, Color(gun_c, 0.25), 16.0)
			draw_line(Vector2.ZERO, Vector2.from_angle(cur_ang) * r, gun_c, 6.0)
		else:
			draw_line(aim_dir * 10.0, aim_dir * 18.0, gun_c, 4.0)
	else:
		draw_line(aim_dir * 8.0, aim_dir * 26.0, gun_c, 6.0)
