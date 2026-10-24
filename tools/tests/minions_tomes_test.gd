extends SceneTree
## Khung lính (Minion), ô Tome (phím F), 8 Tome, pickup Tome, lưu/khôi phục.
## Chạy: godot --headless --path . -s tools/tests/minions_tomes_test.gd
var fails: int = 0
func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

const DUMMY_SRC := """
extends Node2D
var alive: bool = true
var active: bool = true
var data: Dictionary = {"radius": 14.0}
var total: int = 0
var hits: Array = []
var statuses: Array = []
func kill() -> void: pass
func hurt_center() -> Vector2: return global_position
func take_damage(d: int, _pos = Vector2.ZERO, _k = 0.0, _t = false) -> void:
	total += d
	hits.append(d)
func apply_element(_a = null, _b = null, _c = null) -> void: pass
func apply_status(t = null, d = 0.0, _c = null) -> void: statuses.append([t, d])
func apply_sunder() -> void: pass
"""

var dscript: GDScript
var G
var main
var p

func dummy(pos: Vector2) -> Node2D:
	var d := Node2D.new()
	d.set_script(dscript)
	d.add_to_group("enemies")
	G.world.add_child(d)
	d.global_position = pos
	return d

func clear_all() -> void:
	for n in get_nodes_in_group_safe("enemies"):
		n.queue_free()
	for n in get_nodes_in_group_safe("minions"):
		n.queue_free()
	for n in get_nodes_in_group_safe("enemy_bullets"):
		n.queue_free()
	await process_frame

func get_nodes_in_group_safe(g: String) -> Array:
	return root.get_tree().get_nodes_in_group(g)

func wait(sec: float) -> void:
	await create_timer(sec).timeout

func _init() -> void:
	await process_frame
	G = root.get_node("Global")
	var TS = load("res://scripts/tome_skill.gd")
	var MN = load("res://scripts/minion.gd")
	dscript = GDScript.new()
	dscript.source_code = DUMMY_SRC
	dscript.reload()
	# ---- dữ liệu ----
	ck(TS.ORDER.size() == 8 and TS.TOMES.size() == 8, "8 tomes")
	for id in TS.ORDER:
		ck(TS.TOMES.has(id) and TS.new().has_method("_cast_" + id), "tome %s has data + cast" % id)
	for k in MN.KINDS:
		ck(["chase", "shoot", "guard", "totem", "orbit"].has(String(MN.KINDS[k]["mode"])), "minion kind %s valid mode" % k)
	ck(InputMap.has_action("tome"), "tome action exists")
	var keys: Array = []
	for ev in InputMap.action_get_events("tome"):
		keys.append(ev.physical_keycode)
	ck(keys == [KEY_F], "tome key is F")
	for other in ["interact", "restart", "skill", "dodge", "swap_weapon", "confirm"]:
		for ev in InputMap.action_get_events(other):
			if ev is InputEventKey:
				ck(ev.physical_keycode != KEY_F, "F not used by " + other)
	# ---- vào ván ----
	G.reset_run()
	G.current_class = "mage"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	p = main.player
	ck(p.tome_skill == null and G.run_tome == "", "no tome at start")
	# ---- equip / đổi ----
	ck(p.equip_tome("nope") == "" and p.tome_skill == null, "invalid tome ignored")
	ck(p.equip_tome("frost_nova") == "" and p.tome_skill != null and p.tome_skill.skill_id == "frost_nova", "equip first tome")
	ck(G.run_tome == "frost_nova", "run_tome stored")
	ck(p.equip_tome("storm_bolt") == "frost_nova" and p.tome_skill.skill_id == "storm_bolt", "swap returns old")
	ck(p.tome_skill.cooldown_left > 0.0, "swapped tome starts on cooldown")
	ck(p.equip_tome("storm_bolt") == "", "same tome: nothing displaced")
	var saved: Dictionary = main._build_saved_run()
	ck(String(saved.get("tome", "")) == "storm_bolt", "saved_run keeps tome")
	var ids: Array = G.random_tome_ids(3, ["storm_bolt"])
	ck(ids.size() == 3 and not ids.has("storm_bolt"), "random_tome_ids excludes held")
	ck(G.random_tome_ids(99).size() == 8, "random_tome_ids capped")
	# ---- haste/power áp cho Tome ----
	p.equip_tome("frost_nova")
	var cd0: float = p.tome_skill._effective_cooldown()
	G.apply_buff("buff_skill_haste")
	ck(p.tome_skill._effective_cooldown() < cd0, "haste shortens tome cooldown")
	var pw0: float = p.tome_skill.power()
	G.apply_buff("buff_skill_power")
	ck(p.tome_skill.power() > pw0, "power raises tome power")
	G.run_buffs.clear()
	# ---- Frost Nova ----
	await clear_all()
	p.global_position = Vector2(2000, 2000)
	var near = dummy(p.global_position + Vector2(60, 0))
	var far = dummy(p.global_position + Vector2(400, 0))
	p.tome_skill.cooldown_left = 0.0
	ck(p.tome_skill.try_activate(), "frost nova cast")
	ck(near.total > 0 and far.total == 0, "nova hits only in radius")
	ck(near.statuses.any(func(s): return s[0] == "stun") and near.statuses.any(func(s): return s[0] == "slow"), "nova stun + slow")
	ck(not p.tome_skill.is_ready(), "cooldown started")
	ck(not p.tome_skill.try_activate(), "can't cast on cooldown")
	# ---- Storm Bolt ----
	await clear_all()
	p.equip_tome("storm_bolt")
	p.tome_skill.cooldown_left = 0.0
	p.global_position = p.get_global_mouse_position() # con trỏ trùng Player: mục tiêu đầu = quái gần nhất
	var line: Array = []
	for i in 7:
		line.append(dummy(p.global_position + Vector2(100 + 60 * i, 0)))
	p.tome_skill._cast_storm_bolt()
	var hit_n: int = 0
	for d in line:
		if d.total > 0:
			hit_n += 1
	ck(hit_n == 5, "storm bolt jumps to 5 enemies (got %d)" % hit_n)
	ck(line[0].hits[0] > line[4].hits[0], "bolt falls off per jump")
	await clear_all()
	p.global_position = Vector2(2000, 2000)
	p.tome_skill.cooldown_left = 5.0
	p.tome_skill._cast_storm_bolt()
	ck(p.tome_skill.cooldown_left <= 1.0, "no target: cooldown nearly refunded")
	# ---- Black Hole ----
	await clear_all()
	p.equip_tome("black_hole")
	p.tome_skill.cooldown_left = 0.0
	var victim = dummy(p.global_position + Vector2(40, 0))
	var holes_before: int = 0
	p.tome_skill._cast_black_hole()
	var hole = null
	for c in G.world.get_children():
		if c.get("end_dmg") != null and int(c.end_dmg) > 0:
			hole = c
	ck(hole != null and hole.pull_mult > 1.0, "black hole spawned")
	if hole != null:
		hole.global_position = victim.global_position
		hole.duration = 0.5
		var end_dmg: int = int(hole.end_dmg)
		await wait(0.9)
		ck(victim.hits.has(end_dmg), "black hole exploded on collapse (hits %s want %d)" % [str(victim.hits), end_dmg])
	# ---- Minion: spirit đuổi + đánh ----
	await clear_all()
	var tgt = dummy(p.global_position + Vector2(160, 0))
	var sp = MN.spawn(p, "spirit", p.global_position, 1.0)
	await wait(1.6)
	ck(tgt.total > 0, "spirit chased and hit target (total %d)" % tgt.total)
	ck(sp.get_collision_layer() == 0, "minion has no collision layer")
	# ---- Minion hết hạn ----
	var shortlived = MN.spawn(p, "spirit", p.global_position, 1.0, 0.02)
	var exp_flag := [false]
	shortlived.expired.connect(func(_k, _pos): exp_flag[0] = true)
	await wait(0.5)
	ck(exp_flag[0] and not is_instance_valid(shortlived), "minion expires + signal")
	# ---- Minion hết hạn khi chủ chết ----
	var orphan = MN.spawn(p, "spirit", p.global_position, 1.0)
	p.alive = false
	await wait(0.2)
	ck(not is_instance_valid(orphan), "minion removed when owner dies")
	p.alive = true
	# ---- Turret bắn + giới hạn 2 ----
	await clear_all()
	p.equip_tome("arc_turret")
	p.tome_skill.cooldown_left = 0.0
	p.global_position = p.get_global_mouse_position() # turret đặt ngay chỗ Player
	var t2 = dummy(p.global_position + Vector2(200, 0))
	for i in 3:
		p.tome_skill._cast_arc_turret()
	await process_frame
	var turrets: int = 0
	for m in root.get_tree().get_nodes_in_group("minions"):
		if is_instance_valid(m) and not m.is_queued_for_deletion() and m.kind == "turret":
			turrets += 1
	ck(turrets == 2, "turret cap 2 (got %d)" % turrets)
	var shot_ct := [0]
	G.world.child_entered_tree.connect(func(n): if n.get_script() != null and String(n.get_script().resource_path).ends_with("bullet.gd"): shot_ct[0] += 1)
	await wait(0.9)
	var shots: int = shot_ct[0]
	ck(shots > 0, "turret fired bullets at the target (%d shots)" % shots)
	# ---- Ward Barrier chặn đạn ----
	await clear_all()
	var wm = MN.spawn(p, "ward", p.global_position + Vector2(100, 0), 1.0)
	var eb := Node2D.new()
	eb.add_to_group("enemy_bullets")
	G.world.add_child(eb)
	eb.global_position = wm.global_position + Vector2(20, 0)
	var eb_far := Node2D.new()
	eb_far.add_to_group("enemy_bullets")
	G.world.add_child(eb_far)
	eb_far.global_position = wm.global_position + Vector2(300, 0)
	await wait(0.2)
	ck(not is_instance_valid(eb) and is_instance_valid(eb_far), "ward destroys nearby enemy bullet only")
	# ---- Totem hồi máu ----
	await clear_all()
	p.hp = 10
	var tm = MN.spawn(p, "totem", p.global_position, 1.0)
	await wait(1.8)
	ck(p.hp > 10, "totem heals owner (hp %d)" % p.hp)
	p.hp = p.max_hp
	# ---- Blade Dance ----
	await clear_all()
	p.equip_tome("blade_dance")
	p.tome_skill.cooldown_left = 0.0
	var bt = dummy(p.global_position + Vector2(72, 0))
	p.tome_skill._cast_blade_dance()
	await wait(1.5)
	ck(bt.total > 0, "blades cut enemy on the orbit (total %d)" % bt.total)
	# ---- Spirit Pact ----
	await clear_all()
	p.equip_tome("spirit_pact")
	p.tome_skill.cooldown_left = 0.0
	p.tome_skill._cast_spirit_pact()
	await process_frame
	var spirits: int = 0
	for m in root.get_tree().get_nodes_in_group("minions"):
		if m.kind == "spirit":
			spirits += 1
	ck(spirits == 2, "spirit pact summons 2 (got %d)" % spirits)
	# ---- Pickup Tome ----
	await clear_all()
	p.equip_tome("frost_nova")
	var dropped: Array = []
	G.tome_drop_requested.connect(func(id, pos): dropped.append(id))
	var pk = load("res://scenes/pickup.tscn").instantiate()
	pk.setup("tome", "black_hole")
	G.world.add_child(pk)
	pk.global_position = p.global_position
	pk._near = true
	pk._lock = 0.0
	pk.choice_group = 777
	var pk2 = load("res://scenes/pickup.tscn").instantiate()
	pk2.setup("tome", "bulwark_none" if false else "arc_turret")
	pk2.choice_group = 777
	G.world.add_child(pk2)
	pk2.global_position = p.global_position + Vector2(500, 0)
	pk._try_take_tome()
	await process_frame
	ck(p.tome_skill.skill_id == "black_hole", "pickup equips tome")
	ck(dropped == ["frost_nova"], "old tome dropped via signal")
	ck(not is_instance_valid(pk2), "other tome in choice group vanishes")
	# ---- Chặn dmg_k = 0 ----
	ck(MN.spawn(p, "guardian", p.global_position, 5.0).dmg == 0, "guardian deals no damage")
	# ---- Dungeon: chọn Tome không trùng Tome đang cầm ----
	var dun = main.get_node_or_null("Dungeon")
	if dun == null:
		for c in main.get_children():
			if c.has_method("_spawn_tome_choice"):
				dun = c
	if dun != null:
		await clear_all()
		for n in root.get_tree().get_nodes_in_group("tome_pickup"):
			n.queue_free()
		await process_frame
		dun._spawn_tome_choice(p.global_position + Vector2(0, 600), 2)
		await process_frame
		var offered: Array = []
		for n in root.get_tree().get_nodes_in_group("tome_pickup"):
			offered.append(n.extra)
		ck(offered.size() == 2 and not offered.has("black_hole"), "tome choice: 2 offered, none is held: %s" % str(offered))
	else:
		print("NOTE: dungeon node not found, skipped choice test")
	# ---- Tome hiếm: chỉ boss tầng 6 và 12 ----
	ck(G.BOSS_TOME_FLOORS == [6, 12], "tome drops only from bosses on floors 6 and 12")
	var tdun = main.get_node_or_null("Dungeon")
	ck(tdun == null or not (tdun.get_script().source_code.contains("_spawn_tome_choice(room_center(cell) + Vector2(0.0, 80.0)")), "treasure room no longer offers tomes")
	print("minions_tomes_test: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)
