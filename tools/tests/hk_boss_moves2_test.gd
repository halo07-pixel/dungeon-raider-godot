extends SceneTree
## Đòn mới đợt hai: brute "Bone Cage" (4 cụm gai khép lại) + "Twin Slam" (pha 2, đập hai lần), colossus "Geyser Line" (4 cột nước) +
## "Bubble Volley" (5 bong bóng chậm, rồi nối dậm đất). Xác suất ≤1/4 mỗi đòn, đòn không đỡ được ≤1/3 bộ đòn, âm tell_*.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func zones(b: Node, k: String) -> Array:
	var out: Array = []
	for c in b.get_children():
		if c.get("kind") == k:
			out.append(c)
	return out

func make(B, room, kind: String, fy: float) -> CharacterBody2D:
	var b := CharacterBody2D.new()
	b.set_script(B)
	b.kind = kind
	b.position = Vector2(900, fy - 100.0)
	root.add_child(b)
	b.arena = room.bounds()
	await frames(5)
	b.global_position = Vector2(900, fy - b._size.y * 0.5)
	return b

func rates(b, phase: int, n: int) -> Dictionary:
	var cnt: Dictionary = {}
	for i in n:
		b.state = "walk"
		b.phase = phase
		b._pick_attack()
		cnt[b.state] = int(cnt.get(b.state, 0)) + 1
	return cnt

func unparry(cnt: Dictionary, n: int) -> float:
	var u := 0
	for s in ["wind_cage", "wind_rush", "wind_fissure", "wind_tide", "wind_geyser", "wind_sweep"]:
		u += int(cnt.get(s, 0))
	return float(u) / float(n)

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_boss_moves2_test_save.json"
	var B = load("res://hk/boss.gd")
	var Sfx = load("res://hk/sfx.gd")
	ck(Sfx.DEFS.has("tell_cage") and Sfx.DEFS.has("tell_geyser") and Sfx.DEFS.has("tell_volley"), "có âm tell_cage/geyser/volley")
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
	var fy: float = 19.0 * 32.0
	p.global_position = Vector2(500, fy - 22.0)

	# --- brute
	var br = await make(B, room, "brute", fy)
	var heard: Array = []
	br.sfx.connect(func(n: String): heard.append(n))
	br.state = "wind_cage"
	br._t = 99.0
	br._cast(p)
	await frames(3)
	var sp: Array = zones(br, "spikes")
	ck(sp.size() == 4, "Bone Cage: 4 cụm gai (%d)" % sp.size())
	var xs: Array = sp.map(func(z): return snappedf(z.rect.get_center().x - p.global_position.x, 1.0))
	xs.sort()
	ck(xs == [-90.0, -45.0, 45.0, 90.0], "gai cách người chơi ±90 và ±45 (%s)" % str(xs))
	var dl: Array = sp.map(func(z): return z.delay)
	ck(dl.max() - dl.min() > 0.5, "hai đợt: ngoài trước, khép vào sau (delay %s)" % str(dl))
	for p1 in [1, 2]:
		var c: Dictionary = rates(br, p1, 3000)
		ck(int(c.get("wind_cage", 0)) > 0 and float(c.get("wind_cage", 0)) / 3000.0 <= 0.25, "brute pha %d: cage ≤1/4 (%d/3000)" % [p1, int(c.get("wind_cage", 0))])
		ck(unparry(c, 3000) <= 0.37, "brute pha %d: đòn không đỡ được ≤1/3 (%.2f)" % [p1, unparry(c, 3000)])
		var tw: int = 0
		for i in 600:
			br.state = "walk"
			br.phase = p1
			br._twin = 0
			br._pick_attack()
			if br._twin == 1:
				tw += 1
		ck((tw > 0) == (p1 == 2), "Twin Slam chỉ pha 2 (pha %d: %d)" % [p1, tw])
	# Twin Slam: chạm đất lần một -> đập lần hai (wind_slam), lần hai xong mới recover
	br.phase = 2
	br._twin = 1
	br.state = "air"
	br._was_air = true
	br.global_position = Vector2(900, fy - br._size.y * 0.5)
	br.velocity = Vector2.ZERO
	br._ground(0.016, p)
	ck(br.state == "wind_slam" and br._twin == 0, "Twin Slam: sau lần đầu đập tiếp (%s, twin %d)" % [br.state, br._twin])
	br.state = "air"
	br._was_air = true
	br._ground(0.016, p)
	ck(br.state == "recover", "Twin Slam: lần hai xong thì recover (%s)" % br.state)
	br._twin = 1
	br._next()
	ck(br._twin == 0, "_next xoá cờ twin")
	br.state = "wind_cage"
	br._t = 0.0
	await frames(2)
	ck(heard.has("tell_cage"), "wind_cage phát tell_cage")
	br.queue_free()

	# --- colossus
	var co = await make(B, room, "colossus", fy)
	var h2: Array = []
	co.sfx.connect(func(n: String): h2.append(n))
	co.state = "wind_geyser"
	co._t = 99.0
	co._cast(p)
	await frames(3)
	var gz: Array = zones(co, "geyser")
	ck(gz.size() == 4, "Geyser Line: 4 cột nước (%d)" % gz.size())
	if gz.size() == 4:
		gz.sort_custom(func(a, b2): return a.delay < b2.delay)
		ck(gz[1].delay > gz[0].delay and gz[3].rect.get_center().x < gz[0].rect.get_center().x, "phun lần lượt về phía người chơi (bên trái boss)")
		ck(gz[0].rect.size.y == 110.0, "cột cao 110px")
		await frames(30)   # cột đầu đã có hiệu lực: đứng trong thì mất mặt nạ
		p.global_position = gz[0].rect.get_center()
		p.invuln = 0.0
		var hp0: int = p.hp
		await frames(2)
		ck(p.hp < hp0, "đứng trong cột nước bị hại")
		p.invuln = 0.0
		p.global_position = Vector2(gz[0].rect.get_center().x + 45.0, fy - 22.0)   # khe giữa hai cột
		hp0 = p.hp
		await frames(2)
		ck(p.hp == hp0, "đứng ở khe giữa hai cột thì an toàn")
	for plat in [false, true]:
		co.platforms = [Rect2(600, fy - 96.0, 160, 8)] if plat else []
		for ph in [1, 2]:
			var cc: Dictionary = rates(co, ph, 3000)
			for k in ["wind_geyser", "wind_volley"]:
				ck(int(cc.get(k, 0)) > 0 and float(cc.get(k, 0)) / 3000.0 <= 0.25, "colossus pha %d platform=%s: %s ≤1/4 (%d)" % [ph, plat, k, int(cc.get(k, 0))])
			ck(unparry(cc, 3000) <= 0.37, "colossus pha %d platform=%s: không đỡ được ≤1/3 (%.2f)" % [ph, plat, unparry(cc, 3000)])
	# Bubble Volley: 5 bong bóng chậm, rồi nối dậm đất
	p.global_position = Vector2(300, fy - 22.0)
	co.global_position = Vector2(900, fy - co._size.y * 0.5)
	co.state = "wind_volley"
	co._t = 0.0
	co._ground(0.016, p)
	await frames(3)
	var bubbles: Array = []
	for c in room.get_parent().get_children():
		if c is Area2D and c.get("slows") == true:
			bubbles.append(c)
	ck(bubbles.size() == 5, "Bubble Volley: 5 bong bóng chậm (%d)" % bubbles.size())
	ck(bubbles.all(func(x): return x.vel.x < 0.0), "bắn về phía người chơi")
	ck(co.state == "wind_quake", "sau volley nối dậm đất (%s)" % co.state)
	co.state = "wind_geyser"
	await frames(2)
	ck(h2.has("tell_geyser"), "wind_geyser phát tell_geyser")
	print("DONE fails=", fails)
	quit()
