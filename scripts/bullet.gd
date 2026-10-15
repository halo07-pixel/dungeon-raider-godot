extends Area2D
## Đạn (Area2D) nâng cấp: Tích hợp hiệu ứng Sử thi/Huyền thoại (Xuyên, Nổ, Chậm, Xích sét).

var dir: Vector2 = Vector2.RIGHT
var damage: int = 10
var speed: float = 500.0
var life: float = 1.0
var color: Color = Color.WHITE
var radius: float = 5.0
var pierce: bool = false
var from_player: bool = true
var knock: float = 140.0
var effect: String = ""
var _hit: Array = []
var homing: bool = false # Đạn Dark Bolt của Necromancer: bẻ hướng dần về phía mục tiêu
var homing_target: Node = null
## AI Tầng 2 (Q-Learning): nếu viên đạn này do quái Tinh Anh bắn ra (enemy.gd gán khi tạo
## đạn), báo kết quả trúng/trượt ngược lại cho QAgent của nó để cập nhật Q-table.
var source_q_agent: Node = null
var _q_reward_sent: bool = false
## Buff tầm xa (đặt bởi player.gd lúc bắn)
var bounces_left: int = 0
var split_on_hit: bool = false
var is_crit: bool = false
var is_fragment: bool = false # mảnh tách ra từ Đạn Phân Tách — không tách tiếp
const HOMING_TURN_RATE: float = 2.2 # rad/s - bẻ hướng từ từ, không phải dính chắc chắn

@onready var life_timer: Timer = $Life

func setup(p_from_player: bool, p_dir: Vector2, p_dmg: int, p_speed: float, p_life: float, p_color: Color, p_rad: float, p_pierce: bool = false, p_effect: String = "") -> void:
	from_player = p_from_player
	dir = p_dir.normalized()
	damage = p_dmg
	speed = p_speed
	life = p_life
	color = p_color
	radius = p_rad
	pierce = p_pierce
	effect = p_effect
	knock = 140.0 if p_from_player else 220.0
	rotation = dir.angle()

func _ready() -> void:
	if from_player:
		collision_layer = Global.L_PBULLET
		collision_mask = Global.L_WORLD | Global.L_ENEMY
	else:
		collision_layer = Global.L_EBULLET
		collision_mask = Global.L_WORLD | Global.L_PLAYER
		add_to_group("enemy_bullets") # Để Dao găm nhận diện xóa đạn
		
	var s := CircleShape2D.new()
	s.radius = radius
	$Shape.shape = s
	body_entered.connect(_on_body_entered)
	life_timer.timeout.connect(_on_timeout)
	life_timer.start(life)

## Đạn địch bị Phản Đạn: đổi chủ thành đạn của Player bay theo hướng mới.
func reflect(new_dir: Vector2, dmg_mult: float) -> void:
	from_player = true
	remove_from_group("enemy_bullets")
	source_q_agent = null
	_q_reward_sent = true
	dir = new_dir.normalized()
	rotation = dir.angle()
	damage = maxi(1, int(float(damage) * dmg_mult))
	knock = 140.0
	_hit.clear()
	collision_layer = Global.L_PBULLET
	collision_mask = Global.L_WORLD | Global.L_ENEMY
	life_timer.start(maxf(life_timer.time_left, 1.0))
	color = Color(0.6, 1.0, 0.7)
	queue_redraw()

func _nearest_enemy_pos(max_dist: float) -> Variant:
	var best: Variant = null
	var best_d: float = max_dist
	for e in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("boss"):
		if not is_instance_valid(e) or not e.get("alive"):
			continue
		var pos: Vector2 = e.hurt_center() if e.has_method("hurt_center") else e.global_position
		var dd: float = global_position.distance_to(pos)
		if dd < best_d:
			best_d = dd
			best = pos
	return best

func _physics_process(delta: float) -> void:
	if homing and from_player:
		# Đạn Tầm Nhiệt của Player: tự dò quái gần nhất trong 320px
		var tp: Variant = _nearest_enemy_pos(320.0)
		if tp != null:
			var want: Vector2 = ((tp as Vector2) - global_position).normalized()
			dir = dir.slerp(want, minf(1.0, 4.0 * delta))
			rotation = dir.angle()
	elif homing and is_instance_valid(homing_target):
		var target_pos = homing_target.hurt_center() if homing_target.has_method("hurt_center") else homing_target.global_position
		var want_dir: Vector2 = (target_pos - global_position).normalized()
		dir = dir.slerp(want_dir, minf(1.0, HOMING_TURN_RATE * delta))
		rotation = dir.angle()
	position += dir * speed * delta

func _on_body_entered(body: Node) -> void:
	if body.has_method("take_damage"):
		if not from_player and body.has_method("is_invulnerable") and body.is_invulnerable():
			return
		if pierce:
			if _hit.has(body):
				return
			_hit.append(body)
			
		body.take_damage(damage, global_position - dir * 8.0, knock)

		if not from_player and source_q_agent and not _q_reward_sent:
			_q_reward_sent = true
			source_q_agent.learn(10.0) # AI Tầng 2: đòn chọn vừa rồi trúng Player -> thưởng

		if from_player:
			# ÁP DỤNG BUFF (tầm xa — sát thương tầm xa "đổ bộ" ở đây, không phải trong player.gd._shoot()):
			# Phá Giáp / Hút Máu
			Global.on_player_hit(body, damage, is_crit)
			if Global.buff_stack("buff_sunder") > 0 and body.has_method("apply_sunder"):
				body.apply_sunder()
			if Global.buff_stack("buff_lifesteal") > 0 and is_instance_valid(Global.player):
				Global.player.heal(maxi(1, int(float(damage) * 0.02 * float(Global.buff_stack("buff_lifesteal")))))

		if body.has_method("apply_status"):
			if from_player:
				# Kích hoạt trạng thái lên quái (Sử thi / Huyền thoại)
				if effect == "slow":
					body.apply_status("slow", 2.0)
				elif effect == "chain": # Xích sét laser Huyền thoại
					_chain_lightning(body)
				# ÁP DỤNG BUFF: Lưỡi Rỉ Máu / Đạn Băng
				if randf() < minf(0.6, 0.15 * float(Global.buff_stack("buff_bleed_proc"))):
					body.apply_status("bleed", 0.0)
				if randf() < minf(0.6, 0.20 * float(Global.buff_stack("buff_slow_proc"))):
					body.apply_status("slow", 1.5)
			elif effect == "poison":
				# Độc Trượng (Orc Shaman, biome Đầm Lầy): 3 nhịp x 4 dmg lên Player
				body.apply_status("poison", 3, 4)
				
		if from_player and split_on_hit and not is_fragment:
			_spawn_fragments()
		if not pierce:
			_impact()
	elif from_player and bounces_left > 0 and _try_bounce():
		return
	else:
		# Đập tường/vật cản (không có take_damage) = trượt -> phạt QAgent nếu là đạn Tinh Anh
		if source_q_agent and not _q_reward_sent:
			_q_reward_sent = true
			source_q_agent.learn(-5.0)
		_impact()

## Đạn Nảy: dò pháp tuyến tường bằng raycast ngắn rồi phản xạ hướng bay.
func _try_bounce() -> bool:
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(global_position - dir * (radius + 10.0), global_position + dir * (radius + 14.0), Global.L_WORLD)
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return false
	bounces_left -= 1
	dir = dir.bounce(hit["normal"]).normalized()
	rotation = dir.angle()
	global_position = hit["position"] + hit["normal"] * (radius + 2.0)
	_hit.clear()
	Global.burst(global_position, color, 3, 70.0, 0.8)
	return true

func _spawn_fragments() -> void:
	for off in [-0.6, 0.6]:
		var nb = load("res://scenes/bullet.tscn").instantiate()
		nb.setup(true, dir.rotated(off), maxi(1, int(float(damage) * 0.4)), speed, 0.45, color, maxf(3.0, radius * 0.6))
		nb.is_fragment = true
		_add_deferred(nb, global_position)

## Không được add_child ngay trong callback va chạm (đang flush physics).
func _add_deferred(node: Node, pos: Vector2) -> void:
	Global.world.add_child.call_deferred(node)
	node.set_deferred("global_position", pos)

func _chain_lightning(first_target: Node) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != first_target and e.alive and e.global_position.distance_to(first_target.global_position) < 150.0:
			e.take_damage(int(damage * 0.5), first_target.global_position, 0.0)
			Global.burst(e.global_position, Color.YELLOW, 2, 80.0, 1.0)

func _on_timeout() -> void:
	if source_q_agent and not _q_reward_sent:
		_q_reward_sent = true
		source_q_agent.learn(-5.0) # AI Tầng 2: hết giờ mà không trúng -> phạt
	_impact()

func _impact() -> void:
	if effect == "explode": # Shotgun Huyền thoại (Nổ dung nham)
		Global.burst(global_position, Color(1.0, 0.3, 0.1), 15, 150.0, 2.0)
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.has_method("take_damage") and e.alive and e.global_position.distance_to(global_position) < 70.0:
				e.take_damage(damage, global_position, knock * 1.5)
	else:
		Global.burst(global_position, color, 5, 100.0, 1.0)
	queue_free()

func _draw() -> void:
	var trail: float = radius * (6.0 if pierce else 2.5)
	draw_line(Vector2(-trail, 0.0), Vector2.ZERO, Color(color, 0.5), radius * 1.4)
	draw_circle(Vector2.ZERO, radius, color)
	draw_circle(Vector2.ZERO, radius * 0.5, Color.WHITE)
