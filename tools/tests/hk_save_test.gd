extends SceneTree
## Save hỏng: cờ/shade sai kiểu bị bỏ, geo bị chặn trần, delete_save xoá cả .tmp; nước làm chậm người chơi qua slow_t.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_save_test_save.json"
	St.from_dict({"geo": 9999999999, "flags": {"boss_warden": true, "x": 5, "y": "s", 3: true}, "shade": {"room": 7, "x": 1, "y": 2, "geo": 3}})
	ck(St.geo == St.MAX_GEO, "geo bị chặn trần (%d)" % St.geo)
	ck(St.flag("boss_warden") and not St.flags.has("x") and not St.flags.has("y"), "cờ sai kiểu bị bỏ (%s)" % str(St.flags))
	ck(St.shade.is_empty(), "shade sai kiểu bị bỏ")
	St.from_dict({"shade": {"room": "gate_2", "x": 10, "y": 20.5, "geo": -5}})
	ck(St.shade.get("room") == "gate_2" and int(St.shade["geo"]) == 0 and float(St.shade["y"]) == 20.5, "shade hợp lệ được nhận, geo >= 0")
	St.from_dict({"flags": "bad", "shade": 5})
	ck(St.flags.is_empty() and St.shade.is_empty(), "flags/shade không phải Dictionary -> rỗng")
	# sai kiểu ở số/mảng/chuỗi: không lỗi script, dùng mặc định (trước đây int([]) / for null làm from_dict dừng giữa chừng)
	for bad in [{"hp_bonus": []}, {"geo": {}}, {"notch_bonus": [1]}, {"abilities": null}, {"visited": 5}, {"charms_owned": null}, {"bench_room": []}, {"music_vol": "7", "time": "x"}]:
		St.from_dict(bad)
		ck(St.hp == St.max_hp() and St.geo == 0 and St.bench_room == St.START_ROOM, "save sai kiểu %s -> mặc định" % str(bad))
	St.from_dict({"abilities": ["dash", 5, ["x"], "khong_co"], "visited": ["gate_1", 7, null], "charms_owned": ["fury", {}], "geo": 12.0})
	ck(St.abilities == ["dash"] and St.visited == ["gate_1"] and St.charms_owned == ["fury"] and St.geo == 12, "phần tử sai kiểu bị bỏ, phần tử đúng giữ (%s %s %s)" % [str(St.abilities), str(St.visited), str(St.charms_owned)])
	var f := FileAccess.open(St.save_path + ".tmp", FileAccess.WRITE)
	f.store_string("x")
	f.close()
	St.save()
	St.delete_save()
	ck(not FileAccess.file_exists(St.save_path) and not FileAccess.file_exists(St.save_path + ".tmp"), "delete_save xoá cả file .tmp")
	# nước: zone chỉ đặt slow_t, player tự giảm tốc
	var Z = load("res://hk/zone.gd")
	var P = load("res://hk/player.gd")
	var pl := CharacterBody2D.new()
	pl.set_script(P)
	root.add_child(pl)
	pl.add_to_group("hk_player")
	pl.global_position = Vector2(100, 380)   # đáy vùng nước (nước dâng từ dưới lên)
	var z := Node2D.new()
	z.set_script(Z)
	z.kind = "water"
	z.rect = Rect2(0, 0, 400, 400)
	z.life = 5.0
	root.add_child(z)
	await physics_frame
	await physics_frame
	await physics_frame
	ck(pl.slow_t > 0.0, "zone nước đặt slow_t cho người chơi (%f)" % pl.slow_t)
	z.queue_free()
	pl.queue_free()
	St.delete_save()
	print("hk_save_test: ", "OK" if fails == 0 else "%d lỗi" % fails)
	quit(1 if fails > 0 else 0)
