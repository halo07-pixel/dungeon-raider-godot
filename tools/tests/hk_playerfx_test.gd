extends SceneTree
## Hiệu ứng tương tác với người chơi: FX.puff (tắt theo Atmosphere, có trần, tự dọn), player phát fx(run|land|wall|dash),
## nước bắn khi vào/ra vùng nước, đèn vật tương tác sáng dần khi lại gần, đèn người chơi theo tâm trạng, trang trí lắc khi chạy qua.
var fails: int = 0
var got: Array = []

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout

func puffs(n: Node) -> int:
	var c: int = 0
	for ch in n.get_children():
		if ch is CPUParticles2D:
			c += 1
	return c

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	var FX = load("res://hk/fx.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_playerfx_save.json"
	St.delete_save()
	St.atmosphere_on = true
	# FX.puff: tạo, tắt theo Atmosphere, trần, tự dọn
	var holder := Node2D.new()
	root.add_child(holder)
	ck(FX.puff(holder, Vector2.ZERO, 3, Color.WHITE) != null, "puff tạo hạt khi Atmosphere bật")
	St.atmosphere_on = false
	ck(FX.puff(holder, Vector2.ZERO, 3, Color.WHITE) == null, "Atmosphere tắt -> không tạo")
	St.atmosphere_on = true
	for i in 40:
		FX.puff(holder, Vector2.ZERO, 2, Color.WHITE)
	ck(puffs(holder) <= FX.MAX_LIVE, "có trần số cụm (%d)" % puffs(holder))
	ck(FX.puff(holder, Vector2.ZERO, 2, Color.WHITE) == null, "đủ trần thì không tạo thêm")
	await wait(1.2)
	ck(puffs(holder) == 0 and FX._live == 0, "hạt tự dọn, bộ đếm về 0 (%d)" % FX._live)
	# bộ đếm đúng cả khi cha bị giải phóng giữa chừng
	var h2 := Node2D.new()
	root.add_child(h2)
	for i in 5:
		FX.puff(h2, Vector2.ZERO, 2, Color.WHITE)
	h2.queue_free()
	await wait(0.2)
	ck(FX._live == 0, "cha bị free: bộ đếm vẫn về 0 (%d)" % FX._live)
	holder.queue_free()
	# world thật
	for a in ["dash", "double_jump", "wall_cling"]:
		St.give_ability(a)
	var w := Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	await wait(0.6)
	w.player.fx.connect(func(k: String, p: Vector2, pw: float): got.append([k, pw]))
	var base_n: int = puffs(w._content)
	w._on_player_fx("land", Vector2(100, 100), 0.0)
	var n_small: int = puffs(w._content) - base_n
	await wait(1.0)
	w._on_player_fx("land", Vector2(100, 100), 1.0)
	var big: CPUParticles2D = null
	for ch in w._content.get_children():
		if ch is CPUParticles2D:
			big = ch
	ck(n_small == 1 and big != null and big.amount > 3 + 0, "đáp mạnh bụi nhiều hơn (amount=%d)" % (big.amount if big else -1))
	await wait(1.0)
	# player phát tín hiệu thật: đáp đất, chạy, dash
	w.player.global_position = w.room.default_spawn()
	await wait(0.5)
	ck(w.player.is_on_floor(), "người chơi đứng trên sàn")
	got.clear()
	w.player._air_t = 0.5
	w.player._track_air(0.01)
	ck(got.size() == 1 and got[0][0] == "land" and got[0][1] > 0.4, "đáp đất sau khi rơi lâu phát land (%s)" % str(got))
	got.clear()
	w.player._air_t = 0.05
	w.player._track_air(0.01)
	ck(got.is_empty(), "nhảy thấp không phát land")
	w.player.velocity.x = w.player.RUN_SPEED
	w.player._step_t = 0.0
	w.player._track_air(0.01)
	ck(got.size() == 1 and got[0][0] == "run", "chạy phát run")
	w.player._track_air(0.01)
	ck(got.size() == 1, "bụi chân có nhịp, không phát mỗi khung")
	got.clear()
	w.player.velocity = Vector2.ZERO
	w.player._dash_cd = 0.0
	w.player.can_dash = true
	var ev := InputEventAction.new()
	ev.action = "hk_dash"
	ev.pressed = true
	Input.parse_input_event(ev)
	await wait(0.15)
	ev.pressed = false
	Input.parse_input_event(ev)
	ck(got.any(func(g): return g[0] == "dash"), "dash phát dash (%s)" % str(got))
	await wait(1.0)
	# nước: vào -> bắn, ra -> bắn
	var z := Node2D.new()
	z.set_script(load("res://hk/zone.gd"))
	z.kind = "water"
	z.rect = Rect2(w.player.global_position + Vector2(-60, -40), Vector2(120, 100))
	z.life = 20.0
	z.fx_parent = w._content
	w._content.add_child(z)
	var tries: int = 0
	while not z._in_water and tries < 120:
		await process_frame
		tries += 1
	ck(z._in_water, "người chơi trong nước")
	ck(puffs(w._content) >= 1, "vào nước có hạt (%d)" % puffs(w._content))
	await wait(1.0)
	w.player.global_position += Vector2(600, 0)
	tries = 0
	while z._in_water and tries < 120:
		await process_frame
		tries += 1
	ck(not z._in_water, "rời nước")
	ck(puffs(w._content) >= 1, "ra khỏi nước có hạt")
	z.queue_free()
	await wait(1.0)
	# đèn vật tương tác + tâm trạng
	w.busy = false
	w.load_room("gate_8")
	await process_frame
	var at: Node2D = w.atmosphere
	var bench_light: Dictionary = {}
	for it in at._lights:
		if not it["flicker"]:
			bench_light = it
	ck(not bench_light.is_empty(), "gate_8 có đèn bench")
	w.player.respawn_at(w.room.bench_spawn())
	await wait(0.4)
	var near_e: float = bench_light["l"].energy
	w.player.respawn_at(w.room.bench_spawn() + Vector2(-700, 0))
	await wait(0.4)
	var far_e: float = bench_light["l"].energy
	ck(near_e > far_e * 1.5 and absf(far_e - float(bench_light["base"])) < 0.01, "đèn bench sáng khi lại gần (%.2f vs %.2f)" % [near_e, far_e])
	w.player.hp = 1   # world đọc trạng thái người chơi mỗi khung rồi gọi set_mood
	await wait(0.3)
	ck(at._mood == "danger" and at._player_light.color.g < 0.6, "còn 1 mặt nạ: đèn người chơi ngả đỏ")
	w.player.hp = w.player.max_hp
	w.player.focusing = true
	w._process(0.0)   # tránh khung vật lý của người chơi đặt lại focusing trước khi world đọc
	ck(at._mood == "focus", "Focus: tâm trạng focus (%s)" % at._mood)
	w.player.focusing = false
	await wait(0.3)
	ck(at._mood == "" and absf(at._player_light.energy - 0.5) < 0.01, "bình thường: đèn về mặc định")
	# trang trí lắc khi chạy qua gần
	var dec = load("res://hk/decor.gd").new()
	var foot := Vector2(200, 200)
	var mx: float = 0.0
	for i in 60:
		await process_frame
		mx = maxf(mx, absf(dec.sway(foot, foot + Vector2(20, 0), 300.0)))
	ck(mx > 0.5 and mx <= dec.SWAY_MAX + 0.001, "chạy gần: lắc trong (0, %.1f] (%.2f)" % [dec.SWAY_MAX, mx])
	ck(dec.sway(foot, foot + Vector2(20, 0), 0.0) == 0.0, "đứng yên không lắc")
	ck(dec.sway(foot, foot + Vector2(500, 0), 300.0) == 0.0, "ở xa không lắc")
	dec.free()
	St.delete_save()
	print("hk_playerfx_test: ", "OK" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails > 0 else 0)
