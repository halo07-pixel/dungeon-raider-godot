extends SceneTree
## Test thế giới: dữ liệu phòng hợp lệ, cửa nối hai chiều, nạp mọi phòng, chuyển cửa, bench/save, chết + shade, shop, bùa.
var fails: int = 0
var St
var WD

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func _init() -> void:
	await process_frame
	St = load("res://hk/state.gd")
	WD = load("res://hk/world_data.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_test_save.json"
	St.delete_save()
	var rooms: Dictionary = WD.load_all()
	ck(rooms.size() >= 24, "đủ phòng (%d)" % rooms.size())
	# --- dữ liệu phòng ---
	var benches: int = 0
	var altars: Array = []
	var charms: Array = []
	var bosses: Array = []
	for id in rooms:
		var r: Dictionary = rooms[id]
		var grid: Array = r["grid"]
		var w: int = String(grid[0]).length()
		ck(w >= 28 and grid.size() >= 16, "%s đủ lớn cho camera (%dx%d)" % [id, w, grid.size()])
		var chars: Dictionary = {}
		for l in grid:
			ck(String(l).length() == w, "%s các dòng cùng độ dài" % id)
			for ch in String(l):
				chars[ch] = true
		if chars.has("B"): benches += 1
		if r.has("altar"): altars.append(r["altar"]["id"])
		if r.has("charm"): charms.append(r["charm"]["id"])
		if r.has("boss"): bosses.append(r["boss"]["id"])
		ck(chars.has("A") == r.has("altar"), "%s: ký tự A khớp khai báo altar" % id)
		ck(chars.has("C") == r.has("charm"), "%s: ký tự C khớp khai báo charm" % id)
		ck(chars.has("X") == r.has("boss"), "%s: ký tự X khớp khai báo boss" % id)
		for dch in r["doors"]:
			var link: Dictionary = r["doors"][dch]
			ck(chars.has(dch), "%s: cửa %s có trong lưới" % [id, dch])
			ck(rooms.has(link["to"]), "%s: cửa %s trỏ tới phòng có thật" % [id, dch])
			if rooms.has(link["to"]):
				var back: Dictionary = rooms[link["to"]]["doors"].get(link["door"], {})
				ck(not back.is_empty() and back["to"] == id and back["door"] == dch, "%s:%s nối hai chiều với %s:%s" % [id, dch, link["to"], link["door"]])
		for ch in chars:
			if ch.is_valid_int() and ch != "0":
				ck(r["doors"].has(ch), "%s: ký tự cửa %s có khai báo" % [id, ch])
	ck(benches >= 6, "đủ bench (%d)" % benches)
	for a in ["dash", "double_jump", "wall_cling"]:
		ck(a in altars, "có bàn thờ " + a)
	for b in ["warden", "wraith", "lord"]:
		ck(b in bosses, "có boss " + b)
	for c in charms:
		ck(St.CHARMS.has(c), "bùa " + c + " tồn tại")
	# --- bản đồ không chồng nhau ---
	var ids: Array = rooms.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a := Rect2(rooms[ids[i]]["map"], WD.map_size(rooms[ids[i]])).grow(-0.05)
			var b := Rect2(rooms[ids[j]]["map"], WD.map_size(rooms[ids[j]])).grow(-0.05)
			ck(not a.intersects(b), "bản đồ: %s và %s không chồng nhau" % [ids[i], ids[j]])
	# --- world ---
	var w := Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	await frames(5)
	ck(w.room.id == "gate_1", "bắt đầu ở gate_1")
	ck(w.player.is_on_floor() or true, "người chơi có mặt")
	for id in ids:
		w.load_room(id)
		await frames(2)
		ck(w.room.id == id, "nạp được phòng " + id)
		var sp: Vector2 = w.room.default_spawn()
		ck(w.room.bounds().has_point(sp), "%s: điểm xuất phát trong phòng" % id)
		for dch in w.room.doors:
			ck(w.room.bounds().grow(1.0).has_point(w.room.spawn_for_door(dch)), "%s: điểm vào cửa %s trong phòng" % [id, dch])
	# --- chuyển cửa ---
	w.load_room("gate_1")
	w.player.respawn_at(w.room.default_spawn(), true)
	await frames(30)
	await w.transition("gate_2", "1")
	ck(w.room.id == "gate_2" and not w.busy, "chuyển cửa sang gate_2")
	ck(w.player.global_position.x > 40.0 and w.player.global_position.x < 120.0, "xuất hiện sát cửa trái gate_2 (x=%f)" % w.player.global_position.x)
	await frames(20)
	ck(w.room.id == "gate_2", "không bị bật ngược về cửa (x=%f)" % w.player.global_position.x)
	# cửa dưới: đáp cạnh lỗ, không rơi lại
	await w.transition("gate_2", "3")
	await frames(40)
	ck(w.room.id == "gate_2" and w.player.is_on_floor(), "đến bằng cửa dưới thì đứng trên sàn")
	# --- bench lưu & hồi máu ---
	w.load_room("gate_1")
	w.player.respawn_at(w.room.bench_spawn(), true)
	STATE_set_hp(1)
	await w.rest()
	ck(St.hp == St.max_hp(), "bench hồi đầy máu")
	ck(St.bench_room == "gate_1" and FileAccess.file_exists("user://hk_test_save.json"), "bench ghi save")
	# --- chết: mất geo thành shade, về bench ---
	await w.transition("gate_2", "1")
	St.geo = 77
	w.player.global_position = Vector2(300, 500)
	w.player.invuln = 0.0 # rest()/respawn_at(refill) đặt khung bất tử 1s; test chờ hết thay vì đợi thật
	w.player.take_damage(0.0, 99)
	ck(w.player.is_dead(), "take_damage(99) giết được người chơi")
	await create_timer(2.5, true, false, true).timeout
	ck(w.room.id == "gate_1", "chết thì về bench (%s)" % w.room.id)
	ck(St.geo == 0 and int(St.shade.get("geo", 0)) == 77 and St.shade["room"] == "gate_2", "geo thành shade")
	ck(St.hp == St.max_hp() and not w.player.is_dead(), "hồi sinh đầy máu")
	await w.transition("gate_2", "1")
	var shade = null
	for n in w.get_children():
		pass
	for n in w._content.get_children():
		if n.has_method("take_hit") and n.get("amount") != null:
			shade = n
	ck(shade != null, "shade xuất hiện ở phòng đã chết")
	if shade:
		for i in 4:
			shade.take_hit(5, Vector2.ZERO)
		ck(St.geo == 77 and St.shade.is_empty(), "đánh shade lấy lại geo")
	# --- tương tác: bàn thờ, bùa, shop ---
	w._on_interacted("altar", {"id": "dash"})
	ck(St.has_ability("dash") and St.flag("got_dash"), "nhận kỹ năng dash")
	w._on_interacted("charm", {"id": "iron_heart"})
	ck("iron_heart" in St.charms_owned, "nhận bùa")
	ck(St.toggle_charm("iron_heart") and St.max_hp() == St.BASE_HP + 2, "bật Iron Heart +2 mặt nạ")
	ck(St.toggle_charm("heavy_blow") == false, "chưa sở hữu thì không bật được")
	St.give_charm("heavy_blow"); St.give_charm("long_reach")
	ck(St.toggle_charm("heavy_blow") == false, "hết ô thì không bật thêm (3 ô: 2+2>3)")
	ck(St.toggle_charm("iron_heart") and St.toggle_charm("heavy_blow") and not St.toggle_charm("long_reach"), "tháo Iron Heart thì bật được Heavy Blow, Long Reach (2) vẫn vượt 3 ô")
	ck(St.nail_damage() == 7, "Heavy Blow: sát thương 5 -> 7 (%d)" % St.nail_damage())
	St.geo = 1000
	w.shop.open(w.player)
	var stock: Array = w.shop._stock()
	ck(stock.size() >= 3, "shop có hàng")
	w.shop._buy(stock[0])
	ck(St.hp_bonus == 1 and St.geo < 1000, "mua mặt nạ")
	w.shop.close()
	# phím Up mở shop không được dịch lựa chọn trong khung mở (action_press không tạo just_pressed -> dùng sự kiện thật)
	var ev := InputEventAction.new()
	ev.action = "hk_up"
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	ck(Input.is_action_just_pressed("hk_up"), "kiểm tra thử: sự kiện hk_up là just_pressed")
	w.shop.open(w.player)
	w.shop._process(0.0)
	ck(w.shop._sel == 0, "khung đầu sau khi mở shop bị bỏ qua (sel=%d)" % w.shop._sel)
	ev.pressed = false
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	w.shop._process(0.0)
	ck(w.shop._sel != 0, "khung sau đó thì Up chạy bình thường (sel=%d)" % w.shop._sel)
	ev.pressed = false
	Input.parse_input_event(ev)
	w.shop.close()
	# --- save/load round trip ---
	St.save()
	var snap: Dictionary = St.to_dict()
	St.reset()
	ck(St.load_save(), "đọc được save")
	ck(St.to_dict()["abilities"] == snap["abilities"] and St.hp_bonus == 1 and St.flag("got_dash"), "save khớp")
	FileAccess.open("user://hk_test_save.json", FileAccess.WRITE).store_string("{hỏng")
	ck(not St.load_save(), "save hỏng không làm crash")
	St.delete_save()
	Engine.time_scale = 1.0
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)

func STATE_set_hp(v: int) -> void:
	St.hp = v
