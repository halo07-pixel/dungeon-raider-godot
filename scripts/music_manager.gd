extends Node
## Autoload "MusicManager": nhạc nền theo biome, nhạc riêng từng boss, nhạc Dungeon Lord 3 giai đoạn,
## nhạc menu và tiếng nhấn (stinger).
##
## CHỈ LẮNG NGHE tín hiệu ("call down, signal up"): Global.floor_started · boss_spawned ·
## boss_hp_changed · boss_defeated · player_died, cộng với việc scene Main Menu được nạp.
## Không node nào khác phải gọi vào đây, nên dungeon/boss/player vẫn chỉ phát tín hiệu như cũ.
## File nhạc nằm ở assets/music/ (CC0 — nguồn và các chỉnh sửa ghi trong assets/music/CREDITS.md).
##
##   Main Menu ........................... menu
##   Tầng 1-3 / 4-6 / 7-9 (và 11+) ....... explore_stone / explore_swamp / explore_ice
##   Tầng 10, trước khi vào phòng Lord ... lord_intro
##   Boss Warden / Necromancer / Frost ... boss_warden / boss_necromancer / boss_frost
##   Dungeon Lord vào trận ............... lord_fight  ->  từ pha 3 (dưới 50% máu) lord_final

const BUS_MUSIC: String = "Music"
## Nhạc luôn nằm DƯỚI tiếng SFX tổng hợp của Global (đo bằng test: RMS SFX sau gain ≈ -21..-29 dBFS,
## đỉnh ≈ -16 dBFS; nhạc đã chuẩn hoá -20 LUFS khám phá / -17 boss / -15..-16 Lord trước khi trừ mức này).
## Thanh "Music Volume" 100% = đúng mức này; nếu thấy nhạc to/nhỏ quá thì chỉnh hằng số này.
const MUSIC_BUS_BASE_DB: float = -10.0
const SILENT_DB: float = -60.0
const STINGER_DB: float = -2.0
const DEFAULT_FADE_IN: float = 2.0
const DEFAULT_FADE_OUT: float = 1.5

const MUSIC_DIR: String = "res://assets/music/"
const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"
const LORD_FLOOR: int = 10
## Dungeon Lord có 4 pha (BOSS_DATA trong boss.gd, ngưỡng 75/50/25% máu). Từ pha này trở đi
## nhạc đẩy lên bản cao trào nhất.
const LORD_FINAL_PHASE: int = 3
## Tiếng nhấn "victory" dài 4s: nhạc khám phá quay lại ngay trước khi nó dứt.
const VICTORY_RETURN_DELAY: float = 3.7
## Thời gian chờ lúc thoát game để luồng âm thanh của engine kịp nhả playback (xem _exit_tree).
## Đo thực tế: chờ ≤ 40ms vẫn báo lỗi, 60ms lúc được lúc không, ≥ 100ms thì sạch -> lấy 200ms cho chắc.
const EXIT_FLUSH_MSEC: int = 200

const LOOPS: Dictionary = {
	"menu": "menu.ogg",
	"explore_stone": "explore_stone.ogg",
	"explore_swamp": "explore_swamp.ogg",
	"explore_ice": "explore_ice.ogg",
	"boss_warden": "boss_warden.ogg",
	"boss_necromancer": "boss_necromancer.ogg",
	"boss_frost": "boss_frost.ogg",
	"lord_intro": "lord_intro.ogg",
	"lord_fight": "lord_fight.ogg",
	"lord_final": "lord_final.ogg",
}
const STINGERS: Dictionary = {
	"boss_appears": "stinger_boss_appears.ogg",
	"victory": "stinger_victory.ogg",
	"game_over": "stinger_game_over.ogg",
}

## Khoá của bản nhạc đang phát ("" = im lặng). Public để test và để tránh restart cùng một bài.
var current_key: String = ""
## Loại boss đang đánh ("" = không có trận boss nào đang diễn ra).
var boss_kind: String = ""

var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _fade_tweens: Array = [null, null]
var _stinger: AudioStreamPlayer
var _streams: Dictionary = {}
## Tăng mỗi khi có sự kiện mới: các lệnh hẹn giờ cũ (vd. quay lại nhạc khám phá sau boss) tự huỷ.
var _token: int = 0
## Đã từng phát âm thanh -> lúc thoát mới cần chờ AudioServer nhả playback (thoát khi chưa phát gì thì khỏi chờ).
var _audio_used: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # nhạc vẫn chạy và đổi bài mượt khi game tạm dừng (chọn buff, ESC)
	_setup_bus()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_MUSIC
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)
	_stinger = AudioStreamPlayer.new()
	_stinger.bus = BUS_MUSIC
	_stinger.volume_db = STINGER_DB
	add_child(_stinger)
	set_music_volume(float(Global.settings.get("music_volume", 1.0)), false)

	Global.floor_started.connect(_on_floor_started)
	Global.boss_spawned.connect(_on_boss_spawned)
	Global.boss_hp_changed.connect(_on_boss_hp_changed)
	Global.boss_defeated.connect(_on_boss_defeated)
	Global.player_died.connect(_on_player_died)
	get_tree().root.child_entered_tree.connect(_on_root_child_entered)
	_sync_with_current_scene.call_deferred()


## Thoát game: dừng hẳn, nhả tham chiếu stream rồi chờ một chút cho luồng âm thanh của engine xử lý lệnh dừng.
## Không chờ thì lúc tắt engine, AudioServer vẫn còn giữ playback đang dừng dở và in
## "ERROR: N resources still in use at exit" — vô hại với người chơi nhưng gây nhiễu log khi chạy test/headless.
func _exit_tree() -> void:
	for p in _players:
		p.stop()
		p.stream = null
	if _stinger != null:
		_stinger.stop()
		_stinger.stream = null
	_streams.clear()
	if _audio_used:
		OS.delay_msec(EXIT_FLUSH_MSEC)


# ---------------------------------------------------------------- Bus + âm lượng
## Tạo bus "Music" tách khỏi Master nếu chưa có (cùng cách Global dựng bus "SFX").
func _setup_bus() -> void:
	if AudioServer.get_bus_index(BUS_MUSIC) == -1:
		var idx: int = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, BUS_MUSIC)
		AudioServer.set_bus_send(idx, "Master")


## v: 0..1 (thanh Music Volume trong Settings). Lưu vào Global.settings cùng master/sfx.
func set_music_volume(v: float, p_save: bool = true) -> void:
	v = clampf(v, 0.0, 1.0)
	Global.settings["music_volume"] = v
	var db: float = -80.0
	if v > 0.0:
		db = linear_to_db(v) + MUSIC_BUS_BASE_DB
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUS_MUSIC), db)
	if p_save:
		Global.save_game()


# ---------------------------------------------------------------- Chọn bài theo ngữ cảnh
## Biome theo tầng — khớp Dungeon._biome_for_floor: 1-3 đá · 4-6 đầm lầy · 7-9 băng · 10 = tầng Lord · 11+ băng.
func explore_key_for_floor(floor_num: int) -> String:
	if floor_num == LORD_FLOOR:
		return "lord_intro"
	if floor_num <= 3:
		return "explore_stone"
	if floor_num <= 6:
		return "explore_swamp"
	return "explore_ice"


func boss_key_for_kind(kind: String) -> String:
	match kind:
		"warden":
			return "boss_warden"
		"necromancer":
			return "boss_necromancer"
		"frost":
			return "boss_frost"
		"lord":
			return "lord_fight"
	return "boss_warden" # boss thêm sau này mà chưa có bài riêng -> dùng nhạc boss chung


# ---------------------------------------------------------------- Phát / đổi bài
## Đổi sang bài `key` bằng crossfade. Cùng bài đang phát thì giữ nguyên (không restart).
func play_track(key: String, fade_in: float = DEFAULT_FADE_IN, fade_out: float = DEFAULT_FADE_OUT) -> void:
	if key == current_key and _players[_active].playing:
		return
	var stream: AudioStream = _get_stream(key)
	if stream == null:
		return # thiếu file -> im lặng, không làm sập game
	var old_idx: int = _active
	_active = 1 - _active
	var p: AudioStreamPlayer = _players[_active]
	p.stop()
	p.stream = stream
	p.volume_db = SILENT_DB
	p.play()
	_audio_used = true
	_fade(_active, 0.0, fade_in, false)
	if _players[old_idx].playing:
		_fade(old_idx, SILENT_DB, fade_out, true)
	current_key = key


func stop_music(fade_out: float = DEFAULT_FADE_OUT) -> void:
	current_key = ""
	for i in 2:
		if _players[i].playing:
			_fade(i, SILENT_DB, fade_out, true)


## Tiếng nhấn ngắn (không lặp) phát chồng lên nhạc nền, cùng bus Music.
func play_stinger(key: String) -> void:
	var stream: AudioStream = _get_stream(key)
	if stream == null:
		return
	_stinger.stream = stream
	_stinger.play()
	_audio_used = true


func _fade(idx: int, to_db: float, duration: float, stop_when_done: bool) -> void:
	var prev: Tween = _fade_tweens[idx]
	if prev != null and prev.is_valid():
		prev.kill()
	var p: AudioStreamPlayer = _players[idx]
	var tw: Tween = create_tween()
	_fade_tweens[idx] = tw
	tw.tween_property(p, "volume_db", to_db, maxf(0.01, duration))
	if stop_when_done:
		tw.tween_callback(p.stop)


## Nạp stream theo khoá (có cache). Ưu tiên load() (bản đã import, dùng được khi xuất game);
## nếu chưa import (chạy headless / chưa mở editor) thì đọc thẳng file .ogg.
func _get_stream(key: String) -> AudioStream:
	if _streams.has(key):
		return _streams[key]
	var is_loop: bool = LOOPS.has(key)
	var file: String = String(LOOPS.get(key, STINGERS.get(key, "")))
	if file == "":
		return null
	var path: String = MUSIC_DIR + file
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	elif FileAccess.file_exists(path):
		stream = AudioStreamOggVorbis.load_from_file(path)
	if stream == null:
		push_warning("MusicManager: không nạp được " + path)
		return null
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = is_loop
	_streams[key] = stream
	return stream


# ---------------------------------------------------------------- Phản ứng với tín hiệu
## Scene Main Menu vừa được nạp (lúc mở game, hoặc Save & Quit / Game Over / Victory -> menu).
func _on_root_child_entered(node: Node) -> void:
	if node.scene_file_path == MAIN_MENU_SCENE:
		_token += 1
		boss_kind = ""
		play_track("menu", 1.5, 1.0)


func _sync_with_current_scene() -> void:
	var scene: Node = get_tree().current_scene
	if scene != null and scene.scene_file_path == MAIN_MENU_SCENE and current_key == "":
		play_track("menu", 1.5, 1.0)


func _on_floor_started(floor_num: int) -> void:
	_token += 1
	boss_kind = ""
	play_track(explore_key_for_floor(floor_num))


func _on_boss_spawned(boss) -> void:
	_token += 1
	var kind: String = "warden"
	if is_instance_valid(boss) and boss.get("kind") != null:
		kind = String(boss.get("kind"))
	boss_kind = kind
	play_stinger("boss_appears")
	# Boss thường: nhạc nổi dần theo nhịp tiếng nhấn; Lord vào thẳng cao trào nên nổi nhanh hơn.
	play_track(boss_key_for_kind(kind), 1.5 if kind == "lord" else 2.5, 0.8)


func _on_boss_hp_changed(_hp: float, _max_hp: float, phase: int, _boss_name: String) -> void:
	if boss_kind == "lord" and phase >= LORD_FINAL_PHASE:
		play_track("lord_final", 0.8, 0.8)


func _on_boss_defeated() -> void:
	_token += 1
	var token: int = _token
	boss_kind = ""
	play_stinger("victory")
	stop_music(1.2)
	await get_tree().create_timer(VICTORY_RETURN_DELAY).timeout
	if token == _token: # chưa có sự kiện nào khác (qua tầng, chết, về menu) chen vào
		play_track(explore_key_for_floor(Global.floor_num), 3.0, 1.0)


func _on_player_died() -> void:
	_token += 1
	boss_kind = ""
	stop_music(0.6)
	play_stinger("game_over")
