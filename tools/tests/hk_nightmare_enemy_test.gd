extends SceneTree
## Nightmare (nhánh B): quái phục kích, tối đa 2 quái xông cùng lúc, reviver hồi nhanh khi có quái khác gần, The Stalker.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func mk(kind: String, pos: Vector2, ambush: bool = false) -> CharacterBody2D:
	var e := CharacterBody2D.new()
	e.set_script(load("res://hk/enemy.gd"))
	e.kind = kind
	e.ambush = ambush
	e.position = pos
	root.add_child(e)
	return e

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_nightmare_enemy_save.json"
	ck(load("res://hk/sfx.gd").DEFS.has("rustle") and load("res://hk/sfx.gd").DEFS.has("stalk"), "có âm rustle/stalk")
	var room := Node2D.new()
	room.set_script(load("res://hk/room.gd"))
	root.add_child(room)
	var grid: Array = []
	for r in 20:
		grid.append("#".repeat(60) if r == 19 else "#" + ".".repeat(58) + "#")
	room.build("test", {"area": "gate", "doors": {}, "grid": grid})
	var fy: float = 19.0 * 32.0
	var p := CharacterBody2D.new()
	p.set_script(load("res://hk/player.gd"))
	p.position = Vector2(300, fy - 22.0)
	root.add_child(p)
	p.invuln = 9999.0
	p.set_physics_process(false)
	await frames(20)

	# --- phục kích
	var heard: Array = []
	var a = mk("crawler", Vector2(900, fy - 20.0), true)
	a.sfx.connect(func(n: String): heard.append(n))
	await frames(5)
	ck(a.state == "hidden" and not a.visible and a.collision_layer == 0, "phục kích: ẩn, không va chạm")
	p.global_position = Vector2(900.0 - 400.0, fy - 22.0)
	await frames(10)
	ck(a.state == "hidden", "xa thì vẫn ẩn")
	p.global_position = Vector2(900.0 - 100.0, fy - 22.0)
	await frames(2)
	ck(a.state == "emerge" and a.visible and heard.has("rustle"), "lại gần: trồi ra + sột soạt (%s)" % a.state)
	await frames(2)
	ck(a.collision_layer == 4, "trồi ra: đánh được")
	p.invuln = 0.0
	var hp0: int = St.hp
	await frames(5)
	ck(a.state == "emerge", "đang trồi: chưa chuyển trạng thái sớm")
	ck(St.hp == hp0, "đang trồi: không gây hại")
	await frames(40)
	ck(a.state != "hidden" and a.state != "emerge", "trồi xong thành quái thường (%s)" % a.state)
	p.invuln = 9999.0
	a.queue_free()

	# --- tối đa 2 quái xông cùng lúc
	var cs: Array = []
	for i in 4:
		var c = mk("charger", Vector2(1100 + i * 30, fy - 22.0))
		c.dir = -1
		cs.append(c)
	p.global_position = Vector2(950, fy - 22.0)
	await frames(30)
	var rush := 0
	for c in cs:
		if c.state == "windup" or c.state == "lunge":
			rush += 1
	ck(rush <= 2 and rush >= 1, "nightmare: ≤2 charger xông cùng lúc (%d)" % rush)
	St.nightmare = false
	for c in cs:
		c.state = "idle"
		c._kb_t = 0.0
	await frames(3)
	rush = 0
	for c in cs:
		if c.state == "windup" or c.state == "lunge":
			rush += 1
	ck(rush >= 3, "tắt nightmare: không giới hạn (%d)" % rush)
	St.nightmare = true
	for c in cs:
		c.queue_free()
	await frames(2)

	# --- reviver hồi nhanh khi có quái khác gần
	var rv = mk("reviver", Vector2(500, fy - 20.0))
	await frames(5)
	rv.take_hit(99, Vector2(400, fy))
	ck(rv.state == "down", "reviver nằm")
	rv._t = 2.0
	var t0: float = rv._t
	await frames(30)
	var alone: float = t0 - rv._t
	var rv2 = mk("reviver", Vector2(1500, fy - 20.0))
	var buddy = mk("crawler", Vector2(1550, fy - 20.0))
	await frames(5)
	rv2.take_hit(99, Vector2(1400, fy))
	rv2._t = 2.0
	await frames(30)
	var withbuddy: float = 2.0 - rv2._t
	ck(withbuddy > alone * 1.25, "có quái khác gần: hồi nhanh hơn (%f vs %f)" % [withbuddy, alone])
	rv.queue_free()
	rv2.queue_free()
	buddy.queue_free()

	# --- Stalker
	var S = load("res://hk/stalker.gd")
	var st := CharacterBody2D.new()
	st.set_script(S)
	st.arena = room.bounds()
	var sh: Array = []
	st.sfx.connect(func(n: String): sh.append(n))
	var touched := [0]
	st.touched.connect(func(): touched[0] += 1)
	root.add_child(st)
	p.global_position = Vector2(300, fy - 22.0)
	await frames(3)
	ck(st.global_position.x > room.bounds().get_center().x and sh.has("stalk"), "Stalker hiện ở phía xa")
	ck(st.state == "appear", "mới hiện: chưa đuổi")
	var d0: float = st.global_position.distance_to(p.global_position)
	await frames(100)
	ck(st.state == "chase", "sau APPEAR thì đuổi (%s)" % st.state)
	await frames(60)
	ck(st.global_position.distance_to(p.global_position) < d0 - 100.0, "đuổi lại gần")
	# chậm hơn người chơi: tốc độ < tốc độ chạy
	ck(S.SPEED < 200.0, "chậm hơn người chơi")
	# chém: choáng 3s, không chết
	ck(st.take_hit(5, p.global_position) == true and st.state == "stun", "chém: choáng")
	var pos_stun: Vector2 = st.global_position
	await frames(30)
	ck(st.global_position == pos_stun, "choáng: đứng yên")
	await frames(170)
	ck(st.state == "chase", "hết choáng thì đuổi lại (%s)" % st.state)
	# chạm: mất 1 mặt nạ, biến mất, báo world
	p.invuln = 0.0
	St.hp = St.max_hp()
	p.hp = St.hp
	st.global_position = p.global_position
	await frames(2)
	ck(touched[0] == 1 and st.state == "gone", "chạm: biến mất + báo (touched %d, %s)" % [touched[0], st.state])
	ck(st.collision_layer == 0, "biến mất: không còn bị chém")
	# đỡ: choáng
	var st2 := CharacterBody2D.new()
	st2.set_script(S)
	st2.arena = room.bounds()
	root.add_child(st2)
	await frames(100)
	st2.stagger(0.6)
	ck(st2.state == "stun", "đỡ: choáng qua stagger")
	print("DONE fails=", fails)
	quit(fails)
