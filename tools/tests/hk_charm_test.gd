extends SceneTree
## Test bùa mới: Second Wind (+0.5s bất tử sau khi trúng), Shade Cloak (không bị hại khi dash, kể cả gai), Frugal Soul (27 Soul),
## Spring Nail (pogo +25%), bán ở shop, ngân sách ô bùa.
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
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_charm_test_save.json"
	St.give_ability("dash")
	for id in ["second_wind", "shade_cloak", "frugal_soul", "spring_nail"]:
		ck(St.CHARMS.has(id) and int(St.CHARMS[id]["cost"]) >= 1 and String(St.CHARMS[id]["desc"]) != "", "bùa %s có dữ liệu" % id)
	# số liệu suy ra
	ck(St.spell_cost() == 33 and St.iframes_bonus() == 0.0 and St.pogo_mult() == 1.0, "mặc định không đổi")
	St.give_charm("frugal_soul"); St.give_charm("second_wind"); St.give_charm("spring_nail"); St.give_charm("shade_cloak")
	ck(St.toggle_charm("frugal_soul") and St.spell_cost() == 27, "Frugal Soul: 27")
	ck(St.toggle_charm("second_wind") and is_equal_approx(St.iframes_bonus(), 0.5), "Second Wind: +0.5s")
	ck(St.toggle_charm("spring_nail") and is_equal_approx(St.pogo_mult(), 1.25), "Spring Nail: x1.25")
	ck(St.toggle_charm("shade_cloak") == false, "Shade Cloak (2 ô) không vừa khi đã đeo 3 bùa 1 ô (3 ô)")
	St.toggle_charm("frugal_soul")   # tháo để nhường ô
	St.toggle_charm("second_wind")
	ck(St.toggle_charm("shade_cloak"), "đủ chỗ thì đeo Shade Cloak")
	# người chơi
	var room := Node2D.new()
	room.set_script(load("res://hk/room.gd"))
	root.add_child(room)
	var grid: Array = []
	for r in 20:
		grid.append("#".repeat(60) if r == 19 else "#" + ".".repeat(58) + "#")
	room.build("test", {"area": "gate", "doors": {}, "grid": grid})
	var p := CharacterBody2D.new()
	p.set_script(load("res://hk/player.gd"))
	p.position = Vector2(500, 560)
	root.add_child(p)
	await frames(30)
	# Shade Cloak: dash bất khả xâm phạm
	var hurt: Array = [0]
	p.hazard_hit.connect(func(): hurt[0] += 1)
	p._dash_t = 0.1
	var hp0: int = p.hp
	p.take_damage(p.global_position.x + 20.0)
	ck(p.hp == hp0, "Shade Cloak: dash không mất máu")
	p.hazard_damage(p.global_position.x + 20.0)
	ck(p.hp == hp0 and hurt[0] == 0, "Shade Cloak: dash qua gai không mất máu, không bị đưa về chỗ an toàn")
	p._dash_t = 0.0
	p.take_damage(p.global_position.x + 20.0)
	ck(p.hp == hp0 - 1, "hết dash thì bị thương bình thường")
	# Second Wind: bất tử dài hơn
	St.toggle_charm("shade_cloak")
	St.toggle_charm("second_wind")
	p.invuln = 0.0
	p.hp = 5
	p.take_damage(0.0)
	ck(is_equal_approx(p.invuln, p.IFRAMES + 0.5), "Second Wind: bất tử %.2fs" % p.invuln)
	St.toggle_charm("second_wind")
	p.invuln = 0.0
	p.take_damage(0.0)
	ck(is_equal_approx(p.invuln, p.IFRAMES), "gỡ bùa: về %.1fs" % p.IFRAMES)
	# Frugal Soul: dùng Soul Bolt với 27 Soul
	St.toggle_charm("frugal_soul")
	St.soul = 27
	p._stun = 0.0
	p._spell_cd = 0.0
	var ev := InputEventAction.new()
	ev.action = "hk_spell"
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(4)
	ev.pressed = false
	Input.parse_input_event(ev)
	await frames(2)
	ck(St.soul == 0, "Frugal Soul: bắn bằng 27 Soul (còn %d)" % St.soul)
	# shop bán đủ
	var shop = load("res://hk/shop.gd").new()
	root.add_child(shop)
	St.charms_owned = []
	var stock: Array = shop._stock()
	var ids: Array = []
	for it in stock:
		ids.append(String(it["id"]))
	for id in ["second_wind", "shade_cloak", "frugal_soul", "spring_nail"]:
		ck(id in ids, "shop bán %s" % id)
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
