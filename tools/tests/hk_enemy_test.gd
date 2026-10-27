extends SceneTree
## Test quái mới: guard (khiên chặn chính diện, nhận sát thương từ sau/trên, không cho Soul khi bị chặn, hạ khiên khi recover),
## dropper (treo -> rung -> rơi khi người chơi ở dưới -> choáng -> bò lên lại), mini-boss brute/hexer (có thể hạ, đặt cờ).
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_enemy_test_save.json"
	var room := Node2D.new()
	room.set_script(load("res://hk/room.gd"))
	root.add_child(room)
	var grid: Array = []
	for r in 20:
		grid.append("#".repeat(60) if r == 19 else "#" + ".".repeat(58) + "#")
	room.build("test", {"area": "gate", "doors": {}, "grid": grid})
	var p := CharacterBody2D.new()
	p.set_script(load("res://hk/player.gd"))
	p.position = Vector2(300, 560)
	root.add_child(p)
	await frames(30)
	# ---- guard
	var g := CharacterBody2D.new()
	g.set_script(load("res://hk/enemy.gd"))
	g.kind = "guard"
	g.position = Vector2(900, 560)
	root.add_child(g)
	await frames(30)
	g.set_physics_process(false)
	g.dir = -1   # nhìn sang trái
	var hp0: int = g.hp
	var front := Vector2(g.global_position.x - 60.0, g.global_position.y)
	var behind := Vector2(g.global_position.x + 60.0, g.global_position.y)
	var above := Vector2(g.global_position.x - 20.0, g.global_position.y - 120.0)
	ck(g.take_hit(5, front) == false and g.hp == hp0, "khiên chặn đòn chính diện")
	ck(g.take_hit(5, behind) == true and g.hp == hp0 - 5, "đánh từ sau thì trúng")
	ck(g.take_hit(5, above) == true and g.hp == hp0 - 10, "chém từ trên xuống thì trúng")
	g.state = "recover"
	ck(g.take_hit(5, front) == true and g.hp == hp0 - 15, "hạ khiên (recover) thì chính diện cũng trúng")
	g.state = "idle"
	# người chơi chém khiên: không cộng Soul, bị bật lùi
	var soul0: int = St.soul
	p.global_position = Vector2(g.global_position.x - 70.0, g.global_position.y)
	p.facing = 1
	var ev := InputEventAction.new()
	ev.action = "hk_attack"
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(6)
	ev.pressed = false
	Input.parse_input_event(ev)
	await frames(10)
	ck(St.soul == soul0 and g.hp == hp0 - 15, "chém vào khiên: không Soul, không mất máu (soul %d hp %d)" % [St.soul, g.hp])
	g.queue_free()
	await frames(2)
	# ---- dropper
	var d := CharacterBody2D.new()
	d.set_script(load("res://hk/enemy.gd"))
	d.kind = "dropper"
	d.position = Vector2(700, 80)
	root.add_child(d)
	p.global_position = Vector2(300, 570)
	await frames(20)
	ck(d.state == "hang" and absf(d.global_position.y - 80.0) < 1.0, "dropper treo yên khi người chơi ở xa (%s)" % d.state)
	p.global_position = Vector2(700, 570)
	p.velocity = Vector2.ZERO
	var seen: Dictionary = {}
	var f: int = 0
	while f < 400 and not seen.has("rise"):
		await physics_frame
		f += 1
		p.global_position = Vector2(700, 570)   # giữ người chơi bên dưới (tránh bị đánh mà chết)
		p.invuln = 5.0
		seen[d.state] = true
	ck(seen.has("shake") and seen.has("drop") and seen.has("land") and seen.has("rise"), "dropper: rung -> rơi -> choáng -> bò lên (%s)" % str(seen.keys()))
	p.global_position = Vector2(300, 570)
	f = 0
	while f < 400 and d.state != "hang":
		await physics_frame
		f += 1
	ck(d.state == "hang" and absf(d.global_position.y - 80.0) < 2.0, "dropper về lại chỗ treo")
	d.queue_free()
	# ---- mini-boss
	for kind in ["brute", "hexer"]:
		var b := CharacterBody2D.new()
		b.set_script(load("res://hk/boss.gd"))
		b.kind = kind
		b.position = Vector2(900, 520)
		root.add_child(b)
		b.arena = room.bounds()
		var defeated: Array = [false]
		b.defeated.connect(func(): defeated[0] = true)
		p.global_position = Vector2(700, 560)
		p.invuln = 99.0
		await frames(40)
		ck(b.state != "dormant", "%s: vào trận khi người chơi lại gần (%s)" % [kind, b.state])
		var states: Dictionary = {}
		var f0: int = Engine.get_physics_frames()
		var stage: int = 0
		while Engine.get_physics_frames() - f0 < 2400 and is_instance_valid(b):
			Engine.time_scale = 3.0   # hitstop/reset đặt lại time_scale: ép lại mỗi khung
			await physics_frame
			if not is_instance_valid(b):
				break
			states[b.state] = true
			var el: int = Engine.get_physics_frames() - f0
			if stage == 0 and el > 600:
				b.take_hit(b.hp - 1, p.global_position)   # xuống 1 máu (qua pha 2) để test nhanh
				stage = 1
			elif stage == 1 and el > 720 and b.state != "intro":
				b.take_hit(1, p.global_position)
				stage = 2
		Engine.time_scale = 1.0
		ck(defeated[0], "%s: hạ được và phát tín hiệu defeated" % kind)
		var want: Array = ["wind_slam", "wind_slash"] if kind == "brute" else ["wind_bolt", "wind_conjure", "fade_out"]
		var hit: int = 0
		for w in want:
			if states.has(w):
				hit += 1
		ck(hit >= (1 if kind == "brute" else 2), "%s: dùng các đòn riêng (%s)" % [kind, str(states.keys())])
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
