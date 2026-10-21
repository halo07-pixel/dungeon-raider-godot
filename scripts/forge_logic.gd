extends RefCounted
## Luật của Lò Rèn (Forge) — hàm static thuần dữ liệu để UI (scenes/forge.gd) và test dùng chung.
## Tiền tệ: Vàng (Global.coins) để nâng cấp / ghép; Phế Liệu (Global.scrap, chỉ trong ván) có được khi phân rã vũ khí
## và dùng để reroll dòng phụ / ghép lên Mythic.
const WeaponInstance = preload("res://scripts/weapon_instance.gd")

## Vàng nâng cấp: UPGRADE_BASE[độ hiếm] * (cấp hiện tại + 1).
const UPGRADE_BASE: Dictionary = {"common": 20, "rare": 30, "epic": 45, "legendary": 65, "mythic": 90}
## Phế liệu khi phân rã: SALVAGE_SCRAP[độ hiếm] + SALVAGE_PER_LEVEL * cấp.
const SALVAGE_SCRAP: Dictionary = {"common": 2, "rare": 5, "epic": 12, "legendary": 30, "mythic": 80}
const SALVAGE_PER_LEVEL: int = 2
## Phế liệu reroll dòng phụ (Common không có dòng phụ, Mythic bị khóa).
const REROLL_SCRAP: Dictionary = {"rare": 4, "epic": 8, "legendary": 16}
## Ghép 2 cây cùng loại + cùng độ hiếm lên bậc kế: vàng theo bậc đích; Legendary -> Mythic tốn thêm phế liệu.
const FUSE_GOLD: Dictionary = {"rare": 40, "epic": 80, "legendary": 140, "mythic": 250}
const FUSE_MYTHIC_SCRAP: int = 40

static func next_rarity(r: String) -> String:
	var i: int = Global.WEAPON_RARITY_ORDER.find(r)
	return "" if i < 0 or i + 1 >= Global.WEAPON_RARITY_ORDER.size() else String(Global.WEAPON_RARITY_ORDER[i + 1])

static func upgrade_cost(inst: Dictionary) -> int:
	if inst.is_empty() or int(inst["level"]) >= WeaponInstance.MAX_LEVEL:
		return -1
	return int(UPGRADE_BASE[inst["rarity"]]) * (int(inst["level"]) + 1)

static func salvage_value(inst: Dictionary) -> int:
	return int(SALVAGE_SCRAP[inst["rarity"]]) + SALVAGE_PER_LEVEL * int(inst["level"])

## Phế liệu reroll, hoặc -1 nếu cây này không reroll được (Common/Mythic).
static func reroll_cost(inst: Dictionary) -> int:
	return int(REROLL_SCRAP.get(inst.get("rarity", ""), -1))

## {"ok": bool, "gold": int, "scrap": int, "result_rarity": String, "why": String}
static func fuse_info(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = {"ok": false, "gold": 0, "scrap": 0, "result_rarity": "", "why": ""}
	if a.is_empty() or b.is_empty():
		out["why"] = "Needs two weapons"
		return out
	if a["id"] != b["id"] or a["rarity"] != b["rarity"]:
		out["why"] = "Needs the same weapon type and rarity"
		return out
	var nxt: String = next_rarity(String(a["rarity"]))
	if nxt == "":
		out["why"] = "Already the highest rarity"
		return out
	out["ok"] = true
	out["result_rarity"] = nxt
	out["gold"] = int(FUSE_GOLD[nxt])
	out["scrap"] = FUSE_MYTHIC_SCRAP if nxt == "mythic" else 0
	return out

static func can_afford(gold_cost: int, scrap_cost: int) -> bool:
	return Global.coins >= gold_cost and Global.scrap >= scrap_cost

## --- Thao tác lên Player (trả về true nếu thành công; tự trừ tiền) ---
static func upgrade(p: Node, slot: int) -> bool:
	var inst: Dictionary = p.weapon_slots[slot]
	var cost: int = upgrade_cost(inst)
	if cost < 0 or not can_afford(cost, 0):
		return false
	Global.coins -= cost
	var n: Dictionary = inst.duplicate(true)
	n["level"] = int(n["level"]) + 1
	p.set_slot(slot, n)
	return true

static func reroll(p: Node, slot: int) -> bool:
	var inst: Dictionary = p.weapon_slots[slot]
	var cost: int = reroll_cost(inst)
	if cost < 0 or not can_afford(0, cost):
		return false
	Global.scrap -= cost
	var n: Dictionary = inst.duplicate(true)
	n["affixes"] = WeaponInstance.roll_affixes(String(n["id"]), String(n["rarity"]))
	p.set_slot(slot, WeaponInstance.normalize(n))
	return true

static func salvage(p: Node, slot: int) -> bool:
	var inst: Dictionary = p.weapon_slots[slot]
	if inst.is_empty():
		return false
	var gain: int = salvage_value(inst)
	if not p.remove_slot(slot): # không cho phân rã cây vũ khí cuối cùng
		return false
	Global.scrap += gain
	return true

## Ghép 2 ô thành 1 (vào ô đang cầm, ô kia trống). Cấp = cấp cao hơn; dòng phụ random lại theo bậc mới.
static func fuse(p: Node) -> bool:
	var a: Dictionary = p.weapon_slots[0]
	var b: Dictionary = p.weapon_slots[1]
	var info: Dictionary = fuse_info(a, b)
	if not bool(info["ok"]) or not can_afford(int(info["gold"]), int(info["scrap"])):
		return false
	Global.coins -= int(info["gold"])
	Global.scrap -= int(info["scrap"])
	var res: Dictionary = WeaponInstance.roll(String(a["id"]), String(info["result_rarity"]), maxi(int(a["level"]), int(b["level"])))
	var keep: int = p.active_slot
	p.set_slot(keep, res)
	p.remove_slot(1 - keep)
	return true
