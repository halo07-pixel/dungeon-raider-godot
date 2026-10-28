extends SceneTree
## Test dễ nhìn + menu: gợi ý nơi tìm bùa (chưa đến / đã đến / do boss giữ / bán ở thương nhân), tab Charms và Pause vẽ không lỗi,
## tường Catacombs tối hơn, phòng có bục một chiều vẽ không lỗi.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	var WD = load("res://hk/world_data.gd")
	var R = load("res://hk/room.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_readability_save.json"
	St.delete_save()
	var rooms: Dictionary = WD.load_all()
	var menu = load("res://hk/menu.gd").new()
	menu.rooms = rooms
	root.add_child(menu)
	await process_frame
	ck(menu.charm_hint("fury") == "Not found yet.", "bùa trong phòng chưa đến: Not found yet")
	St.visit("vault_2")
	ck(menu.charm_hint("fury") == "Seen in %s." % rooms["vault_2"]["name"], "đã đến phòng có bùa: nói tên phòng (%s)" % menu.charm_hint("fury"))
	St.visit("cat_6")
	ck("boss guards" in menu.charm_hint("heavy_blow"), "bùa do boss giữ: có nhắc boss")
	ck(menu.charm_hint("second_wind") == "Sold by a wandering merchant.", "bùa không nằm trong phòng: thương nhân bán")
	for tab in ["charms", "pause", "map", "memories"]:
		menu.open(tab)
		await process_frame
		await process_frame
		menu._view.queue_redraw()
		await process_frame
	menu.close()
	St.give_ability("dash")
	menu.open("pause")
	await process_frame
	await process_frame
	menu.close()
	# tường catacomb tối hơn khu khác
	ck(float(R.WALL_DIM.get("catacomb", 1.0)) < 1.0 and float(R.WALL_DIM.get("gate", 1.0)) == 1.0, "WALL_DIM: chỉ catacomb tối đi")
	# phòng có bục một chiều vẽ được
	var w := Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	St.bench_room = "cat_2"
	root.add_child(w)
	await create_timer(0.4).timeout
	ck(w.room.oneways.size() > 0, "cat_2 có bục một chiều")
	w.room.queue_redraw()
	await process_frame
	await process_frame
	St.delete_save()
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
