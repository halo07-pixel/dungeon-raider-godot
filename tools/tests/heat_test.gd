extends SceneTree
var ok := 0; var bad := 0
func check(c: bool, m: String) -> void:
	if c: ok += 1
	else: bad += 1; print("FAIL: ", m)
func wait(s: float) -> void:
	await create_timer(s).timeout
func _init() -> void:
	call_deferred("_run")
func find_cb(n: Node, txt: String) -> Node:
	if n is CheckButton and n.text.begins_with(txt): return n
	for c in n.get_children():
		var r = find_cb(c, txt)
		if r != null: return r
	return null
func _run() -> void:
	var G = root.get_node("Global")
	G.save_path = "user://test_save.dat" # test không đụng save thật
	var H = load("res://scripts/heat.gd")
	var AF = load("res://scripts/enemy_affix.gd")
	# --- dữ liệu ---
	check(H.ORDER.size() == H.MODS.size(), "order covers mods")
	for id in H.ORDER: check(H.MODS.has(id) and int(H.MODS[id]["cost"]) > 0 and String(H.MODS[id]["desc"]) != "", "mod " + id)
	check(H.total([]) == 0 and H.total(["swift", "glass", "bogus"]) == 3, "total")
	check(absf(H.gem_mult(["glass", "furious"]) - 1.6) < 0.001, "gem mult")
	check(H.gems(5, []) == 5 and H.gems(5, ["glass", "furious"]) == 8 and H.gems(0, ["glass"]) == 0, "gems")
	check(H.sanitize(["glass", "x", "swift"]) == ["swift", "glass"], "sanitize order")
	# --- Global ---
	G.run_heat = []
	var base: float = G.enemy_dmg_mult_for_floor(5)
	G.run_heat = ["glass"]
	check(absf(G.enemy_dmg_mult_for_floor(5) - base * H.PLAYER_DAMAGE_MULT) < 0.0001, "glass mult")
	G.run_heat = []
	check(G.heat_points() == 0 and G.heat_gems(7) == 7, "no heat no change")
	G.heat_selected = {"swift": true, "reinforce": true}
	G.reset_run()
	check(G.run_heat == ["swift", "reinforce"], "reset_run snapshots selection (%s)" % [G.run_heat])
	G.heat_selected.erase("swift")
	check(G.run_heat == ["swift", "reinforce"], "run_heat frozen")
	# --- affix ---
	G.run_heat = []
	var n0 := 0; var n1 := 0
	for i in 4000: if AF.roll("hell_ogre", 12) != "": n0 += 1
	G.run_heat = ["elite_pack"]
	for i in 4000: if AF.roll("hell_ogre", 12) != "": n1 += 1
	check(n1 > n0 + 500, "elite_pack raises affix rate (%d -> %d)" % [n0, n1])
	var f1 := 0
	for i in 500: if AF.roll("slime", 1) != "": f1 += 1
	check(f1 == 0, "floor 1 stays affix-free")
	check(AF.max_per_room() == AF.MAX_PER_ROOM + 1, "max per room +1")
	G.run_heat = []
	check(AF.max_per_room() == AF.MAX_PER_ROOM, "max per room base")
	# --- save/load ---
	G.heat_selected = {"glass": true, "furious": true}
	G.save_game()
	G.heat_selected = {}
	G.load_game()
	check(G.selected_heat_ids() == ["furious", "glass"], "save roundtrip (%s)" % [G.selected_heat_ids()])
	# --- menu ---
	G.heat_selected = {}
	change_scene_to_file("res://scenes/main_menu.tscn")
	await wait(1.5)
	var m = current_scene
	m.show_class_menu()
	await wait(0.3)
	var cb = find_cb(m, "Swift Foes")
	check(cb != null, "menu has Swift Foes toggle")
	if cb != null:
		cb.button_pressed = true
		await wait(0.1)
		check(G.heat_selected.has("swift"), "toggle on selects")
		check(m.heat_summary.text.contains("+15%"), "summary %s" % m.heat_summary.text)
		cb.button_pressed = false
		await wait(0.1)
		check(not G.heat_selected.has("swift") and m.heat_summary.text.contains("normal"), "toggle off")
	# --- in-game ---
	G.saved_run = {}
	G.heat_selected = {}
	change_scene_to_file("res://scenes/main.tscn")
	await wait(2.0)
	var main = current_scene; var dg = main.dungeon
	G.run_heat = []
	var BOSS = load("res://scenes/boss.tscn")
	var b0 = BOSS.instantiate(); b0.setup(1.0, "warden")
	check(b0.phase == 1, "boss phase 1 without heat")
	G.run_heat = ["furious"]
	var b1 = BOSS.instantiate(); b1.setup(1.0, "warden")
	var b2 = BOSS.instantiate(); b2.setup(1.0, "lord")
	check(b1.phase == 2 and b2.phase == 2 and b1.pending_roar, "furious: boss starts phase 2")
	b0.free(); b1.free(); b2.free()
	# swift
	G.run_heat = []
	var en = dg._spawn_enemy("slime", dg.room_center(dg.start_cell) + Vector2(300, 0), dg.start_cell, false)
	check(en._heat_speed() == 1.0, "speed base")
	G.run_heat = ["swift"]
	check(absf(en._heat_speed() - 1.15) < 0.001, "swift speed")
	en.kill()
	# reinforce
	G.run_heat = ["reinforce"]
	G.floor_num = 3
	dg.generate(3)
	await wait(0.5)
	for e in get_nodes_in_group("enemies"): e.kill()
	var cell := Vector2i(-1, -1)
	for c in dg.rooms:
		if dg.rooms[c]["type"] == "normal": cell = c
	check(cell != Vector2i(-1, -1), "found normal room")
	main.player.hurt_timer.start(900.0)
	main.player.global_position = dg.room_center(cell)
	dg.current_cell = cell
	dg.rooms[cell]["visited"] = true
	dg._spawn_wave(cell, 3)
	await wait(0.3)
	for e in get_nodes_in_group("enemies"): e.kill()
	await wait(0.8)
	var second := 0
	for e in get_nodes_in_group("enemies"):
		if e.alive: second += 1
	check(dg.rooms[cell].get("reinforced", false) and second >= 2, "reinforcement wave spawned (%d)" % second)
	check(not dg.rooms[cell]["cleared"], "room not cleared during reinforcement")
	for e in get_nodes_in_group("enemies"): e.kill()
	await wait(0.8)
	var third := 0
	for e in get_nodes_in_group("enemies"):
		if e.alive: third += 1
	check(third == 0 and dg.rooms[cell]["cleared"], "cleared after second wave, no third (%d)" % third)
	# no heat: single wave
	G.run_heat = []
	dg.generate(3)
	await wait(0.5)
	for e in get_nodes_in_group("enemies"): e.kill()
	for c in dg.rooms:
		if dg.rooms[c]["type"] == "normal": cell = c
	main.player.global_position = dg.room_center(cell)
	dg.current_cell = cell
	dg._spawn_wave(cell, 3)
	await wait(0.3)
	for e in get_nodes_in_group("enemies"): e.kill()
	await wait(0.8)
	check(dg.rooms[cell]["cleared"] and not dg.rooms[cell].get("reinforced", false), "no heat: cleared after one wave")
	# telemetry entry carries heat
	G.run_heat = ["glass", "swift"]
	G.profile["history"] = []
	main.telemetry.finish_run(false)
	check(G.profile["history"].size() == 1 and int(G.profile["history"][0].get("heat", -1)) == 3, "history entry has heat")
	# saved run carries heat
	G.run_heat = ["swift"]
	check(main._build_saved_run()["heat"] == ["swift"], "saved_run heat")
	print("heat_test: %d ok, %d fail" % [ok, bad])
	quit(1 if bad > 0 else 0)
