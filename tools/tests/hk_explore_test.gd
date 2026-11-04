extends SceneTree
## Khám phá: save `benches` (kiểm kiểu), đi nhanh giữa bench (chỉ khi đứng ở bench, không Rush/khoá boss, chỉ tới bench đã nghỉ),
## tường nứt `%` (chém một nhát vỡ cả cụm, cờ lưu, nạp lại vẫn mở, rương trong hốc gấp ba).
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func tap(a: String) -> void:
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	ev = InputEventAction.new()
	ev.action = a
	ev.pressed = false
	Input.parse_input_event(ev)
	await process_frame

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_explore_test_save.json"
	St.delete_save()
	# --- save ---
	St.from_dict({"benches": 5})
	ck(St.benches == [], "benches sai kiểu -> rỗng")
	St.from_dict({"benches": ["gate_4", 3, "cat_1", null]})
	ck(St.benches == ["gate_4", "cat_1"], "benches chỉ giữ chuỗi (%s)" % str(St.benches))
	St.reset()
	St.from_dict({"bench_room": "cat_1", "bench_id": "bench"})
	ck("cat_1" in St.benches, "save cũ chưa có benches: bench đang dùng được thêm vào")
	St.reset()
	St.benches = ["gate_4"]
	var d: Dictionary = St.to_dict()
	St.reset()
	ck(St.benches == [], "reset xoá benches")
	St.from_dict(d)
	ck(St.benches == ["gate_4"], "benches đi qua to_dict/from_dict")
	St.reset()
	# --- world ---
	var w := Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	await frames(5)
	ck(w.room.id == "gate_1", "bắt đầu ở gate_1")
	await w._travel("gate_4")
	ck(w.room.id == "gate_1", "bench chưa nghỉ: không đi nhanh được")
	St.benches = ["gate_1", "gate_4"]
	w.player.respawn_at(w.room.bench_spawn(), true)
	await frames(3)
	await process_frame
	await process_frame
	ck(w._at_bench(), "đứng ở bench: _at_bench")
	ck(w.menu.can_travel, "đứng ở bench: menu.can_travel (enabled=%s busy=%s)" % [str(w.menu.enabled), str(w.busy)])
	w.player.global_position = Vector2(700, w.player.global_position.y)
	await frames(2)
	await process_frame
	await process_frame
	ck(not w._at_bench() and not w.menu.can_travel, "đứng xa bench: không đi nhanh")
	w.player.respawn_at(w.room.bench_spawn(), true)
	St.rush = true
	ck(not w._at_bench(), "Boss Rush: không đi nhanh")
	St.rush = false
	w.room.locked = true
	ck(not w._at_bench(), "cửa đang khoá (đánh boss): không đi nhanh")
	w.room.locked = false
	w.menu.current_room = "gate_1"
	ck(w.menu.travel_targets() == ["gate_4"], "đích đi nhanh không gồm phòng hiện tại (%s)" % str(w.menu.travel_targets()))
	St.hp = 1
	await w._travel("gate_4")
	ck(w.room.id == "gate_4" and not w.busy, "đi nhanh tới gate_4")
	ck(St.hp == St.max_hp() and St.bench_room == "gate_4", "đến nơi: hồi đầy máu, bench đổi")
	ck(w.player.global_position.distance_to(w.room.bench_spawn()) < 4.0, "đứng cạnh bench")
	ck(w.room.bounds().has_point(w.player.global_position), "vị trí trong phòng")
	# --- menu: Bản đồ -> chọn bench -> đi nhanh ---
	St.benches = ["gate_1", "gate_4", "cat_1"]
	w.load_room("gate_1")
	w.player.respawn_at(w.room.bench_spawn(), true)
	await frames(3)
	await process_frame
	await tap("hk_map")
	ck(w.menu.tab == "map" and w.menu._targets == ["gate_4", "cat_1"], "mở Bản đồ ở bench: có 2 đích (%s)" % str(w.menu._targets))
	await tap("hk_down")
	ck(w.menu.sel == 1, "Xuống: chọn bench thứ hai")
	await tap("hk_jump")
	ck(w.menu.tab == "", "xác nhận: menu đóng")
	await frames(90)
	ck(w.room.id == "cat_1" and not w.busy, "đi nhanh qua menu tới cat_1 (%s)" % w.room.id)
	# --- tường nứt ---
	w.load_room("cat_3")
	await frames(3)
	for n in get_nodes_in_group("hk_enemy"):
		n.free()
	ck(w.room.cracks.size() == 2, "cat_3 có 2 ô tường nứt (%d)" % w.room.cracks.size())
	ck(get_nodes_in_group("hk_crack").size() == 2, "mỗi ô nứt là một body")
	var p = w.player
	p.invuln = 0.0
	var fy: float = float(w.room.rows - 4) * 32.0 - 22.0   # sàn ở hàng F = rows - 4
	p.global_position = Vector2(14.0 * 32.0 + 16.0, fy)
	p.velocity = Vector2.ZERO
	await frames(3)
	ck(not St.flag("secret_cat_3"), "chưa vỡ: chưa có cờ")
	var Menu = load("res://hk/menu.gd")
	var rd: Dictionary = load("res://hk/world_data.gd").load_all()["cat_3"].duplicate()
	rd["id"] = "cat_3"   # menu._draw_map đặt id trước khi gọi map_icons
	var has_cache := func(ic: Array) -> bool:
		for i in ic:
			if i["k"] == "cache":
				return true
		return false
	ck(not has_cache.call(Menu.map_icons(rd)), "hốc bí mật chưa mở: bản đồ không lộ rương")
	var crack_n: Node = get_nodes_in_group("hk_crack")[0]
	p.global_position = crack_n.global_position + Vector2(-400, 0)
	await frames(2)
	ck(crack_n._glow < 0.05, "xa vết nứt: không sáng (%f)" % crack_n._glow)
	p.global_position = crack_n.global_position + Vector2(-40, 0)
	await frames(2)
	ck(crack_n._glow > 0.3, "lại gần vết nứt: sáng lên (%f)" % crack_n._glow)
	p.global_position = Vector2(14.0 * 32.0 + 16.0, fy)
	p.velocity = Vector2.ZERO
	await frames(3)
	p.facing = 1
	p.attack_dir = Vector2.RIGHT
	p._hit_set.clear()
	p._attack_t = 0.3
	await frames(4)
	ck(St.flag("secret_cat_3"), "chém một nhát: tường vỡ, cờ đặt")
	await frames(2)
	ck(get_nodes_in_group("hk_crack").is_empty() and w.room.cracks.is_empty(), "cả cụm ô nứt biến mất")
	p.global_position = Vector2(18.0 * 32.0 + 16.0, fy)
	p.velocity = Vector2.ZERO
	await frames(10)
	ck(p.is_on_floor() and absf(p.global_position.x - (18.0 * 32.0 + 16.0)) < 4.0, "vào được hốc (x=%f)" % p.global_position.x)
	ck(has_cache.call(Menu.map_icons(rd)), "hốc đã mở: bản đồ hiện rương chưa nhặt")
	for ar in ["gate", "catacomb", "vault", "archive", "grove"]:
		ck(load("res://hk/lore.gd").secret_note(ar) != "", "có ghi chú hốc cho khu " + ar)
	var geo0: int = St.geo
	w._on_interacted("cache", {"key": "cat_3:18:17", "pos": Vector2(18.0 * 32.0 + 16.0, 18.0 * 32.0)})
	ck(St.shards == 1 and St.geo == geo0, "rương trong hốc bí mật cho 1 mảnh, không Geo (%d, %d)" % [St.shards, St.geo - geo0])
	w.load_room("cat_3")
	await frames(3)
	ck(w.room.cracks.is_empty() and get_nodes_in_group("hk_crack").is_empty(), "nạp lại phòng: tường vẫn mở")
	St.reset()
	w.load_room("cat_3")
	await frames(3)
	ck(w.room.cracks.size() == 2, "ván mới: tường nứt trở lại")
	print("hk_explore_test: ", "OK" if fails == 0 else "%d lỗi" % fails)
	print("DONE fails=", fails)
	quit(fails)
