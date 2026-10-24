extends SceneTree
## Đo "lạm phát sức mạnh": sức mạnh người chơi (sát thương, tốc độ đánh, bền) so với độ khó quái theo tầng, cho 3 mức build.
## Chạy: godot --headless --path . --script tools/balance/inflation_calc.gd [-- --out file.md]
## Mọi hằng số đọc từ code game (Global, WeaponInstance, Player, SkillTree) trừ các giả định build ghi rõ ở phần PROFILES.
## Chỉ số chính: R(F) = hệ số sát thương người chơi / (HP quái x giáp) so với tầng 1. R > 1 = quái đang "yếu đi" tương đối so với đầu game.
## KHÔNG sửa game. Đây là bước 1 (chỉ đo) của kế hoạch chống lạm phát.

const FLOORS: Array = [1, 3, 5, 8, 10, 12, 15]
const CLASSES: Array = ["ranger", "brawler", "mage", "rogue"]

var G
var P # script Player (hằng số)
var WI # script WeaponInstance
var _out: PackedStringArray = PackedStringArray()
var out_path: String = ""

func _init() -> void:
	call_deferred("_main")

func _p(s: String = "") -> void:
	print(s)
	_out.append(s)

func _c(script, name: String, fallback):
	var m: Dictionary = script.get_script_constant_map()
	return m.get(name, fallback)

# ---------------------------------------------------------------- giả định build theo tầng (người chơi đã lấy gì khi TỚI tầng F)
## picks: số lần chọn buff tới tầng F = 1/boss đã hạ (F-1) + ~0.5 mỗi tầng từ sự kiện (rương, thử thách, hầm bí mật).
func picks_for(F: int) -> int:
	return (F - 1) + int(round(0.5 * float(F - 1)))

func rarity_for(profile: String, F: int) -> String:
	match profile:
		"casual":
			return "common" if F < 4 else ("rare" if F < 8 else "epic")
		"focused":
			return "common" if F < 3 else ("rare" if F < 5 else ("epic" if F < 8 else "legendary"))
		_:
			return "mythic"

func build(profile: String, F: int, melee: bool) -> Dictionary:
	var b: Dictionary = {"dmg": 0, "haste": 0, "crit": 0, "momentum": 0, "berserk": 0, "focus": 0, "level": 0, "mastery": 0, "aff_dmg": 1.0, "aff_cd": 1.0, "aff_crit": 0.0,
		"hp_meta": 0, "shield_stacks": 0, "tree_power": 0.0}
	var rar: String = rarity_for(profile, F)
	b["rarity"] = rar
	var picks: int = picks_for(F)
	if profile == "casual":
		var off: int = int(ceil(float(picks) / 3.0)) # 1/3 lượt chọn rơi vào buff tấn công
		for i in off:
			var order: Array = ["dmg", "haste", "crit"]
			var k: String = order[i % 3]
			b[k] = mini(5, int(b[k]) + 1)
		b["level"] = mini(5, F / 4)
		b["mastery"] = 0
		b["hp_meta"] = 0
		b["shield_stacks"] = mini(2, picks / 6)
		b["tree_power"] = 0.0
	elif profile == "focused":
		var order2: Array = ["haste", "dmg", "crit", "haste", "dmg", "crit"] # tham lam theo mức lợi biên
		var left: int = picks
		for k in ["haste", "dmg", "crit"]:
			var take: int = mini(5, left)
			b[k] = take
			left -= take
			if left <= 0:
				break
		# còn dư lượt thì lấy buff sử thi tấn công (mỗi cái 1 stack)
		if left > 0:
			b["momentum"] = 1
			left -= 1
		if left > 0:
			b["berserk"] = 1
			left -= 1
		if left > 0 and not melee:
			b["focus"] = mini(3, left)
		b["level"] = mini(5, F / 2)
		b["mastery"] = 3
		b["hp_meta"] = 5
		b["shield_stacks"] = mini(5, picks / 4)
		b["tree_power"] = 0.15
		if rar != "common" and rar != "rare":
			b["aff_cd"] = 0.85
			b["aff_crit"] = 0.12
		elif rar == "rare":
			b["aff_cd"] = 0.85
	else: # cap lý thuyết
		b["dmg"] = 5; b["haste"] = 5; b["crit"] = 5; b["momentum"] = 1; b["berserk"] = 1
		b["focus"] = 0 if melee else 3
		b["level"] = 5
		b["mastery"] = 5
		b["hp_meta"] = 10
		b["shield_stacks"] = 5
		b["tree_power"] = 0.25
		b["aff_cd"] = 0.85
		b["aff_crit"] = 0.24 # 2 dòng phụ Keen? (cap: 1 Swift + 1 Keen) — lấy 0.12; hệ số nhân thêm bên dưới nếu 3 dòng (mythic)
		b["aff_crit"] = 0.12
		b["aff_dmg"] = 1.2 # mythic có 3 dòng phụ: thêm Heavy/Brutal (cd 1.15 bù lại bên dưới)
		b["aff_cd"] = 0.85 * 1.15
	return b

## Hệ số nhân sát thương trung bình (so với vũ khí common +0, không buff) của một build lên 1 mục tiêu.
func dmg_mult(b: Dictionary, melee: bool, class_crit: float) -> Dictionary:
	var rm: float = float(G.rarities[String(b["rarity"])]["mult"])
	var add: float = rm + 0.05 * float(b["mastery"]) + 0.08 * float(G._stack_weight(int(b["dmg"])))
	add += float(_c(P, "MOMENTUM_PER_STACK", 0.05)) * 5.0 * 0.6 * float(b["momentum"]) # trung bình 60% số stack tối đa
	add += 0.4 * 0.5 * float(b["berserk"])  # trung bình máu 50%
	add += 0.2 * 0.5 * float(b["focus"])    # đứng yên ~50% thời gian
	var level: float = 1.0 + float(_c(WI, "LEVEL_DMG", 0.08)) * float(b["level"])
	var hm: float = 1.0
	for i in int(b["haste"]): # Haste giảm dần như Global.haste_mult()
		hm *= 1.0 - 0.1 * (1.0 if i < int(G.STACK_DIMINISH_FROM) else float(G.STACK_DIMINISH))
	var cd: float = maxf(float(G.CD_FLOOR), hm * float(b["aff_cd"]))
	var crit_c: float = clampf(minf(float(G.CRIT_CAP), 0.08 * float(b["crit"]) + float(b["aff_crit"])) + class_crit, 0.0, 1.0)
	var crit_f: float = 1.0 + crit_c # đòn chí mạng x2
	var dmg: float = add * level * float(b["aff_dmg"]) * (1.0 + float(b["tree_power"]) * 0.0) # cây kỹ năng chỉ tác động kỹ năng, không tính vào sát thương vũ khí
	var speed: float = 1.0 / cd
	return {"mult": dmg * speed * crit_f, "dmg": dmg, "speed": speed, "crit": crit_f}

func enemy_ehp(F: int) -> float:
	var armor: float = floor((float(F) - 1.0) * 1.6) + 2.0
	var armor1: float = 2.0
	return G.hp_scale_for_floor(F) * G.endless_difficulty_mult(F) * (1.0 - G.armor_reduction(armor1)) / (1.0 - G.armor_reduction(armor))

func enemy_dmg(F: int) -> float:
	return minf(float(G.ENEMY_DMG_MULT_CAP), 1.0 + float(G.ENEMY_DMG_PER_FLOOR) * float(maxi(0, F - 1)))

func player_ehp(b: Dictionary, cid: String) -> float:
	var hp: float = float(G.classes[cid]["max_hp"]) + 10.0 * float(b["hp_meta"])
	var sh: float = float(_c(P, "SHIELD_BASE", 20)) + float(_c(P, "SHIELD_CAP_PER_STACK", 10)) * float(b["shield_stacks"])
	var steal: float = float(G.rarities[String(b["rarity"])]["lifesteal"])
	var heal_bonus: float = 1.0 + steal * 4.0 # hút máu coi như hồi thêm: ước lượng thô, 1% hút máu ~ +4% máu hiệu dụng qua một tầng
	var brawler: float = 1.0 / 0.92 if cid == "brawler" else 1.0
	return (hp + sh) * heal_bonus * brawler

func _main() -> void:
	G = root.get_node("Global")
	P = load("res://scripts/player.gd")
	WI = load("res://scripts/weapon_instance.gd")
	var a: PackedStringArray = OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size():
			out_path = a[i + 1]
	_p("# Lạm phát sức mạnh — đo từ dữ liệu game")
	_p("")
	_p("Giả định build (xem PROFILES trong script): **casual** = 1/3 lượt chọn buff vào tấn công, vũ khí hiếm theo tầng, ít nâng cấp; **focused** = dồn mọi lượt vào buff tấn công + forge; **cap** = mọi trần cùng lúc (trần lý thuyết, không ai đạt được ở đầu game).")
	_p("Lượt chọn buff tới tầng F = (F-1) + 0.5·(F-1) từ sự kiện. R(F) = hệ số sức mạnh người chơi / (HP quái × giáp) so với tầng 1; R > 1: quái yếu đi tương đối.")
	_p("")
	for melee in [false, true]:
		_p("## 1%s. Sức mạnh sát thương — %s" % ["b" if melee else "a", "vũ khí cận chiến" if melee else "vũ khí tầm xa"])
		_p("")
		_p("| Tầng | HP×giáp quái | casual: mult → R | focused: mult → R | cap: mult → R |")
		_p("|---|---|---|---|---|")
		for F in FLOORS:
			var e: float = enemy_ehp(F)
			var cells: PackedStringArray = PackedStringArray()
			for prof in ["casual", "focused", "cap"]:
				var b: Dictionary = build(prof, F, melee)
				var m: Dictionary = dmg_mult(b, melee, 0.0)
				cells.append("x%.2f → R %.2f" % [m["mult"], float(m["mult"]) / e])
			_p("| %d | x%.2f | %s |" % [F, e, " | ".join(cells)])
		_p("")
	_p("## 2. Cấu thành sức mạnh (tầng 10, tầm xa): đâu là nguồn lớn nhất")
	_p("")
	_p("| Build | độ hiếm | cộng dồn sát thương (hiếm+buff+mastery) | cấp +N | tốc độ đánh | chí mạng | tổng |")
	_p("|---|---|---|---|---|---|---|")
	for prof in ["casual", "focused", "cap"]:
		var bb: Dictionary = build(prof, 10, false)
		var mm: Dictionary = dmg_mult(bb, false, 0.0)
		var lvl: float = 1.0 + float(_c(WI, "LEVEL_DMG", 0.08)) * float(bb["level"])
		_p("| %s | %s | x%.2f | x%.2f | x%.2f | x%.2f | **x%.2f** |" % [prof, bb["rarity"], float(mm["dmg"]) / lvl / float(bb["aff_dmg"]), lvl, mm["speed"], mm["crit"], mm["mult"]])
	_p("")
	_p("## 3. Độ bền: máu+giáp hiệu dụng so với sát thương quái (tầng 1 = 1.00, ranger)")
	_p("")
	_p("| Tầng | sát thương quái | casual | focused | cap |")
	_p("|---|---|---|---|---|")
	var base_ehp: float = player_ehp(build("casual", 1, false), "ranger")
	for F in FLOORS:
		var d: float = enemy_dmg(F)
		var cells2: PackedStringArray = PackedStringArray()
		for prof in ["casual", "focused", "cap"]:
			var ehp: float = player_ehp(build(prof, F, false), "ranger")
			cells2.append("%.2f" % (ehp / base_ehp / d))
		_p("| %d | x%.2f | %s |" % [F, d, " | ".join(cells2)])
	_p("")
	_p("## 4. Thời gian hạ boss (giây) với build focused — vũ khí khởi đầu của class, tầng boss cuối nhóm")
	_p("")
	_p("| Tầng (boss) | HP boss | " + " | ".join(PackedStringArray(CLASSES)) + " |")
	_p("|---|---|" + "---|".repeat(CLASSES.size()))
	var boss_script = load("res://scripts/boss.gd")
	var bd: Dictionary = boss_script.BOSS_DATA
	for F in [3, 6, 9, 10, 15]:
		var kind: String = "warden" if F <= 3 else ("necromancer" if F <= 6 else ("frost" if F <= 9 else "lord"))
		var hp: float = float(bd[kind]["base_hp"]) * G.hp_scale_for_floor(F) * G.endless_difficulty_mult(F)
		var armor: float = floor((float(F) - 1.0) * 1.6) + 2.0
		var red: float = G.armor_reduction(armor)
		var cells3: PackedStringArray = PackedStringArray()
		for cid in CLASSES:
			var w: Dictionary = G.weapons[String(G.classes[cid]["default_weapon"])]
			var melee_w: bool = bool(w.get("is_melee", false))
			var b2: Dictionary = build("focused", F, melee_w)
			var cc: float = 0.15 if cid == "rogue" else 0.0
			var m2: Dictionary = dmg_mult(b2, melee_w, cc)
			var pass_m: float = 1.12 if ((cid == "ranger" and not melee_w) or (cid == "brawler" and melee_w)) else 1.0
			var base_hits: float = float(w.get("pellets", 1)) / maxf(0.01, float(w["cooldown"]))
			if bool(w.get("boomerang", false)): base_hits = 2.0 / maxf(float(w["cooldown"]), float(w.get("life", 2.0)))
			if int(w.get("pellets", 1)) > 1: base_hits = float(w["pellets"]) * 0.5 / maxf(0.01, float(w["cooldown"]))
			var dps: float = float(w["damage"]) * pass_m * base_hits * float(m2["mult"]) * (1.0 - red) * 0.75
			cells3.append("%.0fs" % (hp / maxf(0.1, dps)))
		_p("| %d (%s) | %.0f | %s |" % [F, bd[kind]["name"], hp, " | ".join(cells3)])
	_p("")
	_p("## 5. Cách đọc")
	_p("- R tăng theo tầng = người chơi mạnh lên nhanh hơn quái; R trên ~2 ở tầng 10 cho build focused nghĩa là boss chỉ bằng nửa độ trâu thiết kế.")
	_p("- Bảng 2 cho thấy nhân tố nào đóng góp nhiều nhất (độ hiếm/buff cộng dồn, tốc độ đánh nhân, chí mạng nhân).")
	_p("- Bảng 4 giả định trúng 75%, bỏ qua kỹ năng class, đạn xuyên/AOE, trạng thái; dùng để so các mức build và class, không phải thời gian thực.")
	_p("- Giả định build (số lượt chọn, vũ khí theo tầng) là ước lượng của tôi; cần đối chiếu với dữ liệu ván thật (telemetry) để chỉnh.")
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(_out) + "\n")
			f.close()
	quit()
