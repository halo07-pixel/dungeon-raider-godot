extends SceneTree
## Skill Power/Haste, nội tại class, buff kỹ năng, Gravity Well, Shadow Dash/Rush chí mạng.
## Chạy: godot --headless --path . -s tools/tests/skill_stats_test.gd
var fails: int = 0
func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

const DUMMY_SRC := """
extends Node2D
var alive: bool = true
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

func _init() -> void:
	await process_frame
	var WI = load("res://scripts/weapon_instance.gd")
	var SU = load("res://scripts/skill_upgrades.gd")
	var CS = load("res://scripts/class_skill.gd")
	var G = root.get_node("Global")
	var dscript := GDScript.new()
	dscript.source_code = DUMMY_SRC
	dscript.reload()
	# ---- dữ liệu ----
	ck(not CS.SKILLS.has("phase_step"), "phase_step removed")
	ck(CS.SKILLS.has("gravity_well") and G.classes["mage"]["skill"] == "gravity_well", "mage uses gravity_well")
	ck(SU.for_skill("gravity_well").size() == 4 and SU.for_skill("phase_step").is_empty(), "gravity_well upgrades")
	ck(not SU.has("skup_ps_far"), "old phase step upgrade ids unknown")
	for cid in G.classes:
		ck(G.classes[cid].has("passive"), cid + " has passive")
	G.reset_run()
	G.current_class = "ranger"
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var p = main.player
	var cs = p.class_skill
	ck(cs != null and cs.skill_id == "overdrive", "ranger skill overdrive")
	# ---- buff pool ----
	var seen := {}
	for i in 600:
		for id in G.roll_buff_choices(3):
			seen[id] = true
	for id in ["buff_skill_power", "buff_skill_haste", "buff_skill_surge", "buff_skill_overflow", "buff_skill_echo", "buff_skill_burst", "buff_skill_overload"]:
		ck(seen.has(id), id + " offered")
	# ---- skill power / haste ----
	ck(absf(p.skill_power()) < 0.001 and absf(p.skill_haste()) < 0.001, "starts at zero (ranger)")
	G.apply_buff("buff_skill_power"); G.apply_buff("buff_skill_power")
	G.apply_buff("buff_skill_haste")
	ck(absf(p.skill_power() - 0.24) < 0.001 and absf(p.skill_haste() - 0.10) < 0.001, "stats from buffs")
	ck(absf(cs._effective_cooldown() - 12.0 / 1.10) < 0.01, "haste shortens cooldown: %f" % cs._effective_cooldown())
	ck(absf(cs._dmg_mult() / p._secondary_dmg_mult() - 1.24) < 0.001, "skill power in skill dmg")
	G.run_buffs.clear()
	G.apply_buff("buff_skill_overload")
	ck(absf(p.skill_power() - 0.4) < 0.001 and absf(p.skill_haste() + 0.2) < 0.001, "overload trade-off")
	ck(absf(cs._mult("radius_mult") - 1.2) < 0.001, "overload radius")
	G.run_buffs.clear()
	# ---- nội tại ----
	var dmg_of = func(cls: String, wid: String):
		G.current_class = cls
		p.set_slot(p.active_slot, WI.make(wid, "common"))
		return p._passive_dmg_mult()
	ck(absf(dmg_of.call("ranger", "pistol") - 1.12) < 0.001 and absf(dmg_of.call("ranger", "broadsword") - 1.0) < 0.001, "ranger passive ranged only")
	ck(absf(dmg_of.call("brawler", "broadsword") - 1.12) < 0.001 and absf(dmg_of.call("brawler", "pistol") - 1.0) < 0.001, "brawler passive melee only")
	G.current_class = "mage"
	ck(absf(p.skill_haste() - 0.25) < 0.001, "mage haste passive")
	G.current_class = "rogue"
	ck(absf(p._passive_crit() - 0.15) < 0.001, "rogue crit passive")
	G.current_class = "brawler"
	p.hp = p.max_hp; p.shield = 0.0
	p.hurt_timer.stop()
	var hp0: int = p.hp
	p.take_damage(100, Vector2.ZERO, 0.0, true)
	var took: int = hp0 - p.hp
	var expect: int = int(100.0 * G.enemy_dmg_mult_for_floor(G.floor_num) * 0.92)
	ck(absf(float(took - expect)) <= 1.0, "brawler takes 8%% less (%d vs %d)" % [took, expect])
	p.hp = p.max_hp
	G.current_class = "ranger"
	# ---- Spellburst / Overflow / Surge / Echo ----
	G.run_buffs.clear()
	G.apply_buff("buff_skill_burst"); G.apply_buff("buff_skill_burst")
	ck(absf(p.spellburst_chance() - 0.5) < 0.001, "spellburst chance")
	G.run_buffs.clear()
	G.apply_buff("buff_skill_surge")
	p.shield = 0.0
	p.max_shield = 100
	cs.cooldown_left = 0.0
	p.rolling = false
	ck(cs.try_activate(), "cast")
	ck(absf(p.shield - 20.0) < 0.001, "surge shield")
	G.run_buffs.clear()
	G.apply_buff("buff_skill_overflow")
	cs.cooldown_left = 0.0
	cs.try_activate()
	var cd0: float = cs.cooldown_left
	cs.refund_cooldown(1.0)
	ck(absf(cd0 - cs.cooldown_left - 1.0) < 0.001, "refund 1s")
	cs.refund_cooldown(100.0)
	ck(cs.cooldown_left >= cd0 * 0.5 - 0.001, "refund capped at half cooldown (%f of %f)" % [cs.cooldown_left, cd0])
	G.run_buffs.clear()
	G.apply_buff("buff_skill_echo")
	# vũ khí cận chiến + dummy để đo sát thương đòn đánh (class mage: không có chí mạng ngẫu nhiên từ nội tại)
	G.current_class = "mage"
	p.set_slot(p.active_slot, WI.make("broadsword", "common"))
	var d = Node2D.new()
	d.set_script(dscript)
	d.add_to_group("enemies")
	G.world.add_child(d)
	d.global_position = p.global_position + Vector2(24, 0)
	p.aim_dir = Vector2.RIGHT
	cs.cooldown_left = 0.0
	cs.try_activate() # shadow_dash? ranger cs = overdrive; echo timer set via skill_used
	ck(p.skill_echo_timer > 0.0, "echo armed")
	var swing = func():
		p.fire_timer.stop(); p.swinging = false
		d.hits.clear()
		p.global_position = d.global_position - Vector2(24, 0)
		p._swing()
		return d.hits[0] if d.hits.size() > 0 else 0
	G.run_buffs.clear() # không còn crit buff
	var echoed: int = swing.call()
	var normal: int = swing.call()
	ck(echoed >= normal * 2 - 2 and echoed > normal, "echo doubles next hit (%d vs %d)" % [echoed, normal])
	ck(p.skill_echo_timer == 0.0, "echo consumed")
	# ---- Overdrive pierce ----
	G.current_class = "ranger"
	cs.cooldown_left = 0.0
	cs.try_activate()
	ck(p.skill_pierce_add == 1 and cs.active_left > 0.0, "overdrive pierce on")
	cs.active_left = 0.001
	cs._physics_process(0.1)
	ck(p.skill_pierce_add == 0 and p.skill_attack_cd_mult == 1.0, "overdrive pierce off")
	# ---- Slam stun ----
	var cs_slam = CS.new()
	p.add_child(cs_slam)
	cs_slam.setup(p, "slam")
	d.statuses.clear()
	p.global_position = d.global_position - Vector2(40, 0)
	cs_slam.try_activate()
	ck(d.statuses.any(func(s): return s[0] == "stun" and absf(s[1] - 0.4) < 0.001), "slam stuns 0.4s")
	cs_slam.queue_free()
	# ---- Rogue: crit charges ----
	G.current_class = "rogue"
	G.run_buffs.clear()
	p.rolling = false
	var cs_dash = CS.new()
	p.add_child(cs_dash)
	cs_dash.setup(p, "shadow_dash")
	p.skill_crit_charges = 0
	cs_dash.try_activate()
	ck(p.skill_crit_charges == 1, "dash grants 1 crit charge")
	var cs_rush = CS.new()
	p.add_child(cs_rush)
	cs_rush.setup(p, "shadow_rush")
	p.skill_crit_charges = 0
	cs_rush.try_activate()
	ck(p.skill_crit_charges == 3 and p.skill_attack_cd_mult == 1.0, "rush grants 3 crit charges, no haste")
	G.skill_upgrades_taken.append("skup_sr_frenzy")
	p.skill_crit_charges = 0
	cs_rush.cooldown_left = 0.0
	cs_rush.try_activate()
	ck(p.skill_crit_charges == 5, "bloodlust +2 charges")
	G.skill_upgrades_taken.clear()
	# crit charges consumed by hits (đo bằng sát thương, tắt crit ngẫu nhiên của Rogue passive bằng cách so sánh nhiều lần)
	G.current_class = "mage"
	p.set_slot(p.active_slot, WI.make("broadsword", "common"))
	p.skill_crit_charges = 2
	p.skill_crit_timer = 6.0
	var c1: int = swing.call()
	var c2: int = swing.call()
	ck(p.skill_crit_charges == 0, "charges consumed by swings")
	ck(c1 >= int(float(normal) * 1.9) and c2 >= int(float(normal) * 1.9), "guaranteed crits ~2x (%d,%d vs %d)" % [c1, c2, normal])
	p.skill_crit_charges = 3
	p.skill_crit_timer = 0.05
	await create_timer(0.3).timeout
	ck(p.skill_crit_charges == 0, "charges expire")
	d.queue_free()
	# ---- Gravity Well ----
	G.current_class = "mage"
	G.run_buffs.clear()
	var e = load("res://scenes/enemy.tscn").instantiate()
	e.setup("slime")
	main.dungeon.entities.add_child(e)
	e.global_position = p.global_position + Vector2(100, 0)
	e.active = true
	e.get_node("Hurtbox").max_hp = 99999.0 # kiếm khí còn bay của vũ khí chuẩn có thể giết dummy
	e.get_node("Hurtbox").hp = 99999.0
	e.set_physics_process(false) # chỉ để well kéo qua knockback; ta tự tích hợp knockback bên dưới
	var cs_gw = CS.new()
	p.add_child(cs_gw)
	cs_gw.setup(p, "gravity_well")
	p.aim_dir = Vector2.RIGHT
	ck(absf(cs_gw._effective_cooldown() - 8.0 / 1.25) < 0.01, "mage cooldown 6.4: %f" % cs_gw._effective_cooldown())
	var well_pos: Vector2 = p.global_position + Vector2(100, 0)
	var well = Node2D.new()
	well.set_script(load("res://scripts/gravity_well.gd"))
	well.radius = 130.0
	well.duration = 1.2
	well.tick_damage = 5
	G.world.add_child(well)
	well.global_position = well_pos + Vector2(60, 0)
	var hp0e: float = float(e.hp)
	for i in 40:
		await physics_frame
	ck(float(e.hp) < hp0e, "well damages enemy (%f -> %f)" % [hp0e, e.hp])
	ck(e.knockback.x > 0.0, "well pulls enemy toward centre (kb %s)" % str(e.knockback))
	for i in 60:
		await physics_frame
	ck(not is_instance_valid(well), "well expires")
	# cast through the skill path
	p.global_position = main.dungeon.room_center(main.dungeon.start_cell)
	cs_gw.cooldown_left = 0.0
	cs_gw.try_activate()
	var wells: int = 0
	for n in G.world.get_children():
		if n.get_script() == load("res://scripts/gravity_well.gd"):
			wells += 1
	ck(wells == 1, "cast spawns a well")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
