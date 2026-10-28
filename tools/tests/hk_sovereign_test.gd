extends SceneTree
## Test boss bí mật many_faced: đổi dạng (hộp/va chạm theo dạng, không lặp liền, báo trước không nhận đòn), 3 pha, dạng thật pha 3,
## chiến thắng đặt cờ + ending bí mật; cánh cửa tới phòng boss bị khoá cho đến khi đủ 6 ký ức.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func tick() -> void:
	Engine.time_scale = 4.0   # hitstop/reset đặt lại time_scale: ép lại mỗi khung
	await physics_frame

func frames(n: int) -> void:
	for i in n:
		await tick()

func _init() -> void:
	await process_frame
	Engine.max_physics_steps_per_frame = 16
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	var B = load("res://hk/boss.gd")
	var L = load("res://hk/lore.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_sovereign_save.json"
	St.delete_save()
	var room := Node2D.new()
	room.set_script(load("res://hk/room.gd"))
	root.add_child(room)
	var grid: Array = []
	for r in 24:
		grid.append("#".repeat(60) if r == 23 else "#" + ".".repeat(58) + "#")
	room.build("test", {"area": "vault", "doors": {}, "grid": grid})
	var p := CharacterBody2D.new()
	p.set_script(load("res://hk/player.gd"))
	p.position = Vector2(300, 700)
	root.add_child(p)
	p.invuln = 999.0
	await frames(20)
	var b := CharacterBody2D.new()
	b.set_script(load("res://hk/boss.gd"))
	b.kind = "many_faced"
	b.position = Vector2(1200, 640)
	root.add_child(b)
	b.arena = room.bounds()
	var defeated: Array = [false]
	b.defeated.connect(func(): defeated[0] = true)
	ck(b.max_hp == 480 and b.title() == "The Many-Faced" and b.form == "warden", "khởi đầu: 480 HP, dạng warden")
	p.global_position = Vector2(900, 700)
	await frames(80)
	ck(b.state != "dormant", "vào trận khi lại gần (%s)" % b.state)
	print("[phase1]")
	# ---- đổi dạng pha 1: chỉ trong SHIFT_P1, không lặp liền, hộp + va chạm theo dạng
	var seen: Dictionary = {}
	var last: String = b.form
	var repeat_bad: bool = false
	var size_bad: bool = false
	var mask_bad: bool = false
	for i in 8:
		b._form_t = 0.0
		var f0: int = Engine.get_physics_frames()
		while Engine.get_physics_frames() - f0 < 900 and b.state != "wind_shift":
			await tick()
			b._form_t = 0.0
		ck(b.state == "wind_shift", "pha 1: báo trước đổi dạng (%s)" % b.state)
		var hp0: int = b.hp
		b.take_hit(3, p.global_position)
		ck(b.hp == hp0, "đang báo trước đổi dạng: không nhận đòn")
		f0 = Engine.get_physics_frames()
		while Engine.get_physics_frames() - f0 < 200 and b.state == "wind_shift":
			await tick()
		await tick()
		await tick()
		seen[b.form] = true
		if b.form == last:
			repeat_bad = true
		last = b.form
		if not b._size.is_equal_approx(B.body_size(b.form)) or not is_equal_approx(b._shape.size.x, b._size.x):
			size_bad = true
		if (b.collision_mask == 0) != (b.form in B.FLYERS):
			mask_bad = true
		b._form_t = 99.0
		await frames(30)
	ck(not repeat_bad, "không đổi sang đúng dạng đang có")
	ck(not size_bad, "hộp và hình va chạm khớp dạng mới")
	ck(not mask_bad, "dạng bay không va sàn, dạng đi bộ có")
	for f in seen:
		ck(f in B.SHIFT_P1, "pha 1 chỉ dùng dạng %s trong danh sách P1" % f)
	ck(seen.size() >= 2, "pha 1: có đổi qua nhiều dạng (%s)" % str(seen.keys()))
	print("[phase2]")
	# ---- pha 2 (66%)
	b.take_hit(b.hp - (b.max_hp * 2 / 3), p.global_position)
	await frames(2)
	b.take_hit(1, p.global_position)
	b.hp = b.max_hp * 2 / 3 - 1
	b.state = "walk"
	b.take_hit(1, p.global_position)
	ck(b.phase == 2, "pha 2 khi còn dưới 66%% máu (phase=%d hp=%d)" % [b.phase, b.hp])
	await frames(60)
	var seen2: Dictionary = {}
	for i in 14:
		b._form_t = 0.0
		var f1: int = Engine.get_physics_frames()
		while Engine.get_physics_frames() - f1 < 900 and b.state != "wind_shift":
			await tick()
			b._form_t = 0.0
		var f2: int = Engine.get_physics_frames()
		while Engine.get_physics_frames() - f2 < 200 and b.state == "wind_shift":
			await tick()
		await tick()
		seen2[b.form] = true
		b._form_t = 99.0
		await frames(20)
	ck(seen2.has("colossus") or seen2.has("lord"), "pha 2: có thêm dạng colossus/lord (%s)" % str(seen2.keys()))
	print("[phase3]")
	# ---- pha 3: dạng thật, không đổi dạng nữa
	b.hp = b.max_hp / 3 + 1
	b.state = "walk"
	b.take_hit(1, p.global_position)
	ck(b.phase == 3 and b.form == "sovereign", "pha 3: dạng thật sovereign (phase=%d form=%s)" % [b.phase, b.form])
	await frames(60)
	ck(b._size.is_equal_approx(B.body_size("sovereign")) and b.collision_mask == 1, "dạng thật: hộp riêng, đi bộ")
	b._form_t = 0.0
	await frames(300)
	ck(b.form == "sovereign" and b.state != "wind_shift", "pha 3: không đổi dạng nữa")
	# đòn lai của pha >= 2: bắn quạt từ dạng đi bộ
	var saw_bolt: bool = false
	var f3: int = Engine.get_physics_frames()
	while Engine.get_physics_frames() - f3 < 1800 and is_instance_valid(b):
		await tick()
		if b.state == "wind_bolt":
			saw_bolt = true
			break
	ck(saw_bolt, "dạng thật dùng đòn lai (bắn quạt)")
	print("[defeat]")
	# ---- hạ
	if is_instance_valid(b):
		b.state = "walk"
		b.take_hit(b.hp, p.global_position)
	await frames(3)
	ck(defeated[0], "hạ được và phát tín hiệu defeated")
	# ---- phòng + cửa
	var WD = load("res://hk/world_data.gd")
	var rooms: Dictionary = WD.load_all()
	ck(rooms.has("sov_1") and rooms["sov_1"]["boss"]["id"] == "many_faced", "có phòng boss bí mật")
	ck(rooms["vault_7"]["doors"]["2"].get("needs", "") == "sovereign_open" and rooms["vault_7"]["doors"]["2"]["to"] == "sov_1", "cửa vault_7 -> sov_1 cần sovereign_open")
	ck(rooms["sov_1"]["doors"]["1"]["to"] == "vault_7", "cửa về")
	Engine.time_scale = 1.0
	# thế giới thật: cửa khoá khi thiếu ký ức, mở khi đủ
	St.reset()
	St.bench_room = "vault_7"
	var w := Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	await create_timer(0.4).timeout
	w._on_door("2")
	await create_timer(0.5).timeout
	ck(w.room.id == "vault_7" and w.hud.banner_text == "Sealed", "thiếu ký ức: cửa bị niêm phong")
	ck(not St.flag("sovereign_open"), "chưa đủ ký ức: chưa có cờ mở")
	for m in L.MEMORIES:
		St.set_flag("boss_" + String(m["id"]))
	w._on_door("2")
	await create_timer(1.0).timeout
	ck(St.flag("sovereign_open") and w.room.id == "sov_1", "đủ 6 ký ức: vào được phòng boss bí mật (%s)" % w.room.id)
	await create_timer(0.3).timeout
	# hạ boss bí mật trong world: cờ + ending bí mật
	var ended: Array = [false]
	w.ending_reached.connect(func(): ended[0] = true)
	w._on_boss_defeated("many_faced")
	ck(St.flag("boss_many_faced") and St.flag("ending_true"), "hạ boss bí mật đặt cờ ending_true")
	ck(w.hud.banner_sub == L.line("many_faced", "memory"), "banner câu cuối")
	await create_timer(3.4).timeout
	ck(ended[0], "phát ending_reached")
	ck(L.ending_lines() == L.ENDING_TRUE, "ending bí mật")
	Engine.time_scale = 1.0
	St.delete_save()
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
