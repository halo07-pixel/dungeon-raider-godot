extends Node
## Autoload "Global": hằng số vật lý, DỮ LIỆU CÂN BẰNG (vũ khí / quái), tín hiệu chung,
## và các hiệu ứng dùng chung (âm thanh tự tổng hợp, hạt, số sát thương bay, hitstop).

signal message(text: String, color: Color)
signal player_died
signal portal_entered
signal boss_spawned(boss)
signal boss_hp_changed(hp: float, max_hp: float, phase: int, boss_name: String)
signal boss_defeated
## Dungeon phát ngay khi bắt đầu dựng một tầng (mọi tầng, kể cả tầng Lord). MusicManager chọn nhạc theo biome.
signal floor_started(floor_num: int)
## Một đòn của Player vừa trúng quái/boss (cận chiến, đạn, nguồn phụ). Buff phản ứng khi trúng (Fortify...) nghe signal này.
signal player_hit_landed(target: Node, dmg: int, is_crit: bool)
## Player vừa nhận sát thương (HUD nghe để nháy viền đỏ khi đòn nặng).
signal player_damaged(amount: int, max_hp: int)

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
	"legendary": {"name": "Legendary", "mult": 2.0, "lifesteal": 0.10, "color": Color(1.0, 0.8, 0.1), "weight": 5}
}

var weapons: Dictionary = {
	"pistol": {"name": "Pistol", "damage": 10, "cooldown": 0.30, "speed": 640.0, "pellets": 1, "spread": 3.0, "pierce": false, "life": 1.1, "recoil": 45.0, "radius": 5.0, "color": Color(1.0, 0.9, 0.4), "sfx": "shoot", "is_melee": false},
	"smg": {"name": "SMG", "damage": 5, "cooldown": 0.085, "speed": 700.0, "pellets": 1, "spread": 9.0, "pierce": false, "life": 1.0, "recoil": 18.0, "radius": 4.0, "color": Color(1.0, 0.65, 0.25), "sfx": "shoot", "is_melee": false},
	"shotgun": {"name": "Shotgun", "damage": 7, "cooldown": 0.75, "speed": 560.0, "pellets": 6, "spread": 36.0, "pierce": false, "life": 0.45, "recoil": 150.0, "radius": 4.0, "color": Color(1.0, 0.5, 0.3), "sfx": "shotgun", "is_melee": false},
	"laser": {"name": "Laser Gun", "damage": 14, "cooldown": 0.50, "speed": 1100.0, "pellets": 1, "spread": 0.0, "pierce": true, "life": 0.9, "recoil": 60.0, "radius": 4.0, "color": Color(0.4, 1.0, 1.0), "sfx": "laser", "is_melee": false},

	"broadsword": {"name": "Longsword", "damage": 25, "cooldown": 0.45, "is_melee": true, "range": 55.0, "cleave_angle": 180.0, "knock": 280.0, "color": Color(0.9, 0.9, 0.9), "sfx": "dodge"},
	"daggers": {"name": "Daggers", "damage": 17, "cooldown": 0.22, "is_melee": true, "range": 40.0, "cleave_angle": 80.0, "knock": 120.0, "color": Color(0.6, 0.9, 0.6), "sfx": "dodge"},
	"hammer": {"name": "War Hammer", "damage": 40, "cooldown": 0.90, "is_melee": true, "range": 65.0, "cleave_angle": 160.0, "knock": 550.0, "color": Color(1.0, 0.5, 0.2), "sfx": "slam"}
}

var classes: Dictionary = {
	"ranger": {"name": "Ranger", "max_hp": 100, "default_weapon": "pistol"},
	"brawler": {"name": "Brawler", "max_hp": 200, "default_weapon": "broadsword"}
}
var current_class: String = "brawler"

var enemies: Dictionary = {
	"slime": {"hp": 30, "speed": 95.0, "touch": 10, "touch_cd": 0.8, "touch_knock": 260.0, "radius": 13.0, "coins": 1, "weight": 1.0, "color": Color(0.35, 0.85, 0.35)},
	"archer": {"hp": 22, "speed": 85.0, "touch": 0, "touch_cd": 1.0, "touch_knock": 200.0, "radius": 12.0, "coins": 2, "weight": 1.0, "color": Color(0.4, 0.6, 1.0), "shoot_cd": 1.5, "bullet_damage": 8, "bullet_speed": 280.0, "keep_away": 170.0, "range": 380.0},
	"brute": {"hp": 120, "speed": 62.0, "touch": 20, "touch_cd": 1.0, "touch_knock": 430.0, "radius": 20.0, "coins": 3, "weight": 2.5, "color": Color(0.8, 0.35, 0.25)},

	# --- BIOME 2 (Đầm Lầy) — bộ quái RIÊNG, không lặp với biome khác. Chủ đề Độc & Tiêu Hao:
	# phối hợp giữ chân (Masked Orc) + dồn độc (Shaman tầm xa + Chort cận chiến) ---
	"shaman": {"hp": 20, "speed": 80.0, "touch": 0, "touch_cd": 1.0, "touch_knock": 180.0, "radius": 12.0, "coins": 2, "weight": 1.0, "color": Color(0.55, 0.85, 0.35), "shoot_cd": 1.8, "bullet_damage": 4, "bullet_speed": 260.0, "keep_away": 170.0, "range": 380.0, "bullet_effect": "poison"},
	"chort": {"hp": 18, "speed": 128.0, "touch": 6, "touch_cd": 0.5, "touch_knock": 150.0, "radius": 11.0, "coins": 2, "weight": 0.9, "color": Color(0.85, 0.25, 0.2)},
	"masked_orc": {"hp": 140, "speed": 58.0, "touch": 16, "touch_cd": 1.1, "touch_knock": 350.0, "radius": 20.0, "coins": 3, "weight": 2.6, "color": Color(0.5, 0.65, 0.4)},

	# --- BIOME 3 (Băng Giá) — bộ quái RIÊNG. Chủ đề Mất Kiểm Soát: không có vai tầm xa
	# (hết quái CC0 phù hợp) nhưng bù lại dày CC — slide + slow — khớp với Ô Băng ---
	"frost_zombie": {"hp": 35, "speed": 90.0, "touch": 8, "touch_cd": 0.9, "touch_knock": 220.0, "radius": 13.0, "coins": 2, "weight": 1.0, "color": Color(0.55, 0.8, 0.95)},
	"frost_big_zombie": {"hp": 150, "speed": 50.0, "touch": 22, "touch_cd": 1.2, "touch_knock": 400.0, "radius": 21.0, "coins": 3, "weight": 2.8, "color": Color(0.6, 0.85, 1.0), "slam_cd": 2.2, "slam_radius": 70.0},
	"frost_tiny": {"hp": 12, "speed": 150.0, "touch": 14, "touch_cd": 999.0, "touch_knock": 260.0, "radius": 9.0, "coins": 1, "weight": 0.6, "color": Color(0.75, 0.92, 1.0)},
}
# ==============================================================================

var floor_num: int = 1
var coins: int = 0
var player = null
var camera = null
var world: Node2D = null

## Hệ số khó THÊM áp dụng cho tầng > 10 (Chế Độ Vô Hạn, sau khi hạ Dungeon Lord tầng 10):
## nhân thêm vào công thức scale máu/giáp vốn có của boss.gd/enemy.gd, khiến độ khó tăng
## NHANH HƠN hẳn so với tốc độ tăng đều 1-10 — đúng như phần thưởng/thử thách của Vô Hạn.
const ENDLESS_START_FLOOR: int = 10
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
	return minf(ENEMY_DMG_MULT_CAP, 1.0 + ENEMY_DMG_PER_FLOOR * float(maxi(0, for_floor_num - 1)))

var _sfx: Dictionary = {}
var _dot_tex: ImageTexture
var _hitstop_active: bool = false

## Cache dùng chung cho toàn bộ ảnh nạp từ res://assets — nhiều script (enemy,
## player, boss, pickup, dungeon, menu...) từng tự viết lại 3 dòng Image.load() +
## ImageTexture.create_from_image() giống hệt nhau, vừa trùng lặp code vừa tốn
## I/O đĩa + cấp phát lại mỗi lần gọi. Gom về 1 chỗ, load 1 lần/path rồi tái sử dụng.
var _tex_cache: Dictionary = {}

func load_tex(path: String) -> ImageTexture:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var img := Image.new()
	var tex: ImageTexture = null
	if img.load(path) == OK:
		tex = ImageTexture.create_from_image(img)
	else:
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
	}


func reset_run() -> void:
	floor_num = 1
	coins = 0
	buff_picks_left = 0
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
	"buff_sweep": {"name": "Sweep", "desc": "Melee: +50% range, +40% arc. Ranged: pierce", "tier": "epic", "class": "any"},
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
	"buff_super": {"name": "Mega Shot", "desc": "Every 6th shot: piercing, x3 damage", "tier": "epic", "class": "ranged"},
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
func roll_buff_choices(n: int = 3) -> Array:
	var candidates: Array = []
	var wclass: String = player_weapon_class()
	for id in buff_pool:
		var bclass: String = String(buff_pool[id].get("class", "any"))
		if bclass != "any" and bclass != wclass:
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

func request_buff_choice() -> void:
	buff_picks_left = BUFF_PICKS_PER_BOSS
	_offer_next_buff_pick()

## Phát 3 lựa chọn cho lượt kế tiếp (nếu còn lượt). buff_picker gọi lại sau mỗi lần chọn.
func _offer_next_buff_pick() -> void:
	if buff_picks_left <= 0:
		return
	var choices: Array = roll_buff_choices(3)
	if choices.is_empty():
		buff_picks_left = 0
		return
	buff_choice_requested.emit(choices)

func consume_buff_pick() -> void:
	buff_picks_left = maxi(0, buff_picks_left - 1)
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
	if not buff_pool.has(id):
		return
	run_buffs[id] = buff_stack(id) + 1
	if id == "buff_shield_cap" and is_instance_valid(player):
		player.refresh_max_shield()
		player.shield += 10.0 # phần giáp tăng thêm được tặng đầy ngay
	message.emit("Buff: " + buff_pool[id]["name"], BUFF_TIER_COLOR.get(buff_pool[id]["tier"], Color.WHITE))


func add_coin() -> void:
	coins += 1
	# Bổ sung dòng này để ghi chép vào sổ thống kê Game Over
	if get("run_stats") != null and run_stats.has("coins"):
		run_stats["coins"] += 1


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


func sfx(sfx_name: String) -> void:
	if not _sfx.has(sfx_name):
		return
	var p := AudioStreamPlayer.new()
	p.stream = _sfx[sfx_name]
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
var upgrades: Dictionary = {
	"hp_boost": 0, "start_coin": 0, "mastery": 0, "revive": 0
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

func save_game() -> void:
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file != null:
		var data = {
			"purple_gems": purple_gems,
			"upgrades": upgrades,
			"saved_run": saved_run, # Lưu thêm ván đang chơi
			"settings": settings,
			"elite_q_table": elite_q_table
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
				var loaded_upgrades = data.get("upgrades", {})
				for k in loaded_upgrades.keys():
					if upgrades.has(k): upgrades[k] = loaded_upgrades[k]
				var loaded_settings = data.get("settings", {})
				for k in loaded_settings.keys():
					settings[k] = loaded_settings[k]
				elite_q_table = _migrate_q_table(data.get("elite_q_table", {}))
			file.close()
	else:
		save_game()
