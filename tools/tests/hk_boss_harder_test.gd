extends SceneTree
## Boss khó hơn (hành vi, không đổi HP/sát thương): pha 2 nghỉ ngắn hơn, không lặp đòn, nối đòn (nước->dậm đất, bục nóng->mưa đá),
## brute dậm đất + 5 cụm gai pha 2, warden sóng hồi pha 2, grove bào tử đợt hai, hexer quạt đôi.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func zones(b: Node, k: String) -> int:
	var n := 0
	for c in b.get_children():
		if c.get("kind") == k:
			n += 1
	return n

func make(B, room, kind: String, fy: float) -> CharacterBody2D:
	var b := CharacterBody2D.new()
	b.set_script(B)
	b.kind = kind
	b.position = Vector2(900, fy - 100.0)
	root.add_child(b)
	b.arena = room.bounds()
	await frames(5)
	return b

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_boss_harder_test_save.json"
	var B = load("res://hk/boss.gd")
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
	p.global_position = Vector2(300, fy - 22.0)

	# nhịp pha 2 ngắn hơn
	var w = await make(B, room, "warden", fy)
	var s1 := 0.0
	var s2 := 0.0
	for i in 200:
		w.phase = 1
		w._next()
		s1 += w._t
		w.phase = 2
		w._next()
		s2 += w._t
	ck(s2 < s1 * 0.8, "pha 2 nghỉ ngắn hơn (p1 %.1f, p2 %.1f)" % [s1, s2])
	# không lặp đòn y hệt hai lượt liền: tỉ lệ lặp thấp hơn bốc ngẫu nhiên thuần (>1/4 với 4 loại)
	w.phase = 2
	var rep := 0
	var last := ""
	for i in 400:
		w.state = "walk"
		w._pick_attack()
		if w.state == last and last != "":
			rep += 1
		last = w.state
	ck(float(rep) / 400.0 < 0.2, "ít lặp đòn (%d/400)" % rep)
	# warden pha 2: sóng hồi (2 sóng), pha 1: 1 sóng
	for ph in [1, 2]:
		w.phase = ph
		w.state = "wind_sweep"
		w.global_position = Vector2(900, fy - w._size.y * 0.5)
		w._t = 0.0
		w._ground(0.016, p)
		await frames(3)
		ck(zones(w, "sweep") == (1 if ph == 1 else 2), "warden pha %d: %d sóng quét" % [ph, 1 if ph == 1 else 2])
		for c in w.get_children():
			if c.get("kind") == "sweep":
				c.queue_free()
		await frames(2)
	w.queue_free()

	# brute: có quake, fissure 3 -> 5 cụm
	var br = await make(B, room, "brute", fy)
	var q := false
	for i in 300:
		br.state = "walk"
		br.phase = 1
		br._pick_attack()
		q = q or br.state == "wind_quake"
	ck(q, "brute có quake")
	for ph in [1, 2]:
		br.phase = ph
		br.state = "wind_fissure"
		br._cast(p)
		await frames(3)
		ck(zones(br, "spikes")== (3 if ph == 1 else 5), "brute pha %d: gai (%d)" % [ph, zones(br, "spikes")])
		for c in br.get_children():
			if c.get("kind") == "spikes":
				c.queue_free()
		await frames(2)
	br.queue_free()

	# colossus: nước -> dậm đất (cả hai pha)
	var co = await make(B, room, "colossus", fy)
	for ph in [1, 2]:
		co.phase = ph
		co.state = "wind_tide"
		co.global_position = Vector2(900, fy - co._size.y * 0.5)
		co._t = 0.0
		co._ground(0.016, p)
		ck(co.state == "wind_quake", "colossus pha %d: nước nối dậm đất (%s)" % [ph, co.state])
	co.queue_free()

	# lord: bục nóng -> mưa đá chỉ pha 2 và khi có bục
	var lo = await make(B, room, "lord", fy)
	lo.platforms = [Rect2(300, 400, 160, 12), Rect2(700, 300, 160, 12)]
	for ph in [1, 2]:
		lo.phase = ph
		lo.state = "wind_heat"
		lo.global_position = Vector2(900, fy - lo._size.y * 0.5)
		lo._t = 0.0
		lo._ground(0.016, p)
		ck(lo.state == ("rain" if ph == 2 else "recover"), "lord pha %d: sau bục nóng -> %s" % [ph, lo.state])
	lo.platforms = []
	lo.phase = 2
	lo.state = "wind_heat"
	lo._t = 0.0
	lo._ground(0.016, p)
	ck(lo.state == "recover", "lord không có bục: không nối mưa (%s)" % lo.state)
	lo.queue_free()

	# grove: bào tử đợt hai (pha 1: 5+1, pha 2: 7+6)
	var gr = await make(B, room, "grove", fy)
	for ph in [1, 2]:
		gr.phase = ph
		gr.state = "wind_bloom"
		gr._t = 99.0   # chỉ _cast thủ công, không để vòng đòn tự tung thêm lần nữa
		gr._cast(p)
		await frames(3)
		var want: int = 6 if ph == 1 else 13
		ck(zones(gr, "spore") == want, "grove pha %d: %d cụm bào tử (%d)" % [ph, want, zones(gr, "spore")])
		for c in gr.get_children():
			if c.get("kind") == "spore":
				c.queue_free()
		await frames(2)
	gr.queue_free()

	# hexer: quạt đôi (pha 2 luôn)
	var hx = await make(B, room, "hexer", fy)
	hx.phase = 2
	var shots := 0
	for i in 60:
		hx.state = "hover"
		hx._t = 0.0
		hx._wraith(0.016, p)
		if hx.state == "wind_bolt" and hx._combo == 1:
			shots += 1
	ck(shots > 0, "hexer pha 2 có quạt đôi")
	hx.state = "wind_bolt"
	hx._combo = 1
	hx._t = 0.0
	hx._wraith(0.016, p)
	ck(hx.state == "wind_bolt" and hx._combo == 0, "quạt đầu -> quạt hai (state %s, combo %d)" % [hx.state, hx._combo])
	hx._t = 0.0
	hx._wraith(0.016, p)
	ck(hx.state == "hover", "sau quạt hai về hover (%s)" % hx.state)
	print("DONE fails=", fails)
	quit()
