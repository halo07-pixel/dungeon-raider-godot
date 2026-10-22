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
const WarnFx = preload("res://scripts/skill_warn_fx.gd")
const SkillUpgrades = preload("res://scripts/skill_upgrades.gd")

signal skill_used(skill_id: String)
## Hồi chiêu xong (sẵn sàng dùng lại).
signal skill_ready(skill_id: String)
## Kỹ năng có thời lượng (vd Overdrive) vừa hết tác dụng.
signal skill_ended(skill_id: String)

const SKILLS: Dictionary = {
	# Kỹ năng khởi đầu
	"overdrive": {"name": "Overdrive", "cooldown": 12.0, "desc": "[Q] Attack much faster for a few seconds, and your shots pierce 1 more enemy."},
	"slam": {"name": "Slam", "cooldown": 6.0, "desc": "[Q] Smash the ground, hurting, pushing back and briefly stunning nearby enemies."},
	# Kỹ năng tiến hoá (Ranger+ / Brawler+)
	"barrage": {"name": "Barrage", "cooldown": 7.0, "desc": "[Q] Fire 3 fan volleys of bullets."},
	"shockwave": {"name": "Shockwave", "cooldown": 9.0, "desc": "[Q] Blast enemies away and clear bullets."},
	# Mage / Mage+
	"gravity_well": {"name": "Gravity Well", "cooldown": 8.0, "desc": "[Q] Place a well at your cursor: it pulls enemies in, slows and damages them for a few seconds."},
	"meteor_storm": {"name": "Meteor Storm", "cooldown": 10.0, "desc": "[Q] Mark the ground at your cursor; meteors crash down there shortly after."},
	# Rogue / Rogue+
	"shadow_dash": {"name": "Shadow Dash", "cooldown": 6.0, "desc": "[Q] Dash through enemies, cutting everything in your path. Your next hit is a guaranteed critical."},
	# Summoner / Summoner+
	"summon": {"name": "Summon", "cooldown": 6.0, "desc": "[Q] Call a minion that fights for you: Spirit (melee), Wisp (ranged), Guardian (blocks bullets), in turn. Up to 2 at once."},
	"legion": {"name": "Legion", "cooldown": 12.0, "desc": "[Q] Call 3 Spitelings that rush enemies and explode when their time runs out."},
	"shadow_rush": {"name": "Shadow Rush", "cooldown": 8.0, "desc": "[Q] Dash far through enemies, making them bleed. Your next 3 hits are guaranteed critical."},
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
	var m: float = SkillUpgrades.mod_mult(skill_id, Global.skill_upgrades_taken, key)
	if key == "dmg_mult": # nút meta Honed Technique áp cho mọi kỹ năng
		m *= Global.SkillTree.skill_damage_mult(Global.upgrades)
	if key == "radius_mult" and Global.buff_stack("buff_skill_overload") > 0:
		m *= OVERLOAD_RADIUS_MULT
	return m

func _effective_cooldown() -> float:
	var haste: float = float(player.skill_haste()) if is_instance_valid(player) else 0.0
	return maxf(1.0, (base_cooldown + _add("cooldown_add")) * Global.SkillTree.skill_cooldown_mult(Global.upgrades) / (1.0 + haste))

## Hoàn bớt hồi chiêu (buff Overflow). Tổng hoàn mỗi lần tung tối đa nửa thời gian hồi để không thể tự reset vô hạn.
var _refunded: float = 0.0
func refund_cooldown(seconds: float) -> void:
	if cooldown_left <= 0.0:
		return
	var room: float = maxf(0.0, cooldown_total * 0.5 - _refunded)
	var give: float = minf(seconds, room)
	_refunded += give
	cooldown_left = maxf(0.0, cooldown_left - give)

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
	_refunded = 0.0
	if randf() < float(player.spellburst_chance()):
		cooldown_left = 0.0 # Spellburst: lần tung miễn phí
		Global.float_text(player.global_position + Vector2(0, -40), "SPELLBURST", Color(0.8, 0.6, 1.0), 18)
	skill_used.emit(skill_id)
	match skill_id:
		"overdrive": _overdrive()
		"slam": _slam()
		"barrage": _barrage()
		"shockwave": _shockwave()
		"gravity_well": _gravity_well()
		"meteor_storm": _meteor_storm()
		"shadow_dash": _shadow_dash(false)
		"shadow_rush": _shadow_dash(true)
		"summon": _summon()
		"legion": _legion()
	return true

## Dọn hiệu ứng kéo dài khi Player chết / node bị gỡ để không để lại buff vĩnh viễn trên Player.
func _exit_tree() -> void:
	if active_left > 0.0:
		active_left = 0.0
		_end_active()

func _end_active() -> void:
	if skill_id == "overdrive" and is_instance_valid(player):
		player.skill_attack_cd_mult = 1.0
		player.skill_pierce_add = 0
	skill_ended.emit(skill_id)

func _dmg_mult() -> float:
	return float(player._secondary_dmg_mult()) * (1.0 + float(player.skill_power()))

# ------------------------------------------------------------------ Ranger+: Barrage
const OVERLOAD_RADIUS_MULT: float = 1.2

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
const SLAM_BASE_STUN: float = 0.4

func _slam() -> void:
	_blast(SLAM_RADIUS, SLAM_DMG_BASE, SLAM_DMG_PER_FLOOR, SLAM_KNOCK, false, Color(1.0, 0.85, 0.55), 16, 0.5, SLAM_BASE_STUN)

## Vụ nổ quanh Player: gây sát thương + đẩy lùi quái/boss trong bán kính; tuỳ chọn xoá đạn địch.
func _blast(radius: float, dmg_base: float, dmg_per_floor: float, knock: float, clear_bullets: bool, color: Color, burst_n: int, shake: float, base_stun: float = 0.0) -> void:
	var origin: Vector2 = player.global_position
	radius *= _mult("radius_mult") # nâng cấp trong run
	var dmg: int = maxi(1, int((dmg_base + dmg_per_floor * float(Global.floor_num)) * _dmg_mult() * _mult("dmg_mult")))
	var stun: float = _add("stun_add") + base_stun
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
	player.skill_pierce_add = 1 # đạn xuyên thêm 1 quái trong lúc Overdrive
	Global.burst(player.global_position, Color(1.0, 0.8, 0.3), 14, 200.0, 1.4)
	Global.shake(0.3, 0.2)
	Global.sfx("barrage_cast")

# ------------------------------------------------------------------ Dùng chung cho kỹ năng lướt / rơi từ trên
## Điểm đến khi lướt `dist` px theo hướng ngắm: raycast với tường, dừng cách tường DASH_WALL_MARGIN px.
const DASH_WALL_MARGIN: float = 16.0

func _dash_destination(dist: float) -> Vector2:
	var from: Vector2 = player.global_position
	var to: Vector2 = from + player.aim_dir * dist
	var q := PhysicsRayQueryParameters2D.create(from, to, Global.L_WORLD)
	var hit: Dictionary = player.get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return to
	var travel: float = maxf(0.0, from.distance_to(hit["position"]) - DASH_WALL_MARGIN)
	return from + player.aim_dir * travel

## Chuyển Player tới `dest` ngay lập tức, bất tử `iframes` giây, rải hiệu ứng tàn ảnh dọc đường đi.
func _relocate_player(dest: Vector2, iframes: float, color: Color) -> void:
	var from: Vector2 = player.global_position
	for i in 4:
		Global.burst(from.lerp(dest, float(i) / 3.0), color, 5, 60.0, 1.2)
	player.global_position = dest
	if player.hurt_timer.time_left < iframes:
		player.hurt_timer.start(iframes)

## Sát thương + đẩy lùi quái/boss trong bán kính quanh `origin` (không nhất thiết là vị trí Player).
func _damage_area(origin: Vector2, radius: float, dmg: int, knock: float, slow: float) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.alive and e.global_position.distance_to(origin) <= radius:
			e.take_damage(dmg, origin, knock)
			if slow > 0.0 and e.alive and e.has_method("apply_status"):
				e.apply_status("slow", slow)
			Global.on_secondary_hit(e, dmg, false)
	for b in get_tree().get_nodes_in_group("boss"):
		if is_instance_valid(b) and b.alive and b.global_position.distance_to(origin) <= radius + 20.0:
			b.take_damage(dmg, origin, 0.0)
			Global.on_secondary_hit(b, dmg, false)

func _ring_fx(pos: Vector2, radius: float, color: Color, duration: float = 0.35) -> void:
	var fx := Node2D.new()
	fx.set_script(RingFx)
	fx.max_radius = radius
	fx.color = color
	fx.duration = duration
	Global.world.add_child(fx)
	fx.global_position = pos

# ------------------------------------------------------------------ Mage: Gravity Well (kỹ năng khởi đầu)
const GravityWell = preload("res://scripts/gravity_well.gd")
const WELL_RADIUS: float = 130.0
const WELL_DURATION: float = 3.0
const WELL_DMG_BASE: float = 6.0
const WELL_DMG_PER_FLOOR: float = 0.6
const WELL_MAX_RANGE: float = 380.0
const WELL_COLOR: Color = Color(0.6, 0.4, 1.0)

func _gravity_well() -> void:
	var to: Vector2 = player.get_global_mouse_position() - player.global_position
	var pos: Vector2 = player.global_position + to.limit_length(WELL_MAX_RANGE)
	var well := Node2D.new()
	well.set_script(GravityWell)
	well.radius = WELL_RADIUS * _mult("radius_mult")
	well.duration = WELL_DURATION + _add("duration_add")
	well.tick_damage = maxi(1, int((WELL_DMG_BASE + WELL_DMG_PER_FLOOR * float(Global.floor_num)) * _dmg_mult() * _mult("dmg_mult")))
	well.color = WELL_COLOR
	Global.world.add_child(well)
	well.global_position = pos
	_ring_fx(pos, well.radius, WELL_COLOR, 0.4)
	Global.burst(pos, WELL_COLOR, 14, 200.0, 1.4)
	Global.shake(0.15, 0.12)
	Global.sfx("phase_step")

# ------------------------------------------------------------------ Mage+: Meteor Storm
const METEOR_COUNT: int = 3
const METEOR_DELAY: float = 0.8
const METEOR_GAP: float = 0.3
const METEOR_RADIUS: float = 80.0
const METEOR_SCATTER: float = 90.0
const METEOR_KNOCK: float = 300.0
const METEOR_DMG_BASE: float = 26.0
const METEOR_DMG_PER_FLOOR: float = 2.5
const METEOR_MAX_RANGE: float = 460.0   # vùng đánh dấu không xa hơn thế so với Player
const METEOR_COLOR: Color = Color(1.0, 0.45, 0.15)

## Điểm đánh dấu: vị trí con trỏ, giới hạn METEOR_MAX_RANGE quanh Player.
func _target_point() -> Vector2:
	var to: Vector2 = player.get_global_mouse_position() - player.global_position
	return player.global_position + to.limit_length(METEOR_MAX_RANGE)

func _meteor_storm() -> void:
	var center: Vector2 = _target_point()
	var count: int = METEOR_COUNT + int(_add("meteors_add"))
	var radius: float = METEOR_RADIUS * _mult("radius_mult")
	Global.sfx("meteor_warn")
	for i in count:
		var pos: Vector2 = center if i == 0 else center + Vector2.from_angle(randf() * TAU) * randf_range(30.0, METEOR_SCATTER)
		var delay: float = METEOR_DELAY + float(i) * METEOR_GAP
		var warn := Node2D.new()
		warn.set_script(WarnFx)
		warn.radius = radius
		warn.duration = delay
		warn.color = METEOR_COLOR
		Global.world.add_child(warn)
		warn.global_position = pos
		_meteor_land(pos, radius, delay)

func _meteor_land(pos: Vector2, radius: float, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if not is_instance_valid(player) or not player.alive or not is_inside_tree():
		return
	var dmg: int = maxi(1, int((METEOR_DMG_BASE + METEOR_DMG_PER_FLOOR * float(Global.floor_num)) * _dmg_mult() * _mult("dmg_mult")))
	_damage_area(pos, radius, dmg, METEOR_KNOCK, 0.0)
	_ring_fx(pos, radius, METEOR_COLOR, 0.4)
	Global.burst(pos, METEOR_COLOR, 20, 260.0, 2.0)
	Global.shake(0.4, 0.25)
	Global.sfx("meteor_impact")

# ------------------------------------------------------------------ Summoner: Summon / Summoner+: Legion
const MinionScript = preload("res://scripts/minion.gd")
const SUMMON_ORDER: Array = ["spirit", "wisp", "guardian"]
const LEGION_COUNT: int = 3
var _summon_idx: int = 0

## Lính tự triệu hồi (đánh dấu meta "summoned") — không tính lính do Tome tạo.
func _my_minions(kinds: Array) -> Array:
	var out: Array = []
	for m in get_tree().get_nodes_in_group("minions"):
		if is_instance_valid(m) and not m.is_queued_for_deletion() and m.owner_player == player and m.has_meta("summoned") and kinds.has(m.kind):
			out.append(m)
	return out

func _summon_power() -> float:
	return _dmg_mult() * _mult("dmg_mult") * float(player.minion_dmg_mult())

func _summon() -> void:
	var kind: String = String(SUMMON_ORDER[_summon_idx % SUMMON_ORDER.size()])
	_summon_idx += 1
	var m: Node = MinionScript.spawn(player, kind, player.global_position + player.aim_dir * 30.0, _summon_power(), _mult("life_mult"), _summon_idx % 3)
	m.set_meta("summoned", true)
	var cap: int = _minion_cap() + int(_add("minions_add"))
	var mine: Array = _my_minions(SUMMON_ORDER)
	while mine.size() > cap:
		var old: Node = mine.pop_front()
		old.queue_free()
	_ring_fx(player.global_position, 46.0, m.cfg["color"], 0.35)
	Global.burst(player.global_position, m.cfg["color"], 10, 150.0, 1.2)
	Global.sfx("barrage_cast", 1.1)

func _minion_cap() -> int:
	return int(player.PASSIVE_SUMMONER_MINIONS) if Global.current_class == "summoner" else 1

func _legion() -> void:
	var count: int = LEGION_COUNT + int(_add("minions_add"))
	for i in count:
		var ang: float = TAU * float(i) / float(count)
		var m: Node = MinionScript.spawn(player, "mini", player.global_position + Vector2.from_angle(ang) * 26.0, _summon_power(), _mult("life_mult"), i)
		m.set_meta("summoned", true)
	var mine: Array = _my_minions(["mini"])
	while mine.size() > count * 2:
		var old: Node = mine.pop_front()
		old.queue_free()
	_ring_fx(player.global_position, 60.0, Color(1.0, 0.55, 0.4), 0.4)
	Global.shake(0.15, 0.12)
	Global.sfx("barrage_cast", 0.8)

# ------------------------------------------------------------------ Rogue: Shadow Dash / Rogue+: Shadow Rush
const SHADOW_DIST: float = 160.0
const RUSH_DIST: float = 230.0
const SHADOW_IFRAMES: float = 0.3
const SHADOW_WIDTH: float = 24.0        # nửa bề rộng "lưỡi" quét dọc đường lướt
const SHADOW_KNOCK: float = 150.0
const SHADOW_DMG_BASE: float = 14.0
const SHADOW_DMG_PER_FLOOR: float = 1.2
const RUSH_DMG_MULT: float = 1.5
const DASH_CRIT_CHARGES: int = 1
const RUSH_CRIT_CHARGES: int = 3
const SHADOW_COLOR: Color = Color(0.55, 0.9, 0.55)

func _shadow_dash(rush: bool) -> void:
	var from: Vector2 = player.global_position
	var dist: float = (RUSH_DIST if rush else SHADOW_DIST) + _add("dist_add")
	var dest: Vector2 = _dash_destination(dist)
	_relocate_player(dest, SHADOW_IFRAMES, SHADOW_COLOR)
	var dmg: int = maxi(1, int((SHADOW_DMG_BASE + SHADOW_DMG_PER_FLOOR * float(Global.floor_num)) * _dmg_mult() * _mult("dmg_mult") * (RUSH_DMG_MULT if rush else 1.0)))
	_damage_line(from, dest, dmg, rush)
	player.grant_skill_crits((RUSH_CRIT_CHARGES if rush else DASH_CRIT_CHARGES) + int(_add("crit_add")))
	Global.sfx("shadow_dash", 0.85 if rush else 1.0)
	Global.shake(0.15, 0.1)

## Sát thương mọi quái/boss nằm trong SHADOW_WIDTH px quanh đoạn thẳng a->b (rush: kèm chảy máu).
func _damage_line(a: Vector2, b: Vector2, dmg: int, bleed: bool) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.alive and _dist_to_segment(e.global_position, a, b) <= SHADOW_WIDTH + float(e.data.get("radius", 12.0)):
			e.take_damage(dmg, a, SHADOW_KNOCK)
			if bleed and e.alive and e.has_method("apply_status"):
				e.apply_status("bleed", 0.0)
			Global.burst(e.global_position, SHADOW_COLOR, 6, 140.0, 1.2)
			Global.on_secondary_hit(e, dmg, false)
	for bs in get_tree().get_nodes_in_group("boss"):
		if is_instance_valid(bs) and bs.alive and _dist_to_segment(bs.global_position, a, b) <= SHADOW_WIDTH + 34.0:
			bs.take_damage(dmg, a, 0.0)
			Global.on_secondary_hit(bs, dmg, false)

static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len2: float = ab.length_squared()
	if len2 < 0.001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
