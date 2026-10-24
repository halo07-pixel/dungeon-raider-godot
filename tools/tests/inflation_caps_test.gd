extends SceneTree
## Trần chống lạm phát: Power/Haste giảm dần từ lớp 3, hồi đòn vĩnh viễn >= CD_FLOOR, chí mạng từ buff/affix <= CRIT_CAP.
## Chạy: godot --headless --path . -s tools/tests/inflation_caps_test.gd
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var G = root.get_node("Global")
	G.run_buffs = {}
	ck(absf(G.power_bonus()) < 0.0001 and absf(G.haste_mult() - 1.0) < 0.0001, "không buff = không đổi")
	G.run_buffs = {"buff_dmg": 2, "buff_haste": 2}
	ck(absf(G.power_bonus() - 0.16) < 0.0001, "2 lớp Power = +16% (cũ)")
	ck(absf(G.haste_mult() - 0.81) < 0.0001, "2 lớp Haste = x0.81 (cũ)")
	G.run_buffs = {"buff_dmg": 5, "buff_haste": 5}
	ck(absf(G.power_bonus() - 0.304) < 0.0001, "5 lớp Power = +30.4 phần trăm (cũ +40)")
	ck(G.haste_mult() > 0.66 and G.haste_mult() < 0.68, "5 lớp Haste ~x0.67 (cũ 0.59)")
	var P = load("res://scripts/player.gd").new()
	P.aff = {"cd": 0.7, "crit": 0.4, "reach": 1.0, "dmg": 1.0}
	ck(P._perm_cd_mult() >= G.CD_FLOOR - 0.0001, "hồi đòn vĩnh viễn không dưới CD_FLOOR (%.3f)" % P._perm_cd_mult())
	G.run_buffs = {"buff_crit": 5}
	ck(P._crit_total() <= G.CRIT_CAP + 0.0001, "chí mạng buff+affix bị chặn (%.2f)" % P._crit_total())
	P.free()
	G.run_buffs = {}
	print("inflation_caps_test: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)
