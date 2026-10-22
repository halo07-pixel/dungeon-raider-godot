extends SceneTree
## Ultimate: thanh nộ (nạp bằng đòn trúng/hạ gục/nhận sát thương), 5 chiêu cuối, phím X, lưu/khôi phục.
## Chạy: godot --headless --path . -s tools/tests/ultimate_test.gd
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


func count_minions(kind: String = "") -> int:
	var n: int = 0
	for m in root.get_tree().get_nodes_in_group("minions"):
		if is_instance_valid(m) and not m.is_queued_for_deletion() and (kind == "" or m.kind == kind):
			n += 1
	return n

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
	var UL = load("res://scripts/ultimate.gd")
	dscript = GDScript.new()
	dscript.source_code = DUMMY_SRC
	dscript.reload()
	# ---- dữ liệu ----
	for cid in G.classes:
		var uid: String = String(G.classes[cid].get("ultimate", ""))
		ck(UL.exists(uid), "class %s has valid ultimate (%s)" % [cid, uid])
		ck(UL.new().has_method("_start_" + uid) and UL.new().has_method("_tick_" + uid), "ultimate %s has start/tick" % uid)
	ck(InputMap.has_action("ultimate"), "ultimate action exists")
	var keys: Array = []
	for ev in InputMap.action_get_events("ultimate"):
		keys.append(ev.physical_keycode)
	ck(keys == [KEY_X], "ultimate key is X")
	for other in InputMap.get_actions():
		if other == "ultimate" or String(other).begins_with("ui_"):
			continue
		for ev in InputMap.action_get_events(other):
			if ev is InputEventKey:
				ck(ev.physical_keycode != KEY_X, "X not used by " + String(other))
	# ---- nạp thanh nộ ----
	var main = await start_run("ranger")
	var p = main.player
	var u = p.ultimate
	ck(u != null and u.ult_id == "bullet_storm", "ranger has bullet storm")
	ck(u.meter() == 0.0 and not u.is_ready(), "starts empty")
	await clear_all()
	p.global_position = Vector2(2000, 2000)
	var t = dummy(p.global_position + Vector2(60, 0))
	G.on_player_hit(t, 10, false)
	ck(absf(u.meter() - UL.HIT_CHARGE) < 0.001, "a hit charges %.2f (got %.2f)" % [UL.HIT_CHARGE, u.meter()])
	var m0: float = u.meter()
	var dying = dummy(p.global_position + Vector2(60, 0), 1)
	dying.take_damage(5)
	G.on_player_hit(dying, 5, false)
	ck(u.meter() > m0 + UL.KILL_CHARGE - 0.01, "kill gives bonus charge")
	# giới hạn nạp từ đòn trúng mỗi giây
	G.run_ult_meter = 0.0
	u._budget = UL.HIT_BUDGET_MAX
	for i in 200:
		G.on_player_hit(t, 10, false)
	ck(u.meter() <= UL.HIT_BUDGET_MAX + 0.01, "hit charge limited by budget (%.2f)" % u.meter())
	# nhận sát thương nạp
	G.run_ult_meter = 0.0
	G.player_damaged.emit(int(p.max_hp * 0.1), p.max_hp)
	ck(absf(u.meter() - 6.0) < 0.01, "10%% max hp damage -> +6 (%.2f)" % u.meter())
	G.player_damaged.emit(p.max_hp * 5, p.max_hp)
	ck(absf(u.meter() - 21.0) < 0.01, "taken charge capped per hit (%.2f)" % u.meter())
	# đầy + signal
	var ready_flag := [false]
	u.ultimate_ready.connect(func(): ready_flag[0] = true)
	G.run_ult_meter = 99.5
	u.add_charge(5.0)
	ck(u.meter() == UL.METER_MAX and u.is_ready() and ready_flag[0], "caps at max + ready signal")
	# không tung khi chưa đầy
	G.run_ult_meter = 50.0
	ck(not u.try_activate() and u.meter() == 50.0, "can't cast when not full")
	# ---- Bullet Storm ----
	G.run_ult_meter = 100.0
	var shot_ct := [0]
	G.world.child_entered_tree.connect(func(n): if n.get_script() != null and String(n.get_script().resource_path).ends_with("bullet.gd"): shot_ct[0] += 1)
	ck(u.try_activate(), "storm cast")
	ck(u.meter() == 0.0 and u.active_left > 0.0, "meter reset, active")
	u.add_charge(10.0)
	ck(u.meter() == 0.0, "no charging during the ultimate")
	await wait(1.0)
	ck(shot_ct[0] >= UL.STORM_BULLETS * 3, "storm fires rings (%d bullets)" % shot_ct[0])
	u.active_left = 0.0
	# ---- Earthquake ----
	await clear_all()
	var m2 = await start_run("brawler")
	p = m2.player
	u = p.ultimate
	ck(u.ult_id == "earthquake", "brawler has earthquake")
	p.global_position = Vector2(2000, 2000)
	var near = dummy(p.global_position + Vector2(100, 0))
	var far = dummy(p.global_position + Vector2(600, 0))
	var eb := Node2D.new()
	eb.add_to_group("enemy_bullets")
	G.world.add_child(eb)
	eb.global_position = p.global_position + Vector2(50, 0)
	G.run_ult_meter = 100.0
	ck(u.try_activate(), "quake cast")
	ck(near.hits.size() == 1 and far.total == 0, "first pulse hits near only")
	ck(not is_instance_valid(eb) or eb.is_queued_for_deletion(), "quake clears bullets")
	ck(near.statuses.any(func(s): return s[0] == "stun"), "quake stuns")
	await wait(1.3)
	ck(near.hits.size() == 3, "3 pulses (got %d)" % near.hits.size())
	# ---- Starfall ----
	await clear_all()
	var m3 = await start_run("mage")
	p = m3.player
	u = p.ultimate
	ck(u.ult_id == "starfall", "mage has starfall")
	p.global_position = Vector2(2000, 2000)
	var crowd: Array = []
	for i in 12:
		crowd.append(dummy(p.global_position + Vector2.from_angle(TAU * float(i) / 12.0) * 150.0))
	G.run_ult_meter = 100.0
	ck(u.try_activate(), "starfall cast")
	await wait(5.0)
	var dealt: int = 0
	for e in crowd:
		dealt += e.total
	ck(dealt > 0, "starfall meteors landed (%d dmg)" % dealt)
	# ---- Blade Tempest ----
	await clear_all()
	var m4 = await start_run("rogue")
	p = m4.player
	u = p.ultimate
	ck(u.ult_id == "blade_tempest", "rogue has tempest")
	p.global_position = Vector2(2000, 2000)
	var tn = dummy(p.global_position + Vector2(70, 0))
	var tf = dummy(p.global_position + Vector2(500, 0))
	G.run_ult_meter = 100.0
	ck(u.try_activate(), "tempest cast")
	await process_frame
	ck(p.is_invulnerable(), "invulnerable during tempest")
	await wait(1.0)
	ck(tn.hits.size() >= 4 and tf.total == 0, "tempest ticks near enemy only (%d)" % tn.hits.size())
	await wait(2.4)
	ck(u.active_left == 0.0, "tempest ended")
	# ---- Horde ----
	await clear_all()
	var m5 = await start_run("summoner")
	p = m5.player
	u = p.ultimate
	ck(u.ult_id == "horde", "summoner has horde")
	p.global_position = Vector2(2000, 2000)
	p.class_skill._summon()
	p.class_skill._summon()
	G.run_ult_meter = 100.0
	ck(u.try_activate(), "horde cast")
	await process_frame
	ck(count_minions("spirit") >= 3 and count_minions("wisp") >= 2 and count_minions("guardian") >= 1, "horde summoned 3/2/1 (spirit %d wisp %d guardian %d)" % [count_minions("spirit"), count_minions("wisp"), count_minions("guardian")])
	ck(count_minions() >= 6, "horde ignores the 2-minion cap")
	# ---- chết thì không tung ----
	G.run_ult_meter = 100.0
	u.active_left = 0.0
	p.alive = false
	ck(not u.try_activate(), "can't cast while dead")
	p.alive = true
	# ---- lưu / khôi phục ----
	G.run_ult_meter = 42.0
	var saved: Dictionary = m5._build_saved_run()
	ck(absf(float(saved["ult_meter"]) - 42.0) < 0.001, "saved_run keeps meter")
	G.reset_run()
	ck(G.run_ult_meter == 0.0, "reset_run clears meter")
	print("ultimate_test: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)
