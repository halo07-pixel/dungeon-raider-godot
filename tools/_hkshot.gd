extends SceneTree
## Chụp ảnh một phòng: godot --path . -s tools/_hkshot.gd -- <room_id> <out.png> [x y] [debug]
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var rid: String = args[0] if args.size() > 0 else "gate_1"
	var out: String = args[1] if args.size() > 1 else "/tmp/hk.png"
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_shot.json"
	for a in ["dash", "double_jump", "wall_cling"]:
		St.give_ability(a)
	St.bench_room = rid
	St.bench_id = "bench"
	var w := Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	await create_timer(0.3).timeout
	if args.size() > 3:
		w.player.global_position = Vector2(float(args[2]), float(args[3]))
	if "debug" in args:
		w.debug_boxes.toggle()
	await create_timer(0.8).timeout
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()
