extends RefCounted
## Boss Rush: đánh lần lượt các boss thật trong phòng boss thật, trạng thái riêng (không đụng save/cờ thật). Static như state.gd.
const STATE = preload("res://hk/state.gd")
const ORDER: Array = [["warden", "gate_6"], ["hexer", "gate_7"], ["brute", "cat_6"], ["wraith", "cat_8"], ["colossus", "arc_5"], ["lord", "vault_7"]]
const SECRET: Array = ["many_faced", "sov_1"]   # chỉ thêm khi đã có True End ở một ô save
const RUN_PATH: String = "user://hk_rush_run.json"   # save tạm của lượt đang chơi
static var record_path: String = "user://hk_rush.json"
static var idx: int = 0
static var deaths: int = 0
static var order: Array = []

## Mở khoá khi có ô save nào đã hạ Dungeon Lord.
static func unlocked() -> bool:
	for i in STATE.SLOTS:
		if bool(STATE.slot_info(i).get("done", false)):
			return true
	return false

static func has_true_end() -> bool:
	for i in STATE.SLOTS:
		if bool(STATE.slot_info(i).get("true_end", false)):
			return true
	return false

## Dựng trạng thái cho một lượt: ván trắng + đủ kỹ năng, 7 mặt nạ, 5 ô, mọi bùa (bùa độc quyền cũng có).
static func setup(with_secret: bool) -> void:
	STATE.reset()
	STATE.save_path = RUN_PATH
	STATE.delete_save()
	for a in STATE.ABILITIES:
		STATE.give_ability(a)
	for c in STATE.CHARMS:
		STATE.give_charm(c)
	STATE.hp_bonus = 2
	STATE.notch_bonus = 2
	STATE.toggle_charm("heavy_blow")
	STATE.toggle_charm("swift_edge")
	STATE.hp = STATE.max_hp()
	order = ORDER.duplicate()
	if with_secret:
		order.append(SECRET)
	idx = 0
	deaths = 0

static func current_room() -> String:
	return String(order[idx][1])

static func last() -> bool:
	return idx >= order.size() - 1

## Thời gian tốt nhất đã lưu (giây), -1 nếu chưa có. Đọc có kiểm tra kiểu.
static func best() -> float:
	if not FileAccess.file_exists(record_path):
		return -1.0
	var d = JSON.parse_string(FileAccess.get_file_as_string(record_path))
	if d is Dictionary and (d.get("best") is float or d.get("best") is int) and float(d["best"]) > 0.0:
		return float(d["best"])
	return -1.0

## Ghi kỷ lục nếu nhanh hơn; trả true khi phá kỷ lục.
static func submit(time: float) -> bool:
	var b: float = best()
	if b > 0.0 and time >= b:
		return false
	var f := FileAccess.open(record_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"best": time}))
	f.close()
	return true
