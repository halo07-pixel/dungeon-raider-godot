extends SceneTree
## Đo hiệu năng cơ sở (không phải mô phỏng chơi): với mỗi tầng, dựng ván, đẩy một phòng đông quái + lính + đạn rồi lấy mẫu
## thời gian xử lý mỗi khung (Performance monitors) và số node/đối tượng. Dùng để tìm tầng/tình huống nặng trước khi tối ưu.
## Chạy: godot --headless --path . -s tools/perf_report.gd   (headless không vẽ nên TIME_PROCESS chỉ phản ánh logic, không phải GPU)
const FLOORS: Array = [1, 5, 10, 15]
const FRAMES: int = 240
const ENEMIES: int = 12

func _init() -> void:
	await process_frame
	var G = root.get_node("Global")
	G.save_path = "user://perf_save.dat"
	print("%-6s %-9s %9s %9s %9s %9s %9s" % ["tầng", "cảnh", "proc ms", "phys ms", "max proc", "node", "enemies"])
	for f in FLOORS:
		G.reset_run()
		G.current_class = "summoner"
		G.floor_num = f
		var main = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		for _i in 3:
			await process_frame
		var dg = main.dungeon
		for scen in ["trống", "đông"]:
			if scen == "đông":
				dg._spawn_wave(dg.current_cell, ENEMIES)
				var Minion = load("res://scripts/minion.gd")
				for k in 3:
					Minion.spawn(main.player, "spirit", main.player.global_position + Vector2(30 * k, 20), 1.0, 60.0, k)
				Input.action_press("shoot")
			for _w in 150:
				await process_frame # khởi động: bỏ các khung đầu (nạp cảnh, spawn)
			var sum_p := 0.0
			var sum_ph := 0.0
			var max_p := 0.0
			for _i in FRAMES:
				await process_frame
				var p: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
				sum_p += p
				sum_ph += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
				max_p = maxf(max_p, p)
			print("%-6d %-9s %9.2f %9.2f %9.2f %9d %9d" % [f, scen, sum_p / FRAMES, sum_ph / FRAMES, max_p, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), get_nodes_in_group("enemies").size()])
		Input.action_release("shoot")
		main.queue_free()
		await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://perf_save.dat"))
	quit()
