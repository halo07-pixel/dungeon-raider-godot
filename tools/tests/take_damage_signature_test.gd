extends SceneTree
## take_damage có 3 chữ ký khác nhau (player 6 tham số, enemy 4, boss 4). Mọi kiểu gọi đang dùng trong code phải chạy được trên đúng loại mục tiêu.
## Lỗi thật từng xảy ra: thêm tham số `source` làm đạn của Player gọi enemy.take_damage với quá nhiều tham số -> hết gây sát thương.
## Chạy: godot --headless --path . -s tools/tests/take_damage_signature_test.gd
var fails: int = 0
func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func _init() -> void:
	await process_frame
	var G = root.get_node("Global")
	G.save_path = "user://test_save.dat"
	G.reset_run()
	G.current_class = "ranger"
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var p = main.player
	var pos: Vector2 = p.global_position + Vector2(120, 0)

	# --- Enemy: (amount) / (amount, from) / (amount, from, knock) / (amount, from, knock, true_dmg) ---
	var shapes_enemy: Array = [[10], [10, Vector2.ZERO], [10, Vector2.ZERO, 120.0], [10, Vector2.ZERO, 120.0, true]]
	for i in shapes_enemy.size():
		var e = load("res://scenes/enemy.tscn").instantiate()
		e.setup("brute")
		main.dungeon.entities.add_child(e)
		e.global_position = pos
		await process_frame
		e.active = true # quái mới sinh có khoảng chờ chưa nhận đòn
		var before: float = float(e.hp)
		e.callv("take_damage", shapes_enemy[i])
		ck(float(e.hp) < before, "enemy.take_damage shape %d (%d args) gay sat thuong" % [i, shapes_enemy[i].size()])
		e.queue_free()

	# --- Boss: (amount) / (amount, from) / (amount, from, knock) ---
	var shapes_boss: Array = [[10], [10, Vector2.ZERO], [10, Vector2.ZERO, 0.0], [10, Vector2.ZERO, 0.0, true]]
	for i in shapes_boss.size():
		var b = load("res://scenes/boss.tscn").instantiate()
		b.setup(1.0, "warden")
		main.dungeon.entities.add_child(b)
		b.global_position = pos + Vector2(200, 0)
		await process_frame
		if b.has_method("activate_boss"): b.activate_boss()
		var before_b: float = float(b.hp)
		b.callv("take_damage", shapes_boss[i])
		ck(float(b.hp) < before_b, "boss.take_damage shape %d (%d args) gay sat thuong" % [i, shapes_boss[i].size()])
		b.queue_free()

	# --- Player: 1..6 tham số; ignore_invuln=true khi có (bỏ qua khung bất tử giữa các lần gọi) ---
	var hurt: Array = []
	G.player_hurt_by.connect(func(src, amt): hurt.append([src, amt]))
	var shapes_player: Array = [
		[5, Vector2.ZERO, 0.0, true],
		[5, Vector2.ZERO, 0.0, true, false],
		[5, Vector2.ZERO, 0.0, true, false, "enemy:slime"],
		[5, Vector2.ZERO, 0.0, true, true, "hazard:test"],
	]
	for i in shapes_player.size():
		p.hp = p.max_hp
		var n0: int = hurt.size()
		p.callv("take_damage", shapes_player[i])
		ck(hurt.size() == n0 + 1, "player.take_damage shape %d (%d args) phat tin hieu player_hurt_by" % [i, shapes_player[i].size()])
	ck(hurt.size() >= 3 and String(hurt[2][0]) == "enemy:slime", "nguon sat thuong duoc ghi dung (enemy:slime)")
	ck(hurt.size() >= 4 and String(hurt[3][0]) == "hazard:test", "nguon hazard duoc ghi")
	# gọi kiểu 1-3 tham số lúc không bất tử cũng phải chạy
	p.hp = p.max_hp
	p.hurt_timer.stop()
	var n1: int = hurt.size()
	p.take_damage(5)
	ck(hurt.size() == n1 + 1, "player.take_damage(amount) don gian chay duoc")
	print("take_damage_signature_test: ", "OK" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails > 0 else 0)
