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
	"mage": [
		{"name": "Mage+", "skill": "meteor_storm", "skill_name": "Meteor Storm",
		 "desc": "[Q] Mark the ground at your cursor; meteors crash down there shortly after.",
		 "req": {"type": "boss", "kind": "lord", "count": 2}},
	],
	"summoner": [
		{"name": "Summoner+", "skill": "legion", "skill_name": "Legion",
		 "desc": "[Q] Call 3 Spitelings that rush enemies and explode when their time runs out.",
		 "req": {"type": "boss", "kind": "lord", "count": 2}},
	],
	"rogue": [
		{"name": "Rogue+", "skill": "shadow_rush", "skill_name": "Shadow Rush",
		 "desc": "[Q] Dash far through enemies, making them bleed. Your next 3 hits are guaranteed critical.",
		 "req": {"type": "boss", "kind": "lord", "count": 2}},
	],
}

## Hướng tiến hoá B của mỗi class (cùng điều kiện mở khoá với EVOLUTIONS): khi tiến hoá chọn A hoặc B, đổi hướng tự do ở màn Profile.
## Cùng cấu trúc với EVOLUTIONS (name, skill, skill_name, desc, req).
const EVOLUTION_ALT: Dictionary = {
	"ranger": [
		{"name": "Deadeye", "skill": "railshot", "skill_name": "Railshot",
		 "desc": "[Q] Fire a piercing beam that hits everything in a long line and makes enemies bleed.",
		 "req": {"type": "boss", "kind": "lord", "count": 2}},
	],
	"brawler": [
		{"name": "Juggernaut", "skill": "charge", "skill_name": "Charge",
		 "desc": "[Q] Charge forward, ramming and knocking back enemies. Grants a shield.",
		 "req": {"type": "boss", "kind": "lord", "count": 2}},
	],
	"mage": [
		{"name": "Arcanist", "skill": "blink_nova", "skill_name": "Blink Nova",
		 "desc": "[Q] Blink toward your cursor, with a blast where you leave and where you arrive.",
		 "req": {"type": "boss", "kind": "lord", "count": 2}},
	],
	"rogue": [
		{"name": "Shade", "skill": "smoke_veil", "skill_name": "Smoke Veil",
		 "desc": "[Q] Drop a smoke cloud that slows and cuts enemies. Your next hit is a guaranteed critical.",
		 "req": {"type": "boss", "kind": "lord", "count": 2}},
	],
	"summoner": [
		{"name": "Soulbinder", "skill": "soul_detonation", "skill_name": "Soul Detonation",
		 "desc": "[Q] Detonate all your minions at once; each blast refunds some cooldown.",
		 "req": {"type": "boss", "kind": "lord", "count": 2}},
	],
}

## Số ván gần nhất giữ trong hồ sơ (thống kê cuối run).
const HISTORY_MAX: int = 20

static func new_class_entry() -> Dictionary:
	return {"runs": 0, "best_floor": 0, "kills": 0, "bosses": {}, "tier": 0, "branch": "a"}

static func new_profile() -> Dictionary:
	return {"runs": 0, "wins": 0, "best_floor": 0, "kills": 0, "secrets": 0, "bosses": {}, "classes": {}, "history": [], "council": 0}

## Gộp dữ liệu đã lưu vào cấu trúc mặc định (save cũ thiếu khóa vẫn đọc được).
static func merge_loaded(loaded) -> Dictionary:
	var p: Dictionary = new_profile()
	if not (loaded is Dictionary):
		return p
	for k in ["runs", "wins", "best_floor", "kills", "secrets", "council"]:
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
				e["branch"] = "b" if String(src.get("branch", "a")) == "b" else "a" # save cũ không có khoá này -> hướng A
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

## Số lần hạ Hội Đồng Bốn Boss.
static func record_council_clear(p: Dictionary) -> void:
	p["council"] = int(p.get("council", 0)) + 1

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

## Tiến hoá lên bậc kế, chọn hướng "a" hoặc "b" (hướng B chỉ khi class có EVOLUTION_ALT).
static func evolve(p: Dictionary, cid: String, branch: String = "a") -> bool:
	if not can_evolve(p, cid):
		return false
	var c: Dictionary = cls(p, cid)
	c["tier"] += 1
	c["branch"] = "b" if (branch == "b" and EVOLUTION_ALT.has(cid)) else "a"
	return true

## Hướng đang chọn của class ("a" nếu chưa tiến hoá hay save cũ).
static func branch_of(p: Dictionary, cid: String) -> String:
	return "b" if String(cls(p, cid).get("branch", "a")) == "b" else "a"

## Đổi hướng (chỉ khi đã tiến hoá). Trả true nếu đổi được.
static func set_branch(p: Dictionary, cid: String, branch: String) -> bool:
	if tier_of(p, cid) <= 0 or not (branch == "a" or (branch == "b" and EVOLUTION_ALT.has(cid))):
		return false
	cls(p, cid)["branch"] = branch
	return true

## Bậc tiến hoá `t` (1-based) của class theo hướng `branch`; {} nếu không có.
static func evolution_at(cid: String, t: int, branch: String) -> Dictionary:
	var src: Dictionary = EVOLUTION_ALT if branch == "b" else EVOLUTIONS
	var list: Array = src.get(cid, [])
	if t < 1 or t > list.size():
		return {}
	return list[t - 1]

## Bậc đã mở hiện tại theo hướng đang chọn ({} nếu chưa tiến hoá).
static func current_evolution(p: Dictionary, cid: String) -> Dictionary:
	var t: int = mini(tier_of(p, cid), EVOLUTIONS.get(cid, []).size())
	return evolution_at(cid, t, branch_of(p, cid))

## Kỹ năng đang có của class ("" nếu chưa tiến hoá) — lấy từ bậc cao nhất đã mở.
static func active_skill(p: Dictionary, cid: String) -> String:
	var cur: Dictionary = current_evolution(p, cid)
	return String(cur["skill"]) if not cur.is_empty() else ""

## Tên hiển thị của class theo bậc ("Ranger" → "Ranger+").
static func display_name(p: Dictionary, cid: String, base: String) -> String:
	var cur: Dictionary = current_evolution(p, cid)
	return String(cur["name"]) if not cur.is_empty() else base
