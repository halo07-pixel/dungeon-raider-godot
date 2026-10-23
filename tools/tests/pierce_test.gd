extends SceneTree
var fails: int = 0
var total: int = 0
var hits: Dictionary = {}

func check(ok: bool, name: String) -> void:
	total += 1
	if ok:
		print("PASS  ", name)
	else:
		fails += 1
		print("FAIL  ", name)

func wait(sec: float) -> void:
	await create_timer(sec).timeout

func on_hit(target: Node, _d: int, _c: bool) -> void:
	hits[target] = int(hits.get(target, 0)) + 1

func scenario(label: String, main, weapon: String, rarity: String, buffs: Dictionary, super_shot: bool, expect: int, n_enemies: int = 5) -> void:
	var G = root.get_node("Global")
	G.save_path = "user://test_save.dat" # test không đụng save thật
	var p = main.player
	G.run_buffs.clear()
	for k in buffs:
		G.run_buffs[k] = buffs[k]
	p.set_weapon_with_rarity(weapon, rarity)
	p.shot_count = 5 if super_shot else 0
	hits.clear()
	var list: Array = []
	for i in n_enemies:
		var e = main.dungeon._spawn_enemy("brute", p.global_position + Vector2(90.0 + 60.0 * i, 0.0), main.dungeon.start_cell)
		e.set_physics_process(false)
		list.append(e)
	p.aim_dir = Vector2.RIGHT
	p.fire_timer.stop()
	p._shoot()
	await wait(0.7)
	var hit_enemies: int = 0
	var max_per: int = 0
	for e in list:
		var c: int = int(hits.get(e, 0))
		if c > 0:
			hit_enemies += 1
		max_per = maxi(max_per, c)
	check(hit_enemies == expect and max_per <= 1, "%s: đánh %d quái (cần %d), mỗi quái tối đa %d lần" % [label, hit_enemies, expect, max_per])
	for e in list:
		if is_instance_valid(e):
			e.queue_free()
	await wait(0.1)

func _initialize() -> void:
	await process_frame
	var G = root.get_node("Global")
	G.save_path = "user://test_save.dat" # test không đụng save thật
	G.saved_run.clear()
	G.player_hit_landed.connect(on_hit)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await wait(1.0)
	var p = main.player
	p.max_hp = 1000000
	p.hp = 1000000
	check(G.weapons["laser"]["pierce_count"] == 2 and not G.weapons["laser"]["pierce"], "Laser: pierce_count 2, không còn xuyên vô hạn")
	await scenario("Pistol thường", main, "pistol", "common", {}, false, 1)
	await scenario("SMG thường", main, "smg", "common", {}, false, 1)
	await scenario("Pistol Epic", main, "pistol", "epic", {}, false, 2)
	await scenario("Pistol + Sweep", main, "pistol", "common", {"buff_sweep": 1}, false, 2)
	await scenario("Pistol + Mega Shot (phát thứ 6)", main, "pistol", "common", {"buff_super": 1}, true, 3)
	await scenario("Pistol + Mega Shot (phát thường)", main, "pistol", "common", {"buff_super": 1}, false, 1)
	await scenario("Laser thường", main, "laser", "common", {}, false, 3)
	await scenario("Laser + Sweep", main, "laser", "common", {"buff_sweep": 1}, false, 4)
	await scenario("Laser + Mega Shot (phát thứ 6)", main, "laser", "common", {"buff_super": 1}, true, 4)
	await scenario("Laser + Sweep + Mega Shot (phát thứ 6)", main, "laser", "common", {"buff_sweep": 1, "buff_super": 1}, true, 5)
	# đạn biến mất sau quái cuối: không còn viên nào bay
	var left: int = 0
	for b in get_nodes_in_group("enemy_bullets"):
		left += 1
	var player_bullets: int = 0
	for n in main.dungeon.get_parent().get_children():
		if n.has_method("reflect") and n.get("from_player") == true:
			player_bullets += 1
	check(player_bullets == 0, "không còn đạn của Player lơ lửng sau khi xong (%d)" % player_bullets)
	print("SUMMARY pierce: %d/%d PASS" % [total - fails, total])
	quit(1 if fails > 0 else 0)
