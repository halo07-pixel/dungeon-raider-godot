extends SceneTree
## Test cảm giác đánh trúng: đòn thường vs đòn nặng (hạ gục / boss) khác âm, tia lửa, độ rung; hitstop xong thì time_scale về 1; rung tắt theo tuỳ chọn.
var fails: int = 0
var fx_log: Array = []
var shakes: Array = []

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func _init() -> void:
	await process_frame
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_feel_test_save.json"
	var w := Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	await frames(60)
	var P: Node = w.player
	ck(P.HITSTOP_BIG > P.HITSTOP_HIT, "đòn nặng dừng hình lâu hơn đòn thường")
	P.fx.connect(func(k, _p, pw): fx_log.append([k, pw]))
	P.hit_landed.connect(func(s): shakes.append(s))
	w._spawn_enemy("g", P.global_position + Vector2(200, 0))   # guard hp cao: một nhát không chết
	w._spawn_enemy("c", P.global_position + Vector2(400, 0))
	await frames(2)
	var tough: Node = null
	var weak: Node = null
	for n in w._content.get_children():
		if n.is_in_group("hk_enemy"):
			if n.kind == "guard":
				tough = n
			else:
				weak = n
	tough.hp = 50
	P.attack_dir = Vector2.RIGHT
	w.sfx.history.clear()
	P._on_nail_hit(tough)
	ck("hit" in w.sfx.history and not ("hit_heavy" in w.sfx.history), "trúng thường -> 'hit' (%s)" % str(w.sfx.history))
	ck(shakes.back() == 1.0, "rung thường = 1.0")
	ck(fx_log.back()[0] == "hit" and fx_log.back()[1] < 1.0, "tia lửa nhẹ")
	await frames(2)
	ck(Engine.time_scale < 1.0, "đang hitstop")
	await create_timer(0.3, true, false, true).timeout
	ck(is_equal_approx(Engine.time_scale, 1.0), "hitstop xong -> time_scale về 1 (%s)" % Engine.time_scale)
	weak.hp = 0
	w.sfx.history.clear()
	P._on_nail_hit(weak)
	ck("hit_heavy" in w.sfx.history, "hạ gục -> 'hit_heavy'")
	ck(shakes.back() > 1.0, "rung mạnh khi hạ gục")
	ck(fx_log.back()[1] >= 1.0, "tia lửa + vòng khi hạ gục")
	await create_timer(0.3, true, false, true).timeout
	w._spawn_boss("warden", P.global_position + Vector2(300, 0))
	await frames(2)
	w.sfx.history.clear()
	w.boss.hp = 999
	P._on_nail_hit(w.boss)
	ck("hit_heavy" in w.sfx.history and shakes.back() > 1.0, "trúng boss -> nặng dù chưa chết")
	await create_timer(0.3, true, false, true).timeout
	# tuỳ chọn rung tắt: camera không nhận rung
	St.shake_on = false
	w.cam._shake = 0.0
	w.cam.shake(1.8)
	ck(w.cam._shake == 0.0, "tắt rung -> camera không rung")
	St.shake_on = true
	Engine.time_scale = 1.0
	St.delete_save()
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
