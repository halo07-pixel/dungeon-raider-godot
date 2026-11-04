extends SceneTree
## Khu 5 Toxic Grove: bảng theo khu đầy đủ, phòng + bào tử đọc đúng, zone spore theo nhịp (và Spore Ward), sporeling nổ bào tử khi chết,
## thornshooter bắn ba gai, boss Rotted Warden (wind_bloom, wind_vine), bùa spore_ward gắn với dash.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func zones(parent: Node, kind: String) -> Array:
	var out: Array = []
	for c in parent.get_children():
		if c.get("kind") == kind and c.has_method("current"):
			out.append(c)
	return out

func tap(a: String) -> void:
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	ev = InputEventAction.new()
	ev.action = a
	ev.pressed = false
	Input.parse_input_event(ev)
	await process_frame

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_grove_test_save.json"
	St.delete_save()
	var WD = load("res://hk/world_data.gd")
	var EN = load("res://hk/enemy.gd")
	var BO = load("res://hk/boss.gd")
	var ZN = load("res://hk/zone.gd")
	var LORE = load("res://hk/lore.gd")
	var RM = load("res://hk/room.gd")
	# --- bảng theo khu
	var wsrc: String = FileAccess.get_file_as_string("res://hk/world.gd")
	ck(wsrc.contains('"grove": "Toxic Grove"') and wsrc.contains('"grove": "dirt"'), "world: AREA_NAMES + SURFACE có grove")
	ck(RM.PALETTES.has("grove") and RM.BG_DIM.has("grove") and RM.TILESET.has("grove"), "room: PALETTES/BG_DIM/TILESET có grove")
	ck(load("res://hk/menu.gd").AREA_COLORS.has("grove"), "menu: AREA_COLORS có grove")
	ck(load("res://hk/music.gd").AREA_TRACK.has("grove"), "music: AREA_TRACK có grove")
	ck(load("res://hk/atmosphere.gd").AREAS.has("grove"), "atmosphere: AREAS có grove")
	var amb: Color = load("res://hk/atmosphere.gd").AREAS["grove"]["ambient"]
	ck(amb.r >= 0.7 and amb.g >= 0.7 and amb.b >= 0.7, "ambient grove không tối hơn 0.7")
	ck(load("res://hk/backdrop.gd").COLORS.has("grove"), "backdrop: có grove")
	ck(load("res://hk/sfx.gd").LOOPS.has("amb_grove"), "sfx: có amb_grove")
	ck(LORE.DEATH.has("grove"), "lore: có dòng chết grove")
	ck(load("res://hk/shop.gd").AREA_CHARMS.has("grove") and load("res://hk/shop.gd").AREA_TIER.has("grove"), "shop: có grove")
	for s in ["tell_bloom", "tell_vine"]:
		ck(load("res://hk/sfx.gd").DEFS.has(s), "có âm " + s)
	ck(St.CHARMS.has("spore_ward"), "có bùa spore_ward")
	ck(LORE.line("grove", "intro") != "" and LORE.line("grove", "memory") != "", "lore: Rotted Warden có câu vào trận và ký ức")
	ck(LORE.MEMORIES.size() == 6, "6 ký ức giữ nguyên (grove là bonus, không đổi điều kiện ending)")
	# --- phòng thật
	var rooms: Dictionary = WD.load_all()
	for i in range(1, 6):
		ck(rooms.has("grove_%d" % i) and rooms["grove_%d" % i]["area"] == "grove", "có phòng grove_%d" % i)
	ck(rooms["arc_3"]["doors"].get("3", {}).get("to", "") == "grove_1" and rooms["grove_1"]["doors"]["1"]["to"] == "arc_3", "arc_3 <-> grove_1 nối hai chiều")
	var nsp: int = 0
	var chars: Dictionary = {}
	for i in range(1, 6):
		var r: Dictionary = rooms["grove_%d" % i]
		nsp += r["spores"].size()
		for row in r["grid"]:
			for ch in String(row):
				chars[ch] = true
	ck(nsp >= 6, "phòng grove có đám bào tử (%d)" % nsp)
	ck(chars.has("m") and chars.has("t"), "phòng grove có sporeling (m) và thornshooter (t)")
	ck(rooms["grove_5"]["boss"]["id"] == "grove" and rooms["grove_5"]["charm"]["id"] == "spore_ward", "grove_5: boss + bùa")
	# --- dựng phòng thử + người chơi
	var room := Node2D.new()
	room.set_script(RM)
	root.add_child(room)
	var grid: Array = []
	for r in 20:
		grid.append("#".repeat(60) if r == 19 else "#" + ".".repeat(58) + "#")
	room.build("test", {"area": "grove", "doors": {}, "grid": grid})
	var p := CharacterBody2D.new()
	p.set_script(load("res://hk/player.gd"))
	root.add_child(p)
	p.set_physics_process(false)
	var floor_y: float = 19.0 * 32.0
	p.global_position = Vector2(900, floor_y - 22.0)
	# --- zone spore theo nhịp
	var z := Node2D.new()
	z.set_script(ZN)
	z.kind = "spore"
	z.rect = Rect2(800, floor_y - 64.0, 200, 64)
	z.life = 1.0e9
	z.period = 3.0
	z.on_from = 1.5
	z.fx_parent = root
	root.add_child(z)
	p.hp = p.max_hp
	p.invuln = 0.0
	await frames(8)
	ck(p.hp == p.max_hp, "bào tử pha tắt (0..1.5s): không gây hại")
	z._t = 1.6
	await frames(3)
	ck(p.hp < p.max_hp, "bào tử pha bật: gây hại (hp %d)" % p.hp)
	p.hp = p.max_hp
	p.invuln = 0.0
	p.spore_t = 1.0
	await frames(3)
	ck(p.hp == p.max_hp, "đang có spore_t (Spore Ward): bào tử không gây hại")
	p.spore_t = 0.0
	z._t = 3.2   # sang chu kỳ mới (pha tắt)
	await frames(3)
	ck(p.hp == p.max_hp, "chu kỳ sau: lại tắt")
	z.queue_free()
	# --- sporeling: chết thì nổ bào tử (0.5s mờ, rồi gây hại, hết sau SPORE_BURST)
	var sp := CharacterBody2D.new()
	sp.set_script(EN)
	sp.kind = "sporeling"
	sp.position = Vector2(1500, floor_y - EN.body_size("sporeling").y * 0.5)
	root.add_child(sp)
	await frames(3)
	p.hp = p.max_hp
	p.invuln = 0.0
	sp.take_hit(999, Vector2(1450, floor_y))
	p.global_position = Vector2(1500, floor_y - 22.0)   # đứng đúng chỗ bào tử nổ
	await frames(4)
	var bz: Array = zones(root, "spore")
	ck(bz.size() == 1, "sporeling chết: tạo 1 đám bào tử (%d)" % bz.size())
	ck(p.hp == p.max_hp, "đám bào tử mới nổ: 0.5s đầu chỉ là mây mờ")
	await frames(50)
	ck(p.hp < p.max_hp, "sau 0.5s: gây hại (hp %d)" % p.hp)
	await frames(120)
	ck(zones(root, "spore").is_empty(), "đám bào tử nổ tự tan sau %.1fs" % EN.SPORE_BURST)
	# --- thornshooter: ba gai
	for c in root.get_children():
		if c.get("friendly") != null and c.get("vel") != null:
			c.free()
	var th := CharacterBody2D.new()
	th.set_script(EN)
	th.kind = "thornshooter"
	th.position = Vector2(1300, floor_y - EN.body_size("thornshooter").y * 0.5)
	root.add_child(th)
	await frames(3)
	th.state = "windup"
	th._t = 0.0
	await frames(3)
	var thorns: int = 0
	for c in root.get_children():
		if c.get("friendly") == false and c.get("vel") != null:
			thorns += 1
	ck(thorns == 3, "thornshooter bắn 3 gai (%d)" % thorns)
	th.free()
	for c in root.get_children():
		if c.get("friendly") != null and c.get("vel") != null:
			c.free()
	# --- boss Rotted Warden
	ck(BO.DATA["grove"]["hp"] == 140 and BO.SKILL["grove"] == "wind_bloom" and BO.BOUNTY["grove"] == 60, "số liệu Rotted Warden: hp 140, wind_bloom, bounty 60")
	var b := CharacterBody2D.new()
	b.set_script(BO)
	b.kind = "grove"
	b.position = Vector2(1500, floor_y - 100.0)
	root.add_child(b)
	b.arena = room.bounds()
	await frames(5)
	b.state = "walk"
	b._t = 99.0
	b.global_position = Vector2(1500, floor_y - b._size.y * 0.5 - 1.0)
	b.state = "wind_bloom"
	b._t = 0.0
	await frames(3)
	ck(zones(b, "spore").size() == 6, "wind_bloom pha 1: 5 cụm + 1 đợt hai (%d)" % zones(b, "spore").size())
	b.state = "wind_vine"
	b._t = 0.0
	await frames(3)
	ck(zones(b, "vine").size() == 9, "wind_vine pha 1: 6 dây + 3 dây hàng nhẹ (%d)" % zones(b, "vine").size())
	b.phase = 2
	b.state = "wind_bloom"
	b._t = 0.0
	await frames(3)
	ck(zones(b, "spore").size() == 19, "wind_bloom pha 2: thêm 13 cụm (7 + 6 đợt hai; cộng 6 cụm pha 1 còn lại) (%d)" % zones(b, "spore").size())
	for zs in zones(b, "spore"):
		zs.free()
	b.phase = 1
	# grove vào pha 2 ở 66% máu (warden: 50%)
	b.hp = b.max_hp * 2 / 3 + 1
	b.state = "walk"
	b.take_hit(1, Vector2.ZERO)
	ck(b.phase == 2, "grove vào pha 2 ở ~66%% máu (phase %d, hp %d)" % [b.phase, b.hp])
	b.phase = 1
	b.state = "walk"
	for zq in zones(b, "vine"):   # pha 2: thêm hàng dây thứ hai (6 + 6), hàng sau xuất hiện muộn hơn và lệch khe
		zq.free()
	b.phase = 2
	b.state = "wind_vine"
	b._t = 0.0
	await frames(3)
	var vz: Array = zones(b, "vine")
	var maxd: float = 0.0
	for zv in vz:
		maxd = maxf(maxd, zv.delay)
	ck(vz.size() == 12 and maxd > 1.9, "wind_vine pha 2: 12 dây, hàng sau muộn (%d dây, delay tối đa %f)" % [vz.size(), maxd])
	for zv in vz:
		zv.free()
	b.phase = 1
	var vines: int = 0
	var blooms: int = 0
	for i in 300:
		b.state = "walk"
		b.phase = 1 if i < 150 else 2
		b._pick_attack()
		if b.state == "wind_vine":
			vines += 1
		if b.state == "wind_bloom":
			blooms += 1
	ck(vines > 0 and blooms > 0, "chọn đòn: có cả vine (%d) và bloom (%d)" % [vines, blooms])
	b.free()
	# --- Spore Ward gắn với dash
	St.give_ability("dash")
	St.give_charm("spore_ward")
	ck(St.toggle_charm("spore_ward"), "đeo được spore_ward")
	p.set_physics_process(true)
	p.global_position = Vector2(400, floor_y - 22.0)
	p.controls_enabled = true
	await frames(10)
	ck(p.spore_t == 0.0, "chưa dash: spore_t = 0")
	p._stun = 0.0   # đòn bào tử trước đó để lại choáng ngắn
	p.can_dash = true   # dash có thể còn hồi/đang ở trạng thái sau đòn trước: đặt sạch để test không phụ thuộc nhịp
	p._dash_cd = 0.0
	var dev := InputEventAction.new()   # giữ phím qua vài khung vật lý để chắc chắn có một tick thấy just_pressed
	dev.action = "hk_dash"
	dev.pressed = true
	Input.parse_input_event(dev)
	await process_frame
	await frames(3)
	var drel := InputEventAction.new()
	drel.action = "hk_dash"
	drel.pressed = false
	Input.parse_input_event(drel)
	ck(p.spore_t > 0.0 and p.spore_t <= p.DASH_TIME + p.SPORE_WARD_TAIL + 0.001, "dash với Spore Ward: spore_t trong (0, %.2f] (%f)" % [p.DASH_TIME + p.SPORE_WARD_TAIL, p.spore_t])
	await frames(70)
	ck(p.spore_t == 0.0, "hết tail: spore_t về 0")
	St.charms_equipped.erase("spore_ward")
	p._dash_cd = 0.0
	p._stun = 0.0
	p.can_dash = true
	await tap("hk_dash")
	ck(p.spore_t == 0.0, "không đeo bùa: dash không đặt spore_t")
	print("hk_grove_test: ", "OK" if fails == 0 else "%d lỗi" % fails)
	print("DONE fails=", fails)
	quit(fails)
