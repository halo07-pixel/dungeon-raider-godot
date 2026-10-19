extends Node
## Kỹ năng riêng của class, kích hoạt bằng phím "skill" (Q). Node con của Player;
## tách khỏi _physics_process của Player. Player chỉ cần: aim_dir, global_position, alive, rolling,
## _secondary_dmg_mult(), skill_attack_cd_mult. HUD đọc cooldown_left / cooldown_total / skill_name /
## active_left qua duck typing; âm thanh/UI nghe signal skill_used, skill_ready, skill_ended.
##
## Mỗi class có kỹ năng KHỞI ĐẦU (Global.classes[cid]["skill"]) ngay từ đầu; khi tiến hoá
## (MetaProgress.EVOLUTIONS) kỹ năng được thay bằng bản mạnh hơn. Thêm kỹ năng = thêm 1 dòng vào SKILLS
## + 1 hàm xử lý trong try_activate().

const BULLET = preload("res://scenes/bullet.tscn")
const RingFx = preload("res://scripts/skill_ring_fx.gd")
const SkillUpgrades = preload("res://scripts/skill_upgrades.gd")

signal skill_used(skill_id: String)
## Hồi chiêu xong (sẵn sàng dùng lại).
signal skill_ready(skill_id: String)
## Kỹ năng có thời lượng (vd Overdrive) vừa hết tác dụng.
signal skill_ended(skill_id: String)

const SKILLS: Dictionary = {
	# Kỹ năng khởi đầu
	"overdrive": {"name": "Overdrive", "cooldown": 12.0, "desc": "[Q] Attack much faster for a few seconds."},
	"slam": {"name": "Slam", "cooldown": 6.0, "desc": "[Q] Smash the ground, hurting and pushing back nearby enemies."},
	# Kỹ năng tiến hoá (Ranger+ / Brawler+)
	"barrage": {"name": "Barrage", "cooldown": 7.0, "desc": "[Q] Fire 3 fan volleys of bullets."},
	"shockwave": {"name": "Shockwave", "cooldown": 9.0, "desc": "[Q] Blast enemies away and clear bullets."},
}

var player: Node = null
var skill_id: String = ""
var skill_name: String = ""
var cooldown_total: float = 1.0
var base_cooldown: float = 1.0
var cooldown_left: float = 0.0
## Thời gian còn lại của hiệu ứng kéo dài (0 = không có hiệu ứng đang chạy).
var active_left: float = 0.0

func setup(p_player: Node, p_skill_id: String) -> void:
	player = p_player
	skill_id = p_skill_id
	var cfg: Dictionary = SKILLS.get(p_skill_id, {})
	skill_name = String(cfg.get("name", ""))
	base_cooldown = float(cfg.get("cooldown", 8.0))
	cooldown_total = _effective_cooldown()

## Cộng / nhân dồn các nâng cấp trong run (Global.skill_upgrades_taken) áp cho kỹ năng này.
func _add(key: String) -> float:
	return SkillUpgrades.mod_add(skill_id, Global.skill_upgrades_taken, key)

func _mult(key: String) -> float:
	return SkillUpgrades.mod_mult(skill_id, Global.skill_upgrades_taken, key)

func _effective_cooldown() -> float:
	return maxf(1.0, base_cooldown + _add("cooldown_add"))

func is_ready() -> bool:
	return cooldown_left <= 0.0

func _physics_process(delta: float) -> void:
	var was_cooling: bool = cooldown_left > 0.0
	cooldown_left = maxf(0.0, cooldown_left - delta)
	if was_cooling and cooldown_left <= 0.0:
		skill_ready.emit(skill_id)
	if active_left > 0.0:
		active_left = maxf(0.0, active_left - delta)
		if active_left <= 0.0:
			_end_active()
	if not is_instance_valid(player) or not player.alive:
		if active_left > 0.0:
			active_left = 0.0
			_end_active()
		return
	if Input.is_action_just_pressed("skill"):
		try_activate()

func try_activate() -> bool:
	if skill_id == "" or not is_ready() or not is_instance_valid(player) or not player.alive:
		return false
	if player.rolling:
		return false
	cooldown_total = _effective_cooldown()
	cooldown_left = cooldown_total
	skill_used.emit(skill_id)
	match skill_id:
		"overdrive": _overdrive()
		"slam": _slam()
		"barrage": _barrage()
		"shockwave": _shockwave()
	return true

## Dọn hiệu ứng kéo dài khi Player chết / node bị gỡ để không để lại buff vĩnh viễn trên Player.
func _exit_tree() -> void:
	if active_left > 0.0:
		active_left = 0.0
		_end_active()

func _end_active() -> void:
	if skill_id == "overdrive" and is_instance_valid(player):
		player.skill_attack_cd_mult = 1.0
	skill_ended.emit(skill_id)

func _dmg_mult() -> float:
	return float(player._secondary_dmg_mult())

# ------------------------------------------------------------------ Ranger+: Barrage
const BARRAGE_VOLLEYS: int = 3
const BARRAGE_BULLETS: int = 9
const BARRAGE_FAN_DEG: float = 72.0
const BARRAGE_GAP: float = 0.12

const BARRAGE_PITCH: Array = [1.0, 1.1, 0.92] # cao độ từng loạt đạn khác nhau để không nghe lặp

func _barrage() -> void:
	Global.shake(0.35, 0.3)
	Global.sfx("barrage_cast")
	var volleys: int = BARRAGE_VOLLEYS + int(_add("volleys_add"))
	var bullets: int = BARRAGE_BULLETS + int(_add("bullets_add"))
	for v in volleys:
		if not is_instance_valid(player) or not player.alive:
			return
		_fire_volley(float(BARRAGE_PITCH[v % BARRAGE_PITCH.size()]), bullets)
		await get_tree().create_timer(BARRAGE_GAP).timeout

func _fire_volley(pitch: float = 1.0, bullets: int = BARRAGE_BULLETS) -> void:
	var dmg: int = maxi(1, int((8.0 + 1.2 * float(Global.floor_num)) * _dmg_mult() * _mult("dmg_mult")))
	var base: float = player.aim_dir.angle()
	var fan: float = deg_to_rad(BARRAGE_FAN_DEG)
	for i in bullets:
		var off: float = lerpf(-fan * 0.5, fan * 0.5, float(i) / float(bullets - 1))
		var b = BULLET.instantiate()
		b.setup(true, Vector2.from_angle(base + off), dmg, 680.0, 0.9, Color(0.5, 0.9, 1.0), 5.0)
		Global.world.add_child(b)
		b.global_position = player.global_position + Vector2.from_angle(base + off) * 22.0
	Global.sfx("barrage_volley", pitch)
	Global.burst(player.global_position + player.aim_dir * 26.0, Color(0.5, 0.9, 1.0), 6, 120.0, 1.2)

# ------------------------------------------------------------------ Brawler+: Shockwave
const SHOCK_RADIUS: float = 190.0
const SHOCK_KNOCK: float = 650.0
const SHOCK_DMG_BASE: float = 30.0
const SHOCK_DMG_PER_FLOOR: float = 3.0

func _shockwave() -> void:
	_blast(SHOCK_RADIUS, SHOCK_DMG_BASE, SHOCK_DMG_PER_FLOOR, SHOCK_KNOCK, true, Color(1.0, 0.75, 0.35), 28, 0.8)

# ------------------------------------------------------------------ Brawler: Slam (kỹ năng khởi đầu)
const SLAM_RADIUS: float = 120.0
const SLAM_KNOCK: float = 420.0
const SLAM_DMG_BASE: float = 16.0
const SLAM_DMG_PER_FLOOR: float = 1.5

func _slam() -> void:
	_blast(SLAM_RADIUS, SLAM_DMG_BASE, SLAM_DMG_PER_FLOOR, SLAM_KNOCK, false, Color(1.0, 0.85, 0.55), 16, 0.5)

## Vụ nổ quanh Player: gây sát thương + đẩy lùi quái/boss trong bán kính; tuỳ chọn xoá đạn địch.
func _blast(radius: float, dmg_base: float, dmg_per_floor: float, knock: float, clear_bullets: bool, color: Color, burst_n: int, shake: float) -> void:
	var origin: Vector2 = player.global_position
	radius *= _mult("radius_mult") # nâng cấp trong run
	var dmg: int = maxi(1, int((dmg_base + dmg_per_floor * float(Global.floor_num)) * _dmg_mult() * _mult("dmg_mult")))
	var stun: float = _add("stun_add")
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.alive and e.global_position.distance_to(origin) <= radius:
			e.take_damage(dmg, origin, knock)
			if stun > 0.0 and e.alive and e.has_method("apply_status"):
				e.apply_status("stun", stun)
			Global.on_secondary_hit(e, dmg, false)
	for b in get_tree().get_nodes_in_group("boss"):
		if is_instance_valid(b) and b.alive and b.global_position.distance_to(origin) <= radius + 20.0:
			b.take_damage(dmg, origin, 0.0)
			Global.on_secondary_hit(b, dmg, false)
	if clear_bullets:
		for eb in get_tree().get_nodes_in_group("enemy_bullets"):
			if is_instance_valid(eb) and eb.global_position.distance_to(origin) <= radius + 10.0:
				eb.queue_free()
	var fx := Node2D.new()
	fx.set_script(RingFx)
	fx.max_radius = radius
	fx.color = color
	Global.world.add_child(fx)
	fx.global_position = origin
	Global.burst(origin, color, burst_n, 320.0, 2.0)
	Global.shake(shake, 0.3)
	Global.sfx("shockwave")

# ------------------------------------------------------------------ Ranger: Overdrive (kỹ năng khởi đầu)
const OVERDRIVE_DURATION: float = 4.0
## Hệ số nhân thời gian hồi đòn đánh trong lúc Overdrive (0.5 = đánh nhanh gấp đôi).
const OVERDRIVE_CD_MULT: float = 0.5

func _overdrive() -> void:
	active_left = OVERDRIVE_DURATION + _add("duration_add")
	player.skill_attack_cd_mult = OVERDRIVE_CD_MULT * _mult("attack_cd_mult")
	Global.burst(player.global_position, Color(1.0, 0.8, 0.3), 14, 200.0, 1.4)
	Global.shake(0.3, 0.2)
	Global.sfx("barrage_cast")
