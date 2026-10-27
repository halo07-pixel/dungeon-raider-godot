extends SceneTree
## Test khớp hình–hộp: hộp thật của quái/boss/người chơi suy ra từ sprite, vùng tương tác bao quanh phần nhìn thấy, vùng chém hợp lý.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	var WD = load("res://hk/world_data.gd")
	var EN = load("res://hk/enemy.gd")
	var BO = load("res://hk/boss.gd")
	var PL = load("res://hk/player.gd")
	var B = load("res://hk/bodies.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_align_save.json"
	# quái/boss: hộp = bbox sprite nhìn thấy x hệ số
	for k in EN.LOOK:
		var look: Dictionary = EN.LOOK[k]
		var want: Vector2 = B.rect(String(look["anim"]), float(look["scale"])).size
		ck(EN.body_size(k).is_equal_approx(want), "enemy %s: hộp = sprite" % k)
		ck(want.x > 8 and want.y > 8, "enemy %s: kích thước hợp lý" % k)
	for k in BO.LOOK:
		var look: Dictionary = BO.LOOK[k]
		ck(BO.body_size(k).is_equal_approx(B.rect(String(look["anim"]), float(look["scale"])).size), "boss %s: hộp = sprite" % k)
	# người chơi: hộp 24x44 đúng bằng sprite hiệp sĩ đứng (±4px) và đáy = chân
	var kn: Vector2 = B.rect("knight_m_idle_anim", 2.0).size
	ck(absf(kn.x - PL.BODY.x) <= 8.0 and absf(kn.y - PL.BODY.y) <= 6.0, "player: BODY gần sprite (%s vs %s)" % [kn, PL.BODY])
	ck(is_equal_approx(PL.FOOT, PL.BODY.y * 0.5), "player: FOOT = BODY.y/2")
	# vùng tương tác bao trọn phần nhìn thấy, ở mọi phòng
	var rooms: Dictionary = WD.load_all()
	var n: int = 0
	for id in rooms:
		var room := Node2D.new()
		room.set_script(load("res://hk/room.gd"))
		root.add_child(room)
		room.build(id, rooms[id])
		for it in room.interactables:
			n += 1
			var vis: Rect2 = it["vis"]
			ck(vis.size.x > 4 and vis.size.y > 4, "%s/%s: vis có kích thước" % [id, it["kind"]])
			ck(Rect2(it["rect"]).encloses(vis), "%s/%s: vùng tương tác bao vis" % [id, it["kind"]])
			ck(Rect2(it["rect"]).size.x <= vis.size.x + 80.0, "%s/%s: vùng tương tác không quá rộng" % [id, it["kind"]])
		room.queue_free()
	ck(n >= 20, "có vật tương tác để kiểm tra (%d)" % n)
	# vùng chém: tầm với và bề cao quanh 60–110 x 40–90
	var p := CharacterBody2D.new()
	p.set_script(PL)
	root.add_child(p)
	await process_frame
	var ar: Rect2 = p.attack_rect()
	ck(ar.size.x >= 60 and ar.size.x <= 110 and ar.size.y >= 40 and ar.size.y <= 90, "vùng chém hợp lý %s" % ar.size)
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
