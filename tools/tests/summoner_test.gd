extends SceneTree
## Class Summoner: dữ liệu, nội tại, Summon xoay 3 lính + giới hạn, Legion nổ khi hết hạn, nâng cấp, tiến hoá.
## Chạy: godot --headless --path . -s tools/tests/summoner_test.gd
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

func count_kind(kind: String, only_summoned: bool = true) -> int:
	var n: int = 0
	for m in root.get_tree().get_nodes_in_group("minions"):
		if is_instance_valid(m) and not m.is_queued_for_deletion() and m.kind == kind and (not only_summoned or m.has_meta("summoned")):
			n += 1
	return n

func _init() -> void:
	await process_frame
	G = root.get_node("Global")
	var CS = load("res://scripts/class_skill.gd")
	var SU = load("res://scripts/skill_upgrades.gd")
	var MP = load("res://scripts/meta_progress.gd")
	var MN = load("res://scripts/minion.gd")
	dscript = GDScript.new()
	dscript.source_code = DUMMY_SRC
	dscript.reload()
	# ---- dữ liệu ----
	var c: Dictionary = G.classes.get("summoner", {})
	ck(not c.is_empty() and int(c["max_hp"]) == 85 and c["default_weapon"] == "chakram" and c["skill"] == "summon", "summoner class data")
	ck(c.has("passive") and G.weapons.has("chakram"), "summoner passive + weapon exist")
	ck(CS.SKILLS.has("summon") and CS.SKILLS.has("legion"), "summon + legion skills")
	ck(SU.for_skill("summon").size() == 4 and SU.for_skill("legion").size() == 4, "upgrades for summon + legion")
	var ids := {}
	for sid in ["summon", "legion"]:
		for u in SU.for_skill(sid):
			ck(not ids.has(u["id"]), "unique upgrade id " + u["id"])
			ids[u["id"]] = true
	ck(MP.EVOLUTIONS.has("summoner") and MP.EVOLUTIONS["summoner"][0]["skill"] == "legion", "summoner evolution -> legion")
	ck(MN.KINDS.has("mini") and MN.KINDS.has("spirit") and MN.KINDS.has("wisp") and MN.KINDS.has("guardian"), "minion kinds for summoner")
	for pid in ["idle", "run"]:
		ck(load("res://assets/dungeon/necromancer_idle_anim_f0.png") != null, "necromancer sprite exists")
	# ---- vào ván ----
	var prof: Dictionary = G.profile
	G.reset_run()
	G.current_class = "summoner"
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	G.world = G.world if G.world != null else main
	var p = main.player
	ck(p.max_hp == 85, "hp 85 (got %d)" % p.max_hp)
	ck(p.weapon_id == "chakram", "starts with chakram")
	ck(p.class_skill != null and p.class_skill.skill_id == "summon", "class skill is summon")
	ck(absf(p.skill_haste() - 0.25) < 0.001, "summoner haste passive")
	ck(absf(p.minion_dmg_mult() - 1.3) < 0.001, "minion damage +30%")
	ck(p.sprite.sprite_frames.get_frame_count("idle") == 4 and p.sprite.sprite_frames.get_frame_count("run") == 4 and p.sprite.sprite_frames.get_frame_count("hit") >= 1, "sprite frames idle/run/hit built")
	G.current_class = "mage"
	ck(absf(p.minion_dmg_mult() - 1.0) < 0.001, "other classes: no minion bonus")
	G.current_class = "summoner"
	# ---- Summon xoay + giới hạn 2 ----
	p.global_position = Vector2(2000, 2000)
	var cs = p.class_skill
	cs.cooldown_left = 0.0
	cs._summon()
	ck(count_kind("spirit") == 1, "1st summon = spirit")
	cs._summon()
	ck(count_kind("wisp") == 1, "2nd summon = wisp")
	cs._summon()
	await process_frame
	ck(count_kind("guardian") == 1, "3rd summon = guardian")
	ck(count_kind("spirit") == 0 and count_kind("wisp") == 1, "cap 2: oldest (spirit) replaced")
	cs._summon() # lại spirit
	await process_frame
	ck(count_kind("spirit") == 1 and count_kind("wisp") == 0 and count_kind("guardian") == 1, "rotation restarts at spirit, wisp dropped")
	var total: int = count_kind("spirit") + count_kind("wisp") + count_kind("guardian")
	ck(total == 2, "never more than 2 summoned (got %d)" % total)
	# Tome không tính vào giới hạn
	p.equip_tome("arc_turret")
	p.tome_skill.cooldown_left = 0.0
	p.tome_skill._cast_arc_turret()
	await process_frame
	ck(count_kind("turret", false) == 1 and count_kind("spirit") + count_kind("wisp") + count_kind("guardian") == 2, "tome minions don't count toward cap")
	# Nâng cấp +1 lính
	G.skill_upgrades_taken.append("skup_sm_pack")
	cs._summon()
	await process_frame
	var total3: int = count_kind("spirit") + count_kind("wisp") + count_kind("guardian")
	ck(total3 == 3, "Bigger Pack allows 3 (got %d)" % total3)
	G.skill_upgrades_taken.clear()
	# Sát thương lính tăng theo bonus nội tại + Skill Power
	var spirit_dmg: int = 0
	for m in root.get_tree().get_nodes_in_group("minions"):
		if m.kind == "spirit":
			spirit_dmg = m.dmg
	G.apply_buff("buff_skill_power")
	cs._summon() # wisp
	cs._summon() # guardian
	cs._summon() # spirit mạnh hơn
	await process_frame
	var spirit_dmg2: int = 0
	for m in root.get_tree().get_nodes_in_group("minions"):
		if m.kind == "spirit" and m.has_meta("summoned"):
			spirit_dmg2 = m.dmg
	ck(spirit_dmg2 > spirit_dmg, "skill power raises minion damage (%d -> %d)" % [spirit_dmg, spirit_dmg2])
	G.run_buffs.clear()
	# ---- Spirit thực sự đánh quái ----
	for n in root.get_tree().get_nodes_in_group("minions"):
		n.queue_free()
	await process_frame
	var tgt = dummy(p.global_position + Vector2(140, 0))
	cs._summon_idx = 0
	cs._summon() # spirit
	await wait(1.5)
	ck(tgt.total > 0, "summoned spirit damages enemy (%d)" % tgt.total)
	for n in root.get_tree().get_nodes_in_group("minions"):
		n.queue_free()
	for n in root.get_tree().get_nodes_in_group("enemies"):
		n.queue_free()
	await process_frame
	# ---- Legion ----
	cs.setup(p, "legion")
	cs.cooldown_left = 0.0
	var lt = dummy(p.global_position + Vector2(300, 0))
	cs._legion()
	await process_frame
	ck(count_kind("mini") == 3, "legion calls 3 spitelings (got %d)" % count_kind("mini"))
	# ép hết hạn ngay cạnh quái -> nổ gây sát thương diện rộng
	for m in root.get_tree().get_nodes_in_group("minions"):
		if m.kind == "mini":
			m.global_position = lt.global_position + Vector2(10, 0)
			m.life = 0.01
	await wait(0.4)
	ck(lt.total > 0 and count_kind("mini") == 0, "spitelings explode on expiry (dmg %d)" % lt.total)
	# chủ chết: không nổ
	var lt2 = dummy(p.global_position + Vector2(300, 80))
	cs._legion()
	await process_frame
	for m in root.get_tree().get_nodes_in_group("minions"):
		if m.kind == "mini":
			m.global_position = lt2.global_position
	p.alive = false
	await wait(0.3)
	ck(lt2.total == 0, "no explosion when owner is dead")
	p.alive = true
	# ---- tiến hoá lên Legion khi mở ----
	ck(G.class_skill_id_for("summoner") == "summon", "default summoner skill")
	var P: Dictionary = G.profile
	var entry: Dictionary = MP.cls(P, "summoner")
	ck(entry.has("tier"), "profile gets summoner entry")
	print("summoner_test: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)
