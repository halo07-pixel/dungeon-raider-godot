extends RefCounted
## Boss Rush: đánh lần lượt các boss thật trong phòng boss thật, trạng thái riêng (không đụng save/cờ thật). Static như state.gd.
const STATE = preload("res://hk/state.gd")
const ORDER: Array = [["warden", "gate_6"], ["hexer", "gate_7"], ["brute", "cat_6"], ["wraith", "cat_8"], ["colossus", "arc_5"], ["lord", "vault_7"]]
const SECRET: Array = ["many_faced", "sov_1"]   # chỉ thêm khi đã có True End ở một ô save
const HUB: String = "gate_8"   # phòng sảnh: có bench, không quái, cạnh gate_6; đi qua cửa nào cũng bắt đầu lượt
const RUN_PATH: String = "user://hk_rush_run.json"   # save tạm của lượt đang chơi
static var record_path: String = "user://hk_rush.json"
static var idx: int = -1             # -1 = đang ở sảnh, chưa bắt đầu
static var time: float = 0.0         # đồng hồ lượt: chỉ chạy khi đang đánh (không tính chờ giữa boss, fade, sảnh)
static var mark: float = 0.0         # time lúc hạ boss trước
static var splits: Array = []        # {id, seg, new} mỗi boss đã hạ
static var cleared: bool = false     # boss của phòng hiện tại đã hạ: đồng hồ dừng, chờ người chơi đi qua cửa sang boss kế
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
	idx = -1
	deaths = 0
	time = 0.0
	mark = 0.0
	splits = []
	cleared = false

## Rời sảnh, bắt đầu bấm giờ.
static func start() -> void:
	cleared = false
	idx = 0
	deaths = 0
	time = 0.0
	mark = 0.0
	splits = []

static func current_room() -> String:
	return HUB if idx < 0 else String(order[idx][1])

static func last() -> bool:
	return idx >= order.size() - 1

## File kỷ lục: {"best": giây cả lượt, "bosses": {id: giây tốt nhất một boss}}. Đọc có kiểm tra kiểu, hỏng thì coi như trống.
static func _load() -> Dictionary:
	var out: Dictionary = {"best": -1.0, "bosses": {}}
	if not FileAccess.file_exists(record_path):
		return out
	var d = JSON.parse_string(FileAccess.get_file_as_string(record_path))
	if not (d is Dictionary):
		return out
	if (d.get("best") is float or d.get("best") is int) and float(d["best"]) > 0.0:
		out["best"] = float(d["best"])
	var b = d.get("bosses", {})
	if b is Dictionary:
		for k in b:
			if k is String and (b[k] is float or b[k] is int) and float(b[k]) > 0.0:
				out["bosses"][k] = float(b[k])
	return out

static func _store(d: Dictionary) -> bool:
	var f := FileAccess.open(record_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d))
	f.close()
	return true

## Thời gian cả lượt tốt nhất (giây), -1 nếu chưa có.
static func best() -> float:
	return float(_load()["best"])

## Thời gian tốt nhất của một boss (giây), -1 nếu chưa có.
static func seg_best(id: String) -> float:
	return float(_load()["bosses"].get(id, -1.0))

## Ghi kỷ lục cả lượt nếu nhanh hơn; trả true khi phá kỷ lục.
static func submit(t: float) -> bool:
	var d: Dictionary = _load()
	if float(d["best"]) > 0.0 and t >= float(d["best"]):
		return false
	d["best"] = t
	return _store(d)

## Hạ boss `id` sau `seg` giây: ghi vào splits và kỷ lục boss (ghi ngay, bỏ lượt giữa chừng vẫn giữ). Trả true khi phá kỷ lục boss đó.
static func record_split(id: String, seg: float) -> bool:
	var d: Dictionary = _load()
	var old: float = float(d["bosses"].get(id, -1.0))
	var is_new: bool = old < 0.0 or seg < old
	if is_new:
		d["bosses"][id] = seg
		_store(d)
	splits.append({"id": id, "seg": seg, "new": is_new})
	return is_new

## "m:ss.d" cho thời gian ngắn của từng boss.
static func fmt(sec: float) -> String:
	var t: float = maxf(0.0, sec)
	return "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]
