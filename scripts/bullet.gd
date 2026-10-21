extends Area2D
## Đạn (Area2D) nâng cấp: Tích hợp hiệu ứng Sử thi/Huyền thoại (Xuyên, Nổ, Chậm, Xích sét).

const RingFx = preload("res://scripts/skill_ring_fx.gd")
const AftershockZone = preload("res://scripts/aftershock_zone.gd")

var dir: Vector2 = Vector2.RIGHT
var damage: int = 10
var speed: float = 500.0
var life: float = 1.0
var color: Color = Color.WHITE
var radius: float = 5.0
var pierce: bool = false
## Xuyên CÓ GIỚI HẠN (đạn tầm xa của Player): số quái còn xuyên qua được. Trúng quái khi = 0 thì gây sát thương
## rồi biến mất. `pierce` (true) vẫn là xuyên vô hạn, chỉ còn dùng cho sóng kiếm/đòn cận chiến.
var pierce_left: int = 0
var from_player: bool = true
var source: String = "" # ai bắn (đạn địch): "enemy:kind" / "boss:kind", để ghi nguồn sát thương khi trúng Player
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
## Đạn Tầm Nhiệt của Player
var homing_delay: float = 0.0          # giây bay thẳng trước khi bắt đầu bẻ lái
var lock_target: Node = null           # mục tiêu đã khóa (giữ đến khi chết)
var homing_exclude: Node = null        # quái KHÔNG được khóa (mảnh tách ra không quay lại quái vừa trúng)
const HOMING_RANGE: float = 360.0
const HOMING_PIERCE_STRAIGHT: float = 0.03 # giây bay thẳng sau khi xuyên qua 1 quái, rồi mới khóa quái kế tiếp
const HOMING_CONE_COS: float = 0.5     # cos(60°): nón ưu tiên phía trước
const HOMING_BASE_TURN: float = 5.0    # rad/s khi ở xa
const HOMING_LEAD: float = 0.12        # đón đầu: cộng velocity * 0.12s
const HOMING_FAR: float = 140.0
const HOMING_NEAR: float = 120.0
const HOMING_MAX_TURN: float = 60.0
const HOMING_ORBIT_FACTOR: float = 0.5 # bán kính vòng cua tối đa = 0.5 * khoảng cách
const HOMING_LEAD_FADE_NEAR: float = 40.0 # dưới 40px: nhắm thẳng tâm, bỏ đón đầu
var is_fragment: bool = false # mảnh tách ra từ Đạn Phân Tách — không tách tiếp
## Railgun: độ dài vệt tia vẽ phía sau đạn (0 = đạn thường).
var beam_len: float = 0.0
## Arcane Staff (effect "orb"): nổ diện rộng khi va chạm/hết tầm. blast_status "slow" làm chậm quái trong vùng;
## blast_echo = nổ thêm 1 lần nữa sau BLAST_ECHO_DELAY (Legendary).
var blast_radius: float = 0.0
var blast_status: String = ""
var blast_echo: bool = false
var _exploded: bool = false
## Crossbow (effect "pin"): quái trúng đạn mà phía sau trong pin_reach px có tường => bị GHIM: sát thương x pin_mult + choáng pin_stun giây.
signal pinned(target: Node)
var pin_mult: float = 1.8
var pin_stun: float = 1.0
var pin_reach: float = 70.0
## Flamethrower (effect "fire"): trúng thì gây cháy với công suất burn_power.
var burn_power: int = 2
## Chakram: bay ra out_time giây (hoặc tới khi chạm tường) rồi quay về Player; lượt về nhân sát thương return_dmg_mult.
var boomerang: bool = false
var out_time: float = 0.55
var return_dmg_mult: float = 1.0
var _returning: bool = false
var _alive_t: float = 0.0
var _spin: float = 0.0
const CHAKRAM_CATCH_DIST: float = 20.0
const CHAKRAM_RETURN_SPEED_MULT: float = 1.25
const BLAST_ECHO_DELAY: float = 0.4
const BLAST_ECHO_DMG_MULT: float = 0.6
const BLAST_ECHO_RADIUS_MULT: float = 0.8
const BLAST_KNOCK_MULT: float = 1.2
const BLAST_REACH: float = 12.0        # cộng thêm bán kính thân quái để quái to cũng bị tính
const BLAST_SLOW_TIME: float = 1.8
const AFTERSHOCK_DMG_MULT: float = 0.25   # mỗi nhịp lửa = 25% sát thương quả cầu
const VOLATILE_RADIUS_MULT: float = 0.6
const VOLATILE_DMG_MULT: float = 0.5
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

# ---------------------------------------------------------------- Đạn Tầm Nhiệt (buff_homing)
## Khóa mục tiêu (ưu tiên quái trong góc nón phía trước), nhắm tâm hitbox + đón đầu nhẹ, tăng
## tốc độ bẻ lái khi vào gần (chống bay vòng quanh), và có thể trễ kích hoạt (homing_delay).
func _target_alive(t) -> bool:
	return is_instance_valid(t) and bool(t.get("alive"))

## Điểm nhắm: tâm hitbox thật + vận tốc * HOMING_LEAD (đón đầu chuyển động ngang).
## lead_weight 0..1: gần mục tiêu thì giảm dần phần đón đầu để găm thẳng vào tâm hitbox.
func _aim_point(t: Node2D, lead_weight: float = 1.0) -> Vector2:
	var pos: Vector2 = t.hurt_center() if t.has_method("hurt_center") else t.global_position
	var v: Variant = t.get("velocity")
	if v is Vector2:
		pos += (v as Vector2) * HOMING_LEAD * lead_weight
	return pos

func _acquire_lock() -> Node:
	var best_cone: Node = null
	var best_cone_d: float = INF
	var best_any: Node = null
	var best_any_d: float = INF
	for e in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("boss"):
		if not _target_alive(e) or e == homing_exclude or _hit.has(e) or e.get("active") == false:
			continue
		var to: Vector2 = _aim_point(e) - global_position
		var d: float = to.length()
		if d > HOMING_RANGE or d < 0.001:
			continue
		if d < best_any_d:
			best_any_d = d
			best_any = e
		if dir.dot(to / d) >= HOMING_CONE_COS and d < best_cone_d:
			best_cone_d = d
			best_cone = e
	return best_cone if best_cone != null else best_any

## Hệ số tốc độ xoay theo khoảng cách: xa (>140px) = 1x mượt; vào gần (<120px) tăng dần 2.5x -> 3x.
func _turn_mult(d: float) -> float:
	if d >= HOMING_FAR:
		return 1.0
	if d >= HOMING_NEAR:
		return lerpf(1.0, 2.5, (HOMING_FAR - d) / (HOMING_FAR - HOMING_NEAR))
	return lerpf(2.5, 3.0, 1.0 - d / HOMING_NEAR)

## Vừa xuyên qua 1 quái: bỏ khóa, bay thẳng một đoạn ngắn để thoát khỏi quái đó rồi mới tìm quái khác.
func _after_pierce() -> void:
	if homing and from_player:
		lock_target = null
		homing_delay = HOMING_PIERCE_STRAIGHT

func _steer_player_homing(delta: float) -> void:
	if homing_delay > 0.0:
		homing_delay -= delta # bay thẳng trước (đạn vòng bung ra rồi mới chụm vào)
		return
	if not _target_alive(lock_target) or _hit.has(lock_target):
		lock_target = _acquire_lock() # chọn lại khi mục tiêu cũ đã chết HOẶC đã bị xuyên qua (không thể trúng lần 2)
	if lock_target == null:
		return
	var center_d: float = (_aim_point(lock_target, 0.0) - global_position).length()
	var lead_w: float = clampf((center_d - HOMING_LEAD_FADE_NEAR) / (HOMING_FAR - HOMING_LEAD_FADE_NEAR), 0.0, 1.0)
	var to: Vector2 = _aim_point(lock_target, lead_w) - global_position
	var d: float = to.length()
	if d < 1.0:
		return
	var rate: float = HOMING_BASE_TURN * _turn_mult(d)
	if d < HOMING_NEAR:
		# Chống orbit: bán kính vòng cua (speed/rate) luôn nhỏ hơn khoảng cách tới mục tiêu.
		rate = maxf(rate, minf(HOMING_MAX_TURN, speed / (HOMING_ORBIT_FACTOR * d)))
	var diff: float = wrapf(to.angle() - dir.angle(), -PI, PI)
	dir = dir.rotated(clampf(diff, -rate * delta, rate * delta))
	rotation = dir.angle()

func _physics_process(delta: float) -> void:
	if boomerang and from_player:
		_boomerang_step(delta)
		return
	if homing and from_player:
		_steer_player_homing(delta)
	elif homing and is_instance_valid(homing_target):
		var target_pos = homing_target.hurt_center() if homing_target.has_method("hurt_center") else homing_target.global_position
		var want_dir: Vector2 = (target_pos - global_position).normalized()
		dir = dir.slerp(want_dir, minf(1.0, HOMING_TURN_RATE * delta))
		rotation = dir.angle()
	position += dir * speed * delta

## Chakram: bay thẳng, tới hạn (hoặc chạm tường) thì quay về Player; tới sát Player thì được "bắt" lại (đĩa biến mất).
func _boomerang_step(delta: float) -> void:
	_alive_t += delta
	_spin += delta * 18.0
	queue_redraw()
	if not _returning and _alive_t >= out_time:
		_start_return()
	if _returning:
		var pl: Node2D = Global.player
		if not is_instance_valid(pl) or not bool(pl.get("alive")):
			queue_free()
			return
		var to: Vector2 = (pl.hurt_center() if pl.has_method("hurt_center") else pl.global_position) - global_position
		if to.length() <= CHAKRAM_CATCH_DIST:
			Global.burst(global_position, color, 4, 80.0, 1.0)
			queue_free()
			return
		dir = to.normalized()
	position += dir * speed * delta

func _start_return() -> void:
	if _returning:
		return
	_returning = true
	_hit.clear() # lượt về được đánh lại các quái đã trúng lượt đi
	damage = maxi(1, int(float(damage) * return_dmg_mult))
	speed *= CHAKRAM_RETURN_SPEED_MULT

func _on_body_entered(body: Node) -> void:
	if body.has_method("take_damage"):
		if effect == "orb" and from_player and blast_radius > 0.0:
			_impact() # quả cầu phép nổ ngay khi chạm; sát thương do vụ nổ áp cho mọi quái trong vùng (kể cả quái bị chạm)
			return
		if not from_player and body.has_method("is_invulnerable") and body.is_invulnerable():
			return
		if pierce or pierce_left > 0:
			if _hit.has(body):
				return # đã xuyên qua quái này rồi, không đánh lần 2
			_hit.append(body)

		var hit_dmg: int = damage
		var pinned_now: bool = false
		if effect == "pin" and from_player and _wall_behind(body):
			hit_dmg = int(float(damage) * pin_mult)
			pinned_now = true
		body.take_damage(hit_dmg, global_position - dir * 8.0, knock, false, false, source)
		if pinned_now:
			_apply_pin(body)
		elif effect == "fire" and from_player and body.has_method("apply_element"):
			body.apply_element("burn", burn_power, 0)

		if not from_player and source_q_agent and not _q_reward_sent:
			_q_reward_sent = true
			source_q_agent.learn(10.0) # AI Tầng 2: đòn chọn vừa rồi trúng Player -> thưởng

		if from_player:
			# ÁP DỤNG BUFF (tầm xa — sát thương tầm xa "đổ bộ" ở đây, không phải trong player.gd._shoot()):
			# Phá Giáp / Hút Máu
			Global.on_player_hit(body, hit_dmg, is_crit)
			if Global.buff_stack("buff_sunder") > 0 and body.has_method("apply_sunder"):
				body.apply_sunder()

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
			elif effect == "burn":
				# Cầu lửa (Imp, biome Địa Ngục): thiêu 2 nhịp
				body.apply_status("burn", 2)
				
		if from_player and split_on_hit and not is_fragment:
			_spawn_fragments(body)
		if pierce and homing and from_player:
			_after_pierce()
		if not pierce:
			if pierce_left > 0:
				pierce_left -= 1 # xuyên qua quái này, còn bay tiếp
				_after_pierce()
			else:
				_impact()
	elif from_player and bounces_left > 0 and _try_bounce():
		return
	elif boomerang and from_player:
		_start_return() # Chakram chạm tường: quay về luôn (lượt về xuyên tường, không bị chặn)
	else:
		# Đập tường/vật cản (không có take_damage) = trượt -> phạt QAgent nếu là đạn Tinh Anh
		if source_q_agent and not _q_reward_sent:
			_q_reward_sent = true
			source_q_agent.learn(-5.0)
		_impact()

## Crossbow: có tường ngay phía sau mục tiêu (theo hướng bay, trong pin_reach px) không?
func _wall_behind(target: Node2D) -> bool:
	var from: Vector2 = target.global_position
	var q := PhysicsRayQueryParameters2D.create(from, from + dir * pin_reach, Global.L_WORLD)
	return not get_world_2d().direct_space_state.intersect_ray(q).is_empty()

func _apply_pin(target: Node) -> void:
	if target.has_method("apply_status"):
		target.apply_status("stun", pin_stun)
	Global.float_text(target.global_position + Vector2(0, -28), "PINNED", Color(1.0, 0.85, 0.5), 18)
	Global.burst(target.global_position, Color(1.0, 0.85, 0.5), 8, 120.0, 1.3)
	Global.shake(0.15, 0.1)
	pinned.emit(target)

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

## Đạn Phân Tách: 2 mảnh (40% sát thương). Thừa hưởng Tầm Nhiệt (khóa quái KHÁC con vừa trúng)
## và Đạn Nảy của Player. Siêu Đạn (xuyên) gọi hàm này ở MỖI quái nó xuyên qua.
func _spawn_fragments(hit_body: Node = null) -> void:
	for off in [-0.6, 0.6]:
		var nb = load("res://scenes/bullet.tscn").instantiate()
		nb.setup(true, dir.rotated(off), maxi(1, int(float(damage) * 0.4)), speed, 0.45, color, maxf(3.0, radius * 0.6))
		nb.is_fragment = true
		nb.bounces_left = Global.buff_stack("buff_bounce")
		if Global.buff_stack("buff_homing") > 0:
			nb.homing = true
			nb.homing_exclude = hit_body
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
	if effect == "orb" and from_player and blast_radius > 0.0:
		_explode_orb()
		return
	if effect == "explode": # Shotgun Huyền thoại (Nổ dung nham)
		Global.burst(global_position, Color(1.0, 0.3, 0.1), 15, 150.0, 2.0)
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.has_method("take_damage") and e.alive and e.global_position.distance_to(global_position) < 70.0:
				e.take_damage(damage, global_position, knock * 1.5)
	else:
		Global.burst(global_position, color, 5, 100.0, 1.0)
	queue_free()

## Quả cầu nổ: ẩn đạn, gây nổ tại chỗ; Legendary nổ lần 2 sau BLAST_ECHO_DELAY rồi mới huỷ đạn.
func _explode_orb() -> void:
	if _exploded:
		return
	_exploded = true
	set_physics_process(false)
	hide()
	$Shape.set_deferred("disabled", true)
	var pos: Vector2 = global_position
	_orb_blast(pos, blast_radius, damage)
	if Global.buff_stack("buff_aftershock") > 0:
		_spawn_aftershock(pos)
	if blast_echo:
		await get_tree().create_timer(BLAST_ECHO_DELAY).timeout
		if is_inside_tree():
			_orb_blast(pos, blast_radius * BLAST_ECHO_RADIUS_MULT, maxi(1, int(float(damage) * BLAST_ECHO_DMG_MULT)))
	queue_free()

func _orb_blast(pos: Vector2, rad: float, dmg: int) -> void:
	Global.burst(pos, color, 14, 170.0, 1.8)
	Global.shake(0.12, 0.1)
	var fx := Node2D.new()
	fx.set_script(RingFx)
	fx.max_radius = rad
	fx.color = color
	fx.duration = 0.3
	Global.world.add_child(fx)
	fx.global_position = pos
	var targets: Array = get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("boss")
	for e in targets:
		if not is_instance_valid(e) or not bool(e.get("alive")) or e.get("active") == false:
			continue
		if e.global_position.distance_to(pos) > rad + BLAST_REACH:
			continue
		e.take_damage(dmg, pos, 0.0 if e.is_in_group("boss") else knock * BLAST_KNOCK_MULT)
		Global.on_player_hit(e, dmg, is_crit)
		if blast_status == "slow" and e.has_method("apply_status"):
			e.apply_status("slow", BLAST_SLOW_TIME)
		if not bool(e.get("alive")) and Global.buff_stack("buff_volatile") > 0:
			_volatile_pop(e.global_position, rad, dmg, e)

## Volatile Orb: quái chết trong vụ nổ nổ nhỏ lên quái kề bên (không dây chuyền tiếp).
func _volatile_pop(pos: Vector2, rad: float, dmg: int, dead: Node) -> void:
	var r: float = rad * VOLATILE_RADIUS_MULT
	var pop_dmg: int = maxi(1, int(float(dmg) * VOLATILE_DMG_MULT))
	Global.burst(pos, color, 8, 120.0, 1.4)
	var fx := Node2D.new()
	fx.set_script(RingFx)
	fx.max_radius = r
	fx.color = color
	fx.duration = 0.25
	Global.world.add_child(fx)
	fx.global_position = pos
	for o in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("boss"):
		if o == dead or not is_instance_valid(o) or not bool(o.get("alive")) or o.get("active") == false:
			continue
		if o.global_position.distance_to(pos) <= r + BLAST_REACH:
			o.take_damage(pop_dmg, pos, 0.0, true)

## Aftershock: vùng lửa còn lại sau vụ nổ.
func _spawn_aftershock(pos: Vector2) -> void:
	var z := Node2D.new()
	z.set_script(AftershockZone)
	z.radius = blast_radius * 0.8
	z.tick_damage = maxi(1, int(float(damage) * AFTERSHOCK_DMG_MULT))
	z.color = color
	Global.world.add_child(z)
	z.global_position = pos

func _draw() -> void:
	if boomerang:
		for k in 4:
			var a: float = _spin + float(k) * TAU * 0.25
			draw_line(Vector2.ZERO, Vector2.from_angle(a) * radius * 1.25, Color(color, 0.9), 2.5)
		draw_arc(Vector2.ZERO, radius * 0.8, 0.0, TAU, 20, Color.WHITE, 2.0)
		draw_arc(Vector2.ZERO, radius * 1.05, 0.0, TAU, 20, Color(color, 0.7), 1.5)
		return
	if beam_len > 0.0:
		draw_line(Vector2(-beam_len, 0.0), Vector2.ZERO, Color(color, 0.30), radius * 3.0)
		draw_line(Vector2(-beam_len, 0.0), Vector2.ZERO, Color(color, 0.85), radius * 1.4)
		draw_line(Vector2(-beam_len * 0.8, 0.0), Vector2.ZERO, Color.WHITE, radius * 0.6)
	var trail: float = radius * (6.0 if (pierce or pierce_left > 0) else 2.5)
	draw_line(Vector2(-trail, 0.0), Vector2.ZERO, Color(color, 0.5), radius * 1.4)
	draw_circle(Vector2.ZERO, radius, color)
	draw_circle(Vector2.ZERO, radius * 0.5, Color.WHITE)
