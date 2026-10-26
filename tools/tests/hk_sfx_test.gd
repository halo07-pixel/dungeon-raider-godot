extends SceneTree
## Test âm thanh HK: mọi âm tổng hợp ra dữ liệu; các sự kiện thật (nhảy, chém, dash, bị đánh, quái chết, nhặt, shop, boss) gọi đúng tên âm.
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
	await frames(2)

func _init() -> void:
	await process_frame
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_sfx_test_save.json"
	St.give_ability("dash")
	var SFX = load("res://hk/sfx.gd")
	var s: Node = SFX.new()
	root.add_child(s)
	await process_frame
	for n in SFX.DEFS:
		var st: AudioStreamWAV = s._sounds.get(n)
		ck(st != null and st.data.size() > 200, "âm '%s' có dữ liệu" % n)
	var w := Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	await frames(60)
	w.sfx.history.clear()
	await tap("hk_jump", 4)
	ck("jump" in w.sfx.history, "nhảy -> 'jump' (%s)" % str(w.sfx.history))
	await frames(80)
	await tap("hk_attack", 2)
	ck("slash" in w.sfx.history, "chém -> 'slash'")
	await frames(30)
	await tap("hk_dash", 2)
	ck("dash" in w.sfx.history, "dash -> 'dash'")
	await frames(60)
	w.player.invuln = 0.0
	w.player.take_damage(w.player.global_position.x - 50.0)
	ck("hurt" in w.sfx.history, "bị đánh -> 'hurt'")
	w.shop.open(w.player)
	St.geo = 0
	w.shop._buy(w.shop._items[0])
	ck("deny" in w.sfx.history, "thiếu Geo -> 'deny'")
	St.geo = 5000
	w.shop._buy(w.shop._items[0])
	ck("buy" in w.sfx.history, "mua -> 'buy'")
	w.shop.close()
	w._on_interacted("cache", {"key": "t", "pos": Vector2.ZERO})
	ck("geo" in w.sfx.history, "rương -> 'geo'")
	w._on_interacted("altar", {"id": "double_jump"})
	ck("ability" in w.sfx.history, "bàn thờ -> 'ability'")
	w._on_interacted("charm", {"id": "fury"})
	ck("charm" in w.sfx.history, "bùa -> 'charm'")
	w._spawn_enemy("c", w.player.global_position + Vector2(200, 0))
	await frames(2)
	var en: Node = null
	for n in w._content.get_children():
		if n.is_in_group("hk_enemy"):
			en = n
	ck(en != null, "có quái để thử")
	if en:
		en.take_hit(999, en.global_position)
		ck("enemy_die" in w.sfx.history, "quái chết -> 'enemy_die'")
	w._spawn_boss("warden", w.player.global_position + Vector2(300, 0))
	await frames(2)
	w.boss.engaged.emit()
	ck("roar" in w.sfx.history, "boss lộ diện -> 'roar'")
	w.boss.shake.emit(3.0)
	ck("slam" in w.sfx.history, "boss giậm mạnh -> 'slam'")
	w.sfx.history.clear()
	w.boss.shake.emit(1.0)
	ck(not ("slam" in w.sfx.history), "rung nhẹ thì không 'slam'")
	w._on_boss_defeated("warden")
	ck("boss_die" in w.sfx.history, "boss chết -> 'boss_die'")
	St.delete_save()
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
