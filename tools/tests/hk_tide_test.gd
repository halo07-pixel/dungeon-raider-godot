extends SceneTree
## Nước dâng của Colossus nguy hiểm hơn: phòng có bục -> nước TIDE_H, chìm (mất 1 mặt nạ mỗi 2s, tối đa 2), dòng chảy kéo về boss, nhảy lên cao thì đứng yên bộ đếm;
## phòng không có bục -> như cũ (80px, chỉ làm chậm, không chìm).
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func water(b: Node) -> Node:
	for c in b.get_children():
		if c.get("kind") == "water":
			return c
	return null

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_tide_test_save.json"
	var B = load("res://hk/boss.gd")
	var Z = load("res://hk/zone.gd")
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
	for has_platform in [true, false]:
		var b := CharacterBody2D.new()
		b.set_script(B)
		b.kind = "colossus"
		b.position = Vector2(300, fy - 100.0)
		root.add_child(b)
		b.arena = room.bounds()
		b.platforms = [Rect2(600, fy - 96.0, 160, 8)] if has_platform else []
		await frames(5)
		b.state = "wind_tide"
		b.global_position = Vector2(300, fy - b._size.y * 0.5)   # đứng trên sàn: _floor_y() = chân boss
		b._t = 99.0
		b._cast(p)
		await frames(3)
		var w = water(b)
		ck(w != null, "có nước (platform=%s)" % has_platform)
		if w == null:
			continue
		ck(w.drown == has_platform, "drown chỉ bật khi có bục (%s)" % w.drown)
		var want_h: float = B.TIDE_H if has_platform else 80.0
		ck(absf(w.rect.size.y - want_h) < 0.1, "nước cao %.0f (%.0f)" % [want_h, w.rect.size.y])
		await frames(60)   # nước dâng đủ cao (0.6s trễ + 0.8s dâng)
		await frames(40)
		p.global_position = Vector2(900, fy - 22.0)
		var hp0: int = p.hp
		p.drift = 0.0   # player.physics tắt nên không tự xoá drift của vòng trước
		# dòng chảy: boss ở x=300 (bên trái người chơi) -> kéo sang trái
		await frames(1)
		ck((p.drift < 0.0) if has_platform else (p.drift == 0.0), "dòng chảy %s (drift %.0f)" % ["kéo về boss" if has_platform else "không có", p.drift])
		# ở trong nước ~2.2s (không i-frame): có bục thì mất đúng 1 mặt nạ, không có bục thì không mất
		for i in 135:
			p.invuln = 0.0
			p.global_position = Vector2(900, fy - 22.0)
			await frames(1)
		ck(p.hp == hp0 - (1 if has_platform else 0), "ở trong nước 2.2s: hp %d -> %d" % [hp0, p.hp])
		if has_platform:
			# nhảy lên trên mặt nước: bộ đếm đứng yên, không mất thêm
			var hp1: int = p.hp
			for i in 120:
				p.invuln = 0.0
				p.global_position = Vector2(900, fy - 22.0 - 200.0)
				await frames(1)
			ck(p.hp == hp1, "trên mặt nước: không chìm thêm (%d)" % p.hp)
			# ở lại trong nước tiếp: chỉ mất thêm tối đa MAX_DROWN tổng cộng
			for i in 400:
				p.invuln = 0.0
				p.global_position = Vector2(900, fy - 22.0)
				await frames(1)
				if water(b) == null:
					break
			ck(p.hp >= hp0 - Z.MAX_DROWN, "tối đa %d mặt nạ mỗi đợt nước (hp %d -> %d)" % [Z.MAX_DROWN, hp0, p.hp])
		b.queue_free()
		await frames(3)
		p.hp = St.max_hp()
		p.invuln = 0.0
	print("DONE fails=", fails)
	quit()
