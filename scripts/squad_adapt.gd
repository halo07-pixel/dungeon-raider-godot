extends RefCounted
## Đội hình thích nghi: đổi chiến thuật của cả đội quái theo lối chơi đã quan sát (PlayerProfiler).
## Thuần dữ liệu + hàm static (không đụng scene) nên test headless được. SquadDirector gọi tactics() mỗi
## lần cập nhật và áp kết quả; không nơi nào khác đọc hồ sơ để đổi hành vi đội.
## Nguyên tắc: KHÔNG tăng máu/sát thương, mọi hiệu ứng nhỏ và có trần, chỉ bật khi đủ dữ liệu và từ tầng
## MIN_FLOOR. Đặt ENABLED = false để tắt riêng phần thích nghi. Mọi hệ số cân bằng nằm ở đầu file.

const ENABLED: bool = true
const MIN_FLOOR: int = 3
const MIN_CONFIDENCE: float = 0.4       # dưới mức này coi như chưa biết lối chơi
const BIAS_THRESHOLD: float = 0.35      # |melee_bias| tối thiểu để coi là hay đứng xa / hay cận chiến
const DODGE_THRESHOLD: float = 0.3      # |dodge_bias| tối thiểu để đón đầu hướng né
const BURST_SHOTS_PER_SEC: float = 2.5  # nhịp ra đòn từ mức này là "đánh dồn dập"

# Người hay đứng xa xả súng: ép sát hơn.
const KITER_FLANK_WEIGHT_MULT: float = 1.25
const KITER_FLANK_RADIUS_MULT: float = 0.85
const KITER_CHASE_SPEED_MAX: float = 1.12   # quái cận chiến đang ở xa chạy nhanh hơn tối đa chừng này
# Người hay lao cận chiến: tản rộng, xạ thủ lùi xa.
const MELEE_FLANK_RADIUS_MULT: float = 1.35
const MELEE_RANGED_BEHIND_MULT: float = 1.4
# Người né lệch một bên: đón đầu về phía đó.
const LEAD_WEIGHT_MAX: float = 0.45
const LEAD_MIN_DIST: float = 60.0
const LEAD_MAX_DIST: float = 240.0
# Người đánh dồn dập: đội gom lại chờ nhau lâu hơn.
const BURST_WAIT_DIST_MULT: float = 1.4
const BURST_WAIT_FAST_RATIO: float = 0.75

const DEFAULT: Dictionary = {
	"active": false, "strength": 0.0, "tags": [],
	"flank_weight_mult": 1.0, "flank_radius_mult": 1.0, "chase_speed": 1.0,
	"ranged_behind_mult": 1.0, "lead": 0.0,
	"wait_dist_mult": 1.0, "wait_fast_ratio": 0.0, # 0 = giữ hằng số gốc của SquadDirector
}

## Độ tin cậy -> sức mạnh thích nghi 0..1 (0 khi chưa đủ dữ liệu).
static func strength_for(confidence: float) -> float:
	return clampf((confidence - MIN_CONFIDENCE) / (1.0 - MIN_CONFIDENCE), 0.0, 1.0)

## profile: {melee_bias, dodge_bias, shots_per_sec, confidence}. Trả về Dictionary cùng khoá với DEFAULT.
static func tactics(profile: Dictionary, floor_num: int) -> Dictionary:
	var t: Dictionary = DEFAULT.duplicate(true)
	if not ENABLED or floor_num < MIN_FLOOR:
		return t
	var s: float = strength_for(float(profile.get("confidence", 0.0)))
	if s <= 0.0:
		return t
	t["strength"] = s
	var tags: Array = []
	var mb: float = float(profile.get("melee_bias", 0.0))
	var db: float = float(profile.get("dodge_bias", 0.0))
	var sps: float = float(profile.get("shots_per_sec", 0.0))
	if mb <= -BIAS_THRESHOLD:
		var k: float = s * minf(1.0, absf(mb))
		t["flank_weight_mult"] = lerpf(1.0, KITER_FLANK_WEIGHT_MULT, k)
		t["flank_radius_mult"] = lerpf(1.0, KITER_FLANK_RADIUS_MULT, k)
		t["chase_speed"] = lerpf(1.0, KITER_CHASE_SPEED_MAX, k)
		tags.append("kiter")
	elif mb >= BIAS_THRESHOLD:
		var k: float = s * minf(1.0, absf(mb))
		t["flank_radius_mult"] = lerpf(1.0, MELEE_FLANK_RADIUS_MULT, k)
		t["ranged_behind_mult"] = lerpf(1.0, MELEE_RANGED_BEHIND_MULT, k)
		tags.append("melee")
	if absf(db) >= DODGE_THRESHOLD:
		t["lead"] = signf(db) * LEAD_WEIGHT_MAX * s * minf(1.0, absf(db))
		tags.append("dodge_right" if db > 0.0 else "dodge_left")
	if sps >= BURST_SHOTS_PER_SEC:
		t["wait_dist_mult"] = lerpf(1.0, BURST_WAIT_DIST_MULT, s)
		t["wait_fast_ratio"] = lerpf(0.0, BURST_WAIT_FAST_RATIO, s)
		tags.append("burst")
	t["tags"] = tags
	t["active"] = not tags.is_empty()
	return t

## Dòng chữ Game Over từ các nhãn đã thích nghi trong ván ("" nếu chưa có).
const TAG_TEXT: Dictionary = {
	"kiter": "you shoot from range", "melee": "you fight up close",
	"dodge_left": "you dodge left", "dodge_right": "you dodge right", "burst": "you attack in bursts",
}
const TAG_ORDER: Array = ["kiter", "melee", "dodge_left", "dodge_right", "burst"]

static func adapted_text(seen: Dictionary) -> String:
	var parts: Array = []
	for id in TAG_ORDER:
		if seen.has(id):
			parts.append(TAG_TEXT[id])
	if parts.is_empty():
		return ""
	return "Enemies adapted: " + ", ".join(parts)
