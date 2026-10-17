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
const RLControllerScript = preload("res://scripts/rl_controller.gd")
const BOSS_HAZARD = preload("res://scripts/boss_hazard.gd")
const SLAM_RADIUS: float = 150.0
## --- Dungeon Lord "khó hơn" (chỉ áp dụng khi kind == "lord"; các boss khác giữ nguyên) ---
const LORD_RING_COUNT: int = 14                       # đạn mỗi vòng (Warden vẫn 12)
const LORD_RING_VOLLEYS: Array = [3, 4, 5, 5]         # số vòng đạn theo pha 1..4
const LORD_RING_GAP: float = 0.3                      # giây giữa các vòng (đủ để đọc mẫu đạn)
const LORD_AOE_MULT: float = 1.35                     # nhân bán kính các vùng AOE của Lord
const LORD_JUDGE_RADIUS: float = 230.0
const LORD_JUDGE_DAMAGE: int = 55
const LORD_JUDGE_TELEGRAPH: float = 1.3
const LORD_JUDGE_FOLLOW: float = 0.8                  # vùng nổ bám theo Player trong 0.8s đầu rồi chốt
const LORD_JUDGE_CHASES: int = 3
const LORD_JUDGE_CHASE_RADIUS: float = 110.0
const LORD_JUDGE_CHASE_DAMAGE: int = 28
const LORD_JUDGE_CHASE_TELEGRAPH: float = 0.4
const LORD_JUDGE_CHASE_LEAD: float = 0.4              # đón đầu theo vận tốc Player (giây)
const LORD_JUDGE_FINAL_RINGS: int = 2
const LORD_JUDGE_FINAL_COUNT: int = 16
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
var slow_timer: float = 0.0
const BOSS_SLOW_STRENGTH: float = 0.2   # chậm tối đa 20% khi kháng khống chế = 0 (trước đây 40%)
const BOSS_CC_DURATION_MULT: float = 0.5
var is_boss: bool = true
var blink_cd: float = 0.0 # riêng Necromancer: hồi chiêu dịch chuyển né cận chiến
## Riêng Frost: khi máu <=25%, vào pha "nổi điên" — đánh nhanh hơn, telegraph ngắn hơn,
## đuổi theo nhanh hơn, ưu tiên các đòn nguy hiểm nhất. Bù lại cho việc đòn to-xác mà
## thiếu áp lực thời gian khiến người chơi kiting thoải mái ở pha cuối.
var frost_enraged: bool = false

## Buff "Phá Giáp" (Sử Thi) của Player — cùng công thức/field với HurtboxComponent của
## enemy.gd thường (xem ghi chú ở đó), boss không dùng component nên khai báo trực tiếp.
var sunder_stacks: int = 0
var sunder_timer: float = 0.0
const SUNDER_PER_STACK: float = 0.08
const SUNDER_MAX_STACKS: int = 5
const SUNDER_DURATION: float = 3.0

## Boss chỉ chịu Thiêu Đốt / Độc / làm chậm-tích-băng (KHÔNG bị đóng băng cứng) — xem element_status.gd.
var elements = preload("res://scripts/components/element_status.gd").new()

func apply_element(kind: String, power: int, cap: int) -> void:
	if not alive:
		return
	if not elements.dot_cb.is_valid():
		elements.dot_cb = func(dmg: int, color: Color):
			if alive:
				take_damage(dmg, global_position, 0.0)
				Global.burst(global_position, color, 3, 50.0, 1.0)
	match kind:
		"burn": elements.apply_burn(power)
		"poison": elements.apply_poison(power, cap)
		"frost":
			# Boss KHÔNG bị đóng băng cứng, chỉ bị chậm theo từng stack Lạnh (xem apply_status("slow")).
			if not elements.slow_cb.is_valid():
				elements.slow_cb = func(d: float): apply_status("slow", d)
			elements.apply_frost(cap, false)

## Boss chỉ nhận trạng thái "slow" (các trạng thái khác — choáng, chảy máu... — bị bỏ qua như trước).
## Mức chậm giảm theo cc_resist (kháng khống chế tăng theo tầng).
func apply_status(type: String, duration: float, _extra: float = 0.0) -> void:
	if type != "slow" or not alive:
		return
	slow_timer = maxf(slow_timer, duration * BOSS_CC_DURATION_MULT)

func _slow_factor() -> float:
	if slow_timer <= 0.0:
		return 1.0
	return 1.0 - BOSS_SLOW_STRENGTH * (1.0 - cc_resist)

func apply_sunder() -> void:
	if not alive:
		return
	sunder_stacks = mini(sunder_stacks + 1, SUNDER_MAX_STACKS)
	sunder_timer = SUNDER_DURATION

## Ranh giới phòng Boss (world space), do dungeon.gd truyền vào lúc spawn qua
## set_arena_bounds(). Rect2() rỗng (mặc định) = KHÔNG giới hạn — để các code path cũ
## (spawn test/debug không gọi set_arena_bounds) không bị ảnh hưởng. Chỉ dùng để chặn
## _necro_blink() dịch chuyển xuyên tường ra ngoài bản đồ (BUG: global_position += ...
## gán thẳng toạ độ, bỏ qua va chạm vật lý mà move_and_slide() vẫn tự chặn được).
## AI Tầng 3: RLController (chính sách nội bộ thích nghi nhẹ) — xem rl_controller.gd.
## Dùng để (1) thiên lệch chọn đòn trong _attack_pool(), (2) pha trộn nhẹ vào hướng đuổi Player
## (lách ngang + tránh tường). KHÔNG thay thế chuỗi đòn/telegraph đã tinh chỉnh của từng boss.
var rl: Node = null
const RL_DECISION_INTERVAL: float = 0.25
const RL_MOVE_BLEND: float = 0.35      # 0 = đuổi thẳng như cũ, 1 = hoàn toàn theo chính sách
const RL_PICK_BIAS: float = 0.7        # độ mạnh thiên lệch chọn đòn (exp(±pick*BIAS))
## Chính sách đã huấn luyện offline cho Dungeon Lord (tools/rl/train_lord.py). Thiếu file -> chạy như cũ.
const LORD_POLICY_PATH: String = "res://assets/ai/lord_policy.json"
## Đòn diện rộng/đón đầu (ưu tiên khi Player ở xa/chạy nhanh) và đòn trực diện (ưu tiên khi gần).
const AREA_ATTACKS: Array = ["ring", "slam", "blizzard", "spike_field", "ice_prison", "judgement", "frost_breath", "necro_curse"]
const DIRECT_ATTACKS: Array = ["charge", "necro_bolt", "frost_charge"]
var _rl_timer: float = 0.0
var _rl_move: Vector2 = Vector2.ZERO
var _rl_prev_player_total: float = -1.0
var _rl_prev_hp: float = -1.0
var arena_rect: Rect2 = Rect2()

func set_arena_bounds(rect: Rect2) -> void:
	arena_rect = rect

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
	var floor_scale: float = Global.hp_scale_for_floor(Global.floor_num)
	var endless_mult: float = Global.endless_difficulty_mult(Global.floor_num) # >1.0 chỉ khi tầng > 10 (Vô Hạn)
	max_hp = float(cfg["base_hp"]) * hp_mult * floor_scale * endless_mult
	hp = max_hp
	armor = floor((Global.floor_num - 1) * 1.6) + 2.0 + floor((endless_mult - 1.0) * 10.0)
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
	rl = Node.new()
	rl.set_script(RLControllerScript)
	rl.name = "RLController"
	add_child(rl)
	rl.attach(self)
	if kind == "lord":
		rl.load_policy(LORD_POLICY_PATH)

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
	var base: float = COOLDOWN_TABLE[mini(phase - 1, COOLDOWN_TABLE.size() - 1)]
	if kind == "frost" and frost_enraged:
		base *= 0.6
	return base


func _speed_mult() -> float:
	var m: float = SPEED_MULT_TABLE[mini(phase - 1, SPEED_MULT_TABLE.size() - 1)]
	if kind == "frost" and frost_enraged:
		m *= 0.7 # telegraph ngắn hơn -> khó đọc đòn hơn ở pha nổi điên
	return m


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
				pool.append("ice_prison")
			if phase >= 3:
				pool.append("blizzard")
				pool.append("ice_prison") # tăng tỉ lệ ở pha cuối, đòn chính xác rủi ro cao
			if frost_enraged:
				pool.append("ice_prison")
				pool.append("blizzard") # nổi điên: dồn thêm trọng số vào 2 đòn nguy hiểm nhất
			return pool
		"lord":
			# Mỗi pha có CHỦ ĐỀ riêng (không đơn thuần cộng dồn hết mọi đòn cùng lúc) để trận
			# đấu cuối có cảm giác leo thang rõ rệt thay vì "trộn lẫn mọi đòn đã gặp".
			match phase:
				1: return ["charge", "ring", "ring"] # Pha 1: áp sát kiểu Warden
				2: return ["necro_bolt", "necro_bolt", "necro_curse", "necro_summon", "charge"] # Pha 2: tầm xa + triệu hồi
				3: return ["frost_breath", "spike_field", "frost_charge", "ice_prison", "necro_bolt"] # Pha 3: khống chế vùng
				_: return ["judgement", "lord_summon_all", "ring", "necro_bolt", "ice_prison"] # Pha 4: tổng lực
		_: # warden
			var pool: Array = ["charge", "ring"]
			if phase >= 2:
				pool.append("slam")
				pool.append("summon")
			return pool


## Hệ số pha trộn hướng đi / độ mạnh thiên lệch chọn đòn: lấy từ chính sách đã huấn luyện nếu có.
func _rl_move_blend() -> float:
	if rl != null and rl.move_blend >= 0.0:
		return rl.move_blend
	return RL_MOVE_BLEND


func _rl_pick_bias() -> float:
	if rl != null and rl.pick_bias >= 0.0:
		return rl.pick_bias
	return RL_PICK_BIAS


## Giá trị PICK [-1,1] mới nhất của RLController (0 nếu chưa có).
func _rl_pick_value() -> float:
	if rl == null:
		return 0.0
	return float(rl.last_action[rl.ACTION_PICK])

## Chọn đòn có trọng số: mỗi lần xuất hiện trong pool = 1 phiếu (như pick_random cũ), nhân thêm
## exp(±pick * RL_PICK_BIAS) — đòn diện rộng được tăng khi pick > 0, đòn trực diện khi pick < 0.
## pick = 0 -> đúng phân phối cũ.
func _weighted_attack(pool: Array, pick: float) -> String:
	var weights: Array = []
	var total: float = 0.0
	for a in pool:
		var sign_f: float = 1.0 if AREA_ATTACKS.has(a) else (-1.0 if DIRECT_ATTACKS.has(a) else 0.0)
		var w: float = exp(pick * sign_f * _rl_pick_bias())
		weights.append(w)
		total += w
	var roll: float = randf() * total
	for i in pool.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]

## Nhịp quyết định của RLController: chấm reward cho nhịp trước (Player mất bao nhiêu HP+giáp,
## Boss mất bao nhiêu HP) rồi decide_action() mới. Tách riêng khỏi vật lý di chuyển.
func _tick_rl(delta: float) -> void:
	if rl == null or not active:
		return
	_rl_timer -= delta
	if _rl_timer > 0.0:
		return
	_rl_timer = RL_DECISION_INTERVAL
	var p = Global.player
	if not is_instance_valid(p) or not p.alive:
		return
	var p_total: float = float(p.hp) + float(p.shield)
	var dealt: float = maxf(0.0, _rl_prev_player_total - p_total) if _rl_prev_player_total >= 0.0 else 0.0
	var taken: float = maxf(0.0, _rl_prev_hp - hp) if _rl_prev_hp >= 0.0 else 0.0
	_rl_prev_player_total = p_total
	_rl_prev_hp = hp
	rl.reward_step(dealt, taken)
	var act: PackedFloat32Array = rl.decide_action()
	_rl_move = Vector2(act[rl.ACTION_MOVE_X], act[rl.ACTION_MOVE_Y])

func _on_attack_timer_timeout() -> void:
	if not alive or busy or not active:
		return
	var p = Global.player
	if not is_instance_valid(p) or not p.alive:
		attack_timer.start(0.7)
		return
	busy = true
	if pending_roar:
		pending_roar = false
		await _roar()
		if not alive:
			return
	var attack: String = _weighted_attack(_attack_pool(), _rl_pick_value())
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
		"ice_prison": await _atk_ice_prison()
		"lord_summon_all": await _atk_lord_summon_all()
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
	if kind == "lord":
		await _lord_ring_volleys()
		return
	_fire_ring(12, 0.0, Color(1.0, 0.7, 0.2))
	if phase >= 2:
		await get_tree().create_timer(0.35).timeout
		if not alive:
			return
		_fire_ring(12, PI / 12.0, Color(1.0, 0.7, 0.2))
	await get_tree().create_timer(0.3).timeout


## Dungeon Lord: nhiều vòng đạn liên tiếp, mỗi vòng lệch góc khác nhau (chu kỳ 0 / nửa khoảng / 1/4
## khoảng) nên lỗ hổng xoay vị trí qua từng vòng — phải di chuyển liên tục thay vì đứng 1 chỗ.
func _lord_ring_volleys() -> void:
	var volleys: int = int(LORD_RING_VOLLEYS[clampi(phase - 1, 0, LORD_RING_VOLLEYS.size() - 1)])
	var step: float = TAU / float(LORD_RING_COUNT)
	var offsets: Array = [0.0, step * 0.5, step * 0.25]
	for v in volleys:
		if not alive:
			return
		_fire_ring(LORD_RING_COUNT, float(offsets[v % offsets.size()]), Color(1.0, 0.7, 0.2))
		await get_tree().create_timer(LORD_RING_GAP).timeout


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
		# Necromancer ở biome Đầm Lầy -> triệu hồi "shaman" (KHÔNG dùng "archer", vốn
		# là quái tầm xa độc quyền biome 1, để không phá quy tắc không lẫn quái giữa biome).
		summon_requested.emit("shaman", global_position + Vector2.from_angle(ang) * 90.0)
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
	hz.radius = 70.0 * (LORD_AOE_MULT if kind == "lord" else 1.0)
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
	if arena_rect.size != Vector2.ZERO:
		# Trừ hao BODY_RADIUS để cả thân boss (không chỉ điểm gốc) ở lại trong phòng.
		var safe_rect: Rect2 = arena_rect.grow(-BODY_RADIUS)
		global_position = global_position.clamp(safe_rect.position, safe_rect.end)
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
	_spawn_ice_patch(global_position + charge_dir * 70.0, 85.0)
	await get_tree().create_timer(0.3).timeout


## Vùng băng đọng lại trên sàn sau đòn đánh (tạo "vùng cấm" tạm thời thay vì đánh 1 phát
## xong là hết) — sát thương nhẹ mỗi nhịp + làm chậm ai đứng trong, không cần telegraph vì
## đã đứng sau đòn gốc (người chơi đã thấy/né đòn gốc rồi mới đến lượt vùng này).
func _spawn_ice_patch(pos: Vector2, radius: float, duration: float = 2.5) -> void:
	var hz := Area2D.new()
	hz.set_script(BOSS_HAZARD)
	hz.damage = 4
	hz.tick_interval = 0.5
	hz.duration = duration
	hz.radius = radius
	hz.telegraph_time = 0.0
	hz.apply_slow = true
	hz.color = Color(0.5, 0.85, 1.0, 0.3)
	Global.world.add_child(hz)
	hz.global_position = pos


func _atk_frost_spike_field() -> void:
	var p = Global.player
	# Nhắm vào vị trí DỰ ĐOÁN (vị trí hiện tại + hướng di chuyển trong khoảng thời gian
	# telegraph 0.65s) thay vì vị trí đứng yên — buộc người chơi phải đọc hướng đi của mình
	# và né thật, không phải cứ đứng yên là tự động né được.
	var center: Vector2 = global_position
	if is_instance_valid(p):
		center = p.global_position + p.velocity * 0.65
	Global.sfx("slam")
	var is_lord: bool = kind == "lord"
	var n: int = 7 if is_lord else 5
	for i in n:
		var ang: float = TAU * float(i) / float(n) + randf() * 0.4
		var pos: Vector2 = center + Vector2.from_angle(ang) * randf_range(20.0, 150.0 if is_lord else 110.0)
		var hz := Area2D.new()
		hz.set_script(BOSS_HAZARD)
		hz.single_shot = true
		hz.damage = 18
		hz.radius = 34.0 * (LORD_AOE_MULT if is_lord else 1.0)
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
	_spawn_ice_patch(global_position, 150.0, 2.0)
	var n: int = 3 if phase >= 3 else 2 # tăng theo pha, khớp cách Warden/Necromancer đã làm
	for i in n:
		var ang: float = TAU * float(i) / float(n) + randf() * 0.6
		# Frost ở biome Băng Giá -> triệu hồi "frost_zombie" (KHÔNG dùng "slime", vốn là
		# quái cơ bản độc quyền biome 1, để không phá quy tắc không lẫn quái giữa biome).
		summon_requested.emit("frost_zombie", global_position + Vector2.from_angle(ang) * 100.0)
	await get_tree().create_timer(0.5).timeout


## "Giam Băng" — đòn skillshot chính xác: nhắm thẳng vị trí Player NGAY LÚC BẮT ĐẦU
## telegraph (không đuổi theo sau đó), trúng thì Choáng + sát thương nặng. Khác hẳn các
## đòn AoE còn lại của Frost (vốn đều là tỏa tròn/quạt quanh thân boss) — rủi ro/thưởng
## cao: dễ đọc hướng nhắm nhưng nếu không né kịp thì bị phạt nặng.
func _atk_ice_prison() -> void:
	var p = Global.player
	# Nhắm vào vị trí Player NGAY LÚC BẮT ĐẦU telegraph (không đuổi theo sau đó) — người
	# chơi thấy vòng tròn hiện ra đúng dưới chân mình thì biết phải bước ra trước khi hết giờ.
	var target_pos: Vector2 = p.global_position if is_instance_valid(p) else global_position
	Global.sfx("boss_charge")
	var hz := Area2D.new()
	hz.set_script(BOSS_HAZARD)
	hz.single_shot = true
	hz.damage = 24
	hz.radius = 46.0 * (LORD_AOE_MULT if kind == "lord" else 1.0)
	hz.telegraph_time = 0.85 * _speed_mult()
	hz.apply_stun_duration = 1.3
	hz.color = Color(0.6, 0.95, 1.0, 0.6)
	Global.world.add_child(hz)
	hz.global_position = target_pos
	if kind == "lord":
		# Cụm 3 vòng: dưới chân + 2 bên (vuông góc hướng boss -> Player) — chặn đường né ngang.
		var side: Vector2 = (target_pos - global_position).normalized().orthogonal() * 120.0
		for sgn in [-1.0, 1.0]:
			var hz2 := Area2D.new()
			hz2.set_script(BOSS_HAZARD)
			hz2.single_shot = true
			hz2.damage = 24
			hz2.radius = 46.0 * LORD_AOE_MULT
			hz2.telegraph_time = 0.85 * _speed_mult()
			hz2.apply_stun_duration = 1.3
			hz2.color = Color(0.6, 0.95, 1.0, 0.6)
			Global.world.add_child(hz2)
			hz2.global_position = target_pos + side * sgn
	await get_tree().create_timer(0.85 * _speed_mult() + 0.2).timeout


# ==============================================================================
# ĐÒN ĐỘC QUYỀN DUNGEON LORD — "Phán Quyết" (pha 4, ultimate)
# ==============================================================================
## "Phán Quyết" — nay là 1 CHUỖI COMBO 4 nhịp thay vì 1 phát nổ tĩnh đơn điệu:
## (1) đòn giả (false-telegraph, không gây sát thương) nhử người chơi né hụt sớm ->
## (2) đòn nổ lớn thật, telegraph dài, tâm cố định lúc bắt đầu -> (3)+(4) 2 đòn truy đuổi
## nhỏ hơn nhưng NHANH hơn, mỗi đòn nhắm lại đúng vị trí Player lúc đó -> buộc phải né
## liên tục chứ không phải "thấy vòng tròn, bước ra 1 lần là xong" -> kết bằng Ring dồn dập.
func _atk_judgement() -> void:
	var p = Global.player
	Global.message.emit("Dungeon Lord is charging", Color(1.0, 0.2, 0.2))
	Global.sfx("roar")
	# (1) Đòn giả: lóe sáng nhanh, KHÔNG spawn hazard — chỉ để nhử phản xạ né sớm của người chơi.
	await _telegraph("flash", 0.4)
	if not alive:
		return
	# (2) Đòn nổ lớn thật.
	Global.shake(0.3, 1.5)
	var center: Vector2 = p.global_position if is_instance_valid(p) else global_position
	var hz := Area2D.new()
	hz.set_script(BOSS_HAZARD)
	hz.single_shot = true
	hz.damage = LORD_JUDGE_DAMAGE
	hz.radius = LORD_JUDGE_RADIUS
	hz.telegraph_time = LORD_JUDGE_TELEGRAPH
	hz.color = Color(1.0, 0.15, 0.15, 0.5)
	# Vùng nổ BÁM theo Player trong LORD_JUDGE_FOLLOW giây đầu rồi mới chốt vị trí.
	hz.follow_target = p if is_instance_valid(p) else null
	hz.follow_time = LORD_JUDGE_FOLLOW
	Global.world.add_child(hz)
	hz.global_position = center
	await get_tree().create_timer(1.5).timeout
	if not alive:
		return
	# (3)+(4) 2 đòn truy đuổi nhanh, mỗi đòn chốt lại đúng vị trí Player NGAY lúc đó.
	for i in LORD_JUDGE_CHASES:
		if not alive:
			return
		# Đón đầu theo vận tốc Player (không chỉ vị trí hiện tại)
		var chase_pos: Vector2 = global_position
		if is_instance_valid(p):
			chase_pos = p.global_position + p.velocity * LORD_JUDGE_CHASE_LEAD
		var hz2 := Area2D.new()
		hz2.set_script(BOSS_HAZARD)
		hz2.single_shot = true
		hz2.damage = LORD_JUDGE_CHASE_DAMAGE
		hz2.radius = LORD_JUDGE_CHASE_RADIUS
		hz2.telegraph_time = LORD_JUDGE_CHASE_TELEGRAPH
		hz2.color = Color(1.0, 0.25, 0.1, 0.55)
		Global.world.add_child(hz2)
		hz2.global_position = chase_pos
		await get_tree().create_timer(0.6).timeout
	if not alive:
		return
	# Kết liễu: Ring dồn dập, nối liền không khoảng nghỉ — đúng chất "khoảnh khắc chung kết".
	for r in LORD_JUDGE_FINAL_RINGS:
		if not alive:
			return
		_fire_ring(LORD_JUDGE_FINAL_COUNT, (PI / float(LORD_JUDGE_FINAL_COUNT)) * float(r), Color(1.0, 0.3, 0.2))
		await get_tree().create_timer(LORD_RING_GAP).timeout


## "Tổng Triệu Hồi" — đòn độc quyền Dungeon Lord (pha 4): triệu hồi cùng lúc 1 quái mỗi
## biome (slime/chort/frost_tiny) thay vì chỉ lặp lại đúng 1 loại như các boss khác — biểu
## tượng cho việc Lord nắm quyền năng của cả 3 vùng, khác hẳn mọi đòn triệu hồi đã gặp trước đó.
func _atk_lord_summon_all() -> void:
	await _telegraph("flash", 0.6 * _speed_mult())
	if not alive:
		return
	Global.sfx("door")
	var kinds: Array = ["slime", "chort", "frost_tiny"]
	for i in kinds.size():
		var ang: float = TAU * float(i) / float(kinds.size()) + randf() * 0.4
		summon_requested.emit(kinds[i], global_position + Vector2.from_angle(ang) * 100.0)
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
	if sunder_stacks > 0:
		sunder_timer -= delta
		if sunder_timer <= 0.0:
			sunder_stacks = 0
	if elements.is_active():
		elements.tick(delta)
	if slow_timer > 0.0:
		slow_timer = maxf(0.0, slow_timer - delta)
	_tick_rl(delta)
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
		var chase_speed: float = 55.0 + 20.0 * float(phase)
		if kind == "frost" and frost_enraged:
			chase_speed += 35.0
		var chase_dir: Vector2 = (p.global_position - global_position).normalized()
		var steer: Vector2 = chase_dir
		if _rl_move.length() > 0.05:
			var blend: float = _rl_move_blend()
			steer = (chase_dir * (1.0 - blend) + _rl_move.normalized() * blend).normalized()
		velocity = steer * chase_speed * _slow_factor()
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

	var actual_damage = Global.armored_damage(amount, current_armor)
	if sunder_stacks > 0:
		actual_damage = int(float(actual_damage) * (1.0 + SUNDER_PER_STACK * float(sunder_stacks)))
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
	if kind == "frost" and not frost_enraged and ratio <= 0.25:
		frost_enraged = true
		Global.message.emit("%s enrages" % BOSS_NAME, Color(0.4, 0.9, 1.0))
		Global.shake(0.6, 0.4)
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
	Global.record_kill()
	Global.record_boss_kill(kind)
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
