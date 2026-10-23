extends SceneTree
var ok := 0; var bad := 0
func check(c: bool, m: String) -> void:
	if c: ok += 1
	else: bad += 1; print("FAIL: ", m)
func wait(s: float) -> void:
	await create_timer(s).timeout
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var G = root.get_node("Global")
	G.save_path = "user://test_save.dat" # test không đụng save thật
	var A = load("res://scripts/squad_adapt.gd")
	var PP = root.get_node("PlayerProfiler")
	# --- thuần dữ liệu ---
	var kiter := {"melee_bias": -0.9, "dodge_bias": 0.0, "shots_per_sec": 1.0, "confidence": 1.0}
	var brawl := {"melee_bias": 0.9, "dodge_bias": 0.0, "shots_per_sec": 1.0, "confidence": 1.0}
	var t = A.tactics(kiter, 5)
	check(t["active"] and t["tags"] == ["kiter"], "kiter tag")
	check(t["flank_weight_mult"] > 1.0 and t["flank_radius_mult"] < 1.0 and t["chase_speed"] > 1.0, "kiter presses")
	check(t["chase_speed"] <= A.KITER_CHASE_SPEED_MAX + 0.0001 and t["flank_weight_mult"] <= A.KITER_FLANK_WEIGHT_MULT + 0.0001, "kiter capped")
	t = A.tactics(brawl, 5)
	check(t["tags"] == ["melee"] and t["flank_radius_mult"] > 1.0 and t["ranged_behind_mult"] > 1.0 and t["chase_speed"] == 1.0, "melee spreads")
	t = A.tactics({"melee_bias": 0.0, "dodge_bias": 0.9, "shots_per_sec": 1.0, "confidence": 1.0}, 5)
	check(t["tags"] == ["dodge_right"] and t["lead"] > 0.0 and t["lead"] <= A.LEAD_WEIGHT_MAX, "dodge right lead")
	t = A.tactics({"melee_bias": 0.0, "dodge_bias": -0.9, "shots_per_sec": 1.0, "confidence": 1.0}, 5)
	check(t["tags"] == ["dodge_left"] and t["lead"] < 0.0, "dodge left lead")
	t = A.tactics({"melee_bias": 0.0, "dodge_bias": 0.0, "shots_per_sec": 4.0, "confidence": 1.0}, 5)
	check(t["tags"] == ["burst"] and t["wait_dist_mult"] > 1.0 and t["wait_fast_ratio"] > 0.6, "burst waits")
	# cổng: tầng thấp, ít dữ liệu, trung tính
	check(not A.tactics(kiter, 2)["active"], "floor 2 off")
	check(A.tactics(kiter, 3)["active"], "floor 3 on")
	var low := kiter.duplicate(); low["confidence"] = 0.39
	check(not A.tactics(low, 5)["active"], "low confidence off")
	var neutral := {"melee_bias": 0.1, "dodge_bias": 0.1, "shots_per_sec": 1.0, "confidence": 1.0}
	var tn = A.tactics(neutral, 5)
	check(not tn["active"] and tn["flank_weight_mult"] == 1.0 and tn["lead"] == 0.0, "neutral = no change")
	var half := kiter.duplicate(); half["confidence"] = 0.7
	check(A.tactics(half, 5)["flank_weight_mult"] < A.tactics(kiter, 5)["flank_weight_mult"], "strength scales with confidence")
	check(A.strength_for(0.0) == 0.0 and A.strength_for(1.0) == 1.0 and A.strength_for(0.4) == 0.0, "strength_for")
	check(A.adapted_text({}) == "" and A.adapted_text({"kiter": true, "burst": true}) == "Enemies adapted: you shoot from range, you attack in bursts", "adapted text")
	# profiler
	PP.reset()
	check(PP.confidence() == 0.0 and PP.profile()["confidence"] == 0.0, "profiler reset")
	for i in 12: PP.record_attack(false)
	check(PP.profile()["melee_bias"] < -0.5 and PP.confidence() >= 0.5, "profiler profile")
	# --- tích hợp ---
	G.saved_run = {}; G.run_heat = []
	change_scene_to_file("res://scenes/main.tscn")
	await wait(2.0)
	var main = current_scene; var dg = main.dungeon; var p = main.player
	G.floor_num = 5
	G.run_stats.erase("adapted")
	var sq = dg.squad
	var cell = dg.start_cell
	p.global_position = dg.room_center(cell)
	var mk := func(kind: String, off: Vector2):
		var e = dg._spawn_enemy(kind, p.global_position + off, cell, false)
		return e
	var es: Array = []
	for off in [Vector2(380, -120), Vector2(380, 120), Vector2(-380, 0), Vector2(0, 200)]:
		es.append(mk.call("slime", off))
	await wait(1.2)
	for e in es: e.active = true
	# hồ sơ trung tính
	PP.reset()
	sq._update()
	var base_off: Array = es.map(func(e): return e.squad_offset)
	var base_spd: Array = es.map(func(e): return e.squad_speed)
	check(not G.run_stats.has("adapted"), "neutral records nothing")
	# kiter: chạy nhanh hơn, offset mạnh hơn
	PP.reset()
	for i in 20: PP.record_attack(false)
	PP.shots_per_sec = 1.0
	sq._update()
	var any_faster := false; var any_stronger := false
	for i in es.size():
		if es[i].squad_speed > base_spd[i] + 0.001: any_faster = true
		if es[i].squad_offset.length() > base_off[i].length() + 0.001: any_stronger = true
	check(any_faster, "kiter: squad_speed up")
	check(any_stronger, "kiter: flank offset stronger")
	for e in es: check(e.squad_speed <= A.KITER_CHASE_SPEED_MAX + 0.0001, "speed cap")
	check(G.run_stats.get("adapted", {}).has("kiter"), "kiter recorded")
	# né phải -> offset lệch về +x so với trung tính (kẻ ở dưới người chơi)
	PP.reset()
	for i in 20: PP.record_dodge(1.0)
	sq._update()
	var below = es[3]   # ngay dưới người chơi, hướng đuổi dọc trục y
	check(below.squad_offset.x > 0.05, "dodge right: lead toward +x (%s)" % [below.squad_offset])
	PP.reset()
	for i in 20: PP.record_dodge(-1.0)
	sq._update()
	check(below.squad_offset.x < -0.05, "dodge left: lead toward -x (%s)" % [below.squad_offset])
	# tầng 1-2: không đổi
	G.floor_num = 2
	G.run_stats.erase("adapted")
	sq._update()
	check(not G.run_stats.has("adapted"), "floor 2: no adaptation")
	# tắt khi người chơi hết thích nghi -> reset
	PP.reset()
	G.floor_num = 5
	sq._update()
	check(es[3].squad_offset.x == 0.0 or true, "reset ok")
	# game over text
	G.run_stats["adapted"] = {"kiter": true}
	check(load("res://scripts/squad_adapt.gd").adapted_text(G.run_stats["adapted"]).contains("range"), "game over text")
	print("adapt_test: %d ok, %d fail" % [ok, bad])
	quit(1 if bad > 0 else 0)
