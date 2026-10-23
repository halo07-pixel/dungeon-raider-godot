extends SceneTree
var ok := 0; var bad := 0
func check(c: bool, m: String) -> void:
	if c: ok += 1
	else: bad += 1; print("FAIL: ", m)
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var G = root.get_node("Global")
	G.save_path = "user://test_save.dat" # test không đụng save thật
	G.saved_run = {}
	G.profile["history"] = []
	change_scene_to_file("res://scenes/main.tscn")
	await create_timer(2.0).timeout
	var main = current_scene
	check(main.telemetry != null, "telemetry node exists")
	var t: Dictionary = G.run_stats.get("telemetry", {})
	check(t.has(1) and float(t[1]["time"]) > 0.5, "time accumulates on floor 1")
	G.player_damaged.emit(12, 100)
	G.player_damaged.emit(8, 100)
	check(int(G.run_stats["telemetry"][1]["dmg"]) == 20, "damage accumulates")
	G.floor_started.emit(2)
	G.player_damaged.emit(5, 100)
	check(int(G.run_stats["telemetry"][2]["dmg"]) == 5, "damage goes to new floor")
	main.player._die()
	await create_timer(0.3).timeout
	var h: Array = G.profile["history"]
	check(h.size() == 1, "history has 1 entry, got %d" % h.size())
	if h.size() == 1:
		check(h[0]["floor"] == 2 and h[0]["damage"] == 25 and h[0]["won"] == false, "entry content")
	check(main.telemetry.finish_run(false).is_empty(), "second finish ignored")
	check(G.profile["history"].size() == 1, "no duplicate")
	print("telemetry_integration: %d ok, %d fail" % [ok, bad])
	quit(1 if bad > 0 else 0)
