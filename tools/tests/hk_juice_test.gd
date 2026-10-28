extends SceneTree
## Test hiệu ứng: vòng/tia/chết tạo node rồi tự dọn, cài đặt rung màn hình (tắt thì camera không rung; lưu/đọc; menu Pause bật/tắt),
## boss/quái vẽ không lỗi (không còn vùng cảnh báo màu).
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await process_frame
	await process_frame
	e.pressed = false
	Input.parse_input_event(e)
	await process_frame

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	var FX = load("res://hk/fx.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_juice_save.json"
	St.delete_save()
	# hiệu ứng tự dọn
	var holder := Node2D.new()
	root.add_child(holder)
	var n0: int = holder.get_child_count()
	FX.ring(holder, Vector2(10, 10), Color.RED)
	FX.spark(holder, Vector2(10, 10), Vector2.RIGHT, Color.RED)
	FX.death(holder, Vector2(10, 10), Color.RED)
	FX.death(holder, Vector2(10, 10), Color.RED, true)
	ck(holder.get_child_count() >= n0 + 4, "hiệu ứng tạo node (%d)" % (holder.get_child_count() - n0))
	await create_timer(1.6).timeout
	ck(holder.get_child_count() == n0, "hiệu ứng tự dọn sau khi xong (còn %d)" % (holder.get_child_count() - n0))
	# rung màn hình
	var cam = load("res://hk/camera.gd").new()
	root.add_child(cam)
	cam.shake(10.0)
	cam._process(0.0)
	ck(cam.offset != Vector2.ZERO, "bật rung: camera rung")
	await create_timer(1.2).timeout
	St.shake_on = false
	cam.shake(5.0)
	await process_frame
	await process_frame
	ck(cam.offset == Vector2.ZERO, "tắt rung: camera đứng yên")
	St.shake_on = true
	# lưu/đọc, dữ liệu hỏng, ván mới không xoá cài đặt
	St.shake_on = false
	ck(St.save(), "ghi save")
	St.shake_on = true
	ck(St.load_save() and St.shake_on == false, "đọc lại shake_on=false")
	var d: Dictionary = St.to_dict()
	d["shake_on"] = "rác"
	St.shake_on = true
	St.from_dict(d)
	ck(St.shake_on == true, "giá trị sai kiểu: giữ nguyên")
	d.erase("shake_on")
	St.shake_on = false
	St.from_dict(d)
	ck(St.shake_on == false, "save cũ không có khoá: giữ giá trị hiện tại")
	St.reset()
	ck(St.shake_on == false, "reset() không xoá cài đặt rung")
	# menu Pause: hàng thứ 3 bật/tắt
	St.shake_on = true
	var menu = load("res://hk/menu.gd").new()
	root.add_child(menu)
	await process_frame
	menu.open("pause")
	await process_frame
	await press("hk_down")
	await press("hk_down")
	await press("hk_left")
	ck(St.shake_on == false, "menu: Left ở hàng rung -> tắt")
	await press("hk_right")
	ck(St.shake_on == true, "menu: Right -> bật")
	menu.close()
	# vẽ boss/quái không lỗi (SCRIPT ERROR sẽ làm run_all báo FAIL)
	var room := Node2D.new()
	room.set_script(load("res://hk/room.gd"))
	root.add_child(room)
	var grid: Array = []
	for r in 20:
		grid.append("#".repeat(60) if r == 19 else "#" + ".".repeat(58) + "#")
	room.build("test", {"area": "gate", "doors": {}, "grid": grid})
	var p := CharacterBody2D.new()
	p.set_script(load("res://hk/player.gd"))
	p.position = Vector2(400, 560)
	root.add_child(p)
	var states: Dictionary = {"warden": ["wind_slash", "wind_slam"], "hexer": ["wind_bolt", "wind_conjure"]}
	for kind in states:
		var b := CharacterBody2D.new()
		b.set_script(load("res://hk/boss.gd"))
		b.kind = kind
		b.position = Vector2(800, 520)
		root.add_child(b)
		b.arena = room.bounds()
		await create_timer(0.3).timeout
		for st in states[kind]:
			b.state = st
			b._t = 0.3
			b.queue_redraw()
			await process_frame
			await process_frame
		b.queue_free()
	for kind in ["charger", "guard"]:
		var e := CharacterBody2D.new()
		e.set_script(load("res://hk/enemy.gd"))
		e.kind = kind
		e.position = Vector2(900, 560)
		root.add_child(e)
		await process_frame
		e.set_physics_process(false)
		e.state = "windup"
		e._t = 0.3
		e.queue_redraw()
		await process_frame
		await process_frame
		e.queue_free()
	St.delete_save()
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
