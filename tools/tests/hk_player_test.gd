extends SceneTree
## Test cảm giác chơi cơ bản của bản Hollow Knight-style: rơi/đáp đất, nhảy cao-thấp, dash, chém, pogo, mất máu.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func hold(a: String, n: int) -> void:
	Input.action_press(a)
	await frames(n)
	Input.action_release(a)
	await frames(1)

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var room := Node2D.new()
	room.set_script(load("res://hk/room.gd"))
	room.rects = [Rect2(-500, 600, 3000, 200)]
	root.add_child(room)
	var p := CharacterBody2D.new()
	p.set_script(load("res://hk/player.gd"))
	p.position = Vector2(0, 500)
	root.add_child(p)
	await frames(60)
	ck(p.is_on_floor(), "đáp xuống sàn")
	var floor_y: float = p.position.y
	# nhảy cao (giữ) vs nhảy thấp (nhả sớm)
	var top_hold: float = floor_y
	Input.action_press("hk_jump")
	for i in 40:
		await physics_frame
		top_hold = minf(top_hold, p.position.y)
	Input.action_release("hk_jump")
	await frames(60)
	var top_tap: float = floor_y
	Input.action_press("hk_jump")
	await physics_frame
	Input.action_release("hk_jump")
	for i in 40:
		await physics_frame
		top_tap = minf(top_tap, p.position.y)
	await frames(60)
	ck(floor_y - top_hold > 100.0, "nhảy giữ phím cao >100px (%.0f)" % (floor_y - top_hold))
	ck(floor_y - top_tap < (floor_y - top_hold) * 0.6, "nhảy nhả sớm thấp hơn (%.0f vs %.0f)" % [floor_y - top_tap, floor_y - top_hold])
	# dash
	p.facing = 1
	var x0: float = p.position.x
	await hold("hk_dash", 1)
	await frames(15)
	ck(p.position.x - x0 > 100.0, "dash đi xa (%.0f)" % (p.position.x - x0))
	await frames(40)
	# chém quái
	var e := CharacterBody2D.new()
	e.set_script(load("res://hk/crawler.gd"))
	e.position = Vector2(p.position.x + 60.0, 576)
	root.add_child(e)
	await frames(2)
	e.set_physics_process(false)
	var hp0: int = e.hp
	p.facing = 1
	await hold("hk_attack", 1)
	await frames(10)
	ck(e.hp == hp0 - 1, "chém ngang trúng quái, đúng 1 lần (%d -> %d)" % [hp0, e.hp])
	await frames(30)
	# pogo: đứng trên quái, chém xuống khi đang ở trên không
	e.position = Vector2(p.position.x, 590)
	p.position = Vector2(p.position.x, 490)
	p.velocity = Vector2.ZERO
	p.can_dash = false
	Input.action_press("hk_down")
	await physics_frame
	var vy_min: float = 0.0
	Input.action_press("hk_attack")
	for i in 14:
		await physics_frame
		vy_min = minf(vy_min, p.velocity.y)
	Input.action_release("hk_attack")
	Input.action_release("hk_down")
	ck(vy_min <= p.POGO_V + 1.0, "chém xuống trúng quái thì nảy lên (vy %.0f)" % vy_min)
	ck(e.hp < hp0 - 1 or not is_instance_valid(e), "chém xuống gây sát thương")
	await frames(60)
	# mất máu + khung bất tử
	var hp1: int = p.hp
	p.take_damage(p.position.x - 50.0)
	p.take_damage(p.position.x - 50.0)
	ck(p.hp == hp1 - 1, "bị đánh mất 1 mặt nạ, khung bất tử chặn đòn thứ hai")
	ck(p.velocity.x > 0.0, "bị hất ra xa nguồn đòn")
	Engine.time_scale = 1.0
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
