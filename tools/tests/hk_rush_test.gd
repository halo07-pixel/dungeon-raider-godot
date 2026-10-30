extends SceneTree
## Boss Rush: mở khoá theo ô save đã xong, kỷ lục (chỉ nhận nhanh hơn, đọc có kiểm tra kiểu), trạng thái cô lập (save tạm, đủ đồ),
## hạ boss -> đầy máu + sang boss kế, chết -> hồi sinh tại trận và đếm, boss cuối -> rush_finished; save thật không bị đụng.
var fails: int = 0
var got: Array = []

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout

func kill(w: Node2D) -> void:
	w.boss.state = "idle"
	w.boss.take_hit(99999, Vector2.ZERO)

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	var Rush = load("res://hk/rush.gd")
	St.slot_base = "user://hk_rush_test_slot.json"
	Rush.record_path = "user://hk_rush_test_rec.json"
	for p in [Rush.record_path, Rush.RUN_PATH]:
		DirAccess.remove_absolute(p)
	for i in St.SLOTS:
		DirAccess.remove_absolute(St.slot_path(i))
	# mở khoá
	St.reset()
	St.boot = "keep"
	St.save_path = St.slot_path(0)
	St.save()
	ck(not Rush.unlocked(), "chưa xong ván nào -> khoá")
	St.set_flag("ending")
	St.save_path = St.slot_path(1)
	St.save()
	ck(Rush.unlocked() and not Rush.has_true_end(), "có ô đã xong -> mở, chưa True End")
	St.set_flag("ending_true")
	St.save()
	ck(Rush.has_true_end(), "ô True End -> thêm boss bí mật")
	# kỷ lục
	ck(Rush.best() < 0.0, "chưa có kỷ lục")
	ck(Rush.submit(300.0) and absf(Rush.best() - 300.0) < 0.01, "ghi kỷ lục đầu")
	ck(not Rush.submit(400.0) and absf(Rush.best() - 300.0) < 0.01, "chậm hơn không ghi đè")
	ck(Rush.submit(250.0) and absf(Rush.best() - 250.0) < 0.01, "nhanh hơn ghi đè")
	var f := FileAccess.open(Rush.record_path, FileAccess.WRITE)
	f.store_string("{\"best\": \"abc\"}")
	f.close()
	ck(Rush.best() < 0.0, "kỷ lục hỏng kiểu -> bỏ qua")
	DirAccess.remove_absolute(Rush.record_path)
	# kỷ lục từng boss: ghi ngay, chỉ nhận nhanh hơn, không làm mất kỷ lục cả lượt
	ck(Rush.record_split("warden", 40.0) and absf(Rush.seg_best("warden") - 40.0) < 0.01, "split đầu là kỷ lục")
	ck(not Rush.record_split("warden", 50.0) and absf(Rush.seg_best("warden") - 40.0) < 0.01, "split chậm hơn không ghi đè")
	ck(Rush.record_split("warden", 35.5) and absf(Rush.seg_best("warden") - 35.5) < 0.01, "split nhanh hơn ghi đè")
	Rush.submit(250.0)
	ck(absf(Rush.best() - 250.0) < 0.01 and absf(Rush.seg_best("warden") - 35.5) < 0.01, "kỷ lục cả lượt và từng boss cùng tồn tại")
	ck(Rush.fmt(75.34) == "1:15.3" and Rush.fmt(5.0) == "0:05.0", "định dạng m:ss.d")
	DirAccess.remove_absolute(Rush.record_path)
	Rush.splits = []
	# trạng thái lượt
	Rush.setup(false)
	ck(St.save_path == Rush.RUN_PATH and St.max_hp() == 7 and St.notches() == 5, "save tạm, 7 mặt nạ, 5 ô")
	ck(St.has_ability("dash") and St.has_ability("wall_cling") and "oath_ward" in St.charms_owned and "many_faces" in St.charms_owned, "đủ kỹ năng và bùa")
	ck(St.notches_used() <= St.notches() and Rush.order.size() == 6 and Rush.idx == -1 and Rush.current_room() == Rush.HUB, "bùa mặc định vừa ô, 6 boss, bắt đầu ở sảnh")
	Rush.setup(true)
	ck(Rush.order.size() == 7 and String(Rush.order[6][0]) == "many_faced", "có True End -> 7 boss, many_faced cuối")
	for pair in Rush.order:
		ck(load("res://hk/world_data.gd").load_all().has(String(pair[1])), "phòng %s tồn tại" % pair[1])
	# trong engine thật
	St.boot = "rush"
	var w := Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	w.rush_finished.connect(func(t: float, d: int, r: bool): got = [t, d, r])
	root.add_child(w)
	await wait(0.5)
	ck(St.rush and w.room.id == Rush.HUB and w.boss == null and St.save_path == Rush.RUN_PATH, "vào Rush: ở sảnh, chưa có boss, save tạm")
	var t_hub: float = Rush.time
	await wait(0.5)
	ck(Rush.time == t_hub, "đồng hồ không chạy ở sảnh")
	w._on_door("1")   # ra khỏi sảnh = bắt đầu
	await wait(1.5)
	ck(Rush.idx == 0 and w.room.id == "gate_6" and is_instance_valid(w.boss), "ra cửa sảnh: sang gate_6 có boss")
	ck(not FileAccess.file_exists(St.slot_path(0)) or St.slot_info(0).get("rooms", 0) == 0, "save thật không bị ghi")
	# chết -> hồi sinh tại trận, đếm
	w.player.take_damage(0.0)
	w.player.hp = 0
	w.player.died.emit()
	await wait(2.5)
	ck(Rush.deaths == 1 and w.room.id == "gate_6" and is_instance_valid(w.boss) and not w.busy, "chết: ở lại gate_6, deaths=1, boss còn")
	# hạ boss -> hồi đầy máu, sang boss kế sau ~2s
	w.player.hp = 2
	await wait(1.0)
	var t_kill: float = Rush.time
	ck(t_kill > 0.5, "đồng hồ chạy khi đang đánh (%.2f)" % t_kill)
	kill(w)
	await wait(0.3)
	ck(w.busy and Rush.idx == 0, "vừa hạ: chờ, chưa sang phòng kế")
	await wait(3.5)
	ck(Rush.time - t_kill < 1.3 and Rush.splits.size() == 1 and String(Rush.splits[0]["id"]) == "warden" and absf(float(Rush.splits[0]["seg"]) - t_kill) < 0.1, "chờ giữa boss không tính giờ; ghi split warden")
	ck(Rush.idx == 1 and w.room.id == "gate_7" and w.player.hp == St.max_hp() and is_instance_valid(w.boss), "sang gate_7, đầy máu, boss mới")
	# boss cuối
	Rush.idx = Rush.order.size() - 1
	await w._rush_enter()
	ck(w.room.id == "sov_1" and Rush.last(), "boss cuối (có True End): sov_1")
	kill(w)
	await wait(3.6)
	ck(got.size() == 3 and int(got[1]) == 1 and bool(got[2]) and absf(float(got[0]) - Rush.time) < 0.01 and Rush.splits.size() == 2, "rush_finished(time, 1 chết, kỷ lục), đủ split")
	ck(Rush.best() > 0.0, "kỷ lục được ghi")
	ck(not St.flag("ending"), "Rush không đặt cờ ending")
	for p in [Rush.record_path, Rush.RUN_PATH, Rush.RUN_PATH + ".tmp"]:
		DirAccess.remove_absolute(p)
	for i in St.SLOTS:
		DirAccess.remove_absolute(St.slot_path(i))
	print("hk_rush_test: ", "OK" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails > 0 else 0)
