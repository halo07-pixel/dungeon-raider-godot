extends RefCounted
## Nội dung SURVIVAL GUIDE (BBCode) cho từng tab. Thuần dữ liệu: main_menu.gd chỉ dựng giao diện.
## Số liệu lấy TRỰC TIẾP từ dữ liệu game (Global.weapons / rarities / buff_pool / enemies, EnemyAffix,
## EventRooms, MetaProgress...) nên khi chỉnh cân bằng, sổ tay tự đúng. Chỉ phần mô tả (cách chơi, mẹo)
## là chữ viết tay. Tránh dùng ký tự "[" trong chữ thường: BBCode sẽ hiểu nhầm là thẻ.

const PlayerScript = preload("res://scripts/player.gd")
const ClassSkillScript = preload("res://scripts/class_skill.gd")
const MetaProgress = preload("res://scripts/meta_progress.gd")
const EnemyAffix = preload("res://scripts/enemy_affix.gd")
const EventRooms = preload("res://scripts/event_rooms.gd")
const BossScript = preload("res://scripts/boss.gd")
const EnemyScript = preload("res://scripts/enemy.gd")

const TAB_ORDER: Array = ["basics", "classes", "weapons", "buffs", "defense", "enemies", "events", "tips"]
const TAB_TITLES: Dictionary = {
	"basics": "BASICS", "classes": "CLASSES", "weapons": "WEAPONS", "buffs": "BUFFS",
	"defense": "DEFENSE", "enemies": "ENEMIES", "events": "EVENTS", "tips": "TIPS",
}
const TIER_ORDER: Array = ["common", "rare", "epic"]
const TIER_LABEL: Dictionary = {"common": "COMMON", "rare": "RARE", "epic": "EPIC"}
const TIER_HEX: Dictionary = {"common": "#dddddd", "rare": "#4db8ff", "epic": "#c05cf2"}
const CLASS_TAG: Dictionary = {"any": "", "melee": " (melee)", "ranged": " (ranged)"}

# ---------------------------------------------------------------- Tiện ích
static func _h(title: String, hex: String = "#ffd700") -> String:
	return "[center][b][color=%s]--- %s ---[/color][/b][/center]\n\n" % [hex, title]

static func _sub(title: String, hex: String = "#7fd4ff") -> String:
	return "\n[b][color=%s]%s[/color][/b]\n" % [hex, title]

static func _key(action: String) -> String:
	return "[b]%s[/b]" % Global.key_name_for_action(action)

static func _pct(x: float) -> String:
	var v: float = x * 100.0
	return ("%d%%" % int(v)) if is_equal_approx(v, round(v)) else ("%.1f%%" % v)

static func _num(x: float) -> String:
	if is_equal_approx(x, round(x)):
		return str(int(x))
	var txt: String = "%.2f" % x
	return txt.rstrip("0").rstrip(".") if "." in txt else txt

static func _display(kind: String) -> String:
	return kind.replace("_", " ").capitalize()

static func tab_text(tab_id: String) -> String:
	match tab_id:
		"basics": return basics()
		"classes": return classes()
		"weapons": return weapons()
		"buffs": return buffs()
		"defense": return defense()
		"enemies": return enemies()
		"events": return events()
		"tips": return tips()
	return ""

# ---------------------------------------------------------------- BASICS
static func basics() -> String:
	var t: String = _h("BASICS")
	t += "[b]Goal[/b]: clear rooms, grow stronger, and beat the boss on floor 10 (the Dungeon Lord). "
	t += "Beyond it, Endless mode starts and enemies scale up much faster.\n"
	t += _sub("Controls")
	t += "Move: %s %s %s %s\n" % [_key("move_up"), _key("move_left"), _key("move_down"), _key("move_right")]
	t += "Aim and attack: [b]Mouse[/b] (hold to keep attacking)\n"
	t += "Dodge roll: %s (brief invulnerability, short cooldown)\n" % _key("dodge")
	t += "Class skill: %s (after your class evolves)\n" % _key("skill")
	t += "Interact: %s (altars, chests, shrines)\n" % _key("interact")
	t += "Movement keys and dodge can be changed in Settings.\n"
	t += _sub("A run")
	t += "Each floor is a set of rooms. Clear a room to open its doors and pick 1 of 3 buffs. "
	t += "Spend coins at the shop NPC. Every floor ends with a boss room and a portal to the next floor.\n"
	t += "Biome changes: floors 1-3 Stone, 4-6 Swamp, 7-9 Frost. Poison, slow and sliding ice get more common as you go.\n"
	t += _sub("Between runs")
	t += "Purple Gems are kept after you die. Spend them in the SKILL TREE. Your PROFILE tracks runs, kills and bosses, "
	t += "and unlocks class evolutions.\n"
	return t

# ---------------------------------------------------------------- CLASSES
static func classes() -> String:
	var t: String = _h("CLASSES")
	for cid in Global.classes:
		var c: Dictionary = Global.classes[cid]
		var w: Dictionary = Global.weapons.get(String(c["default_weapon"]), {})
		t += "[b][color=#ffd700]%s[/color][/b]: %d HP, starts with %s.\n" % [c["name"], int(c["max_hp"]), String(w.get("name", "?"))]
		var list: Array = MetaProgress.EVOLUTIONS.get(cid, [])
		for evo in list:
			var req: Dictionary = evo["req"]
			var need: String = ""
			if String(req["type"]) == "boss":
				need = "defeat the %s %d times" % [_display(String(req["kind"])), int(req["count"])]
			else:
				need = "reach floor %d" % int(req.get("floor", 0))
			var sk: Dictionary = ClassSkillScript.SKILLS.get(String(evo["skill"]), {})
			t += "  Evolves into [b]%s[/b] (%s).\n" % [evo["name"], need]
			t += "  Skill [b]%s[/b], cooldown %s s: %s\n" % [evo["skill_name"], _num(float(sk.get("cooldown", 0.0))), String(evo["desc"]).replace("[Q]", Global.key_name_for_action("skill") + ":")]
		t += "\n"
	t += "Melee classes use short-range sweeping attacks and take hits better. Ranged classes keep distance, "
	t += "and get ranged-only buffs such as Ricochet and Homing. Melee-only buffs such as Sword Wave only appear for melee weapons.\n"
	return t

# ---------------------------------------------------------------- WEAPONS
static func weapons() -> String:
	var t: String = _h("WEAPONS")
	t += _sub("Ranged")
	for wid in Global.weapons:
		var w: Dictionary = Global.weapons[wid]
		if bool(w.get("is_melee", false)):
			continue
		var line: String = "[b]%s[/b]: %s dmg" % [w["name"], _num(float(w["damage"]))]
		if int(w.get("pellets", 1)) > 1:
			line += " x%d pellets" % int(w["pellets"])
		line += ", %.1f shots/s" % (1.0 / float(w["cooldown"]))
		if int(w.get("pierce_count", 0)) > 0:
			line += ", pierces %d enemies" % int(w["pierce_count"])
		t += line + "\n"
	t += _sub("Melee")
	for wid in Global.weapons:
		var w: Dictionary = Global.weapons[wid]
		if not bool(w.get("is_melee", false)):
			continue
		t += "[b]%s[/b]: %s dmg, %.1f swings/s, range %d, arc %d degrees\n" % [w["name"], _num(float(w["damage"])), 1.0 / float(w["cooldown"]), int(w["range"]), int(w["cleave_angle"])]
	t += _sub("Rarity")
	var tag_hex: Dictionary = {"common": "#dddddd", "rare": "#44ff44", "epic": "#b644ff", "legendary": "#ffd700"}
	for rid in Global.rarities:
		var r: Dictionary = Global.rarities[rid]
		var line: String = "[b][color=%s]%s[/color][/b]: x%s damage" % [tag_hex.get(rid, "#ffffff"), r["name"], _num(float(r["mult"]))]
		if float(r["lifesteal"]) > 0.0:
			line += ", %s lifesteal" % _pct(float(r["lifesteal"]))
		t += line + "\n"
	t += "Melee weapons get only %s of the lifesteal (and half again against bosses).\n" % _pct(Global.MELEE_LIFESTEAL_MULT)
	t += "Epic and Legendary weapons also gain a special effect.\n"
	return t

# ---------------------------------------------------------------- BUFFS
static func buffs() -> String:
	var t: String = _h("BUFFS")
	t += "After clearing a room you choose 1 of 3 buffs. Buffs that do not fit your weapon are never offered. "
	t += "A star shown on an offer means you already own a partner buff (synergy).\n"
	for tier in TIER_ORDER:
		t += _sub(String(TIER_LABEL[tier]) + (" (stack up to the limit)" if tier != "epic" else " (one copy only)"), String(TIER_HEX[tier]))
		var ids: Array = []
		for id in Global.buff_pool:
			if String(Global.buff_pool[id]["tier"]) == tier:
				ids.append(id)
		ids.sort_custom(func(a, b): return String(Global.buff_pool[a]["name"]) < String(Global.buff_pool[b]["name"]))
		for id in ids:
			var b: Dictionary = Global.buff_pool[id]
			var mx: int = int(Global.BUFF_MAX_STACK.get(id, 1))
			t += "[b]%s[/b]%s: %s" % [b["name"], CLASS_TAG.get(String(b["class"]), ""), b["desc"]]
			if mx > 1:
				t += " (max %d)" % mx
			t += "\n"
	t += _sub("Synergies")
	var seen: Dictionary = {}
	for a in Global.SYNERGY_MAP:
		for b in Global.SYNERGY_MAP[a]:
			var key: String = (a + "|" + b) if String(a) < String(b) else (b + "|" + a)
			if seen.has(key) or not Global.buff_pool.has(a) or not Global.buff_pool.has(b):
				continue
			seen[key] = true
			t += "%s + %s\n" % [Global.buff_pool[a]["name"], Global.buff_pool[b]["name"]]
	return t

# ---------------------------------------------------------------- DEFENSE
static func defense() -> String:
	var scr: Script = PlayerScript
	var consts: Dictionary = scr.get_script_constant_map()
	var t: String = _h("DEFENSE")
	t += _sub("Shield")
	t += "Shield absorbs damage before your HP. You start with %d.\n" % int(consts.get("SHIELD_BASE", 20))
	if consts.has("SHIELD_PER_FLOOR"):
		t += "It also grows by %d every floor.\n" % int(consts["SHIELD_PER_FLOOR"])
	else:
		t += "It only grows through buffs (Shield Cap), not by floor. Entering a new floor refills it.\n"
	t += "After %s s without being hit it regenerates %d per second.\n" % [_num(float(consts.get("SHIELD_REGEN_DELAY", 2.5))), int(consts.get("SHIELD_REGEN_RATE", 10.0))]
	t += "Related buffs: "
	var rel: Array = []
	for id in ["buff_shield_cap", "buff_shield_regen", "buff_shield_nova", "buff_fortify"]:
		if Global.buff_pool.has(id):
			rel.append("[b]%s[/b] (%s)" % [Global.buff_pool[id]["name"], Global.buff_pool[id]["desc"]])
	t += ", ".join(rel) + ".\n"
	t += _sub("Health")
	t += "Health does not regenerate on its own. Heal with pickups, Feast, Dodge Heal and lifesteal. "
	t += "Each new floor heals 30% of max HP.\n"
	t += _sub("Dodge roll")
	t += "Rolling makes you invulnerable while it lasts and moves you fast. Melee builds can turn the roll into an attack with Roll Slash.\n"
	t += _sub("Armor")
	t += "Tougher enemies and bosses have armor that reduces your damage by a percentage: armor 10 reduces %s, armor 19 reduces %s. " % [_pct(Global.armor_reduction(10.0)), _pct(Global.armor_reduction(19.0))]
	t += "Sunder stacks extra damage taken on whatever you hit, which helps against armor.\n"
	t += _sub("Floor scaling")
	t += "Enemy HP at floor 10 is about x%s of floor 1. Enemy damage also rises with the floor. After floor %d, Endless mode adds %s more difficulty per floor.\n" % [_num(Global.hp_scale_for_floor(10)), Global.ENDLESS_START_FLOOR, _pct(Global.ENDLESS_RATE)]
	return t

# ---------------------------------------------------------------- ENEMIES
const ENEMY_NOTES: Dictionary = {
	"slime": "Basic melee chaser.",
	"archer": "Shoots from range and keeps its distance.",
	"brute": "Slow, tanky, hits hard.",
	"shaman": "Ranged, its shots poison you.",
	"chort": "Fast and fragile melee.",
	"masked_orc": "Heavy swamp bruiser.",
	"frost_zombie": "Basic frost melee.",
	"frost_big_zombie": "Slams the ground and slows you.",
	"frost_tiny": "Fast, explodes on contact.",
	"mimic": "Only comes from trapped chests. Tough and rewards a Purple Gem.",
}

static func enemies() -> String:
	var t: String = _h("ENEMIES")
	for kind in Global.enemies:
		var e: Dictionary = Global.enemies[kind]
		t += "[b]%s[/b]: %d HP, %d contact dmg. %s\n" % [_display(kind), int(e["hp"]), int(e["touch"]), ENEMY_NOTES.get(kind, "")]
	t += "(Stats are for floor 1. They grow every floor.)\n"
	t += _sub("Elites")
	t += "%s of Archers and Shamans spawn as purple Elites with x%s HP. They learn from your habits and aim less predictably.\n" % [_pct(EnemyScript.ELITE_CHANCE), _num(EnemyScript.ELITE_HP_MULT)]
	t += _sub("Affixes")
	t += "From floor 2, normal enemies can carry an affix (up to %d per room). Chance rises with the floor, capped at %s.\n" % [EnemyAffix.MAX_PER_ROOM, _pct(EnemyAffix.CHANCE_MAX)]
	var af_notes: Dictionary = {
		"volatile": "explodes shortly after dying (%d dmg, move away when it warns)" % EnemyAffix.VOLATILE_DAMAGE,
		"warden": "shields nearby allies every %s s. Kill it to drop the shields" % _num(EnemyAffix.WARD_INTERVAL),
		"summoner": "calls up to %d minions every %s s. Kill it first" % [EnemyAffix.MAX_MINIONS, _num(EnemyAffix.SUMMON_INTERVAL)],
	}
	for id in EnemyAffix.AFFIXES:
		var a: Dictionary = EnemyAffix.AFFIXES[id]
		t += "[b]%s[/b] (from floor %d): %s.\n" % [a["label"], int(a["min_floor"]), af_notes.get(id, "")]
	t += _sub("Bosses")
	var order: Array = [["warden", "floors 1-3"], ["necromancer", "floors 4-6"], ["frost", "floors 7-9"], ["lord", "floor 10 and beyond"]]
	for row in order:
		var d: Dictionary = BossScript.BOSS_DATA.get(row[0], {})
		t += "[b]%s[/b] (%s): %d phases.\n" % [String(d.get("name", row[0])), row[1], int(d.get("phases", 3))]
	t += "Bosses change their behavior between phases. The Dungeon Lord also watches how you fight and adapts its attack choices.\n"
	return t

# ---------------------------------------------------------------- EVENTS
static func events() -> String:
	var t: String = _h("EVENT ROOMS")
	t += "From floor 2, a floor may contain 0 to 2 special rooms, marked with colors on the minimap. Walk up and press %s.\n" % _key("interact")
	t += _sub("Altar", "#c05cf2")
	t += "Give %s of your max HP to receive a random Epic buff. Needs enough HP to pay. Used once.\n" % _pct(EventRooms.ALTAR_HP_FRACTION)
	t += _sub("Challenge Shrine", "#f28030")
	t += "Starts %d waves of enemies. Survive them all for %d coins.\n" % [EventRooms.CHALLENGE_WAVES, EventRooms.CHALLENGE_REWARD_COINS]
	t += _sub("Chest", "#f2cc4d")
	t += "A gamble. %s of the time it is treasure (%d coins, a heal, maybe a buff choice). " % [_pct(EventRooms.CHEST_GOOD), EventRooms.CHEST_COINS]
	t += "%s it is a Mimic: defeat it for %d Purple Gem. Otherwise it is a trap that hurts %s of your max HP.\n" % [_pct(EventRooms.CHEST_MIMIC), EventRooms.MIMIC_GEM_REWARD, _pct(EventRooms.TRAP_HP_FRACTION)]
	t += _sub("Secret Room", "#66e680")
	t += "Hidden until you get near its door. Holds %d coins, a heal, and a %s chance of a Purple Gem.\n" % [EventRooms.SECRET_COINS, _pct(EventRooms.SECRET_GEM_CHANCE)]
	return t

# ---------------------------------------------------------------- TIPS
static func tips() -> String:
	var t: String = _h("TIPS")
	t += "- Dodge through attacks, not away from them: the roll is a free shield.\n"
	t += "- Kill Summoners and Wardens first; Volatile enemies are safest to finish from range.\n"
	t += "- Pick buffs that match your weapon. Synergy buffs are worth more than a single big one.\n"
	t += "- Shield regenerates, health does not. Avoid chip damage, and let the shield refill between fights.\n"
	t += "- Fortify rewards fast weapons. Combine it with Shield Cap so the bonus has room to grow.\n"
	t += "- Altars are worth the HP early in a floor, when you can still recover.\n"
	t += "- Do not rush a boss. Learn each phase, then punish the recovery after its big attacks.\n"
	t += "- Spend Purple Gems in the SKILL TREE after every run.\n"
	return t
