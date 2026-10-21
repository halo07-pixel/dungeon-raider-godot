extends Node
## Autoload "Global": hằng số vật lý, DỮ LIỆU CÂN BẰNG (vũ khí / quái), tín hiệu chung,
## và các hiệu ứng dùng chung (âm thanh tự tổng hợp, hạt, số sát thương bay, hitstop).
const WeaponInstance = preload("res://scripts/weapon_instance.gd")

signal message(text: String, color: Color)
signal player_died
signal portal_entered
signal boss_spawned(boss)
signal boss_hp_changed(hp: float, max_hp: float, phase: int, boss_name: String)
signal boss_defeated
## Hội Đồng Bốn Boss: HUD dựng 4 thanh máu; cổng mở sau tầng 15 dẫn vào đấu trường.
signal council_started(bosses: Array)
signal council_portal_entered
## Dungeon phát ngay khi bắt đầu dựng một tầng (mọi tầng, kể cả tầng Lord). MusicManager chọn nhạc theo biome.
signal floor_started(floor_num: int)
## Một đòn của Player vừa trúng quái/boss (cận chiến, đạn, nguồn phụ). Buff phản ứng khi trúng (Fortify...) nghe signal này.
signal player_hit_landed(target: Node, dmg: int, is_crit: bool)
## Player vừa nhận sát thương (HUD nghe để nháy viền đỏ khi đòn nặng).
signal player_damaged(amount: int, max_hp: int)
signal player_hurt_by(source: String, amount: int) # nguồn: "enemy:kind", "boss:kind", "hazard:...", "trap:...", "dot:burn" ...
## Player đổi vũ khí lấy từ ô đang cầm (nhặt bằng E khi đủ ô) -> Dungeon nghe để đặt vũ khí cũ xuống sàn.
signal weapon_drop_requested(inst: Dictionary, pos: Vector2)

const TILE: int = 32

# ---------------------------------------------------------------- Cài đặt (âm lượng / điều khiển / màn hình)
const BUS_SFX: String = "SFX"
## Các action cho phép đổi phím trong menu Settings (không gồm "shoot" - đang gắn
## cứng chuột trái, và "confirm"/"restart" - phím hệ thống, không cần đổi).
const REBINDABLE_ACTIONS: Array = ["move_up", "move_down", "move_left", "move_right", "dodge"]
var settings: Dictionary = {
	"master_volume": 1.0,
	"sfx_volume": 1.0,
	"fullscreen": false,
}

## Tạo bus "SFX" tách khỏi Master nếu chưa có (project không có AudioBusLayout.tres
## sẵn nên dựng bằng code, đồng bộ cách UI toàn dự án đang được dựng runtime).
func _setup_audio_buses() -> void:
	if AudioServer.get_bus_index(BUS_SFX) == -1:
		var idx: int = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, BUS_SFX)
		AudioServer.set_bus_send(idx, "Master")

func _apply_settings() -> void:
	set_master_volume(float(settings.get("master_volume", 1.0)), false)
	set_sfx_volume(float(settings.get("sfx_volume", 1.0)), false)
	set_fullscreen(bool(settings.get("fullscreen", false)), false)

func set_master_volume(v: float, p_save: bool = true) -> void:
	v = clampf(v, 0.0, 1.0)
	settings["master_volume"] = v
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(maxf(v, 0.0001)) if v > 0.0 else -80.0)
	if p_save: save_game()

func set_sfx_volume(v: float, p_save: bool = true) -> void:
	v = clampf(v, 0.0, 1.0)
	settings["sfx_volume"] = v
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUS_SFX), linear_to_db(maxf(v, 0.0001)) if v > 0.0 else -80.0)
	if p_save: save_game()

func set_fullscreen(on: bool, p_save: bool = true) -> void:
	settings["fullscreen"] = on
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	if p_save: save_game()

## Trả về tên phím hiện tại của 1 action (để Settings UI hiển thị), "..." nếu chưa gán.
func key_name_for_action(action: String) -> String:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return OS.get_keycode_string(ev.physical_keycode)
	return "..."

## Đổi phím cho 1 action: xoá hết phím cũ, gán phím mới duy nhất.
func rebind_action(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)
	settings["key_" + action] = int(keycode)
	save_game()

## Áp lại phím đã lưu (gọi sau _setup_input() để ghi đè phím mặc định).
func _apply_saved_keybinds() -> void:
	for action in REBINDABLE_ACTIONS:
		var key_key: String = "key_" + action
		if settings.has(key_key):
			InputMap.action_erase_events(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = int(settings[key_key]) as Key
			InputMap.action_add_event(action, ev)

# Bit collision layer (khớp [layer_names] trong project.godot)
const L_WORLD: int = 1
const L_PLAYER: int = 2
const L_ENEMY: int = 4
const L_PBULLET: int = 8
const L_EBULLET: int = 16
const L_PICKUP: int = 32
var rarities: Dictionary = {
	"common": {"name": "Common", "mult": 1.0, "lifesteal": 0.0, "color": Color(0.8, 0.8, 0.8), "weight": 50},
	"rare": {"name": "Rare", "mult": 1.25, "lifesteal": 0.0, "color": Color(0.2, 0.8, 0.3), "weight": 30},
	"epic": {"name": "Epic", "mult": 1.5, "lifesteal": 0.05, "color": Color(0.6, 0.2, 0.8), "weight": 15},
	"legendary": {"name": "Legendary", "mult": 2.0, "lifesteal": 0.10, "color": Color(1.0, 0.8, 0.1), "weight": 5},
	# Mythic: chỉ rơi từ tầng MYTHIC_MIN_FLOOR (weight 0 = không có trong bảng gốc), hoặc ghép 2 Legendary cùng loại ở Forge.
	"mythic": {"name": "Mythic", "mult": 2.2, "lifesteal": 0.15, "color": Color(1.0, 0.25, 0.35), "weight": 0}
}

var weapons: Dictionary = {
	"pistol": {"name": "Pistol", "damage": 10, "cooldown": 0.30, "speed": 640.0, "pellets": 1, "spread": 3.0, "pierce": false, "life": 1.1, "recoil": 45.0, "radius": 5.0, "color": Color(1.0, 0.9, 0.4), "sfx": "shoot", "is_melee": false},
	"smg": {"name": "SMG", "damage": 5, "cooldown": 0.085, "speed": 700.0, "pellets": 1, "spread": 9.0, "pierce": false, "life": 1.0, "recoil": 18.0, "radius": 4.0, "color": Color(1.0, 0.65, 0.25), "sfx": "shoot", "is_melee": false},
	"shotgun": {"name": "Shotgun", "damage": 7, "cooldown": 0.75, "speed": 560.0, "pellets": 6, "spread": 36.0, "pierce": false, "life": 0.45, "recoil": 150.0, "radius": 4.0, "color": Color(1.0, 0.5, 0.3), "sfx": "shotgun", "is_melee": false},
	# --- Vũ khí tầm xa có cơ chế riêng (xem Player._shoot/_tick_charge và Bullet) ---
	# Longbow: GIỮ chuột để căng dây, nhả để bắn. Càng căng lâu càng mạnh/nhanh/xuyên (charge_min..charge_max = hệ số sát thương).
	"bow": {"name": "Longbow", "damage": 22, "cooldown": 0.35, "speed": 760.0, "pellets": 1, "spread": 0.0, "pierce": false, "life": 1.0, "recoil": 30.0, "radius": 4.0, "color": Color(0.95, 0.85, 0.55), "sfx": "shoot", "is_melee": false, "charge_time": 0.75, "charge_min": 0.3, "charge_max": 2.4},
	# Railgun: bắn chậm, tia xuyên MỌI quái trên đường thẳng (beam = đạn xuyên vô hạn kèm vệt tia dài).
	"railgun": {"name": "Railgun", "damage": 55, "cooldown": 1.6, "speed": 1500.0, "pellets": 1, "spread": 0.0, "pierce": false, "life": 0.6, "recoil": 220.0, "radius": 6.0, "color": Color(0.4, 0.9, 1.0), "sfx": "laser", "is_melee": false, "beam": true},
	# Arcane Staff: quả cầu nổ diện rộng (blast_radius px) khi chạm quái/tường/hết tầm; sát thương nổ áp cho mọi quái trong vùng.
	"staff": {"name": "Arcane Staff", "damage": 22, "cooldown": 0.75, "speed": 430.0, "pellets": 1, "spread": 2.0, "pierce": false, "life": 1.1, "recoil": 40.0, "radius": 7.0, "color": Color(0.7, 0.45, 1.0), "sfx": "laser", "is_melee": false, "blast_radius": 64.0},
	# --- Đợt 2: cơ chế riêng (xem Player._shoot và Bullet) ---
	# Crossbow: nỏ nặng. Quái bị bắn ngay SÁT TƯỜNG (trong tầm ghim) bị ghim: choáng + sát thương cộng thêm.
	"crossbow": {"name": "Crossbow", "damage": 34, "cooldown": 0.85, "speed": 900.0, "pellets": 1, "spread": 0.0, "pierce": false, "life": 0.9, "recoil": 60.0, "radius": 5.0, "color": Color(0.85, 0.8, 0.65), "sfx": "shoot", "is_melee": false, "pin": true},
	# Flamethrower: phun lửa tầm ngắn liên tục, xuyên mọi quái, gây cháy.
	"flamethrower": {"name": "Flamethrower", "damage": 4, "cooldown": 0.07, "speed": 380.0, "pellets": 1, "spread": 12.0, "pierce": false, "life": 0.26, "recoil": 8.0, "radius": 6.0, "color": Color(1.0, 0.55, 0.15), "sfx": "", "is_melee": false, "flame": true},
	# Chakram: ném đĩa bay ra rồi quay về tay (chạm quái cả lượt đi lẫn lượt về). Chưa về thì chưa ném được đĩa mới.
	"chakram": {"name": "Chakram", "damage": 20, "cooldown": 0.6, "speed": 560.0, "pellets": 1, "spread": 0.0, "pierce": false, "life": 2.4, "recoil": 0.0, "radius": 9.0, "color": Color(0.8, 0.9, 1.0), "sfx": "dodge", "is_melee": false, "boomerang": true, "out_time": 0.55},
	"laser": {"name": "Laser Gun", "damage": 16, "cooldown": 0.50, "speed": 1100.0, "pellets": 1, "spread": 0.0, "pierce": false, "pierce_count": 2, "life": 0.9, "recoil": 60.0, "radius": 4.0, "color": Color(0.4, 1.0, 1.0), "sfx": "laser", "is_melee": false},

	"broadsword": {"name": "Longsword", "damage": 25, "cooldown": 0.45, "is_melee": true, "range": 55.0, "cleave_angle": 180.0, "knock": 280.0, "color": Color(0.9, 0.9, 0.9), "sfx": "dodge"},
	"daggers": {"name": "Daggers", "damage": 14, "cooldown": 0.22, "is_melee": true, "range": 40.0, "cleave_angle": 80.0, "knock": 120.0, "color": Color(0.6, 0.9, 0.6), "sfx": "dodge"},
	# Spear: đâm hẹp, tầm xa. Quái đứng TRƯỚC NHẤT trong đường đâm ăn đủ sát thương, quái phía sau ăn một phần.
	"spear": {"name": "Spear", "damage": 30, "cooldown": 0.55, "is_melee": true, "range": 95.0, "cleave_angle": 28.0, "knock": 200.0, "color": Color(0.8, 0.9, 1.0), "sfx": "dodge", "thrust": true},
	# Scythe: quét 360 độ, chậm. Bậc Epic/Legendary phải ĐỔI MÁU mỗi nhát vung, bù lại hút máu mạnh khi trúng quái.
	"scythe": {"name": "Scythe", "damage": 30, "cooldown": 0.8, "is_melee": true, "range": 68.0, "cleave_angle": 360.0, "knock": 160.0, "color": Color(0.75, 0.4, 0.9), "sfx": "slam", "reap": true},
	"hammer": {"name": "War Hammer", "damage": 40, "cooldown": 0.90, "is_melee": true, "range": 65.0, "cleave_angle": 160.0, "knock": 550.0, "color": Color(1.0, 0.5, 0.2), "sfx": "slam"}
}

## Số ô vũ khí Player có thể cầm cùng lúc (đổi bằng phím "swap_weapon").
const MAX_WEAPON_SLOTS: int = 2
## Độ hiếm vũ khí rơi từ rương/boss dịch dần lên theo tầng: mỗi tầng sau tầng 1 cộng thêm
## trọng số cho rare/epic/legendary (trừ từ common), dừng ở WEAPON_RARITY_MAX_FLOORS tầng.
const WEAPON_RARITY_FLOOR_BONUS: Dictionary = {"rare": 1.0, "epic": 1.0, "legendary": 0.5}
const WEAPON_RARITY_MAX_FLOORS: int = 12
const WEAPON_RARITY_ORDER: Array = ["common", "rare", "epic", "legendary", "mythic"]
## Mythic chỉ xuất hiện từ tầng này; mỗi tầng sau đó cộng MYTHIC_WEIGHT_PER_FLOOR trọng số (tối đa MYTHIC_WEIGHT_CAP).
const MYTHIC_MIN_FLOOR: int = 8
const MYTHIC_WEIGHT_PER_FLOOR: float = 0.5
const MYTHIC_WEIGHT_CAP: float = 3.0

## Bảo hiểm xui (pity) cho vũ khí rơi từ rương/boss: sau PITY_EPIC lần liên tiếp không ra Epic+ thì lần kế tiếp tối thiểu Epic;
## sau PITY_LEGENDARY lần không ra Legendary+ thì lần kế tối thiểu Legendary. Đếm theo ván (reset_run, lưu trong save).
const PITY_EPIC: int = 4
const PITY_LEGENDARY: int = 12
var weapon_pity: Dictionary = {"epic": 0, "legendary": 0}
## Phế Liệu (chỉ trong ván): nhận khi phân rã vũ khí ở Lò Rèn, dùng để reroll dòng phụ / ghép Mythic.
var scrap: int = 0

## Như roll_weapon_rarity nhưng áp dụng + cập nhật bộ đếm pity. Dùng cho drop thật trong ván.
func roll_weapon_rarity_pity(for_floor: int, min_rarity: String = "common") -> String:
	var floor_min: String = min_rarity
	if int(weapon_pity["legendary"]) >= PITY_LEGENDARY:
		floor_min = _higher_rarity(floor_min, "legendary")
	elif int(weapon_pity["epic"]) >= PITY_EPIC:
		floor_min = _higher_rarity(floor_min, "epic")
	var r: String = roll_weapon_rarity(for_floor, floor_min)
	var idx: int = WEAPON_RARITY_ORDER.find(r)
	weapon_pity["epic"] = 0 if idx >= WEAPON_RARITY_ORDER.find("epic") else int(weapon_pity["epic"]) + 1
	weapon_pity["legendary"] = 0 if idx >= WEAPON_RARITY_ORDER.find("legendary") else int(weapon_pity["legendary"]) + 1
	return r

func _higher_rarity(a: String, b: String) -> String:
	return a if WEAPON_RARITY_ORDER.find(a) >= WEAPON_RARITY_ORDER.find(b) else b

## Random độ hiếm vũ khí cho tầng `for_floor`. `min_rarity` nâng độ hiếm tối thiểu (vd boss thưởng từ "rare").
func roll_weapon_rarity(for_floor: int, min_rarity: String = "common") -> String:
	var steps: int = clampi(for_floor - 1 + SkillTree.early_rare_steps(upgrades, for_floor), 0, WEAPON_RARITY_MAX_FLOORS)
	var weights: Dictionary = {}
	for rid in WEAPON_RARITY_ORDER:
		weights[rid] = float(rarities[rid]["weight"])
	for rid in WEAPON_RARITY_FLOOR_BONUS:
		var bonus: float = float(WEAPON_RARITY_FLOOR_BONUS[rid]) * float(steps)
		weights[rid] += bonus
		weights["common"] = maxf(5.0, weights["common"] - bonus)
	if for_floor >= MYTHIC_MIN_FLOOR:
		weights["mythic"] = minf(MYTHIC_WEIGHT_CAP, MYTHIC_WEIGHT_PER_FLOOR * float(for_floor - MYTHIC_MIN_FLOOR + 1))
	var total: float = 0.0
	for rid in WEAPON_RARITY_ORDER:
		total += float(weights[rid])
	var pick: float = randf() * total
	var chosen: String = "common"
	for rid in WEAPON_RARITY_ORDER:
		pick -= float(weights[rid])
		if pick <= 0.0:
			chosen = rid
			break
	if WEAPON_RARITY_ORDER.find(chosen) < WEAPON_RARITY_ORDER.find(min_rarity):
		chosen = min_rarity
	return chosen

## Chọn ngẫu nhiên 1 vũ khí (mọi class đều dùng được), ưu tiên không trùng các id trong `exclude`.
func random_weapon_id(exclude: Array = []) -> String:
	var pool: Array = []
	for w_id in weapons:
		if not exclude.has(w_id):
			pool.append(w_id)
	if pool.is_empty():
		pool = weapons.keys()
	return String(pool.pick_random())

## Dòng chỉ số ngắn cho gợi ý nhặt đồ: "DMG 12 · 0.30s" (đã nhân hệ số độ hiếm).
func weapon_summary(w_id: String, rarity: String) -> String:
	var w: Dictionary = weapons.get(w_id, {})
	if w.is_empty():
		return ""
	var mult: float = float(rarities.get(rarity, rarities["common"])["mult"])
	var kind: String = "melee" if bool(w.get("is_melee", false)) else "ranged"
	return "%s · DMG %d · %.2fs" % [kind, int(float(w["damage"]) * mult), float(w["cooldown"])]

## Như weapon_summary nhưng cho 1 cây cụ thể (tính cả cấp nâng + dòng phụ Heavy/Swift/Brutal).
func weapon_instance_summary(inst: Dictionary) -> String:
	if inst.is_empty():
		return ""
	var w: Dictionary = weapons[inst["id"]]
	var mods: Dictionary = WeaponInstance.affix_mods(inst)
	var mult: float = float(rarities[inst["rarity"]]["mult"]) * WeaponInstance.level_mult(int(inst["level"])) * float(mods["dmg"])
	var kind: String = "melee" if bool(w.get("is_melee", false)) else "ranged"
	return "%s · DMG %d · %.2fs" % [kind, int(float(w["damage"]) * mult), float(w["cooldown"]) * float(mods["cd"])]

var classes: Dictionary = {
	"ranger": {"name": "Ranger", "max_hp": 100, "default_weapon": "pistol", "skill": "overdrive", "passive": {"name": "Marksman", "desc": "Ranged weapons deal +12% damage."}},
	"brawler": {"name": "Brawler", "max_hp": 200, "default_weapon": "broadsword", "skill": "slam", "passive": {"name": "Bulwark", "desc": "Melee weapons deal +12% damage and you take 8% less damage."}},
	# Cây kiếng: máu thấp, sát thương lớn, né + định vị bằng kỹ năng lướt
	"mage": {"name": "Mage", "max_hp": 80, "default_weapon": "staff", "skill": "gravity_well", "passive": {"name": "Arcane Mind", "desc": "Skills recharge 25% faster."}},
	# Sát thủ: lướt xuyên quái gây sát thương, dao găm nhanh
	"rogue": {"name": "Rogue", "max_hp": 90, "default_weapon": "daggers", "skill": "shadow_dash", "passive": {"name": "Assassin", "desc": "+15% critical chance."}}
}
var current_class: String = "brawler"

var enemies: Dictionary = {
	"slime": {"hp": 30, "speed": 95.0, "touch": 10, "touch_cd": 0.8, "touch_knock": 260.0, "radius": 13.0, "coins": 1, "weight": 1.0, "color": Color(0.35, 0.85, 0.35)},
	"archer": {"hp": 22, "speed": 85.0, "touch": 0, "touch_cd": 1.0, "touch_knock": 200.0, "radius": 12.0, "coins": 2, "weight": 1.0, "color": Color(0.4, 0.6, 1.0), "shoot_cd": 1.5, "bullet_damage": 8, "bullet_speed": 280.0, "keep_away": 170.0, "range": 380.0, "shooter": true, "kiter": true},
	"brute": {"hp": 120, "speed": 62.0, "touch": 20, "touch_cd": 1.0, "touch_knock": 430.0, "radius": 20.0, "coins": 3, "weight": 2.5, "color": Color(0.8, 0.35, 0.25)},

	# --- BIOME 2 (Đầm Lầy) — bộ quái RIÊNG, không lặp với biome khác. Chủ đề Độc & Tiêu Hao:
	# phối hợp giữ chân (Masked Orc) + dồn độc (Shaman tầm xa + Chort cận chiến) ---
	"shaman": {"hp": 20, "speed": 80.0, "touch": 0, "touch_cd": 1.0, "touch_knock": 180.0, "radius": 12.0, "coins": 2, "weight": 1.0, "color": Color(0.55, 0.85, 0.35), "shoot_cd": 1.8, "bullet_damage": 4, "bullet_speed": 260.0, "keep_away": 170.0, "range": 380.0, "bullet_effect": "poison", "shooter": true, "kiter": true},
	"chort": {"hp": 18, "speed": 128.0, "touch": 6, "touch_cd": 0.5, "touch_knock": 150.0, "radius": 11.0, "coins": 2, "weight": 0.9, "color": Color(0.85, 0.25, 0.2)},
	"masked_orc": {"hp": 140, "speed": 58.0, "touch": 16, "touch_cd": 1.1, "touch_knock": 350.0, "radius": 20.0, "coins": 3, "weight": 2.6, "color": Color(0.5, 0.65, 0.4)},

	# --- BIOME 3 (Băng Giá) — bộ quái RIÊNG. Chủ đề Mất Kiểm Soát: không có vai tầm xa
	# (hết quái CC0 phù hợp) nhưng bù lại dày CC — slide + slow — khớp với Ô Băng ---
	"frost_zombie": {"hp": 35, "speed": 90.0, "touch": 8, "touch_cd": 0.9, "touch_knock": 220.0, "radius": 13.0, "coins": 2, "weight": 1.0, "color": Color(0.55, 0.8, 0.95)},
	"frost_big_zombie": {"hp": 150, "speed": 50.0, "touch": 22, "touch_cd": 1.2, "touch_knock": 400.0, "radius": 21.0, "coins": 3, "weight": 2.8, "color": Color(0.6, 0.85, 1.0), "slam_cd": 2.2, "slam_radius": 70.0},
	"frost_tiny": {"hp": 12, "speed": 150.0, "touch": 14, "touch_cd": 999.0, "touch_knock": 260.0, "radius": 9.0, "coins": 1, "weight": 0.6, "color": Color(0.75, 0.92, 1.0), "suicide": true},

	# --- BIOME 4 (Địa Ngục, tầng 11+) — bộ quái RIÊNG, mỗi loại một vai và tương tác với nhau:
	# Imp bắn cầu lửa rồi lùi · Ogre lao thẳng để lại vệt lửa · Acolyte cấp khiên cho đồng đội
	# (phải hạ trước) · Cinder tự nổ, chết để lại vũng lửa. Kỹ năng ở scripts/hell_skills.gd.
	"hell_imp": {"hp": 26, "speed": 100.0, "touch": 0, "touch_cd": 1.0, "touch_knock": 200.0, "radius": 12.0, "coins": 3, "weight": 1.0, "color": Color(1.0, 0.5, 0.15), "shoot_cd": 1.6, "bullet_damage": 9, "bullet_speed": 300.0, "keep_away": 190.0, "range": 360.0, "bullet_effect": "burn", "shoot_sfx": "imp_fire", "shooter": true, "kiter": true},
	"hell_ogre": {"hp": 170, "speed": 55.0, "touch": 24, "touch_cd": 1.1, "touch_knock": 450.0, "radius": 22.0, "coins": 4, "weight": 3.0, "color": Color(0.8, 0.3, 0.75)},
	"hell_acolyte": {"hp": 40, "speed": 70.0, "touch": 0, "touch_cd": 1.0, "touch_knock": 150.0, "radius": 13.0, "coins": 4, "weight": 1.2, "color": Color(0.85, 0.4, 0.9), "keep_away": 170.0, "range": 260.0, "kiter": true},
	"cinder_tiny": {"hp": 14, "speed": 140.0, "touch": 12, "touch_cd": 999.0, "touch_knock": 240.0, "radius": 9.0, "coins": 1, "weight": 0.6, "color": Color(1.0, 0.7, 0.2), "suicide": true},

	# --- Mimic (phòng sự kiện Rương Bẫy): không nằm trong bảng spawn thường, chỉ sinh từ rương bẫy.
	"mimic": {"hp": 90, "speed": 115.0, "touch": 22, "touch_cd": 0.7, "touch_knock": 380.0, "radius": 15.0, "coins": 8, "weight": 1.6, "color": Color(0.85, 0.6, 0.2)},
}
# ==============================================================================

var floor_num: int = 1
## true khi đang ở đấu trường Hội Đồng Bốn Boss (tầng 15 giữ nguyên, thoát qua cổng xuống tầng 16).
var in_council: bool = false

## --- Chế độ Heat (scripts/heat.gd) ---
## heat_selected: lựa chọn ở menu chọn class (id -> true), lưu trong save. run_heat: bản CHỐT cho ván đang chơi
## (lấy lúc reset_run, đi theo saved_run) nên đổi menu giữa chừng không ảnh hưởng ván đang dở.
var heat_selected: Dictionary = {}
var run_heat: Array = []

func heat_on(id: String) -> bool:
	return run_heat.has(id)

func heat_points() -> int:
	return HeatScript.total(run_heat)

## Ngọc Tím sau thưởng Heat của ván hiện tại.
func heat_gems(base: int) -> int:
	return HeatScript.gems(base, run_heat)

func selected_heat_ids() -> Array:
	return HeatScript.sanitize(heat_selected.keys())
var coins: int = 0
var player = null
var camera = null
var world: Node2D = null

## Hệ số khó THÊM áp dụng cho tầng > 10 (Chế Độ Vô Hạn, sau khi hạ Dungeon Lord tầng 10):
## nhân thêm vào công thức scale máu/giáp vốn có của boss.gd/enemy.gd, khiến độ khó tăng
## NHANH HƠN hẳn so với tốc độ tăng đều 1-10 — đúng như phần thưởng/thử thách của Vô Hạn.
## Tầng 11-15 là Chương Địa Ngục (độ khó do bộ quái + tầng thử thách quyết định, không nhân thêm); Vô Hạn bắt đầu tăng sau tầng này.
const ENDLESS_START_FLOOR: int = 15
const ENDLESS_RATE: float = 0.12

func endless_difficulty_mult(for_floor_num: int) -> float:
	if for_floor_num <= ENDLESS_START_FLOOR:
		return 1.0
	return 1.0 + ENDLESS_RATE * float(for_floor_num - ENDLESS_START_FLOOR)

## Hệ số nhân SÁT THƯƠNG quái/boss gây cho Player theo tầng (trước đây chỉ HP quái
## scale theo tầng qua floor_scale trong enemy.gd, sát thương gây ra vẫn là số cứng
## -> quái các tầng sau "trâu" nhưng không "đau" hơn). +7%/tầng, trần +80% (tầng ~12+)
## để tránh one-shot vô lý ở Vô Hạn. Áp dụng tập trung tại player.gd::take_damage().
## HP quái/boss nhân theo tầng ĐÚNG 1 LẦN (trước đây dungeon.gd truyền 1 hệ số rồi enemy.gd/boss.gd
## nhân thêm 1 hệ số nữa -> tầng 10 trâu gấp 6.2 lần quái / 13.7 lần boss). Chọn 0.3889/tầng
## để tầng 10 = 1 + 0.3889*9 = x4.5 so với tầng 1 (theo yêu cầu người chơi).
const HP_SCALE_PER_FLOOR: float = 5 / 9.0
## Giáp quái/boss giảm sát thương theo PHẦN TRĂM: giảm = giáp / (giáp + ARMOR_K). Trước đây giáp
## trừ thẳng vào từng phát nên đạn nhỏ (Pistol 10, SMG 5) bị phạt nặng hơn nhiều so với đòn to.
## K=30: giáp 10 (quái tầng 10) giảm 25%, giáp 19 (Dungeon Lord) giảm ~39%, mọi vũ khí như nhau.
const ARMOR_K: float = 30.0
const MELEE_LIFESTEAL_MULT: float = 0.5
func hp_scale_for_floor(for_floor_num: int) -> float:
	return 1.0 + HP_SCALE_PER_FLOOR * float(maxi(0, for_floor_num - 1))
func armor_reduction(armor: float) -> float:
	var a: float = maxf(0.0, armor)
	return a / (a + ARMOR_K)

func armored_damage(amount: int, armor: float) -> int:
	return maxi(1, roundi(float(amount) * (1.0 - armor_reduction(armor))))
const ENEMY_DMG_PER_FLOOR: float = 0.1
const ENEMY_DMG_MULT_CAP: float = 2.5
func enemy_dmg_mult_for_floor(for_floor_num: int) -> float:
	var m: float = minf(ENEMY_DMG_MULT_CAP, 1.0 + ENEMY_DMG_PER_FLOOR * float(maxi(0, for_floor_num - 1)))
	if heat_on("glass"):
		m *= HeatScript.PLAYER_DAMAGE_MULT # Glass Cannon: nhận thêm sát thương, áp ở điểm chung duy nhất
	return m

var _sfx: Dictionary = {}
var _dot_tex: ImageTexture
var _hitstop_active: bool = false

## Cache dùng chung cho toàn bộ ảnh nạp từ res://assets — nhiều script (enemy,
## player, boss, pickup, dungeon, menu...) từng tự viết lại 3 dòng Image.load() +
## ImageTexture.create_from_image() giống hệt nhau, vừa trùng lặp code vừa tốn
## I/O đĩa + cấp phát lại mỗi lần gọi. Gom về 1 chỗ, load 1 lần/path rồi tái sử dụng.
var _tex_cache: Dictionary = {}

## Ưu tiên load() (bản đã import — BẮT BUỘC để chạy được trong game đã xuất, vì file PNG gốc
## không được đóng gói). Chỉ khi chưa có bản import (headless / chưa mở editor) mới đọc file thô.
func load_tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		var img := Image.new()
		if img.load(path) == OK:
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		push_error("Không tải được ảnh: " + path)
	_tex_cache[path] = tex
	return tex

## Pixel font "Press Start 2P" dùng chung cho Main Menu + cửa hàng Gacha — nạp 1
## lần từ byte (giống cách nạp ảnh ở trên) để không phụ thuộc file .import khi
## chạy headless, rồi tái sử dụng thay vì mỗi màn hình tự đọc file riêng.
const PIXEL_FONT_PATH: String = "res://assets/fonts/PressStart2P-Regular.ttf"
var _pixel_font: FontFile

func pixel_font() -> FontFile:
	if _pixel_font == null:
		var imported: FontFile = null
		if ResourceLoader.exists(PIXEL_FONT_PATH):
			imported = load(PIXEL_FONT_PATH) as FontFile # bản đã import — dùng được khi xuất game
		if imported != null:
			_pixel_font = imported
		else:
			_pixel_font = FontFile.new()
			var bytes := FileAccess.get_file_as_bytes(PIXEL_FONT_PATH)
			if bytes.is_empty():
				push_error("Không tải được pixel font: " + PIXEL_FONT_PATH)
			else:
				_pixel_font.data = bytes
	return _pixel_font


func _ready() -> void:
	_setup_audio_buses()
	load_game()
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	_setup_input()
	_apply_saved_keybinds()
	_apply_settings()
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_dot_tex = ImageTexture.create_from_image(img)
	_sfx = {
		"shoot": _tone(700.0, 0.07, 0.20, -350.0),
		"shotgun": _tone(180.0, 0.14, 0.28, -100.0, true),
		"laser": _tone(1200.0, 0.12, 0.20, -900.0),
		"hit": _tone(300.0, 0.05, 0.22, -150.0, true),
		"kill": _tone(220.0, 0.18, 0.28, -180.0, true),
		"hurt": _tone(140.0, 0.20, 0.32, -80.0),
		"dodge": _tone(400.0, 0.12, 0.18, 500.0),
		"pickup": _tone(660.0, 0.12, 0.22, 500.0),
		"door": _tone(120.0, 0.25, 0.28, 60.0),
		"enemy_shoot": _tone(420.0, 0.08, 0.16, -200.0),
		"boss_charge": _tone(90.0, 0.35, 0.32, 250.0),
		"slam": _tone(70.0, 0.40, 0.40, -40.0, true),
		"roar": _tone(80.0, 0.70, 0.36, 60.0, true),
		# Âm nhiều lớp cho Barrage / Shockwave / Altar / Mimic (xem _mix)
		"barrage_cast": _mix(0.22, [
			{"freq": 300.0, "slide": 900.0, "vol": 0.18, "dur": 0.20, "wave": "sine"},
			{"freq": 0.0, "vol": 0.14, "dur": 0.10, "wave": "noise", "lp": 0.35}]),
		"barrage_volley": _mix(0.20, [
			{"freq": 0.0, "vol": 0.34, "dur": 0.16, "wave": "noise", "lp": 0.55, "decay": 2.2},
			{"freq": 1100.0, "slide": -800.0, "vol": 0.16, "dur": 0.14, "wave": "saw"},
			{"freq": 150.0, "slide": -70.0, "vol": 0.22, "dur": 0.12, "wave": "square"}]),
		# Mage / Rogue: lướt, thiên thạch báo hiệu + rơi
		"phase_step": _mix(0.35, [
			{"freq": 1500.0, "slide": -1100.0, "vol": 0.22, "dur": 0.18, "wave": "sine", "decay": 1.6},
			{"freq": 0.0, "vol": 0.16, "dur": 0.14, "wave": "noise", "lp": 0.6, "decay": 2.0},
			{"freq": 520.0, "slide": 700.0, "vol": 0.18, "dur": 0.22, "wave": "sine", "delay": 0.08, "decay": 1.8}]),
		"shadow_dash": _mix(0.28, [
			{"freq": 0.0, "vol": 0.34, "dur": 0.22, "wave": "noise", "lp": 0.8, "decay": 2.4},
			{"freq": 900.0, "slide": -600.0, "vol": 0.14, "dur": 0.16, "wave": "saw", "decay": 2.0}]),
		"meteor_warn": _mix(0.7, [
			{"freq": 220.0, "slide": 380.0, "vol": 0.40, "dur": 0.60, "wave": "sine", "swell": 1.0},
			{"freq": 0.0, "vol": 0.22, "dur": 0.55, "wave": "noise", "lp": 0.15, "swell": 1.0}]),
		"meteor_impact": _mix(0.7, [
			{"freq": 120.0, "slide": -80.0, "vol": 0.40, "dur": 0.50, "wave": "sine", "decay": 1.5},
			{"freq": 0.0, "vol": 0.38, "dur": 0.40, "wave": "noise", "lp": 0.18, "decay": 2.0},
			{"freq": 700.0, "slide": -600.0, "vol": 0.14, "dur": 0.20, "wave": "saw", "decay": 2.2}]),
		"shockwave": _mix(0.75, [
			{"freq": 95.0, "slide": -55.0, "vol": 0.42, "dur": 0.55, "wave": "sine", "decay": 1.4},
			{"freq": 0.0, "vol": 0.40, "dur": 0.40, "wave": "noise", "lp": 0.12, "decay": 1.8},
			{"freq": 180.0, "slide": 700.0, "vol": 0.16, "dur": 0.30, "wave": "saw", "delay": 0.04},
			{"freq": 0.0, "vol": 0.18, "dur": 0.40, "wave": "noise", "lp": 0.7, "delay": 0.18, "decay": 2.5}]),
		"altar_offer": _mix(1.1, [
			{"freq": 110.0, "slide": -20.0, "vol": 0.30, "dur": 0.70, "wave": "sine", "decay": 0.9},
			{"freq": 1300.0, "slide": -900.0, "vol": 0.16, "dur": 0.10, "wave": "sine", "delay": 0.04},
			{"freq": 1100.0, "slide": -800.0, "vol": 0.12, "dur": 0.10, "wave": "sine", "delay": 0.22},
			{"freq": 523.0, "vol": 0.15, "dur": 0.80, "wave": "sine", "delay": 0.20, "decay": 1.6},
			{"freq": 659.0, "vol": 0.12, "dur": 0.80, "wave": "sine", "delay": 0.28, "decay": 1.6},
			{"freq": 784.0, "vol": 0.12, "dur": 0.80, "wave": "sine", "delay": 0.36, "decay": 1.6}]),
		"altar_deny": _mix(0.30, [
			{"freq": 160.0, "slide": -50.0, "vol": 0.22, "dur": 0.14, "wave": "square"},
			{"freq": 120.0, "slide": -40.0, "vol": 0.22, "dur": 0.14, "wave": "square", "delay": 0.14}]),
		"mimic_reveal": _mix(0.95, [
			{"freq": 170.0, "slide": 260.0, "vol": 0.20, "dur": 0.24, "wave": "saw", "decay": 0.7},
			{"freq": 0.0, "vol": 0.14, "dur": 0.20, "wave": "noise", "lp": 0.3},
			{"freq": 85.0, "slide": -35.0, "vol": 0.34, "dur": 0.65, "wave": "saw", "delay": 0.20, "decay": 1.1},
			{"freq": 0.0, "vol": 0.26, "dur": 0.55, "wave": "noise", "lp": 0.2, "delay": 0.20, "decay": 1.3}]),
		"mimic_die": _mix(0.55, [
			{"freq": 320.0, "slide": -260.0, "vol": 0.30, "dur": 0.45, "wave": "saw", "decay": 1.2},
			{"freq": 0.0, "vol": 0.26, "dur": 0.30, "wave": "noise", "lp": 0.4},
			{"freq": 60.0, "vol": 0.28, "dur": 0.30, "wave": "sine", "delay": 0.20}]),
		# Biome Địa Ngục: Lava Tile, trạng thái Burn, Magma Eruption, Flame Trail
		"lava_burn": _mix(0.40, [
			{"freq": 0.0, "vol": 0.30, "dur": 0.34, "wave": "noise", "lp": 0.75, "decay": 1.7},
			{"freq": 140.0, "slide": -70.0, "vol": 0.20, "dur": 0.20, "wave": "saw", "decay": 1.3},
			{"freq": 0.0, "vol": 0.16, "dur": 0.20, "wave": "noise", "lp": 0.95, "delay": 0.12, "decay": 2.0}]),
		"burn_tick": _mix(0.14, [
			{"freq": 0.0, "vol": 0.22, "dur": 0.05, "wave": "noise", "lp": 0.95, "decay": 1.5},
			{"freq": 0.0, "vol": 0.16, "dur": 0.05, "wave": "noise", "lp": 0.8, "delay": 0.06, "decay": 1.5}]),
		"burn_douse": _mix(0.40, [
			{"freq": 0.0, "vol": 0.28, "dur": 0.34, "wave": "noise", "lp": 0.6, "decay": 0.9},
			{"freq": 520.0, "slide": -320.0, "vol": 0.16, "dur": 0.14, "wave": "sine"}]),
		"magma_warn": _mix(0.85, [
			{"freq": 55.0, "slide": 60.0, "vol": 0.38, "dur": 0.80, "wave": "saw", "swell": 0.9, "decay": 0.3},
			{"freq": 0.0, "vol": 0.26, "dur": 0.80, "wave": "noise", "lp": 0.10, "swell": 0.9, "decay": 0.3},
			{"freq": 240.0, "slide": 360.0, "vol": 0.10, "dur": 0.70, "wave": "sine", "swell": 0.9, "decay": 0.3}]),
		"magma_eruption": _mix(1.0, [
			{"freq": 85.0, "slide": -50.0, "vol": 0.46, "dur": 0.60, "wave": "sine", "decay": 1.3},
			{"freq": 0.0, "vol": 0.40, "dur": 0.70, "wave": "noise", "lp": 0.14, "decay": 1.6},
			{"freq": 320.0, "slide": -260.0, "vol": 0.20, "dur": 0.35, "wave": "saw", "decay": 1.4},
			{"freq": 0.0, "vol": 0.22, "dur": 0.55, "wave": "noise", "lp": 0.85, "delay": 0.08, "decay": 2.2},
			{"freq": 0.0, "vol": 0.14, "dur": 0.40, "wave": "noise", "lp": 0.9, "delay": 0.45, "decay": 1.8}]),
		"magma_pool": _mix(0.55, [
			{"freq": 0.0, "vol": 0.14, "dur": 0.50, "wave": "noise", "lp": 0.08, "decay": 0.6},
			{"freq": 130.0, "slide": 180.0, "vol": 0.16, "dur": 0.07, "wave": "sine", "delay": 0.04},
			{"freq": 100.0, "slide": 200.0, "vol": 0.14, "dur": 0.08, "wave": "sine", "delay": 0.21},
			{"freq": 150.0, "slide": 160.0, "vol": 0.12, "dur": 0.06, "wave": "sine", "delay": 0.36}]),
		"flame_trail": _mix(0.55, [
			{"freq": 0.0, "vol": 0.30, "dur": 0.50, "wave": "noise", "lp": 0.45, "swell": 0.3, "decay": 1.2},
			{"freq": 90.0, "slide": 40.0, "vol": 0.18, "dur": 0.45, "wave": "saw", "swell": 0.3, "decay": 1.2},
			{"freq": 0.0, "vol": 0.14, "dur": 0.25, "wave": "noise", "lp": 0.95, "delay": 0.20, "decay": 1.8}]),
		# Boss Biome Đá/Đầm Lầy/Băng (Nứt Đất, Đầm Độc Lan, Mặt Băng), Mimic và vàng
		"fissure_warn": _mix(0.80, [
			{"freq": 48.0, "slide": 40.0, "vol": 0.38, "dur": 0.75, "wave": "sine", "swell": 0.9, "decay": 0.3},
			{"freq": 0.0, "vol": 0.24, "dur": 0.75, "wave": "noise", "lp": 0.07, "swell": 0.9, "decay": 0.3}]),
		"fissure_burst": _mix(0.40, [
			{"freq": 0.0, "vol": 0.34, "dur": 0.32, "wave": "noise", "lp": 0.45, "decay": 2.0},
			{"freq": 130.0, "slide": -80.0, "vol": 0.30, "dur": 0.25, "wave": "sine", "decay": 1.4},
			{"freq": 0.0, "vol": 0.20, "dur": 0.08, "wave": "noise", "lp": 0.95, "delay": 0.01}]),
		"bog_warn": _mix(0.85, [
			{"freq": 0.0, "vol": 0.22, "dur": 0.80, "wave": "noise", "lp": 0.09, "swell": 0.9, "decay": 0.3},
			{"freq": 110.0, "slide": 160.0, "vol": 0.16, "dur": 0.07, "wave": "sine", "delay": 0.10},
			{"freq": 140.0, "slide": 180.0, "vol": 0.16, "dur": 0.07, "wave": "sine", "delay": 0.32},
			{"freq": 170.0, "slide": 200.0, "vol": 0.16, "dur": 0.07, "wave": "sine", "delay": 0.50},
			{"freq": 200.0, "slide": 240.0, "vol": 0.18, "dur": 0.08, "wave": "sine", "delay": 0.66}]),
		"bog_burst": _mix(0.50, [
			{"freq": 0.0, "vol": 0.30, "dur": 0.40, "wave": "noise", "lp": 0.55, "decay": 1.7},
			{"freq": 210.0, "slide": -120.0, "vol": 0.22, "dur": 0.25, "wave": "sine", "decay": 1.2}]),
		"ice_sheet_warn": _mix(0.90, [
			{"freq": 900.0, "slide": 900.0, "vol": 0.14, "dur": 0.85, "wave": "sine", "swell": 0.9, "decay": 0.3},
			{"freq": 1350.0, "slide": 1350.0, "vol": 0.10, "dur": 0.80, "wave": "sine", "swell": 0.9, "decay": 0.3},
			{"freq": 0.0, "vol": 0.12, "dur": 0.80, "wave": "noise", "lp": 0.95, "swell": 0.9, "decay": 0.3}]),
		"ice_sheet_freeze": _mix(0.70, [
			{"freq": 0.0, "vol": 0.30, "dur": 0.20, "wave": "noise", "lp": 0.95, "decay": 2.4},
			{"freq": 1800.0, "slide": -1400.0, "vol": 0.18, "dur": 0.30, "wave": "sine", "decay": 1.3},
			{"freq": 70.0, "slide": -20.0, "vol": 0.34, "dur": 0.40, "wave": "sine", "decay": 1.3}]),
		"council_rage": _mix(0.85, [
			{"freq": 70.0, "slide": -25.0, "vol": 0.34, "dur": 0.80, "wave": "saw", "swell": 0.2, "decay": 0.9},
			{"freq": 105.0, "slide": -35.0, "vol": 0.22, "dur": 0.70, "wave": "saw", "swell": 0.2, "decay": 0.9},
			{"freq": 0.0, "vol": 0.20, "dur": 0.40, "wave": "noise", "lp": 0.4, "decay": 1.6}]),
		"council_revive": _mix(0.80, [
			{"freq": 220.0, "slide": 380.0, "vol": 0.22, "dur": 0.70, "wave": "sine", "swell": 0.8, "decay": 0.6},
			{"freq": 330.0, "slide": 420.0, "vol": 0.14, "dur": 0.65, "wave": "sine", "swell": 0.8, "delay": 0.05, "decay": 0.6},
			{"freq": 0.0, "vol": 0.14, "dur": 0.70, "wave": "noise", "lp": 0.12, "swell": 0.8, "decay": 0.5}]),
		"imp_fire": _mix(0.30, [
			{"freq": 0.0, "vol": 0.24, "dur": 0.20, "wave": "noise", "lp": 0.5, "swell": 0.2, "decay": 1.5},
			{"freq": 430.0, "slide": -220.0, "vol": 0.18, "dur": 0.22, "wave": "saw", "decay": 1.4}]),
		"ogre_windup": _mix(0.70, [
			{"freq": 62.0, "slide": 70.0, "vol": 0.30, "dur": 0.65, "wave": "saw", "swell": 0.85, "decay": 0.4},
			{"freq": 0.0, "vol": 0.16, "dur": 0.65, "wave": "noise", "lp": 0.12, "swell": 0.85, "decay": 0.4}]),
		"ogre_charge": _mix(0.50, [
			{"freq": 0.0, "vol": 0.30, "dur": 0.45, "wave": "noise", "lp": 0.35, "swell": 0.15, "decay": 1.0},
			{"freq": 95.0, "slide": -45.0, "vol": 0.32, "dur": 0.40, "wave": "sine", "decay": 1.0}]),
		"affix_summon": _mix(0.45, [
			{"freq": 140.0, "slide": 260.0, "vol": 0.22, "dur": 0.40, "wave": "saw", "swell": 0.5, "decay": 1.1},
			{"freq": 0.0, "vol": 0.14, "dur": 0.40, "wave": "noise", "lp": 0.25, "swell": 0.6, "decay": 1.2}]),
		"affix_split": _mix(0.30, [
			{"freq": 0.0, "vol": 0.24, "dur": 0.12, "wave": "noise", "lp": 0.8, "decay": 2.2},
			{"freq": 300.0, "slide": 240.0, "vol": 0.16, "dur": 0.14, "wave": "square", "decay": 1.6},
			{"freq": 380.0, "slide": 300.0, "vol": 0.12, "dur": 0.14, "wave": "square", "delay": 0.09, "decay": 1.6}]),
		"affix_frenzy": _mix(0.25, [
			{"freq": 180.0, "slide": 420.0, "vol": 0.14, "dur": 0.20, "wave": "saw", "decay": 1.5},
			{"freq": 0.0, "vol": 0.08, "dur": 0.15, "wave": "noise", "lp": 0.6, "decay": 1.6}]),
		"affix_leech": _mix(0.25, [
			{"freq": 520.0, "slide": -260.0, "vol": 0.13, "dur": 0.20, "wave": "sine", "decay": 1.3},
			{"freq": 260.0, "slide": -100.0, "vol": 0.10, "dur": 0.20, "wave": "sine", "delay": 0.04, "decay": 1.3}]),
		"affix_blink_warn": _mix(0.40, [
			{"freq": 900.0, "slide": 700.0, "vol": 0.22, "dur": 0.35, "wave": "sine", "swell": 0.8, "decay": 0.6},
			{"freq": 0.0, "vol": 0.10, "dur": 0.35, "wave": "noise", "lp": 0.9, "swell": 0.8, "decay": 0.6}]),
		"affix_blink": _mix(0.25, [
			{"freq": 1200.0, "slide": -900.0, "vol": 0.16, "dur": 0.18, "wave": "sine", "decay": 1.6},
			{"freq": 0.0, "vol": 0.14, "dur": 0.10, "wave": "noise", "lp": 0.9, "decay": 2.0}]),
		"volatile_boom": _mix(0.45, [
			{"freq": 0.0, "vol": 0.34, "dur": 0.35, "wave": "noise", "lp": 0.45, "decay": 1.6},
			{"freq": 120.0, "slide": -70.0, "vol": 0.34, "dur": 0.35, "wave": "sine", "decay": 1.3}]),
		"ward_cast": _mix(0.45, [
			{"freq": 520.0, "slide": 300.0, "vol": 0.20, "dur": 0.35, "wave": "sine", "decay": 1.3},
			{"freq": 780.0, "slide": 200.0, "vol": 0.13, "dur": 0.30, "wave": "sine", "delay": 0.05, "decay": 1.4}]),
		"cinder_burst": _mix(0.40, [
			{"freq": 0.0, "vol": 0.30, "dur": 0.30, "wave": "noise", "lp": 0.6, "decay": 1.7},
			{"freq": 150.0, "slide": -90.0, "vol": 0.26, "dur": 0.25, "wave": "sine", "decay": 1.4},
			{"freq": 0.0, "vol": 0.16, "dur": 0.05, "wave": "noise", "lp": 0.95, "delay": 0.12},
			{"freq": 0.0, "vol": 0.14, "dur": 0.05, "wave": "noise", "lp": 0.95, "delay": 0.20}]),
		"trial_horn": _mix(0.90, [
			{"freq": 110.0, "slide": 6.0, "vol": 0.24, "dur": 0.80, "wave": "saw", "swell": 0.3, "decay": 0.7},
			{"freq": 165.0, "slide": 9.0, "vol": 0.16, "dur": 0.80, "wave": "saw", "swell": 0.3, "decay": 0.7},
			{"freq": 0.0, "vol": 0.08, "dur": 0.80, "wave": "noise", "lp": 0.08, "swell": 0.3, "decay": 0.7}]),
		"mimic_windup": _mix(0.65, [
			{"freq": 90.0, "slide": 120.0, "vol": 0.26, "dur": 0.60, "wave": "saw", "swell": 0.85, "decay": 0.4},
			{"freq": 0.0, "vol": 0.18, "dur": 0.60, "wave": "noise", "lp": 0.3, "swell": 0.85, "decay": 0.4}]),
		"mimic_lunge": _mix(0.38, [
			{"freq": 0.0, "vol": 0.30, "dur": 0.34, "wave": "noise", "lp": 0.5, "swell": 0.2, "decay": 1.2},
			{"freq": 240.0, "slide": -140.0, "vol": 0.20, "dur": 0.30, "wave": "saw", "decay": 1.2}]),
		"mimic_bite": _mix(0.28, [
			{"freq": 0.0, "vol": 0.30, "dur": 0.05, "wave": "noise", "lp": 0.9},
			{"freq": 190.0, "slide": -120.0, "vol": 0.28, "dur": 0.09, "wave": "square", "decay": 1.2},
			{"freq": 0.0, "vol": 0.30, "dur": 0.05, "wave": "noise", "lp": 0.9, "delay": 0.12},
			{"freq": 160.0, "slide": -100.0, "vol": 0.26, "dur": 0.10, "wave": "square", "delay": 0.12, "decay": 1.2}]),
		"coin": _mix(0.28, [
			{"freq": 1568.0, "vol": 0.18, "dur": 0.08, "wave": "sine", "decay": 0.8},
			{"freq": 2093.0, "vol": 0.18, "dur": 0.20, "wave": "sine", "delay": 0.06, "decay": 1.5}]),
		"mimic_steal": _mix(0.55, [
			{"freq": 0.0, "vol": 0.28, "dur": 0.05, "wave": "noise", "lp": 0.9},
			{"freq": 170.0, "slide": -100.0, "vol": 0.26, "dur": 0.10, "wave": "square", "decay": 1.2},
			{"freq": 1568.0, "vol": 0.16, "dur": 0.08, "wave": "sine", "delay": 0.14},
			{"freq": 2093.0, "vol": 0.16, "dur": 0.10, "wave": "sine", "delay": 0.20},
			{"freq": 1397.0, "vol": 0.14, "dur": 0.22, "wave": "sine", "delay": 0.27, "decay": 1.6}]),
		"mimic_spit": _mix(0.30, [
			{"freq": 0.0, "vol": 0.26, "dur": 0.22, "wave": "noise", "lp": 0.5, "decay": 1.3},
			{"freq": 620.0, "slide": -380.0, "vol": 0.20, "dur": 0.16, "wave": "sine"}]),
		"spit_pop": _mix(0.32, [
			{"freq": 0.0, "vol": 0.26, "dur": 0.20, "wave": "noise", "lp": 0.8, "decay": 2.4},
			{"freq": 300.0, "slide": -220.0, "vol": 0.26, "dur": 0.18, "wave": "sine", "decay": 1.4},
			{"freq": 1850.0, "vol": 0.12, "dur": 0.12, "wave": "sine", "delay": 0.03, "decay": 1.6}]),
		"mimic_rage": _mix(0.85, [
			{"freq": 140.0, "slide": -70.0, "vol": 0.30, "dur": 0.70, "wave": "saw", "decay": 1.0},
			{"freq": 0.0, "vol": 0.24, "dur": 0.60, "wave": "noise", "lp": 0.25, "decay": 1.2},
			{"freq": 66.0, "vol": 0.30, "dur": 0.50, "wave": "sine", "decay": 1.2}]),
	}


## Vàng đang bị Mimic cầm (đã trừ khỏi coins, trả lại khi Mimic chết/biến mất; Save & Quit cộng vào gold lưu).
var stolen_gold_held: int = 0

func reset_run() -> void:
	floor_num = 1
	in_council = false
	weapon_pity = {"epic": 0, "legendary": 0}
	scrap = 0
	run_heat = selected_heat_ids()
	coins = 0
	stolen_gold_held = 0
	buff_picks_left = 0
	skill_upgrades_taken.clear()
	skill_upgrade_pending = false
	Engine.time_scale = 1.0
	_hitstop_active = false
	reset_run_buffs()
	if PlayerProfiler:
		PlayerProfiler.reset()


# ---------------------------------------------------------------- Hệ thống Buff (chọn 1/3 sau khi dọn phòng)
signal buff_choice_requested(choices: Array)
## Dungeon phát khi một phòng thường/boss vừa dọn sạch (các buff như Thực Khách lắng nghe).
signal room_cleared

const BUFF_TIER_COLOR: Dictionary = {
	"skill": Color(1.0, 0.65, 0.2),
	"common": Color(0.85, 0.85, 0.85),
	"rare": Color(0.3, 0.75, 1.0),
	"epic": Color(0.75, 0.35, 0.95),
}
## Trần số lần stack cho từng buff — Thường/Hiếm stack nhiều lần (có trần chống phá cân
## bằng), Sử Thi độc nhất (max 1), đổi hẳn lối chơi nên không cộng dồn.
const BUFF_MAX_STACK: Dictionary = {
	# Dùng chung
	"buff_dmg": 5, "buff_haste": 5, "buff_reach": 5, "buff_crit": 5, "buff_bleed_proc": 3, "buff_slow_proc": 3,
	"buff_dodge_heal": 5, "buff_gourmand": 3, "buff_sense": 1,
	"buff_deathnova": 1, "buff_momentum": 1, "buff_sunder": 1, "buff_berserk": 1, "buff_sweep": 1,
	# Giáp ảo
	"buff_burn": 3, "buff_poison": 3, "buff_freeze": 2, "buff_arc": 1, "buff_chain": 1,
	"buff_shield_cap": 5, "buff_shield_regen": 4, "buff_shield_nova": 1, "buff_fortify": 1,
	# Cận chiến
	"buff_wave": 3, "buff_rollslash": 3, "buff_counter": 1, "buff_whirl": 1,
	# Tầm xa
	"buff_bounce": 2, "buff_split": 1, "buff_focus": 3, "buff_homing": 1, "buff_ring": 1, "buff_super": 1,
	# Buff riêng từng vũ khí (chỉ xuất hiện khi đang cầm đúng vũ khí đó)
	"buff_heavy_bolt": 3, "buff_nailgun": 1, "buff_fuel_tank": 3, "buff_inferno": 1, "buff_sharpened": 3, "buff_twin_disc": 1,
	"buff_perfect_draw": 1, "buff_quickdraw": 3, "buff_overcharge": 1, "buff_capacitor": 3,
	"buff_aftershock": 1, "buff_volatile": 2, "buff_impale": 1, "buff_reach_master": 3,
	"buff_reap": 1, "buff_blood_pact": 2,
	# Kỹ năng
	"buff_skill_power": 5, "buff_skill_haste": 5, "buff_skill_surge": 3, "buff_skill_overflow": 3,
	"buff_skill_echo": 1, "buff_skill_burst": 2, "buff_skill_overload": 1,
}
## "class": "any" (mọi vũ khí) | "melee" (chỉ khi đang cầm vũ khí cận chiến) | "ranged" (chỉ tầm xa).
## Buff bị lọc khỏi lượt chọn nếu không hợp loại vũ khí đang cầm (xem roll_buff_choices).
var buff_pool: Dictionary = {
	# ---- Dùng chung
	"buff_dmg": {"name": "Power", "desc": "+8% damage", "tier": "common", "class": "any"},
	"buff_haste": {"name": "Haste", "desc": "-10% cooldown", "tier": "common", "class": "any"},
	"buff_reach": {"name": "Range", "desc": "+15% range", "tier": "common", "class": "any"},
	"buff_gourmand": {"name": "Feast", "desc": "Room clear: heal 8% max HP", "tier": "common", "class": "any"},
	"buff_crit": {"name": "Critical", "desc": "+8% crit chance", "tier": "rare", "class": "any"},
	"buff_bleed_proc": {"name": "Bleed", "desc": "+15% bleed chance", "tier": "rare", "class": "any"},
	"buff_slow_proc": {"name": "Chill", "desc": "+20% slow chance", "tier": "rare", "class": "any"},
	"buff_dodge_heal": {"name": "Dodge Heal", "desc": "Dodge: heal 3 HP", "tier": "rare", "class": "any"},
	"buff_sense": {"name": "Map Sense", "desc": "Reveal all rooms", "tier": "rare", "class": "any"},
	"buff_deathnova": {"name": "Death Nova", "desc": "Enemies explode on death", "tier": "epic", "class": "any"},
	"buff_momentum": {"name": "Momentum", "desc": "Chain hits: up to +25% damage", "tier": "epic", "class": "any"},
	"buff_sunder": {"name": "Sunder", "desc": "Hits stack bonus damage taken", "tier": "epic", "class": "any"},
	"buff_berserk": {"name": "Berserk", "desc": "Low HP: up to +40% damage", "tier": "epic", "class": "any"},
	"buff_sweep": {"name": "Sweep", "desc": "Melee: +50% range, +40% arc. Ranged: shots pierce +1 enemy", "tier": "epic", "class": "any"},
	# ---- Nguyên tố
	"buff_burn": {"name": "Ignite", "desc": "20% burn chance (3s)", "tier": "rare", "class": "any"},
	"buff_poison": {"name": "Venom", "desc": "Hits stack poison (max 3)", "tier": "rare", "class": "any"},
	"buff_freeze": {"name": "Frost", "desc": "Hits stack chill; 3 stacks freeze", "tier": "rare", "class": "any"},
	"buff_arc": {"name": "Arc", "desc": "Every 2.5s: lightning hits 3 enemies", "tier": "epic", "class": "any"},
	"buff_chain": {"name": "Chain Lightning", "desc": "Crits chain to 3 enemies (60%)", "tier": "epic", "class": "any"},
	# ---- Giáp ảo
	"buff_shield_cap": {"name": "Shield Cap", "desc": "+10 max shield", "tier": "common", "class": "any"},
	"buff_shield_regen": {"name": "Shield Regen", "desc": "+25% regen, starts 0.4s sooner", "tier": "rare", "class": "any"},
	"buff_shield_nova": {"name": "Shield Nova", "desc": "On shield break: shockwave (6s CD)", "tier": "epic", "class": "any"},
	"buff_fortify": {"name": "Fortify", "desc": "Hits grant a little shield", "tier": "rare", "class": "any"},
	# ---- Cận chiến
	"buff_wave": {"name": "Sword Wave", "desc": "Slash fires a wave (35% damage)", "tier": "rare", "class": "melee"},
	"buff_rollslash": {"name": "Roll Slash", "desc": "Roll end: 120% damage burst", "tier": "rare", "class": "melee"},
	"buff_counter": {"name": "Counter", "desc": "After a hit: next slash x2 (3s)", "tier": "epic", "class": "melee"},
	"buff_whirl": {"name": "Whirlwind", "desc": "Every 4th slash is 360 degrees", "tier": "epic", "class": "melee"},
	# ---- Tầm xa
	"buff_bounce": {"name": "Ricochet", "desc": "+1 wall bounce", "tier": "rare", "class": "ranged"},
	"buff_split": {"name": "Split Shot", "desc": "Hits split into 2 shards (40%)", "tier": "rare", "class": "ranged"},
	"buff_focus": {"name": "Focus", "desc": "Standing still: +20% damage", "tier": "rare", "class": "ranged"},
	"buff_homing": {"name": "Homing", "desc": "Bullets track targets", "tier": "epic", "class": "ranged"},
	"buff_ring": {"name": "Bullet Ring", "desc": "Every 5th shot: ring of 8 (50%)", "tier": "epic", "class": "ranged"},
	"buff_super": {"name": "Mega Shot", "desc": "Every 6th shot: x3 damage, pierces 2 enemies", "tier": "epic", "class": "ranged"},
	# ---- Kỹ năng (Skill Build): hợp mọi class, tăng sức mạnh/tần suất kỹ năng Q
	"buff_skill_power": {"name": "Arcana", "desc": "+12% skill damage", "tier": "common", "class": "any"},
	"buff_skill_haste": {"name": "Quick Cast", "desc": "Skills recharge 10% faster", "tier": "common", "class": "any"},
	"buff_skill_surge": {"name": "Surge", "desc": "Casting a skill grants 20 shield", "tier": "rare", "class": "any"},
	"buff_skill_overflow": {"name": "Overflow", "desc": "Kills within 2s of a cast refund 1s of skill cooldown", "tier": "rare", "class": "any"},
	"buff_skill_echo": {"name": "Echo", "desc": "After a cast, your next attack deals x2 damage", "tier": "epic", "class": "any"},
	"buff_skill_burst": {"name": "Spellburst", "desc": "25% chance a cast costs no cooldown", "tier": "epic", "class": "any"},
	"buff_skill_overload": {"name": "Overload", "desc": "Skills +40% damage and +20% radius, but 20% slower recharge", "tier": "epic", "class": "any"},
	# ---- Riêng từng vũ khí: "weapon" = id vũ khí bắt buộc đang cầm (xem roll_buff_choices)
	"buff_heavy_bolt": {"name": "Heavy Bolt", "desc": "Crossbow: +20% damage and +40 px pin reach", "tier": "rare", "class": "ranged", "weapon": "crossbow"},
	"buff_nailgun": {"name": "Nailgun", "desc": "Crossbow: pinning an enemy halves the next reload", "tier": "epic", "class": "ranged", "weapon": "crossbow"},
	"buff_fuel_tank": {"name": "Fuel Tank", "desc": "Flamethrower: +15% range and +10% burn damage", "tier": "rare", "class": "ranged", "weapon": "flamethrower"},
	"buff_inferno": {"name": "Inferno", "desc": "Flamethrower: enemies you kill burst into flames", "tier": "epic", "class": "ranged", "weapon": "flamethrower"},
	"buff_sharpened": {"name": "Sharpened Edge", "desc": "Chakram: +15% damage", "tier": "rare", "class": "ranged", "weapon": "chakram"},
	"buff_twin_disc": {"name": "Twin Discs", "desc": "Chakram: throw 2 discs at once", "tier": "epic", "class": "ranged", "weapon": "chakram"},
	"buff_perfect_draw": {"name": "Perfect Draw", "desc": "Release right as the draw fills: x1.5 damage", "tier": "epic", "class": "ranged", "weapon": "bow"},
	"buff_quickdraw": {"name": "Quickdraw", "desc": "Draw the bow 15% faster", "tier": "rare", "class": "ranged", "weapon": "bow"},
	"buff_overcharge": {"name": "Overcharge", "desc": "Every 3rd Railgun shot: x2 damage, wider beam", "tier": "epic", "class": "ranged", "weapon": "railgun"},
	"buff_capacitor": {"name": "Capacitor", "desc": "Railgun kills cut 0.4s off the next shot's cooldown", "tier": "rare", "class": "ranged", "weapon": "railgun"},
	"buff_aftershock": {"name": "Aftershock", "desc": "Staff blasts leave a fire patch for 2s", "tier": "epic", "class": "ranged", "weapon": "staff"},
	"buff_volatile": {"name": "Volatile Orb", "desc": "Enemies killed by a Staff blast explode (50%)", "tier": "rare", "class": "ranged", "weapon": "staff"},
	"buff_impale": {"name": "Impale", "desc": "Spear tip stuns the front enemy; hitting it again within 2s: x1.5 damage", "tier": "epic", "class": "melee", "weapon": "spear"},
	"buff_reach_master": {"name": "Reach Master", "desc": "Spear: +10% reach and +10% damage to enemies behind the tip", "tier": "rare", "class": "melee", "weapon": "spear"},
	"buff_reap": {"name": "Reap", "desc": "Scythe kills make you swing 6% faster (stacks to 5, 3s)", "tier": "epic", "class": "melee", "weapon": "scythe"},
	"buff_blood_pact": {"name": "Blood Pact", "desc": "Scythe: 25% less HP cost per swing, heals 5% of damage dealt", "tier": "rare", "class": "melee", "weapon": "scythe"},
}
## Bảng buff có tương tác chéo (đối xứng): id -> các buff đối tác. buff_picker hiện nhãn ★ khi đã có đối tác.
const SYNERGY_MAP: Dictionary = {
	"buff_ring": ["buff_homing", "buff_bounce"],
	"buff_homing": ["buff_ring", "buff_split"],
	"buff_bounce": ["buff_ring", "buff_split"],
	"buff_split": ["buff_homing", "buff_bounce", "buff_super"],
	"buff_super": ["buff_split"],
	"buff_whirl": ["buff_wave"],
	"buff_wave": ["buff_whirl"],
	"buff_fortify": ["buff_shield_regen", "buff_shield_cap"],
	"buff_shield_regen": ["buff_fortify"],
	"buff_shield_cap": ["buff_fortify"],
	"buff_deathnova": ["buff_burn", "buff_poison", "buff_freeze"],
	"buff_burn": ["buff_deathnova"],
	"buff_poison": ["buff_deathnova"],
	"buff_freeze": ["buff_deathnova", "buff_shield_nova"],
	"buff_shield_nova": ["buff_freeze", "buff_arc"],
	"buff_arc": ["buff_shield_nova"],
	"buff_skill_power": ["buff_skill_overload", "buff_skill_echo"],
	"buff_skill_haste": ["buff_skill_burst", "buff_skill_overflow"],
	"buff_skill_echo": ["buff_skill_power"],
	"buff_skill_burst": ["buff_skill_haste"],
	"buff_skill_overflow": ["buff_skill_haste"],
	"buff_skill_overload": ["buff_skill_power"],
}

## Danh sách tên các buff đối tác mà Player ĐÃ sở hữu của buff `id` (rỗng = không có kết hợp).
func synergy_owned_partner_names(id: String) -> Array:
	var out: Array = []
	for partner in SYNERGY_MAP.get(id, []):
		if buff_stack(partner) > 0 and buff_pool.has(partner):
			out.append(String(buff_pool[partner]["name"]))
	return out

var run_buffs: Dictionary = {}

func reset_run_buffs() -> void:
	run_buffs.clear()

## "melee" / "ranged" theo vũ khí Player đang cầm (mặc định ranged nếu chưa có Player).
func player_weapon_class() -> String:
	if is_instance_valid(player) and player.get("weapon") != null and player.weapon.get("is_melee", false):
		return "melee"
	return "ranged"

func buff_stack(id: String) -> int:
	return int(run_buffs.get(id, 0))

## Trọng số được nới lại (trước: 60/32/8) sau khi đổi sang chỉ 1 lượt chọn buff/tầng
## (thay vì mỗi phòng) — ít lượt hơn nên cần tỉ lệ Rare/Epic cao hơn để vẫn đa dạng.
func _buff_tier_weight(tier: String) -> float:
	match tier:
		"common": return 50.0
		"rare": return 33.0
		"epic": return 17.0
	return 0.0

## Random n lựa chọn buff (không trùng nhau trong 1 lượt, loại buff đã đạt trần stack),
## random có trọng số theo tier (common > rare > epic).
func roll_buff_choices(n: int = 3, only_tier: String = "") -> Array:
	var candidates: Array = []
	var wclass: String = player_weapon_class()
	for id in buff_pool:
		var bclass: String = String(buff_pool[id].get("class", "any"))
		if bclass != "any" and bclass != wclass:
			continue
		var req_weapon: String = String(buff_pool[id].get("weapon", ""))
		if req_weapon != "" and (not is_instance_valid(player) or String(player.get("weapon_id")) != req_weapon):
			continue
		if only_tier != "" and String(buff_pool[id]["tier"]) != only_tier:
			continue
		if buff_stack(id) < int(BUFF_MAX_STACK.get(id, 1)):
			candidates.append(id)
	var choices: Array = []
	for i in n:
		if candidates.is_empty():
			break
		var total_w: float = 0.0
		for id in candidates:
			total_w += _buff_tier_weight(buff_pool[id]["tier"])
		var roll: float = randf() * total_w
		var picked: String = candidates[0]
		for id in candidates:
			roll -= _buff_tier_weight(buff_pool[id]["tier"])
			if roll <= 0.0:
				picked = id
				break
		choices.append(picked)
		candidates.erase(picked)
	return choices

## Gọi khi dọn xong phòng (thường/boss) để yêu cầu UI hiện 3 lựa chọn Pick-1.
const BUFF_PICKS_PER_BOSS: int = 1
var buff_picks_left: int = 0

## Tiêu đề màn chọn buff (phòng sự kiện đổi tiêu đề riêng, về mặc định khi chọn xong).
const BUFF_TITLE_DEFAULT: String = "CHOOSE A BUFF"
var buff_choice_title: String = BUFF_TITLE_DEFAULT

## Một lượt chọn buff với danh sách do bên gọi chọn sẵn (Altar, kho bí mật...). false nếu rỗng.
func request_buff_choice_of(choices: Array, title: String) -> bool:
	if choices.is_empty():
		return false
	buff_picks_left = 1
	buff_choice_title = title
	buff_choice_requested.emit(choices)
	return true

func request_buff_choice() -> void:
	buff_picks_left = BUFF_PICKS_PER_BOSS
	rerolls_left = SkillTree.rerolls_per_offer(upgrades)
	_offer_next_buff_pick()

## Đổi bài (nút Second Thoughts): chỉ cho lượt chọn buff thường, mỗi lượt mời một lần.
var rerolls_left: int = 0

func can_reroll() -> bool:
	return rerolls_left > 0 and buff_picks_left > 0 and buff_choice_title == BUFF_TITLE_DEFAULT

func try_reroll() -> bool:
	if not can_reroll():
		return false
	var choices: Array = roll_buff_choices(SkillTree.buff_choice_count(upgrades))
	if choices.is_empty():
		return false
	rerolls_left -= 1
	buff_choice_requested.emit(choices)
	return true

## Phát 3 lựa chọn cho lượt kế tiếp (nếu còn lượt). buff_picker gọi lại sau mỗi lần chọn.
## Hết lượt buff thường thì mới tới lượt nâng cấp kỹ năng (nếu đang chờ).
func _offer_next_buff_pick() -> void:
	if buff_picks_left <= 0:
		_offer_pending_skill_upgrade()
		return
	var choices: Array = roll_buff_choices(SkillTree.buff_choice_count(upgrades))
	if choices.is_empty():
		buff_picks_left = 0
		_offer_pending_skill_upgrade()
		return
	buff_choice_requested.emit(choices)

# ---------------------------------------------------------------- Nâng cấp kỹ năng class trong run
## Boss ở các tầng này mời chọn 1 nâng cấp kỹ năng (sau lượt chọn buff thường).
const SKILL_UPGRADE_FLOORS: Array = [5, 10]
const SKILL_UPGRADE_CHOICES: int = 2
## Id các nâng cấp đã lấy trong ván này (reset khi bắt đầu ván mới, lưu trong saved_run).
var skill_upgrades_taken: Array = []
var skill_upgrade_pending: bool = false

## Dungeon gọi khi hạ boss: đánh dấu có lượt nâng cấp nếu tầng này thuộc SKILL_UPGRADE_FLOORS.
func queue_skill_upgrade_for_floor(for_floor: int) -> void:
	if SKILL_UPGRADE_FLOORS.has(for_floor):
		skill_upgrade_pending = true

func current_skill_id() -> String:
	if is_instance_valid(player) and player.get("class_skill") != null and is_instance_valid(player.class_skill):
		return String(player.class_skill.skill_id)
	return class_skill_id()

func skill_upgrade_count(skill_id: String) -> int:
	return SkillUpgrades.count_taken(skill_id, skill_upgrades_taken)

## Chọn ngẫu nhiên tối đa n nâng cấp chưa lấy của kỹ năng hiện tại.
func roll_skill_upgrade_choices(n: int = SKILL_UPGRADE_CHOICES) -> Array:
	var pool: Array = SkillUpgrades.available(current_skill_id(), skill_upgrades_taken)
	pool.shuffle()
	return pool.slice(0, n)

func _offer_pending_skill_upgrade() -> void:
	if not skill_upgrade_pending:
		return
	skill_upgrade_pending = false
	var choices: Array = roll_skill_upgrade_choices()
	if choices.is_empty():
		return
	var sk_name: String = String(player.class_skill.skill_name) if is_instance_valid(player) and player.get("class_skill") != null and is_instance_valid(player.class_skill) else "SKILL"
	request_buff_choice_of(choices, "UPGRADE: %s" % sk_name.to_upper())

## Thông tin hiển thị cho 1 thẻ chọn: buff thường hoặc nâng cấp kỹ năng (tier "skill").
func buff_info(id: String) -> Dictionary:
	if buff_pool.has(id):
		return buff_pool[id]
	var up: Dictionary = SkillUpgrades.find(id)
	if not up.is_empty():
		return {"name": up["name"], "desc": up["desc"], "tier": "skill"}
	return {"name": id, "desc": "", "tier": "common"}

func consume_buff_pick() -> void:
	buff_picks_left = maxi(0, buff_picks_left - 1)
	if buff_picks_left <= 0:
		buff_choice_title = BUFF_TITLE_DEFAULT
	_offer_next_buff_pick()

## Điểm CHUNG cho hiệu ứng nguyên tố khi đòn của Player trúng mục tiêu (cận chiến + đạn đều gọi).
## target: quái/boss (duck-typing apply_element). dmg: sát thương đòn vừa gây (để tính DOT).
func on_player_hit(target: Node, dmg: int, is_crit: bool) -> void:
	if not is_instance_valid(target) or not target.has_method("apply_element"):
		return
	player_hit_landed.emit(target, dmg, is_crit)
	var burn: int = buff_stack("buff_burn")
	if burn > 0 and randf() < 0.2 * float(burn):
		target.apply_element("burn", maxi(2, int(float(dmg) * 0.12)), 0)
	var poison: int = buff_stack("buff_poison")
	if poison > 0:
		target.apply_element("poison", 2 + floor_num / 2, 3 + 2 * (poison - 1))
	var freeze: int = buff_stack("buff_freeze")
	if freeze > 0:
		target.apply_element("frost", 0, 3 if freeze < 2 else 2)
	if is_crit and buff_stack("buff_chain") > 0:
		chain_lightning(target, int(float(dmg) * 0.6), 3)

## Nguồn sát thương PHỤ (Lăn Chém / Sét Lan / Giáp Phản Chấn...): áp dụng cùng bộ hiệu ứng như một đòn
## đánh trúng thường — nguyên tố (Thiêu Đốt/Độc/Băng/Chớp Giật) và Phá Giáp.
func on_secondary_hit(target: Node, dmg: int, is_crit: bool = false) -> void:
	if not is_instance_valid(target):
		return
	on_player_hit(target, dmg, is_crit)
	if buff_stack("buff_sunder") > 0 and target.has_method("apply_sunder"):
		target.apply_sunder()

## Sét nảy từ `origin_target` sang tối đa n quái gần nhất (bán kính 200px). Gây sát thương trực tiếp
## (không gọi lại on_player_hit nên không đệ quy).
func chain_lightning(origin_target: Node, dmg: int, n: int) -> int:
	var origin: Vector2 = origin_target.global_position
	var cands: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != origin_target and is_instance_valid(e) and e.alive and e.global_position.distance_to(origin) <= 200.0:
			cands.append(e)
	cands.sort_custom(func(a, b): return a.global_position.distance_to(origin) < b.global_position.distance_to(origin))
	var hit: int = 0
	for e in cands:
		if hit >= n:
			break
		e.take_damage(maxi(1, dmg), origin, 0.0)
		burst(e.global_position, Color(1.0, 0.95, 0.3), 5, 120.0, 1.2)
		hit += 1
	return hit

## Áp dụng buff đã chọn: +1 stack. Chỉ "buff_shield_cap" cần xử lý NGAY (cộng giáp) —
## mọi buff khác đọc Global.buff_stack(id) trực tiếp tại điểm hook (player.gd/bullet.gd/
## enemy.gd/boss.gd) mỗi lần bắn/chém/nhận dmg, không cần cache lại giá trị ở đây.
func apply_buff(id: String) -> void:
	if SkillUpgrades.has(id):
		if not skill_upgrades_taken.has(id):
			skill_upgrades_taken.append(id)
		message.emit("Skill upgrade: " + String(SkillUpgrades.find(id)["name"]), BUFF_TIER_COLOR["skill"])
		return
	if not buff_pool.has(id):
		return
	run_buffs[id] = buff_stack(id) + 1
	if id == "buff_shield_cap" and is_instance_valid(player):
		player.refresh_max_shield()
		player.shield += 10.0 # phần giáp tăng thêm được tặng đầy ngay
	message.emit("Buff: " + buff_pool[id]["name"], BUFF_TIER_COLOR.get(buff_pool[id]["tier"], Color.WHITE))


var _coin_bonus_acc: float = 0.0

func add_coin() -> void:
	var gained: int = 1
	_coin_bonus_acc += SkillTree.coin_bonus(upgrades) # nút Deep Pockets: dồn dần, đủ 1 xu thì thưởng thêm
	if _coin_bonus_acc >= 0.9999:
		_coin_bonus_acc -= 1.0
		gained += 1
	coins += gained
	# Bổ sung dòng này để ghi chép vào sổ thống kê Game Over
	if get("run_stats") != null and run_stats.has("coins"):
		run_stats["coins"] += gained


# ---------------------------------------------------------------- Input map (tạo bằng code)
func _setup_input() -> void:
	_add_key("move_left", KEY_A)
	_add_key("move_left", KEY_LEFT)
	_add_key("move_right", KEY_D)
	_add_key("move_right", KEY_RIGHT)
	_add_key("move_up", KEY_W)
	_add_key("move_up", KEY_UP)
	_add_key("move_down", KEY_S)
	_add_key("move_down", KEY_DOWN)
	_add_key("dodge", KEY_SPACE)
	_add_key("skill", KEY_Q)
	_add_key("interact", KEY_E)
	_add_key("swap_weapon", KEY_TAB)
	if not InputMap.has_action("swap_weapon"):
		InputMap.add_action("swap_weapon")
	var swap_mb := InputEventMouseButton.new()
	swap_mb.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("swap_weapon", swap_mb)
	_add_key("confirm", KEY_ENTER)
	_add_key("confirm", KEY_KP_ENTER)
	_add_key("restart", KEY_R)
	if not InputMap.has_action("shoot"):
		InputMap.add_action("shoot")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("shoot", mb)


func _add_key(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)


# ---------------------------------------------------------------- Âm thanh tự tổng hợp (không cần file .wav)
func _tone(freq: float, dur: float, vol: float, slide: float = 0.0, noise: bool = false) -> AudioStreamWAV:
	var rate: int = 22050
	var n: int = int(float(rate) * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase: float = 0.0
	for i in n:
		var k: float = float(i) / float(n)
		phase += TAU * (freq + slide * k) / float(rate)
		var s: float = 0.0
		if noise:
			s = randf_range(-1.0, 1.0)
		else:
			s = 1.0 if sin(phase) > 0.0 else -1.0
		var v: int = int(clampf(s * (1.0 - k) * vol, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


## Trộn nhiều lớp âm thành một AudioStreamWAV. Mỗi lớp: freq, slide (Hz trượt hết lớp), vol, dur (s),
## wave ("sine"|"square"|"saw"|"noise"), delay (s, mặc định 0), decay (số mũ tắt dần, mặc định 1),
## lp (0..1, bộ lọc thông thấp cho noise; càng nhỏ càng trầm), swell (0..1, phần đầu lớp tăng dần từ 0 lên đủ to,
## dùng cho tiếng dâng lên). total = độ dài tổng của clip.
func _mix(total: float, layers: Array) -> AudioStreamWAV:
	var rate: int = 22050
	var n: int = int(float(rate) * total)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for L in layers:
		var start: int = int(float(rate) * float(L.get("delay", 0.0)))
		var len_s: int = mini(int(float(rate) * float(L["dur"])), n - start)
		if len_s <= 0:
			continue
		var wave: String = L.get("wave", "sine")
		var freq: float = float(L.get("freq", 0.0))
		var slide: float = float(L.get("slide", 0.0))
		var vol: float = float(L["vol"])
		var decay: float = float(L.get("decay", 1.0))
		var lp: float = float(L.get("lp", 1.0))
		var swell: float = float(L.get("swell", 0.0))
		var phase: float = 0.0
		var lp_state: float = 0.0
		for i in len_s:
			var k: float = float(i) / float(len_s)
			phase += TAU * (freq + slide * k) / float(rate)
			var v: float = 0.0
			match wave:
				"sine": v = sin(phase)
				"square": v = 1.0 if sin(phase) > 0.0 else -1.0
				"saw": v = fmod(phase / TAU, 1.0) * 2.0 - 1.0
				_:
					lp_state += lp * (randf_range(-1.0, 1.0) - lp_state)
					v = lp_state * (1.0 + (1.0 - lp) * 1.5)
			var env: float = pow(1.0 - k, decay) * minf(1.0, float(i) / 66.0) # attack ~3 ms chống lách tách
			if swell > 0.0:
				env = minf(1.0, k / swell) * pow(1.0 - k, decay)
			buf[start + i] += v * env * vol
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


func sfx(sfx_name: String, pitch: float = 1.0) -> void:
	if not _sfx.has(sfx_name):
		return
	var p := AudioStreamPlayer.new()
	p.stream = _sfx[sfx_name]
	p.pitch_scale = pitch
	p.volume_db = -6.0
	p.bus = BUS_SFX
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ---------------------------------------------------------------- Hiệu ứng hình ảnh
func burst(pos: Vector2, color: Color, amount: int = 10, speed: float = 160.0, size: float = 1.5) -> void:
	if world == null or not is_instance_valid(world):
		return
	var p := CPUParticles2D.new()
	p.texture = _dot_tex
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	p.color = color
	p.z_index = 50
	world.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)


func float_text(pos: Vector2, text: String, color: Color = Color.WHITE, font_size: int = 16) -> void:
	if world == null or not is_instance_valid(world):
		return
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.z_index = 100
	world.add_child(l)
	l.global_position = pos + Vector2(-10.0, -26.0)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position:y", l.global_position.y - 38.0, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


func shake(strength: float, time: float = 0.2) -> void:
	if camera != null and is_instance_valid(camera):
		camera.shake(strength, time)


## Khựng hình cực ngắn. Dùng Engine.time_scale + timer bỏ qua time_scale.
## (Đạn xuyên dùng danh sách "đã trúng" nên không bị lỗi lặp sát thương như bản Pygame.)
func hitstop(duration: float = 0.05) -> void:
	if _hitstop_active:
		return
	_hitstop_active = true
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop_active = false
# HỆ THỐNG LƯU TRỮ VÀ THỐNG KÊ (Lưu vĩnh viễn Ngọc Tím và Nâng cấp)
# ==============================================================================
var save_path: String = "user://dungeon_raider_save.dat"

var purple_gems: int = 0
## Hồ sơ vĩnh viễn (thống kê + tiến hoá class). Cấu trúc/logic nằm ở scripts/meta_progress.gd.
const MetaProgress = preload("res://scripts/meta_progress.gd")
const SkillUpgrades = preload("res://scripts/skill_upgrades.gd")
const HeatScript = preload("res://scripts/heat.gd")
const SkillTree = preload("res://scripts/skill_tree.gd")
var profile: Dictionary = MetaProgress.new_profile()
var upgrades: Dictionary = {
	"hp_boost": 0, "start_coin": 0, "mastery": 0, "revive": 0,
	"choice4": 0, "reroll": 0, "early_rare": 0, "coin_bonus": 0,
	"start_buff": 0, "q_cooldown": 0, "q_damage": 0, "soft_shield": 0
}

# Lưu toàn bộ trạng thái của một ván chơi đang dở dang
var saved_run: Dictionary = {}

var run_stats: Dictionary = {
	"floors": 1, "kills": 0, "coins": 0,
	"gacha_common": 0, "gacha_rare": 0, "gacha_epic": 0, "gacha_legendary": 0
}

func reset_run_stats() -> void:
	run_stats = {
		"floors": 1, "kills": 0, "coins": 0,
		"gacha_common": 0, "gacha_rare": 0, "gacha_epic": 0, "gacha_legendary": 0
	}

## AI Tầng 2 (Q-Learning, xem scripts/q_agent.gd): Q-table CHUNG cho mọi quái Tinh Anh,
## persist qua save file -> quái "nhớ" lối chơi của Player xuyên nhiều ván, không reset
## theo run (KHÁC run_buffs). Dictionary[String state, Dictionary[String action, float]].
var elite_q_table: Dictionary = {}

## Q-table cũ (state 3 yếu tố, trước khi thêm "Player đang di chuyển") không còn khớp -> bỏ.
## State hợp lệ hiện tại có đúng 4 phần ngăn bởi "|".
func _migrate_q_table(t: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for state in t:
		if String(state).split("|").size() == 4:
			out[state] = t[state]
	return out

# --- Ghi nhận hồ sơ (gọi từ main/enemy/boss; lưu file ở các mốc hiếm, không lưu mỗi lần hạ quái) ---
func record_run_start() -> void:
	MetaProgress.record_run_start(profile, current_class)
	save_game()

func record_council_clear() -> void:
	MetaProgress.record_council_clear(profile)
	save_game()

func record_run_end(entry: Dictionary) -> void:
	MetaProgress.record_run_end(profile, entry)
	save_game()

func record_floor_reached(f: int) -> void:
	MetaProgress.record_floor(profile, current_class, f)

func record_kill() -> void:
	MetaProgress.record_kill(profile, current_class)

func record_secret_found() -> void:
	MetaProgress.record_secret(profile)
	save_game()

func record_win() -> void:
	MetaProgress.record_win(profile)
	save_game()

func record_boss_kill(kind: String) -> void:
	var was_ready: bool = MetaProgress.can_evolve(profile, current_class)
	MetaProgress.record_boss(profile, current_class, kind)
	if not was_ready and MetaProgress.can_evolve(profile, current_class):
		var nm: String = String(classes[current_class]["name"])
		message.emit("%s can evolve! Open Profile in the menu." % nm, Color(1.0, 0.85, 0.3))
	save_game()

func class_skill_id() -> String:
	return class_skill_id_for(current_class)

## Kỹ năng đang có của một class: bản tiến hoá nếu đã mở, không thì kỹ năng khởi đầu.
func class_skill_id_for(cid: String) -> String:
	var evolved: String = MetaProgress.active_skill(profile, cid)
	if evolved != "":
		return evolved
	return String(classes.get(cid, {}).get("skill", ""))

func save_game() -> void:
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file != null:
		var data = {
			"purple_gems": purple_gems,
			"upgrades": upgrades,
			"saved_run": saved_run, # Lưu thêm ván đang chơi
			"settings": settings,
			"profile": profile,
			"elite_q_table": elite_q_table,
			"heat": selected_heat_ids()
		}
		file.store_var(data)
		file.close()

func load_game() -> void:
	if FileAccess.file_exists(save_path):
		var file = FileAccess.open(save_path, FileAccess.READ)
		if file != null:
			var data = file.get_var()
			if data != null:
				purple_gems = data.get("purple_gems", 0)
				saved_run = data.get("saved_run", {})
				# Player._ready chạy TRƯỚC main._ready: phải đặt đúng class của ván đang lưu ngay lúc nạp,
				# nếu không "Continue" sau khi mở lại game dựng nhầm sprite/máu/kỹ năng của class mặc định.
				if not saved_run.is_empty() and classes.has(String(saved_run.get("class", ""))):
					current_class = String(saved_run["class"])
				var loaded_upgrades = data.get("upgrades", {})
				for k in loaded_upgrades.keys():
					if upgrades.has(k): upgrades[k] = loaded_upgrades[k]
				var loaded_settings = data.get("settings", {})
				for k in loaded_settings.keys():
					settings[k] = loaded_settings[k]
				profile = MetaProgress.merge_loaded(data.get("profile", {}))
				elite_q_table = _migrate_q_table(data.get("elite_q_table", {}))
				heat_selected.clear()
				var hs = data.get("heat", [])
				if hs is Array:
					for id in HeatScript.sanitize(hs):
						heat_selected[id] = true
			file.close()
	else:
		save_game()
