extends SceneTree
## Test đỡ đòn: cửa sổ thời gian, đỡ trượt khựng, đỡ trúng không mất mặt nạ + Soul, vùng gây hại không đỡ được, đạn bị phản,
## quái choáng, boss choáng có trần 6s, đỡ đi trước Oath Ward.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func tap(action: String, n: int = 3) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(n)
	ev.pressed = false
	Input.parse_input_event(ev)

func _init() -> void:
	await process_frame
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_parry_test_save.json"
	var w := Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	await frames(60)
	var P: Node = w.player
	ck(InputMap.has_action("hk_parry"), "có phím hk_parry")
	# 1) không bấm: trúng đòn bình thường
	P.invuln = 0.0
	P.hp = P.max_hp
	var hp0: int = P.hp
	ck(P.take_damage(P.global_position.x - 40.0) == false and P.hp == hp0 - 1, "không đỡ -> mất 1 mặt nạ, trả false")
	await frames(60)
	P.invuln = 0.0
	# 2) đỡ trúng
	var soul0: int = St.soul
	var got: Array = []
	P.parried.connect(func(x): got.append(x))
	await tap("hk_parry")
	ck(P._parry_t > 0.0, "bấm phím mở cửa sổ đỡ")
	var hp1: int = P.hp
	ck(P.take_damage(P.global_position.x - 40.0) == true, "đòn trong cửa sổ -> trả true")
	ck(P.hp == hp1, "đỡ trúng không mất mặt nạ")
	ck(St.soul == mini(St.SOUL_MAX, soul0 + P.PARRY_SOUL), "đỡ trúng cộng Soul (%d -> %d)" % [soul0, St.soul])
	ck(got.size() == 1 and P.invuln >= P.PARRY_INVULN, "phát signal parried, có bất tử ngắn")
	ck(P._parry_rec == 0.0, "đỡ trúng được đỡ lại ngay (không khựng)")
	await create_timer(0.3, true, false, true).timeout
	P.invuln = 0.0
	# 3) đỡ trượt: hết cửa sổ rồi mới bị đánh -> mất mặt nạ; bấm lại trong lúc khựng vô tác dụng
	await tap("hk_parry")
	await create_timer(P.PARRY_WINDOW + 0.1, true, false, true).timeout
	var hp2: int = P.hp
	P.take_damage(P.global_position.x - 40.0)
	ck(P.hp == hp2 - 1, "đỡ trượt (quá cửa sổ) -> mất mặt nạ")
	await frames(30)
	P.invuln = 0.0
	P._parry_rec = 0.3
	P._parry_t = 0.0
	await tap("hk_parry")
	ck(P._parry_t == 0.0, "đang khựng sau đỡ trượt: bấm không mở cửa sổ")
	P._parry_rec = 0.0
	P.hp = P.max_hp   # tránh chết giữa chừng (world sẽ nạp lại phòng và giải phóng quái thử)
	# 4) vùng gây hại / gai: không đỡ được dù đang trong cửa sổ
	P._parry_t = 0.1
	var hp3: int = P.hp
	P.take_damage(P.global_position.x, 1, false)
	ck(P.hp == hp3 - 1, "take_damage(parryable=false) không đỡ được")
	await frames(30)
	P.invuln = 0.0
	P._parry_t = 0.1
	var hp4: int = P.hp
	P.hazard_damage(P.global_position.x)
	ck(P.hp == hp4 - 1, "gai (hazard_damage) không đỡ được")
	await frames(30)
	P.invuln = 0.0
	P._parry_t = 0.0
	P.hp = P.max_hp
	# 5) đạn của quái: đỡ trúng thì bị phản lại
	var pr := Area2D.new()
	pr.set_script(load("res://hk/projectile.gd"))
	pr.friendly = false
	pr.vel = Vector2(-200, 0)
	w._content.add_child(pr)
	pr.global_position = P.global_position + Vector2(30, 0)
	await frames(1)
	P._parry_t = 0.15
	P.invuln = 0.0
	var hp5: int = P.hp
	pr._on_body(P)
	ck(is_instance_valid(pr) and not pr.is_queued_for_deletion() and pr.friendly and pr.vel.x > 0.0, "đạn bị đỡ -> phản lại (friendly, vận tốc đảo)")
	ck(P.hp == hp5, "đạn bị đỡ không gây sát thương")
	pr.queue_free()   # đạn đã phản không được bay trúng quái thử ở bước sau
	await create_timer(0.3, true, false, true).timeout
	P.invuln = 0.0
	# đạn không đỡ -> trúng và biến mất
	var pr2 := Area2D.new()
	pr2.set_script(load("res://hk/projectile.gd"))
	w._content.add_child(pr2)
	await frames(1)
	var hp6: int = P.hp
	pr2._on_body(P)
	ck(P.hp == hp6 - 1 and pr2.is_queued_for_deletion(), "đạn không bị đỡ: gây 1 sát thương và biến mất")
	await frames(30)
	P.hp = P.max_hp
	# 6) quái choáng
	P.invuln = 0.0
	for old in w.get_tree().get_nodes_in_group("hk_enemy"):   # chỉ để lại quái thử, không để quái khác của phòng làm nhiễu
		old.queue_free()
	await frames(2)
	w._spawn_enemy("h", P.global_position + Vector2(80, 0))   # charger
	await frames(2)
	var en: Node = null
	for n in w._content.get_children():
		if n.is_in_group("hk_enemy"):
			en = n
	ck(en != null, "có quái để thử")
	en.stagger(0.6)
	ck(en.state == "stagger", "quái bị choáng")
	await frames(10)
	P.invuln = 0.0
	var hp7: int = P.hp
	P.global_position = en.global_position
	await frames(3)
	ck(P.hp == hp7, "quái đang choáng không gây hại chạm")
	await create_timer(0.8, true, false, true).timeout
	ck(en.state != "stagger", "quái hết choáng")
	P.invuln = 0.0
	await frames(5)
	ck(P.hp < hp7, "đối chứng: hết choáng thì chạm lại gây hại (hp %d -> %d)" % [hp7, P.hp])
	P.hp = P.max_hp
	# 7) boss choáng, trần 6s
	w._spawn_boss("warden", P.global_position + Vector2(900, 0))
	await frames(2)
	var b: Node = w.boss
	b.state = "dormant"
	b.stagger(0.8)
	ck(b.state == "dormant", "boss đang ngủ: không choáng")
	b.state = "walk"
	b.stagger(0.8)
	ck(b.state == "stagger", "boss bị choáng")
	b._t = 0.0
	await frames(3)
	ck(b.state != "stagger", "boss hết choáng thì chọn đòn mới (%s)" % b.state)
	b.state = "walk"
	b.stagger(0.8)
	ck(b.state == "walk", "choáng lần hai trong 6s bị chặn")
	b._stagger_cd = 0.0
	b.stagger(0.8)
	ck(b.state == "stagger", "hết trần 6s thì choáng lại được")
	# 8) world: đỡ làm kẻ gần đó choáng
	b.state = "walk"
	b._stagger_cd = 0.0
	b.global_position = P.global_position + Vector2(60, 0)
	P.invuln = 0.0
	P._parry_t = 0.15
	P.take_damage(b.global_position.x)
	ck(b.state == "stagger", "đỡ đòn của boss đứng cạnh -> world gọi stagger")
	await create_timer(0.3, true, false, true).timeout
	# 9) đỡ đi trước Oath Ward (ward không bị tiêu hao)
	St.give_charm("oath_ward")
	St.charms_equipped = ["oath_ward"]
	P.ward_ready = true
	P.invuln = 0.0
	P._parry_t = 0.15
	P.take_damage(P.global_position.x - 40.0)
	ck(P.ward_ready, "đỡ trúng không tiêu hao Oath Ward")
	Engine.time_scale = 1.0
	St.delete_save()
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
