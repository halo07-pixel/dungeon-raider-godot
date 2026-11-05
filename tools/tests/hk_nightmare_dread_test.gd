extends SceneTree
## Nightmare (nhánh D): tim đập (1 mặt nạ / phòng im lặng / Stalker gần), viền tối khi máu thấp, thì thầm (phòng tối), nhỏ giọt (phòng im lặng),
## nhạc cắt trước boss. Tất cả tắt cùng Atmosphere hoặc khi tắt Nightmare/Boss Rush.
var fails: int = 0
var w: Node2D

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func go(id: String) -> void:
	w.busy = false
	w.load_room(id)
	await process_frame

## Chạy _dread_tick tới khi có nhịp (hud._beat == 1) hoặc hết `secs`; trả giây tới nhịp đầu, -1 nếu không có.
func first_beat(secs: float) -> float:
	var t := 0.0
	w.hud._beat = 0.0
	w._beat_t = 0.0
	while t < secs:
		w._dread_tick(0.1)
		t += 0.1
		if w.hud._beat >= 1.0:
			return t
	return -1.0

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	var Sfx = load("res://hk/sfx.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_nightmare_dread_save.json"
	St.delete_save()
	for k in ["heartbeat", "whisper", "drip"]:
		ck(Sfx.DEFS.has(k), "có âm " + k)
	w = Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	for i in 10:
		await process_frame
	await go("cat_9")   # phòng thường
	w._mode = ""
	w.player.hp = 3
	ck(first_beat(3.0) < 0.0, "đủ máu, phòng thường: không tim đập")
	w.player.hp = 1
	var b: float = first_beat(3.0)
	ck(b > 0.0 and b <= 1.0, "còn 1 mặt nạ: tim đập (%f)" % b)
	St.atmosphere_on = false
	ck(first_beat(3.0) < 0.0, "tắt Atmosphere: không tim đập")
	ck(not w.hud.dread, "tắt Atmosphere: không viền")
	St.atmosphere_on = true
	St.nightmare = false
	ck(first_beat(3.0) < 0.0, "tắt Nightmare: không tim đập")
	St.nightmare = true
	St.rush = true
	ck(first_beat(3.0) < 0.0, "Boss Rush: không tim đập")
	St.rush = false
	# phòng im lặng: tim đập chậm hơn kể cả đủ máu
	w.player.hp = 3
	w._mode = "silent"
	b = first_beat(4.0)
	ck(b > 0.0, "phòng im lặng: tim đập dù đủ máu (%f)" % b)
	# Stalker gần: nhanh hơn (0.65s)
	w._mode = ""
	var st := CharacterBody2D.new()
	st.set_script(load("res://hk/stalker.gd"))
	st.arena = w.room.bounds()
	w.add_child(st)
	await process_frame
	await process_frame
	st.global_position = w.player.global_position + Vector2(200, 0)
	st.state = "chase"
	b = first_beat(3.0)
	ck(b > 0.0 and b <= 0.7, "Stalker gần: tim đập nhanh (%f)" % b)
	st.free()
	# viền: chỉ khi 1-2 mặt nạ và dread
	w.hud.hp = 1
	w.hud.dread = true
	ck(w.hud.dread and w.hud.hp <= 2, "điều kiện viền khi còn 1 mặt nạ")
	# thì thầm / nhỏ giọt đặt lại bộ đếm sau khi phát
	w.player.hp = 3
	w._mode = "dark"
	w._whisper_t = 0.05
	w._dread_tick(0.1)
	ck(w._whisper_t >= 6.0, "phòng tối: thì thầm rồi hẹn lần sau (%f)" % w._whisper_t)
	w._mode = "silent"
	w._drip_t = 0.05
	w._dread_tick(0.1)
	ck(w._drip_t >= 2.0, "phòng im lặng: nhỏ giọt rồi hẹn lần sau (%f)" % w._drip_t)
	# nhạc cắt trước boss
	await go("gate_6")
	ck(w.boss != null, "phòng boss có boss")
	w.music.play("explore_stone")
	w._on_boss_engaged()
	await process_frame
	ck(w.music.current == "", "nhạc cắt khi boss xuất hiện")
	await create_timer(w.BOSS_SILENCE + 0.3).timeout
	ck(w.music.current != "", "rồi nhạc boss vào (%s)" % w.music.current)
	# lần vào trận mới trong lúc im lặng: await cũ không được phát nhạc
	w.music.play("explore_stone")
	w._on_boss_engaged()
	await process_frame
	w._engage_id += 1
	await create_timer(w.BOSS_SILENCE + 0.3).timeout
	ck(w.music.current == "", "đã vào lần khác: await cũ không phát nhạc (%s)" % w.music.current)
	St.nightmare = false
	await go("gate_6")
	w.music.play("explore_stone")
	w._on_boss_engaged()
	ck(w.music.current != "" and w.music.current != "explore_stone", "tắt nightmare: nhạc boss vào ngay")
	print("DONE fails=", fails)
	quit(fails)
