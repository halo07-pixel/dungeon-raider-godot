extends SceneTree
## HUD và chữ: mất/hồi mặt nạ kích hoạt hiệu ứng, soul tăng nháy, Geo đếm dần + "+N", thanh máu boss lớn (trượt mượt, gỡ khi boss mất),
## vẽ không lỗi; tab Charms báo lý do không đeo được; gợi ý tương tác có chữ cho mọi loại vật.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout

func press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	ev.pressed = false
	Input.parse_input_event(ev)
	await process_frame

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_hud_save.json"
	var hud := Control.new()
	hud.set_script(load("res://hk/hud.gd"))
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(hud)
	await wait(0.2)
	# mặt nạ
	hud.set_health(5, 5)
	ck(hud._hurt == 0.0 and hud._pop == 0.0, "đặt máu bằng cũ: không hiệu ứng")
	hud.set_health(4, 5)
	ck(hud._hurt > 0.0, "mất mặt nạ -> chớp")
	await wait(0.6)
	ck(hud._hurt == 0.0, "hiệu ứng mất mặt nạ tự hết")
	hud.set_health(5, 5)
	ck(hud._pop > 0.0, "hồi mặt nạ -> phồng")
	# soul
	hud.set_soul(0)
	hud.set_soul(33)
	ck(hud._soul_flash > 0.0, "nhận soul -> nháy")
	await wait(0.5)
	hud.set_soul(10)
	ck(hud._soul_flash == 0.0, "tiêu soul không nháy")
	# Geo đếm dần và +N
	St.geo = 0
	await wait(0.2)
	St.geo = 500
	await process_frame
	await process_frame
	ck(hud.geo > 0 and hud.geo < 500 and hud._geo_gain == 500, "Geo tăng: đếm dần (%d), +500" % hud.geo)
	await wait(1.5)
	ck(hud.geo == 500, "Geo đếm tới đủ (%d)" % hud.geo)
	St.geo = 100
	await process_frame
	await process_frame
	ck(hud.geo == 100, "Geo giảm (mua đồ/chết): hiện ngay (%d)" % hud.geo)
	await wait(1.4)
	ck(hud._geo_gain == 0, "+N tự hết")
	# thanh máu boss
	var fake := Node2D.new()
	fake.set_script(GDScript.new())
	var src := GDScript.new()
	src.source_code = "extends Node2D\nvar hp: int = 100\nvar max_hp: int = 100\nvar state: String = \"idle\"\nfunc title() -> String:\n\treturn \"Test Boss\"\n"
	src.reload()
	fake.free()
	fake = Node2D.new()
	fake.set_script(src)
	root.add_child(fake)
	hud.boss = fake
	await wait(0.2)
	ck(absf(hud._boss_frac - 1.0) < 0.01, "boss đầy máu: thanh đầy")
	fake.hp = 50
	await wait(0.1)
	ck(hud._boss_frac < 1.0 and hud._boss_frac > 0.5, "thanh trượt mượt (%.2f)" % hud._boss_frac)
	await wait(0.8)
	ck(absf(hud._boss_frac - 0.5) < 0.01, "thanh tới đúng mức máu")
	fake.hp = 1
	fake.state = "dormant"
	await wait(0.2)   # vẽ cả hai trạng thái không lỗi
	fake.free()
	await wait(0.2)
	ck(not is_instance_valid(hud.boss) and hud._boss_frac == 1.0, "boss bị giải phóng: thanh gỡ, không lỗi")
	hud.banner("Test", "sub")
	await wait(0.6)
	hud.free()
	# menu Charms: lý do không đeo được
	St.reset()
	var menu = load("res://hk/menu.gd").new()
	root.add_child(menu)
	await process_frame
	menu.open("charms")
	await process_frame
	menu.sel = 0
	await press("hk_jump")
	ck(menu._msg.contains("not found"), "bùa chưa có: báo chưa tìm thấy (%s)" % menu._msg)
	await press("hk_down")
	ck(menu._msg == "", "đổi dòng xoá thông báo")
	St.give_charm("heavy_blow")
	St.give_charm("quick_focus")
	var keys: Array = St.CHARMS.keys()
	menu.sel = keys.find("heavy_blow")
	await press("hk_jump")
	ck(menu._msg == "" and "heavy_blow" in St.charms_equipped, "đeo được: không thông báo")
	menu.sel = keys.find("quick_focus")
	await press("hk_jump")
	ck(menu._msg.contains("notches") and not ("quick_focus" in St.charms_equipped), "thiếu ô: báo không đủ ô (%s)" % menu._msg)
	# gợi ý tương tác có chữ cho mọi loại
	var Room = load("res://hk/room.gd")
	for k in ["bench", "merchant", "altar", "charm", "cache"]:
		ck(Room.PROMPTS.has(k) and String(Room.PROMPTS[k]) != "", "gợi ý có chữ cho %s" % k)
	St.delete_save()
	print("hk_hud_test: ", "OK" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails > 0 else 0)
