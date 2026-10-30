extends SceneTree
## Camera zoom: zoom_to mượt/snap, punch giật rồi trả, clamp theo phòng, tắt Zoom effects thì luôn zoom thường, boss lớn zoom ra / boss thường zoom vào,
## hạ boss/vào phòng mới trả zoom, chết zoom vào, cài đặt lưu/đọc/menu.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout

func press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	ev.pressed = false
	Input.parse_input_event(ev)
	await process_frame

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_camera_save.json"
	St.delete_save()
	St.zoom_on = true
	var w := Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	await wait(0.5)
	var cam: Camera2D = w.cam
	ck(absf(cam.zoom.x - 1.5) < 0.01 and absf(cam.base - 1.5) < 0.001, "zoom thường 1.5")
	# mượt và snap
	cam.zoom_to(1.7, 3.0)
	await wait(0.1)
	ck(cam.zoom.x > 1.5 and cam.zoom.x < 1.69, "zoom_to đi dần (%.3f)" % cam.zoom.x)
	await wait(2.0)
	ck(absf(cam.zoom.x - 1.7) < 0.01, "đến mục tiêu")
	cam.zoom_to(1.5, 0.0, true)
	ck(absf(cam.zoom.x - 1.5) < 0.001, "snap đặt ngay")
	# punch giật rồi trả
	cam.punch()
	await wait(0.05)
	ck(cam.zoom.x > 1.52, "punch làm zoom lớn hơn (%.3f)" % cam.zoom.x)
	await wait(0.6)
	ck(absf(cam.zoom.x - 1.5) < 0.005, "punch tự trả")
	# clamp: phòng nhỏ hơn khung nhìn ở zoom ra -> không zoom ra quá mức phòng
	cam.set_bounds(Rect2(0, 0, 1000, 600))
	cam.zoom_to(0.5, 0.0, true)
	ck(cam.zoom.x >= 1.28 - 0.01, "không zoom ra quá phòng (%.3f)" % cam.zoom.x)
	cam.set_bounds(w.room.bounds())
	cam.zoom_to(1.5, 0.0, true)
	# tắt Zoom effects -> luôn zoom thường
	St.zoom_on = false
	cam.zoom_to(1.9, 0.0, true)
	cam.punch()
	await wait(0.1)
	ck(absf(cam.zoom.x - 1.5) < 0.001, "Zoom effects tắt: giữ 1.5")
	St.zoom_on = true
	cam.zoom_to(1.5, 0.0, true)
	# boss thường zoom vào, boss lớn zoom ra, hạ boss / vào phòng trả zoom
	var cases: Array = [["gate_6", "warden", 1.7], ["arc_5", "colossus", 1.3], ["vault_7", "lord", 1.3], ["sov_1", "many_faced", 1.3]]
	for c in cases:
		St.flags.erase("boss_" + c[1])
		w.busy = false
		w.load_room(c[0])
		await process_frame
		w.player.respawn_at(w.room.default_spawn())   # xa boss: không kích hoạt ngay
		await wait(0.1)
		ck(is_instance_valid(w.boss), "%s: có boss" % c[0])
		if w.boss.state == "dormant":   # cửa gần boss thì boss kích hoạt ngay khi vào (zoom đã bắt đầu đổi): chỉ kiểm khi chưa kích hoạt
			ck(absf(cam.zoom.x - 1.5) < 0.001, "%s: vào phòng ở zoom thường" % c[0])
		w.boss.state = "dormant"
		w.player.global_position = w.boss.global_position + Vector2(-200, 0)
		await wait(2.5)
		var want: float = c[2]
		var lo: float = maxf(want, cam._min_zoom)
		ck(absf(cam.zoom.x - lo) < 0.02, "%s: zoom %.2f khi vào trận (đang %.3f)" % [c[1], lo, cam.zoom.x])
		w.boss.state = "idle"
		w.boss.take_hit(99999, Vector2.ZERO)
		await wait(2.5 if c[1] == "warden" else 0.2)
		if c[1] == "warden":
			ck(absf(cam.zoom.x - 1.5) < 0.02, "hạ boss: zoom về thường (%.3f)" % cam.zoom.x)
		St.flags.erase("boss_" + c[1])
		St.flags.erase("ending")
		St.flags.erase("ending_true")
		w.busy = false
		w.player.controls_enabled = true
	w.load_room("gate_1")
	ck(absf(cam.zoom.x - 1.5) < 0.001, "vào phòng mới: snap về zoom thường")
	# chết: zoom vào rồi phòng mới snap lại
	w.busy = false
	w.player.hp = 0
	w.player.died.emit()
	await wait(0.6)
	ck(cam.zoom.x > 1.55, "chết: zoom vào (%.3f)" % cam.zoom.x)
	await wait(2.5)
	ck(absf(cam.zoom.x - 1.5) < 0.005, "hồi sinh: zoom thường")
	# cài đặt: lưu/đọc/sai kiểu/reset không xoá
	St.zoom_on = false
	St.save()
	St.zoom_on = true
	ck(St.load_save() and St.zoom_on == false, "đọc lại zoom_on=false")
	var d: Dictionary = St.to_dict()
	d["zoom_on"] = "rác"
	St.zoom_on = true
	St.from_dict(d)
	ck(St.zoom_on == true, "sai kiểu: giữ nguyên")
	St.zoom_on = false
	St.reset()
	ck(St.zoom_on == false, "reset() không xoá")
	St.zoom_on = true
	# menu Pause: hàng thứ 5 chỉnh Zoom effects
	var menu = load("res://hk/menu.gd").new()
	root.add_child(menu)
	await process_frame
	menu.open("pause")
	await process_frame
	for i in 4:
		await press("hk_down")
	await press("hk_left")
	ck(St.zoom_on == false, "menu: Left ở hàng Zoom -> tắt")
	await press("hk_right")
	ck(St.zoom_on == true, "menu: Right -> bật")
	St.delete_save()
	print("hk_camera_test: ", "OK" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails > 0 else 0)
