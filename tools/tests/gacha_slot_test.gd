extends SceneTree
## Gacha: kết quả cho chọn đặt vũ khí mới vào ô 1 hoặc ô 2. Chạy: godot --headless --path . -s tools/tests/gacha_slot_test.gd
var fails: int = 0
func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func buttons(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Button:
			out.append(c)
		buttons(c, out)

func _init() -> void:
	await process_frame
	var WI = load("res://scripts/weapon_instance.gd")
	var G = root.get_node("Global")
	G.reset_run()
	G.current_class = "ranger"
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var p = main.player
	var npc = load("res://scenes/npc.tscn").instantiate()
	main.add_child(npc)
	await process_frame
	var won = WI.make("spear", "legendary", 0, ["swift", "reaching"])
	# --- ô 2 trống: đặt vào ô 2, ô 1 giữ nguyên ---
	p.set_slot(0, WI.make("pistol", "rare"))
	p.weapon_slots[1] = {}
	npc.win_inst = won
	npc._on_spin_finished()
	await process_frame
	var bs: Array = []
	buttons(npc.confirm_box, bs)
	var put: Array = bs.filter(func(b): return String(b.text).begins_with("PUT IN SLOT"))
	ck(put.size() == 2, "two put buttons, got %d" % put.size())
	ck(String(put[1].text).contains("(empty)"), "slot 2 labelled empty")
	ck(String(put[0].text).contains("Pistol"), "slot 1 names replaced weapon")
	put[1].pressed.emit()
	ck(p.weapon_slots[1]["id"] == "spear" and p.weapon_slots[0]["id"] == "pistol", "placed in slot 2, slot 1 kept")
	ck(p.active_slot == 1 and p.weapon_id == "spear", "slot 2 now in hand")
	# --- đủ 2 ô: thay ô 1 dù đang cầm ô 2 ---
	npc.win_inst = WI.make("hammer", "epic", 0, ["heavy", "keen"])
	npc._on_spin_finished()
	await process_frame
	bs = []
	buttons(npc.confirm_box, bs)
	put = bs.filter(func(b): return String(b.text).begins_with("PUT IN SLOT"))
	ck(String(put[0].text).contains("replaces Pistol"), "button names replaced weapon")
	put[0].pressed.emit()
	ck(p.weapon_slots[0]["id"] == "hammer" and p.weapon_slots[1]["id"] == "spear", "replaced slot 1, kept slot 2")
	ck(p.active_slot == 0 and p.weapon_id == "hammer", "slot 1 in hand")
	# --- bỏ qua ---
	npc.win_inst = WI.make("bow", "common")
	npc._on_spin_finished()
	await process_frame
	bs = []
	buttons(npc.confirm_box, bs)
	var skip: Array = bs.filter(func(b): return String(b.text).begins_with("SKIP"))
	ck(skip.size() == 1, "skip button")
	skip[0].pressed.emit()
	ck(p.weapon_slots[0]["id"] == "hammer" and p.weapon_slots[1]["id"] == "spear", "skip changes nothing")
	# --- save sau khi đổi ---
	var sv = main._build_saved_run()
	ck(sv["weapon_slots"][0]["id"] == "hammer" and sv["active_slot"] == 0, "save reflects placement")
	ck(not p.place_weapon(2, won) and not p.place_weapon(0, {}), "invalid place rejected")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
