extends SceneTree
## Sigil: dữ liệu, ô gắn, gộp chỉ số, hiệu ứng (sát thương/hồi/bán kính/đốt/làm chậm/hút máu/giáp/hoàn hồi/chí mạng/echo/sét/phá giáp), pickup, lưu.
## Chạy: godot --headless --path . -s tools/tests/sigils_test.gd
var fails: int = 0
func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

const DUMMY_SRC := """
extends Node2D
var alive: bool = true
var active: bool = true
var hp: int = 100000
var data: Dictionary = {"radius": 14.0}
var total: int = 0
var hits: Array = []
var statuses: Array = []
var elements: Array = []
var sundered: int = 0
func kill() -> void: pass
func hurt_center() -> Vector2: return global_position
func take_damage(d: int, _pos = Vector2.ZERO, _k = 0.0, _t = false) -> void:
	total += d
	hits.append(d)
	hp -= d
	if hp <= 0:
		alive = false
func apply_element(a = null, b = null, c = null) -> void: elements.append([a, b, c])
func apply_status(t = null, d = 0.0, _c = null) -> void: statuses.append([t, d])
func apply_sunder() -> void: sundered += 1
"""
var dscript: GDScript
var G
func dummy(pos: Vector2, hp: int = 100000) -> Node2D:
	var d := Node2D.new()
	d.set_script(dscript)
	d.hp = hp
	d.add_to_group("enemies")
	G.world.add_child(d)
	d.global_position = pos
	return d
func clear_all() -> void:
	for g in ["enemies", "minions", "enemy_bullets"]:
		for n in root.get_tree().get_nodes_in_group(g):
			n.queue_free()
	await process_frame
func wait(sec: float) -> void:
	await create_timer(sec).timeout

func _init() -> void:
	await process_frame
	G = root.get_node("Global")
	var SG = load("res://scripts/sigils.gd")
	dscript = GDScript.new()
	dscript.source_code = DUMMY_SRC
	dscript.reload()
	# ---- dữ liệu ----
	ck(SG.SIGILS.size() == 14, "14 sigils")
	for id in SG.SIGILS:
		var s: Dictionary = SG.SIGILS[id]
		ck(SG.RARITY_ORDER.has(String(s["rarity"])) and String(s["desc"]) != "" and not (s["mods"] as Dictionary).is_empty(), "sigil %s well-formed" % id)
	for r in SG.RARITY_ORDER:
		var n: int = 0
		for id in SG.SIGILS:
			if SG.rarity_of(id) == r:
				n += 1
		ck(n >= 3, "rarity %s has >= 3 sigils" % r)
	ck(absf(SG.total(["might", "overcharge"], "dmg") - 1.8) < 0.001, "dmg multiplies (1.2*1.5)")
	ck(absf(SG.total(["overcharge", "swiftness"], "cd") - 1.0625) < 0.001, "cd multiplies")
	ck(absf(SG.total([], "dmg") - 1.0) < 0.001 and SG.total([], "burn") == 0.0, "defaults")
	ck(absf(SG.total(["ember", "ember"], "burn") - 0.7) < 0.001, "additive keys add")
	ck(SG.capacity("class", false) == 2 and SG.capacity("class", true) == 3 and SG.capacity("tome", false) == 2, "capacities")
	var w1: Dictionary = SG.rarity_weights(1)
	var w10: Dictionary = SG.rarity_weights(10)
	ck(w10["epic"] > w1["epic"] and absf(w1["common"] + w1["rare"] + w1["epic"] - 100.0) < 0.01, "epic weight grows, weights sum 100")
	# ---- roll_choices ----
	var rc: Array = SG.roll_choices(3, 5, ["might"])
	ck(rc.size() == 3 and not rc.has("might") and rc[0] != rc[1] and rc[1] != rc[2] and rc[0] != rc[2], "roll_choices distinct + excludes")
	ck(SG.roll_choices(99, 5).size() == 14, "roll_choices capped by pool")
	var epic_seen: int = 0
	for i in 300:
		for id in SG.roll_choices(3, 10):
			if SG.rarity_of(id) == "epic":
				epic_seen += 1
	ck(epic_seen > 30, "epics do show up (%d)" % epic_seen)
	# ---- socket logic ----
	var slots: Dictionary = SG.empty_slots()
	ck(SG.socket(slots, "nope", "class", false, ["class"]).is_empty(), "unknown id rejected")
	ck(SG.socket(slots, "might", "class", false, ["class", "tome"])["target"] == "class", "first goes to class")
	ck(SG.socket(slots, "might", "class", false, ["class"]).is_empty(), "duplicate rejected")
	SG.socket(slots, "swiftness", "class", false, ["class", "tome"])
	var r3: Dictionary = SG.socket(slots, "expanse", "class", false, ["class", "tome"])
	ck(r3["target"] == "tome" and r3["displaced"] == "", "class full -> spills to tome")
	var r4: Dictionary = SG.socket(slots, "ember", "tome", false, ["class", "tome"])
	ck(r4["target"] == "tome" and r4["displaced"] == "", "prefer tome with free slot")
	var r5: Dictionary = SG.socket(slots, "rime", "class", false, ["class", "tome"])
	ck(r5["target"] == "class" and r5["displaced"] == "might", "all full: replaces oldest in preferred, returns it")
	ck(slots["class"] == ["swiftness", "rime"], "class slots after replace: %s" % str(slots["class"]))
	var s2: Dictionary = SG.empty_slots()
	ck(SG.socket(s2, "might", "tome", false, ["class"])["target"] == "class", "no tome: falls back to class")
	var s3: Dictionary = SG.empty_slots()
	for id in ["might", "swiftness", "expanse"]:
		SG.socket(s3, id, "class", true, ["class"])
	ck(s3["class"].size() == 3, "evolved class holds 3")
	var norm: Dictionary = SG.normalize({"class": ["might", "might", "bogus", "swiftness", "expanse"], "tome": ["might", "ember"]}, false)
	ck(norm["class"] == ["might", "swiftness"] and norm["tome"] == ["ember"], "normalize: dup/unknown/overflow dropped: %s" % str(norm))
	ck(SG.normalize(null, false) == SG.empty_slots(), "normalize garbage")
	# ---- vào ván ----
	G.reset_run()
	G.current_class = "mage"
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var p = main.player
	var cs = p.class_skill
	var ts_check: bool = p.sigil_runner != null
	ck(ts_check, "player has sigil runner")
	ck(G.run_sigils == SG.empty_slots(), "no sigils at start")
	# ---- socket qua Player ----
	var res: Dictionary = p.socket_sigil("might")
	ck(res["target"] == "class" and G.run_sigils["class"] == ["might"], "player socket into class")
	ck(p.socket_sigil("ember", "tome")["target"] == "class", "no tome yet: goes to class")
	p.equip_tome("frost_nova")
	ck(p.socket_sigil("rime", "tome")["target"] == "tome", "tome now available + preferred")
	G.run_sigils = SG.empty_slots()
	# ---- chỉ số: dmg / cd / radius / life ----
	var base_cd: float = cs._effective_cooldown()
	var base_dm: float = cs._mult("dmg_mult")
	var base_rad: float = cs._mult("radius_mult")
	var base_life: float = cs._mult("life_mult")
	G.run_sigils = {"class": ["might", "swiftness"], "tome": []}
	ck(absf(cs._mult("dmg_mult") / base_dm - 1.2) < 0.001, "class dmg sigil")
	ck(absf(cs._effective_cooldown() / base_cd - 0.85) < 0.001 or cs._effective_cooldown() == 1.0, "class cooldown sigil")
	G.run_sigils = {"class": ["expanse", "persistence"], "tome": []}
	ck(absf(cs._mult("radius_mult") / base_rad - 1.2) < 0.001, "class radius sigil")
	ck(absf(cs._mult("life_mult") / base_life - 1.25) < 0.001, "class life sigil")
	# Sigil Tome không ảnh hưởng skill class và ngược lại
	p.equip_tome("frost_nova")
	var tbase: float = p.tome_skill.power()
	var tcd: float = p.tome_skill._effective_cooldown()
	G.run_sigils = {"class": ["might"], "tome": []}
	ck(absf(p.tome_skill.power() - tbase) < 0.0001, "class sigil doesn't touch tome")
	G.run_sigils = {"class": [], "tome": ["might", "swiftness"]}
	ck(absf(p.tome_skill.power() / tbase - 1.2) < 0.001, "tome dmg sigil")
	ck(absf(p.tome_skill._effective_cooldown() / tcd - 0.85) < 0.001, "tome cooldown sigil")
	ck(absf(cs._mult("dmg_mult") / base_dm - 1.0) < 0.001, "tome sigil doesn't touch class skill")
	# ---- hiệu ứng theo đòn ----
	await clear_all()
	p.global_position = Vector2(2000, 2000)
	var t1 = dummy(p.global_position + Vector2(40, 0))
	G.run_sigils = {"class": ["ember", "rime"], "tome": []}
	for i in 60:
		G.on_secondary_hit(t1, 20, false, "class")
	ck(t1.elements.size() > 5 and t1.elements[0][0] == "burn", "ember ignites (%d)" % t1.elements.size())
	ck(t1.statuses.size() > 10 and t1.statuses[0][0] == "slow", "rime slows (%d)" % t1.statuses.size())
	var burns_before: int = t1.elements.size()
	for i in 40:
		G.on_secondary_hit(t1, 20, false, "tome")
	ck(t1.elements.size() >= burns_before and true, "tome hits don't use class sigils")
	var elems_after_tome: int = t1.elements.size() - burns_before
	# on_player_hit may add burns from buffs only; none here, so no class-sigil burn from tome src
	ck(elems_after_tome == 0, "tome-src hits ignore class sigils (%d)" % elems_after_tome)
	G.run_sigils = {"class": ["siphon"], "tome": []}
	p.hp = 10
	G.on_secondary_hit(t1, 20, false, "class")
	ck(p.hp == 11, "siphon heals 1 (hp %d)" % p.hp)
	G.on_secondary_hit(t1, 20, false, "class")
	ck(p.hp == 11, "siphon rate limited")
	p.hp = p.max_hp
	G.run_sigils = {"class": ["fracture"], "tome": []}
	var sb: int = t1.sundered
	G.on_secondary_hit(t1, 20, false, "class")
	ck(t1.sundered == sb + 1, "fracture sunders")
	# storm: nhiều lần chắc chắn có sét nảy
	await clear_all()
	var a = dummy(p.global_position + Vector2(40, 0))
	var b = dummy(p.global_position + Vector2(90, 0))
	var c2 = dummy(p.global_position + Vector2(140, 0))
	G.run_sigils = {"class": ["storm", "storm"], "tome": []} # ép 60%: đưa 2 id trùng trực tiếp vào bảng
	for i in 40:
		G.on_secondary_hit(a, 40, false, "class")
	ck(b.total > 0 or c2.total > 0, "storm arcs to nearby enemies (%d/%d)" % [b.total, c2.total])
	# harvest: giết thì hoàn hồi chiêu, tối đa nửa
	await clear_all()
	G.run_sigils = {"class": ["harvest"], "tome": []}
	cs.cooldown_total = 10.0
	cs.cooldown_left = 10.0
	cs._refunded = 0.0
	for i in 8:
		var v = dummy(p.global_position + Vector2(30, 0), 1)
		v.take_damage(5)
		G.on_secondary_hit(v, 5, false, "class")
	ck(absf(cs.cooldown_left - 5.0) < 0.01, "harvest refunds, capped at half (cooldown_left %.2f)" % cs.cooldown_left)
	# không hoàn khi quái còn sống
	cs.cooldown_left = 10.0
	cs._refunded = 0.0
	var alive_t = dummy(p.global_position + Vector2(30, 0))
	G.on_secondary_hit(alive_t, 5, false, "class")
	ck(cs.cooldown_left == 10.0, "no refund on non-kill")
	# ---- khi tung: giáp + chí mạng ----
	G.run_sigils = {"class": ["aegis", "keen"], "tome": []}
	p.shield = 0.0
	p.skill_crit_charges = 0
	p.sigil_runner.on_cast("slam", "class")
	ck(p.shield >= 11.9 or p.max_shield < 12, "aegis grants shield (%f)" % p.shield)
	ck(p.skill_crit_charges >= 2, "keen grants crit charges")
	# ---- echo: tung lại miễn phí ----
	await clear_all()
	G.run_sigils = {"class": ["echo"], "tome": []}
	p.global_position = Vector2(2000, 2000)
	cs.setup(p, "slam")
	cs.cooldown_left = 0.0
	var e1 = dummy(p.global_position + Vector2(50, 0))
	cs.execute_free()
	var once: int = e1.hits.size()
	ck(once == 1 and cs.cooldown_left == 0.0, "execute_free costs no cooldown")
	p.sigil_runner.recast("class")
	await wait(0.7)
	ck(e1.hits.size() == 2, "echo recast hits again (%d)" % e1.hits.size())
	# ---- hit attribution: lính, vùng, đạn ----
	await clear_all()
	G.run_sigils = {"class": ["ember"], "tome": []}
	var heard: Array = []
	G.skill_hit_landed.connect(func(src, tg, d): heard.append(src))
	var tgt = dummy(p.global_position + Vector2(100, 0))
	var MN = load("res://scripts/minion.gd")
	MN.spawn(p, "spirit", p.global_position + Vector2(60, 0), 1.0, 1.0, 0, "class")
	await wait(1.5)
	ck(heard.has("class"), "minion hit reports its source")
	heard.clear()
	cs.setup(p, "slam")
	cs.execute_free()
	ck(heard.has("class"), "slam hit reports class source")
	# ---- pickup ----
	await clear_all()
	G.run_sigils = SG.empty_slots()
	p.equip_tome("frost_nova")
	var dropped: Array = []
	G.sigil_drop_requested.connect(func(id, pos): dropped.append(id))
	for id in ["might", "swiftness", "expanse", "ember"]:
		var pk = load("res://scenes/pickup.tscn").instantiate()
		pk.setup("sigil", id)
		G.world.add_child(pk)
		pk.global_position = p.global_position
		pk._near = true
		pk._lock = 0.0
		pk._try_take_sigil()
		await process_frame
		Pickup_reset()
	ck(G.run_sigils["class"] == ["might", "swiftness"] and G.run_sigils["tome"] == ["expanse", "ember"], "pickups fill class then tome: %s" % str(G.run_sigils))
	var pk2 = load("res://scenes/pickup.tscn").instantiate()
	pk2.setup("sigil", "rime")
	G.world.add_child(pk2)
	pk2.global_position = p.global_position
	pk2._near = true
	pk2._lock = 0.0
	pk2._try_take_sigil()
	await process_frame
	ck(dropped == ["might"] and G.run_sigils["class"] == ["swiftness", "rime"], "full: replaced oldest dropped: %s %s" % [str(dropped), str(G.run_sigils)])
	var pk3 = load("res://scenes/pickup.tscn").instantiate()
	pk3.setup("sigil", "rime")
	G.world.add_child(pk3)
	pk3.global_position = p.global_position
	pk3._near = true
	pk3._lock = 0.0
	Pickup_reset()
	pk3._try_take_sigil()
	await process_frame
	ck(is_instance_valid(pk3) and G.run_sigils["class"] == ["swiftness", "rime"], "already-socketed sigil can't be taken again")
	# ---- Dungeon: boss cache không trùng ----
	var dun = null
	for ch in main.get_children():
		if ch.has_method("_spawn_sigil_choice"):
			dun = ch
	if dun != null:
		await clear_all()
		for n in root.get_tree().get_nodes_in_group("sigil_pickup"):
			n.queue_free()
		await process_frame
		dun._spawn_sigil_choice(p.global_position + Vector2(0, 600), 3)
		await process_frame
		var offered: Array = []
		for n in root.get_tree().get_nodes_in_group("sigil_pickup"):
			offered.append(n.extra)
		var socketed: Array = SG.all_socketed(G.run_sigils)
		var clash: bool = false
		for id in offered:
			if socketed.has(id):
				clash = true
		ck(offered.size() == 3 and not clash, "boss cache: 3 offered, none already socketed %s" % str(offered))
	else:
		print("NOTE: dungeon node not found")
	# ---- lưu / khôi phục ----
	G.run_sigils = {"class": ["might"], "tome": ["ember"]}
	var saved: Dictionary = main._build_saved_run()
	ck(saved["sigils"] == {"class": ["might"], "tome": ["ember"]}, "saved_run keeps sigils")
	G.reset_run()
	ck(G.run_sigils == SG.empty_slots(), "reset_run clears sigils")
	print("sigils_test: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)

func Pickup_reset() -> void:
	# _taken_frame chặn nhặt 2 lần trong cùng khung hình: chờ sang khung mới là đủ (đã await process_frame)
	pass
