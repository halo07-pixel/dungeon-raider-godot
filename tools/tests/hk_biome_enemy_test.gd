extends SceneTree
## Quái riêng theo khu: sentry (Gate; khiên + gọi 1 crawler con không Geo), reviver (Catacomb; nằm 2s rồi đứng dậy một lần, đánh lúc nằm là diệt),
## cinder (Vault; húc để lại vệt lửa tự tắt), bubbler (Archive; bong bóng chỉ làm chậm, không sát thương). Phòng thật có đủ bốn loại.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func mk(St, kind: String, pos: Vector2) -> CharacterBody2D:
	var e := CharacterBody2D.new()
	e.set_script(load("res://hk/enemy.gd"))
	e.kind = kind
	e.position = pos
	root.add_child(e)
	return e

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	var EN = load("res://hk/enemy.gd")
	var WD = load("res://hk/world_data.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_biome_enemy_save.json"
	# ---- dữ liệu: có sprite + hộp, có trong phòng thật
	for k in ["sentry", "reviver", "cinder", "bubbler"]:
		ck(EN.LOOK.has(k) and EN.DATA.has(k) and EN.body_size(k).x > 4.0 and EN.body_size(k).y > 4.0, "%s: có LOOK/DATA/hộp" % k)
	var seen: Dictionary = {}
	for rid in WD.load_all():
		for row in WD.load_all()[rid]["grid"]:
			for ch in String(row):
				if ch in "kzib":
					seen[ch] = seen.get(ch, 0) + 1
	ck(seen.has("k") and seen.has("z") and seen.has("i") and seen.has("b"), "phòng thật có đủ 4 loại quái khu (%s)" % str(seen))
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
	p.invuln = 9999.0
	await frames(30)
	# ---- reviver
	var z = mk(St, "reviver", Vector2(900, 560))
	await frames(20)
	z.set_physics_process(true)
	var geo0: int = St.geo
	ck(z.take_hit(99, Vector2(800, 560)) == true and is_instance_valid(z) and not z.is_queued_for_deletion() and z.state == "down" and z.hp == 1, "reviver: lần chết đầu thì nằm xuống (state %s)" % z.state)
	ck(St.geo == geo0, "reviver nằm: chưa rơi Geo")
	await frames(int(EN.REVIVE_AFTER * 60.0) + 20)
	ck(z.state != "down" and z.hp == 5, "reviver đứng dậy với nửa máu (state %s hp %d)" % [z.state, z.hp])
	z.take_hit(99, Vector2(800, 560))
	await frames(2)
	ck(not is_instance_valid(z) or z.is_queued_for_deletion(), "reviver: chết lần hai là hết")
	ck(St.geo > geo0, "reviver chết hẳn thì rơi Geo")
	var z2 = mk(St, "reviver", Vector2(1000, 560))
	await frames(10)
	z2.take_hit(99, Vector2(900, 560))
	ck(z2.state == "down", "reviver 2 nằm xuống")
	z2.take_hit(1, Vector2(900, 560))
	await frames(2)
	ck(not is_instance_valid(z2) or z2.is_queued_for_deletion(), "đánh reviver lúc đang nằm: diệt hẳn")
	# ---- cinder: lunge để lại vệt lửa rồi tự tắt
	var c = mk(St, "cinder", Vector2(900, 560))
	await frames(10)
	c.dir = -1
	c.state = "lunge"
	c._t = 0.5
	await frames(30)
	var flames: int = 0
	for n in root.get_children():
		if n.get("kind") == "flame":
			flames += 1
	ck(flames >= 2, "cinder: để lại vệt lửa (%d)" % flames)
	c.queue_free()
	await frames(int(EN.FIRE_TRAIL * 60.0) + 90)
	flames = 0
	for n in root.get_children():
		if n.get("kind") == "flame":
			flames += 1
	ck(flames == 0, "vệt lửa tự tắt (%d còn lại)" % flames)
	# ---- bubbler: bong bóng làm chậm, không mất máu
	p.global_position = Vector2(500, 560)
	var hp0: int = p.hp
	var bub := Area2D.new()
	bub.set_script(load("res://hk/projectile.gd"))
	bub.friendly = false
	bub.slows = true
	bub.vel = Vector2.ZERO
	root.add_child(bub)
	bub.global_position = p.global_position
	p.invuln = 0.0
	await frames(6)
	ck(p.slow_t > 0.0 and p.hp == hp0, "bong bóng: làm chậm, không mất máu (slow_t %.2f hp %d/%d)" % [p.slow_t, p.hp, hp0])
	p.invuln = 9999.0
	var b = mk(St, "bubbler", Vector2(900, 560))
	b._t = 0.0
	p.global_position = Vector2(700, 560)
	await frames(100)
	var shot: bool = false
	for n in root.get_children():
		if n.get("slows") == true and n != bub:
			shot = true
	ck(shot, "bubbler bắn bong bóng")
	b.queue_free()
	# ---- sentry: khiên + gọi đúng 1 crawler không Geo
	var s = mk(St, "sentry", Vector2(900, 560))
	await frames(20)
	var front := Vector2(s.global_position.x + 60.0 * float(s.dir), s.global_position.y)
	s.set_physics_process(false)
	ck(s.take_hit(5, front) == false, "sentry: khiên chặn chính diện")
	s.set_physics_process(true)
	p.global_position = Vector2(700, 560)
	s._t = 0.0
	await frames(150)
	var minions: Array = []
	for n in root.get_children():
		if is_instance_valid(n) and n.get("minion") == true and not n.is_queued_for_deletion():
			minions.append(n)
	ck(minions.size() == 1 and minions[0].kind == "crawler", "sentry gọi đúng 1 crawler con (%d)" % minions.size())
	await frames(150)
	var count2: int = 0
	for n in root.get_children():
		if is_instance_valid(n) and n.get("minion") == true and not n.is_queued_for_deletion():
			count2 += 1
	ck(count2 <= 1, "sentry không gọi thêm khi con cũ còn sống (%d)" % count2)
	if not minions.is_empty():
		var g1: int = St.geo
		minions[0].take_hit(99, Vector2(0, 560))
		ck(St.geo == g1, "crawler con không rơi Geo")
	# ---- âm riêng: đúng tên âm cho từng quái (có trong sfx.DEFS)
	var SFX = load("res://hk/sfx.gd")
	for n in ["tell_bell", "revive", "tell_ember", "ember", "bubble", "pop"]:
		ck(SFX.DEFS.has(n), "sfx.DEFS có %s" % n)
	p.global_position = Vector2(700, 560)
	var heard: Array = []
	var s2 = mk(St, "sentry", Vector2(900, 560))
	s2.sfx.connect(func(n: String): heard.append(n))
	s2._t = 0.0
	await frames(40)
	ck("tell_bell" in heard, "sentry windup: tiếng chuông (%s)" % str(heard))
	var heard2: Array = []
	var c2 = mk(St, "cinder", Vector2(1100, 560))
	c2.sfx.connect(func(n: String): heard2.append(n))
	c2.dir = -1
	c2.state = "windup"
	c2._t = 0.3
	await frames(60)
	ck("tell_ember" in heard2 and "ember" in heard2, "cinder: tell_ember + ember khi để lại lửa (%s)" % str(heard2))
	var heard3: Array = []
	var z3 = mk(St, "reviver", Vector2(1300, 560))
	z3.sfx.connect(func(n: String): heard3.append(n))
	await frames(10)
	z3.take_hit(99, Vector2(1200, 560))
	ck(z3.body_rect().size == EN.body_size("reviver"), "reviver nằm: hộp va chạm giữ nguyên")
	await frames(int(EN.REVIVE_AFTER * 60.0) + 20)
	ck("revive" in heard3, "reviver đứng dậy phát tiếng revive (%s)" % str(heard3))
	var heard4: Array = []
	var b3 = mk(St, "bubbler", Vector2(900, 560))
	b3.sfx.connect(func(n: String): heard4.append(n))
	b3._t = 0.0
	p.global_position = Vector2(560, 560)
	p.invuln = 0.0
	await frames(200)
	ck("bubble" in heard4 and not ("spit" in heard4), "bubbler bắn: tiếng bubble (%s)" % str(heard4))
	ck("pop" in heard4, "bong bóng trúng người chơi: tiếng pop (%s)" % str(heard4))
	p.invuln = 9999.0
	St.delete_save()
	print("hk_biome_enemy_test: ", "OK" if fails == 0 else "%d lỗi" % fails)
	quit(1 if fails > 0 else 0)
