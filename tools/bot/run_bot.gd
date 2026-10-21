extends SceneTree
## Chạy bot tự chơi hàng loạt và in bảng tổng hợp cân bằng.
##   godot --headless --path . --script tools/bot/run_bot.gd -- --runs 5 --class ranger --speed 6
## Tham số (sau dấu --):
##   --runs N          số ván mỗi cấu hình (mặc định 3)
##   --class a,b,c     class cần thử (mặc định cả 4: ranger,brawler,mage,rogue)
##   --heat x,y        mô-đun Heat bật (mặc định không); dùng "none" hoặc "off:on" để so sánh hai cấu hình: --heat-compare
##   --heat-compare    chạy mỗi class 2 lần: Heat tắt rồi Heat bật (--heat chọn các mô-đun, mặc định tất cả)
##   --speed X         hệ số tăng tốc thời gian mô phỏng (mặc định 6)
##   --max-min M       trần thời gian mô phỏng mỗi ván, phút (mặc định 25)
##   --max-floor F     dừng ván khi tới tầng F (mặc định 20)
##   --seed S          hạt giống ngẫu nhiên
##   --out file.json   ghi kết quả chi tiết ra file
## Bot dùng file save riêng (user://bot_save.dat) nên không đụng save thật.

const BotBrain = preload("res://tools/bot/bot_brain.gd")

var G
var opts: Dictionary = {"runs": 3, "class": "ranger,brawler,mage,rogue", "heat": "", "speed": 6.0, "max-min": 25.0, "max-floor": 20, "seed": 0, "out": "", "trace": 0, "start-floor": 1, "buffs": 0}
var results: Array = []

func _init() -> void:
	call_deferred("_main")

func _parse_args() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		var k: String = String(a[i]).trim_prefix("--")
		if k == "heat-compare":
			opts["heat-compare"] = true
			i += 1
			continue
		if i + 1 < a.size() and opts.has(k):
			var v: String = a[i + 1]
			if opts[k] is float: opts[k] = float(v)
			elif opts[k] is int: opts[k] = int(v)
			else: opts[k] = v
			i += 2
		else:
			i += 1

func _main() -> void:
	G = root.get_node("Global")
	_parse_args()
	G.save_path = "user://bot_save.dat"
	var seed_v: int = int(opts["seed"])
	if seed_v != 0:
		seed(seed_v)
	Engine.max_physics_steps_per_frame = 200
	var classes: Array = String(opts["class"]).split(",", false)
	var heat_all: Array = G.HeatScript.ORDER.duplicate()
	var heat_ids: Array = heat_all if (opts.has("heat-compare") and String(opts["heat"]) == "") else Array(String(opts["heat"]).split(",", false))
	var configs: Array = []
	for c in classes:
		if opts.has("heat-compare"):
			configs.append({"class": c, "heat": []})
			configs.append({"class": c, "heat": heat_ids})
		else:
			configs.append({"class": c, "heat": heat_ids})
	for cfg in configs:
		for r in int(opts["runs"]):
			var res: Dictionary = await _play(cfg["class"], cfg["heat"])
			res["class"] = cfg["class"]
			res["heat"] = ",".join(PackedStringArray(cfg["heat"]))
			results.append(res)
			print("run %-8s heat=%-3d floor=%2d %-9s t=%5.0fs kills=%3d rolls=%d hunts=%d stuck=%d killer=%s" % [res["class"], G.HeatScript.total(cfg["heat"]), res["floor"], res["end"], res["time"], res["kills"], res["rolls"], res["hunts"], res["stuck"], res["killer"]])
	_report(configs)
	if String(opts["out"]) != "":
		var f := FileAccess.open(String(opts["out"]), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(results, "\t"))
			f.close()
	Engine.time_scale = 1.0
	quit()

func _play(cid: String, heat_ids: Array) -> Dictionary:
	paused = false
	Engine.time_scale = 1.0
	G.current_class = cid
	G.saved_run = {}
	G.heat_selected = {}
	for id in heat_ids:
		G.heat_selected[id] = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 30:
		await physics_frame
	var main = current_scene
	if int(opts["start-floor"]) > 1:
		# nhảy thẳng tới tầng cần đo (vd Hell 11-15 / Council) với bộ buff ngẫu nhiên cho trước, như người chơi đã đi tới đó
		for i in int(opts["buffs"]):
			var pick: Array = G.roll_buff_choices(1)
			if not pick.is_empty():
				G.apply_buff(String(pick[0]))
		G.floor_num = int(opts["start-floor"]) - 1
		main._next_floor()
		for i in 30:
			await physics_frame
	var brain = BotBrain.new()
	main.add_child(brain)
	brain.setup(main)
	brain.trace = int(opts["trace"]) > 0
	var max_t: float = float(opts["max-min"]) * 60.0
	var end: String = "timeout"
	var won: bool = false
	var speed: float = float(opts["speed"])
	while true:
		await physics_frame
		if not G._hitstop_active:
			Engine.time_scale = speed
		if main.is_game_over:
			end = "death"
			break
		if main.is_victory_screen:
			won = true
			# tới Endless như người chơi bấm "Continue to Endless Mode"
			main.is_victory_screen = false
			paused = false
			main.pause_layer.hide()
			main._next_floor.call_deferred()
		if G.floor_num >= int(opts["max-floor"]):
			end = "max-floor"
			break
		if brain.sim_time >= max_t:
			break
	var killer: String = main.telemetry.killer(G.run_stats) if main.has_method("get") else ""
	var killer_name: String = main.telemetry.source_name(killer) if killer != "" else "-"
	var summary: Dictionary = main.telemetry.summary(G.run_stats)
	var res := {
		"floor": G.floor_num, "end": end, "won": won, "time": brain.sim_time, "kills": int(G.run_stats.get("kills", 0)),
		"killer": killer_name, "damage": int(summary["total_damage"]), "rolls": brain.stats["rolls"], "skills": brain.stats["skills"],
		"stuck": brain.stats["stuck_events"], "hunts": int(brain.stats.get("hunts", 0)), "buffs": brain.stats["buffs"].size(),
		"top": main.telemetry.top_sources(G.run_stats),
	}
	Engine.time_scale = 1.0
	paused = false
	brain.queue_free()
	return res

func main_name(src: String) -> String:
	return load("res://scripts/run_telemetry.gd").source_name(src)

func _report(configs: Array) -> void:
	print("")
	print("===== TỔNG HỢP (%d ván) =====" % results.size())
	var groups: Dictionary = {}
	for r in results:
		var key: String = "%s | Heat %d" % [r["class"], G.HeatScript.total(String(r["heat"]).split(",", false))]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(r)
	for key in groups:
		var arr: Array = groups[key]
		var floors: Array = arr.map(func(r): return int(r["floor"]))
		var sum_f := 0; var sum_t := 0.0; var wins := 0; var deaths := {}
		for r in arr:
			sum_f += int(r["floor"]); sum_t += float(r["time"])
			if r["won"]: wins += 1
			if r["end"] == "death":
				deaths[r["killer"]] = int(deaths.get(r["killer"], 0)) + 1
		floors.sort()
		var top_killer := "-"; var tk := 0
		for k in deaths:
			if int(deaths[k]) > tk:
				tk = int(deaths[k]); top_killer = k
		var src: Dictionary = {}
		var src_total := 0
		for r in arr:
			for row in r["top"]:
				src[row[0]] = int(src.get(row[0], 0)) + int(row[1])
				src_total += int(row[1])
		var src_rows: Array = []
		for k in src:
			src_rows.append([k, src[k]])
		src_rows.sort_custom(func(a, b): return a[1] > b[1])
		var src_txt: Array = []
		for row in src_rows.slice(0, 4):
			src_txt.append("%s %d%%" % [main_name(String(row[0])), int(round(100.0 * float(row[1]) / float(maxi(1, src_total))))])
		print("%-18s tầng TB %.1f (min %d, max %d) | thắng Lord %d/%d | thời gian TB %.0fs | kẻ hạ nhiều nhất: %s | sát thương nhận: %s" % [key, float(sum_f) / float(arr.size()), floors[0], floors[-1], wins, arr.size(), sum_t / float(arr.size()), top_killer, ", ".join(PackedStringArray(src_txt))])
