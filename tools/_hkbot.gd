extends SceneTree
## Bot đo độ khó (không chạy trong run_all; test `hk_bot_test.gd` chỉ kiểm bot chạy được): godot --headless --path . -s tools/_hkbot.gd -- <kind|all> [lần]
## kind = crawler|flyer|spitter|charger|guard|dropper|sentry|reviver|cinder|bubbler|warden|wraith|lord|brute|hexer|colossus|many_faced; `all` = lần lượt tất cả rồi in bảng.
## Bot "người chơi trung bình": tiến lại, chém khi tới tầm, nhảy né sau ~0.25s khi quái/boss vào thế đánh hoặc khi vùng gây hại (gai, lửa, sóng lửa, bục nóng) sắp chạm,
## nhảy lên chém khi boss bay ở trên cao. Không vòng ra sau khiên (guard/sentry bị chặn nhiều hơn người thật). In: số lần bị trúng, thời gian hạ, tỉ lệ hạ được trong 90s.
const ALL: Array = ["crawler", "flyer", "spitter", "charger", "guard", "dropper", "sentry", "reviver", "cinder", "bubbler", "warden", "brute", "hexer", "wraith", "colossus", "lord", "many_faced"]
const HAZARD_LEAD: float = 0.35   # coi vùng là nguy hiểm khi còn ≤ chừng này giây nữa có hiệu lực (người thật nghe âm báo)
const HAZARD_PAD: float = 60.0    # lề né quanh vùng gây hại
const DANGER: Array = ["windup", "lunge", "bash", "dive", "shake", "wind_slash", "wind_slam", "wind_dive", "air"]
var _pulse: Array = []

func tap(a: String) -> void:
	var e := InputEventAction.new()
	e.action = a
	e.pressed = true
	Input.parse_input_event(e)
	_pulse.append(a)

func release_pulses() -> void:
	for a in _pulse:
		var e := InputEventAction.new()
		e.action = a
		e.pressed = false
		Input.parse_input_event(e)
	_pulse.clear()

## Vùng gây hại (zone.gd) đang hoặc sắp có hiệu lực mà người chơi đứng gần: trả tâm vùng để bot chạy ngược lại, không có thì null.
func hazard_center(p: Node2D, owners: Array):
	var body := Rect2(p.global_position - Vector2(12, 22), Vector2(24, 44)).grow(HAZARD_PAD)
	for o in owners:
		if not is_instance_valid(o):
			continue
		for n in o.get_children():
			if n.has_method("active") and n.get("kind") != null and n.kind in ["spikes", "firewave", "heat", "flame", "pillar"]:
				if (n.active() or n.delay <= HAZARD_LEAD) and body.intersects(n.current()):
					return n.current().get_center()
	return null

func hold(a: String, on: bool) -> void:
	if on:
		Input.action_press(a)
	else:
		Input.action_release(a)

func _init() -> void:
	await process_frame
	Engine.max_fps = 0
	Engine.max_physics_steps_per_frame = 64
	load("res://hk/input.gd").ensure()
	var args := OS.get_cmdline_user_args()
	var kinds: Array = ALL if args[0] == "all" else [args[0]]
	var runs: int = int(args[1]) if args.size() > 1 else 6
	var St = load("res://hk/state.gd")
	var boss_kinds: Array = ["warden", "wraith", "lord", "brute", "hexer", "colossus", "many_faced"]
	var table: Array = []
	for kind in kinds:
		var is_boss: bool = kind in boss_kinds
		var tot_hits: int = 0
		var tot_time: float = 0.0
		var wins: int = 0
		for run in runs:
			seed(1000 + run)
			St.boot = "keep"
			St.reset()
			St.save_path = "user://hk_bot_save.json"
			St.give_ability("dash")
			St.hp = 50
			var room := Node2D.new()
			room.set_script(load("res://hk/room.gd"))
			root.add_child(room)
			var grid: Array = []
			for r in 20:
				grid.append("#".repeat(60) if r == 19 else "#" + ".".repeat(58) + "#")
			room.build("bot", {"area": "gate", "doors": {}, "grid": grid})
			var p := CharacterBody2D.new()
			p.set_script(load("res://hk/player.gd"))
			p.position = Vector2(500, 560)
			root.add_child(p)
			var hits: Array = [0]
			var last_hp: Array = [St.hp]
			p.health_changed.connect(func(h, _m):
				if h < last_hp[0]:
					hits[0] += last_hp[0] - h
				last_hp[0] = h)
			var e := CharacterBody2D.new()
			if is_boss:
				e.set_script(load("res://hk/boss.gd"))
				e.kind = kind
				e.position = Vector2(1200, 540)
				root.add_child(e)
				e.arena = room.bounds()
			else:
				e.set_script(load("res://hk/enemy.gd"))
				e.kind = kind
				e.position = Vector2(900, 540 if kind != "flyer" else 480)
				if kind == "dropper":
					e.position = Vector2(700, 80)
				root.add_child(e)
			for i in 40:
				await physics_frame
			hits[0] = 0
			var t: float = 0.0
			var danger_t: float = 0.0
			var dodge_t: float = 0.0
			var flee_x: float = 0.0
			var last_f: int = Engine.get_physics_frames()
			while is_instance_valid(e) and t < 90.0 and St.hp > 0:
				await physics_frame
				Engine.time_scale = 3.0   # hitstop/reset đặt lại time_scale, ép lại mỗi khung
				release_pulses()
				if not is_instance_valid(e):
					break
				var dt: float = float(Engine.get_physics_frames() - last_f) / 60.0   # time_scale chạy nhiều tick mỗi lần await
				last_f = Engine.get_physics_frames()
				t += dt
				var dx: float = e.global_position.x - p.global_position.x
				var dy: float = e.global_position.y - p.global_position.y
				var dir: int = 1 if dx > 0 else -1
				var dist: float = absf(dx)
				var reach: float = 92.0   # cố định để so sánh công bằng giữa các phiên bản (hộp đổi theo bản)
				var st: String = String(e.get("state")) if e.get("state") != null else ""
				if kind == "dropper" and st == "hang":
					reach = 30.0   # dropper chỉ rơi khi người chơi đứng ngay dưới (<70px): bot phải chui vào dưới nó rồi né
				if st in DANGER:
					danger_t += dt
				else:
					danger_t = 0.0
				if dodge_t <= 0.0:
					var hz = hazard_center(p, [e, root])
					if hz != null:   # vùng gây hại sắp chạm: nhảy và chạy ngược khỏi vùng
						dodge_t = 0.45
						flee_x = hz.x
						tap("hk_jump")
					elif danger_t > 0.25 and dist < 260.0:
						dodge_t = 0.45
						flee_x = e.global_position.x
						tap("hk_jump")
				if dodge_t > 0.0:
					dodge_t -= dt
					var away_right: bool = flee_x < p.global_position.x
					hold("hk_left", not away_right)
					hold("hk_right", away_right)
					continue
				if dist > reach:
					hold("hk_left", dir < 0)
					hold("hk_right", dir > 0)
				else:
					hold("hk_left", false)
					hold("hk_right", false)
					if p.facing != dir:
						hold("hk_left", dir < 0)
						hold("hk_right", dir > 0)
					elif absf(dy) < 90.0 or dy > -90.0 and dy < 40.0:
						tap("hk_attack")
				if dy < -90.0 and dist < 110.0:   # mục tiêu ở trên cao (boss bay): nhảy lên chém lên
					hold("hk_up", true)
					tap("hk_attack")
					if p.is_on_floor():
						tap("hk_jump")
				else:
					hold("hk_up", false)
			for a in ["hk_left", "hk_right", "hk_up"]:
				hold(a, false)
			release_pulses()
			var won: bool = not is_instance_valid(e) or (is_boss and e.hp <= 0)
			if won:
				wins += 1
			tot_hits += hits[0]
			tot_time += t
			print("  run %d: %s hits=%d t=%.1fs" % [run, "WIN" if won else "fail", hits[0], t])
			if is_instance_valid(e):
				e.queue_free()
			p.queue_free()
			room.queue_free()
			await process_frame
		var line: String = "RESULT %s: wins=%d/%d  hits/run=%.1f  time/run=%.1fs" % [kind, wins, runs, float(tot_hits) / runs, tot_time / runs]
		print(line)
		table.append(line)
	if table.size() > 1:
		print("==== BẢNG (%d lần/loại) ====" % runs)
		for l in table:
			print(l)
	quit()
