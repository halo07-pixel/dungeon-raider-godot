extends RefCounted
## Chế độ Heat: điều kiện khó hơn do người chơi TỰ CHỌN trước khi vào ván, đổi lấy nhiều Ngọc Tím hơn.
## Thuần dữ liệu + hàm static (không đụng scene). Độ khó đến từ HÀNH VI (thêm affix, thêm đợt quái, boss vào pha
## sớm...) thay vì chỉ nhân HP, để người chơi mạnh có thể tự đẩy thử thách mà không cần chỉnh số cho mọi người.
## Global giữ lựa chọn ở menu (heat_selected, lưu trong save) và bản chốt cho ván đang chơi (run_heat).
## Thêm mức Heat mới = thêm 1 dòng vào MODS + đọc Global.heat_on("id") ở chỗ cần áp dụng.

const GEM_BONUS_PER_POINT: float = 0.15   # mỗi điểm Heat cộng 15% Ngọc Tím nhận được
const AFFIX_CHANCE_BONUS: float = 0.20    # Veteran Packs: cộng vào tỉ lệ quái có affix
const AFFIX_EXTRA_PER_ROOM: int = 1       # Veteran Packs: thêm số quái có affix tối đa mỗi phòng
const HEAL_DROP_MULT: float = 0.5         # Scarce Supplies: nhân tỉ lệ rơi bình máu
const FLOOR_HEAL_FRACTION: float = 0.30   # hồi khi sang tầng mới (bình thường)
const FLOOR_HEAL_FRACTION_SCARCE: float = 0.15
const ENEMY_SPEED_MULT: float = 1.15      # Swift Foes
const REINFORCE_WAVE_SCALE: float = 0.5   # Reinforcements: đợt hai có số quái bằng 50% đợt thường
const BOSS_START_PHASE: int = 2           # Furious Bosses
const PLAYER_DAMAGE_MULT: float = 1.25    # Glass Cannon

const ORDER: Array = ["elite_pack", "scarce", "swift", "reinforce", "furious", "glass"]
const MODS: Dictionary = {
	"elite_pack": {"name": "Veteran Packs", "cost": 1,
		"desc": "Enemies carry affixes far more often, up to 3 per room."},
	"scarce": {"name": "Scarce Supplies", "cost": 1,
		"desc": "Heal drops are halved and new floors heal 15% instead of 30%."},
	"swift": {"name": "Swift Foes", "cost": 1,
		"desc": "Enemies move 15% faster."},
	"reinforce": {"name": "Reinforcements", "cost": 2,
		"desc": "Every normal room sends a second, smaller wave when you clear it."},
	"furious": {"name": "Furious Bosses", "cost": 2,
		"desc": "Bosses start in phase 2."},
	"glass": {"name": "Glass Cannon", "cost": 2,
		"desc": "You take 25% more damage."},
}

## Tổng điểm Heat của một danh sách id (id lạ bị bỏ qua).
static func total(ids: Array) -> int:
	var t: int = 0
	for id in ids:
		if MODS.has(id):
			t += int(MODS[id]["cost"])
	return t

static func gem_mult(ids: Array) -> float:
	return 1.0 + GEM_BONUS_PER_POINT * float(total(ids))

## Ngọc Tím sau thưởng Heat (làm tròn lên; không Heat thì giữ nguyên).
static func gems(base: int, ids: Array) -> int:
	if base <= 0 or total(ids) <= 0:
		return base
	return int(ceil(float(base) * gem_mult(ids)))

## Lọc về các id hợp lệ theo thứ tự chuẩn (dùng khi nạp save).
static func sanitize(ids: Array) -> Array:
	var out: Array = []
	for id in ORDER:
		if ids.has(id):
			out.append(id)
	return out
