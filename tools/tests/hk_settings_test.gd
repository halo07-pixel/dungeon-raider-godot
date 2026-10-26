extends SceneTree
## Test âm lượng (lưu/đọc, không bị reset xoá, menu Pause chỉnh được) và chữ gợi ý phím của gate_1.
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
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_settings_save.json"
	St.delete_save()
	ck(St.music_vol == 10 and St.sfx_vol == 10, "mặc định 10/10")
	ck(St.vol_db(10) == 0.0 and St.vol_db(0) <= -80.0 and St.vol_db(5) < St.vol_db(10), "đổi 0..10 sang dB")
	St.music_vol = 3
	St.sfx_vol = 7
	St.reset()
	ck(St.music_vol == 3 and St.sfx_vol == 7, "reset() không xoá âm lượng")
	ck(St.save(), "ghi save")
	St.music_vol = 10
	St.sfx_vol = 10
	ck(St.load_save() and St.music_vol == 3 and St.sfx_vol == 7, "đọc lại đúng âm lượng")
	var d: Dictionary = St.to_dict()
	d["music_vol"] = 99
	d["sfx_vol"] = -4
	St.from_dict(d)
	ck(St.music_vol == 10 and St.sfx_vol == 0, "save hỏng bị kẹp về 0..10")
	d.erase("music_vol")
	d.erase("sfx_vol")
	St.music_vol = 4
	St.from_dict(d)
	ck(St.music_vol == 4, "save cũ không có khoá: giữ giá trị hiện tại")
	# menu Pause: Left/Right chỉnh dòng đang chọn, Down đổi dòng
	St.music_vol = 5
	St.sfx_vol = 5
	var menu = load("res://hk/menu.gd").new()
	root.add_child(menu)
	var got: Array = [0]
	menu.volume_changed.connect(func(): got[0] += 1)
	await process_frame
	menu.open("pause")
	await process_frame
	await press("hk_right")
	ck(St.music_vol == 6 and St.sfx_vol == 5 and got[0] == 1, "Right tăng nhạc (%d,%d,%d)" % [St.music_vol, St.sfx_vol, got[0]])
	await press("hk_down")
	await press("hk_left")
	ck(St.music_vol == 6 and St.sfx_vol == 4, "Down rồi Left giảm hiệu ứng (%d,%d)" % [St.music_vol, St.sfx_vol])
	St.sfx_vol = 0
	await press("hk_left")
	ck(St.sfx_vol == 0, "không xuống dưới 0")
	menu.close()
	# gợi ý phím: gate_1 có chữ, phòng khác thì không
	var rooms: Dictionary = WD.load_all()
	var hints: Array = rooms["gate_1"]["hints"]
	ck(hints.size() >= 3, "gate_1 có gợi ý phím (%d)" % hints.size())
	for h in hints:
		ck(String(h["text"]).length() > 5 and int(h["col"]) > 0 and int(h["row"]) > 0, "gợi ý hợp lệ %s" % str(h))
	ck(rooms["gate_2"]["hints"].is_empty(), "gate_2 không có gợi ý")
	St.delete_save()
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
