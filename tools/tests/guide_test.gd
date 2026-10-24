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
	var GC = load("res://scripts/guide_content.gd")
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	await create_timer(0.5).timeout
	var shots: String = OS.get_environment("SHOTS")
	menu.show_index()
	for tab in GC.TAB_ORDER:
		menu._select_guide_tab(tab)
		await create_timer(0.2).timeout
		var raw: String = menu._guide_text.text
		var parsed: String = menu._guide_text.get_parsed_text()
		check(raw.length() > 200, "%s: có nội dung (%d ký tự)" % [tab, raw.length()])
		check(not ("[b]" in parsed or "[/b]" in parsed or "[color" in parsed), "%s: BBCode được dựng đúng, không lộ thẻ" % tab)
		if shots != "":
			root.get_texture().get_image().save_png(shots + "/guide_" + tab + ".png")
	var buffs: String = GC.buffs()
	var miss: Array = []
	for id in G.buff_pool:
		if not (String(G.buff_pool[id]["name"]) in buffs): miss.append(id)
	check(miss.is_empty(), "mọi buff trong buff_pool đều có trong sổ tay (thiếu: %s)" % str(miss))
	var w: String = GC.weapons()
	var wmiss: Array = []
	for id in G.weapons:
		if not (String(G.weapons[id]["name"]) in w): wmiss.append(id)
	check(wmiss.is_empty(), "mọi vũ khí có trong sổ tay (thiếu: %s)" % str(wmiss))
	var ls_missing: Array = []
	for rid in ["epic", "legendary", "mythic"]:
		var want: String = "%d%% lifesteal" % roundi(float(G.rarities[rid]["lifesteal"]) * 100.0)
		if not (want in w): ls_missing.append("%s: %s" % [rid, want])
	check(ls_missing.is_empty(), "hút máu theo bậc khớp dữ liệu thật (thiếu: %s)" % str(ls_missing))
	check("Laser Gun" in w and "pierces 2 enemies" in w, "Laser ghi xuyên 2 quái")
	var e: String = GC.enemies()
	var emiss: Array = []
	for k in G.enemies:
		if not (k.replace("_", " ").capitalize() in e): emiss.append(k)
	check(emiss.is_empty(), "mọi loại quái có trong sổ tay (thiếu: %s)" % str(emiss))
	check("Volatile" in e and "Warden" in e and "Summoner" in e and "Dungeon Lord" in e, "affix và boss cuối có mặt")
	var d: String = GC.defense()
	var pl = load("res://scripts/player.gd")
	var has_floor: bool = pl.get_script_constant_map().has("SHIELD_PER_FLOOR")
	check(("grows by" in d) == has_floor, "mô tả giáp khớp code (SHIELD_PER_FLOOR tồn tại: %s)" % str(has_floor))
	check("Altar" in GC.events() and "Mimic" in GC.events(), "tab Events có Altar và Mimic")
	menu.show_main_menu()
	await create_timer(0.1).timeout
	print("SUMMARY guide: %d/%d PASS" % [total - fails, total])
	await create_timer(0.3).timeout
	quit(1 if fails > 0 else 0)
