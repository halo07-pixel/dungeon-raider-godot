extends CharacterBody2D
## Kẻ địch: AI/di chuyển/sprite + bắn tầm xa/dộng đất tầm xa. Logic GÂY và NHẬN sát
## thương (Phase 5: Hitbox/Hurtbox Component Pattern) đã tách ra 2 Node con riêng:
## - $Hurtbox (HurtboxComponent)    — nhận đòn: hp/giáp, khống chế (choáng/chậm/chảy máu)
## - $MeleeHitbox (MeleeHitboxComponent) — gây đòn cận chiến (đòn chạm + hiệu ứng theo kind)
## Xem scripts/components/. File này chỉ còn giữ: identity (kind/data), AI di chuyển,
## sprite/animation, bắn tầm xa (_shoot — đã tách sẵn qua bullet.gd từ trước), dộng đất
## tầm xa (_frost_slam), và chuỗi chết/rơi đồ (_die/_drop_and_free — khác phạm trù với
## gây/nhận sát thương nên vẫn ở đây, chỉ đổi điểm kích hoạt sang nghe signal từ Hurtbox).

signal died(enemy)

const PICKUP = preload("res://scenes/pickup.tscn")
const BULLET = preload("res://scenes/bullet.tscn")

var kind: String = "slime"
var data: Dictionary = {}
var active: bool = false
var knockback: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT
var player_too_close: bool = false
var player_in_range: bool = false
var has_los: bool = false
var strafe_sign: float = 1.0
var _t: float = 0.0

## Property ảo (Godot 4 computed property, chỉ có get) trỏ thẳng vào $Hurtbox — giữ
## nguyên giao diện cũ enemy.hp/.max_hp/.alive cho ~15 nơi gọi rải rác trong
## bullet.gd/boss.gd/dungeon.gd/spike_trap.gd/... (đọc .alive/.hp trực tiếp trên enemy)
## không phải sửa gì, trong khi state thật sự giờ nằm hẳn trong Hurtbox, không còn 2
## bản sao lệch nhau. Dùng $Hurtbox (không qua field @onready) để an toàn cả khi được
## đọc trước khi node vào SceneTree.
var hp: float:
	get: return $Hurtbox.hp
var max_hp: float:
	get: return $Hurtbox.max_hp
var alive: bool:
	get: return $Hurtbox.alive

@onready var hurtbox: HurtboxComponent = $Hurtbox
@onready var melee_hitbox: MeleeHitboxComponent = $MeleeHitbox
@onready var touch_zone: Area2D = $TouchZone
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
	"brute": {"prefix": "ogre", "single_anim": false, "offset_y": 2.0},
	# Biome 2 (Đầm Lầy) — sprite chỉ có khung "idle" (không có "run" riêng) nên single_anim=true.
	"shaman": {"prefix": "orc_shaman", "single_anim": true, "offset_y": -10.0},
	"chort": {"prefix": "chort", "single_anim": true, "offset_y": -12.0},
	"masked_orc": {"prefix": "masked_orc", "single_anim": true, "offset_y": -6.0},
	# Biome 3 (Băng Giá) — bản nhuộm băng (palette-remap) của bộ sprite zombie, prefix "frost_*".
	"frost_zombie": {"prefix": "frost_zombie", "single_anim": true, "offset_y": -6.0},
	"frost_big_zombie": {"prefix": "frost_big_zombie", "single_anim": true, "offset_y": 0.0},
	"frost_tiny": {"prefix": "frost_tiny", "single_anim": true, "offset_y": -6.0},
}

## Tâm hitbox thật — enemy không lệch offset nên bằng global_position, nhưng vẫn
## expose hàm này để player/enemy khác gọi đồng nhất (không ngoại lệ con quái nào).
func hurt_center() -> Vector2:
	return $Body.global_position

## LƯU Ý: dungeon.gd gọi setup() TRƯỚC add_child() (enemy chưa vào SceneTree), nên
## @onready var hurtbox vẫn CHƯA được gán lúc này — phải dùng $Hurtbox (resolve ngay
## trên cây Node con đã dựng xong lúc instantiate(), không phụ thuộc SceneTree) thay
## vì field "hurtbox" ở trên.
func setup(p_kind: String, hp_mult: float = 1.0) -> void:
	kind = p_kind
	data = Global.enemies[p_kind]
	var floor_scale: float = 1.0 + 0.15 * float(Global.floor_num - 1)
	var endless_mult: float = Global.endless_difficulty_mult(Global.floor_num) # >1.0 chỉ khi tầng > 10 (Vô Hạn)
	var computed_max_hp: float = float(data["hp"]) * hp_mult * floor_scale * endless_mult
	var computed_armor: float = floor((Global.floor_num - 1) * 1.2) + floor((endless_mult - 1.0) * 8.0)
	var computed_cc_resist: float = minf(0.0 + (Global.floor_num - 1) * 0.15, 0.6)
	$Hurtbox.setup(computed_max_hp, computed_armor, computed_cc_resist, float(data["weight"]))

func _ready() -> void:
	if data.is_empty():
		setup(kind)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("enemies")
	strafe_sign = 1.0 if randf() < 0.5 else -1.0
	var r: float = data["radius"]
	_set_circle($Body, r)
	_set_circle($TouchZone/Shape, r + 5.0)
	_set_circle($NearZone/Shape, float(data.get("keep_away", 1.0)))
	_set_circle($FarZone/Shape, float(data.get("range", 1.0)))
	hurtbox.hurt.connect(_on_hurt)
	hurtbox.died.connect(_die)
	melee_hitbox.setup(self, hurtbox, touch_zone, data)
	near_zone.body_entered.connect(_on_near_entered)
	near_zone.body_exited.connect(_on_near_exited)
	far_zone.body_entered.connect(_on_far_entered)
	far_zone.body_exited.connect(_on_far_exited)
	action_timer.one_shot = not (kind == "archer" or kind == "shaman" or kind == "frost_big_zombie")
	action_timer.timeout.connect(_on_action_timer_timeout)
	spawn_timer.timeout.connect(_on_spawn_done)
	modulate.a = 0.35
	_setup_sprite()


## Cache SpriteFrames theo "kind" — dựng 1 lần duy nhất cho mỗi loại quái rồi
## dùng chung cho mọi instance (SpriteFrames chỉ chứa dữ liệu khung hình/tốc độ,
## không có trạng thái riêng từng con, nên chia sẻ an toàn). Trước đây mỗi lần
## spawn quái đều load lại ~8 ảnh từ đĩa + tạo ImageTexture mới, khá tốn khi một
## đợt wave sinh tới 10 quái cùng lúc và lặp lại ở mọi phòng/mọi tầng.
static var _frames_cache: Dictionary = {}

func _setup_sprite() -> void:
	var cfg: Dictionary = ENEMY_SPRITES.get(kind, ENEMY_SPRITES["slime"])
	if not _frames_cache.has(kind):
		_frames_cache[kind] = _build_enemy_frames(cfg)
	sprite.sprite_frames = _frames_cache[kind]
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
		var tex := Global.load_tex(path)
		if tex:
			frames.add_frame(anim_name, tex)


func _update_sprite(moving: bool) -> void:
	if facing.x != 0.0:
		sprite.flip_h = facing.x < 0.0
	if hurtbox.is_stunned():
		sprite.modulate = Color.YELLOW
	elif hurtbox.is_slowed():
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
	if kind == "archer" or kind == "shaman":
		action_timer.start(float(data["shoot_cd"]))
	elif kind == "frost_big_zombie":
		action_timer.start(float(data.get("slam_cd", 2.2)))
	else:
		melee_hitbox.try_attack() # Nếu người chơi đã đứng sẵn trong tầm chạm lúc spawn xong

func _on_action_timer_timeout() -> void:
	if not active or not alive or hurtbox.is_stunned():
		return
	if kind == "archer" or kind == "shaman":
		if player_in_range and has_los:
			_shoot()
	elif kind == "frost_big_zombie":
		_frost_slam()

func _shoot() -> void:
	var p = Global.player
	if not is_instance_valid(p) or not p.alive:
		return
	var p_center = p.hurt_center() if p.has_method("hurt_center") else p.global_position
	var dir: Vector2 = (p_center - global_position).normalized()
	var b = BULLET.instantiate()
	b.setup(false, dir, int(data["bullet_damage"]), float(data["bullet_speed"]), 2.5, data["color"], 6.0, false, String(data.get("bullet_effect", "")))
	Global.world.add_child(b)
	b.global_position = global_position + dir * 18.0
	Global.sfx("enemy_shoot")

## Băng Giáng (Frost Big Zombie) — dộng đất định kỳ (action_timer lặp, xem
## _on_action_timer_timeout), gây SLOW nếu người chơi đang đứng gần thay vì đánh cận trực tiếp.
func _frost_slam() -> void:
	var p = Global.player
	if not is_instance_valid(p) or not p.alive:
		return
	var slam_r: float = float(data.get("slam_radius", 70.0))
	var p_center: Vector2 = p.hurt_center() if p.has_method("hurt_center") else p.global_position
	if global_position.distance_to(p_center) > slam_r:
		return
	if p.has_method("apply_status"):
		p.apply_status("slow", 1.0)
	Global.burst(global_position, Color(0.6, 0.85, 1.0), 14, 160.0, 1.6)
	Global.shake(0.25, 0.15)
	Global.sfx("slam")

# --- FORWARD SANG $Hurtbox (giữ nguyên chữ ký cũ cho ~15 nơi gọi .take_damage()/
# .apply_status() trực tiếp trên enemy ở bullet.gd/player.gd/boss.gd/spike_trap.gd/...) ---
func take_damage(amount: int, from_pos: Vector2 = Vector2.ZERO, knock: float = 200.0, true_dmg: bool = false) -> void:
	if not alive or not active:
		return
	hurtbox.take_hit(amount, from_pos, knock, true_dmg)

func apply_status(type: String, duration: float) -> void:
	hurtbox.apply_status(type, duration)

## Phản ứng VFX/âm thanh khi $Hurtbox báo đã nhận đòn — vật lý (cộng dồn knockback)
## vẫn là field "knockback" được _physics_process() của CHÍNH enemy tiêu thụ mỗi frame,
## Hurtbox chỉ tính toán vector rồi trả lên qua signal, không tự ý set velocity.
func _on_hurt(amount: int, knockback_vec: Vector2, true_dmg: bool) -> void:
	knockback += knockback_vec
	modulate = Color(2.5, 2.5, 2.5)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.12)
	Global.float_text(global_position, str(amount), Color(1.0, 0.95, 0.5))
	Global.burst(global_position, data["color"], 5, 120.0, 1.0)
	if not true_dmg:
		Global.sfx("hit")

func _physics_process(delta: float) -> void:
	if not alive:
		return
	_t += delta

	hurtbox.tick_bleed(delta)

	if hurtbox.consume_stun(delta):
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
			"archer", "shaman":
				if player_too_close: move = -dir
				elif player_in_range and has_los: move = dir.orthogonal() * strafe_sign * 0.5
				else: move = dir
			"slime": move = dir * (0.55 + 0.45 * absf(sin(_t * 4.0)))
			_: move = dir

	if hurtbox.consume_slow(delta):
		move *= 0.5

	velocity = move * float(data["speed"]) + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 900.0 * delta)
	move_and_slide()
	_update_sprite(move.length() > 0.05)
	queue_redraw()

func kill() -> void:
	hurtbox.mark_dead()

## Kích hoạt khi $Hurtbox phát tín hiệu "died" (hp về 0 HOẶC kill() ép chết ngay dù hp
## còn dư, vd. frost_tiny tự huỷ sau khi chạm — xem HurtboxComponent.mark_dead()).
func _die() -> void:
	Global.sfx("kill")
	if Global.get("run_stats") != null and Global.run_stats.has("kills"):
		Global.run_stats["kills"] += 1
	Global.shake(0.25, 0.15)
	Global.burst(global_position, data["color"], 18, 220.0, 2.0)
	Global.hitstop(0.035)
	$Body.set_deferred("disabled", true)
	touch_zone.set_deferred("monitoring", false)
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
