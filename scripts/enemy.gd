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
## Affix Summoner xin triệu hồi quái nhỏ — dungeon lắng nghe và dựng quái (enemy không tự biết về phòng).
signal summon_requested(owner_enemy: Node)

const PICKUP = preload("res://scenes/pickup.tscn")
const BULLET = preload("res://scenes/bullet.tscn")
const QAgentScript = preload("res://scripts/q_agent.gd")
const HpBarScript = preload("res://scripts/enemy_hp_bar.gd")
const AffixScript = preload("res://scripts/enemy_affix.gd")

## AI Tầng 2 (Q-Learning): % quái tầm xa (archer/shaman) trở thành "Tinh Anh" mỗi lần spawn —
## HP cao hơn, tint tím nhận diện, và dùng QAgent (scripts/q_agent.gd) để quyết định hành vi
## bắn thay vì luôn theo nhịp cố định như quái thường.
const ELITE_CHANCE: float = 0.15
const ELITE_HP_MULT: float = 1.4
var is_elite: bool = false
var q_agent: Node = null
var affix_id: String = "" ## Biến thể (volatile/summoner/warden); "" = quái thường
var affix_node: Node2D = null

var kind: String = "slime"
var data: Dictionary = {}
var active: bool = false
var knockback: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT
var player_too_close: bool = false
var player_in_range: bool = false
var has_los: bool = false
## AI Tầng 2: hold/retreat của QAgent chạy trong cửa sổ PASSIVE_WINDOW giây rồi tự chấm điểm.
const PASSIVE_WINDOW: float = 0.6
const PASSIVE_DODGE_REWARD: float = 4.0   # Player đang lăn né trong lúc nhịn = nhịn đúng lúc
const PASSIVE_MISSED_PENALTY: float = -3.0 # Player đứng im mà mình bỏ lỡ cơ hội bắn
const PASSIVE_STILL_SPEED: float = 40.0
var retreat_timer: float = 0.0
var passive_timer: float = 0.0
var _passive_saw_roll: bool = false
var _passive_still_time: float = 0.0
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
	"mimic": {"prefix": "chest_full_open", "single_anim": true, "offset_y": -8.0},
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
func setup(p_kind: String, hp_mult: float = 1.0, allow_affix: bool = false) -> void:
	kind = p_kind
	data = Global.enemies[p_kind]
	if (kind == "archer" or kind == "shaman") and randf() < ELITE_CHANCE:
		is_elite = true
		hp_mult *= ELITE_HP_MULT
	elif allow_affix:
		affix_id = AffixScript.roll(kind, Global.floor_num)
	var floor_scale: float = Global.hp_scale_for_floor(Global.floor_num)
	var endless_mult: float = Global.endless_difficulty_mult(Global.floor_num) # >1.0 chỉ khi tầng > 10 (Vô Hạn)
	var computed_max_hp: float = float(data["hp"]) * hp_mult * floor_scale * endless_mult
	var computed_armor: float = floor((Global.floor_num - 1) * 1.2) + floor((endless_mult - 1.0) * 8.0)
	var computed_cc_resist: float = minf(0.0 + (Global.floor_num - 1) * 0.15, 0.6)
	$Hurtbox.setup(computed_max_hp, computed_armor, computed_cc_resist, float(data["weight"]))
	if is_elite:
		q_agent = Node.new()
		q_agent.set_script(QAgentScript)
		add_child(q_agent)
		q_agent.attach(self)
	if affix_id != "":
		affix_node = Node2D.new()
		affix_node.set_script(AffixScript)
		affix_node.name = "Affix"
		add_child(affix_node)
		affix_node.attach(self, affix_id)
		affix_node.summon_requested.connect(func(o): summon_requested.emit(o))

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
	_add_hp_bar()


## Cache SpriteFrames theo "kind" — dựng 1 lần duy nhất cho mỗi loại quái rồi
## dùng chung cho mọi instance (SpriteFrames chỉ chứa dữ liệu khung hình/tốc độ,
## không có trạng thái riêng từng con, nên chia sẻ an toàn). Trước đây mỗi lần
## spawn quái đều load lại ~8 ảnh từ đĩa + tạo ImageTexture mới, khá tốn khi một
## đợt wave sinh tới 10 quái cùng lúc và lặp lại ở mọi phòng/mọi tầng.
static var _frames_cache: Dictionary = {}

## Thanh máu nổi: node riêng z cao, đặt ngay trên ĐỈNH sprite thật (đọc chiều cao khung hình).
func _add_hp_bar() -> void:
	var top: float = -float(data["radius"]) - 10.0
	var frames: SpriteFrames = sprite.sprite_frames
	if frames != null and frames.has_animation("idle") and frames.get_frame_count("idle") > 0:
		var tex: Texture2D = frames.get_frame_texture("idle", 0)
		if tex != null:
			top = (sprite.offset.y - float(tex.get_height()) * 0.5) * sprite.scale.y - 6.0
	var bar: Node2D = Node2D.new()
	bar.set_script(HpBarScript)
	bar.name = "HpBar"
	add_child(bar)
	bar.setup(self, top, float(data["radius"]), is_elite)
	if affix_id != "":
		bar.set_tag(AffixScript.label_of(affix_id), AffixScript.color_of(affix_id))


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
	elif hurtbox.ward > 0.0:
		sprite.modulate = Color(0.6, 0.85, 1.7) # đang có khiên của Warden
	elif affix_id != "":
		sprite.modulate = AffixScript.color_of(affix_id).lerp(Color.WHITE, 0.35) * 1.15
	elif is_elite:
		sprite.modulate = Color(1.4, 0.85, 1.7) # Tinh Anh: tint tím nhận diện bằng mắt
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
		if player_in_range and has_los and passive_timer <= 0.0:
			_shoot() # đang trong cửa sổ hold/retreat thì không mở quyết định mới
	elif kind == "frost_big_zombie":
		_frost_slam()

## AI Tầng 1 (Heuristic/Adaptive): thay vì luôn bắn thẳng vào vị trí hiện tại, pha trộn
## thêm hướng "đón đầu" dựa trên thói quen né trái/phải (PlayerProfiler.dodge_bias) VÀ vận
## tốc hiện tại của Player — trọng số pha trộn tăng dần theo _confidence (càng quan sát
## nhiều ván càng đoán đúng hơn). Luôn cộng thêm 1 lệch góc ngẫu nhiên nhỏ ("Human Error",
## xem PlayerProfiler.human_error_rad()) để không biến thành aimbot bóp nghẹt tuyệt đối.
func _shoot() -> void:
	var p = Global.player
	if not is_instance_valid(p) or not p.alive:
		return
	var p_center = p.hurt_center() if p.has_method("hurt_center") else p.global_position
	var to_player: Vector2 = p_center - global_position
	var base_dir: Vector2 = to_player.normalized()

	# AI Tầng 2 (quái Tinh Anh, xem q_agent.gd): để QAgent quyết định hành vi thay vì luôn bắn.
	var q_action: String = ""
	if is_elite and q_agent:
		q_action = q_agent.choose_action()
		if q_action == "hold" or q_action == "retreat":
			_begin_passive(q_action) # không bắn; sau PASSIVE_WINDOW sẽ tự chấm điểm -> learn()
			return

	# Vector "đón đầu": kết hợp vận tốc thực tế của Player + xu hướng né ngang đã quan sát
	# (AI Tầng 1, PlayerProfiler). Quái Tinh Anh chọn "shoot_straight" thì bỏ qua đón đầu hẳn.
	var lead_weight: float = 0.0 if q_action == "shoot_straight" else PlayerProfiler.predictive_lead_weight()
	var perp: Vector2 = base_dir.orthogonal()
	var lateral_lead: Vector2 = perp * PlayerProfiler.dodge_bias * 40.0
	var velocity_lead: Vector2 = p.velocity * 0.18
	var predicted_point: Vector2 = p_center + (lateral_lead + velocity_lead) * lead_weight
	var dir: Vector2 = (predicted_point - global_position).normalized()
	if dir == Vector2.ZERO:
		dir = base_dir

	# Human Error: luôn lệch thêm 1 góc ngẫu nhiên nhỏ, không bao giờ bắn "hoàn hảo" 100%.
	dir = dir.rotated(randf_range(-1.0, 1.0) * PlayerProfiler.human_error_rad())

	var b = BULLET.instantiate()
	b.setup(false, dir, int(data["bullet_damage"]), float(data["bullet_speed"]), 2.5, data["color"], 6.0, false, String(data.get("bullet_effect", "")))
	if is_elite and q_agent:
		b.source_q_agent = q_agent # bullet.gd báo kết quả trúng/trượt ngược lại qua field này
	Global.world.add_child(b)
	b.global_position = global_position + dir * 18.0
	Global.sfx("enemy_shoot")

## Bắt đầu cửa sổ "nhịn" của QAgent. retreat -> còn chủ động lùi + lách ngang trong cửa sổ.
func _begin_passive(action: String) -> void:
	passive_timer = PASSIVE_WINDOW
	_passive_saw_roll = false
	_passive_still_time = 0.0
	if action == "retreat":
		retreat_timer = PASSIVE_WINDOW

## Theo dõi cửa sổ hold/retreat và chấm điểm khi hết giờ (tách riêng khỏi vật lý di chuyển).
func _tick_passive(delta: float) -> void:
	if passive_timer <= 0.0:
		return
	var p = Global.player
	if is_instance_valid(p) and p.alive:
		if bool(p.get("rolling")):
			_passive_saw_roll = true
		if has_los and p.velocity.length() < PASSIVE_STILL_SPEED:
			_passive_still_time += delta
	passive_timer -= delta
	if passive_timer > 0.0:
		return
	var reward: float = 0.0
	if _passive_saw_roll:
		reward = PASSIVE_DODGE_REWARD
	elif _passive_still_time >= PASSIVE_WINDOW * 0.5:
		reward = PASSIVE_MISSED_PENALTY
	if is_elite and q_agent:
		q_agent.learn(reward)

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

## Buff nguyên tố (burn/poison/frost) — forward sang Hurtbox, cùng kiểu duck-typing.
func apply_element(kind: String, power: int, cap: int) -> void:
	hurtbox.apply_element(kind, power, cap)

func apply_status(type: String, duration: float) -> void:
	hurtbox.apply_status(type, duration)

## Buff "Phá Giáp" (Sử Thi) — forward sang Hurtbox, cùng kiểu duck-typing với take_damage()/apply_status().
func apply_sunder() -> void:
	hurtbox.apply_sunder()

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
	hurtbox.tick_elements(delta)
	hurtbox.tick_sunder(delta)

	if hurtbox.consume_stun(delta):
		velocity = knockback
		knockback = knockback.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		_update_sprite(false)
		queue_redraw()
		return

	_tick_passive(delta)
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
		# QAgent chọn "retreat": chủ động lùi ra xa Player và lách ngang (ghi đè hướng thường)
		if retreat_timer > 0.0:
			retreat_timer -= delta
			move = (-dir + dir.orthogonal() * strafe_sign).normalized()

	if hurtbox.consume_slow(delta):
		move *= hurtbox.SLOW_MOVE_MULT # chậm 25% (trước đây 50%) — xem HurtboxComponent.CC_*

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
	Global.sfx("mimic_die" if kind == "mimic" else "kill")
	if Global.get("run_stats") != null and Global.run_stats.has("kills"):
		Global.run_stats["kills"] += 1
	Global.record_kill()
	Global.shake(0.25, 0.15)
	Global.burst(global_position, data["color"], 18, 220.0, 2.0)
	Global.hitstop(0.035)
	$Body.set_deferred("disabled", true)
	touch_zone.set_deferred("monitoring", false)
	near_zone.set_deferred("monitoring", false)
	far_zone.set_deferred("monitoring", false)
	hide()
	died.emit(self)
	if Global.buff_stack("buff_deathnova") > 0:
		_death_nova()
	_drop_and_free.call_deferred()

## Buff "Nổ Tử Thi" (Sử Thi): quái chết lan 1 lượng sát thương cố định cho quái khác
## trong bán kính nhỏ quanh nó — dùng take_damage() có sẵn (true_dmg để bỏ qua giáp).
func _death_nova() -> void:
	const DEATH_NOVA_DMG: int = 30
	const DEATH_NOVA_RADIUS: float = 90.0
	Global.burst(global_position, Color(1.0, 0.5, 0.15), 14, 180.0, 2.0)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not is_instance_valid(e):
			continue
		if e.has_method("take_damage") and e.alive and e.global_position.distance_to(global_position) < DEATH_NOVA_RADIUS:
			e.take_damage(DEATH_NOVA_DMG, global_position, 80.0, true)
			# Synergy Nổ Tử Thi + Nguyên Tố: vụ nổ lan Cháy/Độc/Lạnh sang đám quái xung quanh
			Global.on_player_hit(e, DEATH_NOVA_DMG, false)

## Tỉ lệ rớt bình máu (giảm để cân bằng với Giáp Ảo hồi lại được).
const HEAL_DROP_CHANCE: float = 0.06

func _drop_and_free() -> void:
	var n: int = data["coins"]
	if has_meta("summoner"):
		n = 0 # quái do Summoner triệu hồi không rơi xu (chống cày)
	elif affix_id != "":
		n += 1 # thưởng thêm cho quái biến thể
	for i in n:
		_spawn_pickup("coin")
	if randf() < HEAL_DROP_CHANCE:
		_spawn_pickup("heal")
	queue_free()

func _spawn_pickup(k: String) -> void:
	var p = PICKUP.instantiate()
	p.setup(k)
	Global.world.add_child(p)
	p.global_position = global_position + Vector2(randf_range(-14.0, 14.0), randf_range(-14.0, 14.0))

func _draw() -> void:
	# Thân quái do $Sprite vẽ; thanh máu nổi giờ là node riêng (enemy_hp_bar.gd) để không bị sprite che.
	pass
