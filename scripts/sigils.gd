extends RefCounted
## Sigil (rune kỹ năng): gắn vào kỹ năng class (Q) hoặc Tome (F) để đổi cách kỹ năng đó chơi. Thuần dữ liệu + hàm static,
## không đụng Node: Global/Player/SigilRunner/ClassSkill/TomeSkill chỉ đọc qua total() và các hàm ô gắn bên dưới.
## Mỗi Sigil có "mods" (khóa -> giá trị). Hệ số nhân (dmg/cd/radius/life) nhân dồn; các khóa còn lại cộng dồn:
##   dmg      : sát thương kỹ năng        cd     : thời gian hồi chiêu        radius : bán kính/kích thước vùng
##   life     : thời gian tồn tại (vùng, lính, hiệu ứng kéo dài)
##   burn     : xác suất đốt mỗi đòn trúng   slow : xác suất làm chậm 1.5s   heal : máu hồi mỗi đòn trúng (giới hạn nhịp)
##   shield   : giáp nhận khi tung               refund : giây hồi chiêu hoàn lại khi kỹ năng hạ gục
##   crits    : số đòn vũ khí chắc chí mạng sau khi tung   recast : xác suất tung lại miễn phí
##   sunder   : > 0 -> đòn trúng phá giáp        chain  : xác suất sét nảy sang 2 quái gần đó
## Thêm Sigil mới = thêm 1 dòng vào SIGILS (id duy nhất); nếu cần khóa mới thì xử lý nó trong SigilRunner / ClassSkill / TomeSkill.

const TARGETS: Array = ["class", "tome"]
const RARITY_ORDER: Array = ["common", "rare", "epic"]
const RARITY_COLOR: Dictionary = {"common": Color(0.85, 0.85, 0.9), "rare": Color(0.3, 0.7, 1.0), "epic": Color(0.75, 0.4, 0.95)}
const RARITY_NAME: Dictionary = {"common": "Common", "rare": "Rare", "epic": "Epic"}

## Số ô gắn: kỹ năng class 2 (3 khi class đã tiến hoá), Tome 2.
const CLASS_SLOTS: int = 2
const CLASS_SLOTS_EVOLVED: int = 3
const TOME_SLOTS: int = 2

const SIGILS: Dictionary = {
	"might": {"name": "Rune of Might", "rarity": "common", "mods": {"dmg": 1.2}, "desc": "+20% skill damage."},
	"swiftness": {"name": "Rune of Swiftness", "rarity": "common", "mods": {"cd": 0.85}, "desc": "Cooldown -15%."},
	"expanse": {"name": "Rune of Expanse", "rarity": "common", "mods": {"radius": 1.2}, "desc": "+20% area size."},
	"persistence": {"name": "Rune of Persistence", "rarity": "common", "mods": {"life": 1.25}, "desc": "Zones, minions and lasting effects last 25% longer."},
	"ember": {"name": "Ember Sigil", "rarity": "rare", "mods": {"burn": 0.35}, "desc": "Skill hits have a 35% chance to ignite."},
	"rime": {"name": "Rime Sigil", "rarity": "rare", "mods": {"slow": 0.5}, "desc": "Skill hits have a 50% chance to slow for 1.5s."},
	"siphon": {"name": "Siphon Sigil", "rarity": "rare", "mods": {"heal": 1.0}, "desc": "Each skill hit heals 1 HP (at most 3 times a second)."},
	"aegis": {"name": "Aegis Sigil", "rarity": "rare", "mods": {"shield": 12.0}, "desc": "Using the skill grants 12 shield."},
	"harvest": {"name": "Harvest Sigil", "rarity": "rare", "mods": {"refund": 1.0}, "desc": "Each kill by the skill refunds 1s of cooldown (up to half of it per cast)."},
	"keen": {"name": "Keen Sigil", "rarity": "rare", "mods": {"crits": 2.0}, "desc": "After using the skill, your next 2 weapon hits are critical."},
	"echo": {"name": "Echo Sigil", "rarity": "epic", "mods": {"recast": 0.25}, "desc": "25% chance to cast the skill a second time for free."},
	"overcharge": {"name": "Overcharge Sigil", "rarity": "epic", "mods": {"dmg": 1.5, "cd": 1.25}, "desc": "+50% skill damage, but cooldown +25%."},
	"fracture": {"name": "Fracture Sigil", "rarity": "epic", "mods": {"sunder": 1.0, "dmg": 1.1}, "desc": "+10% skill damage; hits break enemy armor."},
	"storm": {"name": "Storm Sigil", "rarity": "epic", "mods": {"chain": 0.3}, "desc": "Skill hits have a 30% chance to arc lightning to 2 nearby enemies."},
}

## Trọng số xuất hiện theo độ hiếm; Epic nhiều dần theo tầng.
static func rarity_weights(floor_num: int) -> Dictionary:
	var epic: float = 6.0 + 1.5 * float(floor_num)
	var rare: float = 30.0 + 1.0 * float(floor_num)
	return {"common": maxf(10.0, 100.0 - epic - rare), "rare": rare, "epic": epic}

static func exists(id: String) -> bool:
	return SIGILS.has(id)

static func info(id: String) -> Dictionary:
	return SIGILS.get(id, {})

static func display_name(id: String) -> String:
	return String(SIGILS.get(id, {}).get("name", id))

static func rarity_of(id: String) -> String:
	return String(SIGILS.get(id, {}).get("rarity", "common"))

## Số ô gắn của một kỹ năng.
static func capacity(target: String, class_evolved: bool) -> int:
	if target == "tome":
		return TOME_SLOTS
	return CLASS_SLOTS_EVOLVED if class_evolved else CLASS_SLOTS

## Giá trị gộp của khóa `key` qua danh sách Sigil `ids`. Khóa nhân: mặc định 1.0; khóa cộng: mặc định 0.0.
static func total(ids: Array, key: String) -> float:
	var mult_key: bool = key in ["dmg", "cd", "radius", "life"]
	var v: float = 1.0 if mult_key else 0.0
	for id in ids:
		var mods: Dictionary = SIGILS.get(String(id), {}).get("mods", {})
		if mods.has(key):
			if mult_key:
				v *= float(mods[key])
			else:
				v += float(mods[key])
	return v

## Chọn ngẫu nhiên `count` Sigil khác nhau (theo trọng số độ hiếm), bỏ qua các id trong `exclude`.
static func roll_choices(count: int, floor_num: int, exclude: Array = []) -> Array:
	var pool: Array = []
	for id in SIGILS:
		if not exclude.has(id):
			pool.append(String(id))
	var out: Array = []
	var w: Dictionary = rarity_weights(floor_num)
	while out.size() < count and not pool.is_empty():
		var sum: float = 0.0
		for id in pool:
			sum += float(w[rarity_of(id)])
		var r: float = randf() * sum
		var pick: String = String(pool[pool.size() - 1])
		for id in pool:
			r -= float(w[rarity_of(id)])
			if r <= 0.0:
				pick = String(id)
				break
		out.append(pick)
		pool.erase(pick)
	return out

## Bảng ô gắn rỗng: {"class": [], "tome": []}.
static func empty_slots() -> Dictionary:
	return {"class": [], "tome": []}

## Chuẩn hóa dữ liệu lưu (id lạ/trùng bị bỏ, quá số ô thì cắt).
static func normalize(raw, class_evolved: bool) -> Dictionary:
	var out: Dictionary = empty_slots()
	if not (raw is Dictionary):
		return out
	var seen: Array = []
	for t in TARGETS:
		var arr = raw.get(t, [])
		if not (arr is Array):
			continue
		for id in arr:
			var sid: String = String(id)
			if SIGILS.has(sid) and not seen.has(sid) and out[t].size() < capacity(t, class_evolved):
				out[t].append(sid)
				seen.append(sid)
	return out

static func all_socketed(slots: Dictionary) -> Array:
	var out: Array = []
	for t in TARGETS:
		out.append_array(slots.get(t, []))
	return out

## Gắn `id` vào kỹ năng: ưu tiên `prefer`, còn ô trống thì vào đó; hết ô thì ép vào `prefer` thay Sigil cũ nhất.
## `available`: các đích hợp lệ (vd Tome chưa có thì không gắn được). Trả {"target", "displaced"} (displaced = "" nếu chỉ vào ô trống),
## hoặc {} nếu id lạ / đã gắn rồi.
static func socket(slots: Dictionary, id: String, prefer: String, class_evolved: bool, available: Array) -> Dictionary:
	if not SIGILS.has(id) or all_socketed(slots).has(id):
		return {}
	var order: Array = []
	if available.has(prefer):
		order.append(prefer)
	for t in TARGETS:
		if available.has(t) and not order.has(t):
			order.append(t)
	if order.is_empty():
		return {}
	for t in order:
		if slots[t].size() < capacity(t, class_evolved):
			slots[t].append(id)
			return {"target": t, "displaced": ""}
	var tgt: String = String(order[0])
	var old: String = String(slots[tgt].pop_front())
	slots[tgt].append(id)
	return {"target": tgt, "displaced": old}
