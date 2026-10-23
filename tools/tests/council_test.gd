extends SceneTree
var ok := 0; var bad := 0
func check(c: bool, m: String) -> void:
	if c: ok += 1
	else: bad += 1; print("FAIL: ", m)
func wait(s: float) -> void:
	await create_timer(s).timeout
func keep_alive(pl) -> void:
	pl.hurt_timer.start(900.0)
	pl.hp = pl.max_hp
	pl.burn_ticks = 0
	pl.poison_ticks = 0
func _init() -> void:
	call_deferred("_run")
func find_hud(n: Node) -> Node:
	if n.get("_council_rows") != null: return n
	for c in n.get_children():
		var r = find_hud(c)
		if r != null: return r
	return null
func _run() -> void:
	var G = root.get_node("Global")
	G.save_path = "user://test_save.dat" # test không đụng save thật
	var BC = load("res://scripts/boss_council.gd")
	var DG = load("res://scripts/dungeon.gd")
	check(BC.tokens_for(0) == 2 and BC.tokens_for(1) == 3 and BC.tokens_for(2) == 4 and BC.tokens_for(3) == 4, "tokens_for")
	check(BC.KINDS == ["warden", "necromancer", "frost", "lord"], "kinds")
	var pts: Array = DG.council_spawn_points(Rect2(0, 0, 1000, 600))
	check(pts.size() == 4 and absf(pts[0].x - 300.0) < 0.1 and absf(pts[3].y - 420.0) < 0.1, "spawn points")
	G.saved_run = {}
	G.profile["council"] = 0
	G.purple_gems = 0
	change_scene_to_file("res://scenes/main.tscn")
	await wait(2.0)
	var main = current_scene
	var dg = main.dungeon
	var player = main.player
	var boss_def_count := [0]
	G.boss_defeated.connect(func(): boss_def_count[0] += 1)
	# --- A. tầng 15: sau Hell Trial xuất hiện cổng đỏ ---
	G.floor_num = 15
	dg.generate(15)
	await wait(0.5)
	for e in get_nodes_in_group("enemies"): e.kill()
	await wait(0.2)
	var bc: Vector2i = dg.boss_cell
	player.global_position = dg.room_center(dg.start_cell)
	player.hurt_timer.start(900.0)
	dg.current_cell = bc
	dg._start_hell_trial(bc)
	for w in 3:
		await wait(0.6)
		for e in get_nodes_in_group("enemies"): e.kill()
	await wait(1.0)
	var kinds_found := []
	for n in dg.entities.get_children():
		if n.get("kind") != null and (n.kind == "portal" or n.kind == "council_portal"): kinds_found.append(n.kind)
	check(kinds_found.has("portal") and kinds_found.has("council_portal"), "floor 15 spawns both portals: %s" % [kinds_found])
	# --- B. vào Council qua cổng ---
	G.council_portal_entered.emit()
	await wait(1.0)
	check(G.in_council and G.floor_num == 15, "in council, still floor 15")
	check(dg.rooms.size() == 2, "council floor layout (2 rooms)")
	bc = dg.boss_cell
	paused = false
	check(player.alive, "player alive entering council")
	keep_alive(player)
	dg.current_cell = bc
	player.global_position = dg.room_center(bc) + Vector2(0, 200)
	dg._enter_room(bc)
	await wait(0.5)
	var bosses: Array = get_nodes_in_group("boss")
	check(bosses.size() == 4, "4 bosses (%d)" % bosses.size())
	var ks := []
	for b in bosses: ks.append(b.kind)
	ks.sort()
	check(ks == ["frost", "lord", "necromancer", "warden"], "kinds %s" % [ks])
	var council = dg.entities.get_node_or_null("BossCouncil")
	check(council != null and council.bosses.size() == 4, "council node")
	var lord = null; var necro = null; var warden = null; var frost = null
	for b in bosses:
		match b.kind:
			"lord": lord = b
			"necromancer": necro = b
			"warden": warden = b
			"frost": frost = b
	var lord_base: float = float(load("res://scripts/boss.gd").BOSS_DATA["lord"]["base_hp"]) # đọc từ dữ liệu game, không gõ cứng (cân bằng đổi thì test không vỡ oan)
	var expect_lord: float = lord_base * BC.HP_MULT * G.hp_scale_for_floor(15) * G.endless_difficulty_mult(15)
	check(absf(lord.max_hp - expect_lord) < 1.0, "lord hp scaled %.0f vs %.0f" % [lord.max_hp, expect_lord])
	var hud = find_hud(main)
	check(hud != null and hud._council_rows.size() == 4, "HUD has 4 bars")
	# --- C. thẻ tấn công: tối đa 2 boss ra đòn cùng lúc ---
	var max_busy := 0; var max_tok := 0; var attackers := {}
	var t := 0.0
	while t < 18.0:
		await wait(0.1); t += 0.1
		keep_alive(player)
		var busy_n := 0
		for b in bosses:
			if b.busy:
				busy_n += 1
				attackers[b.kind] = true
		max_busy = maxi(max_busy, busy_n)
		max_tok = maxi(max_tok, council.tokens_in_use())
	check(max_busy <= 2, "max concurrent attackers <= 2 (was %d)" % max_busy)
	check(max_tok <= 2 and max_tok >= 1, "tokens in use <= 2 (was %d)" % max_tok)
	check(attackers.size() >= 3, "tokens rotate among bosses (%d distinct)" % attackers.size())
	# --- D. hồi sinh một lần ---
	keep_alive(player)
	warden.hp = 1.0
	warden.take_damage(100000)
	await wait(0.1)
	check(warden.alive and council.revive_used, "warden revived by necromancer")
	check(absf(warden.hp - warden.max_hp * BC.REVIVE_HP_FRACTION) < 2.0, "revive hp")
	check(warden.rebirth_left > 0.0, "rebirth invulnerable")
	var hp_before: float = warden.hp
	warden.take_damage(500)
	check(warden.hp == hp_before, "no damage during rebirth")
	await wait(1.8)
	check(warden.rebirth_left == 0.0, "rebirth over")
	# --- E. gục => nổi giận, thêm thẻ ---
	var ph_before := {"necromancer": necro.phase, "frost": frost.phase, "warden": warden.phase}
	lord.hp = 1.0
	lord.take_damage(100000)
	await wait(0.2)
	check(not lord.alive, "lord dies (revive used up)")
	check(council.max_tokens() == 3, "tokens grow to 3")
	var raged := 0
	for k in ph_before:
		var b = {"necromancer": necro, "frost": frost, "warden": warden}[k]
		if b.phase > ph_before[k] or b.phase == int(b.BOSS_DATA[b.kind]["phases"]): raged += 1
	check(raged == 3, "survivors enraged")
	check(boss_def_count[0] == 0, "no boss_defeated yet")
	check(G.profile["council"] == 0, "not cleared yet")
	# --- F. hạ nốt ---
	for b in [necro, frost, warden]:
		keep_alive(player)
		b.hp = 1.0
		b.take_damage(100000)
		await wait(0.3)
	await wait(1.5)
	check(boss_def_count[0] == 1, "boss_defeated exactly once (%d)" % boss_def_count[0])
	check(G.profile["council"] == 1, "council clear recorded")
	check(G.purple_gems >= DG.COUNCIL_GEMS, "gems rewarded")
	var weap := get_nodes_in_group("weapon_pickup")
	var legendary := false
	for w in weap:
		if w.get("weapon_rarity") == "legendary": legendary = true
	check(legendary, "legendary weapon reward")
	check(dg.rooms[bc]["cleared"], "room cleared")
	check(hud._council_rows.size() == 0 and hud.boss_bar.visible, "HUD restored")
	# --- G. đi tiếp xuống tầng 16 ---
	main._changing = false
	main._on_portal_entered()
	await wait(1.0)
	check(G.floor_num == 16 and not G.in_council, "after council -> floor 16")
	print("council_test: %d ok, %d fail" % [ok, bad])
	quit(1 if bad > 0 else 0)
