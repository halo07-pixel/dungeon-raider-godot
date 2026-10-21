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

func _is_kiter(e) -> bool:
	var d = e.get("data")
	return d is Dictionary and (bool(d.get("kiter", false)) or bool(d.get("shooter", false)))

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
		player.ai_aim_point = target.global_position
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
	_goal_desc = "goal=(%d,%d) path=%d" % [goal.x, goal.y, path.size()]
	if path.size() >= 2:
		var i: int = 1
		while i < path.size() - 1 and pp.distance_to(path[i]) < 22.0:
			i += 1
		return (path[i] - pp).normalized()
	return (goal - pp).normalized()

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
