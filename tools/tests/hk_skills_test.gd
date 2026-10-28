extends SceneTree
## Đòn riêng theo biom của từng boss: mỗi dạng tạo đúng loại vùng, vùng gây hại/làm chậm đúng lúc, cột rơi thành vật cản,
## Wraith tối phòng rồi sáng lại, Hexer dùng lò lửa, Lord chỉ nung bục, boss chết thì vùng biến mất, many_faced có đòn cho mọi dạng.
var fails: int = 0
var dark_log: Array = []

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func zones(b: Node, kind: String) -> Array:
	var out: Array = []
	for c in b.get_children():
		if c.get("kind") == kind and c.has_method("current"):
			out.append(c)
	return out

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_skills_test_save.json"
	var B = load("res://hk/boss.gd")
	# many_faced: mọi dạng có thể đổi sang đều có đòn riêng
	for f in B.SHIFT_P2:
		ck(B.SKILL.has(f), "dạng %s có đòn riêng" % f)
	ck(B.SKILL.has("sovereign"), "dạng sovereign có đòn riêng")
	var room := Node2D.new()
	room.set_script(load("res://hk/room.gd"))
	root.add_child(room)
	var grid: Array = []
	for r in 20:
		grid.append("#".repeat(60) if r == 19 else "#" + ".".repeat(58) + "#")
	room.build("test", {"area": "gate", "doors": {}, "grid": grid})
	var p := CharacterBody2D.new()
	p.set_script(load("res://hk/player.gd"))
	root.add_child(p)
	p.set_physics_process(false)
	var floor_y: float = 19.0 * 32.0
	for kind in ["warden", "brute", "wraith", "hexer", "lord", "colossus"]:
		var b := CharacterBody2D.new()
		b.set_script(load("res://hk/boss.gd"))
		b.kind = kind
		b.position = Vector2(1500, 300)
		root.add_child(b)
		b.arena = room.bounds()
		b.braziers = [Vector2(112, floor_y), Vector2(1808, floor_y)]
		b.platforms = [Rect2(300, 14 * 32, 320, 8), Rect2(1200, 14 * 32, 320, 8)]
		b.darkness.connect(func(on: bool): dark_log.append(on))
		await frames(5)
		b.state = "walk"
		b._t = 99.0
		b.global_position = Vector2(1500, floor_y - b._size.y * 0.5 - 1.0) if not (kind in B.FLYERS) else Vector2(1500, 300)
		p.global_position = Vector2(900, floor_y - 22.0)
		p.hp = p.max_hp
		p.invuln = 0.0
		var skill: String = String(B.SKILL[kind])
		b.state = skill
		b._t = 0.0
		var hp0: int = p.hp
		match kind:
			"warden":
				await frames(3)
				var z: Array = zones(b, "pillar")
				ck(z.size() == 1, "warden: tạo 1 cột")
				await frames(90)
				ck(z.size() == 1 and is_instance_valid(z[0]) and z[0]._landed, "warden: cột đáp xuống")
				var has_body: bool = false
				for c in z[0].get_children():
					has_body = has_body or c is StaticBody2D
				ck(has_body, "warden: cột đáp xuống thành vật cản (StaticBody2D)")
			"brute":
				await frames(3)
				ck(zones(b, "spikes").size() == 3, "brute: 3 cụm gai nền nứt")
				p.global_position = Vector2(900, floor_y - 22.0)
				await frames(60)
				ck(p.hp < hp0, "brute: gai gây hại khi hiệu lực (hp %d -> %d)" % [hp0, p.hp])
			"wraith":
				dark_log.clear()
				await frames(3)
				ck(dark_log == [true], "wraith: tối phòng %s" % str(dark_log))
				await frames(320)
				ck(dark_log == [true, false], "wraith: sáng lại sau 5s %s" % str(dark_log))
			"hexer":
				await frames(3)
				var fw: Array = zones(b, "firewave")
				ck(fw.size() == 2, "hexer: 2 sóng lửa từ 2 lò (%d)" % fw.size())
				if fw.size() == 2:
					var x0: float = fw[0].rect.position.x
					await frames(60)
					ck(fw[0].rect.position.x > x0 + 50.0, "hexer: sóng lửa chạy vào giữa phòng")
					p.global_position = fw[0].rect.get_center()
					p.invuln = 0.0
					await frames(2)
					ck(p.hp < hp0, "hexer: sóng lửa gây hại")
			"lord":
				await frames(3)
				var hz: Array = zones(b, "heat")
				ck(hz.size() >= 1 and hz.size() <= 2, "lord: nung bục (%d)" % hz.size())
				if not hz.is_empty():
					var r: Rect2 = hz[0].rect
					await frames(70)
					p.global_position = r.get_center() + Vector2(0, 10)
					p.invuln = 0.0
					await frames(2)
					ck(p.hp < hp0, "lord: đứng trên bục nóng bị hại")
			"colossus":
				await frames(3)
				var wz: Array = zones(b, "water")
				ck(wz.size() == 1, "colossus: nước dâng")
				if wz.size() == 1:
					await frames(90)
					var cur: Rect2 = wz[0].current()
					ck(cur.size.y > 70.0, "colossus: nước dâng đủ cao (%.0f)" % cur.size.y)
					p.global_position = Vector2(900, floor_y - 22.0)
					p.velocity = Vector2(300, 0)
					await frames(1)
					ck(p.velocity.x < 300.0, "colossus: nước làm chậm người chơi")
					var fast: float = p.velocity.x
					p.global_position = Vector2(900, floor_y - 22.0 - 200.0)
					p.velocity = Vector2(300, 0)
					await frames(1)
					ck(absf(p.velocity.x - 300.0) < 1.0 or p.velocity.x >= fast, "colossus: trên bục cao thì không bị chậm")
		# boss biến mất thì vùng đi theo
		var kids: Array = []
		for c in b.get_children():
			if c.has_method("current"):
				kids.append(c)
		b.queue_free()
		await frames(3)
		var gone: bool = true
		for c in kids:
			gone = gone and not is_instance_valid(c)
		ck(gone, "%s: boss chết thì vùng biến mất" % kind)
	print("hk_skills_test: ", "OK" if fails == 0 else "%d lỗi" % fails)
	quit(1 if fails > 0 else 0)
