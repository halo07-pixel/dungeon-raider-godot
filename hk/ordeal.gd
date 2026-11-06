extends RefCounted
## Nightmare: phòng "biết nói dối". Chọn lúc chạy theo id phòng (cùng phòng luôn cùng kiểu, không sửa file phòng):
## tối (chỉ nhìn quanh người), im lặng (tắt nhạc/ambient), khoá cửa tới khi hết quái (có giờ chót), rương mimic.
const STATE = preload("res://hk/state.gd")
const LOCK_MIN: int = 3          # phòng có từ chừng này quái trở lên mới có thể khoá
const HIDDEN_GRACE: float = 20.0   # giây sau khi khoá: quái còn nấp thôi không tính
const SEAL_TIMEOUT: float = 60.0 # khoá tối đa chừng này giây (quái kẹt/không tới được thì cửa vẫn mở lại)
const WAVE2_N: int = 2           # đợt quái thứ hai của phòng khoá (một lần)
const WAVE2_LEFT: float = 15.0   # chỉ sinh khi khoá còn ít nhất chừng này giây
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

## Đợt 2: khi còn <= 1 quái (tính cả quái nấp, không tính minion), chưa sinh, khoá còn đủ giờ.
static func wave2_due(live: int, seal_left: float, done: bool) -> bool:
	return not done and live <= 1 and seal_left >= WAVE2_LEFT

## spawns = [{type, pos}] của phòng. Trả [{type, pos}] tối đa WAVE2_N: loại quái mặt đất đầu tiên (bỏ dropper), điểm xa người chơi nhất.
static func wave2_plan(spawns: Array, from: Vector2) -> Array:
	var kind: String = ""
	var pts: Array = []
	for e in spawns:
		if String(e["type"]) == "d":
			continue
		if kind == "":
			kind = String(e["type"])
		pts.append(e["pos"])
	pts.sort_custom(func(a, b): return a.distance_to(from) > b.distance_to(from))
	var out: Array = []
	for i in WAVE2_N:
		if pts.is_empty() or kind == "":
			break
		var pt: Vector2 = pts[i % pts.size()]
		out.append({"type": kind, "pos": pt})
	return out
