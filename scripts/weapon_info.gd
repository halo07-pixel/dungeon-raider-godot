extends RefCounted
## Thông tin so sánh vũ khí cho UI (thẻ nhặt đồ, HUD). Thuần dữ liệu + hàm static; đọc bảng Global.weapons /
## Global.rarities, KHÔNG sửa gì. Số liệu là ước lượng "một mục tiêu, đứng yên" để so nhanh, không phải DPS thật
## (không tính buff, hiệu ứng độ hiếm đặc biệt, hay vùng đánh của Gậy/Lưỡi liềm).
const WeaponInstance = preload("res://scripts/weapon_instance.gd")

const GOOD: Color = Color(0.45, 1.0, 0.5)
const BAD: Color = Color(1.0, 0.45, 0.4)
const SAME: Color = Color(0.85, 0.85, 0.9)

static func rarity_mult(rarity: String) -> float:
	return float(Global.rarities.get(rarity, Global.rarities["common"])["mult"])

## Sát thương một đòn của 1 cây vũ khí (WeaponInstance; đã nhân độ hiếm, cấp nâng, dòng phụ). Cung tính ở mức căng đầy.
static func damage_per_hit(inst: Dictionary) -> float:
	if inst.is_empty():
		return 0.0
	var w: Dictionary = Global.weapons.get(String(inst["id"]), {})
	if w.is_empty():
		return 0.0
	var mods: Dictionary = WeaponInstance.affix_mods(inst)
	var d: float = float(w["damage"]) * rarity_mult(String(inst["rarity"])) * WeaponInstance.level_mult(int(inst.get("level", 0))) * float(mods["dmg"])
	if w.has("charge_time"):
		d *= float(w.get("charge_max", 1.0))
	return d * float(maxi(1, int(w.get("pellets", 1))))

## Số đòn mỗi giây (tính cả dòng phụ Heavy/Swift). Cung: một chu kỳ = thời gian căng + hồi đòn.
static func attacks_per_sec(inst: Dictionary) -> float:
	if inst.is_empty():
		return 0.0
	var w: Dictionary = Global.weapons.get(String(inst["id"]), {})
	if w.is_empty():
		return 0.0
	var cd_mult: float = float(WeaponInstance.affix_mods(inst)["cd"])
	var interval: float = (float(w["cooldown"]) + float(w.get("charge_time", 0.0))) * cd_mult
	return 1.0 / maxf(0.05, interval)

static func dps(inst: Dictionary) -> float:
	return damage_per_hit(inst) * attacks_per_sec(inst)

## Các đặc tính cơ chế (ngắn gọn) của vũ khí + đặc tính Mythic + dòng phụ.
static func traits(inst: Dictionary) -> Array:
	var out: Array = []
	if inst.is_empty():
		return out
	var id: String = String(inst["id"])
	var rarity: String = String(inst["rarity"])
	var w: Dictionary = Global.weapons.get(id, {})
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
		if rarity == "epic" or rarity == "legendary" or rarity == "mythic":
			out.append("Costs HP per swing, heals on hit")
	if int(w.get("pellets", 1)) > 1:
		out.append("%d pellets per shot" % int(w["pellets"]))
	if int(w.get("pierce_count", 0)) > 0:
		out.append("Pierces %d enemies" % int(w["pierce_count"]))
	if bool(w.get("is_melee", false)) and not bool(w.get("thrust", false)) and not bool(w.get("reap", false)):
		out.append("Melee, %d degree arc" % int(w.get("cleave_angle", 0)))
	if rarity == "mythic":
		var mt: Dictionary = WeaponInstance.mythic_trait(id)
		if not mt.is_empty():
			out.append("MYTHIC %s: %s" % [mt["name"], mt["desc"]])
	if int(inst.get("level", 0)) >= WeaponInstance.MAX_LEVEL:
		out.append("Max level: Mastery perk unlocked")
	out.append_array(WeaponInstance.affix_lines(inst))
	return out

## Dòng so sánh {text, color} của vũ khí mới so với vũ khí đang cầm ({} = không có).
static func compare_rows(new_inst: Dictionary, cur_inst: Dictionary) -> Array:
	var rows: Array = []
	var has_cur: bool = not cur_inst.is_empty()
	rows.append(_row("DPS", dps(new_inst), dps(cur_inst), has_cur))
	rows.append(_row("Damage", damage_per_hit(new_inst), damage_per_hit(cur_inst), has_cur))
	rows.append(_row("Speed", attacks_per_sec(new_inst), attacks_per_sec(cur_inst), has_cur, "/s", 2))
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
