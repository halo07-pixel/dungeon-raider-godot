extends SceneTree
## Bot đo độ khó (không chạy trong run_all): godot --headless --path . -s tools/_hkbot.gd -- <kind> [lần]
## kind = crawler|flyer|spitter|charger|guard|dropper|warden|wraith|lord|brute|hexer. Bot "người chơi trung bình": tiến lại, chém khi tới tầm,
## nhảy né sau ~0.25s khi quái/boss vào thế đánh. In: số lần bị trúng, thời gian hạ, tỉ lệ hạ được trong 90s.
const DANGER: Array = ["windup", "lunge", "wind_slash", "wind_slam", "air"]
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
	var kind: String = args[0]
	var runs: int = int(args[1]) if args.size() > 1 else 6
	var St = load("res://hk/state.gd")
	var boss_kinds: Array = ["warden", "wraith", "lord", "brute", "hexer", "colossus", "many_faced"]
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
			if st in DANGER:
				danger_t += dt
			else:
				danger_t = 0.0
			if danger_t > 0.25 and dist < 260.0 and dodge_t <= 0.0:
				dodge_t = 0.45
				tap("hk_jump")
			if dodge_t > 0.0:
				dodge_t -= dt
				hold("hk_left", dir > 0)
				hold("hk_right", dir < 0)
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
			if dy < -110.0 and dist < 80.0:
				hold("hk_up", true)
				tap("hk_attack")
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
	print("RESULT %s: wins=%d/%d  hits/run=%.1f  time/run=%.1fs" % [kind, wins, runs, float(tot_hits) / runs, tot_time / runs])
	quit()
