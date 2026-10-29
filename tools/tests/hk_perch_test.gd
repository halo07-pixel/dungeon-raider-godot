extends SceneTree
## Bug bục lơ lửng: chém không xuyên sàn (nhưng chém từ dưới lên xuyên bục một chiều thì được), đạn bay xuyên bục một chiều
## nhưng dừng ở tường đặc, boss mặt đất nhảy lên bục khi người chơi nấp ở trên.
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
	St.save_path = "user://hk_perch_test_save.json"
	var room := Node2D.new()
	room.set_script(load("res://hk/room.gd"))
	root.add_child(room)
	var grid: Array = []
	for r in 20:
		if r == 19:
			grid.append("#".repeat(60))
		elif r == 14:
			grid.append("#" + ".".repeat(19) + "=".repeat(10) + ".".repeat(29) + "#")
		else:
			grid.append("#" + ".".repeat(58) + "#")
	room.build("test", {"area": "gate", "doors": {}, "grid": grid})
	var p := CharacterBody2D.new()
	p.set_script(load("res://hk/player.gd"))
	root.add_child(p)
	var b := CharacterBody2D.new()
	b.set("kind", "warden")
	b.set_script(load("res://hk/boss.gd"))
	b.kind = "warden"
	b.position = Vector2(1400, 560)
	root.add_child(b)
	b.arena = room.bounds()
	await frames(20)
	b.set_physics_process(false)
	b.state = "walk"
	var floor_y: float = 19.0 * 32.0
	b.global_position = Vector2(800, floor_y - b._size.y * 0.5)
	p.set_physics_process(false)
	await frames(2)
	# 1) người chơi đứng trên bục, boss dưới sàn: chém xuống không trúng
	p.global_position = Vector2(800, 14.0 * 32.0 - 22.0)
	p.attack_dir = Vector2.DOWN
	p._attack_t = 0.2
	p._hit_set.clear()
	var hp0: int = b.hp
	p._tick_attack(0.01)
	ck(b.hp == hp0, "chém xuyên bục xuống boss phải bị chặn (hp %d -> %d)" % [hp0, b.hp])
	# 2) đối chứng: cùng tầm, không có bục chắn -> trúng
	p.global_position = Vector2(700, floor_y - 22.0)
	p.attack_dir = Vector2.RIGHT
	p._attack_t = 0.2
	p._hit_set.clear()
	p._tick_attack(0.01)
	ck(b.hp < hp0, "chém ngang cùng mặt sàn vẫn trúng")
	# 3) người chơi dưới bục, boss trên bục: chém lên xuyên bục một chiều
	b.global_position = Vector2(800, 14.0 * 32.0 - b._size.y * 0.5)
	await frames(2)
	hp0 = b.hp
	p.global_position = Vector2(800, 14.0 * 32.0 + 70.0)
	p.attack_dir = Vector2.UP
	p._attack_t = 0.2
	p._hit_set.clear()
	p._tick_attack(0.01)
	ck(b.hp < hp0, "chém từ dưới lên qua bục một chiều vẫn trúng")
	# 4) đạn: xuyên bục một chiều từ dưới lên, nhưng chạm tường đặc thì biến mất
	var pr := Area2D.new()
	pr.set_script(load("res://hk/projectile.gd"))
	pr.position = Vector2(850, 14.0 * 32.0 + 60.0)
	pr.vel = Vector2(0, -300)
	root.add_child(pr)
	await frames(30)
	ck(is_instance_valid(pr) and pr.position.y < 14.0 * 32.0, "đạn bay xuyên bục một chiều (y=%s)" % str(pr.position.y if is_instance_valid(pr) else "đã mất"))
	var pw := Area2D.new()
	pw.set_script(load("res://hk/projectile.gd"))
	pw.position = Vector2(300, 400)
	pw.vel = Vector2(-600, 0)
	root.add_child(pw)
	await frames(40)
	ck(not is_instance_valid(pw) or pw.is_queued_for_deletion(), "đạn dừng ở tường đặc")
	if is_instance_valid(pr):
		pr.queue_free()
	# 5) boss mặt đất nhảy lên bục khi người chơi nấp ở trên
	b.global_position = Vector2(800, floor_y - b._size.y * 0.5)
	b.state = "walk"
	b._t = 99.0
	b.set_physics_process(true)
	p.global_position = Vector2(800, 14.0 * 32.0 - 22.0)
	var best: float = b.global_position.y
	for i in 240:
		await physics_frame
		best = minf(best, b.global_position.y)
	ck(best < 14.0 * 32.0 - 20.0, "boss nhảy lên đuổi người chơi trên bục (y thấp nhất %.0f, bục y=448)" % best)
	print("hk_perch_test: ", "OK" if fails == 0 else "%d lỗi" % fails)
	quit(1 if fails > 0 else 0)
