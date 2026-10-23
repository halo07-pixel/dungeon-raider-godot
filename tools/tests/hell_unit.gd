extends SceneTree
var ok := 0; var bad := 0
func check(c: bool, m: String) -> void:
	if c: ok += 1
	else: bad += 1; print("FAIL: ", m)
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var G = root.get_node("Global")
	G.save_path = "user://test_save.dat" # test không đụng save thật
	var DG = load("res://scripts/dungeon.gd")
	var EN = load("res://scripts/enemy.gd")
	var AF = load("res://scripts/enemy_affix.gd")
	var HS = load("res://scripts/hell_skills.gd")
	var SQ = load("res://scripts/squad_director.gd")
	for k in ["hell_imp", "hell_ogre", "hell_acolyte", "cinder_tiny"]:
		check(G.enemies.has(k), k + " in enemies")
		var cfg: Dictionary = EN.ENEMY_SPRITES.get(k, {})
		check(not cfg.is_empty(), k + " has sprite cfg")
		var pre: String = cfg.get("prefix", "")
		for i in 4:
			if cfg.get("single_anim", false):
				check(FileAccess.file_exists("res://assets/dungeon/%s_anim_f%d.png" % [pre, i]), "%s frame %d" % [k, i])
			else:
				check(FileAccess.file_exists("res://assets/dungeon/%s_idle_anim_f%d.png" % [pre, i]), "%s idle %d" % [k, i])
				check(FileAccess.file_exists("res://assets/dungeon/%s_run_anim_f%d.png" % [pre, i]), "%s run %d" % [k, i])
	check(HS.KINDS.has("hell_ogre") and HS.KINDS.has("hell_acolyte") and HS.KINDS.has("cinder_tiny") and not HS.KINDS.has("hell_imp"), "skill kinds")
	check(G.enemies["archer"].get("shooter") == true and G.enemies["shaman"].get("kiter") == true, "archer/shaman flags kept")
	check(G.enemies["frost_tiny"].get("suicide") == true and G.enemies["cinder_tiny"].get("suicide") == true, "suicide flags")
	# roster per floor
	var w11: Dictionary = DG.hell_weights(11); var w12: Dictionary = DG.hell_weights(12); var w13: Dictionary = DG.hell_weights(13); var w14: Dictionary = DG.hell_weights(14)
	check(w11.has("hell_imp") and w11.has("cinder_tiny") and not w11.has("hell_ogre") and not w11.has("hell_acolyte"), "floor 11 roster")
	check(w12.has("hell_ogre") and not w12.has("hell_acolyte"), "floor 12 adds ogre")
	check(w13.has("hell_acolyte"), "floor 13 adds acolyte")
	check(w14["hell_ogre"] > w13["hell_ogre"] and w14["hell_acolyte"] > w13["hell_acolyte"], "floor 14 denser")
	for f in [11, 12, 13, 14, 15, 20]:
		for k in DG.hell_weights(f):
			check(G.enemies.has(k), "roster kind exists %s" % k)
	# trial helpers
	check(not DG.is_hell_trial_floor(10) and DG.is_hell_trial_floor(11) and DG.is_hell_trial_floor(15) and not DG.is_hell_trial_floor(16), "trial floors")
	check(DG.trial_wave_count(11) == 2 and DG.trial_wave_count(14) == 2 and DG.trial_wave_count(15) == 3, "wave counts")
	check(DG.trial_wave_size(11) == 7 and DG.trial_wave_size(15) == 10 and DG.trial_wave_size(30) == 10, "wave sizes")
	# affix
	check(AF.chance_for_floor(11) == AF.HELL_CHANCE and AF.chance_for_floor(1) == 0.0, "affix chance")
	for aid in AF.AFFIXES:
		for k in AF.AFFIXES[aid]["kinds"]:
			check(G.enemies.has(k), "affix %s kind %s exists" % [aid, k])
	check(AF.roll("hell_ogre", 12) is String, "roll ok")
	var got := {}
	for i in 600:
		got[AF.roll("cinder_tiny", 12)] = true
	check(not got.has("volatile") and not got.has("splitter"), "cinder never volatile/splitter")
	# endless / squad
	check(G.endless_difficulty_mult(15) == 1.0 and absf(G.endless_difficulty_mult(16) - 1.12) < 0.001, "endless from 15")
	check(SQ.TANKS.has("hell_ogre") and SQ.RANGED.has("hell_imp"), "squad lists")
	for n in ["imp_fire", "ogre_windup", "ogre_charge", "ward_cast", "cinder_burst", "trial_horn"]:
		check(G._sfx.has(n), "sfx defined: " + n)
	check(G.enemies["hell_imp"].get("shoot_sfx") == "imp_fire" and G._sfx.has(G.enemies["hell_imp"]["shoot_sfx"]), "imp shoot_sfx")
	print("hell_unit: %d ok, %d fail" % [ok, bad])
	quit(1 if bad > 0 else 0)
