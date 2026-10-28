extends SceneTree
## Test không khí: cài đặt atmosphere_on (lưu/đọc/hỏng/reset), lò lửa trong file phòng đứng trên sàn, đèn dựng theo phòng không rò,
## tắt thì trả về sáng thường, màu theo khu không quá tối, menu Pause bật/tắt.
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
	var WD = load("res://hk/world_data.gd")
	var A = load("res://hk/atmosphere.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_atmosphere_save.json"
	St.delete_save()
	# cài đặt
	ck(St.atmosphere_on == true, "mặc định bật")
	St.atmosphere_on = false
	St.reset()
	ck(St.atmosphere_on == false, "reset() không xoá cài đặt")
	ck(St.save(), "ghi save")
	St.atmosphere_on = true
	ck(St.load_save() and St.atmosphere_on == false, "đọc lại false")
	var d: Dictionary = St.to_dict()
	d["atmosphere_on"] = "rác"
	St.atmosphere_on = true
	St.from_dict(d)
	ck(St.atmosphere_on == true, "sai kiểu: giữ nguyên")
	d.erase("atmosphere_on")
	St.atmosphere_on = false
	St.from_dict(d)
	ck(St.atmosphere_on == false, "save cũ không có khoá: giữ nguyên")
	St.atmosphere_on = true
	# màu theo khu không quá tối (vùng báo hiệu đòn/gai phải còn rõ)
	for a in A.AREAS:
		var c: Color = A.AREAS[a]["ambient"]
		ck(minf(c.r, minf(c.g, c.b)) >= 0.7, "%s: ambient không tối hơn 0.7" % a)
	var rooms: Dictionary = WD.load_all()
	for id in ["gate", "catacomb", "vault", "archive"]:
		var found: bool = false
		for rid in rooms:
			if rooms[rid]["area"] == id:
				found = true
		ck(found and A.AREAS.has(id), "khu %s có cấu hình" % id)
	# lò lửa trong file phòng đứng trên sàn, trống phía trên
	var nt: int = 0
	for rid in rooms:
		var g: Array = rooms[rid]["grid"]
		for t in rooms[rid]["torches"]:
			nt += 1
			var col: int = int(t["col"])
			var row: int = int(t["row"])
			ck(String(g[row])[col] == "." and String(g[row - 1])[col] == ".", "%s: lò lửa ở ô trống" % rid)
			ck(String(g[row + 1])[col] in "#=", "%s: lò lửa đứng trên sàn" % rid)
	ck(nt >= 10, "có lò lửa trong các phòng (%d)" % nt)
	# trong world thật
	St.reset()
	St.bench_room = "gate_4"
	var w := Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	await create_timer(0.3).timeout
	var atm: Node2D = w.atmosphere
	var n_gate4: int = atm._lights.size()
	ck(n_gate4 >= rooms["gate_4"]["torches"].size() + 1, "gate_4: có đèn lò lửa và bench (%d)" % n_gate4)
	ck(atm._mod.color != Color.WHITE and atm._dust.emitting, "bật: có ánh sáng và hạt")
	var kids0: int = atm.get_child_count()
	w.load_room("cat_8")
	await process_frame
	await process_frame
	ck(atm._area == "catacomb", "đổi phòng: khu catacomb")
	w.load_room("gate_4")
	await process_frame
	await process_frame
	await process_frame
	ck(atm._lights.size() == n_gate4 and atm.get_child_count() == kids0, "đổi phòng đi về: đèn không rò (%d vs %d)" % [atm.get_child_count(), kids0])
	# menu Pause: dòng 4 = Atmosphere
	w.menu.open("pause")
	await process_frame
	for i in 3:
		await press("hk_down")
	await press("hk_left")
	ck(St.atmosphere_on == false, "menu: Left tắt Atmosphere")
	ck(atm._mod.color == Color.WHITE and not atm._dust.emitting and not atm._player_light.visible, "tắt: sáng thường, không hạt, không đèn")
	for it in atm._lights:
		ck(not it["l"].visible, "tắt: đèn phòng ẩn")
	await press("hk_right")
	ck(St.atmosphere_on == true and atm._mod.color != Color.WHITE and atm._player_light.visible, "menu: Right bật lại")
	St.delete_save()
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
