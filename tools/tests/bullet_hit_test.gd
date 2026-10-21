extends SceneTree
## Đạn của Player phải gây sát thương lên quái và boss; đạn quái phải gây sát thương lên Player (và ghi nguồn).
## Chạy: godot --headless --path . -s tools/tests/bullet_hit_test.gd
var fails: int = 0
func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func _init() -> void:
	await process_frame
	var G = root.get_node("Global")
	G.reset_run()
	G.current_class = "ranger"
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var p = main.player
	var BULLET = load("res://scenes/bullet.tscn")
	# --- Player bullet -> enemy ---
	var enemy = load("res://scenes/enemy.tscn").instantiate()
	enemy.setup("slime")
	main.dungeon.entities.add_child(enemy)
	enemy.global_position = p.global_position + Vector2(90, 0)
	enemy.set_physics_process(false) # đứng yên để đo
	enemy.active = true # quái chỉ nhận sát thương khi đã "kích hoạt" (hết thời gian xuất hiện)
	await process_frame
	var hp0: int = int(enemy.hp)
	var b = BULLET.instantiate()
	b.setup(true, Vector2.RIGHT, 7, 600.0, 1.0, Color.WHITE, 6.0)
	G.world.add_child(b)
	b.global_position = enemy.global_position - Vector2(20, 0)
	for i in 30:
		await physics_frame
	print("enemy hp ", hp0, " -> ", enemy.hp)
	ck(int(enemy.hp) < hp0 or not enemy.alive, "player bullet damages enemy")
	# --- Player bullet -> boss ---
	var boss = load("res://scenes/boss.tscn").instantiate()
	boss.setup(1.0, main.dungeon._boss_kind_for_floor(1))
	main.dungeon.entities.add_child(boss)
	boss.global_position = p.global_position + Vector2(0, 90)
	boss.set_physics_process(false)
	if "active" in boss:
		boss.active = true
	await process_frame
	var bhp0: int = int(boss.hp)
	var b2 = BULLET.instantiate()
	b2.setup(true, Vector2.UP, 11, 600.0, 1.0, Color.WHITE, 6.0)
	G.world.add_child(b2)
	b2.global_position = boss.global_position + Vector2(0, 30)
	for i in 30:
		await physics_frame
	print("boss hp ", bhp0, " -> ", boss.hp)
	ck(int(boss.hp) < bhp0, "player bullet damages boss")
	# --- Enemy bullet -> player ---
	var php0: int = p.hp
	p.shield = 0.0
	var b3 = BULLET.instantiate()
	b3.setup(false, Vector2.RIGHT, 5, 400.0, 1.0, Color.RED, 6.0)
	b3.source = "test_shooter"
	G.world.add_child(b3)
	b3.global_position = p.global_position - Vector2(40, 0)
	for i in 30:
		await physics_frame
	print("player hp ", php0, " -> ", p.hp)
	ck(p.hp < php0, "enemy bullet damages player")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
