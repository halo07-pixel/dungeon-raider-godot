extends RefCounted
## Dữ liệu + lựa chọn phòng sự kiện (thuần dữ liệu, dungeon.gd chỉ gọi pick_for_floor).
## Mọi hằng số cân bằng nằm ở đây để chỉnh sau khi chơi thử.

## Loại phòng sự kiện: tên hiển thị, màu minimap, trọng số chọn, tầng tối thiểu.
const TYPES: Dictionary = {
	"altar": {"label": "Altar", "color": Color(0.7, 0.4, 0.9), "weight": 3.0, "min_floor": 2},
	"challenge": {"label": "Challenge", "color": Color(0.95, 0.5, 0.2), "weight": 3.0, "min_floor": 2},
	"trapped_chest": {"label": "Chest", "color": Color(0.95, 0.8, 0.3), "weight": 3.0, "min_floor": 2},
	"secret": {"label": "Secret", "color": Color(0.4, 0.9, 0.5), "weight": 1.5, "min_floor": 2},
}
const COUNT_WEIGHTS: Array = [0.25, 0.5, 0.25] # xác suất có 0 / 1 / 2 phòng sự kiện trong tầng

# --- Altar: mỗi bàn thờ là Máu (buff Epic) hoặc Vàng (buff Hiếm); luôn chọn 1 trong N.
const ALTAR_HP_FRACTION: float = 0.25   # Altar Máu: hiến 25% máu tối đa
const ALTAR_GOLD_CHANCE: float = 0.5    # xác suất một bàn thờ là Altar Vàng
const ALTAR_GOLD_BASE: int = 40         # giá Altar Vàng = base + per_floor * tầng
const ALTAR_GOLD_PER_FLOOR: int = 10
const ALTAR_CHOICES: int = 2
# --- Challenge
const CHALLENGE_WAVES: int = 3
const CHALLENGE_WAVE_SCALE: float = 0.7  # số quái mỗi đợt so với phòng thường
const CHALLENGE_REWARD_COINS: int = 25   # lựa chọn an toàn: xu + 1 lượt chọn buff
const CHALLENGE_BONUS_WAVE_SCALE: float = 1.5 # lựa chọn cược: đợt thêm đông hơn đợt thường
const CHALLENGE_BIG_COINS: int = 60      # thưởng sau khi thắng đợt cược
const CHALLENGE_BIG_CHOICES: int = 3     # chọn 1 trong N buff Sử Thi
# --- Trapped chest (tổng = 1.0)
const CHEST_GOOD: float = 0.60
const CHEST_MIMIC: float = 0.25          # phần còn lại là bẫy
const CHEST_COINS: int = 30
const CHEST_BUFF_CHANCE: float = 0.4
const TRAP_HP_FRACTION: float = 0.15
const PRY_TAP_MAX: float = 0.25          # nhấn E nhanh hơn mức này = mở thường (rủi ro đủ cả bẫy lẫn Mimic)
const PRY_TIME: float = 1.6              # giữ E đủ lâu = nạy rương: bẫy bị vô hiệu, Mimic vẫn có thể xuất hiện
const MIMIC_GEM_REWARD: int = 1
# --- Secret
const SECRET_COINS: int = 25
const SECRET_GEM_GUARANTEED: int = 1
const SECRET_GEM_CHANCE: float = 0.3     # cơ hội thêm 1 viên nữa
const SECRET_BUFF_CHOICES: int = 3       # chọn 1 trong N buff Hiếm
const SECRET_REVEAL_DIST: float = 140.0  # lộ trên minimap khi đứng gần cửa từ phòng kề

static func is_event(room_type: String) -> bool:
	return TYPES.has(room_type)

## Chọn danh sách loại phòng sự kiện cho 1 tầng (mỗi loại tối đa 1 phòng/tầng, tối đa max_slots).
static func pick_for_floor(floor_num: int, max_slots: int) -> Array:
	var pool: Array = []
	for t in TYPES:
		if floor_num >= int(TYPES[t]["min_floor"]):
			pool.append(t)
	if pool.is_empty() or max_slots <= 0:
		return []
	var r: float = randf()
	var n: int = 0
	var acc: float = 0.0
	for i in COUNT_WEIGHTS.size():
		acc += float(COUNT_WEIGHTS[i])
		if r < acc:
			n = i
			break
	n = mini(n, mini(max_slots, pool.size()))
	var out: Array = []
	for k in n:
		var total: float = 0.0
		for t in pool: total += float(TYPES[t]["weight"])
		var roll: float = randf() * total
		var picked: String = pool[0]
		for t in pool:
			roll -= float(TYPES[t]["weight"])
			if roll <= 0.0:
				picked = t
				break
		out.append(picked)
		pool.erase(picked)
	return out

static func altar_gold_cost(floor_num: int) -> int:
	return ALTAR_GOLD_BASE + ALTAR_GOLD_PER_FLOOR * floor_num

## Buff Epic ngẫu nhiên hợp với vũ khí đang cầm, chưa đạt trần stack ("" nếu hết).
static func roll_epic_buff() -> String:
	var wclass: String = Global.player_weapon_class()
	var cands: Array = []
	for id in Global.buff_pool:
		var info: Dictionary = Global.buff_pool[id]
		var bclass: String = String(info.get("class", "any"))
		if info["tier"] == "epic" and (bclass == "any" or bclass == wclass) \
				and Global.buff_stack(id) < int(Global.BUFF_MAX_STACK.get(id, 1)):
			cands.append(id)
	return String(cands.pick_random()) if not cands.is_empty() else ""
