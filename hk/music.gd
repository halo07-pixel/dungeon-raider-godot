extends Node
## Phát nhạc nền từ assets/music (nhạc CC0 của game cũ). `play` cùng bài đang phát thì bỏ qua; đổi bài có fade-in ngắn.
const DIR: String = "res://assets/music/"
const AREA_TRACK: Dictionary = {"gate": "explore_stone", "catacomb": "explore_hell", "vault": "explore_ice"}
const BOSS_TRACK: Dictionary = {"warden": "boss_warden", "wraith": "boss_necromancer", "lord": "lord_fight"}
const VOLUME_DB: float = -9.0
var current: String = ""
var _player: AudioStreamPlayer
var _tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	add_child(_player)

func play(track: String, loop: bool = true) -> void:
	if track == current and _player.playing:
		return
	current = track
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
	_tween.tween_property(_player, "volume_db", VOLUME_DB, 0.8)

func stop() -> void:
	current = ""
	_player.stop()
