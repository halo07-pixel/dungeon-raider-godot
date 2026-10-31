extends Node
## Phát nhạc nền từ assets/music (nhạc CC0 của game cũ). `play` cùng bài đang phát thì bỏ qua; đổi bài có fade-in ngắn.
const STATE = preload("res://hk/state.gd")
const DIR: String = "res://assets/music/"
const AREA_TRACK: Dictionary = {"gate": "explore_stone", "catacomb": "explore_hell", "vault": "explore_ice", "archive": "explore_ice"}
const BOSS_TRACK: Dictionary = {"warden": "boss_warden", "wraith": "boss_necromancer", "lord": "lord_fight", "brute": "boss_warden", "hexer": "boss_necromancer", "colossus": "boss_warden", "many_faced": "lord_fight"}
const SFX = preload("res://hk/sfx.gd")
const VOLUME_DB: float = -9.0
const AMBIENT_DB: float = -12.0   # ambient + lớp pha cuối so với nhạc: ambient nhỏ hơn hẳn, lớp pha cuối chỉ nhỉnh lên
const LAYER_DB: float = -3.0
const FINAL_LAYER: Dictionary = {"lord": [2, "final_lord"], "many_faced": [3, "final_many"]}   # boss -> [pha cuối, vòng lặp trong sfx.LOOPS]
var current: String = ""
var ambient_now: String = ""
var layer_now: String = ""
var _player: AudioStreamPlayer
var _amb: AudioStreamPlayer
var _layer: AudioStreamPlayer
var _tween: Tween
var _amb_tween: Tween
var _layer_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_amb = AudioStreamPlayer.new()
	add_child(_amb)
	_layer = AudioStreamPlayer.new()
	add_child(_layer)

func play(track: String, loop: bool = true) -> void:
	if track == current and _player.playing:
		return
	current = track
	layer("")   # đổi bài thì lớp pha cuối của bài trước tắt
	var path: String = DIR + track + ".ogg"
	if not ResourceLoader.exists(path):
		_player.stop()
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	_player.stream = stream
	_player.volume_db = -40.0
	_player.play()
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", target_db(), 0.8)

func target_db() -> float:
	return VOLUME_DB + STATE.vol_db(STATE.music_vol)

## Gọi khi người chơi đổi thanh âm lượng: đặt thẳng, bỏ fade đang chạy.
func apply_volume() -> void:
	for t in [_tween, _amb_tween, _layer_tween]:
		if t:
			t.kill()
	_player.volume_db = target_db()
	_amb.volume_db = target_db() + AMBIENT_DB
	_layer.volume_db = target_db() + LAYER_DB

func stop() -> void:
	current = ""
	ambient("")
	layer("")
	_player.stop()

## Không khí theo khu (`amb_<khu>`); "" = tắt. Đổi khu: nhỏ dần về 0, đổi vòng lặp, rồi lớn dần. Khu không có vòng lặp thì im.
func ambient(area: String) -> void:
	if area == ambient_now:
		return
	ambient_now = area
	_swap(_amb, "amb_" + area if area != "" else "", AMBIENT_DB, 1.5)

## Lớp nhạc chồng lên bài đang phát (pha 3 của boss); "" = tắt.
func layer(name: String) -> void:
	if name == layer_now:
		return
	layer_now = name
	_swap(_layer, name, LAYER_DB, 1.2)

## Boss vào pha cuối (Lord pha 2, Many-Faced pha 3 = sovereign) có lớp nhạc riêng chồng lên lord_fight, không đổi bài nền.
func phase(kind: String, ph: int) -> void:
	if FINAL_LAYER.has(kind) and ph >= int(FINAL_LAYER[kind][0]):
		layer(String(FINAL_LAYER[kind][1]))

func _swap(p: AudioStreamPlayer, loop_name: String, offset_db: float, fade: float) -> void:
	var tw: Tween = create_tween()
	if p == _amb:
		if _amb_tween:
			_amb_tween.kill()
		_amb_tween = tw
	else:
		if _layer_tween:
			_layer_tween.kill()
		_layer_tween = tw
	if p.playing:
		tw.tween_property(p, "volume_db", -60.0, fade * 0.5)
	tw.tween_callback(func() -> void:
		var st: AudioStream = SFX.loop_stream(loop_name) if loop_name != "" else null
		if st == null:
			p.stop()
			p.stream = null
		elif p.stream != st or not p.playing:
			p.stream = st
			p.volume_db = -60.0
			p.play())
	if loop_name != "":
		tw.tween_property(p, "volume_db", target_db() + offset_db, fade)
