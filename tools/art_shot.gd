extends SceneTree
## Chụp ảnh các sprite mới trong cảnh thật để kiểm tra bằng mắt. Cần màn hình ảo:
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s tools/art_shot.gd -- /tmp/shot.png
func _init() -> void:
	await process_frame
	var G = root.get_node("Global")
	G.save_path = "user://shot_save.dat"
	G.reset_run()
	G.current_class = "summoner"
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for _i in 6:
		await process_frame
	var p = main.player
	var base: Vector2 = p.global_position
	var Minion = load("res://scripts/minion.gd")
	var Pickup = load("res://scenes/pickup.tscn")
	var Forge = load("res://scenes/forge.gd")
	var x: float = -190.0
	for k in ["spirit", "wisp", "guardian", "turret", "totem", "ward", "mini", "blades"]:
		var m = Minion.spawn(p, k, base + Vector2(x, 90), 1.0, 99.0, 0)
		m.set_physics_process(false)
		x += 54.0
	var forge := Area2D.new()
	forge.set_script(Forge)
	G.world.add_child(forge)
	forge.global_position = base + Vector2(-150, -60)
	for spec in [["portal", ""], ["council_portal", ""], ["tome", "storm_bolt"], ["sigil", "might"]]:
		var pk = Pickup.instantiate()
		pk.setup(spec[0], spec[1]) if pk.has_method("setup") else null
		G.world.add_child(pk)
		pk.global_position = base + Vector2(-20 + 70 * ["portal", "council_portal", "tome", "sigil"].find(spec[0]), -60)
	for _i in 30:
		await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/shot.png"
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	quit()
