extends SceneTree
## Bùa độc quyền sau boss: oath_ward (chặn đòn đầu tiên mỗi phòng), steady_breath (bị đánh không đứt Focus), last_light (đòn chí mạng còn 1 mặt nạ,
## một lần mỗi lần nghỉ), many_faces (+2 Soul mỗi cú chém); không bán ở shop; bàn thờ trong phòng boss cần cờ boss; lưu/đọc giữ bùa.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	var Shop = load("res://hk/shop.gd")
	var WD = load("res://hk/world_data.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_boss_charm_save.json"
	var ids: Array = ["oath_ward", "steady_breath", "last_light", "many_faces"]
	var sh = Shop.new()
	root.add_child(sh)
	var stock_ids: Array = []
	for it in sh._stock(""):
		stock_ids.append(it["id"])
	for c in ids:
		ck(St.CHARMS.has(c) and int(St.CHARMS[c]["cost"]) >= 1, "%s có trong CHARMS" % c)
		ck(not (c in stock_ids), "%s không bán ở shop" % c)
	# bàn thờ trong phòng boss cần cờ boss, có ô C
	var rooms: Dictionary = WD.load_all()
	for pair in [["gate_6", "oath_ward", "boss_warden"], ["cat_8", "steady_breath", "boss_wraith"], ["vault_7", "last_light", "boss_lord"], ["sov_1", "many_faces", "boss_many_faced"]]:
		var rm: Dictionary = rooms[pair[0]]
		ck(String(rm["charm"]["id"]) == pair[1] and String(rm["charm"]["needs"]) == pair[2], "%s: bàn thờ %s cần %s" % [pair[0], pair[1], pair[2]])
		var has_c: bool = false
		for row in rm["grid"]:
			if "C" in String(row):
				has_c = true
		ck(has_c, "%s: có ô bàn thờ C" % pair[0])
	# soul
	St.give_charm("many_faces")
	St.toggle_charm("many_faces")
	ck(St.soul_per_hit() == 13, "many_faces: +2 Soul mỗi cú chém (%d)" % St.soul_per_hit())
	St.toggle_charm("many_faces")
	# world + player
	St.reset()
	St.bench_room = "gate_1"
	var w := Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	await create_timer(0.3).timeout
	var p = w.player
	ck(p.ward_ready, "nạp phòng: ward_ready = true")
	# Oath Ward
	for c in ids:
		St.give_charm(c)
	St.toggle_charm("oath_ward")
	var hp0: int = p.hp
	p.invuln = 0.0
	p.take_damage(0.0)
	ck(p.hp == hp0 and not p.ward_ready, "oath_ward: chặn đòn đầu, không mất máu")
	p.invuln = 0.0
	p.take_damage(0.0)
	ck(p.hp == hp0 - 1, "oath_ward: đòn thứ hai trong cùng phòng trúng bình thường")
	p.invuln = 0.0
	w.load_room("gate_2")
	await frames(3)
	ck(p.ward_ready, "đổi phòng: oath_ward dùng lại được")
	St.toggle_charm("oath_ward")
	p.ward_ready = true
	p.invuln = 0.0
	var hp1: int = p.hp
	p.take_damage(0.0)
	ck(p.hp == hp1 - 1, "không trang bị oath_ward thì không chặn")
	# Steady Breath
	St.toggle_charm("steady_breath")
	p.invuln = 0.0
	p._stun = 0.0
	p.focusing = true
	p.take_damage(0.0)
	ck(p._stun == 0.0, "steady_breath: bị đánh khi Focus không choáng")
	St.toggle_charm("steady_breath")
	p.invuln = 0.0
	p._stun = 0.0
	p.focusing = true
	p.take_damage(0.0)
	ck(p._stun > 0.0, "không có steady_breath: choáng như thường")
	p.focusing = false
	# Last Light
	p._stun = 0.0
	St.toggle_charm("last_light")
	p.hp = 1
	p.invuln = 0.0
	p.take_damage(0.0)
	ck(p.hp == 1 and not p.is_dead() and St.last_light_used, "last_light: đòn chí mạng còn 1 mặt nạ")
	p.invuln = 0.0
	p.take_damage(0.0)
	ck(p.hp == 0 and p.is_dead(), "last_light: lần thứ hai (chưa nghỉ) thì chết")
	p.respawn_at(p.global_position, true)
	ck(not St.last_light_used and p.hp == p.max_hp, "hồi sinh/nghỉ: last_light dùng lại được")
	# lưu/đọc
	var d: Dictionary = St.to_dict()
	St.reset()
	St.from_dict(d)
	ck("last_light" in St.charms_owned and "many_faces" in St.charms_owned, "lưu/đọc giữ bùa độc quyền")
	St.delete_save()
	print("hk_boss_charm_test: ", "OK" if fails == 0 else "%d lỗi" % fails)
	quit(1 if fails > 0 else 0)
