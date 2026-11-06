extends SceneTree
## Nightmare (nhánh C): phòng tối / im lặng / khoá cửa tới khi hết quái (có giờ chót) / rương mimic. Chọn theo id phòng, cố định, không đụng phòng boss/bench.
var fails: int = 0
var w: Node2D

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func go(id: String) -> void:
	w.busy = false
	w.load_room(id)
	await process_frame

func counts(data: Dictionary) -> Dictionary:
	var e := 0
	var hz := 0
	var safe := false
	for row in data["grid"]:
		for ch in String(row):
			if ch in "cfshgdkzibmt":
				e += 1
			elif ch == "^":
				hz += 1
			elif ch == "B" or ch == "M":
				safe = true
	return {"e": e, "hz": hz, "safe": safe}

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	var O = load("res://hk/ordeal.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_nightmare_map_save.json"
	St.delete_save()
	w = Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	for i in 10:
		await process_frame
	# --- chọn theo id: cố định, có đủ các kiểu, tôn trọng loại trừ
	var by: Dictionary = {"dark": [], "silent": [], "lock": [], "": []}
	for id in w.rooms:
		var d: Dictionary = w.rooms[id]
		var c: Dictionary = counts(d)
		var m: String = O.mode_for(id, d, c["e"], c["hz"], c["safe"])
		ck(m == O.mode_for(id, d, c["e"], c["hz"], c["safe"]), "%s: kiểu cố định" % id)
		by[m].append(id)
		if m != "":
			ck(not d.has("boss") and not c["safe"], "%s: không phải phòng boss/bench/thương nhân" % id)
		if m == "dark":
			ck(c["hz"] == 0, "%s: phòng tối không có gai" % id)
		if m == "lock":
			ck(c["e"] >= O.LOCK_MIN, "%s: phòng khoá có ≥%d quái" % [id, O.LOCK_MIN])
	print("kiểu phòng: tối ", by["dark"], " im ", by["silent"], " khoá ", by["lock"])
	ck(by["dark"].size() > 0 and by["silent"].size() > 0 and by["lock"].size() > 0, "có đủ ba kiểu (tối %d, im %d, khoá %d)" % [by["dark"].size(), by["silent"].size(), by["lock"].size()])
	ck(by[""].size() > by["lock"].size(), "đa số phòng vẫn thường")
	St.nightmare = false
	for id in w.rooms:
		var c2: Dictionary = counts(w.rooms[id])
		ck(O.mode_for(id, w.rooms[id], c2["e"], c2["hz"], c2["safe"]) == "", "tắt nightmare: %s thường" % id)
	St.nightmare = true

	# --- tối
	await go(by["dark"][0])
	ck(w.atmosphere._dark, "phòng tối: bật tối")
	await go(by[""][0])
	ck(not w.atmosphere._dark, "sang phòng thường: hết tối")

	# --- im lặng
	await go(by["silent"][0])
	ck(w.music.current == "", "phòng im lặng: tắt nhạc")
	await go(by[""][0])
	ck(w.music.current != "", "phòng thường: nhạc trở lại")

	# --- khoá cửa
	var lk: String = by["lock"][0]
	await go(lk)
	ck(w.room.locked and w._seal_t > 0.0, "phòng khoá: cửa đóng")
	await w.get_tree().physics_frame
	w._ordeal_tick(0.1)
	ck(w.room.locked, "còn quái: vẫn khoá")
	for e in get_nodes_in_group("hk_enemy"):
		e.free()
	w._ordeal_tick(0.1)
	ck(w.room.locked and w._wave2_done, "hết quái đợt 1: sinh đợt 2, vẫn khoá")
	await process_frame
	ck(get_nodes_in_group("hk_enemy").size() == O.WAVE2_N, "đợt 2: đúng %d quái" % O.WAVE2_N)
	for e in get_nodes_in_group("hk_enemy"):
		e.free()
	w._ordeal_tick(0.1)
	ck(not w.room.locked, "hết quái đợt 2: mở cửa")
	await process_frame
	ck(get_nodes_in_group("hk_enemy").size() == 0, "đợt 2 chỉ sinh một lần")
	await go(lk)
	ck(w.room.locked, "nạp lại: khoá lại")
	w._ordeal_tick(O.SEAL_TIMEOUT + 1.0)
	ck(not w.room.locked, "hết giờ chót: mở dù còn quái")
	St.nightmare = false
	await go(lk)
	ck(not w.room.locked, "tắt nightmare: không khoá")
	St.nightmare = true

	# --- mimic
	var mim: String = ""
	var real: String = ""
	for i in 20:
		var k: String = "x:%d:1" % i
		if O.is_mimic(k, false) and mim == "":
			mim = k
		if not O.is_mimic(k, false) and real == "":
			real = k
	ck(mim != "" and real != "", "có cả rương mimic và rương thật")
	ck(not O.is_mimic(mim, true), "rương hốc bí mật luôn thật")
	St.nightmare = false
	ck(not O.is_mimic(mim, false), "tắt nightmare: không mimic")
	St.nightmare = true
	await go(by[""][0])
	var geo0: int = St.geo
	var before: int = get_nodes_in_group("hk_enemy").size()
	w._on_interacted("cache", {"key": mim, "pos": w.player.global_position + Vector2(60, 0)})
	await process_frame
	var after: Array = get_nodes_in_group("hk_enemy")
	ck(after.size() == before + 1 and St.geo == geo0, "mimic: sinh quái, không cho Geo")
	ck(after.size() > 0 and after[after.size() - 1].kind == "charger" and after[after.size() - 1].state == "windup", "mimic cắn (charger windup)")
	w._on_interacted("cache", {"key": real, "pos": w.player.global_position})
	ck(St.geo == geo0 + 25, "rương thật: +25 Geo")
	print("DONE fails=", fails)
	quit(fails)
