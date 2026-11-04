extends SceneTree
## Đòn mới cho mini-boss yếu: brute "Bone Hurl" (3 xương ngang, tốc độ lệch), colossus "Undertow" (xoáy kéo về boss, không sát thương, chỉ khi có bục),
## hexer "Ember Rain" (5 điểm lửa nằm sàn); xác suất ≤1/4 mỗi lượt; âm tell_*.
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

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_boss_new_test_save.json"
	var B = load("res://hk/boss.gd")
	var Sfx = load("res://hk/sfx.gd")
	ck(Sfx.DEFS.has("tell_hurl") and Sfx.DEFS.has("tell_undertow") and Sfx.DEFS.has("tell_ember"), "có âm tell_hurl/tell_undertow/tell_ember")
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

	# --- brute: ba xương, tốc độ lệch nhau, ném về phía người chơi; chọn được nhưng ≤1/4
	var br = await make(B, room, "brute", fy)
	var heard: Array = []
	br.sfx.connect(func(n: String): heard.append(n))
	br._t = 99.0
	br.state = "wind_hurl"
	br._cast(p)
	await frames(3)
	var bones: Array = []
	for c in room.get_parent().get_children():
		if c is Area2D and c.get("vel") != null and c.vel.x != 0.0 and not c.friendly:
			bones.append(c)
	ck(bones.size() == 3, "wind_hurl ném 3 xương (%d)" % bones.size())
	var speeds: Array = bones.map(func(x): return absf(x.vel.x))
	speeds.sort()
	ck(speeds == B.HURL_SPEEDS, "tốc độ lệch nhau %s" % str(speeds))
	ck(bones.all(func(x): return x.vel.x < 0.0), "ném về phía người chơi (bên trái)")
	var hurl := 0
	for i in 600:
		br.state = "walk"
		br.phase = 1 + i % 2
		br._pick_attack()
		if br.state == "wind_hurl":
			hurl += 1
	ck(hurl > 0 and float(hurl) / 600.0 <= 0.25, "brute chọn hurl nhưng ≤1/4 (%d/600)" % hurl)
	br.state = "walk"
	br._t = 99.0
	br.state = "wind_hurl"
	br._t = 0.0
	await frames(2)
	ck(heard.has("tell_hurl"), "wind_hurl phát tell_hurl")
	br.queue_free()

	# --- colossus: undertow chỉ khi có bục; kéo về boss, không sát thương
	var co = await make(B, room, "colossus", fy)
	var ut := 0
	for i in 400:
		co.state = "walk"
		co.platforms = []
		co._pick_attack()
		if co.state == "wind_undertow":
			ut += 1
	ck(ut == 0, "không có bục: không dùng undertow (%d)" % ut)
	co.platforms = [Rect2(600, fy - 96.0, 160, 8)]
	for i in 600:
		co.state = "walk"
		co.phase = 1 + i % 2
		co._pick_attack()
		if co.state == "wind_undertow":
			ut += 1
	ck(ut > 0 and float(ut) / 600.0 <= 0.25, "có bục: undertow ≤1/4 (%d/600)" % ut)
	co.state = "wind_undertow"
	co._t = 99.0
	co._cast(p)
	await frames(30)
	var uz: Array = zones(co, "undertow")
	ck(uz.size() == 1, "undertow tạo 1 vùng (%d)" % uz.size())
	if uz.size() == 1:
		p.global_position = Vector2(co.global_position.x - 150.0, fy - 22.0)   # trong vùng, bên trái boss
		var hp0: int = p.hp
		p.drift = 0.0
		p.invuln = 0.0
		await frames(2)
		ck(p.drift > 0.0, "xoáy kéo về phía boss (drift %.0f)" % p.drift)
		ck(p.hp == hp0, "xoáy không gây sát thương")
		p.global_position = Vector2(co.global_position.x + 150.0, fy - 22.0)
		await frames(2)
		ck(p.drift < 0.0, "bên phải boss thì kéo sang trái (%.0f)" % p.drift)
		p.global_position = Vector2(co.global_position.x + 600.0, fy - 22.0)
		p.drift = 0.0
		await frames(2)
		ck(p.drift == 0.0, "ngoài vùng không bị kéo")
		await frames(100)
		ck(zones(co, "undertow").is_empty(), "xoáy tan sau 1.5s")
	co.queue_free()

	# --- hexer: mưa tàn lửa
	var hx = await make(B, room, "hexer", fy)
	hx.global_position = Vector2(900, fy - 240.0)
	var emb := 0
	for i in 800:
		hx.state = "hover"
		hx._t = 0.0
		hx._wraith(0.016, p)
		if hx.state == "wind_ember":
			emb += 1
	ck(emb > 0 and float(emb) / 800.0 <= 0.3, "hexer chọn ember, không quá thường (%d/800)" % emb)
	hx.global_position = Vector2(900, fy - 240.0)
	hx.state = "wind_ember"
	hx._t = 0.0
	hx._wraith(0.016, p)
	await frames(3)
	var fl: Array = zones(hx, "flame")
	ck(fl.size() == B.EMBER_N, "ember thả %d điểm lửa (%d)" % [B.EMBER_N, fl.size()])
	ck(fl.all(func(z): return absf(z.rect.end.y - hx._floor_y()) < 1.0), "lửa nằm trên mặt sàn của boss bay (_floor_y)")
	ck(hx.state == "hover", "xong ember về hover (%s)" % hx.state)
	print("DONE fails=", fails)
	quit()
