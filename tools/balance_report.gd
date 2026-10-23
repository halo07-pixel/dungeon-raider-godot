extends SceneTree
## Báo cáo cân bằng (mô hình thô, KHÔNG phải mô phỏng chiến đấu): DPS ước lượng của vài build điển hình theo tầng,
## so với HP quái/boss, thời gian dọn phòng, thời gian hạ Dungeon Lord và hồi máu hút được so với sát thương nhận vào.
## Mọi hằng số đọc trực tiếp từ Global/Player/Boss nên chạy lại sau khi chỉnh là thấy hiệu ứng ngay.
## Chạy: godot --headless --path . -s tools/balance_report.gd
##
## Giả định (chỉnh ở đây nếu muốn đổi mô hình):
const UPTIME: float = 0.65            # tỉ lệ thời gian thực sự đánh trúng (né, di chuyển, quái chạy)
const CRIT_MULT: float = 2.0
const CONTACT_UPTIME: float = 0.35    # tỉ lệ thời gian quái thật sự chạm/đánh trúng Player nếu không né
const TARGET_TTK: Dictionary = {"casual": [100.0, 9999.0], "strong": [45.0, 110.0], "maxed": [28.0, 60.0]} # Lord tầng 10, giây (uptime đã tính)

## Cấu hình build theo tầng: rarity, level, số buff "đã chọn" (mỗi tầng 1 lượt sau boss), nhóm buff hữu ích trung bình.
func build_for(kind: String, f: int) -> Dictionary:
	var picks: int = maxi(0, f - 1)
	var rarity: String = "common"
	var level: int = 0
	match kind:
		"casual":
			rarity = "common" if f < 5 else "rare"
			level = clampi((f - 1) / 3, 0, 3)
		"strong":
			rarity = "rare" if f < 3 else ("epic" if f < 6 else "legendary")
			level = clampi((f - 1) / 2, 0, 5)
		"maxed":
			rarity = "epic" if f < 3 else ("legendary" if f < 6 else ("mythic" if f >= 8 else "legendary"))
			level = clampi(f - 1, 0, 5)
	return {"rarity": rarity, "level": level, "picks": picks, "affixes": int(WeaponInstance.AFFIX_COUNT.get(rarity, 0))}

var G
var WeaponInstance

func median_base_dps(melee: bool) -> float:
	var vals: Array = []
	for id in G.weapons:
		var w: Dictionary = G.weapons[id]
		if bool(w.get("is_melee", false)) != melee:
			continue
		vals.append(float(w["damage"]) * float(w.get("pellets", 1)) / float(w["cooldown"]))
	vals.sort()
	return float(vals[vals.size() / 2]) if not vals.is_empty() else 0.0

func dps_of(b: Dictionary, melee: bool, f: int) -> float:
	var r: Dictionary = G.rarities[b["rarity"]]
	var base: float = median_base_dps(melee)
	var picks: int = int(b["picks"])
	var dmg_stacks: float = minf(5.0, float(picks) * 0.25)
	var haste_stacks: float = minf(5.0, float(picks) * 0.18)
	var crit_stacks: float = minf(5.0, float(picks) * 0.18)
	var affix_dmg: float = 1.0 + 0.06 * float(b["affixes"]) # heavy/brutal/swift trung bình
	var crit_p: float = minf(0.6, 0.05 + 0.08 * crit_stacks)
	var mult: float = float(r["mult"]) * (1.0 + float(WeaponInstance.LEVEL_DMG) * float(b["level"])) * affix_dmg * (1.0 + 0.08 * dmg_stacks) * (1.0 + (CRIT_MULT - 1.0) * crit_p)
	mult /= pow(0.9, haste_stacks)
	return base * mult

func armor_of_enemy(f: int) -> float:
	return floor((f - 1) * 1.2)

func armor_of_boss(f: int) -> float:
	return floor((f - 1) * 1.6) + 2.0

func avg_enemy_hp(f: int) -> float:
	var hp: float = 0.0
	var wsum: float = 0.0
	for k in ["slime", "archer", "brute"]:
		hp += float(G.enemies[k]["hp"]) * float(G.enemies[k]["weight"])
		wsum += float(G.enemies[k]["weight"])
	return hp / wsum * G.hp_scale_for_floor(f) * G.endless_difficulty_mult(f)

func wave_size(f: int) -> float:
	return minf(float(3 + f + 1), 10.0) # trung bình randi_range(0, 2) = 1

func lord_hp(f: int) -> float:
	var boss = load("res://scripts/boss.gd")
	return float(boss.BOSS_DATA["lord"]["base_hp"]) * G.hp_scale_for_floor(f) * G.endless_difficulty_mult(f)

func leech_hps(dps_eff: float, b: Dictionary, melee: bool, max_hp: float, vs_boss: bool) -> float:
	var rate: float = float(G.rarities[b["rarity"]]["lifesteal"])
	if "vampiric" in WeaponInstance.AFFIXES and int(b["affixes"]) >= 2:
		rate += float(WeaponInstance.AFFIXES["vampiric"]["mods"]["steal"]) * 0.5 # xác suất có Vampiric
	if melee:
		rate *= G.MELEE_LIFESTEAL_MULT
	var raw: float = dps_eff * rate * (0.5 if vs_boss else 1.0)
	var cap: float = max_hp * float(G.get("LEECH_CAP_PCT_PER_SEC") if G.get("LEECH_CAP_PCT_PER_SEC") != null else 999.0)
	return minf(raw, cap)

func incoming_dps(f: int, n: float) -> float:
	var touch: float = 0.0
	for k in ["slime", "brute"]:
		touch += float(G.enemies[k]["touch"]) / float(G.enemies[k]["touch_cd"]) * 0.5
	return touch * n * 0.5 * G.enemy_dmg_mult_for_floor(f) * CONTACT_UPTIME # ~nửa số quái ở gần cùng lúc

func _init() -> void:
	await process_frame
	G = root.get_node("Global")
	WeaponInstance = load("res://scripts/weapon_instance.gd")
	print("")
	print("BALANCE REPORT (mô hình thô)  — Lord tầng 10 mục tiêu (giây, đã tính uptime): casual >%d, strong %d-%d, maxed %d-%d" % [TARGET_TTK["casual"][0], TARGET_TTK["strong"][0], TARGET_TTK["strong"][1], TARGET_TTK["maxed"][0], TARGET_TTK["maxed"][1]])
	print("")
	for melee in [true, false]:
		print("== %s (DPS gốc trung vị %.1f) ==" % ["CẬN CHIẾN" if melee else "TẦM XA", median_base_dps(melee)])
		print("%-7s %-6s %-9s %5s %7s %8s %9s %8s %8s %8s" % ["build", "tầng", "rarity+lv", "DPS", "quái HP", "dọn phòng", "Lord TTK", "hút/s", "nhận/s", "hút/nhận"])
		for kind in ["casual", "strong", "maxed"]:
			for f in [1, 3, 5, 7, 10, 13, 15]:
				var b: Dictionary = build_for(kind, f)
				var dps: float = dps_of(b, melee, f)
				var eff_e: float = dps * (1.0 - G.armor_reduction(armor_of_enemy(f))) * UPTIME
				var eff_b: float = dps * (1.0 - G.armor_reduction(armor_of_boss(f))) * UPTIME
				var room_hp: float = avg_enemy_hp(f) * wave_size(f)
				var clear: float = room_hp / maxf(eff_e, 0.01)
				var ttk: float = lord_hp(f) / maxf(eff_b, 0.01)
				var hp_pool: float = 100.0 + 0.0
				var leech: float = leech_hps(eff_e / UPTIME, b, melee, hp_pool, false)
				var inc: float = incoming_dps(f, wave_size(f))
				print("%-7s F%-5d %-9s %5.0f %7.0f %7.1fs %8.0fs %8.1f %8.1f %8.2f" % [kind, f, "%s+%d" % [String(b["rarity"]).substr(0, 4), int(b["level"])], dps, room_hp, clear, ttk, leech, inc, leech / maxf(inc, 0.01)])
		print("")
	print("Đọc bảng: 'hút/nhận' >= 1.0 nghĩa là hồi máu từ hút máu bù hết sát thương nhận vào (gần như bất tử).")
	quit()
