extends RefCounted
## Thông tin so sánh vũ khí cho UI (thẻ nhặt đồ, HUD). Thuần dữ liệu + hàm static; đọc bảng Global.weapons /
## Global.rarities, KHÔNG sửa gì. Số liệu là ước lượng "một mục tiêu, đứng yên" để so nhanh, không phải DPS thật
## (không tính buff, hiệu ứng độ hiếm đặc biệt, hay vùng đánh của Gậy/Lưỡi liềm).

const GOOD: Color = Color(0.45, 1.0, 0.5)
const BAD: Color = Color(1.0, 0.45, 0.4)
const SAME: Color = Color(0.85, 0.85, 0.9)

static func rarity_mult(rarity: String) -> float:
	return float(Global.rarities.get(rarity, Global.rarities["common"])["mult"])

## Sát thương một đòn (đã nhân độ hiếm). Cung tính ở mức căng đầy.
static func damage_per_hit(id: String, rarity: String) -> float:
	var w: Dictionary = Global.weapons.get(id, {})
	if w.is_empty():
		return 0.0
	var d: float = float(w["damage"]) * rarity_mult(rarity)
	if w.has("charge_time"):
		d *= float(w.get("charge_max", 1.0))
	return d * float(maxi(1, int(w.get("pellets", 1))))

## Số đòn mỗi giây. Cung: một chu kỳ = thời gian căng + hồi đòn.
static func attacks_per_sec(id: String) -> float:
	var w: Dictionary = Global.weapons.get(id, {})
	if w.is_empty():
		return 0.0
	var interval: float = float(w["cooldown"]) + float(w.get("charge_time", 0.0))
	return 1.0 / maxf(0.05, interval)

static func dps(id: String, rarity: String) -> float:
	return damage_per_hit(id, rarity) * attacks_per_sec(id)

## Các đặc tính cơ chế (ngắn gọn) của vũ khí.
static func traits(id: String, rarity: String) -> Array:
	var w: Dictionary = Global.weapons.get(id, {})
	var out: Array = []
	if w.is_empty():
		return out
	if w.has("charge_time"):
		out.append("Hold to draw, release to fire")
	if bool(w.get("beam", false)):
		out.append("Beam pierces every enemy")
	if w.has("blast_radius"):
		out.append("Explodes, %d px radius" % int(w["blast_radius"]))
	if bool(w.get("thrust", false)):
		out.append("Thrust: front enemy takes full damage")
	if bool(w.get("reap", false)):
		out.append("360 degree sweep")
		if rarity == "epic" or rarity == "legendary":
			out.append("Costs HP per swing, heals on hit")
	if int(w.get("pellets", 1)) > 1:
		out.append("%d pellets per shot" % int(w["pellets"]))
	if int(w.get("pierce_count", 0)) > 0:
		out.append("Pierces %d enemies" % int(w["pierce_count"]))
	if bool(w.get("is_melee", false)) and not bool(w.get("thrust", false)) and not bool(w.get("reap", false)):
		out.append("Melee, %d degree arc" % int(w.get("cleave_angle", 0)))
	return out

## Dòng so sánh {text, color} của vũ khí mới so với vũ khí đang cầm.
static func compare_rows(new_id: String, new_rarity: String, cur_id: String, cur_rarity: String) -> Array:
	var rows: Array = []
	rows.append(_row("DPS", dps(new_id, new_rarity), dps(cur_id, cur_rarity), cur_id != ""))
	rows.append(_row("Damage", damage_per_hit(new_id, new_rarity), damage_per_hit(cur_id, cur_rarity), cur_id != ""))
	rows.append(_row("Speed", attacks_per_sec(new_id), attacks_per_sec(cur_id), cur_id != "", "/s", 2))
	return rows

static func _row(label: String, nv: float, cv: float, has_cur: bool, suffix: String = "", decimals: int = 0) -> Dictionary:
	var fmt: String = "%." + str(decimals) + "f"
	var txt: String = "%s %s%s" % [label, fmt % nv, suffix]
	if not has_cur:
		return {"text": txt, "color": SAME}
	var diff: float = nv - cv
	var tol: float = 0.5 * pow(10.0, -float(decimals))
	if absf(diff) < tol:
		return {"text": txt + "  (=)", "color": SAME}
	var sign_s: String = "+" if diff > 0.0 else "-"
	return {"text": "%s  (%s%s)" % [txt, sign_s, fmt % absf(diff)], "color": GOOD if diff > 0.0 else BAD}
