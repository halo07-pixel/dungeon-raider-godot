extends RefCounted
## Trạng thái ván chơi (static, sống qua các lần đổi phòng) + lưu/đọc file. Không phải autoload để test dễ reset.
const SAVE_PATH_DEFAULT: String = "user://hk_save.json"
const BASE_HP: int = 5
const BASE_NOTCHES: int = 3
const SOUL_MAX: int = 99
const START_ROOM: String = "gate_1"

const ABILITIES: Dictionary = {
	"dash": {"name": "Shadow Dash", "desc": "Press the dash key to dash. Recharges when you land."},
	"double_jump": {"name": "Wings of Ash", "desc": "Jump once more in mid-air."},
	"wall_cling": {"name": "Claw Grip", "desc": "Cling to walls and jump off them."},
}

## Bùa: cost = số ô (notch) cần.
const CHARMS: Dictionary = {
	"swift_edge": {"name": "Swift Edge", "cost": 1, "desc": "Nail swings 25% faster."},
	"long_reach": {"name": "Long Reach", "cost": 2, "desc": "Nail reaches 35% further."},
	"soul_siphon": {"name": "Soul Siphon", "cost": 1, "desc": "Gain extra Soul on every nail hit."},
	"iron_heart": {"name": "Iron Heart", "cost": 2, "desc": "+2 masks."},
	"fortune": {"name": "Fortune", "cost": 1, "desc": "Enemies drop 50% more Geo."},
	"quick_focus": {"name": "Quick Focus", "cost": 3, "desc": "Focus heals much faster."},
	"fury": {"name": "Fury", "cost": 2, "desc": "At 1 mask your nail deals +75% damage."},
	"heavy_blow": {"name": "Heavy Blow", "cost": 2, "desc": "Nail deals +40% damage."},
}

static var save_path: String = SAVE_PATH_DEFAULT
static var boot: String = "continue"   # new | continue | keep — world đọc khi khởi động
static var hp_bonus: int = 0            # từ vật phẩm "mặt nạ" mua ở shop
static var hp: int = BASE_HP
static var soul: int = 0
static var geo: int = 0
static var abilities: Array = []
static var charms_owned: Array = []
static var charms_equipped: Array = []
static var notch_bonus: int = 0
static var flags: Dictionary = {}       # cờ một lần: boss đã hạ, bàn thờ đã lấy, ...
static var visited: Array = []
static var bench_room: String = START_ROOM
static var bench_id: String = "start"
static var shade: Dictionary = {}       # {room, x, y, geo}
static var pins: Array = []             # ghim bản đồ do người chơi đặt: {room, x, y}
const MAX_PINS: int = 10
# Âm lượng 0..10: không bị reset() xoá (là cài đặt, không phải tiến trình); lưu cùng file save.
# shortcut: chỉ lưu khi có save, màn tiêu đề dùng mặc định tới khi vào ván; tách file cài đặt khi có thêm cài đặt khác.
static var music_vol: int = 10
static var sfx_vol: int = 10

static func vol_db(v: int) -> float:
	return -80.0 if v <= 0 else linear_to_db(float(v) / 10.0)

static func reset() -> void:
	hp_bonus = 0
	soul = 0
	geo = 0
	abilities = []
	charms_owned = []
	charms_equipped = []
	notch_bonus = 0
	flags = {}
	visited = []
	bench_room = START_ROOM
	bench_id = "start"
	shade = {}
	pins = []
	hp = max_hp()

static func has_ability(id: String) -> bool:
	return id in abilities

static func has_charm(id: String) -> bool:
	return id in charms_equipped

static func max_hp() -> int:
	return BASE_HP + hp_bonus + (2 if has_charm("iron_heart") else 0)

static func notches() -> int:
	return BASE_NOTCHES + notch_bonus

static func notches_used() -> int:
	var n: int = 0
	for c in charms_equipped:
		n += int(CHARMS[c]["cost"])
	return n

## Bật/tắt bùa; trả về false nếu không đủ ô hoặc chưa sở hữu.
static func toggle_charm(id: String) -> bool:
	if id in charms_equipped:
		charms_equipped.erase(id)
		hp = mini(hp, max_hp())
		return true
	if not (id in charms_owned) or notches_used() + int(CHARMS[id]["cost"]) > notches():
		return false
	charms_equipped.append(id)
	return true

static func give_charm(id: String) -> void:
	if CHARMS.has(id) and not (id in charms_owned):
		charms_owned.append(id)

static func give_ability(id: String) -> void:
	if ABILITIES.has(id) and not (id in abilities):
		abilities.append(id)

static func flag(id: String) -> bool:
	return bool(flags.get(id, false))

static func set_flag(id: String) -> void:
	flags[id] = true

## Đặt ghim tại `pos` trong phòng `room_id`; nếu đã có ghim trong bán kính `radius` thì gỡ nó. Trả true khi đặt mới
## (false khi gỡ, hoặc khi đã đủ MAX_PINS).
static func toggle_pin(room_id: String, pos: Vector2, radius: float = 48.0) -> bool:
	for p in pins:
		if String(p["room"]) == room_id and Vector2(float(p["x"]), float(p["y"])).distance_to(pos) <= radius:
			pins.erase(p)
			return false
	if pins.size() >= MAX_PINS:
		return false
	pins.append({"room": room_id, "x": pos.x, "y": pos.y})
	return true

static func visit(room_id: String) -> void:
	if not (room_id in visited):
		visited.append(room_id)

# ---- chỉ số suy ra từ bùa ----
static func attack_cooldown() -> float:
	return 0.35 * (0.75 if has_charm("swift_edge") else 1.0)

static func nail_reach_mult() -> float:
	return 1.35 if has_charm("long_reach") else 1.0

static func nail_damage() -> int:
	var m: float = 1.0
	if has_charm("heavy_blow"):
		m += 0.4
	if has_charm("fury") and hp <= 1:
		m += 0.75
	return maxi(1, roundi(5.0 * m))

static func soul_per_hit() -> int:
	return 11 + (5 if has_charm("soul_siphon") else 0)

static func focus_time() -> float:
	return 0.9 * (0.55 if has_charm("quick_focus") else 1.0)

static func geo_mult() -> float:
	return 1.5 if has_charm("fortune") else 1.0

# ---- lưu/đọc ----
static func to_dict() -> Dictionary:
	return {"v": 1, "hp_bonus": hp_bonus, "soul": soul, "geo": geo, "abilities": abilities, "charms_owned": charms_owned,
		"charms_equipped": charms_equipped, "notch_bonus": notch_bonus, "flags": flags, "visited": visited,
		"bench_room": bench_room, "bench_id": bench_id, "shade": shade, "music_vol": music_vol, "sfx_vol": sfx_vol, "pins": pins}

static func from_dict(d: Dictionary) -> void:
	reset()
	hp_bonus = clampi(int(d.get("hp_bonus", 0)), 0, 4)
	music_vol = clampi(int(d.get("music_vol", music_vol)), 0, 10)
	sfx_vol = clampi(int(d.get("sfx_vol", sfx_vol)), 0, 10)
	geo = maxi(0, int(d.get("geo", 0)))
	notch_bonus = clampi(int(d.get("notch_bonus", 0)), 0, 4)
	for a in d.get("abilities", []):
		give_ability(String(a))
	for c in d.get("charms_owned", []):
		give_charm(String(c))
	for c in d.get("charms_equipped", []):
		if c in charms_owned and not (c in charms_equipped) and notches_used() + int(CHARMS[c]["cost"]) <= notches():
			charms_equipped.append(String(c))
	var f = d.get("flags", {})
	flags = f if f is Dictionary else {}
	for r in d.get("visited", []):
		visited.append(String(r))
	bench_room = String(d.get("bench_room", START_ROOM))
	bench_id = String(d.get("bench_id", "start"))
	var s = d.get("shade", {})
	shade = s if s is Dictionary else {}
	for p in d.get("pins", []):   # dữ liệu save có thể hỏng: chỉ nhận ghim đúng kiểu, tối đa MAX_PINS
		if p is Dictionary and p.get("room") is String and (p.get("x") is float or p.get("x") is int) and (p.get("y") is float or p.get("y") is int) and pins.size() < MAX_PINS:
			pins.append({"room": String(p["room"]), "x": float(p["x"]), "y": float(p["y"])})
	hp = max_hp()

## Ghi nguyên tử: ghi file tạm rồi đổi tên, để mất điện giữa chừng không hỏng save.
static func save() -> bool:
	var tmp: String = save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	return DirAccess.rename_absolute(tmp, save_path) == OK

static func load_save() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not (data is Dictionary):
		return false
	from_dict(data)
	return true

static func delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
