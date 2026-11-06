extends SceneTree
## Guard/sentry ngẩng khiên khi người chơi pogo trên đầu: báo hiệu (chưa chặn) -> khiên chặn từ trên xuống -> hạ khiên -> nghỉ -> ngẩng lại.
## Đòn từ sau lưng luôn trúng; người chơi ở dưới/ngoài tầm thì không ngẩng.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func make(room_kind: String, at: Vector2) -> CharacterBody2D:
	var e := CharacterBody2D.new()
	e.set_script(load("res://hk/enemy.gd"))
	e.kind = room_kind
	e.position = at
	root.add_child(e)
	return e

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.nightmare = false
	St.save_path = "user://hk_guard_overhead_test_save.json"
	var room := Node2D.new()
	room.set_script(load("res://hk/room.gd"))
	root.add_child(room)
	var grid: Array = []
	for r in 20:
		grid.append("#".repeat(60) if r == 19 else "#" + ".".repeat(58) + "#")
	room.build("test", {"area": "gate", "doors": {}, "grid": grid})
	var p := CharacterBody2D.new()
	p.set_script(load("res://hk/player.gd"))
	p.position = Vector2(300, 560)
	root.add_child(p)
	await frames(30)
	var E = load("res://hk/enemy.gd")
	for kind in ["guard", "sentry"]:
		var g := make(kind, Vector2(900, 560))
		await frames(30)
		g.dir = -1
		# người chơi ở dưới/xa: không ngẩng
		p.global_position = Vector2(g.global_position.x - 600.0, g.global_position.y)
		await frames(30)
		ck(g._ovh_tell <= 0.0 and g._shield_up_t <= 0.0, "%s: người chơi ở xa thì không ngẩng khiên" % kind)
		# đứng trên đầu: sau OVERHEAD_SEE thì báo hiệu
		var t: int = 0
		while g._ovh_tell <= 0.0 and t < 60:
			p.global_position = Vector2(g.global_position.x - 20.0, g.global_position.y - g._size.y * 0.5 - 110.0)
			p.velocity = Vector2.ZERO
			await frames(1)
			t += 1
		ck(g._ovh_tell > 0.0 and t >= int(E.OVERHEAD_SEE * 60.0) - 3, "%s: báo hiệu sau ~%.1fs trên đầu (%d khung)" % [kind, E.OVERHEAD_SEE, t])
		var hp0: int = g.hp
		ck(g._shield_up_t <= 0.0 and g.take_hit(2, Vector2(g.global_position.x - 20.0, g.global_position.y - g._size.y * 0.5 - 110.0)) == true and g.hp == hp0 - 2, "%s: trong lúc báo hiệu khiên CHƯA chặn, chém trúng" % kind)
		# hết báo hiệu: khiên ngẩng, chặn từ trên xuống
		t = 0
		while g._shield_up_t <= 0.0 and t < 60:
			p.global_position = Vector2(g.global_position.x - 20.0, g.global_position.y - g._size.y * 0.5 - 110.0)
			await frames(1)
			t += 1
		ck(g._shield_up_t > 0.0, "%s: sau báo hiệu khiên ngẩng" % kind)
		ck(g.take_hit(2, Vector2(g.global_position.x - 20.0, g.global_position.y - g._size.y * 0.5 - 110.0)) == false and g.hp == hp0 - 2, "%s: khiên ngẩng chặn đòn từ trên xuống" % kind)
		ck(g.take_hit(2, Vector2(g.global_position.x + 60.0, g.global_position.y)) == true, "%s: đòn từ sau lưng vẫn trúng" % kind)
		ck(g.take_hit(2, Vector2(g.global_position.x - 300.0, g.global_position.y - g._size.y * 0.5 - 150.0)) == true, "%s: từ trên nhưng lệch xa thì trúng" % kind)
		# nhảy chém chéo từ phía trước (xa hơn OVERHEAD_X, thấp hơn OVERHEAD_H) bị chặn; cao quá thì không
		ck(g.take_hit(2, Vector2(g.global_position.x - 85.0, g.global_position.y - 34.0)) == false, "%s: nhảy chém chéo phía trước bị chặn" % kind)
		ck(g.take_hit(2, Vector2(g.global_position.x - 85.0, g.global_position.y - 160.0)) == true, "%s: đứng quá cao (> %.0fpx) thì không bị chặn" % [kind, E.OVERHEAD_H])
		# hạ khiên sau SHIELD_UP, rồi nghỉ SHIELD_CD không ngẩng lại
		p.global_position = Vector2(g.global_position.x - 600.0, g.global_position.y)
		t = 0
		while g._shield_up_t > 0.0 and t < 200:
			await frames(1)
			t += 1
		ck(g._shield_up_t <= 0.0 and absf(float(t) / 60.0 - E.SHIELD_UP) < 0.35, "%s: khiên hạ sau ~%.1fs (%.2fs)" % [kind, E.SHIELD_UP, float(t) / 60.0])
		ck(g.take_hit(2, Vector2(g.global_position.x - 20.0, g.global_position.y - g._size.y * 0.5 - 110.0)) == true, "%s: hạ khiên rồi thì chém từ trên trúng" % kind)
		var cd_left: float = g._shield_cd
		ck(cd_left > E.SHIELD_CD - 0.4 and cd_left <= E.SHIELD_CD + 0.05, "%s: nghỉ ~%.1fs trước khi ngẩng lại (%.2f)" % [kind, E.SHIELD_CD, cd_left])
		t = 0
		while t < int((E.SHIELD_CD - 0.3) * 60.0):
			p.global_position = Vector2(g.global_position.x - 20.0, g.global_position.y - g._size.y * 0.5 - 110.0)
			await frames(1)
			t += 1
		ck(g._ovh_tell <= 0.0 and g._shield_up_t <= 0.0, "%s: đang nghỉ thì không ngẩng lại" % kind)
		t = 0
		while g._ovh_tell <= 0.0 and t < 120:
			p.global_position = Vector2(g.global_position.x - 20.0, g.global_position.y - g._size.y * 0.5 - 110.0)
			await frames(1)
			t += 1
		ck(g._ovh_tell > 0.0, "%s: hết nghỉ thì ngẩng lại" % kind)
		g.queue_free()
		await frames(3)
	print("hk_guard_overhead_test: ", "OK" if fails == 0 else "%d lỗi" % fails)
	print("DONE fails=", fails)
	quit()
