extends SceneTree
var fails: int = 0
var total: int = 0

func check(ok: bool, name: String) -> void:
	total += 1
	if ok:
		print("PASS  ", name)
	else:
		fails += 1
		print("FAIL  ", name)

func wait(sec: float) -> void:
	await create_timer(sec).timeout

func _initialize() -> void:
	await process_frame
	var G = root.get_node("Global")
	G.save_path = "user://test_save.dat" # test không đụng save thật
	# --- dữ liệu buff
	check(not G.buff_pool.has("buff_deflect") and not G.BUFF_MAX_STACK.has("buff_deflect"), "buff_deflect không còn trong pool / max stack")
	var leftover: bool = false
	for k in G.SYNERGY_MAP:
		if k == "buff_deflect" or G.SYNERGY_MAP[k].has("buff_deflect"):
			leftover = true
	check(not leftover, "SYNERGY_MAP không còn tham chiếu deflect")
	var d: Dictionary = G.buff_pool.get("buff_fortify", {})
	check(d.get("name") == "Fortify" and d.get("tier") == "rare" and d.get("class") == "any" and d.get("desc") == "Hits grant a little shield" and G.BUFF_MAX_STACK.get("buff_fortify") == 1, "buff_fortify: tên/tier/class/mô tả/max stack 1")
	var sym_ok: bool = true
	for k in G.SYNERGY_MAP:
		if not G.buff_pool.has(k):
			sym_ok = false
		for p in G.SYNERGY_MAP[k]:
			if not G.buff_pool.has(p) or not G.SYNERGY_MAP.has(p) or not G.SYNERGY_MAP[p].has(k):
				sym_ok = false
				print("  không đối xứng: ", k, " <-> ", p)
	check(sym_ok, "SYNERGY_MAP đối xứng và mọi id tồn tại trong pool")

	# --- save cũ có buff_deflect + buff_lifesteal
	G.run_buffs.clear()
	G.saved_run = {"class": "brawler", "hp": 150, "weapon_id": "broadsword", "weapon_rarity": "common", "has_revived": false,
		"max_hp": 200, "shield": 20.0, "run_buffs": {"buff_deflect": 1, "buff_lifesteal": 2, "buff_dmg": 2}, "stats": {"floors": 2}}
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await wait(1.0)
	check(G.floor_num == 2 and not G.run_buffs.has("buff_deflect") and not G.run_buffs.has("buff_lifesteal") and G.buff_stack("buff_dmg") == 2, "save cũ: deflect/lifesteal bị loại, buff khác giữ nguyên, load không lỗi")

	# --- Fortify
	var p = main.player
	var enemy: Node = null
	for e in get_nodes_in_group("enemies"):
		if e.has_method("apply_element"):
			enemy = e
			break
	if enemy == null:
		var es = load("res://scenes/enemy.tscn").instantiate()
		root.add_child(es)
		enemy = es
	check(enemy != null and enemy.has_method("apply_element"), "có mục tiêu thật để đánh")
	G.run_buffs.erase("buff_fortify")
	p.shield_delay_timer = 1000.0 # tắt hồi giáp tự nhiên để đo riêng Fortify
	p.shield = 10.0
	G.on_player_hit(enemy, 10, false)
	check(is_equal_approx(p.shield, 10.0), "không có buff: giáp không đổi")
	G.run_buffs["buff_fortify"] = 1
	G.on_player_hit(enemy, 10, false)
	check(is_equal_approx(p.shield, 11.0), "có Fortify: 1 hit +1 giáp (%.1f)" % p.shield)
	G.on_player_hit(enemy, 10, false)
	G.on_player_hit(enemy, 10, true)
	check(is_equal_approx(p.shield, 11.0), "hồi chiêu 0.25s: các hit liền sau không cộng thêm")
	await wait(0.3)
	p.shield_delay_timer = 1000.0
	G.on_secondary_hit(enemy, 10, false)
	check(is_equal_approx(p.shield, 12.0), "sau hồi chiêu: nguồn sát thương phụ cũng cộng (%.1f)" % p.shield)
	p.shield = float(p.max_shield) - 0.4
	await wait(0.3)
	G.on_player_hit(enemy, 10, false)
	check(is_equal_approx(p.shield, float(p.max_shield)), "không vượt max_shield (%.1f/%d)" % [p.shield, p.max_shield])
	await wait(0.3)
	G.on_player_hit(enemy, 10, false)
	check(p.shield <= float(p.max_shield), "đầy giáp: không cộng thêm")
	# Player chết thì không cộng
	p.shield = 5.0
	p.alive = false
	await wait(0.3)
	G.on_player_hit(enemy, 10, false)
	check(is_equal_approx(p.shield, 5.0), "Player đã chết: không cộng giáp")
	p.alive = true

	# Dao Găm vẫn xóa đạn, không lỗi
	p.set_weapon_with_rarity("daggers", "common")
	check(p.weapon_id == "daggers", "đổi sang Dao Găm bình thường")

	print("SUMMARY fortify: %d/%d PASS" % [total - fails, total])
	quit(1 if fails > 0 else 0)
