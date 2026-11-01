extends SceneTree
## Test âm thanh lớp 2: vòng lặp ambient/pha 3 có dữ liệu + lặp được, ambient đổi theo khu, lớp nhạc pha 3 chỉ cho Lord/Many-Faced, bước chân theo mặt sàn.
var fails: int = 0

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
	St.save_path = "user://hk_audio_test_save.json"
	var SFX = load("res://hk/sfx.gd")
	for n in SFX.LOOPS:
		var st: AudioStreamWAV = SFX.loop_stream(n)
		ck(st != null and st.data.size() > 2000 and st.loop_mode == AudioStreamWAV.LOOP_FORWARD, "vòng lặp '%s' có dữ liệu và lặp" % n)
	ck(SFX.loop_stream("khong_co") == null, "tên lạ -> null")
	for a in ["gate", "catacomb", "vault", "archive"]:
		ck(SFX.LOOPS.has("amb_" + a), "khu %s có ambient" % a)
	var s: Node = SFX.new()
	root.add_child(s)
	await process_frame
	for n in ["step_stone", "step_dirt", "step_metal", "step_wet", "step_wood"]:
		ck(s.has_sound(n), "có âm %s" % n)
	var w := Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	await frames(60)
	var m: Node = w.music
	ck(m.ambient_now == w._last_area and m.ambient_now != "", "vào phòng -> ambient theo khu (%s)" % m.ambient_now)
	m.ambient("vault")
	ck(m.ambient_now == "vault", "đổi khu -> ambient vault")
	m.ambient("")
	ck(m.ambient_now == "", "ambient tắt được")
	# lớp nhạc pha cuối
	m.phase("warden", 3)
	ck(m.layer_now == "", "warden không có lớp pha cuối")
	m.phase("lord", 1)
	ck(m.layer_now == "", "Lord pha 1 chưa có lớp")
	m.phase("lord", 2)
	ck(m.layer_now == "final_lord", "Lord pha 2 (cuối) -> final_lord")
	m.play("boss_warden")
	ck(m.layer_now == "", "đổi bài -> tắt lớp pha cuối")
	m.phase("many_faced", 2)
	ck(m.layer_now == "", "Many-Faced pha 2 chưa có lớp")
	m.phase("many_faced", 3)
	ck(m.layer_now == "final_many", "Many-Faced pha 3 -> final_many")
	# boss thật: signal phase_changed tới music
	m.layer("")
	w._spawn_boss("lord", w.player.global_position + Vector2(300, 0))
	await frames(2)
	w.boss.engaged.emit()
	ck(m.ambient_now == "", "đánh boss -> tắt ambient")
	ck(m.layer_now == "", "Lord pha 1: chưa có lớp")
	w.boss.state = "idle"
	w.boss.take_hit(w.boss.max_hp / 2 + 1, Vector2.ZERO)
	ck(w.boss.phase == 2 and m.layer_now == "final_lord", "Lord xuống nửa máu -> signal -> final_lord (phase=%d)" % w.boss.phase)
	# bước chân
	w._last_area = "catacomb"
	w.sfx.history.clear()
	w._on_player_fx("run", w.player.global_position, 0.3)
	ck("step_dirt" in w.sfx.history, "catacomb -> step_dirt (%s)" % str(w.sfx.history))
	w._last_area = "vault"
	w._on_player_fx("run", w.player.global_position, 0.3)
	ck("step_metal" in w.sfx.history, "vault -> step_metal")
	w._last_area = "archive"
	w._on_player_fx("run", w.player.global_position, 0.3)
	ck("step_wet" in w.sfx.history, "archive -> step_wet")
	for a in ["gate", "catacomb", "vault", "archive"]:
		ck(w.SURFACE.has(a), "khu %s có mặt sàn" % a)
	St.delete_save()
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
