extends SceneTree
## Nightmare (nhánh A): cài đặt lưu/đọc có kiểm kiểu, boss đáp trả thói quen, đòn giả, pha 3 ở 25% máu + "Despair", Boss Rush dùng bản gốc.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func count(b: Node, k: String) -> int:
	var n := 0
	for c in b.get_children():
		if c.get("kind") == k:
			n += 1
	return n

func make(B, room, kind: String, fy: float) -> CharacterBody2D:
	var b := CharacterBody2D.new()
	b.set_script(B)
	b.kind = kind
	b.position = Vector2(900, fy - 100.0)
	root.add_child(b)
	b.arena = room.bounds()
	await frames(5)
	b.global_position = Vector2(900, fy - b._size.y * 0.5)
	return b

func rates(b, phase: int, n: int) -> Dictionary:
	var cnt: Dictionary = {}
	for i in n:
		b.state = "walk"
		b.phase = phase
		b._feint_at = 0.0
		b._pick_attack()
		cnt[b.state] = int(cnt.get(b.state, 0)) + 1
	return cnt

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_boss_nightmare_test_save.json"
	var B = load("res://hk/boss.gd")
	ck(load("res://hk/sfx.gd").DEFS.has("tell_despair"), "có âm tell_despair")
	# --- cài đặt
	ck(St.nightmare and St.is_nightmare(), "mặc định bật")
	St.nightmare = false
	St.reset()
	ck(not St.nightmare, "reset() không xoá cài đặt")
	var d: Dictionary = St.to_dict()
	ck(d.get("nightmare") == false, "to_dict có nightmare")
	St.nightmare = true
	St.from_dict(d)
	ck(not St.nightmare, "from_dict đọc lại false")
	St.from_dict({"nightmare": [1]})
	ck(not St.nightmare, "sai kiểu thì giữ giá trị cũ")
	St.nightmare = true
	St.rush = true
	ck(not St.is_nightmare(), "Boss Rush dùng bản gốc")
	St.rush = false

	var room := Node2D.new()
	room.set_script(load("res://hk/room.gd"))
	root.add_child(room)
	var grid: Array = []
	for r in 20:
		grid.append("#".repeat(60) if r == 19 else "#" + ".".repeat(58) + "#")
	room.build("test", {"area": "gate", "doors": {}, "grid": grid})
	var p := CharacterBody2D.new()
	p.set_script(load("res://hk/player.gd"))
	root.add_child(p)
	p.set_physics_process(false)
	var fy: float = 19.0 * 32.0
	p.global_position = Vector2(500, fy - 22.0)

	# --- pha 3 ở 25% máu
	var w = await make(B, room, "warden", fy)
	w.state = "walk"
	w.hp = w.max_hp * 4 / 10
	w.take_hit(1, Vector2.ZERO)
	ck(w.phase == 2, "40% máu = pha 2")
	w.state = "walk"
	w.hp = w.max_hp / 4 + 1
	w.take_hit(1, Vector2.ZERO)
	ck(w.phase == 3, "25% máu = pha 3 (nightmare)")
	var w2 = await make(B, room, "warden", fy)
	St.nightmare = false
	w2.state = "walk"
	w2.hp = w2.max_hp / 4
	w2.take_hit(1, Vector2.ZERO)
	ck(w2.phase == 2, "tắt nightmare: chỉ pha 2")
	St.nightmare = true

	# --- Despair: có khe, chỉ pha 3
	var c3 := rates(w, 3, 400)
	var c2 := rates(w, 2, 400)
	ck(int((await c3).get("wind_despair", 0)) > 0, "pha 3 có despair")
	ck(int((await c2).get("wind_despair", 0)) == 0, "pha 2 không có despair")
	var w3 = await make(B, room, "warden", fy)
	w3.phase = 3
	w3.state = "wind_despair"
	w3._t = 99.0
	w3._cast(p)
	await frames(2)
	var spikes: int = count(w3, "spikes")
	var cells: int = int((w3.arena.size.x - 120.0) / 60.0)
	ck(spikes > 0 and spikes < 2 * cells, "despair: có gai và có khe (%d/%d)" % [spikes, 2 * cells])

	# --- thói quen
	var b = await make(B, room, "warden", fy)
	b._jumps = 0
	b._stands = 0
	var base := rates(b, 1, 600)
	b._jumps = 2
	var jumpy := rates(b, 1, 600)
	ck(int((await jumpy).get("wind_bolt", 0)) > 0 and int((await base).get("wind_bolt", 0)) == 0, "hay nhảy né -> thêm bắn quạt")
	b._jumps = 0
	b._stands = 3
	var still := rates(b, 1, 600)
	ck(int((await still).get("wind_quake", 0)) > int((await base).get("wind_quake", 0)), "hay đứng chịu -> thêm sóng đất")
	# ghi thói quen: một đòn kết thúc khi người chơi đã nhảy
	b._jumps = 0
	b._stands = 0
	b.state = "wind_slash"
	b._t = 0.3
	p.velocity = Vector2.ZERO
	b._air_seen = true
	b._prev_state = "wind_slash"
	b.state = "walk"
	b._nightmare_tick(p)
	ck(b._jumps == 1 and b._stands == 0, "đòn bị né bằng nhảy được ghi")

	# --- đòn giả
	var f = await make(B, room, "warden", fy)
	f.phase = 2
	f.state = "wind_slash"
	f._t = 0.2
	f._feint_at = 0.25
	f._prev_state = "wind_slash"
	f._nightmare_tick(p)
	ck(f.state == "feint", "đòn giả khựng lại")
	f._t = 0.0
	await frames(2)
	ck(f.state == "wind_slash" or f.state == "lunge", "đòn giả rồi chém thật (%s)" % f.state)
	ck(f._t <= 0.16, "chém thật nhanh (%f)" % f._t)
	var f1 = await make(B, room, "warden", fy)
	f1.phase = 1
	var feints := 0
	for i in 300:
		f1.state = "walk"
		f1._feint_at = 0.0
		f1._pick_attack()
		if f1._feint_at > 0.0:
			feints += 1
	ck(feints == 0, "pha 1 không có đòn giả")
	var f2 = await make(B, room, "warden", fy)
	var n2 := 0
	for i in 400:
		f2.state = "walk"
		f2.phase = 2
		f2._feint_at = 0.0
		f2._pick_attack()
		if f2._feint_at > 0.0:
			n2 += 1
	ck(n2 > 0 and n2 < 200, "pha 2 có đòn giả (%d/400)" % n2)
	St.nightmare = false
	f2._feint_at = 0.0
	for i in 100:
		f2.state = "walk"
		f2._pick_attack()
		ck(f2._feint_at == 0.0, "tắt nightmare: không đòn giả")
		if f2._feint_at > 0.0:
			break
	print("DONE fails=", fails)
	quit(fails)
