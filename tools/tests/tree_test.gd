extends SceneTree
var ok := 0; var bad := 0
func check(c: bool, m: String) -> void:
	if c: ok += 1
	else: bad += 1; print("FAIL: ", m)
func wait(s: float) -> void:
	await create_timer(s).timeout
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var G = root.get_node("Global")
	G.save_path = "user://test_save.dat" # test không đụng save thật
	var T = load("res://scripts/skill_tree.gd")
	# data
	check(T.max_total_power() <= T.POWER_CAP + 0.0001, "power cap %.3f" % T.max_total_power())
	check(T.ids().size() == 8, "8 nodes")
	for id in T.NODES:
		var n = T.NODES[id]
		check(G.upgrades.has(id), "upgrades key " + id)
		check(int(n["cost"]) > 0 and (n["req"] == "" or T.NODES.has(n["req"])), "valid " + id)
		check(T.BRANCH_ORDER.has(n["branch"]), "branch " + id)
	# unlock/buy
	var up := {}
	var w := {"gems": 10}
	check(not T.can_unlock(up, "reroll"), "reroll locked without choice4")
	check(not T.buy(up, w, "reroll") and w["gems"] == 10, "buy locked fails, no charge")
	check(T.buy(up, w, "choice4") and w["gems"] == 6, "buy choice4")
	check(not T.buy(up, w, "choice4") and w["gems"] == 6, "no double buy")
	check(T.can_unlock(up, "reroll"), "reroll unlocked")
	var poor := {"gems": 4}
	check(not T.buy(up, poor, "reroll") and poor["gems"] == 4, "too poor")
	check(not T.buy(up, w, "nope"), "unknown id")
	# effects defaults
	var e := {}
	check(T.buff_choice_count(e) == 3 and T.rerolls_per_offer(e) == 0 and T.coin_bonus(e) == 0.0, "defaults")
	check(T.skill_cooldown_mult(e) == 1.0 and T.skill_damage_mult(e) == 1.0 and T.shield_regen_mult(e) == 1.0, "defaults mult")
	check(T.early_rare_steps(e, 1) == 0, "no early rare")
	var all := {}
	for id in T.NODES: all[id] = 1
	check(T.buff_choice_count(all) == 4 and T.rerolls_per_offer(all) == 1, "all: choices")
	check(T.early_rare_steps(all, 3) == 2 and T.early_rare_steps(all, 4) == 0, "early rare floors")
	check(absf(T.total_power(all) - T.max_total_power()) < 0.0001, "total power")
	# --- Global wiring ---
	for k in G.upgrades: G.upgrades[k] = 0
	G.reset_run()
	# rarity
	var rare0 := 0; var rare1 := 0
	for i in 3000: if G.roll_weapon_rarity(2) != "common": rare0 += 1
	G.upgrades["early_rare"] = 1
	for i in 3000: if G.roll_weapon_rarity(2) != "common": rare1 += 1
	check(rare1 > rare0, "early rare raises (%d->%d)" % [rare0, rare1])
	var deep0 := 0
	for i in 2000: if G.roll_weapon_rarity(8) != "common": deep0 += 1
	G.upgrades["early_rare"] = 0
	var deep1 := 0
	for i in 2000: if G.roll_weapon_rarity(8) != "common": deep1 += 1
	check(absf(float(deep0 - deep1)) < 250.0, "floor 8 unaffected (%d vs %d)" % [deep0, deep1])
	# coins
	G.coins = 0
	for i in 100: G.add_coin()
	check(G.coins == 100, "no bonus coins")
	G.upgrades["coin_bonus"] = 1
	G.coins = 0; G._coin_bonus_acc = 0.0
	for i in 100: G.add_coin()
	check(G.coins == 110, "coin bonus +10%% (%d)" % G.coins)
	G.upgrades["coin_bonus"] = 0
	# buff choices & reroll
	var got: Array = []
	G.buff_choice_requested.connect(func(c): got.append(c))
	G.request_buff_choice()
	check(got.size() == 1 and got[0].size() == 3, "3 choices default")
	check(not G.can_reroll() and not G.try_reroll(), "no reroll by default")
	G.buff_picks_left = 0
	G.upgrades["choice4"] = 1; G.upgrades["reroll"] = 1
	got.clear()
	G.request_buff_choice()
	check(got[0].size() == 4, "4 choices")
	check(G.can_reroll() and G.rerolls_left == 1, "reroll available")
	check(G.try_reroll() and got.size() == 2 and got[1].size() == 4, "reroll emits new offer")
	check(not G.can_reroll() and not G.try_reroll(), "only one reroll")
	G.buff_picks_left = 0
	G.rerolls_left = 1; G.buff_picks_left = 1; G.buff_choice_title = "ALTAR"
	check(not G.can_reroll(), "no reroll on special offers")
	G.buff_choice_title = G.BUFF_TITLE_DEFAULT; G.buff_picks_left = 0
	# --- in-game ---
	for k in G.upgrades: G.upgrades[k] = 0
	G.upgrades["start_buff"] = 1
	G.saved_run = {}
	change_scene_to_file("res://scenes/main.tscn")
	await wait(2.0)
	var main = current_scene
	var total := 0
	for id in G.run_buffs: total += int(G.run_buffs[id])
	check(total == 1, "start buff granted (%d)" % total)
	G.upgrades["start_buff"] = 0
	var skill = main.player.get("class_skill")
	if skill == null: skill = main.player.get_node_or_null("ClassSkill")
	check(skill != null, "class skill node")
	if skill != null:
		skill.skill_id = "slam"
		var cd0: float = skill._effective_cooldown()
		var d0: float = skill._mult("dmg_mult")
		G.upgrades["q_cooldown"] = 1; G.upgrades["q_damage"] = 1
		check(absf(skill._effective_cooldown() - maxf(1.0, cd0 * 0.9)) < 0.001, "cooldown -10%")
		check(absf(skill._mult("dmg_mult") - d0 * 1.1) < 0.001, "damage +10%")
	# shield
	var p = main.player
	G.upgrades["q_cooldown"] = 0; G.upgrades["q_damage"] = 0
	p.shield = 0.0; p.shield_delay_timer = 0.0
	p._tick_shield(1.0)
	var s0: float = p.shield
	G.upgrades["soft_shield"] = 1
	p.shield = 0.0
	p._tick_shield(1.0)
	check(p.shield > s0 and absf(p.shield / s0 - 1.1) < 0.01, "shield regen +10%% (%f vs %f)" % [p.shield, s0])
	G.upgrades["soft_shield"] = 0
	# save/load
	G.upgrades["q_damage"] = 1; G.upgrades["reroll"] = 1
	G.save_game()
	G.upgrades["q_damage"] = 0; G.upgrades["reroll"] = 0
	G.load_game()
	check(G.upgrades["q_damage"] == 1 and G.upgrades["reroll"] == 1, "save roundtrip")
	for k in G.upgrades: G.upgrades[k] = 0
	G.save_game()
	# menu
	change_scene_to_file("res://scenes/main_menu.tscn")
	await wait(1.5)
	var m = current_scene
	G.purple_gems = 5
	m._update_upgrade_ui()
	check(m.tree_ui_elements["choice4"]["btn"].text == "4 Gems" and not m.tree_ui_elements["choice4"]["btn"].disabled, "affordable btn")
	check(m.tree_ui_elements["reroll"]["btn"].text == "LOCKED", "locked btn")
	m._buy_tree_node("choice4")
	check(G.upgrades["choice4"] == 1 and G.purple_gems == 1 and m.tree_ui_elements["choice4"]["btn"].text == "OWNED", "bought in menu")
	check(m.tree_ui_elements["reroll"]["btn"].text == "5 Gems" and m.tree_ui_elements["reroll"]["btn"].disabled, "unlocked but unaffordable")
	for k in G.upgrades: G.upgrades[k] = 0
	G.purple_gems = 0
	G.save_game()
	print("tree_test: %d ok, %d fail" % [ok, bad])
	quit(1 if bad > 0 else 0)
