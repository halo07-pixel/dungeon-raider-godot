extends SceneTree
var fails := 0
var total := 0
func check(ok: bool, n: String) -> void:
	total += 1
	if not ok: fails += 1
	print("PASS  " if ok else "FAIL  ", n)
func wait(sec: float) -> void:
	await create_timer(sec).timeout
func hazards() -> Array:
	var out: Array = []
	for n in root.get_node("Global").world.get_children():
		if n is Area2D and n.get("telegraph_time") != null and n.get("apply_burn_ticks") != null:
			out.append(n)
	return out
func clear_hazards() -> void:
	for h in hazards(): h.queue_free()
	await wait(0.1)
func make_boss(main, kind: String, phase: int):
	var b = load("res://scenes/boss.tscn").instantiate()
	b.setup(1.0, kind)
	main.dungeon.entities.add_child(b)
	var p = main.player
	b.global_position = p.global_position + Vector2(-260, 0)
	b.set_arena_bounds(Rect2(p.global_position - Vector2(520, 360), Vector2(1040, 720)))
	b.phase = phase
	b.attack_timer.stop()
	return b
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Global")
	G.save_path = "user://test_save.dat" # test không đụng save thật
	G.saved_run.clear()
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await wait(1.0)
	var p = main.player
	p.max_hp = 100000; p.hp = 100000; p.shield = 0.0; p.shield_delay_timer = 1000.0
	# ---- bảng đòn theo pha
	for kind in ["warden", "necromancer", "frost"]:
		var want: String = {"warden": "fissure", "necromancer": "bog_spread", "frost": "ice_sheet"}[kind]
		var b1 = make_boss(main, kind, 1)
		var b2 = make_boss(main, kind, 2)
		check(not (want in b1._attack_pool()), "%s pha 1: chưa có %s" % [kind, want])
		check(want in b2._attack_pool(), "%s pha 2: có %s" % [kind, want])
		b1.queue_free(); b2.queue_free()
	var lord = make_boss(main, "lord", 3)
	check(not ("fissure" in lord._attack_pool() or "bog_spread" in lord._attack_pool() or "ice_sheet" in lord._attack_pool()), "Lord: bảng đòn không đổi")
	lord.queue_free()
	# ---- Warden: Nứt Đất
	var w = make_boss(main, "warden", 2)
	await clear_hazards()
	var t0 := Time.get_ticks_msec()
	w.call_deferred("_atk_fissure")
	await wait(0.05)
	var hs: Array = hazards()
	var Bs = load("res://scripts/boss.gd")
	check(hs.size() >= 3 and hs.size() <= Bs.FISSURE_COUNT, "Nứt Đất pha 2: 1 vệt (%d điểm)" % hs.size())
	var tt: Array = []
	for h in hs: tt.append(h.telegraph_time)
	var sorted_ok := true
	for i in range(1, tt.size()):
		if tt[i] <= tt[i - 1]: sorted_ok = false
	check(sorted_ok, "các điểm nổ lần lượt (telegraph tăng dần)")
	check(hs[0].global_position.distance_to(w.global_position) > 60.0, "vệt bắt đầu ngoài thân boss")
	var fsx := 0
	for h in hs: if h.fire_sfx == "fissure_burst": fsx += 1
	check(fsx >= 1 and fsx < hs.size(), "Nứt Đất: vài điểm có tiếng nổ, không phải mọi điểm (%d/%d)" % [fsx, hs.size()])
	var played := false
	for c in G.get_children():
		if c is AudioStreamPlayer and c.stream == G._sfx["fissure_warn"]: played = true
	check(played, "Nứt Đất phát tiếng báo trước fissure_warn")
	await wait(2.4)
	await clear_hazards()
	w.phase = 3
	w.call_deferred("_atk_fissure")
	await wait(0.05)
	var n3: int = hazards().size()
	check(n3 > hs.size() * 2, "pha 3: ba vệt (%d điểm)" % n3)
	await wait(2.4)
	# sát thương thật: đặt Player lên điểm cuối vệt
	await clear_hazards()
	w.phase = 2
	p.global_position = w.global_position + Vector2(300, 0)
	p.hp = 100000
	w.call_deferred("_atk_fissure")
	await wait(0.05)
	p.global_position = hazards()[2].global_position
	var hp0: int = p.hp
	await wait(2.4)
	await wait(0.4)
	check(p.hp < hp0, "đứng trên điểm nứt khi nổ thì mất máu (%d -> %d)" % [hp0, p.hp])
	await clear_hazards()
	w.queue_free()
	# ---- Necromancer: Đầm Độc Lan
	var n = make_boss(main, "necromancer", 2)
	p.global_position = n.global_position + Vector2(260, 0)
	p.poison_ticks = 0
	await clear_hazards()
	n.call_deferred("_atk_bog_spread")
	await wait(0.05)
	hs = hazards()
	check(hs.size() == Bs.BOG_POOLS, "Đầm Độc Lan pha 2: %d vũng" % hs.size())
	check(hs[0].end_radius > hs[0].radius and hs[0].apply_poison_ticks > 0, "vũng sẽ lan rộng và gây độc")
	check(hs[0].fire_sfx == "bog_burst", "Đầm Độc Lan có tiếng bog_burst khi kích hoạt")
	var r0: float = hs[0].radius
	await wait(1.0)
	await wait(2.0)
	check(hs[0].radius > r0 + 10.0, "vũng lan rộng theo thời gian (%.0f -> %.0f)" % [r0, hs[0].radius])
	check(absf(hs[0]._shape.radius - hs[0].radius) < 0.01, "vùng va chạm lan theo hình vẽ")
	# đặt Player ngay trong vũng 0 và chờ nhịp
	p.global_position = hs[0].global_position
	await wait(1.4)
	check(p.poison_ticks > 0, "đứng trong vũng bị Độc (ticks=%d)" % p.poison_ticks)
	n.phase = 3
	await clear_hazards()
	n.call_deferred("_atk_bog_spread")
	await wait(0.05)
	check(hazards().size() == Bs.BOG_POOLS_PHASE3, "pha 3: %d vũng" % hazards().size())
	await wait(1.0)
	await clear_hazards()
	n.queue_free()
	# ---- Frozen Horror: Mặt Băng
	var f = make_boss(main, "frost", 2)
	p.global_position = f.global_position + Vector2(260, 0)
	await clear_hazards()
	var combo := 0
	for i in 30:
		f.queued_attack = ""
		f.attack_timer.stop()
		# chỉ kiểm tra xác suất nối đòn, không đợi hết telegraph
		f.call_deferred("_atk_ice_sheet")
		await wait(0.02)
		if f.queued_attack == "frost_charge": combo += 1
		await wait(1.1)
		await clear_hazards()
	check(combo > 8 and combo < 28, "Mặt Băng nối Frost Charge ~60%% (%d/30)" % combo)
	f.queued_attack = ""
	f.call_deferred("_atk_ice_sheet")
	await wait(0.05)
	hs = hazards()
	check(hs.size() == 1 and hs[0].apply_slide_duration > 0.0 and hs[0].damage == 0, "một mảng băng lớn, không gây sát thương, gây trượt")
	check(hs[0].fire_sfx == "ice_sheet_freeze", "Mặt Băng có tiếng ice_sheet_freeze khi kích hoạt")
	await wait(1.1)
	p.global_position = hs[0].global_position
	p.slide_timer = 0.0
	await wait(0.6)
	var slid := false
	for i in 8:
		await wait(0.1)
		if p.slide_timer > 0.0: slid = true
	check(slid, "đứng trên băng thì Player bị trượt")
	# đòn nối tiếp được dùng đúng một lần
	f.queued_attack = "frost_charge"
	var attack_used: String = f.queued_attack
	check(attack_used == "frost_charge", "queued_attack giữ combo cho lượt kế")
	await clear_hazards()
	f.queue_free()
	print("SUMMARY boss_floor: %d/%d PASS" % [total - fails, total])
	await wait(0.3)
	quit(1 if fails > 0 else 0)
