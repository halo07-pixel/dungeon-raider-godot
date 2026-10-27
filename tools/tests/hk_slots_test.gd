extends SceneTree
## Test 3 ô save + đồng hồ chơi: đường dẫn ô, tóm tắt ô, time lưu/đọc/hỏng, tiêu đề chọn ô và xoá ô (P hai lần).
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func tap(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await create_timer(0.1, true, false, true).timeout
	ev.pressed = false
	Input.parse_input_event(ev)
	await create_timer(0.1, true, false, true).timeout

func _init() -> void:
	await process_frame
	var St = load("res://hk/state.gd")
	St.slot_base = "user://hk_slots_test.json"
	for i in St.SLOTS:
		DirAccess.remove_absolute(St.slot_path(i))
	ck(St.slot_path(0) == "user://hk_slots_test.json", "ô 1 dùng đường dẫn gốc")
	ck(St.slot_path(1) == "user://hk_slots_test_2.json" and St.slot_path(2) == "user://hk_slots_test_3.json", "ô 2,3 có hậu tố")
	ck(St.fmt_time(0.0) == "0:00:00" and St.fmt_time(3725.9) == "1:02:05", "định dạng giờ")
	ck(St.slot_info(0).is_empty(), "ô trống -> {}")
	# time lưu/đọc/hỏng
	St.reset()
	St.save_path = St.slot_path(1)
	St.play_time = 125.5
	St.visited = ["gate_1", "gate_2"]
	ck(St.save(), "ghi ô 2")
	var inf: Dictionary = St.slot_info(1)
	ck(int(inf.get("time", -1)) == 125 and inf.get("rooms") == 2 and inf.get("done") == false, "tóm tắt ô 2")
	ck(St.slot_info(0).is_empty() and St.slot_info(2).is_empty(), "ô khác vẫn trống")
	St.play_time = 0.0
	ck(St.load_save() and absf(St.play_time - 125.5) < 0.01, "đọc lại play_time")
	var d: Dictionary = St.to_dict()
	d["time"] = "rác"
	St.from_dict(d)
	ck(St.play_time == 0.0, "time sai kiểu -> 0")
	d["time"] = -50.0
	St.from_dict(d)
	ck(St.play_time == 0.0, "time âm -> 0")
	d.erase("time")
	St.from_dict(d)
	ck(St.play_time == 0.0, "save cũ không có time -> 0")
	St.play_time = 9.0
	St.reset()
	ck(St.play_time == 0.0, "reset() xoá play_time")
	# file save hỏng -> ô coi như trống
	var f := FileAccess.open(St.slot_path(2), FileAccess.WRITE)
	f.store_string("không phải json")
	f.close()
	ck(St.slot_info(2).is_empty(), "save hỏng -> {}")
	DirAccess.remove_absolute(St.slot_path(2))
	# tiêu đề
	var main: Node = load("res://hk/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.3, true, false, true).timeout
	var t: Node = main._overlay
	ck(t != null and t.get_script().resource_path.ends_with("title.gd"), "ra màn hình tiêu đề")
	ck(t._sel == 1, "con trỏ nhảy tới ô đã có save (ô 2)")
	await tap("hk_pin")
	ck(t._confirm == 1, "P lần 1: chờ xác nhận")
	await tap("hk_down")
	ck(t._confirm == -1, "đổi ô huỷ xác nhận")
	await tap("hk_up")
	await tap("hk_pin")
	await tap("hk_pin")
	ck(not FileAccess.file_exists(St.slot_path(1)) and t._info[1].is_empty(), "P hai lần xoá ô 2")
	# ô trống -> New Game ở ô 3, save_path trỏ ô 3
	await tap("hk_down")
	await tap("hk_jump")
	await create_timer(0.5, true, false, true).timeout
	ck(main._world != null and St.save_path == St.slot_path(2), "New Game ở ô 3 dùng save_path ô 3")
	var t0: float = St.play_time
	await create_timer(1.0, true, false, true).timeout
	ck(St.play_time > t0 + 0.5, "đồng hồ chơi chạy")
	St.save()
	ck(not St.slot_info(2).is_empty(), "ô 3 có save")
	main._show_title()
	await create_timer(0.3, true, false, true).timeout
	ck(main._overlay._sel == 2, "quay về tiêu đề: con trỏ ở ô có save")
	await tap("hk_jump")
	await create_timer(0.5, true, false, true).timeout
	ck(main._world != null and St.save_path == St.slot_path(2) and St.play_time >= t0 + 0.5, "Continue ô 3 nạp lại time")
	for i in St.SLOTS:
		DirAccess.remove_absolute(St.slot_path(i))
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
