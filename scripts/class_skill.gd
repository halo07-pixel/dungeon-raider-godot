extends Node
## Kỹ năng riêng của class đã tiến hoá, kích hoạt bằng phím "skill" (Q). Node con của Player;
## tách khỏi _physics_process của Player. Player chỉ cần: aim_dir, global_position, alive, rolling,
## _secondary_dmg_mult(). HUD đọc cooldown_left / cooldown_total / skill_name qua duck typing.

const BULLET = preload("res://scenes/bullet.tscn")
const RingFx = preload("res://scripts/skill_ring_fx.gd")

signal skill_used(skill_id: String)

const SKILLS: Dictionary = {
	"barrage": {"name": "Barrage", "cooldown": 7.0},
	"shockwave": {"name": "Shockwave", "cooldown": 9.0},
}

var player: Node = null
var skill_id: String = ""
var skill_name: String = ""
var cooldown_total: float = 1.0
var cooldown_left: float = 0.0

func setup(p_player: Node, p_skill_id: String) -> void:
	player = p_player
	skill_id = p_skill_id
	var cfg: Dictionary = SKILLS.get(p_skill_id, {})
	skill_name = String(cfg.get("name", ""))
	cooldown_total = float(cfg.get("cooldown", 8.0))

func is_ready() -> bool:
	return cooldown_left <= 0.0

func _physics_process(delta: float) -> void:
	cooldown_left = maxf(0.0, cooldown_left - delta)
	if not is_instance_valid(player) or not player.alive:
		return
	if Input.is_action_just_pressed("skill"):
		try_activate()

func try_activate() -> bool:
	if skill_id == "" or not is_ready() or not is_instance_valid(player) or not player.alive:
		return false
	if player.rolling:
		return false
	cooldown_left = cooldown_total
	skill_used.emit(skill_id)
	match skill_id:
		"barrage": _barrage()
		"shockwave": _shockwave()
	return true

func _dmg_mult() -> float:
	return float(player._secondary_dmg_mult())

# ------------------------------------------------------------------ Ranger+: Barrage
const BARRAGE_VOLLEYS: int = 3
const BARRAGE_BULLETS: int = 9
const BARRAGE_FAN_DEG: float = 72.0
const BARRAGE_GAP: float = 0.12

func _barrage() -> void:
	Global.shake(0.35, 0.3)
	for v in BARRAGE_VOLLEYS:
		if not is_instance_valid(player) or not player.alive:
			return
		_fire_volley()
		await get_tree().create_timer(BARRAGE_GAP).timeout

func _fire_volley() -> void:
	var dmg: int = maxi(1, int((8.0 + 1.2 * float(Global.floor_num)) * _dmg_mult()))
	var base: float = player.aim_dir.angle()
	var fan: float = deg_to_rad(BARRAGE_FAN_DEG)
	for i in BARRAGE_BULLETS:
		var off: float = lerpf(-fan * 0.5, fan * 0.5, float(i) / float(BARRAGE_BULLETS - 1))
		var b = BULLET.instantiate()
		b.setup(true, Vector2.from_angle(base + off), dmg, 680.0, 0.9, Color(0.5, 0.9, 1.0), 5.0)
		Global.world.add_child(b)
		b.global_position = player.global_position + Vector2.from_angle(base + off) * 22.0
	Global.sfx("shotgun")
	Global.burst(player.global_position + player.aim_dir * 26.0, Color(0.5, 0.9, 1.0), 6, 120.0, 1.2)

# ------------------------------------------------------------------ Brawler+: Shockwave
const SHOCK_RADIUS: float = 190.0
const SHOCK_KNOCK: float = 650.0

func _shockwave() -> void:
	var origin: Vector2 = player.global_position
	var dmg: int = maxi(1, int((30.0 + 3.0 * float(Global.floor_num)) * _dmg_mult()))
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.alive and e.global_position.distance_to(origin) <= SHOCK_RADIUS:
			e.take_damage(dmg, origin, SHOCK_KNOCK)
			Global.on_secondary_hit(e, dmg, false)
	for b in get_tree().get_nodes_in_group("boss"):
		if is_instance_valid(b) and b.alive and b.global_position.distance_to(origin) <= SHOCK_RADIUS + 20.0:
			b.take_damage(dmg, origin, 0.0)
			Global.on_secondary_hit(b, dmg, false)
	for eb in get_tree().get_nodes_in_group("enemy_bullets"):
		if is_instance_valid(eb) and eb.global_position.distance_to(origin) <= SHOCK_RADIUS + 10.0:
			eb.queue_free()
	var fx := Node2D.new()
	fx.set_script(RingFx)
	fx.max_radius = SHOCK_RADIUS
	fx.color = Color(1.0, 0.75, 0.35)
	Global.world.add_child(fx)
	fx.global_position = origin
	Global.burst(origin, Color(1.0, 0.75, 0.35), 28, 320.0, 2.0)
	Global.shake(0.8, 0.3)
	Global.sfx("slam")
