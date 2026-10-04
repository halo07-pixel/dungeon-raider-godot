extends CharacterBody2D
## Kẻ địch: Tích hợp hệ thống Trạng thái (Choáng, Chậm, Chảy máu) từ vũ khí Sử thi/Huyền thoại.

signal died(enemy)

const PICKUP = preload("res://scenes/pickup.tscn")
const BULLET = preload("res://scenes/bullet.tscn")

var kind: String = "slime"
var data: Dictionary = {}
var max_hp: float = 30.0
var hp: float = 30.0
var alive: bool = true
var active: bool = false
var knockback: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT
var player_in_touch: bool = false
var player_too_close: bool = false
var player_in_range: bool = false
var has_los: bool = false
var strafe_sign: float = 1.0
var _t: float = 0.0
var armor: float = 0.0
var cc_resist: float = 0.0

# --- HỆ THỐNG TRẠNG THÁI ---
var stun_timer: float = 0.0
var slow_timer: float = 0.0
var bleed_ticks: int = 0
var bleed_timer: float = 0.0

@onready var hitbox: Area2D = $Hitbox
@onready var near_zone: Area2D = $NearZone
@onready var far_zone: Area2D = $FarZone
@onready var los: RayCast2D = $LOS
@onready var action_timer: Timer = $ActionTimer
@onready var spawn_timer: Timer = $SpawnTimer
@onready var sprite: AnimatedSprite2D = $Sprite

## Ánh xạ loại quái -> sprite 0x72 (DungeonTilesetII). "single_anim": true nghĩa là
## chỉ có 1 bộ khung hình dùng chung cho cả idle lẫn di chuyển (vd slug lúc nào cũng trườn).
const ENEMY_SPRITES: Dictionary = {
	"slime": {"prefix": "slug", "single_anim": true, "offset_y": -12.0},
	"archer": {"prefix": "imp", "single_anim": false, "offset_y": -10.0},
	"brute": {"prefix": "ogre", "single_anim": false, "offset_y": -22.0},
}

func setup(p_kind: String, hp_mult: float = 1.0) -> void:
	kind = p_kind
	data = Global.enemies[p_kind]
	var floor_scale: float = 1.0 + 0.15 * float(Global.floor_num - 1)
	max_hp = float(data["hp"]) * hp_mult * floor_scale
	hp = max_hp
	armor = floor((Global.floor_num - 1) * 1.2)
	cc_resist = minf(0.0 + (Global.floor_num - 1) * 0.15, 0.6)

func _ready() -> void:
	if data.is_empty():
		setup(kind)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("enemies")
	strafe_sign = 1.0 if randf() < 0.5 else -1.0
	var r: float = data["radius"]
	_set_circle($Body, r)
	_set_circle($Hitbox/Shape, r + 5.0)
	_set_circle($NearZone/Shape, float(data.get("keep_away", 1.0)))
	_set_circle($FarZone/Shape, float(data.get("range", 1.0)))
	hitbox.body_entered.connect(_on_hitbox_entered)
	hitbox.body_exited.connect(_on_hitbox_exited)
	near_zone.body_entered.connect(_on_near_entered)
	near_zone.body_exited.connect(_on_near_exited)
	far_zone.body_entered.connect(_on_far_entered)
	far_zone.body_exited.connect(_on_far_exited)
	action_timer.one_shot = (kind != "archer")
	action_timer.timeout.connect(_on_action_timer_timeout)
	spawn_timer.timeout.connect(_on_spawn_done)
	modulate.a = 0.35
	_setup_sprite()


func _setup_sprite() -> void:
	var cfg: Dictionary = ENEMY_SPRITES.get(kind, ENEMY_SPRITES["slime"])
	sprite.sprite_frames = _build_enemy_frames(cfg)
	sprite.scale = Vector2(2.0, 2.0)
	sprite.offset = Vector2(0.0, float(cfg["offset_y"]))
	sprite.play("idle")


func _build_enemy_frames(cfg: Dictionary) -> SpriteFrames:
	var frames := SpriteFrames.new()
	var prefix: String = cfg["prefix"]
	if cfg.get("single_anim", false):
		_add_enemy_anim(frames, prefix, "idle", "", 4, 5.0, true)
		_add_enemy_anim(frames, prefix, "run", "", 4, 8.0, true)
	else:
		_add_enemy_anim(frames, prefix, "idle", "idle", 4, 6.0, true)
		_add_enemy_anim(frames, prefix, "run", "run", 4, 10.0, true)
	return frames


func _add_enemy_anim(frames: SpriteFrames, prefix: String, anim_name: String, file_tag: String, count: int, fps: float, loop: bool) -> void:
	frames.add_animation(anim_name)
	frames.set_animation_speed(anim_name, fps)
	frames.set_animation_loop(anim_name, loop)
	for i in count:
		var path: String = ("res://assets/dungeon/%s_anim_f%d.png" % [prefix, i]) if file_tag == "" \
			else ("res://assets/dungeon/%s_%s_anim_f%d.png" % [prefix, file_tag, i])
		var img := Image.new()
		if img.load(path) != OK:
			push_error("Không tải được sprite quái: " + path)
			continue
		frames.add_frame(anim_name, ImageTexture.create_from_image(img))


func _update_sprite(moving: bool) -> void:
	if facing.x != 0.0:
		sprite.flip_h = facing.x < 0.0
	if stun_timer > 0.0:
		sprite.modulate = Color.YELLOW
	elif slow_timer > 0.0:
		sprite.modulate = Color.AQUA
	else:
		sprite.modulate = Color.WHITE
	var want_anim: String = "run" if moving else "idle"
	if sprite.animation != want_anim:
		sprite.play(want_anim)

func _set_circle(node: CollisionShape2D, radius: float) -> void:
	var s := CircleShape2D.new()
	s.radius = radius
	node.shape = s

func _on_hitbox_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_touch = true
		_touch_attack()

func _on_hitbox_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_touch = false

func _on_near_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_too_close = true
func _on_near_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player_too_close = false
func _on_far_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = true
func _on_far_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = false

func _on_spawn_done() -> void:
	active = true
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
	if kind == "archer":
		action_timer.start(float(data["shoot_cd"]))
	elif player_in_touch:
		_touch_attack()

func _on_action_timer_timeout() -> void:
	if not active or not alive or stun_timer > 0:
		return
	if kind == "archer":
		if player_in_range and has_los:
			_shoot()
	elif player_in_touch:
		_touch_attack()

func _touch_attack() -> void:
	if not active or not alive or not player_in_touch or stun_timer > 0:
		return
	if not action_timer.is_stopped():
		return
	var p = Global.player
	if not is_instance_valid(p) or not p.alive:
		return
	p.take_damage(int(data["touch"]), global_position, float(data["touch_knock"]))
	action_timer.start(float(data["touch_cd"]))

func _shoot() -> void:
	var p = Global.player
	if not is_instance_valid(p) or not p.alive:
		return
	var dir: Vector2 = (p.global_position - global_position).normalized()
	var b = BULLET.instantiate()
	b.setup(false, dir, int(data["bullet_damage"]), float(data["bullet_speed"]), 2.5, data["color"], 6.0)
	Global.world.add_child(b)
	b.global_position = global_position + dir * 18.0
	Global.sfx("enemy_shoot")

# --- HÀM NHẬN TRẠNG THÁI TỪ VŨ KHÍ ---
func apply_status(type: String, duration: float) -> void:
	if type == "stun":
		stun_timer = maxf(stun_timer, duration)
	elif type == "slow":
		slow_timer = maxf(slow_timer, duration)
	elif type == "bleed":
		bleed_ticks = 4 # Chảy máu 4 nhịp
		bleed_timer = 0.5 # Mỗi 0.5s giật 1 lần

func _physics_process(delta: float) -> void:
	if not alive:
		return
	_t += delta
	
	# Xử lý Chảy máu
	if bleed_ticks > 0:
		bleed_timer -= delta
		if bleed_timer <= 0:
			bleed_timer = 0.5
			bleed_ticks -= 1
			take_damage(5, global_position, 0.0, true) # True damage
			Global.burst(global_position, Color.DARK_RED, 3, 50.0, 1.0)
			
	# Xử lý Choáng (Stun)
	if stun_timer > 0:
		stun_timer -= delta
		velocity = knockback
		knockback = knockback.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		_update_sprite(false)
		queue_redraw()
		return
		
	var move: Vector2 = Vector2.ZERO
	var p = Global.player
	if active and is_instance_valid(p) and p.alive:
		var to_p: Vector2 = p.global_position - global_position
		los.target_position = to_p          
		los.force_raycast_update()
		has_los = not los.is_colliding()
		var dir: Vector2 = to_p.normalized()
		facing = dir
		match kind:
			"archer":
				if player_too_close: move = -dir
				elif player_in_range and has_los: move = dir.orthogonal() * strafe_sign * 0.5
				else: move = dir
			"slime": move = dir * (0.55 + 0.45 * absf(sin(_t * 4.0)))
			_: move = dir
			
	# Xử lý Làm chậm
	if slow_timer > 0:
		slow_timer -= delta
		move *= 0.5 
		
	velocity = move * float(data["speed"]) + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 900.0 * delta)
	move_and_slide()
	_update_sprite(move.length() > 0.05)
	queue_redraw()

func take_damage(amount: int, from_pos: Vector2 = Vector2.ZERO, knock: float = 200.0, true_dmg: bool = false) -> void:
	if not alive or not active:
		return
	
	var actual_damage = amount
	if not true_dmg:
		actual_damage = maxi(1, amount - int(armor))
	hp -= float(actual_damage)
	
	var actual_knock = knock * (1.0 - cc_resist)
	knockback += (global_position - from_pos).normalized() * actual_knock / float(data["weight"])
	
	modulate = Color(2.5, 2.5, 2.5)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.12)
	Global.float_text(global_position, str(actual_damage), Color(1.0, 0.95, 0.5))
	Global.burst(global_position, data["color"], 5, 120.0, 1.0)
	if not true_dmg: Global.sfx("hit")
	if hp <= 0.0:
		_die()

func kill() -> void:
	if alive: _die()

func _die() -> void:
	alive = false
	Global.sfx("kill")
	if Global.get("run_stats") != null and Global.run_stats.has("kills"):
		Global.run_stats["kills"] += 1
	Global.shake(0.25, 0.15)
	Global.burst(global_position, data["color"], 18, 220.0, 2.0)
	Global.hitstop(0.035)
	$Body.set_deferred("disabled", true)
	hitbox.set_deferred("monitoring", false)
	near_zone.set_deferred("monitoring", false)
	far_zone.set_deferred("monitoring", false)
	hide()
	died.emit(self)
	_drop_and_free.call_deferred()

func _drop_and_free() -> void:
	var n: int = data["coins"]
	for i in n:
		_spawn_pickup("coin")
	if randf() < 0.12:
		_spawn_pickup("heal")
	queue_free()

func _spawn_pickup(k: String) -> void:
	var p = PICKUP.instantiate()
	p.setup(k)
	Global.world.add_child(p)
	p.global_position = global_position + Vector2(randf_range(-14.0, 14.0), randf_range(-14.0, 14.0))

func _draw() -> void:
	# Thân quái giờ do $Sprite (AnimatedSprite2D) vẽ; _draw() chỉ còn thanh máu nổi phía trên.
	var r: float = data["radius"]
	if hp < max_hp and alive:
		draw_rect(Rect2(-r, -r - 10.0, r * 2.0, 4.0), Color(0.15, 0.0, 0.0))
		draw_rect(Rect2(-r, -r - 10.0, r * 2.0 * clampf(hp / max_hp, 0.0, 1.0), 4.0), Color(0.9, 0.2, 0.2))
