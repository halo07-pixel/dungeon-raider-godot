extends SceneTree
## Máy tính cân bằng TĨNH (không chạy game, không bot): DPS lý thuyết của từng class/vũ khí và thời gian hạ boss theo tầng.
## Chạy: godot --headless --path . --script tools/balance/class_calc.gd [-- --out file.md --acc 0.75 --rarity common]
## Đọc thẳng dữ liệu của game (Global.weapons/classes/rarities, BOSS_DATA, hp_scale_for_floor, giáp boss) nên không lệch khi số liệu đổi.
## Mô hình đơn giản: một mục tiêu, đứng yên tầm chuẩn; hệ số "acc" mô tả tỉ lệ đòn trúng thực tế (người chơi < 1).
## Bỏ qua: buff, vũ khí rank/mastery, trạng thái (cháy/độc/chảy máu), né đòn, thời gian di chuyển, boss miễn nhiễm/phase.

var BossScript
const RANGER_RANGED: float = 0.12
const BRAWLER_MELEE: float = 0.12
const ROGUE_CRIT: float = 0.15
const MAGE_HASTE: float = 0.25
const CRIT_MULT: float = 2.0
const PELLET_HIT: float = 0.5 # shotgun: tỉ lệ đạn ghém trúng ở tầm trung
const BOSS_FLOORS: Array = [1, 3, 4, 6, 7, 9, 10]

var G
var opts: Dictionary = {"out": "", "acc": 0.75, "rarity": "common"}
var _out: PackedStringArray = PackedStringArray()

func _init() -> void:
	call_deferred("_main")

func _parse() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		var k: String = String(a[i]).trim_prefix("--")
		if i + 1 < a.size() and opts.has(k):
			var v: String = a[i + 1]
			opts[k] = float(v) if opts[k] is float else v
			i += 2
		else:
			i += 1

func _p(s: String = "") -> void:
	print(s)
	_out.append(s)

# ---------------------------------------------------------------- mô hình sát thương
func _is_melee(w: Dictionary) -> bool:
	return bool(w.get("is_melee", false))

func _class_mult(cid: String, w: Dictionary) -> float:
	if cid == "ranger" and not _is_melee(w):
		return 1.0 + RANGER_RANGED
	if cid == "brawler" and _is_melee(w):
		return 1.0 + BRAWLER_MELEE
	return 1.0

func _crit_chance(cid: String) -> float:
	return ROGUE_CRIT if cid == "rogue" else 0.0

## Số đòn (hit) trên giây trên một mục tiêu, đã gồm cơ chế riêng của vũ khí.
func _hits_per_sec(w: Dictionary) -> float:
	var cd: float = float(w["cooldown"])
	if w.has("charge_time"):
		return float(w.get("charge_max", 1.0)) / maxf(0.01, cd + float(w["charge_time"])) # tính theo hệ số sát thương trung bình của đòn căng
	if bool(w.get("boomerang", false)):
		return 2.0 / maxf(cd, float(w.get("life", 2.0))) # trúng lượt đi và lượt về, chưa về chưa ném
	var pellets: float = float(w.get("pellets", 1))
	if pellets > 1.0:
		pellets *= PELLET_HIT
	return pellets / maxf(0.01, cd)

## sát thương một hit sau giáp và độ hiếm. Bow: hệ số charge đã nằm trong _hits_per_sec nên ở đây dùng sát thương gốc.
func _hit(cid: String, w: Dictionary, rarity_mult: float, armor: float) -> float:
	var raw: float = float(w["damage"]) * rarity_mult * _class_mult(cid, w)
	return float(G.armored_damage(roundi(raw), armor))

func weapon_dps(cid: String, wid: String, rarity: String, armor: float, acc: float) -> float:
	var w: Dictionary = G.weapons[wid]
	var rm: float = float(G.rarities[rarity]["mult"])
	var crit: float = 1.0 + _crit_chance(cid) * (CRIT_MULT - 1.0)
	return _hit(cid, w, rm, armor) * _hits_per_sec(w) * crit * acc

## Bonus DPS từ kỹ năng khởi đầu của class lên boss (trung bình theo chu kỳ hồi chiêu), và hệ số nhân vũ khí (Overdrive).
func skill_bonus(cid: String, wid: String, rarity: String, floor_n: int, armor: float, acc: float) -> Dictionary:
	var w: Dictionary = G.weapons[wid]
	var base: float = weapon_dps(cid, wid, rarity, armor, acc)
	match cid:
		"ranger": # Overdrive: 4s đánh nhanh gấp đôi mỗi 12s hồi chiêu
			var dur: float = 4.0
			var cdn: float = 12.0
			return {"extra": base * (dur * (1.0 / 0.5 - 1.0)) / cdn, "desc": "Overdrive +%d%% DPS" % int(round(dur * 1.0 / cdn * 100.0))}
		"brawler": # Slam: (16+1.5F) mỗi 6s
			var d: float = float(G.armored_damage(roundi(16.0 + 1.5 * float(floor_n)), armor))
			return {"extra": d / 6.0 * acc, "desc": "Slam %d/6s" % int(d)}
		"mage": # Gravity Well: 6 nhịp 0.5s x (6+0.6F), hồi 8s / 1.25
			var td: float = float(G.armored_damage(roundi(6.0 + 0.6 * float(floor_n)), armor))
			return {"extra": td * 6.0 / (8.0 / (1.0 + MAGE_HASTE)), "desc": "Well %dx6/%.1fs" % [int(td), 8.0 / (1.0 + MAGE_HASTE)]}
		"rogue": # Shadow Dash: (14+1.2F) + 1 đòn chắc chắn chí mạng (cộng thêm 1 hit) mỗi 6s
			var dd: float = float(G.armored_damage(roundi(14.0 + 1.2 * float(floor_n)), armor))
			var hitv: float = _hit(cid, w, float(G.rarities[rarity]["mult"]), armor)
			return {"extra": (dd + hitv * (CRIT_MULT - 1.0)) / 6.0 * acc, "desc": "Dash %d+crit/6s" % int(dd)}
	return {"extra": 0.0, "desc": ""}

func boss_for(floor_n: int) -> Dictionary:
	var kind: String = "warden" if floor_n <= 3 else ("necromancer" if floor_n <= 6 else ("frost" if floor_n <= 9 else "lord"))
	var cfg: Dictionary = BossScript.BOSS_DATA[kind]
	var hp: float = float(cfg["base_hp"]) * G.hp_scale_for_floor(floor_n) * G.endless_difficulty_mult(floor_n)
	var armor: float = floor((float(floor_n) - 1.0) * 1.6) + 2.0
	return {"kind": kind, "name": String(cfg["name"]), "hp": hp, "armor": armor, "red": G.armor_reduction(armor)}

func _main() -> void:
	G = root.get_node("Global")
	BossScript = load("res://scripts/boss.gd") # load lúc chạy (sau autoload) để tránh lỗi biên dịch "Global"
	_parse()
	var acc: float = float(opts["acc"])
	var rarity: String = String(opts["rarity"])
	var cls: Array = ["ranger", "brawler", "mage", "rogue"]
	_p("# Cân bằng class — tính tĩnh từ dữ liệu game")
	_p("")
	_p("Mô hình: 1 mục tiêu, tỉ lệ trúng %.0f%%, vũ khí khởi đầu độ hiếm **%s**, kỹ năng khởi đầu, KHÔNG buff/rank/trạng thái. Chỉ nên đọc TƯƠNG ĐỐI giữa các class." % [acc * 100.0, rarity])
	_p("")
	_p("## 1. Thời gian hạ boss (giây) với vũ khí khởi đầu của class")
	_p("")
	_p("| Tầng | Boss | HP | Giáp (giảm) | " + " | ".join(PackedStringArray(cls.map(func(c): return "%s (%s)" % [c, G.classes[c]["default_weapon"]]))) + " |")
	_p("|---|---|---|---|" + "---|".repeat(cls.size()))
	var table: Dictionary = {}
	for f in BOSS_FLOORS:
		var b: Dictionary = boss_for(f)
		var cells: PackedStringArray = PackedStringArray()
		for c in cls:
			var wid: String = String(G.classes[c]["default_weapon"])
			var dps: float = weapon_dps(c, wid, rarity, float(b["armor"]), acc)
			var sk: Dictionary = skill_bonus(c, wid, rarity, f, float(b["armor"]), acc)
			var total: float = dps + float(sk["extra"])
			table[str(f) + c] = total
			cells.append("%.0fs (%.1f dps)" % [float(b["hp"]) / maxf(0.1, total), total])
		_p("| %d | %s | %.0f | %.0f (-%.0f%%) | %s |" % [f, b["name"], b["hp"], b["armor"], float(b["red"]) * 100.0, " | ".join(cells)])
	_p("")
	_p("## 2. Chỉ số so sánh class (DPS lên boss, trung bình 4 class = 100)")
	_p("")
	_p("| Tầng | " + " | ".join(PackedStringArray(cls)) + " |")
	_p("|---|" + "---|".repeat(cls.size()))
	for f in BOSS_FLOORS:
		var vals: Array = cls.map(func(c): return float(table[str(f) + c]))
		var mean: float = vals.reduce(func(a, b): return a + b) / vals.size()
		_p("| %d | %s |" % [f, " | ".join(PackedStringArray(vals.map(func(v): return "%d" % int(round(v / mean * 100.0)))))])
	_p("")
	_p("## 3. Kỹ năng khởi đầu (đóng góp DPS trung bình lên boss tầng 6)")
	_p("")
	var b6: Dictionary = boss_for(6)
	for c in cls:
		var wid6: String = String(G.classes[c]["default_weapon"])
		var s6: Dictionary = skill_bonus(c, wid6, rarity, 6, float(b6["armor"]), acc)
		var w6: float = weapon_dps(c, wid6, rarity, float(b6["armor"]), acc)
		_p("- **%s**: vũ khí %.1f dps + kỹ năng %.1f dps (%s) → kỹ năng chiếm %.0f%%" % [c, w6, float(s6["extra"]), s6["desc"], float(s6["extra"]) / maxf(0.1, w6 + float(s6["extra"])) * 100.0])
	_p("")
	_p("## 4. Xếp hạng vũ khí theo class (DPS lên boss tầng 6, chưa tính kỹ năng; tỉ lệ so với vũ khí khởi đầu của class)")
	_p("")
	for c in cls:
		var rows: Array = []
		for wid in G.weapons:
			rows.append([String(G.weapons[wid]["name"]), weapon_dps(c, String(wid), rarity, float(b6["armor"]), acc)])
		rows.sort_custom(func(x, y): return x[1] > y[1])
		var base_dps: float = weapon_dps(c, String(G.classes[c]["default_weapon"]), rarity, float(b6["armor"]), acc)
		var parts: PackedStringArray = PackedStringArray()
		for r in rows:
			parts.append("%s %.1f (x%.2f)" % [r[0], r[1], float(r[1]) / maxf(0.1, base_dps)])
		_p("**%s** (khởi đầu %.1f dps): %s" % [c, base_dps, ", ".join(parts)])
		_p("")
	_p("## 5. Ghi chú đọc số liệu")
	_p("- Giáp boss giảm theo phần trăm (K=%.0f); đạn nhỏ (SMG, Flamethrower) bị phạt như mọi vũ khí nhưng làm tròn tối thiểu 1 sát thương/đòn." % G.ARMOR_K)
	_p("- Class chênh nhau quá ~25% so với trung bình ở nhiều tầng liên tiếp đáng cân nhắc chỉnh; dưới ~15% coi như cân bằng.")
	_p("- Chưa tính: sát thương diện rộng (Arcane Staff nổ, Flamethrower/Scythe xuyên nhiều quái — lợi thế của mage trong bầy quái bị đánh giá thấp ở bảng boss), buff (Power/Crit/Berserk/...), rank vũ khí, trạng thái (cháy/độc/chảy máu), mastery, né/di chuyển, mô hình lượng sát thương nhận.")
	if String(opts["out"]) != "":
		var f := FileAccess.open(String(opts["out"]), FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(_out) + "\n")
			f.close()
	quit()
