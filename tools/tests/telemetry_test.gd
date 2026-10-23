extends SceneTree
var ok := 0; var bad := 0
func check(c: bool, m: String) -> void:
	if c: ok += 1
	else: bad += 1; print("FAIL: ", m)
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var RT = load("res://scripts/run_telemetry.gd")
	var MP = load("res://scripts/meta_progress.gd")
	var st := {"kills": 7}
	check(RT.summary_text(st) == "", "empty text")
	RT.add_time(st, 1, 30.0); RT.add_damage(st, 1, 10)
	RT.add_time(st, 2, 95.5); RT.add_damage(st, 2, 80); RT.add_damage(st, 2, -5)
	RT.add_damage(st, 3, 40)
	var s: Dictionary = RT.summary(st)
	check(int(s["total_damage"]) == 130, "total dmg")
	check(absf(float(s["total_time"]) - 125.5) < 0.01, "total time")
	check(int(s["hardest_floor"]) == 2 and int(s["hardest_damage"]) == 80, "hardest")
	check(int(s["slowest_floor"]) == 2, "slowest")
	check(RT.fmt_time(125.5) == "2:05", "fmt")
	var txt: String = RT.summary_text(st)
	check(txt.contains("Hardest floor: 2") and txt.contains("Slowest floor: 2"), "text")
	var e: Dictionary = RT.build_entry(st, "ranger", 3, true)
	check(e["class"] == "ranger" and e["floor"] == 3 and e["won"] and e["kills"] == 7, "entry")
	# profile history
	var p: Dictionary = MP.new_profile()
	check(p.has("history") and p["history"].is_empty(), "profile history")
	for i in 25: MP.record_run_end(p, {"floor": i})
	check(p["history"].size() == 20 and p["history"][0]["floor"] == 5, "cap 20")
	var m: Dictionary = MP.merge_loaded(p)
	check(m["history"].size() == 20, "merge keeps history")
	var old: Dictionary = MP.merge_loaded({"runs": 3})
	check(old["history"].is_empty() and old["runs"] == 3, "old save ok")
	var junk: Dictionary = MP.merge_loaded({"history": [1, {"floor": 2}, "x"]})
	check(junk["history"].size() == 1, "junk filtered")
	# save roundtrip with int keys
	var f := FileAccess.open("user://tele_test.bin", FileAccess.WRITE); f.store_var(st); f.close()
	var g := FileAccess.open("user://tele_test.bin", FileAccess.READ); var back = g.get_var(); g.close()
	check(RT.summary(back)["total_damage"] == 130, "roundtrip")
	print("telemetry_test: %d ok, %d fail" % [ok, bad])
	quit(1 if bad > 0 else 0)
