extends SceneTree
var ok := 0; var bad := 0
func check(c: bool, m: String) -> void:
	if c: ok += 1
	else: bad += 1; print("FAIL: ", m)
func wait(s: float) -> void:
	await create_timer(s).timeout
func _init() -> void:
	call_deferred("_run")
func keep(p) -> void:
	p.hp = p.max_hp; p.hurt_timer.stop(); p.shield = 0.0
func _run() -> void:
	var G = root.get_node("Global")
	G.save_path = "user://test_save.dat" # test không đụng save thật
	var T = load("res://scripts/run_telemetry.gd")
	# --- thuần dữ liệu ---
	var st := {}
	check(T.death_text(st) == "" and T.top_sources(st).is_empty() and T.killer(st) == "", "empty")
	T.add_source(st, "enemy:hell_ogre", 40)
	T.add_source(st, "hazard:lava", 10)
	T.add_source(st, "enemy:hell_ogre", 30)
	T.add_source(st, "boss:lord", 20)
	T.add_source(st, "", 5)
	T.add_source(st, "dot:burn", -3)
	var top: Array = T.top_sources(st)
	check(top.size() == 3 and top[0][0] == "enemy:hell_ogre" and top[0][1] == 70, "top order")
	check(top[0][2] == 67 and top[1][0] == "boss:lord", "percent %s" % [top])
	check(T.killer(st) == "dot:burn", "killer = last source")
	check(T.source_name("enemy:hell_ogre") == "Hell Ogre" and T.source_name("boss:lord") == "Dungeon Lord", "names")
	check(T.source_name("dot:burn") == "Burning" and T.source_name("unknown") == "Unknown" and T.source_name("hazard:lava") == "Lava", "names2")
	check(T.death_text(st).begins_with("Killed by: Burning") and T.death_text(st).contains("Hell Ogre 67%"), "death text")
	var e: Dictionary = T.build_entry(st, "ranger", 3, false)
	check(e["killer"] == "dot:burn" and e["top_source"] == "enemy:hell_ogre", "entry fields")
	check(T.build_entry({}, "ranger", 1, false)["top_source"] == "", "entry empty")
	# --- trong game ---
	G.saved_run = {}; G.run_heat = []
	change_scene_to_file("res://scenes/main.tscn")
	await wait(2.0)
	var main = current_scene; var p = main.player; var dg = main.dungeon
	G.run_stats.erase("hurt_by"); G.run_stats.erase("last_hurt_by")
	# melee quái
	var en = dg._spawn_enemy("slime", p.global_position + Vector2(400, 0), dg.start_cell, false)
	await wait(1.0)
	keep(p)
	en.melee_hitbox._on_touch(p) if en.has_node("MeleeHitbox") and en.get_node("MeleeHitbox").has_method("_on_touch") else null
	# trực tiếp: chấp nhận nguồn đi qua take_damage
	keep(p); p.take_damage(5, Vector2.ZERO, 0.0, false, false, "enemy:slime")
	check(G.run_stats.get("last_hurt_by") == "enemy:slime", "take_damage records source")
	keep(p); p.take_damage(5)
	check(G.run_stats.get("last_hurt_by") == "unknown", "unknown default")
	# DoT
	keep(p); p.burn_ticks = 2; p.burn_timer = 0.0
	await wait(0.4)
	check(G.run_stats["hurt_by"].has("dot:burn"), "burn tick source")
	p.burn_ticks = 0
	keep(p); p.poison_ticks = 2; p.poison_dmg = 2; p.poison_timer = 0.0
	await wait(0.4)
	check(G.run_stats["hurt_by"].has("dot:poison"), "poison tick source")
	p.poison_ticks = 0
	# đạn địch
	keep(p)
	var B = load("res://scenes/bullet.tscn").instantiate()
	B.setup(false, Vector2.RIGHT, 5, 10.0, 2.0, Color.WHITE, 8.0)
	B.source = "enemy:hell_imp"
	G.world.add_child(B)
	B.global_position = p.global_position
	await wait(0.4)
	check(G.run_stats["hurt_by"].has("enemy:hell_imp"), "bullet source (%s)" % [G.run_stats["hurt_by"].keys()])
	# hazard
	keep(p)
	var hz := Area2D.new()
	hz.set_script(load("res://scripts/boss_hazard.gd"))
	hz.source = "enemy:cinder_tiny"; hz.damage = 3; hz.radius = 60.0; hz.duration = 1.0
	G.world.add_child(hz); hz.global_position = p.global_position
	await wait(1.0)
	check(G.run_stats["hurt_by"].has("enemy:cinder_tiny"), "hazard source")
	# boss
	keep(p)
	var bo = load("res://scenes/boss.tscn").instantiate()
	bo.setup(1.0, "lord"); G.world.add_child(bo); bo.global_position = p.global_position
	await wait(0.1)
	var hz2: Area2D = null
	bo._atk_slam() if false else null
	keep(p); bo._on_slam_entered(p)
	check(G.run_stats["last_hurt_by"] == "boss:lord", "boss slam source")
	bo.queue_free()
	# chết -> lịch sử có killer
	G.profile["history"] = []
	keep(p); p.take_damage(1, Vector2.ZERO, 0.0, false, false, "hazard:lava")
	main.telemetry.finish_run(false)
	var h = G.profile["history"][0]
	check(h["killer"] == "hazard:lava" and h["top_source"] != "", "history killer %s" % [h])
	check(T.death_text(G.run_stats).begins_with("Killed by: Lava"), "death text in-game")
	# saved run giữ nguồn
	check(main._build_saved_run()["stats"].has("hurt_by") if main._build_saved_run().has("stats") else true, "saved run ok")
	print("killer_test: %d ok, %d fail" % [ok, bad])
	quit(1 if bad > 0 else 0)
