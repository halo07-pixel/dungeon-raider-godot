extends Node
## Autoload "Global": hằng số vật lý, DỮ LIỆU CÂN BẰNG (vũ khí / quái), tín hiệu chung,
## và các hiệu ứng dùng chung (âm thanh tự tổng hợp, hạt, số sát thương bay, hitstop).

signal message(text: String, color: Color)
signal player_died
signal portal_entered
signal boss_spawned(boss)
signal boss_hp_changed(hp: float, max_hp: float, phase: int, boss_name: String)
signal boss_defeated

const TILE: int = 32

# Bit collision layer (khớp [layer_names] trong project.godot)
const L_WORLD: int = 1
const L_PLAYER: int = 2
const L_ENEMY: int = 4
const L_PBULLET: int = 8
const L_EBULLET: int = 16
const L_PICKUP: int = 32
var rarities: Dictionary = {
	"common": {"name": "Common", "mult": 1.0, "lifesteal": 0.0, "color": Color(0.8, 0.8, 0.8), "weight": 50},
	"rare": {"name": "Rare", "mult": 1.25, "lifesteal": 0.02, "color": Color(0.2, 0.8, 0.3), "weight": 30},
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
}
# ==============================================================================

var floor_num: int = 1
var coins: int = 0
var player = null
var camera = null
var world: Node2D = null

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
	load_game()
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	_setup_input()
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
	Engine.time_scale = 1.0
	_hitstop_active = false


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

func save_game() -> void:
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file != null:
		var data = {
			"purple_gems": purple_gems,
			"upgrades": upgrades,
			"saved_run": saved_run # Lưu thêm ván đang chơi
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
			file.close()
	else:
		save_game()
