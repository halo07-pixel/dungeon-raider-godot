extends SceneTree
## Phòng khoá (đánh boss): khe cửa là tường tạm, người chơi chạy dồn về phía cửa vẫn ở trong phòng; mở khoá thì đi qua cửa được; chốt an toàn đưa người ra ngoài về cửa.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func hold(action: String, on: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = on
	Input.parse_input_event(ev)

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_door_lock_save.json"
	St.delete_save()
	St.nightmare = false
	var w := Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	for i in 10:
		await process_frame
	for rid in ["gate_6", "cat_8", "vault_7", "arc_5", "grove_5", "cat_6"]:
		w.busy = false
		w.load_room(rid)
		await process_frame
		await process_frame
		var d0: String = String(w.room.doors.keys()[0])
		var dr: Rect2 = w.room.doors[d0]
		var b: Rect2 = w.room.bounds()
		var act: String = "hk_left" if dr.get_center().x < b.get_center().x else "hk_right"
		w.player.respawn_at(w.room.spawn_for_door(d0))
		w.player.controls_enabled = true
		for i in 20:
			await physics_frame
		w.room.locked = true
		hold(act, true)
		for i in 150:
			await physics_frame
		hold(act, false)
		ck(b.has_point(w.player.global_position), "%s: khoá cửa, người chơi vẫn trong phòng (%s)" % [rid, w.player.global_position])
		# chốt an toàn: đặt ra ngoài phòng thì về cửa
		w.player.global_position = Vector2(-900, b.end.y + 900)
		await physics_frame
		await physics_frame
		ck(b.grow(64.0).has_point(w.player.global_position), "%s: ra ngoài phòng khi khoá thì đưa về" % rid)
		# mở khoá: tường tạm hết đặc
		w.room.locked = false
		await physics_frame
		await physics_frame
		ck(w.room._door_wall.collision_layer == 0, "%s: mở khoá thì tường tạm tắt" % rid)
	print("DONE fails=", fails)
	quit(fails)
