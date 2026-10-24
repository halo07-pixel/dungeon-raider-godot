extends SceneTree
## Splitter: quái con được tạo hoãn tới cuối khung (không lỗi "flushing queries") nhưng bộ đếm quái cộng NGAY.
## Chạy: godot --headless --path . -s tools/tests/split_defer_test.gd
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
	var dg = main.dungeon
	var AF = load("res://scripts/enemy_affix.gd")
	var owner_enemy := Node2D.new()
	var scr := GDScript.new()
	scr.source_code = "extends Node2D\nvar kind: String = \"slime\"\n"
	scr.reload()
	owner_enemy.set_script(scr)
	main.add_child(owner_enemy)
	owner_enemy.global_position = main.player.global_position
	var before_cnt: int = dg.alive_enemies
	var before_nodes: int = root.get_tree().get_nodes_in_group("enemies").size()
	dg._on_affix_split(owner_enemy, dg.current_cell)
	ck(dg.alive_enemies == before_cnt + AF.SPLIT_COUNT, "counter bumped immediately: %d -> %d" % [before_cnt, dg.alive_enemies])
	ck(root.get_tree().get_nodes_in_group("enemies").size() == before_nodes, "children not added synchronously")
	await process_frame
	await process_frame
	ck(dg.alive_enemies == before_cnt + AF.SPLIT_COUNT, "counter stays balanced after spawn: %d" % dg.alive_enemies)
	ck(root.get_tree().get_nodes_in_group("enemies").size() == before_nodes + AF.SPLIT_COUNT, "children spawned next frame")
	print("split_defer_test: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)
