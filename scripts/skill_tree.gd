extends RefCounted
## Cây kỹ năng mở rộng (meta, mua bằng Purple Gem). Thuần dữ liệu + hàm static, không phụ thuộc scene.
## Triết lý: phần lớn là nút "lựa chọn / tiện lợi", chỉ vài nút cộng sức mạnh và tổng sức mạnh bị chặn bởi
## POWER_CAP (kiểm bằng test) để cây không biến thành lạm phát chỉ số. Mỗi nút mua một lần (cấp 0/1).
## Các hệ thống khác chỉ ĐỌC qua hàm static (truyền Global.upgrades vào), không tự gọi ngược lên menu.
## Thêm nút mới = thêm 1 dòng vào NODES + khoá tương ứng trong Global.upgrades.

const POWER_CAP: float = 0.25

const BRANCH_ORDER: Array = ["comfort", "combat"]
const BRANCH_TITLE: Dictionary = {"comfort": "CONVENIENCE", "combat": "COMBAT"}

## cost: Purple Gem; req: nút phải có trước ("" = không); power: phần sức mạnh thật nó cộng (0 = chỉ tiện lợi).
const NODES: Dictionary = {
	"choice4": {"branch": "comfort", "name": "Wider Choice", "desc": "Buff offers show 4 cards instead of 3.", "cost": 4, "req": "", "power": 0.0},
	"reroll": {"branch": "comfort", "name": "Second Thoughts", "desc": "Reroll each buff offer once (press R).", "cost": 5, "req": "choice4", "power": 0.0},
	"coin_bonus": {"branch": "comfort", "name": "Deep Pockets", "desc": "+10% coins from pickups.", "cost": 3, "req": "", "power": 0.0},
	"start_buff": {"branch": "comfort", "name": "Packed Supplies", "desc": "Start every run with a random common buff.", "cost": 6, "req": "coin_bonus", "power": 0.05},
	"q_cooldown": {"branch": "combat", "name": "Quick Study", "desc": "Class skill cooldown -10% (all classes).", "cost": 4, "req": "", "power": 0.07},
	"q_damage": {"branch": "combat", "name": "Honed Technique", "desc": "Class skill damage +10% (all classes).", "cost": 4, "req": "q_cooldown", "power": 0.07},
	"soft_shield": {"branch": "combat", "name": "Supple Plating", "desc": "Shield regenerates 10% faster.", "cost": 3, "req": "", "power": 0.04},
}

const CHOICE_COUNT_BASE: int = 3
const CHOICE_COUNT_WIDE: int = 4
const COIN_BONUS: float = 0.10
const Q_COOLDOWN_MULT: float = 0.90
const Q_DAMAGE_MULT: float = 1.10
const SHIELD_REGEN_MULT: float = 1.10

static func ids() -> Array:
	var out: Array = []
	for b in BRANCH_ORDER:
		for id in NODES:
			if String(NODES[id]["branch"]) == b:
				out.append(id)
	return out

static func owned(up: Dictionary, id: String) -> bool:
	return int(up.get(id, 0)) > 0

## true nếu nút tồn tại, chưa mua, và nút điều kiện đã có.
static func can_unlock(up: Dictionary, id: String) -> bool:
	if not NODES.has(id) or owned(up, id):
		return false
	var req: String = String(NODES[id]["req"])
	return req == "" or owned(up, req)

static func cost(id: String) -> int:
	return int(NODES.get(id, {}).get("cost", 0))

## Mua nút: trừ gem trong `gems` (Dictionary {"gems": n}) nếu đủ. Trả về true nếu mua được.
static func buy(up: Dictionary, gems: Dictionary, id: String) -> bool:
	if not can_unlock(up, id) or int(gems.get("gems", 0)) < cost(id):
		return false
	gems["gems"] = int(gems["gems"]) - cost(id)
	up[id] = 1
	return true

static func total_power(up: Dictionary) -> float:
	var t: float = 0.0
	for id in NODES:
		if owned(up, id):
			t += float(NODES[id]["power"])
	return t

static func max_total_power() -> float:
	var t: float = 0.0
	for id in NODES:
		t += float(NODES[id]["power"])
	return t

# --- Hiệu ứng (các hệ thống gọi) ---
static func buff_choice_count(up: Dictionary) -> int:
	return CHOICE_COUNT_WIDE if owned(up, "choice4") else CHOICE_COUNT_BASE

static func rerolls_per_offer(up: Dictionary) -> int:
	return 1 if owned(up, "reroll") else 0

static func coin_bonus(up: Dictionary) -> float:
	return COIN_BONUS if owned(up, "coin_bonus") else 0.0

static func has_start_buff(up: Dictionary) -> bool:
	return owned(up, "start_buff")

static func skill_cooldown_mult(up: Dictionary) -> float:
	return Q_COOLDOWN_MULT if owned(up, "q_cooldown") else 1.0

static func skill_damage_mult(up: Dictionary) -> float:
	return Q_DAMAGE_MULT if owned(up, "q_damage") else 1.0

static func shield_regen_mult(up: Dictionary) -> float:
	return SHIELD_REGEN_MULT if owned(up, "soft_shield") else 1.0
