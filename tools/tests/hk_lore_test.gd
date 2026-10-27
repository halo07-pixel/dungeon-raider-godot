extends SceneTree
## Test cốt truyện: dữ liệu đủ cho mọi boss, ký ức = cờ boss, dòng bench theo số ký ức, ending 2 kiểu, tab Memories (phím N), banner boss.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await process_frame
	await process_frame
	e.pressed = false
	Input.parse_input_event(e)
	await process_frame

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	var L = load("res://hk/lore.gd")
	var B = load("res://hk/boss.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_lore_save.json"
	St.delete_save()
	# dữ liệu
	var seen: Dictionary = {}
	for m in L.MEMORIES:
		var id: String = String(m["id"])
		seen[id] = true
		ck(B.DATA.has(id), "%s: là boss có thật" % id)
		ck(String(m["title"]) != "" and String(m["intro"]) != "" and String(m["memory"]) != "", "%s: đủ chữ" % id)
	ck(seen.size() == L.MEMORIES.size() and seen.size() == 6, "6 ký ức, không trùng")
	var boss_rooms: Array = []
	for f in DirAccess.get_files_at("res://hk/rooms"):
		if FileAccess.get_file_as_string("res://hk/rooms/" + f).contains("boss: id="):
			for l in FileAccess.get_file_as_string("res://hk/rooms/" + f).split("\n"):
				if l.begins_with("boss: id="):
					boss_rooms.append(l.substr(9).split(" ")[0])
	for id in seen:
		ck(id in boss_rooms, "%s: có phòng boss để nhận ký ức" % id)
	ck(L.BENCH.size() == L.MEMORIES.size() + 1, "mỗi số ký ức 0..6 có một dòng bench")
	# đếm theo cờ
	ck(L.count() == 0 and not L.is_complete(), "mới chơi: 0 ký ức")
	St.set_flag("boss_warden"); St.set_flag("boss_hexer")
	ck(L.count() == 2 and L.has_memory("warden") and not L.has_memory("lord"), "đếm theo cờ boss")
	ck(L.bench_line() == L.BENCH[2], "bench theo số ký ức")
	ck(L.ending_lines() == L.ENDING_NORMAL, "thiếu ký ức: ending thường")
	ck(L.death_line("archive") != L.death_line("gate") and L.death_line("lạ") == L.death_line("gate"), "dòng chết theo khu, khu lạ dùng mặc định")
	for m in L.MEMORIES:
		St.set_flag("boss_" + String(m["id"]))
	ck(L.is_complete() and L.ending_lines() == L.ENDING_FULL, "đủ 6: ending hoàn chỉnh")
	# tab Memories bằng phím N, đóng bằng N
	var menu = load("res://hk/menu.gd").new()
	root.add_child(menu)
	await process_frame
	await press("hk_memories")
	ck(menu.tab == "memories" and menu.is_open(), "phím N mở tab Memories")
	menu._view.queue_redraw()
	await process_frame
	await press("hk_charms")
	ck(menu.tab == "charms", "chuyển sang tab Bùa")
	await press("hk_memories")
	ck(menu.tab == "memories", "chuyển lại Memories")
	await press("hk_memories")
	ck(not menu.is_open(), "N đóng tab")
	menu.queue_free()
	# banner boss trong world thật
	St.reset()
	var w := Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	await create_timer(0.3).timeout
	w._on_boss_defeated("warden")
	ck(w.hud.banner_sub == L.memory("warden")["memory"], "hạ boss: banner hiện ký ức")
	ck(L.count() == 1, "hạ boss: nhận ký ức")
	w.rest()
	await process_frame
	ck(w.hud.banner_sub == L.BENCH[1], "nghỉ bench: dòng theo ký ức")
	St.delete_save()
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
