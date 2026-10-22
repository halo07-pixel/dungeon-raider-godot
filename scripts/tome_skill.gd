extends Node
## Ô kỹ năng PHỤ ("Tome"): kỹ năng không thuộc class, nhặt được trong ván, bấm phím "tome" (F). Node con của Player,
## chạy song song với ClassSkill (Q). Cùng giao diện duck-typing với ClassSkill (skill_id, skill_name, cooldown_left,
## cooldown_total, is_ready()) nên HUD/Sigil/buff dùng chung được. Mỗi Tome = 1 dòng TOMES + 1 hàm _cast_<id>.

const MinionScript = preload("res://scripts/minion.gd")
const GravityWell = preload("res://scripts/gravity_well.gd")
const RingFx = preload("res://scripts/skill_ring_fx.gd")
const Sigils = preload("res://scripts/sigils.gd")

signal skill_used(skill_id: String)
signal skill_ready(skill_id: String)

const TOMES: Dictionary = {
	"arc_turret": {"name": "Arc Turret", "cooldown": 18.0, "desc": "Deploy a turret at your cursor that shoots the nearest enemy for 10s."},
	"spirit_pact": {"name": "Spirit Pact", "cooldown": 16.0, "desc": "Summon 2 Spirits that chase and slash enemies for 10s."},
	"frost_nova": {"name": "Frost Nova", "cooldown": 11.0, "desc": "Freeze the area around you: damages, slows and briefly stuns enemies."},
	"blade_dance": {"name": "Blade Dance", "cooldown": 14.0, "desc": "3 blades orbit you for 6s, cutting anything they touch."},
	"mending_totem": {"name": "Mending Totem", "cooldown": 28.0, "desc": "Plant a totem that heals you while you stand near it for 8s."},
	"black_hole": {"name": "Black Hole", "cooldown": 20.0, "desc": "Drag enemies into a black hole at your cursor; it explodes when it collapses."},
	"storm_bolt": {"name": "Storm Bolt", "cooldown": 8.0, "desc": "Lightning strikes the enemy nearest your cursor and jumps between up to 5 enemies."},
	"ward_barrier": {"name": "Ward Barrier", "cooldown": 20.0, "desc": "Raise a barrier at your cursor that destroys enemy bullets for 6s."},
}
const ORDER: Array = ["arc_turret", "spirit_pact", "frost_nova", "blade_dance", "mending_totem", "black_hole", "storm_bolt", "ward_barrier"]

const PLACE_RANGE: float = 320.0
const NOVA_RADIUS: float = 150.0
const NOVA_DMG_BASE: float = 14.0
const NOVA_DMG_PER_FLOOR: float = 1.4
const NOVA_STUN: float = 0.8
const NOVA_SLOW: float = 3.0
const HOLE_RADIUS: float = 170.0
const HOLE_DURATION: float = 3.0
const HOLE_TICK_BASE: float = 5.0
const HOLE_END_BASE: float = 55.0
const HOLE_END_PER_FLOOR: float = 4.0
const BOLT_BASE: float = 22.0
const BOLT_PER_FLOOR: float = 2.2
const BOLT_JUMPS: int = 5
const BOLT_AIM_RANGE: float = 480.0
const BOLT_JUMP_RANGE: float = 190.0
const BOLT_FALLOFF: float = 0.85
const TURRET_CAP: int = 2

var player: Node = null
var skill_id: String = ""
var skill_name: String = ""
var base_cooldown: float = 1.0
var cooldown_total: float = 1.0
var cooldown_left: float = 0.0
## Giống ClassSkill: HUD đọc, Tome không có hiệu ứng kéo dài nên luôn 0.
var active_left: float = 0.0

static func exists(id: String) -> bool:
	return TOMES.has(id)

func setup(p_player: Node, id: String) -> void:
	player = p_player
	set_tome(id)

func set_tome(id: String) -> void:
	skill_id = id
	var cfg: Dictionary = TOMES.get(id, {})
	skill_name = String(cfg.get("name", ""))
	base_cooldown = float(cfg.get("cooldown", 12.0))
	cooldown_total = _effective_cooldown()
	cooldown_left = minf(cooldown_left, cooldown_total)

func _effective_cooldown() -> float:
	var haste: float = float(player.skill_haste()) if is_instance_valid(player) else 0.0
	return maxf(1.0, base_cooldown * Global.SkillTree.skill_cooldown_mult(Global.upgrades) * _sigil("cd") / (1.0 + haste))

func is_ready() -> bool:
	return cooldown_left <= 0.0

func _physics_process(delta: float) -> void:
	var was: bool = cooldown_left > 0.0
	cooldown_left = maxf(0.0, cooldown_left - delta)
	if was and cooldown_left <= 0.0:
		skill_ready.emit(skill_id)
	if is_instance_valid(player) and player.alive and Input.is_action_just_pressed("tome"):
		try_activate()

## Giá trị gộp của các Sigil đang gắn vào Tome (xem sigils.gd).
func _sigil(key: String) -> float:
	return Sigils.total(Global.run_sigils.get("tome", []), key)

## Hoàn bớt hồi chiêu (Sigil Harvest); tổng hoàn mỗi lần tung tối đa nửa thời gian hồi.
var _refunded: float = 0.0
func refund_cooldown(seconds: float) -> void:
	if cooldown_left <= 0.0:
		return
	var room: float = maxf(0.0, cooldown_total * 0.5 - _refunded)
	var give: float = minf(seconds, room)
	_refunded += give
	cooldown_left = maxf(0.0, cooldown_left - give)

func try_activate() -> bool:
	if skill_id == "" or not is_ready() or not is_instance_valid(player) or not player.alive or player.rolling:
		return false
	cooldown_total = _effective_cooldown()
	cooldown_left = cooldown_total
	_refunded = 0.0
	if randf() < float(player.spellburst_chance()):
		cooldown_left = 0.0
		Global.float_text(player.global_position + Vector2(0, -40), "SPELLBURST", Color(0.8, 0.6, 1.0), 18)
	skill_used.emit(skill_id)
	execute_free()
	return true

## Chạy hiệu ứng Tome KHÔNG tốn hồi chiêu, không phát skill_used (tung lại của Sigil Echo).
func execute_free() -> void:
	call("_cast_" + skill_id)

# ---------------------------------------------------------------- Dùng chung
## Hệ số sức mạnh Tome: giống kỹ năng class (damage phụ + Skill Power + honed technique).
func power() -> float:
	return float(player._secondary_dmg_mult()) * (1.0 + float(player.skill_power())) * Global.SkillTree.skill_damage_mult(Global.upgrades) * _sigil("dmg")

func _dmg(base: float, per_floor: float) -> int:
	return maxi(1, int((base + per_floor * float(Global.floor_num)) * power()))

func _cursor_point(max_range: float = PLACE_RANGE) -> Vector2:
	var to: Vector2 = player.get_global_mouse_position() - player.global_position
	return player.global_position + to.limit_length(max_range)

func _ring(pos: Vector2, radius: float, color: Color, duration: float = 0.4) -> void:
	var fx := Node2D.new()
	fx.set_script(RingFx)
	fx.max_radius = radius
	fx.color = color
	fx.duration = duration
	Global.world.add_child(fx)
	fx.global_position = pos

## Giữ tối đa `cap` lính cùng loại của Player; thừa thì xoá lính cũ nhất.
func _enforce_cap(kind: String, cap: int) -> void:
	var mine: Array = []
	for m in get_tree().get_nodes_in_group("minions"):
		if is_instance_valid(m) and m.kind == kind and m.owner_player == player:
			mine.append(m)
	while mine.size() > cap:
		var old: Node = mine.pop_front()
		old.queue_free()

# ---------------------------------------------------------------- 8 Tome
func _cast_arc_turret() -> void:
	var pos: Vector2 = _cursor_point()
	MinionScript.spawn(player, "turret", pos, power() * float(player.minion_dmg_mult()), _sigil("life"), 0, "tome")
	_enforce_cap("turret", TURRET_CAP)
	_ring(pos, 30.0, Color(0.5, 1.0, 0.7), 0.3)
	Global.sfx("pickup", 0.8)

func _cast_spirit_pact() -> void:
	for i in 2:
		MinionScript.spawn(player, "spirit", player.global_position + Vector2.from_angle(randf() * TAU) * 24.0, power() * float(player.minion_dmg_mult()), 10.0 / 12.0 * _sigil("life"), i, "tome")
	_enforce_cap("spirit", 4)
	_ring(player.global_position, 50.0, Color(0.55, 0.85, 1.0), 0.35)
	Global.sfx("barrage_cast", 1.2)

func _cast_frost_nova() -> void:
	var origin: Vector2 = player.global_position
	var d: int = _dmg(NOVA_DMG_BASE, NOVA_DMG_PER_FLOOR)
	var col := Color(0.6, 0.9, 1.0)
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.alive and e.global_position.distance_to(origin) <= NOVA_RADIUS * _sigil("radius"):
			e.take_damage(d, origin, 120.0)
			if e.alive and e.has_method("apply_status"):
				e.apply_status("stun", NOVA_STUN)
				e.apply_status("slow", NOVA_SLOW)
			Global.on_secondary_hit(e, d, false, "tome")
	for b in get_tree().get_nodes_in_group("boss"):
		if is_instance_valid(b) and b.alive and b.global_position.distance_to(origin) <= NOVA_RADIUS * _sigil("radius") + 20.0:
			b.take_damage(d, origin, 0.0)
			Global.on_secondary_hit(b, d, false, "tome")
	_ring(origin, NOVA_RADIUS * _sigil("radius"), col, 0.45)
	Global.burst(origin, col, 22, 280.0, 1.8)
	Global.shake(0.25, 0.2)
	Global.sfx("shockwave", 1.2)

func _cast_blade_dance() -> void:
	for m in get_tree().get_nodes_in_group("minions"):
		if is_instance_valid(m) and m.kind == "blades" and m.owner_player == player:
			m.queue_free() # tung lại thì làm mới, không chồng lưỡi
	MinionScript.spawn(player, "blades", player.global_position, power() * float(player.minion_dmg_mult()), _sigil("life"), 0, "tome")
	Global.sfx("shadow_dash", 1.3)

func _cast_mending_totem() -> void:
	MinionScript.spawn(player, "totem", player.global_position, power(), _sigil("life"), 0, "tome")
	_enforce_cap("totem", 1)
	_ring(player.global_position, 130.0, Color(0.5, 1.0, 0.5), 0.4)
	Global.sfx("pickup", 1.3)

func _cast_black_hole() -> void:
	var pos: Vector2 = _cursor_point(380.0)
	var hole := Node2D.new()
	hole.set_script(GravityWell)
	hole.radius = HOLE_RADIUS * _sigil("radius")
	hole.duration = HOLE_DURATION * _sigil("life")
	hole.src = "tome"
	hole.tick_damage = _dmg(HOLE_TICK_BASE, 0.5)
	hole.color = Color(0.45, 0.2, 0.8)
	hole.pull_mult = 1.8
	hole.end_dmg = _dmg(HOLE_END_BASE, HOLE_END_PER_FLOOR)
	hole.end_radius = hole.radius * 1.1
	Global.world.add_child(hole)
	hole.global_position = pos
	_ring(pos, hole.radius, hole.color, 0.4)
	Global.sfx("phase_step", 0.7)

func _cast_storm_bolt() -> void:
	var cursor: Vector2 = player.get_global_mouse_position()
	var first: Node = null
	var best: float = INF
	for grp in ["enemies", "boss"]:
		for e in get_tree().get_nodes_in_group(grp):
			if not is_instance_valid(e) or not e.alive or not bool(e.get("active")):
				continue
			if e.global_position.distance_to(player.global_position) > BOLT_AIM_RANGE:
				continue
			var dd: float = e.global_position.distance_to(cursor)
			if dd < best:
				best = dd
				first = e
	if first == null:
		cooldown_left = minf(cooldown_left, 1.0) # không có mục tiêu: gần như hoàn lại
		Global.float_text(player.global_position + Vector2(0, -40), "NO TARGET", Color(0.8, 0.8, 0.8), 14)
		return
	var hit: Array = []
	var cur: Node = first
	var from: Vector2 = player.global_position
	var d: float = float(_dmg(BOLT_BASE, BOLT_PER_FLOOR))
	for i in BOLT_JUMPS:
		if cur == null:
			break
		hit.append(cur)
		var amount: int = maxi(1, int(d))
		cur.take_damage(amount, from, 0.0)
		Global.on_secondary_hit(cur, amount, false, "tome")
		_bolt_fx(from, cur.global_position)
		d *= BOLT_FALLOFF
		from = cur.global_position
		cur = _next_bolt_target(from, hit)
	Global.shake(0.2, 0.15)
	Global.sfx("barrage_volley", 1.4)

func _next_bolt_target(from: Vector2, hit: Array) -> Node:
	var best: float = BOLT_JUMP_RANGE
	var out: Node = null
	for grp in ["enemies", "boss"]:
		for e in get_tree().get_nodes_in_group(grp):
			if not is_instance_valid(e) or not e.alive or not bool(e.get("active")) or hit.has(e):
				continue
			var dd: float = e.global_position.distance_to(from)
			if dd < best:
				best = dd
				out = e
	return out

func _bolt_fx(a: Vector2, b: Vector2) -> void:
	var line := Line2D.new()
	line.width = 3.0
	line.default_color = Color(0.9, 0.95, 0.4)
	var pts := PackedVector2Array([a])
	for k in range(1, 4):
		pts.append(a.lerp(b, float(k) / 4.0) + Vector2(randf_range(-9.0, 9.0), randf_range(-9.0, 9.0)))
	pts.append(b)
	line.points = pts
	line.z_index = 5
	Global.world.add_child(line)
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.2)
	tw.tween_callback(line.queue_free)
	Global.burst(b, Color(1.0, 0.95, 0.3), 5, 120.0, 1.2)

func _cast_ward_barrier() -> void:
	var pos: Vector2 = _cursor_point()
	MinionScript.spawn(player, "ward", pos, 1.0, _sigil("life"), 0, "tome")
	_enforce_cap("ward", 1)
	_ring(pos, 80.0, Color(0.6, 0.8, 1.0), 0.4)
	Global.sfx("pickup", 0.7)
