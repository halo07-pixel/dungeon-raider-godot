extends RefCounted
## Nightmare: phòng "biết nói dối". Chọn lúc chạy theo id phòng (cùng phòng luôn cùng kiểu, không sửa file phòng):
## tối (chỉ nhìn quanh người), im lặng (tắt nhạc/ambient), khoá cửa tới khi hết quái (có giờ chót), rương mimic.
const STATE = preload("res://hk/state.gd")
const LOCK_MIN: int = 3          # phòng có từ chừng này quái trở lên mới có thể khoá
const SEAL_TIMEOUT: float = 60.0 # khoá tối đa chừng này giây (quái kẹt/không tới được thì cửa vẫn mở lại)
const MIMIC_EVERY: int = 3       # cứ rương thứ 3 (theo băm khoá rương) là mimic
const MIMIC_HINT: float = 140.0  # lại gần chừng này thì có âm sột soạt báo trước

## "dark" | "silent" | "lock" | "": không áp cho phòng boss, phòng có bench/thương nhân; tối chỉ khi phòng không có gai.
static func mode_for(id: String, data: Dictionary, enemies: int, hazards: int, has_safe_spot: bool) -> String:
	if not STATE.is_nightmare() or data.has("boss") or has_safe_spot:
		return ""
	var h: int = _mix(id) % 10
	if h < 3 and hazards == 0:
		return "dark"
	if h == 3:
		return "silent"
	if h >= 4 and h <= 6 and enemies >= LOCK_MIN:
		return "lock"
	return ""

## Băm md5 (id liên tiếp như gate_1/gate_2 không cho số liên tiếp), dùng 16 bit đầu.
static func _mix(s: String) -> int:
	return ("0x" + s.md5_text().substr(0, 4)).hex_to_int()

## Rương mimic: không phải rương hốc bí mật (hốc luôn thật).
static func is_mimic(key: String, hidden: bool) -> bool:
	return STATE.is_nightmare() and not hidden and _mix(key) % MIMIC_EVERY == 0
