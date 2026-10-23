extends SceneTree
## Lưu/nạp an toàn: ghi qua file tạm + .bak, file hỏng không làm sập game, nạp lại bản .bak, kiểu dữ liệu sai bị bỏ qua.
## Chạy: godot --headless --path . -s tools/tests/save_safety_test.gd
var fails: int = 0
func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func _init() -> void:
	call_deferred("_run")

func _write_raw(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()

func _run() -> void:
	var G = root.get_node("Global")
	var path := "user://save_safety_test.dat"
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(path + suffix)
	G.save_path = path

	# 1) lưu lần đầu: có file chính, không có .tmp
	G.purple_gems = 7
	G.save_game()
	ck(FileAccess.file_exists(path), "file chinh duoc tao")
	ck(not FileAccess.file_exists(path + ".tmp"), "khong de lai file tam")

	# 2) lưu lần hai: .bak giữ giá trị lần trước
	G.purple_gems = 11
	G.save_game()
	ck(FileAccess.file_exists(path + ".bak"), "co ban .bak sau lan luu thu hai")
	var bak = G._read_save(path + ".bak")
	ck(bak is Dictionary and int(bak["purple_gems"]) == 7, ".bak giu gia tri lan truoc (7)")

	# 3) nạp bình thường
	G.purple_gems = 0
	G.load_game()
	ck(G.purple_gems == 11, "nap file chinh: purple_gems 11, duoc %d" % G.purple_gems)

	# 4) file chính hỏng (rác): nạp từ .bak, không lỗi
	_write_raw(path, PackedByteArray([1, 2, 3, 4, 5]))
	G.purple_gems = 0
	G.load_game()
	ck(G.purple_gems == 7, "file chinh hong -> nap .bak (7), duoc %d" % G.purple_gems)

	# 5) file chính rỗng (kiểu bị cắt khi ghi): nạp từ .bak
	_write_raw(path, PackedByteArray())
	G.purple_gems = 0
	G.load_game()
	ck(G.purple_gems == 7, "file chinh rong -> nap .bak, duoc %d" % G.purple_gems)

	# 6) cả hai hỏng: dùng mặc định, không crash, rồi lưu được lại
	_write_raw(path, PackedByteArray([9, 9, 9]))
	_write_raw(path + ".bak", PackedByteArray([8, 8]))
	G.load_game()
	ck(true, "ca hai hong khong crash")
	G.purple_gems = 3
	G.save_game()
	var again = G._read_save(path)
	ck(again is Dictionary and int(again["purple_gems"]) == 3, "luu lai duoc sau khi hong")

	# 7) kiểu dữ liệu sai trong upgrades bị bỏ qua, không làm hỏng
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_var({"purple_gems": 5, "upgrades": {"hp_boost": "abc", "mastery": 2.0}, "saved_run": "garbage", "settings": 5})
	f.close()
	G.upgrades["hp_boost"] = 0
	G.upgrades["mastery"] = 0
	G.load_game()
	ck(int(G.upgrades["hp_boost"]) == 0, "gia tri chu bi bo qua")
	ck(int(G.upgrades["mastery"]) == 2, "so thuc duoc ep thanh int")
	ck(G.saved_run is Dictionary and G.saved_run.is_empty(), "saved_run sai kieu -> rong")

	# 8) tự lưu ván: sang tầng mới và đóng cửa sổ đều ghi saved_run; chết rồi thì không lưu
	G.saved_run = {}
	G.current_class = "ranger"
	change_scene_to_file("res://scenes/main.tscn")
	for i in 30:
		await physics_frame
	var main = current_scene
	G.floor_num = 2
	main._next_floor()
	for i in 30:
		await physics_frame
	ck(not G.saved_run.is_empty(), "sang tang moi -> co saved_run")
	ck(String(G.saved_run.get("class", "")) == "ranger", "saved_run dung class")
	var disk = G._read_save(path)
	ck(disk is Dictionary and disk.get("saved_run", {}) is Dictionary and not disk["saved_run"].is_empty(), "saved_run da ghi xuong dia")
	G.saved_run = {}
	main._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	ck(not G.saved_run.is_empty(), "dong cua so -> luu van")
	G.saved_run = {}
	main.is_game_over = true
	main._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	ck(G.saved_run.is_empty(), "da chet -> khong luu van")

	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(path + suffix)
	print("save_safety_test: ", "OK" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails > 0 else 0)
