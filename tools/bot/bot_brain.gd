extends Node
## Bot tự chơi để kiểm thử cân bằng (KHÔNG thuộc game chính; chỉ tools/bot/run_bot.gd dùng).
## Điều khiển Player qua đúng các cổng người chơi dùng: Input.action_press (di chuyển/bắn), Player.ai_aim_point
## (ngắm), _start_roll (lăn né), class_skill.try_activate (kỹ năng Q). Không sửa logic game.
## Bot cố tình KHÔNG hoàn hảo (phản ứng trễ, né sai ngẫu nhiên) để gần người chơi trung bình.
## Mọi hệ số nằm đầu file; nâng cấp bot sau này = chỉnh/ thêm hàm ở đây (xem README.md).

const THINK_INTERVAL: float = 0.1          # giây mô phỏng giữa hai lần chọn mục tiêu / hướng
const RANGED_KEEP_DIST: float = 230.0
const RANGED_TOO_CLOSE: float = 150.0
const KITER_CHASE_DIST: float = 150.0
const LEAD_MAX_T: float = 0.6
const LEAD_FACTOR: float = 0.0           # <1: bot không đón đầu hoàn hảo
const BULLET_LOOKAHEAD: float = 0.55      # giây: tính điểm gần nhất của đạn địch trong khoảng này
const BULLET_HIT_RADIUS: float = 26.0
const TRAP_AVOID_DIST: float = 48.0
const BOSS_KEEP_DIST: float = 300.0
const MELEE_ENGAGE_PAD: float = 12.0
const HAZARD_MARGIN: float = 46.0          # thêm vào bán kính vùng nguy hiểm khi tránh
const BULLET_DANGER_DIST: float = 95.0
const DODGE_REACT_CHANCE: float = 0.65     # xác suất thực sự né khi phát hiện đạn tới (bot không hoàn hảo)
const DODGE_MIN_GAP: float = 0.35
const SKILL_ENEMY_COUNT: int = 3
const SKILL_RADIUS: float = 260.0
const WALL_PUSH_DIST: float = 70.0
const REPEL_DIST: float = 170.0            # đẩy khỏi MỌI quái gần hơn mức này (không chỉ quái gần nhất)
const REPEL_WEIGHT: float = 1.5
const TELEGRAPH_AVOID_DIST: float = 230.0   # trùm đang báo trước đòn: lùi ra khỏi tầm này
const CONTACT_ROLL_DIST: float = 58.0      # quái chạm sát thì lăn thoát
const PICKUP_RANGE: float = 170.0
const HEAL_SEEK_RANGE: float = 520.0
const HEAL_SEEK_HP: float = 0.7
const STUCK_SECONDS: float = 2.0
const HUNT_AFTER: float = 40.0              # chừng này giây không hạ được con nào thì chuyển sang "săn": lao thẳng theo đường tới quái
const HUNT_DURATION: float = 20.0
const TIER_SCORE: Dictionary = {"common": 1.0, "rare": 2.0, "epic": 3.2, "skill": 4.0}

var G: Node # autoload Global (lấy bằng đường cây vì script chạy ở chế độ --script không biết tên autoload lúc biên dịch)
var main: Node
var player: CharacterBody2D
var dungeon: Node
var sim_time: float = 0.0
var stats: Dictionary = {"rolls": 0, "skills": 0, "buffs": [], "stuck_events": 0, "rooms_cleared": 0, "think": 0, "shoot_ticks": 0, "hazard_ticks": 0, "nolos_ticks": 0}

var trace: bool = false
var _goal_desc: String = ""
var _trace_t: float = 0.0
var _think_t: float = 0.0
var _move: Vector2 = Vector2.ZERO
var _shoot: bool = false
var _dodge_gap: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO
var _stuck_t: float = 0.0
var _stuck_acc: float = 0.0
var _last_kills: int = 0
var _last_progress: float = 0.0
var _hunt_until: float = 0.0
var _jiggle_t: float = 0.0
var _jiggle_dir: Vector2 = Vector2.ZERO
var _held: Dictionary = {}
var _picker: Node = null

func _init() -> void:
	G = Engine.get_main_loop().root.get_node("Global")

func setup(p_main: Node) -> void:
	main = p_main
	player = p_main.player
	dungeon = p_main.dungeon
	process_mode = Node.PROCESS_MODE_PAUSABLE
	G.buff_choice_requested.connect(_on_buff_choice)
	_last_pos = player.global_position

func _exit_tree() -> void:
	_release_all()
	if is_instance_valid(player):
		player.ai_aim_point = null

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or not player.alive:
		_release_all()
		return
	sim_time += delta
	if trace:
		_trace_t -= delta
		if _trace_t <= 0.0:
			_trace_t = 5.0
			var tg = _nearest(_enemies(), player.global_position)
			if tg != null:
				var hpv = tg.hurtbox.hp if tg.get("hurtbox") != null else tg.get("hp")
				print("     target=%s hp=%s dist=%d los=%s" % [tg.get("kind"), str(hpv), int(player.global_position.distance_to(tg.global_position)), _los(player.global_position, tg.global_position)])
				var pth: PackedVector2Array = dungeon.find_path(player.global_position, tg.global_position)
				print("     tpos=(%d,%d) path=%d first=%s active=%s" % [tg.global_position.x, tg.global_position.y, pth.size(), str(pth.slice(0, 4)), tg.active])
			print("  [t=%4.0f] floor=%d cell=%s hp=%d/%d shield=%d enemies=%d move=(%.1f,%.1f) shoot=%s pos=(%d,%d) weapon=%s %s" % [sim_time, G.floor_num, dungeon.current_cell, player.hp, player.max_hp, int(player.shield), _enemies().size(), _move.x, _move.y, _shoot, player.global_position.x, player.global_position.y, player.weapon.get("name", "?"), _goal_desc])
	_think_t -= delta
	_dodge_gap -= delta
	if _think_t <= 0.0:
		_think_t = THINK_INTERVAL
		_think(THINK_INTERVAL)
	_act()

# ------------------------------------------------------------------ nhận thức
func _enemies() -> Array:
	var out: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.alive and e.active:
			out.append(e)
	for b in get_tree().get_nodes_in_group("boss"):
		if is_instance_valid(b) and b.alive and b.active:
			out.append(b)
	return out

func _nearest(list: Array, from: Vector2):
	var best = null
	var bd: float = INF
	for e in list:
		var d: float = from.distance_to(e.global_position)
		if d < bd:
			bd = d
			best = e
	return best

## Mục tiêu: gần nhất trong số quái đang THẤY được (tia nhìn không bị tường chắn); không ai thấy thì gần nhất.
func _pick_target(list: Array, pp: Vector2):
	var best = null
	var bd: float = INF
	for e in list:
		var d: float = pp.distance_to(e.global_position)
		if d < bd and _los(pp, e.global_position):
			bd = d
			best = e
	return best if best != null else _nearest(list, pp)

## Điểm ngắm có đón đầu: vị trí mục tiêu cộng vận tốc nhân thời gian đạn bay (tối đa LEAD_MAX_T giây).
func _lead_point(pp: Vector2, t) -> Vector2:
	var tp: Vector2 = t.global_position
	if bool(player.weapon.get("is_melee", false)):
		return tp
	var v = t.get("velocity")
	var bspeed: float = float(player.weapon.get("speed", 600.0))
	if not (v is Vector2) or bspeed < 50.0:
		return tp
	var flight: float = minf(LEAD_MAX_T, pp.distance_to(tp) / bspeed)
	return tp + (v as Vector2) * flight * LEAD_FACTOR

func _is_kiter(e) -> bool:
	var d = e.get("data")
	return d is Dictionary and (bool(d.get("kiter", false)) or bool(d.get("shooter", false)))

## Bẫy/ô nguy hiểm trên sàn (gai, lava, độc, băng): nhận diện bằng đường dẫn script.
func _floor_traps() -> Array:
	var out: Array = []
	for n in G.world.get_children():
		if not is_instance_valid(n) or not (n is Area2D):
			continue
		var sc = n.get_script()
		if sc == null:
			continue
		var path: String = String(sc.resource_path)
		if path.ends_with("spike_trap.gd") or path.ends_with("lava_tile.gd") or path.ends_with("poison_tile.gd") or path.ends_with("ice_tile.gd"):
			out.append(n)
	return out

func _hazards() -> Array:
	var out: Array = []
	for n in dungeon.entities.get_children() if dungeon.entities != null else []:
		pass
	for n in G.world.get_children():
		if is_instance_valid(n) and n is Area2D and n.get("telegraph_time") != null and n.get("radius") != null and n.get("tick_interval") != null:
			out.append(n)
	return out

func _pickups(kind: String) -> Array:
	var out: Array = []
	for n in G.world.get_children():
		if is_instance_valid(n) and n is Area2D and n.get("kind") == kind and n.get("tick_interval") == null:
			out.append(n)
	return out

# ------------------------------------------------------------------ quyết định
func _think(dt: float) -> void:
	var pp: Vector2 = player.global_position
	var enemies: Array = _enemies()
	var target = _pick_target(enemies, pp)
	var steer: Vector2 = Vector2.ZERO
	_shoot = false
	stats["think"] += 1
	player.ai_aim_point = null

	# 1) tránh vùng nguy hiểm đang báo trước / đang cháy
	var in_hazard: bool = false
	for hz in _hazards():
		var r: float = float(hz.radius) + HAZARD_MARGIN
		var off: Vector2 = pp - hz.global_position
		var d: float = off.length()
		if d < r:
			in_hazard = true
			steer += off.normalized() * (1.6 + (r - d) / r) if d > 1.0 else Vector2.RIGHT
	if in_hazard:
		stats["hazard_ticks"] += 1
	for tr in _floor_traps():
		var toff: Vector2 = pp - tr.global_position
		var td: float = toff.length()
		if td < TRAP_AVOID_DIST and td > 1.0:
			steer += toff.normalized() * (TRAP_AVOID_DIST - td) / TRAP_AVOID_DIST * 2.2
	var bullet_steer: Vector2 = _bullet_sidestep(pp)
	steer += bullet_steer
	# 2) lăn né đạn địch / vùng nguy hiểm (không hoàn hảo)
	if _dodge_gap <= 0.0 and player.dodge_cooldown.is_stopped() and not player.rolling:
		var threat: Vector2 = Vector2.ZERO
		var danger: bool = in_hazard
		for b in get_tree().get_nodes_in_group("enemy_bullets"):
			if not is_instance_valid(b):
				continue
			var to_p: Vector2 = pp - b.global_position
			if to_p.length() < BULLET_DANGER_DIST and b.dir.dot(to_p.normalized()) > 0.55:
				danger = true
				threat = b.dir
				break
		if danger and randf() < DODGE_REACT_CHANCE:
			var side: Vector2 = Vector2(-threat.y, threat.x) if threat != Vector2.ZERO else (steer.normalized() if steer != Vector2.ZERO else Vector2.RIGHT)
			if randf() < 0.5 and threat != Vector2.ZERO:
				side = -side
			player._start_roll(side.normalized())
			stats["rolls"] += 1
			_dodge_gap = DODGE_MIN_GAP

	var kills_now: int = int(G.run_stats.get("kills", 0))
	if kills_now != _last_kills or target == null or target.is_in_group("boss"): # trùm không tính là "kẹt": đánh trùm lâu là bình thường
		_last_kills = kills_now
		_last_progress = sim_time
	elif sim_time - _last_progress > HUNT_AFTER and sim_time > _hunt_until and enemies.size() <= 2:
		_hunt_until = sim_time + HUNT_DURATION
		_last_progress = sim_time
		stats["hunts"] = int(stats.get("hunts", 0)) + 1
	var boss_steer: Vector2 = _boss_defense(pp)
	if target != null and sim_time < _hunt_until:
		# săn: bỏ luật giữ khoảng cách, đi thẳng theo đường tới mục tiêu và bắn khi thấy
		player.ai_aim_point = target.global_position
		steer += _path_dir(pp, target.global_position)
		_shoot = _los(pp, target.global_position)
		_maybe_skill(enemies, pp, target)
	elif target != null:
		var is_boss: bool = target.is_in_group("boss")
		var melee: bool = bool(player.weapon.get("is_melee", false))
		var to_t: Vector2 = target.global_position - pp
		var dist: float = to_t.length()
		var dir_t: Vector2 = to_t.normalized() if dist > 1.0 else Vector2.RIGHT
		player.ai_aim_point = _lead_point(pp, target)
		if not _los(pp, target.global_position):
			# bị tường chắn: đi theo đường tìm được tới mục tiêu thay vì xoay vòng vô ích
			steer += _path_dir(pp, target.global_position) * 1.2
			stats["nolos_ticks"] += 1
			_shoot = false
		elif melee:
			var reach: float = float(player.weapon.get("range", 55.0)) + MELEE_ENGAGE_PAD
			steer += dir_t if dist > reach * 0.8 else Vector2.ZERO
			_shoot = dist < reach + 25.0
		else:
			var keep: float = BOSS_KEEP_DIST if is_boss else RANGED_KEEP_DIST
			if _is_kiter(target):
				keep = KITER_CHASE_DIST # cung thủ/pháp sư hay lùi: phải áp sát chứ không đứng chờ
			var perp: Vector2 = Vector2(-dir_t.y, dir_t.x) * (1.0 if int(sim_time / 2.0) % 2 == 0 else -1.0)
			if dist < RANGED_TOO_CLOSE:
				steer += -dir_t * 1.2 + perp * 0.5
			elif dist > keep + 60.0:
				steer += dir_t * 0.9
			else:
				steer += perp * 0.7
			_shoot = dist < 560.0
		steer += _repel(enemies, pp, target)
		_maybe_skill(enemies, pp, target)
		steer += _wall_push(pp)
		steer += boss_steer
	else:
		steer += _navigate(pp)
	if _shoot:
		stats["shoot_ticks"] += 1
	# 3) chống kẹt
	steer = _anti_stuck(steer, pp, dt, target == null)
	_move = steer.normalized() if steer.length() > 0.05 else Vector2.ZERO

## Tia nhìn dừng trước mục tiêu 28px: quái đứng sát chân tường thì tâm nó nằm trong vùng va chạm tường,
## nếu bắn tia tới đúng tâm sẽ luôn bị "chắn" dù đạn vẫn trúng được.
func _los(a: Vector2, b: Vector2) -> bool:
	var dir: Vector2 = b - a
	var stop: Vector2 = b - dir.normalized() * minf(28.0, dir.length())
	var q := PhysicsRayQueryParameters2D.create(a, stop, G.L_WORLD)
	return dungeon.get_world_2d().direct_space_state.intersect_ray(q).is_empty()

func _path_dir(pp: Vector2, goal: Vector2) -> Vector2:
	var path: PackedVector2Array = dungeon.find_path(pp, goal)
	if path.size() >= 2:
		var i: int = 1
		while i < path.size() - 1 and pp.distance_to(path[i]) < 22.0:
			i += 1
		return (path[i] - pp).normalized()
	return (goal - pp).normalized()

## Đẩy ra khỏi mọi quái ở gần (tỉ lệ nghịch khoảng cách) — tránh bị dồn bởi nhiều quái cùng lúc.
## Cận chiến thì chỉ đẩy khi quái quá sát (vẫn phải áp sát để đánh).
func _repel(enemies: Array, pp: Vector2, target) -> Vector2:
	var melee: bool = bool(player.weapon.get("is_melee", false))
	var push: Vector2 = Vector2.ZERO
	for e in enemies:
		var off: Vector2 = pp - e.global_position
		var d: float = off.length()
		var lim: float = 60.0 if melee else REPEL_DIST
		if d < lim and d > 1.0:
			push += off.normalized() * (lim - d) / lim
		if d < CONTACT_ROLL_DIST and _dodge_gap <= 0.0 and player.dodge_cooldown.is_stopped() and not player.rolling and randf() < DODGE_REACT_CHANCE:
			var away: Vector2 = off.normalized() if d > 1.0 else Vector2.RIGHT
			player._start_roll((away + Vector2(-away.y, away.x) * (0.5 if randf() < 0.5 else -0.5)).normalized())
			stats["rolls"] += 1
			_dodge_gap = DODGE_MIN_GAP
	return push * REPEL_WEIGHT

## Phòng thủ trước trùm dựa trên trạng thái trùm công bố (charging / tele_mode): nghiêng người khỏi đường lao,
## và lùi ra khỏi tầm đòn đang báo trước (slam/ring/...). Lăn né khi đòn sắp trúng.
## Với từng đạn địch: tính điểm gần Player nhất trong BULLET_LOOKAHEAD giây; nếu sẽ trúng thì nghiêng người sang
## phía vuông góc với đường đạn (không cần lăn). Đạn xa hoặc bay lệch thì bỏ qua.
func _bullet_sidestep(pp: Vector2) -> Vector2:
	var steer: Vector2 = Vector2.ZERO
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		if not is_instance_valid(b):
			continue
		var v: Vector2 = b.dir * float(b.speed)
		var rel: Vector2 = pp - b.global_position
		var vv: float = v.length_squared()
		if vv < 1.0:
			continue
		var t_cp: float = clampf(rel.dot(v) / vv, 0.0, BULLET_LOOKAHEAD)
		var closest: Vector2 = b.global_position + v * t_cp
		var miss: Vector2 = pp - closest
		if miss.length() < BULLET_HIT_RADIUS + float(b.radius):
			var side: Vector2 = Vector2(-b.dir.y, b.dir.x)
			if side.dot(miss) < 0.0:
				side = -side
			steer += side * (1.6 - t_cp)
	return steer

func _boss_defense(pp: Vector2) -> Vector2:
	var steer: Vector2 = Vector2.ZERO
	for b in get_tree().get_nodes_in_group("boss"):
		if not is_instance_valid(b) or not b.alive or not b.active:
			continue
		var to_p: Vector2 = pp - b.global_position
		var dist: float = to_p.length()
		if bool(b.charging):
			var cd: Vector2 = b.charge_dir
			var along: float = cd.dot(to_p)
			var lateral: Vector2 = to_p - cd * along
			if along > -50.0 and lateral.length() < 120.0 and dist < 320.0:
				var side: Vector2 = lateral.normalized() if lateral.length() > 8.0 else Vector2(-cd.y, cd.x)
				steer += side * 2.2
				if _dodge_gap <= 0.0 and player.dodge_cooldown.is_stopped() and not player.rolling and lateral.length() < 90.0 and dist < 200.0:
					player._start_roll(side.normalized())
					stats["rolls"] += 1
					_dodge_gap = DODGE_MIN_GAP
		elif String(b.tele_mode) != "" and dist < TELEGRAPH_AVOID_DIST:
			var away: Vector2 = to_p.normalized() if dist > 1.0 else Vector2.RIGHT
			steer += away * (1.8 + (TELEGRAPH_AVOID_DIST - dist) / TELEGRAPH_AVOID_DIST)
			if float(b.tele_t) > 0.55 and dist < 170.0 and _dodge_gap <= 0.0 and player.dodge_cooldown.is_stopped() and not player.rolling:
				player._start_roll(away)
				stats["rolls"] += 1
				_dodge_gap = DODGE_MIN_GAP
	return steer

func _maybe_skill(enemies: Array, pp: Vector2, target) -> void:
	var cs = player.class_skill
	if cs == null or not cs.has_method("is_ready") or not cs.is_ready():
		return
	var near: int = 0
	for e in enemies:
		if pp.distance_to(e.global_position) <= SKILL_RADIUS:
			near += 1
	if near >= SKILL_ENEMY_COUNT or (target != null and target.is_in_group("boss") and pp.distance_to(target.global_position) < 420.0):
		if cs.try_activate():
			stats["skills"] += 1

## Đẩy nhẹ vào tâm phòng khi sát tường (khi kite không tự dồn mình vào góc).
func _wall_push(pp: Vector2) -> Vector2:
	var rect: Rect2 = dungeon._room_rect(dungeon.current_cell, 3)
	var push: Vector2 = Vector2.ZERO
	if pp.x < rect.position.x + WALL_PUSH_DIST: push.x += 1.0
	if pp.x > rect.end.x - WALL_PUSH_DIST: push.x -= 1.0
	if pp.y < rect.position.y + WALL_PUSH_DIST: push.y += 1.0
	if pp.y > rect.end.y - WALL_PUSH_DIST: push.y -= 1.0
	return push * 1.4

## Không còn quái: nhặt máu/xu gần, rồi tới cổng (nếu trùm đã hạ) hoặc phòng trùm.
func _navigate(pp: Vector2) -> Vector2:
	var goal = null
	if player.hp < player.max_hp * HEAL_SEEK_HP:
		var h = _nearest(_pickups("heal"), pp)
		if h != null and pp.distance_to(h.global_position) < HEAL_SEEK_RANGE:
			goal = h.global_position
	if goal == null:
		var c = _nearest(_pickups("coin"), pp)
		if c != null and pp.distance_to(c.global_position) < PICKUP_RANGE:
			goal = c.global_position
	if goal == null:
		var portal = _nearest(_pickups("portal"), pp)
		if portal != null:
			goal = portal.global_position
	if goal == null:
		goal = dungeon.room_center(dungeon.boss_cell)
	var path: PackedVector2Array = dungeon.find_path(pp, goal)
	if path.size() < 2:
		# không có đường theo lưới: đi theo đồ thị phòng tới phòng kế trên đường tới trùm
		var nxt = _next_cell_toward_boss()
		if nxt != null:
			goal = dungeon.room_center(nxt)
			path = dungeon.find_path(pp, goal)
	_goal_desc = "goal=(%d,%d) path=%d" % [goal.x, goal.y, path.size()]
	if path.size() >= 2:
		var i: int = 1
		while i < path.size() - 1 and pp.distance_to(path[i]) < 22.0:
			i += 1
		return (path[i] - pp).normalized()
	return (goal - pp).normalized()

## BFS trên đồ thị cửa của các phòng: ô phòng kế tiếp cần đi để tới phòng trùm (null nếu đã ở đó / không có).
func _next_cell_toward_boss():
	var start: Vector2i = dungeon.current_cell
	var goal: Vector2i = dungeon.boss_cell
	if start == goal or not dungeon.rooms.has(start):
		return null
	var prev: Dictionary = {start: start}
	var queue: Array = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c == goal:
			break
		for d in dungeon.rooms[c]["doors"]:
			var n: Vector2i = c + d
			if dungeon.rooms.has(n) and not prev.has(n):
				prev[n] = c
				queue.append(n)
	if not prev.has(goal):
		return null
	var c2: Vector2i = goal
	while prev[c2] != start:
		c2 = prev[c2]
	return c2

func _anti_stuck(steer: Vector2, pp: Vector2, dt: float, navigating: bool) -> Vector2:
	if _jiggle_t > 0.0:
		_jiggle_t -= dt
		return _jiggle_dir
	_stuck_acc += dt
	if _stuck_acc >= 1.0: # so vị trí mỗi giây: đi < 25px trong khi đang muốn đi = kẹt (tường, góc, cột)
		if steer.length() > 0.05 and pp.distance_to(_last_pos) < 25.0 and not player.rolling:
			_stuck_t += _stuck_acc
		else:
			_stuck_t = 0.0
		_last_pos = pp
		_stuck_acc = 0.0
	if _stuck_t >= STUCK_SECONDS:
		_stuck_t = 0.0
		_jiggle_t = 1.0
		_jiggle_dir = Vector2.from_angle(randf() * TAU)
		stats["stuck_events"] += 1
	return steer

# ------------------------------------------------------------------ hành động (Input giống người chơi)
func _act() -> void:
	_set_action("move_left", maxf(0.0, -_move.x))
	_set_action("move_right", maxf(0.0, _move.x))
	_set_action("move_up", maxf(0.0, -_move.y))
	_set_action("move_down", maxf(0.0, _move.y))
	_set_action("shoot", 1.0 if _shoot else 0.0)

func _set_action(a: String, strength: float) -> void:
	var cur: float = float(_held.get(a, 0.0))
	if strength > 0.01:
		Input.action_press(a, strength)
	elif cur > 0.0:
		Input.action_release(a)
	_held[a] = strength

func _release_all() -> void:
	for a in _held:
		Input.action_release(a)
	_held.clear()

# ------------------------------------------------------------------ chọn buff
func _on_buff_choice(choices: Array) -> void:
	_choose_buff.call_deferred(choices)

func _find_picker() -> Node:
	if is_instance_valid(_picker):
		return _picker
	for c in main.get_children():
		var s = c.get_script()
		if s != null and String(s.resource_path).ends_with("buff_picker.gd"):
			_picker = c
			return c
	return null

func _choose_buff(choices: Array) -> void:
	var picker: Node = _find_picker()
	if picker == null or choices.is_empty():
		return
	var best: String = String(choices[0])
	var best_score: float = -1.0
	for id in choices:
		var info: Dictionary = G.buff_info(String(id))
		var sc: float = float(TIER_SCORE.get(String(info.get("tier", "common")), 1.0))
		if not G.synergy_owned_partner_names(String(id)).is_empty():
			sc += 1.0
		sc += randf() * 0.5
		if sc > best_score:
			best_score = sc
			best = String(id)
	stats["buffs"].append(best)
	picker._on_card_chosen(best)
