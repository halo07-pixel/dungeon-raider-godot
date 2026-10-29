extends SceneTree
## Boss cuối từng ending: Lord đủ 5 ký ức kia thành "The Gatekeeper" (sắc riêng, đèn ký ức, đòn Echo), Lord thiếu ký ức giữ nguyên,
## Many-Faced pha 3 nhuộm phòng tím + khác sắc Lord, ending_kind theo cờ.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func _spawn_lord(St, flags: Array):
	St.reset()
	for f in flags:
		St.set_flag("boss_" + f)
	St.bench_room = "vault_7"
	var w := Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	await create_timer(0.3).timeout
	return w

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	var L = load("res://hk/lore.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_ending_boss_save.json"
	St.delete_save()
	# Lord thiếu ký ức: boss thường
	var w = await _spawn_lord(St, ["warden", "hexer"])
	ck(w.boss != null and w.boss.kind == "lord", "phòng vault_7 có Lord")
	ck(not w.boss.empowered and w.boss.title() == "Dungeon Lord", "thiếu ký ức: vẫn là Dungeon Lord")
	var plain_tint: Color = w.boss._look_tint()
	w.queue_free()
	await process_frame
	# đủ 5 ký ức kia: Gatekeeper
	w = await _spawn_lord(St, ["warden", "hexer", "wraith", "brute", "colossus"])
	var b = w.boss
	ck(b.empowered and b.title() == "The Gatekeeper" and b.lanterns == 5, "đủ 5 ký ức: Gatekeeper, 5 đèn sáng")
	ck(b.echoes.size() == 3 and "wind_pillar" in b.echoes and "wind_fissure" in b.echoes and "wind_tide" in b.echoes, "Echo có đòn của warden/brute/colossus (%s)" % str(b.echoes))
	ck(b._look_tint() != plain_tint, "Gatekeeper khác sắc Lord thường")
	# Echo chỉ xuất hiện khi đủ điều kiện và từ pha 2
	var seen: Dictionary = {}
	b.phase = 1
	for i in 300:
		b._pick_attack()
		seen[b.state] = true
	ck(not seen.has("wind_pillar") and not seen.has("wind_fissure") and not seen.has("wind_tide"), "pha 1: chưa có Echo")
	b.phase = 2
	seen = {}
	for i in 300:
		b._pick_attack()
		seen[b.state] = true
	ck(seen.has("wind_pillar") or seen.has("wind_fissure") or seen.has("wind_tide"), "pha 2: có Echo (%s)" % str(seen.keys()))
	b.empowered = false
	seen = {}
	for i in 300:
		b._pick_attack()
		seen[b.state] = true
	ck(not seen.has("wind_pillar") and not seen.has("wind_fissure") and not seen.has("wind_tide"), "không empowered: không có Echo")
	w.queue_free()
	await process_frame
	# Many-Faced pha 3: nhuộm phòng + khác sắc Lord
	var mf := CharacterBody2D.new()
	mf.set_script(load("res://hk/boss.gd"))
	mf.kind = "many_faced"
	root.add_child(mf)
	var tints: Array = []
	mf.tinted.connect(func(c: Color): tints.append(c))
	mf.state = "walk"
	mf.hp = mf.max_hp / 3
	mf.take_hit(1, Vector2.ZERO)
	ck(mf.phase == 3 and mf.form == "sovereign", "Many-Faced vào pha 3 dạng sovereign")
	ck(tints.size() == 1 and tints[0] != Color.WHITE, "pha 3 nhuộm phòng")
	ck(mf._look_tint() != plain_tint, "sovereign khác sắc Lord")
	mf.queue_free()
	await process_frame
	ck(tints.size() == 2 and tints[1] == Color.WHITE, "boss rời cảnh thì bỏ nhuộm")
	# ending_kind
	St.reset()
	ck(L.ending_kind() == "normal", "ending thường")
	for m in L.MEMORIES:
		St.set_flag("boss_" + String(m["id"]))
	ck(L.ending_kind() == "full", "đủ 6 ký ức: full")
	St.set_flag("boss_many_faced")
	ck(L.ending_kind() == "true", "hạ Many-Faced: true")
	St.delete_save()
	print("hk_ending_boss_test: ", "OK" if fails == 0 else "%d lỗi" % fails)
	quit(1 if fails > 0 else 0)
