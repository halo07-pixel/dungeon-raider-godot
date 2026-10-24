extends SceneTree
## Lính kẹt sau tường/cửa khóa phòng hoặc tụt quá xa phải được kéo về cạnh chủ. Chạy: godot --headless --path . -s tools/tests/minion_leash_test.gd
var fails: int = 0
func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func _init() -> void:
	await process_frame
	var G = root.get_node("Global")
	var Minion = load("res://scripts/minion.gd")
	G.reset_run()
	G.current_class = "summoner"
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var p = main.player
	# 1) tụt quá xa => về ngay
	var far = Minion.spawn(p, "spirit", p.global_position + Vector2(1500, 0), 1.0, 5.0)
	await physics_frame
	await physics_frame
	ck(far.global_position.distance_to(p.global_position) < 100.0, "far minion recalled: %.0f" % far.global_position.distance_to(p.global_position))
	# 2) kẹt trong hộp tường (như bị bỏ ngoài cửa khóa): chủ cách ~300px
	var spot: Vector2 = p.global_position + Vector2(0, 0)
	var found := false
	for off in [Vector2(300, 0), Vector2(-300, 0), Vector2(0, 300), Vector2(0, -300)]:
		var probe := PhysicsPointQueryParameters2D.new()
		probe.position = p.global_position + off
		probe.collision_mask = G.L_WORLD
		if p.get_world_2d().direct_space_state.intersect_point(probe, 1).is_empty():
			spot = p.global_position + off
			found = true
			break
	if not found:
		print("leash stuck test skipped: no open spot")
	else:
		var box := StaticBody2D.new()
		box.collision_layer = G.L_WORLD
		for side in [Vector2(0, -20), Vector2(0, 20), Vector2(-20, 0), Vector2(20, 0)]:
			var cs := CollisionShape2D.new()
			var sh := RectangleShape2D.new()
			sh.size = Vector2(44, 6) if side.x == 0 else Vector2(6, 44)
			cs.shape = sh
			cs.position = side
			box.add_child(cs)
		G.world.add_child(box)
		box.global_position = spot
		var m = Minion.spawn(p, "spirit", spot, 1.0, 10.0)
		var d0: float = m.global_position.distance_to(p.global_position)
		await create_timer(2.0).timeout
		var d1: float = m.global_position.distance_to(p.global_position)
		ck(d0 > 200.0 and d1 < 100.0, "stuck minion recalled: %.0f -> %.0f" % [d0, d1])
		box.queue_free()
	print("minion_leash_test: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)
