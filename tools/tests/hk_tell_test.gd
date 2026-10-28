extends SceneTree
## Báo hiệu đòn bằng âm (không còn vùng cảnh báo màu): boss vào "wind_*" thì phát đúng âm tell_<đòn> một lần; quái windup phát "tell";
## mọi âm tell có trong bảng âm.
var fails: int = 0
var heard: Array = []

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
	St.save_path = "user://hk_tell_test_save.json"
	var SFX = load("res://hk/sfx.gd")
	for n in ["tell", "tell_slash", "tell_slam", "tell_bolt", "tell_summon", "tell_conjure", "tell_shift", "rumble"]:
		ck(SFX.DEFS.has(n), "bảng âm có %s" % n)
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
	var b := CharacterBody2D.new()
	b.set_script(load("res://hk/boss.gd"))
	b.kind = "warden"
	b.position = Vector2(700, 560)
	root.add_child(b)
	b.arena = room.bounds()
	b.sfx.connect(func(n: String): heard.append(n))
	await frames(20)
	b.state = "wind_slam"
	b._t = 0.45
	await frames(10)
	ck(heard.count("tell_slam") == 1, "wind_slam phát tell_slam đúng một lần (%s)" % str(heard))
	var e := CharacterBody2D.new()
	e.set_script(load("res://hk/enemy.gd"))
	e.kind = "charger"
	e.position = Vector2(1200, 560)
	root.add_child(e)
	e.sfx.connect(func(n: String): heard.append(n))
	await frames(10)
	e.state = "windup"
	e._t = 0.5
	await frames(5)
	ck(heard.has("tell"), "quái windup phát âm tell")
	print("hk_tell_test: ", "OK" if fails == 0 else "%d lỗi" % fails)
	quit(1 if fails > 0 else 0)
