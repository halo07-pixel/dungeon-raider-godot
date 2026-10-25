extends RefCounted
## "Một cây vũ khí cụ thể" (Weapon System 2.0): {"id", "rarity", "level", "affixes"}.
##  - id      : khóa trong Global.weapons (loại vũ khí)
##  - rarity  : common / rare / epic / legendary / mythic  (Global.rarities)
##  - level   : cấp nâng +0..+5 (mỗi cấp +LEVEL_DMG sát thương; +5 mở "Mastery" riêng từng loại — xem Player._rank_perk)
##  - affixes : mảng id dòng phụ (AFFIXES) — random lúc rơi, mỗi cây khác nhau
## Hàm static thuần dữ liệu (không đụng Node) để Player / Pickup / HUD / Forge dùng chung và test được.

const MAX_LEVEL: int = 5
const LEVEL_DMG: float = 0.08

## Số dòng phụ theo độ hiếm.
const AFFIX_COUNT: Dictionary = {"common": 0, "rare": 1, "epic": 2, "legendary": 2, "mythic": 3}

## kind: "both" | "melee" | "ranged". mods: dmg/cd/knock/reach = hệ số nhân; crit/steal/pierce/burn/slow/bleed = cộng dồn.
##   burn/slow/bleed = xác suất gây trạng thái mỗi lần trúng. reach: cận chiến = tầm chém, tầm xa = tầm bay của đạn.
const AFFIXES: Dictionary = {
	"heavy": {"name": "Heavy", "kind": "both", "mods": {"dmg": 1.2, "cd": 1.15}, "desc": "+20% damage, 15% slower"},
	"swift": {"name": "Swift", "kind": "both", "mods": {"cd": 0.85}, "desc": "15% faster attacks"},
	"keen": {"name": "Keen", "kind": "both", "mods": {"crit": 0.12}, "desc": "+12% crit chance"},
	"vampiric": {"name": "Vampiric", "kind": "both", "mods": {"steal": 0.025}, "desc": "+2.5% lifesteal"},
	"piercing": {"name": "Piercing", "kind": "ranged", "mods": {"pierce": 1}, "desc": "shots pierce 1 more enemy"},
	"reaching": {"name": "Reaching", "kind": "both", "mods": {"reach": 1.2}, "desc": "+20% reach"},
	"burning": {"name": "Burning", "kind": "both", "mods": {"burn": 0.25}, "desc": "25% chance to ignite"},
	"chilling": {"name": "Chilling", "kind": "both", "mods": {"slow": 0.25}, "desc": "25% chance to slow"},
	"serrated": {"name": "Serrated", "kind": "both", "mods": {"bleed": 0.30}, "desc": "30% chance to bleed"},
	"brutal": {"name": "Brutal", "kind": "melee", "mods": {"dmg": 1.1, "knock": 1.6}, "desc": "+10% damage, heavy knockback"},
}

## Đặc tính Mythic riêng từng loại vũ khí (hiệu ứng thật nằm ở Player._shoot/_swing; ở đây chỉ là tên + mô tả).
const MYTHIC_TRAITS: Dictionary = {
	"pistol": {"name": "Hail of Lead", "desc": "Every 5th shot fires a 5-bullet piercing fan."},
	"smg": {"name": "Blazing Barrel", "desc": "Fires 20% faster; every bullet pierces 1 enemy."},
	"shotgun": {"name": "Dragon's Breath", "desc": "+3 pellets and a longer blast."},
	"bow": {"name": "Gale Quiver", "desc": "Full draw looses 1 extra piercing arrow."},
	"railgun": {"name": "Twin Rail", "desc": "+15% damage and 10% faster recharge."},
	"staff": {"name": "Cataclysm", "desc": "Explosions are 35% wider."},
	"crossbow": {"name": "Impaler", "desc": "Pin hits +40% harder, stun +0.8s, 15% faster."},
	"flamethrower": {"name": "Inferno Heart", "desc": "Burn +50% and flames reach 25% further."},
	"chakram": {"name": "Twin Fang", "desc": "Faster disc; return pass +50% damage."},
	"laser": {"name": "Prism Lance", "desc": "Pierces 3 more enemies."},
	"broadsword": {"name": "Sunrend", "desc": "+20% reach and 20% crit chance."},
	"daggers": {"name": "Phantom Flurry", "desc": "20% faster; every hit bleeds."},
	"spear": {"name": "Skewer", "desc": "Full damage to everything in line; +10% reach."},
	"scythe": {"name": "Soul Harvest", "desc": "Half the blood cost; +5% heal on hit."},
	"hammer": {"name": "Earthshaker", "desc": "+20% reach; stuns for 2s."},
}

static func make(id: String, rarity: String = "common", level: int = 0, affixes: Array = []) -> Dictionary:
	return normalize({"id": id, "rarity": rarity, "level": level, "affixes": affixes})

## Chuẩn hóa mọi dạng đầu vào (Dictionary đã lưu / chuỗi mã hóa / save cũ {"id","rarity"}) thành instance hợp lệ.
## Trả {} nếu id hay độ hiếm không còn tồn tại.
static func normalize(v) -> Dictionary:
	if v is String:
		v = decode(String(v))
	if not (v is Dictionary):
		return {}
	var id: String = String(v.get("id", ""))
	if not Global.weapons.has(id):
		return {}
	# Ván lưu cũ có bậc/cấp/dòng phụ khác thì đưa hết về bậc chuẩn: chỉ giữ LOẠI vũ khí.
	return {"id": id, "rarity": Global.STANDARD_RARITY, "level": 0, "affixes": []}

static func _kind_ok(aid: String, melee: bool) -> bool:
	var kind: String = String(AFFIXES[aid]["kind"])
	return kind == "both" or (kind == "melee") == melee

## Random các dòng phụ hợp loại vũ khí, số lượng theo độ hiếm (không trùng nhau).
static func roll_affixes(id: String, rarity: String, count: int = -1) -> Array:
	if not Global.weapons.has(id):
		return []
	if count < 0:
		count = int(AFFIX_COUNT.get(rarity, 0))
	var melee: bool = bool(Global.weapons[id].get("is_melee", false))
	var pool: Array = []
	for aid in AFFIXES:
		if _kind_ok(aid, melee):
			pool.append(aid)
	pool.shuffle()
	return pool.slice(0, mini(count, pool.size()))

## Tạo vũ khí mới với dòng phụ random.
static func roll(id: String, rarity: String, level: int = 0) -> Dictionary:
	return make(id, rarity, level, roll_affixes(id, rarity))

## Mã chuỗi cho Pickup (setup("weapon", code)): "id:rarity:level:aff1,aff2". Mã cũ "id:rarity" vẫn giải được.
static func encode(inst: Dictionary) -> String:
	return "%s:%s:%d:%s" % [inst["id"], inst["rarity"], int(inst.get("level", 0)), ",".join(PackedStringArray(inst.get("affixes", [])))]

static func decode(code: String) -> Dictionary:
	var p: PackedStringArray = code.split(":")
	if p.size() < 1 or p[0] == "":
		return {}
	var affs: Array = []
	if p.size() >= 4 and p[3] != "":
		affs = Array(p[3].split(","))
	return normalize({
		"id": p[0],
		"rarity": p[1] if p.size() >= 2 else "common",
		"level": int(p[2]) if p.size() >= 3 else 0,
		"affixes": affs,
	})

static func is_mythic(inst: Dictionary) -> bool:
	return String(inst.get("rarity", "")) == "mythic"

static func level_mult(level: int) -> float:
	return 1.0 + LEVEL_DMG * float(clampi(level, 0, MAX_LEVEL))

## Gộp mọi dòng phụ thành 1 bảng chỉ số. Hệ số nhân mặc định 1.0, chỉ số cộng mặc định 0.
static func affix_mods(inst: Dictionary) -> Dictionary:
	var m: Dictionary = {"dmg": 1.0, "cd": 1.0, "knock": 1.0, "reach": 1.0,
		"crit": 0.0, "steal": 0.0, "pierce": 0, "burn": 0.0, "slow": 0.0, "bleed": 0.0}
	for aid in inst.get("affixes", []):
		var mods: Dictionary = AFFIXES.get(aid, {}).get("mods", {})
		for k in mods:
			if k in ["dmg", "cd", "knock", "reach"]:
				m[k] = float(m[k]) * float(mods[k])
			elif k == "pierce":
				m[k] = int(m[k]) + int(mods[k])
			else:
				m[k] = float(m[k]) + float(mods[k])
	return m

static func affix_name(aid: String) -> String:
	return String(AFFIXES.get(aid, {}).get("name", aid))

## "Pistol +3" / "Pistol"; tên loại lấy từ Global.weapons.
static func display_name(inst: Dictionary) -> String:
	if inst.is_empty():
		return ""
	var nm: String = String(Global.weapons[inst["id"]]["name"])
	var lv: int = int(inst.get("level", 0))
	return nm if lv <= 0 else "%s +%d" % [nm, lv]

## Các dòng mô tả dòng phụ cho thẻ so sánh / tooltip: ["Heavy: +20% damage, 15% slower", ...]
static func affix_lines(inst: Dictionary) -> Array:
	var out: Array = []
	for aid in inst.get("affixes", []):
		out.append("%s: %s" % [affix_name(aid), String(AFFIXES[aid]["desc"])])
	return out

static func mythic_trait(id: String) -> Dictionary:
	return MYTHIC_TRAITS.get(id, {})

## Giá trị "tổng điểm" thô để so sánh nhanh 2 cây (dùng cho gợi ý/forge): hệ số độ hiếm * cấp * số dòng phụ.
static func power_score(inst: Dictionary) -> float:
	if inst.is_empty():
		return 0.0
	var r: float = float(Global.rarities[inst["rarity"]]["mult"])
	return r * level_mult(int(inst.get("level", 0))) * (1.0 + 0.05 * float(inst.get("affixes", []).size()))
