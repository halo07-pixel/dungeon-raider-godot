extends SceneTree
var fails := 0
var total := 0
func check(ok: bool, n: String) -> void:
	total += 1
	if not ok: fails += 1
	print("PASS  " if ok else "FAIL  ", n)
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Global")
	G.save_path = "user://test_save.dat" # test không đụng save thật
	G.saved_run = {"class": "brawler", "hp": 150, "weapon_id": "broadsword", "weapon_rarity": "common", "has_revived": false,
		"max_hp": 200, "shield": 56.0, "run_buffs": {}, "stats": {"floors": 10}}
	G.floor_num = 10
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(1.0).timeout
	var p = main.player
	check(p.max_shield == 20, "tầng 10, không buff: giáp tối đa 20 (là %d)" % p.max_shield)
	check(p.shield <= 20.0, "save cũ giáp 56 bị kẹp về trần mới (%.0f)" % p.shield)
	for fl in [1, 5, 15]:
		G.floor_num = fl
		p.refresh_max_shield()
		check(p.max_shield == 20, "tầng %d: vẫn 20" % fl)
	G.run_buffs["buff_shield_cap"] = 2
	p.refresh_max_shield()
	check(p.max_shield == 40, "2 stack Shield Cap: 40 (là %d)" % p.max_shield)
	G.run_buffs["buff_shield_cap"] = 5
	G.floor_num = 12
	p.refresh_max_shield()
	check(p.max_shield == 70, "5 stack, tầng 12: 70 (là %d)" % p.max_shield)
	# sang tầng mới: giáp hồi đầy
	p.shield = 5.0
	main._changing = true
	await main._next_floor()
	await create_timer(0.3).timeout
	check(is_equal_approx(p.shield, float(p.max_shield)), "sang tầng mới: giáp hồi đầy (%.0f/%d)" % [p.shield, p.max_shield])
	print("SUMMARY shield: %d/%d PASS" % [total - fails, total])
	quit(1 if fails > 0 else 0)
