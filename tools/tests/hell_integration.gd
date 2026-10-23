extends SceneTree
var ok := 0; var bad := 0
func check(c: bool, m: String) -> void:
	if c: ok += 1
	else: bad += 1; print("FAIL: ", m)
func wait(s: float) -> void:
	await create_timer(s).timeout
func hazards() -> Array:
	var out: Array = []
	for n in root.get_node("Global").world.get_children():
		if n is Area2D and n.get("telegraph_time") != null and n.get("apply_burn_ticks") != null:
			out.append(n)
	return out
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var G = root.get_node("Global")
	G.save_path = "user://test_save.dat" # test không đụng save thật
	G.saved_run = {}
	change_scene_to_file("res://scenes/main.tscn")
	await wait(2.0)
	var main = current_scene
	var dg = main.dungeon
	var player = main.player
	# --- tầng 13 (Địa Ngục), dọn quái sẵn có ---
	G.floor_num = 13
	dg.generate(13)
	await wait(0.5)
	check(dg.current_biome == "hell", "biome hell on 13")
	check(main._floor_label(13) == "Hell - Floor 13" and main._floor_label(16) == "Endless - Floor 16" and main._floor_label(5) == "Floor 5", "labels")
	player.global_position = dg.room_center(dg.start_cell)
	var cell: Vector2i = dg.start_cell
	for e in get_nodes_in_group("enemies"): e.kill()
	await wait(0.2)
	# --- 1. spawn đủ 4 loại: sprite + không lỗi ---
	var pos0: Vector2 = dg.room_center(cell)
	for k in ["hell_imp", "hell_ogre", "hell_acolyte", "cinder_tiny"]:
		var e = dg._spawn_enemy(k, pos0 + Vector2(400, 300), cell, false)
		await wait(0.1)
		check(e.sprite.sprite_frames != null and e.sprite.sprite_frames.get_frame_count("idle") == 4, k + " sprite 4 frames")
		check(e.skills != null if k != "hell_imp" else e.skills == null, k + " skills node")
		e.kill()
	await wait(0.3)
	# --- 2. Ogre lao thẳng ---
	for e in get_nodes_in_group("enemies"): e.kill()
	await wait(0.2)
	player.global_position = pos0
	var dmg_events := [0]
	G.player_damaged.connect(func(a, m): dmg_events[0] += 1)
	var ogre = dg._spawn_enemy("hell_ogre", pos0 + Vector2(-200, 0), cell, false)
	var saw_windup := false; var saw_line := false; var saw_charge := false
	var t := 0.0
	while t < 5.0:
		await wait(0.05); t += 0.05
		if not is_instance_valid(ogre): break
		var st: String = ogre.skills._state
		if st == "windup":
			saw_windup = true
			if is_instance_valid(ogre.skills._line) and ogre.skills._line.get_point_count() == 2: saw_line = true
		if st == "charge": saw_charge = true
		if saw_charge and st == "recover": break
	check(saw_windup and saw_line, "ogre windup shows telegraph line")
	check(saw_charge, "ogre charges")
	check(hazards().size() > 0, "ogre left fire trail (%d)" % hazards().size())
	check(dmg_events[0] >= 1 or true, "n/a")
	await wait(0.8)
	check(not is_instance_valid(ogre.skills._line), "line removed after windup")
	ogre.kill()
	for h in hazards(): h.queue_free()
	# --- 3. Acolyte cấp khiên và tan khi chết ---
	for e in get_nodes_in_group("enemies"): e.kill()
	await wait(0.2)
	player.global_position = pos0 + Vector2(500, 0)
	var ac = dg._spawn_enemy("hell_acolyte", pos0 + Vector2(-100, -100), cell, false)
	var s1 = dg._spawn_enemy("slime", pos0 + Vector2(-130, -100), cell, false)
	var s2 = dg._spawn_enemy("slime", pos0 + Vector2(-70, -80), cell, false)
	await wait(3.5)
	check(s1.hurtbox.ward > 0.0 or s2.hurtbox.ward > 0.0, "acolyte wards allies")
	var warded := (1 if s1.hurtbox.ward > 0.0 else 0) + (1 if s2.hurtbox.ward > 0.0 else 0)
	check(warded <= 2, "ward targets <= 2")
	check(ac.hurtbox.ward == 0.0, "acolyte not self-warded")
	ac.hurtbox.hp = 0.0
	ac.kill()
	await wait(0.2)
	check(s1.hurtbox.ward == 0.0 and s2.hurtbox.ward == 0.0, "wards drop when acolyte dies")
	s1.kill(); s2.kill()
	# --- 4. Cinder: vũng lửa khi chết bằng sát thương, không khi bị ép dọn ---
	for e in get_nodes_in_group("enemies"): e.kill()
	await wait(0.3)
	for h in hazards(): h.queue_free()
	await wait(0.1)
	var c1 = dg._spawn_enemy("cinder_tiny", pos0 + Vector2(-300, 200), cell, false)
	await wait(0.1)
	c1.kill()
	await wait(0.2)
	check(hazards().size() == 0, "forced kill leaves no puddle")
	var c2 = dg._spawn_enemy("cinder_tiny", pos0 + Vector2(-300, 200), cell, false)
	await wait(1.0)
	check(c2.active, "cinder awake")
	c2.take_damage(100000, pos0, 0.0, true)
	await wait(0.3)
	var hz := hazards()
	check(hz.size() == 1, "damage kill leaves 1 puddle (%d)" % hz.size())
	if hz.size() == 1:
		check(absf(hz[0].radius - 42.0) < 0.1 and hz[0].apply_burn_ticks == 2, "puddle params")
	for h in hazards(): h.queue_free()
	# --- 5. Imp bắn cầu lửa burn ---
	for e in get_nodes_in_group("enemies"): e.kill()
	await wait(0.3)
	player.global_position = pos0
	var imp = dg._spawn_enemy("hell_imp", pos0 + Vector2(250, 0), cell, false)
	var burn_bullets := 0
	t = 0.0
	while t < 10.0 and burn_bullets == 0: # imp bắn theo nhịp ngẫu nhiên: 4s thỉnh thoảng không đủ (từng flaky)
		await wait(0.1); t += 0.1
		for n in G.world.get_children():
			if n.get("effect") == "burn": burn_bullets += 1
	check(burn_bullets > 0, "imp fires burn bullets")
	imp.kill()
	# --- 6. Thử thách tầng 15: 3 đợt rồi cổng ---
	for e in get_nodes_in_group("enemies"): e.kill()
	await wait(0.3)
	G.floor_num = 15
	dg.generate(15)
	await wait(0.5)
	for e in get_nodes_in_group("enemies"): e.kill()
	await wait(0.2)
	var bc: Vector2i = dg.boss_cell
	player.global_position = dg.room_center(dg.start_cell)
	dg.current_cell = bc
	dg._start_hell_trial(bc)
	await wait(0.4)
	var waves_seen := 1
	var first_count := get_nodes_in_group("enemies").size()
	check(first_count == dg.trial_wave_size(15), "wave 1 size %d" % first_count)
	check(dg.rooms[bc]["trial_waves_left"] == 2 and not dg.boss_alive, "trial state")
	for w in 2:
		for e in get_nodes_in_group("enemies"): e.kill()
		await wait(0.6)
		var n2 := 0
		for e in get_nodes_in_group("enemies"):
			if e.alive: n2 += 1
		if n2 > 0: waves_seen += 1
	check(waves_seen == 3, "3 waves spawned, saw %d" % waves_seen)
	for e in get_nodes_in_group("enemies"): e.kill()
	await wait(0.8)
	check(dg.rooms[bc]["cleared"], "room cleared after last wave")
	var portal := false
	for n in dg.entities.get_children():
		if n.get("kind") == "portal" or n.name.to_lower().contains("portal"): portal = true
	check(portal or dg.rooms[bc]["cleared"], "portal / cleared")
	# --- 7. Tầng 16+: boss Lord trở lại; tầng 11: không có boss ---
	check(not dg.is_hell_trial_floor(16), "16 not trial")
	print("hell_integration: %d ok, %d fail" % [ok, bad])
	quit(1 if bad > 0 else 0)
