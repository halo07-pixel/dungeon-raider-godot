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
# --- giả định cho Ultimate / Summoner / kỹ năng tiến hoá (đọc từ scripts/ultimate.gd, minion.gd, class_skill.gd; đổi ở đây nếu game đổi)
const SUMMON_POWER: float = 1.2 # nội tại Pack Leader +20% sát thương lính
const MINION_UPTIME: float = 0.85 # tỉ lệ thời gian đủ 2 lính (hồi 6s/1.25, sống 12s)
const SUMMONER_CD: float = 1.25 # Summoner hồi kỹ năng nhanh hơn 25%
const ULT_HORDE_POWER: float = 1.2
const ULT_HORDE_LIFE: float = 12.0 * 0.85
const ULT_TAKEN_PCT_PER_SEC: float = 1.0 # GIẢ ĐỊNH: % máu tối đa mất mỗi giây khi đánh boss (nạp 0.6 điểm mỗi 1%)
const ULT_KILL_PTS_PER_SEC: float = 0.4 # GIẢ ĐỊNH: ~0.2 quái/s x 2 điểm (lính nhỏ trong trận boss)
const ULT_HIT_CHARGE: float = 0.7
const ULT_HIT_BUDGET: float = 6.0
# GIẢ ĐỊNH bầy quái: bầy 3 mục tiêu đứng gần nhau, giáp 0. Hệ số nhân [vũ khí, kỹ năng, ult] = số mục tiêu trung bình bị trúng.
const SWARM: Dictionary = {"ranger": [1.0, 1.0, 3.0], "brawler": [1.5, 3.0, 3.0], "mage": [2.0, 3.0, 3.0], "rogue": [1.3, 1.5, 3.0], "summoner": [1.0, 2.0, 3.0]}
const BOSS_HIT: Dictionary = {"ranger": 0.13, "brawler": 1.0, "mage": 0.15, "rogue": 0.7} # GIẢ ĐỊNH: tỉ lệ xung/đạn ult trúng boss

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
		"summoner": # Summon: 2 lính (spirit + wisp) đánh thay
			var m: float = _minion_dps(floor_n, armor, SUMMON_POWER) * MINION_UPTIME * acc
			return {"extra": m, "desc": "2 lính %.1f dps" % m}
	return {"extra": 0.0, "desc": ""}

func _d(x: float, armor: float) -> float:
	return float(G.armored_damage(roundi(x), armor))

## DPS của 1 spirit (cận chiến) + 1 wisp (bắn). Sát thương gốc 8+0.9F, nhân dmg_k và power.
func _minion_dps(floor_n: int, armor: float, power: float) -> float:
	var base: float = (8.0 + 0.45 * float(floor_n)) * power
	return _d(base * 1.0, armor) / 0.55 + _d(base * 0.8, armor) / 0.85

## Bonus DPS của kỹ năng tiến hoá. ab = "A" hoặc "B". Thay kỹ năng khởi đầu (trừ Summoner: cộng thêm lên lính).
func evolved_bonus(cid: String, ab: String, wid: String, rarity: String, f: int, armor: float, acc: float) -> float:
	var F: float = float(f)
	match cid + ab:
		"rangerA": return 15.0 * _d(8.0 + 0.8 * F, armor) / 7.0 * acc # Barrage 3x5 đạn
		"rangerB": return _d(42.0 + 4.2 * F, armor) / 8.0 * acc # Railshot
		"brawlerA": return _d(30.0 + 3.0 * F, armor) / 9.0 * acc # Shockwave
		"brawlerB": return _d(28.0 + 2.8 * F, armor) / 7.0 * acc # Charge
		"mageA": return 3.0 * _d(26.0 + 2.5 * F, armor) / (10.0 / (1.0 + MAGE_HASTE)) * acc # Meteor Storm
		"mageB": return _d(34.0 + 3.4 * F, armor) / (9.0 / (1.0 + MAGE_HASTE)) * acc # Blink Nova
		"rogueA": # Shadow Rush: 3 đòn chắc chắn chí mạng x1.5 mỗi 8s (cộng thêm so với đòn thường)
			var h: float = _hit(cid, G.weapons[wid], float(G.rarities[rarity]["mult"]), armor)
			return 3.0 * h * (1.5 * CRIT_MULT - 1.0) / 8.0 * acc
		"rogueB": return 8.0 * _d(5.0 + 0.5 * F, armor) / 10.0 * acc # Smoke Veil: 4s, GIẢ ĐỊNH 1 nhịp/0.5s
		"summonerA": return 3.0 * _d((8.0 + 0.45 * F) * 0.7 * SUMMON_POWER, armor) / (12.0 / SUMMONER_CD) * acc # Legion: 3 Spiteling nổ mỗi 12s
		"summonerB": return _d(24.0 + 2.4 * F, armor) / (14.0 / SUMMONER_CD) * acc # Soul Detonation
	return 0.0

## Sát thương mỗi lần xả Ultimate lên boss (đã qua giáp, tỉ lệ trúng BOSS_HIT/acc).
func ult_per_cast(cid: String, f: int, armor: float, acc: float) -> float:
	var F: float = float(f)
	match cid:
		"ranger": return 16.0 * 12.0 * BOSS_HIT[cid] * _d(floorf(6.0 + 0.8 * F), armor) # Bullet Storm
		"brawler": return 3.0 * BOSS_HIT[cid] * _d(floorf(34.0 + 3.5 * F), armor) # Earthquake
		"mage": return 12.0 * BOSS_HIT[cid] * _d(floorf(46.0 + 4.2 * F), armor) # Starfall
		"rogue": return 15.0 * BOSS_HIT[cid] * _d(floorf(floorf(11.0 + 1.2 * F) * 1.5), armor) # Blade Tempest
		"summoner": return _minion_dps_horde(f, armor) * ULT_HORDE_LIFE * acc # Horde
	return 0.0

func _minion_dps_horde(f: int, armor: float) -> float:
	var base: float = (8.0 + 0.45 * float(f)) * SUMMON_POWER * ULT_HORDE_POWER
	return 3.0 * _d(base, armor) / 0.55 + 2.0 * _d(base * 0.8, armor) / 0.85 # 3 spirit + 2 wisp (guardian không gây sát thương)

## DPS trung bình của Ultimate = sát thương mỗi lần xả x tốc độ nạp (điểm/s) / 100.
func ult_dps(cid: String, wid: String, f: int, armor: float, acc: float) -> float:
	var w: Dictionary = G.weapons[wid]
	var hit_pts: float = minf(ULT_HIT_BUDGET, _hits_per_sec(w) * acc * ULT_HIT_CHARGE)
	var rate: float = hit_pts + ULT_KILL_PTS_PER_SEC + ULT_TAKEN_PCT_PER_SEC * 0.6
	return ult_per_cast(cid, f, armor, acc) * rate / 100.0

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
	var cls: Array = ["ranger", "brawler", "mage", "rogue", "summoner"]
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
	_p("## 2. Chỉ số so sánh class (DPS lên boss, trung bình các class = 100, chưa tính Ultimate/tiến hoá)")
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
	_p("## 5. Ultimate + kỹ năng tiến hoá (chỉ số, trung bình mọi class = 100)")
	_p("")
	_p("Mỗi biến thể: vũ khí + kỹ năng (khởi đầu hoặc tiến hoá A/B) + Ultimate trung bình. Chi tiết DPS tầng 6 ở cuối mục.")
	_p("")
	var variants: Array = ["Khởi đầu+Ult", "A+Ult", "B+Ult"]
	_p("| Tầng | Biến thể | " + " | ".join(PackedStringArray(cls)) + " | lệch max |")
	_p("|---|---|" + "---|".repeat(cls.size()) + "---|")
	var det: PackedStringArray = PackedStringArray()
	for f in BOSS_FLOORS:
		var bb: Dictionary = boss_for(f)
		var ar: float = float(bb["armor"])
		for vi in range(3):
			var vals2: Array = []
			for c in cls:
				var wid2: String = String(G.classes[c]["default_weapon"])
				var wd: float = weapon_dps(c, wid2, rarity, ar, acc)
				var sk2: float = float(skill_bonus(c, wid2, rarity, f, ar, acc)["extra"])
				var sk_use: float = sk2
				if vi > 0:
					var ev: float = evolved_bonus(c, "A" if vi == 1 else "B", wid2, rarity, f, ar, acc)
					sk_use = (sk2 + ev) if c == "summoner" else ev
				var ud: float = ult_dps(c, wid2, f, ar, acc)
				vals2.append(wd + sk_use + ud)
				if f == 6:
					det.append("- %s %s: vũ khí %.1f + kỹ năng %.1f + ult %.1f = %.1f dps" % [c, variants[vi], wd, sk_use, ud, wd + sk_use + ud])
			var mean2: float = vals2.reduce(func(a, b): return a + b) / vals2.size()
			var idx: Array = vals2.map(func(v): return int(round(v / mean2 * 100.0)))
			_p("| %d | %s | %s | %d |" % [f, variants[vi], " | ".join(PackedStringArray(idx.map(func(v): return str(v)))), int(idx.max()) - int(idx.min())])
	_p("")
	for line in det:
		_p(line)
	_p("")
	_p("## 6. Bầy quái (3 mục tiêu, giáp 0): vũ khí khởi đầu + kỹ năng khởi đầu + Ult, chỉ số trung bình = 100")
	_p("")
	_p("| Tầng | " + " | ".join(PackedStringArray(cls)) + " | lệch max |")
	_p("|---|" + "---|".repeat(cls.size()) + "---|")
	for f in BOSS_FLOORS:
		var sv: Array = []
		for c in cls:
			var wid3: String = String(G.classes[c]["default_weapon"])
			var m: Array = SWARM[c]
			var ult3: float = ult_dps(c, wid3, f, 0.0, acc)
			if c != "summoner": # ult bầy: nhân số mục tiêu trên cơ sở sát thương mỗi mục tiêu (tỉ lệ trúng boss thay bằng 1 phần)
				ult3 = ult3 / float(BOSS_HIT[c]) * 0.4 # GIẢ ĐỊNH: mỗi mục tiêu nhận ~40% số xung
			sv.append(weapon_dps(c, wid3, rarity, 0.0, acc) * float(m[0]) + float(skill_bonus(c, wid3, rarity, f, 0.0, acc)["extra"]) * float(m[1]) + ult3 * float(m[2]))
		var mean3: float = sv.reduce(func(a, b): return a + b) / sv.size()
		var ix: Array = sv.map(func(v): return int(round(v / mean3 * 100.0)))
		_p("| %d | %s | %d |" % [f, " | ".join(PackedStringArray(ix.map(func(v): return str(v)))), int(ix.max()) - int(ix.min())])
	_p("")
	_p("## 7. Ghi chú đọc số liệu")
	_p("- Giáp boss giảm theo phần trăm (K=%.0f); đạn nhỏ (SMG, Flamethrower) bị phạt như mọi vũ khí nhưng làm tròn tối thiểu 1 sát thương/đòn." % G.ARMOR_K)
	_p("- Mục tiêu dự án: mọi class trong ±8% so với trung bình (cột lệch max ≤ 16). Class chênh quá ~25% so với trung bình ở nhiều tầng liên tiếp đáng cân nhắc chỉnh; dưới ~15% coi như cân bằng.")
	_p("- Giả định Ultimate/tiến hoá (đổi ở hằng số đầu file): nạp ult = min(6, đòn/s x 0.7) + 0.4 (hạ quái) + 0.6 (nhận 1% máu/s); tỉ lệ ult trúng boss BOSS_HIT (Bullet Storm 13%, Starfall 15%, Blade Tempest 70%, Earthquake 100%); Summoner tiến hoá cộng thêm lên lính; Smoke Veil 1 nhịp/0.5s; Shadow Rush ước lượng. Chưa kiểm chứng bằng chơi thật.\n- Chưa tính: sát thương diện rộng (Arcane Staff nổ, Flamethrower/Scythe xuyên nhiều quái — lợi thế của mage trong bầy quái bị đánh giá thấp ở bảng boss), buff (Power/Crit/Berserk/...), rank vũ khí, trạng thái (cháy/độc/chảy máu), mastery, né/di chuyển, mô hình lượng sát thương nhận.")
	if String(opts["out"]) != "":
		var f := FileAccess.open(String(opts["out"]), FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(_out) + "\n")
			f.close()
	quit()
