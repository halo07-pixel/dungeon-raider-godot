extends SceneTree
## Test đi-qua trong engine thật: mọi cửa nối hai chiều và vào được an toàn (không chồng tường/gai/cửa, không bị bật lại,
## không rơi mất), mọi phòng boss khoá rồi mở khi hạ boss, bàn thờ cần boss chỉ hiện sau khi hạ, chết giữa trận boss không kẹt.
var fails: int = 0
var St
var w: Node2D

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func ticks(n: int) -> void:
	var f0: int = Engine.get_physics_frames()
	while Engine.get_physics_frames() - f0 < n:
		Engine.time_scale = 4.0   # hitstop/reset đặt lại time_scale: ép lại mỗi khung
		await physics_frame

func _init() -> void:
	await process_frame
	Engine.max_fps = 0
	Engine.max_physics_steps_per_frame = 64
	load("res://hk/input.gd").ensure()
	St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_walk_save.json"
	St.delete_save()
	for a in ["dash", "double_jump", "wall_cling"]:
		St.give_ability(a)
	w = Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	await ticks(20)
	var rooms: Dictionary = w.rooms
	var links: int = 0
	for from_id in rooms:
		for d in rooms[from_id]["doors"]:
			var link: Dictionary = rooms[from_id]["doors"][d]
			links += 1
			var to_id: String = String(link["to"])
			ck(rooms.has(to_id), "%s cửa %s: phòng đích %s tồn tại" % [from_id, d, to_id])
			if not rooms.has(to_id):
				continue
			var back: Dictionary = rooms[to_id]["doors"].get(String(link["door"]), {})
			ck(not back.is_empty() and back["to"] == from_id and String(back["door"]) == d, "%s/%s <-> %s/%s nối hai chiều" % [from_id, d, to_id, link["door"]])
			# vào phòng đích qua cửa đó, như transition() làm
			w.busy = false
			w.load_room(to_id)
			await process_frame   # phòng cũ queue_free xong trước tick vật lý kế (game thật có khung trễ do fade)
			for e in get_nodes_in_group("hk_enemy"):   # quái/boss bắn đẩy người chơi ra khỏi cửa: kiểm riêng bố cục, không kiểm quái
				e.free()
			if is_instance_valid(w.boss):
				w.boss.free()
			var spawn: Vector2 = w.room.spawn_for_door(String(link["door"]))
			w.player.respawn_at(spawn, true)
			w.player.controls_enabled = true
			w.player.velocity = w.room.entry_velocity(String(link["door"]))
			var pr := Rect2(spawn - w.player.BODY * 0.5, w.player.BODY)
			var tag: String = "vào %s qua cửa %s" % [to_id, link["door"]]
			for r in w.room.solids:
				ck(not pr.intersects(r), "%s: không chồng tường" % tag)
			for r in w.room.hazards:
				ck(not pr.intersects(r), "%s: không chồng gai" % tag)
			for ch in w.room.doors:
				ck(not pr.intersects(w.room.doors[ch]), "%s: không chồng cửa %s (sẽ bị bật lại)" % [tag, ch])
			# cô lập: bỏ nối tín hiệu của world (chuyển phòng/hazard bất đồng bộ làm nhiễu), tự ghi sự kiện
			w.room.door_entered.disconnect(w._on_door)
			w.room.hazard_touched.disconnect(w._on_hazard_touch)
			var seen: Array = []
			w.room.door_entered.connect(func(d2): seen.append("cửa " + str(d2)))
			w.room.hazard_touched.connect(func(_x): seen.append("gai"))
			var min_y: float = spawn.y
			var f0: int = Engine.get_physics_frames()
			while Engine.get_physics_frames() - f0 < 75:
				Engine.time_scale = 4.0
				await physics_frame
				min_y = maxf(min_y, w.player.global_position.y)
			ck(seen.is_empty(), "%s: không chạm %s trong 1.2s đầu" % [tag, str(seen)])
			ck(w.player.is_on_floor(), "%s: đứng được trên sàn sau 1.2s (y=%.0f)" % [tag, w.player.global_position.y])
			ck(w.room.bounds().grow(2.0).has_point(w.player.global_position), "%s: còn trong phòng (%s)" % [tag, str(w.player.global_position)])
	ck(links >= 40, "đủ số cửa để kiểm (%d)" % links)
	# phòng boss: khoá khi vào trận, mở khi hạ; chết giữa trận về bench không kẹt
	var bosses: int = 0
	for id in rooms:
		if not rooms[id].has("boss"):
			continue
		bosses += 1
		var bid: String = String(rooms[id]["boss"]["id"])
		St.flags.erase("boss_" + bid)
		w.busy = false
		w.load_room(id)
		ck(is_instance_valid(w.boss), "%s: boss %s xuất hiện khi chưa hạ" % [id, bid])
		ck(not w.room.doors.is_empty(), "%s: phòng boss có cửa ra" % id)
		w.room.locked = true
		w._on_boss_defeated(bid)
		ck(not w.room.locked and St.flag("boss_" + bid), "%s: hạ %s thì mở khoá và đặt cờ" % [id, bid])
		w.busy = false
		w.load_room(id)
		ck(w.boss == null, "%s: đã hạ boss thì không xuất hiện lại" % id)
		ck(not w.room.locked, "%s: vào lại sau khi hạ không bị khoá" % id)
		St.flags.erase("boss_" + bid)
	ck(bosses == 6, "6 phòng boss gồm 3 mini-boss (%d)" % bosses)
	# chết giữa trận boss: về bench, phòng mới không khoá
	St.flags.erase("boss_warden")
	for id in rooms:
		if rooms[id].has("boss") and rooms[id]["boss"]["id"] == "warden":
			w.busy = false
			w.load_room(id)
			w.room.locked = true
			St.bench_room = "gate_4"
			St.bench_id = "bench"
			w.player.died.emit()
			Engine.time_scale = 1.0
			await create_timer(3.5).timeout
			ck(w.room.id == "gate_4" and not w.room.locked and not w.busy, "chết giữa trận warden: về bench, không khoá, không kẹt busy")
			ck(w.player.controls_enabled and not w.player.is_dead(), "chết giữa trận: điều khiển lại được")
	# bàn thờ cần boss: ẩn khi chưa hạ, hiện khi đã hạ
	St.flags.erase("boss_wraith")
	St.flags.erase("got_wall_cling")
	var alt_room: String = ""
	for id in rooms:
		if rooms[id].has("altar") and String(rooms[id]["altar"].get("needs", "")) != "":
			alt_room = id
	ck(alt_room != "", "có bàn thờ cần boss")
	var boss_flags: Array = []
	for id in rooms:
		if rooms[id].has("boss"):
			boss_flags.append("boss_" + String(rooms[id]["boss"]["id"]))
	for id in rooms:
		for k in ["altar", "charm"]:
			if rooms[id].has(k):
				var need: String = String(rooms[id][k].get("needs", ""))
				ck(need == "" or need in boss_flags, "%s: điều kiện %s '%s' có thể đạt được (boss tồn tại)" % [id, k, need])
	if alt_room != "":
		w.busy = false
		w.load_room(alt_room)
		var it: Dictionary = {}
		for i in w.room.interactables:
			if i["kind"] == "altar":
				it = i
		ck(not w.room._visible(it), "bàn thờ cần boss ẩn khi chưa hạ boss")
		St.set_flag(String(rooms[alt_room]["altar"]["needs"]))
		ck(w.room._visible(it), "bàn thờ hiện sau khi hạ boss")
	St.delete_save()
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
