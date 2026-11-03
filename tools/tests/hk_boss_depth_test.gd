extends SceneTree
## Đòn mới của hai mini-boss yếu nhất: colossus "quake" (2 sóng pha 1, 3 sóng pha 2) và brute "rush" (pha 2, lao hai bờ phòng, KHÔNG đỡ được).
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func waves() -> int:
	var n: int = 0
	for c in root.get_children():
		if c.get("friendly") == false and c.get("vel") != null:
			n += 1
			c.queue_free()
	return n

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_boss_depth_test_save.json"
	var B = load("res://hk/boss.gd")
	var Sfx = load("res://hk/sfx.gd")
	ck(Sfx.DEFS.has("tell_quake") and Sfx.DEFS.has("tell_rush"), "có âm tell_quake và tell_rush")
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
	p.global_position = Vector2(900, floor_y - 22.0)
	var heard: Array = []
	# --- colossus quake
	p.global_position = Vector2(100, floor_y - 22.0)   # xa tầm sóng để sóng không bị người chơi chặn
	for ph in [1, 2]:
		var b := CharacterBody2D.new()
		b.set_script(B)
		b.kind = "colossus"
		b.position = Vector2(960, floor_y - 100.0)
		root.add_child(b)
		b.arena = room.bounds()
		b.sfx.connect(func(n: String): heard.append(n))
		await frames(5)
		b.phase = ph
		b.state = "wind_quake"
		b._t = 0.1
		await frames(75)
		var n: int = waves()
		ck(n == (4 if ph == 1 else 6), "colossus pha %d: quake tạo %d sóng (%d)" % [ph, 4 if ph == 1 else 6, n])
		for _k in 12:   # độ dài quake phụ thuộc nhịp khung: chờ tối đa thêm 3s thay vì cố định 1s
			if b.state != "quake" and b.state != "wind_quake":
				break
			await frames(15)
		ck(b.state != "quake" and b.state != "wind_quake", "colossus pha %d: quake kết thúc (%s)" % [ph, b.state])
		b.free()
		waves()
	ck(heard.has("tell_quake"), "quake phát tell_quake")
	p.global_position = Vector2(900, floor_y - 22.0)
	# --- brute rush
	var br := CharacterBody2D.new()
	br.set_script(B)
	br.kind = "brute"
	br.position = Vector2(1500, floor_y - 100.0)
	root.add_child(br)
	br.arena = room.bounds()
	br.sfx.connect(func(n: String): heard.append(n))
	await frames(5)
	br.phase = 1
	var pool_hits: int = 0
	for i in 200:
		br.state = "walk"
		br._t = 0.0
		br._pick_attack()
		if br.state == "wind_rush":
			pool_hits += 1
	ck(pool_hits == 0, "brute pha 1 không bao giờ chọn rush")
	br.phase = 2
	for i in 200:
		br.state = "walk"
		br._pick_attack()
		if br.state == "wind_rush":
			pool_hits += 1
	ck(pool_hits > 0, "brute pha 2 có chọn rush (%d/200)" % pool_hits)
	br.global_position = Vector2(1500, floor_y - br._size.y * 0.5 - 1.0)
	br.state = "wind_rush"
	br._t = 0.1
	var lo: float = 9999.0
	var hi: float = 0.0
	var f: int = 0
	while f < 900:
		await physics_frame
		f += 1
		lo = minf(lo, br.global_position.x)
		hi = maxf(hi, br.global_position.x)
		p.hp = p.max_hp
		p.invuln = 0.0
		if br.state == "recover":
			break
	ck(br.state == "recover", "rush kết thúc sang recover (%s sau %d khung)" % [br.state, f])
	ck(lo <= br.arena.position.x + 60.0 and hi >= br.arena.end.x - 60.0, "rush chạm cả hai bờ phòng (%d..%d)" % [int(lo), int(hi)])
	ck(heard.has("tell_rush"), "rush phát tell_rush")
	# --- rush không đỡ được, đòn thường của cùng boss thì đỡ được
	br.state = "walk"
	br._t = 99.0
	br.velocity = Vector2.ZERO
	p.global_position = br.global_position
	p.hp = p.max_hp
	p.invuln = 0.0
	p._parry_t = 0.15
	await frames(1)
	ck(p.hp == p.max_hp, "chạm thường lúc đang đỡ: được đỡ (hp %d)" % p.hp)
	br.state = "rush"
	br._t = 5.0
	br._combo = 2
	br.dir = 1
	br.global_position = Vector2(900, floor_y - br._size.y * 0.5 - 1.0)
	p.global_position = br.global_position
	p.hp = p.max_hp
	p.invuln = 0.0
	p._parry_t = 0.15
	await frames(1)
	ck(p.hp == p.max_hp - 1, "rush trúng lúc đang đỡ: vẫn mất 1 mặt nạ (hp %d)" % p.hp)
	# --- warden pha 2: sweep không đỡ được
	ck(Sfx.DEFS.has("tell_sweep"), "có âm tell_sweep")
	var wd := CharacterBody2D.new()
	wd.set_script(B)
	wd.kind = "warden"
	wd.position = Vector2(900, floor_y - 100.0)
	root.add_child(wd)
	wd.arena = room.bounds()
	await frames(5)
	var picked: Array = [0, 0]
	for i in 200:
		for ph in [1, 2]:
			wd.state = "walk"
			wd.phase = ph
			wd._pick_attack()
			if wd.state == "wind_sweep":
				picked[ph - 1] += 1
	ck(picked[0] > 0 and picked[1] > 0, "sweep có ở cả hai pha (p1 %d, p2 %d)" % [picked[0], picked[1]])
	wd.phase = 1   # ngưỡng pha 2 của warden vẫn là 50%: ở 66% máu chưa vào pha 2
	wd.hp = wd.max_hp * 2 / 3
	wd.state = "walk"
	wd.take_hit(1, Vector2.ZERO)
	ck(wd.phase == 1, "warden ở ~66%% máu vẫn pha 1 (phase %d)" % wd.phase)
	wd.phase = 2
	wd.state = "walk"
	wd._t = 99.0
	wd.global_position = Vector2(900, floor_y - wd._size.y * 0.5 - 1.0)
	p.global_position = Vector2(1500, floor_y - 22.0)
	heard.clear()
	wd.sfx.connect(func(n: String): heard.append(n))
	wd.state = "wind_sweep"
	wd._t = 0.15   # tell phát khi vào state, đòn tung ra sau khi hết _t
	await frames(14)
	var sw: Array = []
	for c in wd.get_children():
		if c.get("kind") == "sweep":
			sw.append(c)
	ck(sw.size() == 1, "wind_sweep tạo 1 sóng (%d)" % sw.size())
	if sw.size() == 1:
		var z: Node2D = sw[0]
		ck(z.vel.x > 0.0 and z.rect.size.y == B.SWEEP_H, "sóng chạy về phía người chơi, cao %d" % int(B.SWEEP_H))
		var x0: float = z.rect.position.x
		await frames(30)
		ck(z.rect.position.x > x0 + 50.0, "sóng di chuyển dọc sàn (%f -> %f)" % [x0, z.rect.position.x])
		# trúng sóng lúc đang đỡ: vẫn mất mặt nạ; nhảy cao hơn sóng thì không
		p.hp = p.max_hp
		p.invuln = 0.0
		p._parry_t = 0.15
		p.global_position = Vector2(z.rect.get_center().x, floor_y - 22.0)
		await frames(2)
		ck(p.hp == p.max_hp - 1, "sweep trúng lúc đang đỡ: vẫn mất 1 mặt nạ (hp %d)" % p.hp)
		p.hp = p.max_hp
		p.invuln = 0.0
		p.global_position = Vector2(z.rect.get_center().x, floor_y - B.SWEEP_H - 80.0)
		await frames(2)
		ck(p.hp == p.max_hp, "nhảy cao hơn sóng: không trúng (hp %d)" % p.hp)
	ck(heard.has("tell_sweep"), "wind_sweep phát tell_sweep")
	print("hk_boss_depth_test: ", "OK" if fails == 0 else "%d lỗi" % fails)
	print("DONE fails=", fails)
	quit(fails)
