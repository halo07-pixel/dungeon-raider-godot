extends SceneTree
## Trần hút máu (Player.leech): không hồi quá LEECH_CAP_PCT_PER_SEC máu tối đa/giây, boss hồi ít hơn, heal() chủ động không bị trần,
## bình máu hồi theo % máu tối đa, độ hiếm/Vampiric đã hạ. Chạy: godot --headless --path . -s tools/tests/leech_test.gd
var fails: int = 0
func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func _init() -> void:
	await process_frame
	var G = root.get_node("Global")
	G.reset_run()
	G.current_class = "mage"
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var p = main.player
	var WI = load("res://scripts/weapon_instance.gd")
	# ---- hằng số đã hạ ----
	ck(float(G.rarities[G.STANDARD_RARITY]["lifesteal"]) == 0.0 and float(G.rarities[G.STANDARD_RARITY]["mult"]) == 1.0, "standard tier: no lifesteal, x1 damage")
	ck(float(WI.AFFIXES["vampiric"]["mods"]["steal"]) <= 0.025, "vampiric lowered")
	# ---- trần: bơm 1000 lần hút liên tục trong ~0 giây chỉ hồi tối đa ~ burst ----
	p.max_hp = 100
	p.hp = 1
	p._leech_t = -1.0
	for i in 1000:
		p.leech(5)
	var cap_burst: float = float(p.max_hp) * G.LEECH_CAP_PCT_PER_SEC * G.LEECH_BURST_SECS
	ck(p.hp - 1 <= int(cap_burst) + 1, "leech burst capped: healed %d <= %d" % [p.hp - 1, int(cap_burst)])
	ck(p.hp - 1 >= 1, "leech still heals something")
	# ---- hồi theo thời gian: sau 1 giây hồi thêm ~cap/giây (không quá) ----
	var before: int = p.hp
	await create_timer(1.0).timeout
	for i in 1000:
		p.leech(5)
	var gained: int = p.hp - before
	ck(gained <= int(float(p.max_hp) * G.LEECH_CAP_PCT_PER_SEC * 1.0) + 2, "refill ~cap per sec: gained %d" % gained)
	# ---- boss hồi ít hơn ----
	p.hp = 1
	p._leech_budget = 100.0
	p._leech_t = float(Time.get_ticks_msec()) / 1000.0
	p.leech(10, true)
	ck(p.hp - 1 == int(10.0 * G.LEECH_BOSS_MULT), "boss leech halved: %d" % (p.hp - 1))
	# ---- hồi chủ động không bị trần ----
	p.hp = 1
	p.heal(50)
	ck(p.hp == 51, "heal() not capped")
	# ---- bình máu theo % ----
	p.max_hp = 200
	p.hp = 1
	var Pickup = load("res://scripts/pickup.gd")
	ck(maxi(20, int(200.0 * Pickup.HEAL_PCT)) >= 40, "heal pickup scales with max hp")
	print("leech_test: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)
