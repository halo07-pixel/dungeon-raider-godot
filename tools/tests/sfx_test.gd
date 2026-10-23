extends SceneTree
var fails := 0
var total := 0
func check(ok: bool, n: String) -> void:
	total += 1
	if not ok: fails += 1
	print("PASS  " if ok else "FAIL  ", n)
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Global")
	G.save_path = "user://test_save.dat" # test không đụng save thật
	var want := {"barrage_cast": 0.22, "barrage_volley": 0.20, "shockwave": 0.75, "altar_offer": 1.1, "altar_deny": 0.30, "mimic_reveal": 0.95, "mimic_die": 0.55, "lava_burn": 0.40, "burn_tick": 0.14, "burn_douse": 0.40, "magma_warn": 0.85, "magma_eruption": 1.0, "magma_pool": 0.55, "flame_trail": 0.55, "fissure_warn": 0.80, "fissure_burst": 0.40, "bog_warn": 0.85, "bog_burst": 0.50, "ice_sheet_warn": 0.90, "ice_sheet_freeze": 0.70, "mimic_windup": 0.65, "mimic_lunge": 0.38, "mimic_bite": 0.28, "coin": 0.28, "mimic_steal": 0.55, "mimic_spit": 0.30, "spit_pop": 0.32, "mimic_rage": 0.85, "affix_summon": 0.45, "affix_split": 0.30, "affix_frenzy": 0.25, "affix_leech": 0.25, "affix_blink_warn": 0.40, "affix_blink": 0.25, "volatile_boom": 0.45}
	for k in want:
		var w: AudioStreamWAV = G._sfx.get(k)
		check(w != null, k + " tồn tại")
		if w == null: continue
		var n: int = w.data.size() / 2
		var peak := 0
		var sumsq := 0.0
		for i in n:
			var v: int = absi(w.data.decode_s16(i * 2))
			peak = maxi(peak, v)
			sumsq += float(v) * float(v)
		var dur: float = float(n) / float(w.mix_rate)
		var rms: float = sqrt(sumsq / float(n)) / 32767.0
		print("   %s dur=%.2fs peak=%.2f rms=%.3f" % [k, dur, float(peak) / 32767.0, rms])
		check(absf(dur - float(want[k])) < 0.01, k + " độ dài đúng")
		check(peak < 32767 and peak > 4000, k + " không clip, không câm")
		w.save_to_wav(OS.get_environment("OUTD") + "/" + k + ".wav") if false else null
	# mọi tên âm được gọi trong mã đều phải có trong bảng (tránh gọi im lặng)
	var missing: Array = []
	var rx := RegEx.new()
	rx.compile('sfx\\("([a-z_0-9]+)"')
	var dirs: Array = ["res://scripts", "res://scenes"]
	for d in dirs:
		var da := DirAccess.open(d)
		for f in da.get_files():
			if not f.ends_with(".gd"): continue
			var txt: String = FileAccess.get_file_as_string(d + "/" + f)
			for m in rx.search_all(txt):
				var nm: String = m.get_string(1)
				if not G._sfx.has(nm) and not missing.has(nm): missing.append(nm)
	check(missing.is_empty(), "mọi tên Global.sfx() trong mã đều đã định nghĩa (thiếu: %s)" % str(missing))
	G.sfx("barrage_volley", 1.1)
	G.sfx("không_có")
	await create_timer(0.4).timeout
	print("SUMMARY sfx: %d/%d PASS" % [total - fails, total])
	await create_timer(0.3).timeout
	quit(1 if fails > 0 else 0)
