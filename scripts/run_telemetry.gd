extends Node
## Thống kê một ván: thời gian và sát thương nhận theo từng tầng, để biết quái dễ hay khó bằng số thật.
## Node con của Main (Main gọi xuống: finish_run); tự nghe Global.floor_started / player_damaged (signal đi lên).
## Dữ liệu nằm trong Global.run_stats["telemetry"] nên đi theo save "Continue". Phần tính toán là hàm static
## thuần dữ liệu (không đụng scene) để test headless được. Node dừng đếm giờ khi game tạm dừng (PAUSABLE).

const BossScript = preload("res://scripts/boss.gd")

const KEY: String = "telemetry"
const HURT_KEY: String = "hurt_by"          # {nguồn: tổng sát thương} cả ván
const LAST_KEY: String = "last_hurt_by"    # nguồn gây sát thương gần nhất (khi chết = kẻ hạ gục)
const TOP_SOURCES: int = 3
const SOURCE_NAMES: Dictionary = {
	"dot:burn": "Burning", "dot:poison": "Poison", "hazard:lava": "Lava", "hazard:poison": "Poison pool",
	"hazard:ice": "Ice floor", "hazard:boss": "Boss attack zone", "hazard:council": "Council flames",
	"trap:spikes": "Spike trap", "trap:event": "Trap room", "affix:volatile": "Volatile explosion",
}

var _floor: int = 1
var _finished: bool = false
var _won: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_floor = maxi(1, Global.floor_num)
	Global.floor_started.connect(_on_floor_started)
	Global.player_damaged.connect(_on_player_damaged)
	Global.player_hurt_by.connect(_on_player_hurt_by)

func _physics_process(delta: float) -> void:
	if _finished:
		return
	add_time(Global.run_stats, _floor, delta)

func _on_floor_started(floor_num: int) -> void:
	_floor = maxi(1, floor_num)

func _on_player_damaged(amount: int, _max_hp: int) -> void:
	if _finished:
		return
	add_damage(Global.run_stats, _floor, amount)

func _on_player_hurt_by(source: String, amount: int) -> void:
	if _finished:
		return
	add_source(Global.run_stats, source, amount)

## Đánh dấu đã hạ Lord trong ván này (đi tiếp Vô Hạn rồi chết vẫn tính là ván thắng).
func mark_won() -> void:
	_won = true

## Chốt ván: ghi 1 dòng lịch sử vào hồ sơ và trả về entry. Chỉ chốt một lần.
func finish_run(won: bool) -> Dictionary:
	if _finished:
		return {}
	_finished = true
	var entry: Dictionary = build_entry(Global.run_stats, Global.current_class, _floor, won or _won)
	entry["heat"] = Global.heat_points()
	Global.record_run_end(entry)
	return entry

# --- Hàm thuần dữ liệu ---

static func ensure(stats: Dictionary) -> Dictionary:
	if not (stats.get(KEY) is Dictionary):
		stats[KEY] = {}
	return stats[KEY]

static func _floor_entry(stats: Dictionary, floor_num: int) -> Dictionary:
	var t: Dictionary = ensure(stats)
	if not t.has(floor_num):
		t[floor_num] = {"time": 0.0, "dmg": 0}
	return t[floor_num]

static func add_time(stats: Dictionary, floor_num: int, secs: float) -> void:
	var e: Dictionary = _floor_entry(stats, floor_num)
	e["time"] = float(e["time"]) + secs

static func add_damage(stats: Dictionary, floor_num: int, amount: int) -> void:
	var e: Dictionary = _floor_entry(stats, floor_num)
	e["dmg"] = int(e["dmg"]) + maxi(0, amount)

## Tổng hợp: tổng thời gian/sát thương, tầng nhận nhiều sát thương nhất, tầng lâu nhất.
static func summary(stats: Dictionary) -> Dictionary:
	var t: Dictionary = ensure(stats)
	var out: Dictionary = {"total_time": 0.0, "total_damage": 0,
		"hardest_floor": 0, "hardest_damage": 0, "slowest_floor": 0, "slowest_time": 0.0}
	for f in t:
		var e: Dictionary = t[f]
		var tm: float = float(e["time"])
		var dm: int = int(e["dmg"])
		out["total_time"] += tm
		out["total_damage"] += dm
		if dm > int(out["hardest_damage"]):
			out["hardest_damage"] = dm
			out["hardest_floor"] = int(f)
		if tm > float(out["slowest_time"]):
			out["slowest_time"] = tm
			out["slowest_floor"] = int(f)
	return out

# --- Nguồn sát thương (ai/cái gì làm Player mất máu) ---

static func add_source(stats: Dictionary, source: String, amount: int) -> void:
	var src: String = source if source != "" else "unknown"
	if not (stats.get(HURT_KEY) is Dictionary):
		stats[HURT_KEY] = {}
	var d: Dictionary = stats[HURT_KEY]
	d[src] = int(d.get(src, 0)) + maxi(0, amount)
	stats[LAST_KEY] = src

## Tên hiển thị: "enemy:hell_ogre" -> "Hell Ogre", "boss:lord" -> "Dungeon Lord".
static func source_name(source: String) -> String:
	if SOURCE_NAMES.has(source):
		return SOURCE_NAMES[source]
	var parts: PackedStringArray = source.split(":", false, 1)
	if parts.size() == 2:
		if parts[0] == "boss" and BossScript.BOSS_DATA.has(parts[1]):
			return String(BossScript.BOSS_DATA[parts[1]]["name"])
		return parts[1].replace("_", " ").capitalize()
	return "Unknown"

## [[nguồn, sát thương, phần trăm]...] giảm dần theo sát thương, tối đa n phần tử.
static func top_sources(stats: Dictionary, n: int = TOP_SOURCES) -> Array:
	var d: Dictionary = stats.get(HURT_KEY, {}) if stats.get(HURT_KEY) is Dictionary else {}
	var total: int = 0
	for k in d:
		total += int(d[k])
	var rows: Array = []
	for k in d:
		rows.append([String(k), int(d[k])])
	rows.sort_custom(func(a, b): return a[1] > b[1] or (a[1] == b[1] and a[0] < b[0]))
	var out: Array = []
	for r in rows.slice(0, n):
		out.append([r[0], r[1], int(round(100.0 * float(r[1]) / float(maxi(1, total))))])
	return out

static func killer(stats: Dictionary) -> String:
	return String(stats.get(LAST_KEY, ""))

## Dòng chữ màn Game Over: kẻ hạ gục + các nguồn gây nhiều sát thương nhất ("" nếu chưa có số liệu).
static func death_text(stats: Dictionary) -> String:
	var k: String = killer(stats)
	if k == "":
		return ""
	var lines: Array = ["Killed by: %s" % source_name(k)]
	var parts: Array = []
	for r in top_sources(stats):
		parts.append("%s %d%%" % [source_name(r[0]), int(r[2])])
	if not parts.is_empty():
		lines.append("Most damage from: " + ", ".join(parts))
	return "\n".join(lines)

static func fmt_time(secs: float) -> String:
	var s: int = int(secs)
	return "%d:%02d" % [s / 60, s % 60]

## Dòng chữ hiển thị ở màn kết thúc ("" nếu chưa có số liệu).
static func summary_text(stats: Dictionary) -> String:
	var s: Dictionary = summary(stats)
	if float(s["total_time"]) <= 0.0 and int(s["total_damage"]) <= 0:
		return ""
	var lines: Array = ["Run time: %s · Damage taken: %d" % [fmt_time(float(s["total_time"])), int(s["total_damage"])]]
	if int(s["hardest_floor"]) > 0:
		lines.append("Hardest floor: %d (%d damage)" % [int(s["hardest_floor"]), int(s["hardest_damage"])])
	if int(s["slowest_floor"]) > 0:
		lines.append("Slowest floor: %d (%s)" % [int(s["slowest_floor"]), fmt_time(float(s["slowest_time"]))])
	return "\n".join(lines)

static func build_entry(stats: Dictionary, cid: String, last_floor: int, won: bool) -> Dictionary:
	var s: Dictionary = summary(stats)
	return {"class": cid, "floor": last_floor, "won": won, "kills": int(stats.get("kills", 0)),
		"time": snappedf(float(s["total_time"]), 0.1), "damage": int(s["total_damage"]),
		"hardest_floor": int(s["hardest_floor"]),
		"killer": killer(stats), "top_source": String(top_sources(stats, 1)[0][0]) if not top_sources(stats, 1).is_empty() else ""}
