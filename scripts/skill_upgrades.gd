extends RefCounted
## Nâng cấp kỹ năng class TRONG RUN (chọn 1 trong 2 sau boss tầng 5 và 10; không mang sang ván sau).
## Thuần dữ liệu + hàm static, không phụ thuộc scene/Global. Mỗi nâng cấp là một bộ "mods" do
## ClassSkill đọc khi dùng kỹ năng:
##   *_add  : cộng dồn (cooldown_add giây, duration_add giây, volleys_add, bullets_add, stun_add giây,
##            dist_add px lướt, slow_add giây làm chậm, meteors_add số thiên thạch)
##   *_mult : nhân dồn (radius_mult, dmg_mult, attack_cd_mult)
## Thêm nâng cấp mới = thêm 1 dòng vào UPGRADES[skill_id]; id phải duy nhất toàn bộ.

const UPGRADES: Dictionary = {
	"overdrive": [
		{"id": "skup_od_long", "name": "Long Overdrive", "desc": "Overdrive lasts 2 seconds longer.", "mods": {"duration_add": 2.0}},
		{"id": "skup_od_fast", "name": "Overclock", "desc": "Overdrive attack speed is 25% higher.", "mods": {"attack_cd_mult": 0.8}},
		{"id": "skup_od_recharge", "name": "Quick Charge", "desc": "Overdrive cooldown -3 seconds.", "mods": {"cooldown_add": -3.0}},
	],
	"slam": [
		{"id": "skup_slam_wide", "name": "Wide Slam", "desc": "Slam radius +35%.", "mods": {"radius_mult": 1.35}},
		{"id": "skup_slam_heavy", "name": "Heavy Slam", "desc": "Slam damage +50%.", "mods": {"dmg_mult": 1.5}},
		{"id": "skup_slam_stun", "name": "Stunning Slam", "desc": "Slam stuns enemies for 1 second.", "mods": {"stun_add": 1.0}},
		{"id": "skup_slam_recharge", "name": "Quick Slam", "desc": "Slam cooldown -2 seconds.", "mods": {"cooldown_add": -2.0}},
	],
	"phase_step": [
		{"id": "skup_ps_far", "name": "Long Step", "desc": "Phase Step travels 50 px farther.", "mods": {"dist_add": 50.0}},
		{"id": "skup_ps_blast", "name": "Arcane Arrival", "desc": "Phase Step blast damage +50%.", "mods": {"dmg_mult": 1.5}},
		{"id": "skup_ps_recharge", "name": "Quick Step", "desc": "Phase Step cooldown -2 seconds.", "mods": {"cooldown_add": -2.0}},
		{"id": "skup_ps_chill", "name": "Frost Landing", "desc": "Phase Step slows enemies in the blast for 2 seconds.", "mods": {"slow_add": 2.0}},
	],
	"meteor_storm": [
		{"id": "skup_met_more", "name": "Extra Meteor", "desc": "Meteor Storm calls 1 more meteor.", "mods": {"meteors_add": 1}},
		{"id": "skup_met_wide", "name": "Wide Impact", "desc": "Meteor blast radius +30%.", "mods": {"radius_mult": 1.3}},
		{"id": "skup_met_heavy", "name": "Heavy Meteors", "desc": "Meteor damage +40%.", "mods": {"dmg_mult": 1.4}},
		{"id": "skup_met_recharge", "name": "Quick Storm", "desc": "Meteor Storm cooldown -2.5 seconds.", "mods": {"cooldown_add": -2.5}},
	],
	"shadow_dash": [
		{"id": "skup_sd_long", "name": "Long Dash", "desc": "Shadow Dash travels 60 px farther.", "mods": {"dist_add": 60.0}},
		{"id": "skup_sd_deadly", "name": "Deadly Dash", "desc": "Shadow Dash damage +50%.", "mods": {"dmg_mult": 1.5}},
		{"id": "skup_sd_recharge", "name": "Quick Dash", "desc": "Shadow Dash cooldown -2 seconds.", "mods": {"cooldown_add": -2.0}},
	],
	"shadow_rush": [
		{"id": "skup_sr_deadly", "name": "Deadly Rush", "desc": "Shadow Rush damage +40%.", "mods": {"dmg_mult": 1.4}},
		{"id": "skup_sr_frenzy", "name": "Frenzy", "desc": "The attack-speed bonus lasts 2 seconds longer.", "mods": {"duration_add": 2.0}},
		{"id": "skup_sr_recharge", "name": "Quick Rush", "desc": "Shadow Rush cooldown -2 seconds.", "mods": {"cooldown_add": -2.0}},
	],
	"barrage": [
		{"id": "skup_bar_volley", "name": "Extra Volley", "desc": "Barrage fires 1 more volley.", "mods": {"volleys_add": 1}},
		{"id": "skup_bar_dense", "name": "Dense Fan", "desc": "Each volley fires 4 more bullets.", "mods": {"bullets_add": 4}},
		{"id": "skup_bar_heavy", "name": "Heavy Rounds", "desc": "Barrage damage +40%.", "mods": {"dmg_mult": 1.4}},
		{"id": "skup_bar_recharge", "name": "Quick Reload", "desc": "Barrage cooldown -2 seconds.", "mods": {"cooldown_add": -2.0}},
	],
	"shockwave": [
		{"id": "skup_shock_wide", "name": "Wide Shockwave", "desc": "Shockwave radius +30%.", "mods": {"radius_mult": 1.3}},
		{"id": "skup_shock_heavy", "name": "Heavy Shockwave", "desc": "Shockwave damage +40%.", "mods": {"dmg_mult": 1.4}},
		{"id": "skup_shock_stun", "name": "Stunning Shockwave", "desc": "Shockwave stuns enemies for 1 second.", "mods": {"stun_add": 1.0}},
		{"id": "skup_shock_recharge", "name": "Quick Shockwave", "desc": "Shockwave cooldown -2.5 seconds.", "mods": {"cooldown_add": -2.5}},
	],
}

static func for_skill(skill_id: String) -> Array:
	return UPGRADES.get(skill_id, [])

## Thông tin 1 nâng cấp theo id ({} nếu không có), kèm khoá "skill" = kỹ năng sở hữu.
static func find(id: String) -> Dictionary:
	for sid in UPGRADES:
		for u in UPGRADES[sid]:
			if String(u["id"]) == id:
				var out: Dictionary = (u as Dictionary).duplicate()
				out["skill"] = sid
				return out
	return {}

static func has(id: String) -> bool:
	return not find(id).is_empty()

## Id các nâng cấp của kỹ năng mà `taken` chưa có.
static func available(skill_id: String, taken: Array) -> Array:
	var out: Array = []
	for u in for_skill(skill_id):
		if not taken.has(String(u["id"])):
			out.append(String(u["id"]))
	return out

static func count_taken(skill_id: String, taken: Array) -> int:
	var n: int = 0
	for u in for_skill(skill_id):
		if taken.has(String(u["id"])):
			n += 1
	return n

## Tổng các mod dạng cộng của kỹ năng trong số nâng cấp đã lấy.
static func mod_add(skill_id: String, taken: Array, key: String) -> float:
	var total: float = 0.0
	for u in for_skill(skill_id):
		if taken.has(String(u["id"])):
			total += float(u["mods"].get(key, 0.0))
	return total

## Tích các mod dạng nhân (mặc định 1.0).
static func mod_mult(skill_id: String, taken: Array, key: String) -> float:
	var total: float = 1.0
	for u in for_skill(skill_id):
		if taken.has(String(u["id"])):
			total *= float(u["mods"].get(key, 1.0))
	return total
