extends SceneTree
## Hướng tiến hoá A/B: dữ liệu hồ sơ (tương thích save cũ), chọn/đổi hướng, 5 kỹ năng hướng B, nâng cấp, màn Profile.
## Chạy: godot --headless --path . -s tools/tests/class_branches_test.gd
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
var spawn_pos: Vector2 = Vector2.ZERO
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



## Hướng không có tường trong `length` px từ `origin` (dungeon sinh ngẫu nhiên mỗi lần chạy nên không cố định hướng).
func open_dir(p, length: float) -> Vector2:
	for i in 16:
		var d: Vector2 = Vector2.from_angle(TAU * float(i) / 16.0)
		var q := PhysicsRayQueryParameters2D.create(p.global_position, p.global_position + d * (length + 40.0), G.L_WORLD)
		if p.get_world_2d().direct_space_state.intersect_ray(q).is_empty():
			return d
	return Vector2.ZERO

## Đưa Player tới chỗ có hướng bắn thoáng `length` px (quét lưới quanh điểm xuất phát). Trả hướng thoáng; ZERO nếu không tìm được.
func find_open_spot(p, length: float, avoid_mouse: float = 0.0) -> Vector2:
	var start: Vector2 = spawn_pos
	for r in [0, 1, 2, 3, 4, 5, 6, 8, 10, 13]:
		for i in 12:
			var ang: float = TAU * float(i) / 12.0
			p.global_position = start + Vector2.from_angle(ang) * float(r) * 120.0
			if avoid_mouse > 0.0 and p.global_position.distance_to(p.get_global_mouse_position()) < avoid_mouse:
				continue # Blink Nova nhắm theo con trỏ: đứng đủ xa con trỏ để lần dịch chuyển đủ dài
			var pq := PhysicsPointQueryParameters2D.new()
			pq.position = p.global_position
			pq.collision_mask = G.L_WORLD
			if not p.get_world_2d().direct_space_state.intersect_point(pq, 1).is_empty():
				continue
			var d: Vector2 = open_dir(p, length)
			if d != Vector2.ZERO:
				return d
	return Vector2.ZERO

func start_run(cls: String):
	G.reset_run()
	G.current_class = cls
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	return main

func _init() -> void:
	await process_frame
	G = root.get_node("Global")
	var MP = load("res://scripts/meta_progress.gd")
	var CS = load("res://scripts/class_skill.gd")
	var SU = load("res://scripts/skill_upgrades.gd")
	dscript = GDScript.new()
	dscript.source_code = DUMMY_SRC
	dscript.reload()
	# ---- dữ liệu ----
	var ids := {}
	for cid in G.classes:
		ck(MP.EVOLUTION_ALT.has(cid) and MP.EVOLUTIONS.has(cid), cid + " has both paths")
		var a: Dictionary = MP.evolution_at(cid, 1, "a")
		var b: Dictionary = MP.evolution_at(cid, 1, "b")
		ck(not a.is_empty() and not b.is_empty() and a["skill"] != b["skill"] and a["name"] != b["name"], cid + " paths differ")
		ck(a["req"] == b["req"], cid + " same unlock requirement")
		ck(CS.SKILLS.has(String(b["skill"])), "skill %s defined" % b["skill"])
		var ups: Array = SU.for_skill(String(b["skill"]))
		ck(ups.size() == 4, "4 upgrades for " + String(b["skill"]))
		for u in ups:
			ck(not ids.has(u["id"]) and not str(u["desc"]).is_empty(), "unique upgrade id " + String(u["id"]))
			ids[u["id"]] = true
	ck(MP.evolution_at("ranger", 2, "a").is_empty() and MP.evolution_at("ranger", 0, "b").is_empty(), "out-of-range tiers empty")
	# ---- hồ sơ ----
	var P: Dictionary = MP.new_profile()
	ck(MP.cls(P, "mage")["branch"] == "a" and MP.branch_of(P, "mage") == "a", "new entry defaults to a")
	ck(not MP.set_branch(P, "mage", "b"), "can't switch before evolving")
	P["classes"]["mage"] = {"runs": 3, "best_floor": 5, "kills": 10, "bosses": {"lord": 2}, "tier": 0}
	ck(MP.can_evolve(P, "mage"), "mage can evolve")
	ck(MP.evolve(P, "mage", "b"), "evolve to b")
	ck(MP.tier_of(P, "mage") == 1 and MP.branch_of(P, "mage") == "b", "tier 1, branch b")
	ck(MP.active_skill(P, "mage") == "blink_nova" and MP.display_name(P, "mage", "Mage") == "Arcanist", "branch b skill + name")
	ck(MP.set_branch(P, "mage", "a") and MP.active_skill(P, "mage") == "meteor_storm" and MP.display_name(P, "mage", "Mage") == "Mage+", "switch back to a")
	ck(not MP.set_branch(P, "mage", "zzz") and MP.branch_of(P, "mage") == "a", "invalid branch rejected")
	ck(not MP.can_evolve(P, "mage"), "single tier only")
	var Q: Dictionary = MP.new_profile()
	Q["classes"]["rogue"] = {"runs": 1, "best_floor": 2, "kills": 1, "bosses": {"lord": 2}, "tier": 0}
	ck(MP.evolve(Q, "rogue") and MP.branch_of(Q, "rogue") == "a" and MP.active_skill(Q, "rogue") == "shadow_rush", "default evolve = path a (old behaviour)")
	# save cũ: không có khoá branch
	var old: Dictionary = MP.merge_loaded({"classes": {"ranger": {"runs": 4, "best_floor": 6, "kills": 9, "bosses": {"lord": 2}, "tier": 1}}})
	ck(MP.branch_of(old, "ranger") == "a" and MP.active_skill(old, "ranger") == "barrage", "old save loads as path a")
	var newer: Dictionary = MP.merge_loaded({"classes": {"ranger": {"tier": 1, "branch": "b"}, "mage": {"tier": 1, "branch": "garbage"}}})
	ck(MP.active_skill(newer, "ranger") == "railshot" and MP.branch_of(newer, "mage") == "a", "branch b loads; garbage -> a")
	# ---- Global.class_skill_id_for theo hướng ----
	var saved_profile: Dictionary = G.profile
	G.profile = P
	MP.set_branch(P, "mage", "b")
	ck(G.class_skill_id_for("mage") == "blink_nova", "Global uses chosen branch")
	G.profile = saved_profile
	# ---- Kỹ năng hướng B ----
	var main = await start_run("ranger")
	var p = main.player
	var cs = p.class_skill
	spawn_pos = p.global_position
	p.aim_dir = Vector2.RIGHT
	# Railshot
	cs.setup(p, "railshot")
	await clear_all()
	var dir: Vector2 = find_open_spot(p, 700.0)
	ck(dir != Vector2.ZERO, "found open firing lane for tests")
	var side: Vector2 = dir.orthogonal()
	var on_line = dummy(p.global_position + dir * 300.0)
	var on_line2 = dummy(p.global_position + dir * 520.0 + side * 6.0)
	var off_line = dummy(p.global_position + dir * 300.0 + side * 90.0)
	var behind = dummy(p.global_position - dir * 200.0)
	cs.cooldown_left = 0.0
	p.aim_dir = dir # Player ghi đè aim_dir mỗi khung hình theo con trỏ: đặt ngay trước khi tung
	ck(cs.try_activate(), "railshot cast")
	ck(on_line.total > 0 and on_line2.total > 0, "railshot pierces everything on the line")
	ck(off_line.total == 0 and behind.total == 0, "railshot misses off-line / behind")
	ck(on_line.statuses.any(func(s): return s[0] == "bleed"), "railshot causes bleed")
	# Charge
	cs.setup(p, "charge")
	await clear_all()
	dir = find_open_spot(p, 400.0)
	side = dir.orthogonal()
	var rammed = dummy(p.global_position + dir * 120.0)
	var bystander = dummy(p.global_position + dir * 120.0 + side * 120.0)
	p.shield = 0.0
	var x0: Vector2 = p.global_position
	cs.cooldown_left = 0.0
	p.aim_dir = dir
	cs.try_activate()
	ck(p.global_position.distance_to(x0) > 150.0, "charge moves the player (%.0f)" % p.global_position.distance_to(x0))
	ck(rammed.total > 0 and bystander.total == 0, "charge hits the path only")
	ck(p.shield >= minf(40.0, float(p.max_shield)) - 0.01, "charge grants shield")
	G.skill_upgrades_taken.append("skup_ch_stun")
	await clear_all()
	dir = find_open_spot(p, 400.0)
	var stunned = dummy(p.global_position + dir * 100.0)
	cs.cooldown_left = 0.0
	p.aim_dir = dir
	cs.try_activate()
	ck(stunned.statuses.any(func(s): return s[0] == "stun"), "stunning charge upgrade stuns")
	G.skill_upgrades_taken.clear()
	# Blink Nova
	cs.setup(p, "blink_nova")
	await clear_all()
	dir = find_open_spot(p, 450.0, 450.0)
	side = dir.orthogonal()
	var origin: Vector2 = p.global_position
	var here = dummy(origin + dir * 50.0)
	var there = dummy(origin + dir * 330.0)
	var far2 = dummy(origin + dir * 170.0 + side * 300.0)
	cs.cooldown_left = 0.0
	p.aim_dir = dir
	cs.try_activate()
	ck(p.global_position.distance_to(origin) > 150.0, "blink relocates (%.0f)" % p.global_position.distance_to(origin))
	ck(here.total > 0 and there.total > 0 and far2.total == 0, "blink blasts both ends (%d / %d)" % [here.total, there.total])
	# Smoke Veil
	cs.setup(p, "smoke_veil")
	await clear_all()
	p.global_position = Vector2(2000, 2000)
	var smoked = dummy(p.global_position + Vector2(60, 0))
	p.skill_crit_charges = 0
	cs.cooldown_left = 0.0
	cs.try_activate()
	var cloud = null
	for c in G.world.get_children():
		if c.get("pull_mult") != null and float(c.pull_mult) == 0.0:
			cloud = c
	ck(cloud != null, "smoke cloud spawned (no pull)")
	ck(p.skill_crit_charges >= 1 and p.is_invulnerable(), "smoke grants crit + brief invulnerability")
	await wait(1.2)
	ck(smoked.total > 0 and smoked.statuses.any(func(s): return s[0] == "slow"), "smoke damages + slows (%d)" % smoked.total)
	# Soul Detonation
	var m2 = await start_run("summoner")
	p = m2.player
	cs = p.class_skill
	p.global_position = Vector2(2000, 2000)
	cs.setup(p, "soul_detonation")
	await clear_all()
	cs.cooldown_left = 0.0
	cs.try_activate()
	ck(cs.cooldown_left <= 1.0, "no minions: nearly refunded (%.2f)" % cs.cooldown_left)
	await clear_all()
	var MN = load("res://scripts/minion.gd")
	var victim = dummy(p.global_position + Vector2(200, 0))
	var bystand2 = dummy(p.global_position + Vector2(900, 0))
	for i in 3:
		var mm = MN.spawn(p, "guardian", victim.global_position + Vector2(20 * i, 0), 1.0, 1.0, i, "class")
		mm.set_meta("summoned", true)
	var blades = MN.spawn(p, "blades", p.global_position, 1.0)
	await process_frame
	cs.cooldown_left = 0.0
	cs.try_activate()
	await process_frame
	var left: int = 0
	for m in root.get_tree().get_nodes_in_group("minions"):
		if is_instance_valid(m) and not m.is_queued_for_deletion() and m.kind == "guardian":
			left += 1
	ck(left == 0, "all combat minions detonated")
	ck(victim.hits.size() == 3 and bystand2.total == 0, "each minion blasts once (%d hits)" % victim.hits.size())
	ck(is_instance_valid(blades) and not blades.is_queued_for_deletion(), "blades (orbit) not detonated")
	ck(cs.cooldown_left >= cs.cooldown_total * 0.5 - 0.01 and cs.cooldown_left < cs.cooldown_total, "refunded, never more than half (%.2f/%.2f)" % [cs.cooldown_left, cs.cooldown_total])
	# ---- màn Profile dựng được ở cả 2 hướng ----
	G.profile = MP.merge_loaded({"classes": {"ranger": {"runs": 1, "best_floor": 3, "kills": 5, "bosses": {"lord": 2}, "tier": 0}, "mage": {"tier": 1, "branch": "b"}, "summoner": {"tier": 1, "branch": "a"}}})
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	menu._refresh_profile()
	await process_frame
	var btn_texts: Array = []
	var stack: Array = [menu.profile_box]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button:
			btn_texts.append(String(n.text))
		stack.append_array(n.get_children())
	var joined: String = " | ".join(PackedStringArray(btn_texts))
	ck(joined.contains("DEADEYE") and joined.contains("RANGER+"), "ranger shows both evolve choices: " + joined)
	ck(joined.contains("Blink Nova") and joined.contains("Meteor Storm"), "evolved mage shows both branch buttons")
	menu._evolve("ranger", "b")
	ck(MP.active_skill(G.profile, "ranger") == "railshot", "menu evolve picks branch b")
	menu._switch_branch("mage", "a")
	ck(MP.active_skill(G.profile, "mage") == "meteor_storm", "menu switch branch")
	print("class_branches_test: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)
