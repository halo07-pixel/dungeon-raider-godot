extends SceneTree
## Stalker trong world: xuất hiện sau STALK_AFTER phòng không nghỉ, không ở phòng bench/boss, theo qua phòng, nghỉ/chạm thì đặt lại, tắt nightmare thì không có.
var fails: int = 0
var w: Node2D

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func go(id: String) -> int:
	w.busy = false
	w.load_room(id)
	await process_frame
	return get_nodes_in_group("hk_stalker").filter(func(n): return not n.is_queued_for_deletion()).size()

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_stalk_world_save.json"
	St.delete_save()
	w = Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	for i in 10:
		await process_frame
	w._reset_stalk()
	var n: int = await go("gate_2")
	ck(n == 0, "phòng đầu: không có Stalker")
	n = await go("gate_3")
	n = await go("gate_2")
	n = await go("gate_3")
	ck(n == 0, "mới 3 phòng: chưa có (%d)" % n)
	n = await go("gate_2")
	ck(n == 1, "sau %d phòng: Stalker xuất hiện (%d)" % [w._rooms_since_rest, n])
	n = await go("gate_3")
	ck(n == 1, "theo sang phòng kế (%d)" % n)
	n = await go("gate_1")
	ck(n == 0 and w._has_bench(), "phòng có bench: không có Stalker")
	n = await go("gate_6")
	ck(n == 0, "phòng boss: không có Stalker")
	w._on_stalker_touched()
	ck(not w._stalking and w._rooms_since_rest == 0, "chạm: đặt lại bộ đếm")
	n = await go("gate_2")
	ck(n == 0, "sau khi bị chạm: hết đuổi (%d)" % n)
	# nghỉ đặt lại
	for i in 5:
		n = await go("gate_2" if i % 2 == 0 else "gate_3")
	ck(w._stalking, "lại đủ phòng thì đuổi lại")
	w._reset_stalk()
	n = await go("gate_2")
	ck(n == 0, "reset (nghỉ/chết/đi nhanh): hết đuổi")
	# tắt nightmare / Rush
	St.nightmare = false
	for i in 6:
		n = await go("gate_2" if i % 2 == 0 else "gate_3")
	ck(n == 0, "tắt nightmare: không có Stalker")
	St.nightmare = true
	St.rush = true
	w._reset_stalk()
	for i in 6:
		n = await go("gate_2" if i % 2 == 0 else "gate_3")
	ck(n == 0, "Boss Rush: không có Stalker")
	St.rush = false
	print("DONE fails=", fails)
	quit(fails)
