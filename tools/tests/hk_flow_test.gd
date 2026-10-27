extends SceneTree
## Test luồng: tiêu đề -> New Game -> world -> (giả lập hạ boss cuối) -> màn kết thúc -> về tiêu đề -> Continue.
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
	St.slot_base = "user://hk_flow_save.json"
	for i in St.SLOTS:
		DirAccess.remove_absolute(St.slot_path(i))
	var main: Node = load("res://hk/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.3, true, false, true).timeout
	ck(main._overlay != null and main._overlay.get_script().resource_path.ends_with("title.gd"), "mở game ra màn hình tiêu đề")
	ck(main._world == null, "chưa có world khi ở tiêu đề")
	# không có save: ô 1 trống, Jump = New Game
	await tap("hk_jump")
	await create_timer(0.5, true, false, true).timeout
	ck(main._world != null and main._world.room != null, "New Game vào world")
	ck(St.boot == "keep", "boot chuyển về keep sau khi world đọc")
	# hạ boss cuối
	main._world._on_boss_defeated("lord")
	ck(St.flag("boss_lord") and St.flag("ending"), "hạ Lord đặt cờ ending")
	await create_timer(3.4, true, false, true).timeout
	ck(main._overlay != null and main._overlay.get_script().resource_path.ends_with("ending.gd"), "hiện màn kết thúc")
	await create_timer(2.6, true, false, true).timeout
	await tap("hk_jump")
	await create_timer(0.3, true, false, true).timeout
	ck(main._overlay != null and main._overlay.get_script().resource_path.ends_with("title.gd"), "về màn hình tiêu đề")
	ck(FileAccess.file_exists("user://hk_flow_save.json"), "ending đã lưu save")
	# Continue giữ cờ ending
	await tap("hk_jump")
	await create_timer(0.5, true, false, true).timeout
	ck(main._world != null and St.flag("ending"), "Continue nạp lại save có cờ ending")
	for i in St.SLOTS:
		DirAccess.remove_absolute(St.slot_path(i))
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
