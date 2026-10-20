extends RefCounted
## Meta-progression: hồ sơ vĩnh viễn (thống kê) + tiến hoá class. Thuần dữ liệu, không phụ thuộc scene.
## Hồ sơ là Dictionary lưu trong save (Global.profile); các hàm static ở đây chỉ đọc/ghi dictionary đó.
## Thêm bậc tiến hoá mới = thêm 1 dòng vào EVOLUTIONS[class] (điều kiện "boss" hoặc "floor").

## Mỗi bậc: name, skill (id kỹ năng), skill_name, desc, req {type: "boss"|"floor", ...}.
const EVOLUTIONS: Dictionary = {
	"ranger": [
		{"name": "Ranger+", "skill": "barrage", "skill_name": "Barrage",
		 "desc": "[Q] Fire 3 fan volleys of bullets.",
		 "req": {"type": "boss", "kind": "lord", "count": 2}},
	],
	"brawler": [
		{"name": "Brawler+", "skill": "shockwave", "skill_name": "Shockwave",
		 "desc": "[Q] Blast enemies away and clear bullets.",
		 "req": {"type": "boss", "kind": "lord", "count": 2}},
	],
}

## Số ván gần nhất giữ trong hồ sơ (thống kê cuối run).
const HISTORY_MAX: int = 20

static func new_class_entry() -> Dictionary:
	return {"runs": 0, "best_floor": 0, "kills": 0, "bosses": {}, "tier": 0}

static func new_profile() -> Dictionary:
	return {"runs": 0, "wins": 0, "best_floor": 0, "kills": 0, "secrets": 0, "bosses": {}, "classes": {}, "history": []}

## Gộp dữ liệu đã lưu vào cấu trúc mặc định (save cũ thiếu khóa vẫn đọc được).
static func merge_loaded(loaded) -> Dictionary:
	var p: Dictionary = new_profile()
	if not (loaded is Dictionary):
		return p
	for k in ["runs", "wins", "best_floor", "kills", "secrets"]:
		p[k] = int(loaded.get(k, 0))
	var b = loaded.get("bosses", {})
	if b is Dictionary:
		for kind in b: p["bosses"][String(kind)] = int(b[kind])
	var cl = loaded.get("classes", {})
	if cl is Dictionary:
		for cid in cl:
			var e: Dictionary = new_class_entry()
			var src = cl[cid]
			if src is Dictionary:
				for k in ["runs", "best_floor", "kills", "tier"]:
					e[k] = int(src.get(k, 0))
				var sb = src.get("bosses", {})
				if sb is Dictionary:
					for kind in sb: e["bosses"][String(kind)] = int(sb[kind])
			p["classes"][String(cid)] = e
	var h = loaded.get("history", [])
	if h is Array:
		for entry in h:
			if entry is Dictionary:
				p["history"].append(entry)
		p["history"] = p["history"].slice(maxi(0, p["history"].size() - HISTORY_MAX))
	return p

static func cls(p: Dictionary, cid: String) -> Dictionary:
	if not p["classes"].has(cid):
		p["classes"][cid] = new_class_entry()
	return p["classes"][cid]

static func record_run_start(p: Dictionary, cid: String) -> void:
	p["runs"] += 1
	cls(p, cid)["runs"] += 1

static func record_floor(p: Dictionary, cid: String, floor_num: int) -> void:
	p["best_floor"] = maxi(p["best_floor"], floor_num)
	var c: Dictionary = cls(p, cid)
	c["best_floor"] = maxi(c["best_floor"], floor_num)

## Ghi 1 ván vừa kết thúc vào lịch sử (giữ HISTORY_MAX ván gần nhất).
static func record_run_end(p: Dictionary, entry: Dictionary) -> void:
	var h: Array = p.get("history", [])
	h.append(entry)
	if h.size() > HISTORY_MAX:
		h = h.slice(h.size() - HISTORY_MAX)
	p["history"] = h

static func record_kill(p: Dictionary, cid: String) -> void:
	p["kills"] += 1
	cls(p, cid)["kills"] += 1

static func record_secret(p: Dictionary) -> void:
	p["secrets"] = int(p.get("secrets", 0)) + 1

static func record_win(p: Dictionary) -> void:
	p["wins"] += 1

static func record_boss(p: Dictionary, cid: String, kind: String) -> void:
	p["bosses"][kind] = int(p["bosses"].get(kind, 0)) + 1
	var cb: Dictionary = cls(p, cid)["bosses"]
	cb[kind] = int(cb.get(kind, 0)) + 1

static func tier_of(p: Dictionary, cid: String) -> int:
	return int(cls(p, cid)["tier"])

## Bậc tiến hoá kế tiếp của class (Dictionary rỗng nếu đã hết bậc).
static func next_evolution(p: Dictionary, cid: String) -> Dictionary:
	var list: Array = EVOLUTIONS.get(cid, [])
	var t: int = tier_of(p, cid)
	return list[t] if t < list.size() else {}

## [hiện tại, cần] của điều kiện bậc kế tiếp; [0, 0] nếu không còn bậc.
static func progress(p: Dictionary, cid: String) -> Array:
	var evo: Dictionary = next_evolution(p, cid)
	if evo.is_empty():
		return [0, 0]
	var req: Dictionary = evo["req"]
	var c: Dictionary = cls(p, cid)
	if req["type"] == "boss":
		var need: int = int(req["count"])
		return [mini(int(c["bosses"].get(req["kind"], 0)), need), need]
	var need_f: int = int(req["value"])
	return [mini(int(c["best_floor"]), need_f), need_f]

static func can_evolve(p: Dictionary, cid: String) -> bool:
	var pr: Array = progress(p, cid)
	return pr[1] > 0 and pr[0] >= pr[1]

static func evolve(p: Dictionary, cid: String) -> bool:
	if not can_evolve(p, cid):
		return false
	cls(p, cid)["tier"] += 1
	return true

## Kỹ năng đang có của class ("" nếu chưa tiến hoá) — lấy từ bậc cao nhất đã mở.
static func active_skill(p: Dictionary, cid: String) -> String:
	var list: Array = EVOLUTIONS.get(cid, [])
	var t: int = mini(tier_of(p, cid), list.size())
	return String(list[t - 1]["skill"]) if t > 0 else ""

## Tên hiển thị của class theo bậc ("Ranger" → "Ranger+").
static func display_name(p: Dictionary, cid: String, base: String) -> String:
	var list: Array = EVOLUTIONS.get(cid, [])
	var t: int = mini(tier_of(p, cid), list.size())
	return String(list[t - 1]["name"]) if t > 0 else base
