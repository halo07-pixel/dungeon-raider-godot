extends SceneTree
## Màn hình tiêu đề: nền cột + tàn lửa (tắt theo Atmosphere), âm tick/deny/buy qua signal, mục Boss Rush khoá/mở, mờ ra đen rồi mới phát chosen.
var fails: int = 0
var sounds: Array = []
var chosen: Array = []

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

func make() -> Node:
	var t: Node = load("res://hk/title.gd").new()
	t.sfx.connect(func(n: String): sounds.append(n))
	t.chosen.connect(func(m: String, s: int): chosen.append([m, s]))
	root.add_child(t)
	return t

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	St.slot_base = "user://hk_title_test.json"
	for i in St.SLOTS:
		DirAccess.remove_absolute(St.slot_path(i))
	load("res://hk/rush.gd").record_path = "user://hk_title_test_rec.json"
	# nền + tàn lửa
	St.atmosphere_on = true
	var t: Node = make()
	await create_timer(0.3, true, false, true).timeout
	ck(t._pillars.size() == 3 and t._embers != null and t._embers.emitting, "có 3 lớp cột và tàn lửa khi Atmosphere bật")
	t.queue_free()
	St.atmosphere_on = false
	var t2: Node = make()
	await create_timer(0.3, true, false, true).timeout
	ck(not t2._embers.emitting, "Atmosphere tắt -> không tàn lửa")
	St.atmosphere_on = true
	t2.queue_free()
	await create_timer(0.2, true, false, true).timeout
	# Boss Rush khoá: deny, không rời màn
	var t3: Node = make()
	await create_timer(0.3, true, false, true).timeout
	ck(not t3._rush_ok, "chưa xong ván nào -> Rush khoá")
	await tap("hk_down")
	ck(sounds.has("tick") and t3._sel == 1, "đổi mục phát tick")
	t3._sel = St.SLOTS
	await tap("hk_jump")
	ck(sounds.has("deny") and t3._out < 0.0 and chosen.is_empty(), "chọn Rush khoá: deny, ở lại")
	t3.queue_free()
	await create_timer(0.2, true, false, true).timeout
	# mở khoá: chọn -> buy, mờ ra đen, rồi chosen("rush", 0); phím lúc mờ bị bỏ qua
	St.reset()
	St.set_flag("ending")
	St.save_path = St.slot_path(0)
	St.save()
	sounds.clear()
	var t4: Node = make()
	await create_timer(0.3, true, false, true).timeout
	ck(t4._rush_ok, "có ô đã xong -> Rush mở")
	t4._sel = St.SLOTS
	await tap("hk_jump")
	ck(sounds.has("buy") and t4._out >= 0.0, "chọn Rush: buy và bắt đầu mờ")
	var sel_before: int = t4._sel
	await tap("hk_up")
	ck(t4._sel == sel_before, "phím lúc đang mờ bị bỏ qua")
	await create_timer(0.8, true, false, true).timeout
	ck(chosen.size() == 1 and chosen[0][0] == "rush" and chosen[0][1] == 0, "xong mờ -> chosen(rush, 0) đúng một lần")
	DirAccess.remove_absolute(St.slot_path(0))
	DirAccess.remove_absolute(St.slot_path(0) + ".tmp")
	print("hk_title_test: ", "OK" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails > 0 else 0)
