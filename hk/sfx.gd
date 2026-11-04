extends Node
## Âm thanh hiệu ứng tổng hợp bằng code (không cần file .wav), cùng cách làm với game cũ nhưng độc lập autoload.
## Các node báo lên bằng signal `sfx(name)`; world nối signal đó vào `play`. `history` lưu vài tên gần nhất (cho test).
const STATE = preload("res://hk/state.gd")
const RATE: int = 22050
const VOLUME_DB: float = -6.0
var history: Array = []
var _sounds: Dictionary = {}
static var _loops: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in DEFS:
		_sounds[n] = _mix(float(DEFS[n]["total"]), DEFS[n]["layers"])

func has_sound(name: String) -> bool:
	return _sounds.has(name)

func play(name: String, pitch: float = 1.0) -> void:
	history.append(name)
	if history.size() > 16:
		history.pop_front()
	if not _sounds.has(name):
		return
	var p := AudioStreamPlayer.new()
	p.stream = _sounds[name]
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.volume_db = VOLUME_DB + STATE.vol_db(STATE.sfx_vol)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

## Vòng lặp nền (ambient theo khu, lớp nhạc pha cuối của Lord/Many-Faced): dựng lười lần đầu cần, nhớ lại. Mọi lớp có bao thư về 0 ở hai đầu nên khớp vòng không bị "click".
static func loop_stream(name: String) -> AudioStreamWAV:
	if not LOOPS.has(name):
		return null
	if not _loops.has(name):
		_loops[name] = _mix(float(LOOPS[name]["total"]), LOOPS[name]["layers"], true)
	return _loops[name]

## Mỗi lớp: freq, slide (Hz trượt hết lớp), vol, dur, wave (sine|square|saw|noise), delay, decay, lp (noise 0..1), swell.
const DEFS: Dictionary = {
	# báo hiệu đòn (thay vùng cảnh báo màu): mỗi loại đòn một âm khác hẳn nhau để nghe là biết đòn gì
	"tell": {"total": 0.18, "layers": [{"wave": "saw", "freq": 200.0, "slide": 260.0, "vol": 0.14, "dur": 0.16, "swell": 0.6}]},
	"tell_slash": {"total": 0.22, "layers": [{"wave": "saw", "freq": 300.0, "slide": 500.0, "vol": 0.16, "dur": 0.2, "swell": 0.7}]},
	"tell_slam": {"total": 0.4, "layers": [{"wave": "sine", "freq": 110.0, "slide": 60.0, "vol": 0.3, "dur": 0.38, "swell": 0.6}, {"wave": "noise", "lp": 0.1, "vol": 0.12, "dur": 0.3}]},
	"tell_bolt": {"total": 0.2, "layers": [{"wave": "sine", "freq": 1100.0, "slide": 700.0, "vol": 0.16, "dur": 0.08}, {"wave": "sine", "freq": 1100.0, "slide": 700.0, "vol": 0.16, "dur": 0.08, "delay": 0.1}]},
	"tell_summon": {"total": 0.45, "layers": [{"wave": "saw", "freq": 80.0, "slide": 40.0, "vol": 0.2, "dur": 0.4, "swell": 0.5}, {"wave": "sine", "freq": 240.0, "slide": 120.0, "vol": 0.12, "dur": 0.4}]},
	"tell_conjure": {"total": 0.3, "layers": [{"wave": "sine", "freq": 600.0, "slide": 300.0, "vol": 0.14, "dur": 0.25, "swell": 0.4}, {"wave": "noise", "lp": 0.7, "vol": 0.08, "dur": 0.2}]},
	"tell_shift": {"total": 0.5, "layers": [{"wave": "sine", "freq": 300.0, "slide": 700.0, "vol": 0.18, "dur": 0.45, "swell": 0.7}, {"wave": "sine", "freq": 450.0, "slide": 900.0, "vol": 0.1, "dur": 0.45, "swell": 0.7}]},
	"tell_pillar": {"total": 0.4, "layers": [{"wave": "sine", "freq": 90.0, "slide": 50.0, "vol": 0.3, "dur": 0.38, "swell": 0.7}, {"wave": "noise", "lp": 0.08, "vol": 0.15, "dur": 0.35}]},
	"tell_fissure": {"total": 0.35, "layers": [{"wave": "noise", "lp": 0.05, "vol": 0.3, "dur": 0.3, "swell": 0.5}, {"wave": "saw", "freq": 70.0, "slide": 30.0, "vol": 0.15, "dur": 0.3}]},
	"tell_veil": {"total": 0.5, "layers": [{"wave": "sine", "freq": 700.0, "slide": 150.0, "vol": 0.14, "dur": 0.45}, {"wave": "noise", "lp": 0.3, "vol": 0.08, "dur": 0.4, "swell": 0.6}]},
	"tell_torch": {"total": 0.35, "layers": [{"wave": "noise", "lp": 0.4, "vol": 0.25, "dur": 0.3, "swell": 0.4}, {"wave": "saw", "freq": 220.0, "slide": 120.0, "vol": 0.1, "dur": 0.3}]},
	"tell_heat": {"total": 0.4, "layers": [{"wave": "saw", "freq": 140.0, "slide": 260.0, "vol": 0.14, "dur": 0.38, "swell": 0.8}, {"wave": "noise", "lp": 0.6, "vol": 0.1, "dur": 0.3}]},
	"tell_tide": {"total": 0.5, "layers": [{"wave": "sine", "freq": 140.0, "slide": 220.0, "vol": 0.22, "dur": 0.45, "swell": 0.7}, {"wave": "noise", "lp": 0.2, "vol": 0.12, "dur": 0.4}]},
	"crumble": {"total": 0.5, "layers": [{"wave": "noise", "lp": 0.12, "vol": 0.35, "dur": 0.45, "swell": 0.15}, {"wave": "sine", "freq": 90.0, "slide": 40.0, "vol": 0.25, "dur": 0.3}]},
	"tell_bloom": {"total": 0.5, "layers": [{"wave": "noise", "lp": 0.2, "vol": 0.2, "dur": 0.45, "swell": 0.8}, {"wave": "sine", "freq": 160.0, "slide": 240.0, "vol": 0.14, "dur": 0.4, "swell": 0.6}]},
	"tell_vine": {"total": 0.4, "layers": [{"wave": "saw", "freq": 120.0, "slide": 90.0, "vol": 0.14, "dur": 0.35, "swell": 0.7}, {"wave": "noise", "lp": 0.1, "vol": 0.1, "dur": 0.3}]},
	"tell_quake": {"total": 0.5, "layers": [{"wave": "sine", "freq": 80.0, "slide": 40.0, "vol": 0.32, "dur": 0.2}, {"wave": "sine", "freq": 80.0, "slide": 40.0, "vol": 0.32, "dur": 0.2, "delay": 0.25}, {"wave": "noise", "lp": 0.06, "vol": 0.15, "dur": 0.45}]},
	"tell_sweep": {"total": 0.5, "layers": [{"wave": "saw", "freq": 90.0, "slide": 200.0, "vol": 0.16, "dur": 0.4, "swell": 0.8}, {"wave": "noise", "lp": 0.08, "vol": 0.14, "dur": 0.4}, {"wave": "sine", "freq": 1100.0, "vol": 0.1, "dur": 0.1, "delay": 0.4}]},
	"tell_rush": {"total": 0.5, "layers": [{"wave": "saw", "freq": 200.0, "slide": 700.0, "vol": 0.18, "dur": 0.4, "swell": 0.9}, {"wave": "sine", "freq": 1500.0, "vol": 0.12, "dur": 0.1, "delay": 0.38}]},
	"tell_dive": {"total": 0.3, "layers": [{"wave": "saw", "freq": 600.0, "slide": -400.0, "vol": 0.14, "dur": 0.25}]},
	"rumble": {"total": 0.25, "layers": [{"wave": "noise", "lp": 0.06, "vol": 0.25, "dur": 0.22}]},
	"jump": {"total": 0.14, "layers": [{"wave": "sine", "freq": 330.0, "slide": 280.0, "vol": 0.25, "dur": 0.12}]},
	"double_jump": {"total": 0.2, "layers": [{"wave": "sine", "freq": 440.0, "slide": 420.0, "vol": 0.25, "dur": 0.16}, {"wave": "noise", "lp": 0.3, "vol": 0.12, "dur": 0.14}]},
	"wall_jump": {"total": 0.12, "layers": [{"wave": "square", "freq": 260.0, "slide": 200.0, "vol": 0.14, "dur": 0.09}, {"wave": "noise", "lp": 0.4, "vol": 0.15, "dur": 0.08}]},
	"land": {"total": 0.12, "layers": [{"wave": "noise", "lp": 0.15, "vol": 0.4, "dur": 0.1}, {"wave": "sine", "freq": 90.0, "slide": -40.0, "vol": 0.3, "dur": 0.1}]},
	"dash": {"total": 0.22, "layers": [{"wave": "noise", "lp": 0.5, "vol": 0.35, "dur": 0.2, "decay": 1.5}, {"wave": "saw", "freq": 300.0, "slide": -200.0, "vol": 0.08, "dur": 0.18}]},
	"slash": {"total": 0.12, "layers": [{"wave": "noise", "lp": 0.6, "vol": 0.3, "dur": 0.1}, {"wave": "sine", "freq": 500.0, "slide": -350.0, "vol": 0.12, "dur": 0.08}]},
	"hit": {"total": 0.1, "layers": [{"wave": "noise", "lp": 0.9, "vol": 0.4, "dur": 0.06}, {"wave": "square", "freq": 180.0, "slide": -100.0, "vol": 0.2, "dur": 0.08}]},
	"hit_heavy": {"total": 0.16, "layers": [{"wave": "noise", "lp": 0.7, "vol": 0.45, "dur": 0.08}, {"wave": "square", "freq": 120.0, "slide": -70.0, "vol": 0.25, "dur": 0.12}, {"wave": "sine", "freq": 70.0, "slide": -30.0, "vol": 0.35, "dur": 0.14}]},
	"parry": {"total": 0.25, "layers": [{"wave": "square", "freq": 1500.0, "vol": 0.18, "dur": 0.05}, {"wave": "sine", "freq": 2250.0, "vol": 0.2, "dur": 0.22, "decay": 1.6}, {"wave": "sine", "freq": 90.0, "slide": -30.0, "vol": 0.3, "dur": 0.12}]},
	"enemy_die": {"total": 0.3, "layers": [{"wave": "noise", "lp": 0.35, "vol": 0.35, "dur": 0.25}, {"wave": "sine", "freq": 200.0, "slide": -150.0, "vol": 0.25, "dur": 0.25}]},
	"hurt": {"total": 0.3, "layers": [{"wave": "square", "freq": 140.0, "slide": -90.0, "vol": 0.3, "dur": 0.25}, {"wave": "noise", "lp": 0.4, "vol": 0.25, "dur": 0.2}]},
	"die": {"total": 0.9, "layers": [{"wave": "sine", "freq": 220.0, "slide": -200.0, "vol": 0.3, "dur": 0.8}, {"wave": "noise", "lp": 0.1, "vol": 0.3, "dur": 0.6}]},
	"spell": {"total": 0.25, "layers": [{"wave": "saw", "freq": 400.0, "slide": 500.0, "vol": 0.18, "dur": 0.2}, {"wave": "sine", "freq": 900.0, "slide": -600.0, "vol": 0.15, "dur": 0.15}]},
	"heal": {"total": 0.35, "layers": [{"wave": "sine", "freq": 520.0, "vol": 0.25, "dur": 0.12}, {"wave": "sine", "freq": 780.0, "vol": 0.25, "dur": 0.22, "delay": 0.1}]},
	"geo": {"total": 0.18, "layers": [{"wave": "sine", "freq": 1200.0, "vol": 0.2, "dur": 0.07}, {"wave": "sine", "freq": 1600.0, "vol": 0.2, "dur": 0.1, "delay": 0.05}]},
	"bench": {"total": 0.6, "layers": [{"wave": "sine", "freq": 330.0, "vol": 0.2, "dur": 0.5, "swell": 0.2}, {"wave": "sine", "freq": 495.0, "vol": 0.15, "dur": 0.5, "delay": 0.1, "swell": 0.2}]},
	"ability": {"total": 0.75, "layers": [{"wave": "sine", "freq": 440.0, "vol": 0.22, "dur": 0.3}, {"wave": "sine", "freq": 550.0, "vol": 0.22, "dur": 0.3, "delay": 0.1}, {"wave": "sine", "freq": 660.0, "vol": 0.22, "dur": 0.3, "delay": 0.2}, {"wave": "sine", "freq": 880.0, "vol": 0.22, "dur": 0.4, "delay": 0.3}]},
	"charm": {"total": 0.35, "layers": [{"wave": "sine", "freq": 700.0, "vol": 0.22, "dur": 0.15}, {"wave": "sine", "freq": 1050.0, "vol": 0.22, "dur": 0.2, "delay": 0.12}]},
	"tick": {"total": 0.06, "layers": [{"wave": "sine", "freq": 1300.0, "vol": 0.12, "dur": 0.04}]},
	"buy": {"total": 0.25, "layers": [{"wave": "sine", "freq": 900.0, "vol": 0.2, "dur": 0.08}, {"wave": "sine", "freq": 1350.0, "vol": 0.2, "dur": 0.14, "delay": 0.07}]},
	"clang": {"total": 0.2, "layers": [{"wave": "square", "freq": 1250.0, "vol": 0.16, "dur": 0.05}, {"wave": "sine", "freq": 1870.0, "vol": 0.16, "dur": 0.16}]},
	"deny": {"total": 0.15, "layers": [{"wave": "square", "freq": 150.0, "vol": 0.2, "dur": 0.12}]},
	"spit": {"total": 0.15, "layers": [{"wave": "noise", "lp": 0.5, "vol": 0.25, "dur": 0.12}, {"wave": "sine", "freq": 300.0, "slide": -150.0, "vol": 0.15, "dur": 0.1}]},
	"charge": {"total": 0.25, "layers": [{"wave": "saw", "freq": 120.0, "slide": 160.0, "vol": 0.15, "dur": 0.22, "swell": 0.8}]},
	"roar": {"total": 0.8, "layers": [{"wave": "saw", "freq": 90.0, "slide": -30.0, "vol": 0.3, "dur": 0.7, "swell": 0.2}, {"wave": "noise", "lp": 0.12, "vol": 0.3, "dur": 0.7, "swell": 0.2}]},
	"slam": {"total": 0.4, "layers": [{"wave": "noise", "lp": 0.08, "vol": 0.5, "dur": 0.35}, {"wave": "sine", "freq": 60.0, "slide": -30.0, "vol": 0.4, "dur": 0.35}]},
	# quái riêng theo khu
	"tell_bell": {"total": 0.5, "layers": [{"wave": "sine", "freq": 880.0, "vol": 0.2, "dur": 0.45, "decay": 1.6}, {"wave": "sine", "freq": 1320.0, "vol": 0.1, "dur": 0.4, "decay": 1.8, "delay": 0.04}]},
	"revive": {"total": 0.35, "layers": [{"wave": "noise", "lp": 0.3, "vol": 0.2, "dur": 0.25}, {"wave": "sine", "freq": 110.0, "slide": 180.0, "vol": 0.25, "dur": 0.3, "swell": 0.5}]},
	"tell_hurl": {"total": 0.5, "layers": [{"wave": "square", "freq": 180.0, "slide": -100.0, "vol": 0.18, "dur": 0.2}, {"wave": "noise", "lp": 0.3, "vol": 0.14, "dur": 0.3}]},
	"tell_undertow": {"total": 0.6, "layers": [{"wave": "sine", "freq": 220.0, "slide": -160.0, "vol": 0.22, "dur": 0.55, "swell": 0.6}, {"wave": "noise", "lp": 0.15, "vol": 0.14, "dur": 0.5}]},
	"tell_cage": {"total": 0.5, "layers": [{"wave": "saw", "freq": 120.0, "slide": 80.0, "vol": 0.16, "dur": 0.35, "swell": 0.6}, {"wave": "noise", "lp": 0.25, "vol": 0.14, "dur": 0.3}]},
	"tell_geyser": {"total": 0.5, "layers": [{"wave": "sine", "freq": 200.0, "slide": 260.0, "vol": 0.2, "dur": 0.4, "swell": 0.6}, {"wave": "noise", "lp": 0.5, "vol": 0.1, "dur": 0.35}]},
	"tell_volley": {"total": 0.5, "layers": [{"wave": "sine", "freq": 420.0, "slide": 160.0, "vol": 0.14, "dur": 0.25}, {"wave": "noise", "lp": 0.6, "vol": 0.08, "dur": 0.2}]},
	"tell_ember": {"total": 0.4, "layers": [{"wave": "noise", "lp": 0.25, "vol": 0.28, "dur": 0.35, "swell": 0.7}, {"wave": "saw", "freq": 80.0, "slide": 60.0, "vol": 0.12, "dur": 0.35}]},
	"ember": {"total": 0.1, "layers": [{"wave": "noise", "lp": 0.6, "vol": 0.14, "dur": 0.08}]},
	"bubble": {"total": 0.2, "layers": [{"wave": "sine", "freq": 300.0, "slide": 500.0, "vol": 0.18, "dur": 0.15}, {"wave": "noise", "lp": 0.7, "vol": 0.06, "dur": 0.1}]},
	"pop": {"total": 0.12, "layers": [{"wave": "sine", "freq": 900.0, "slide": -500.0, "vol": 0.2, "dur": 0.06}, {"wave": "noise", "lp": 0.8, "vol": 0.14, "dur": 0.05}]},
	# bước chân theo mặt sàn (world chọn theo khu / bục gỗ)
	"step_stone": {"total": 0.08, "layers": [{"wave": "noise", "lp": 0.3, "vol": 0.16, "dur": 0.06}, {"wave": "sine", "freq": 140.0, "slide": -60.0, "vol": 0.1, "dur": 0.06}]},
	"step_dirt": {"total": 0.09, "layers": [{"wave": "noise", "lp": 0.12, "vol": 0.2, "dur": 0.08}]},
	"step_metal": {"total": 0.12, "layers": [{"wave": "noise", "lp": 0.7, "vol": 0.08, "dur": 0.04}, {"wave": "sine", "freq": 900.0, "vol": 0.07, "dur": 0.1, "decay": 1.6}]},
	"step_wet": {"total": 0.1, "layers": [{"wave": "noise", "lp": 0.5, "vol": 0.14, "dur": 0.08}, {"wave": "sine", "freq": 500.0, "slide": 300.0, "vol": 0.06, "dur": 0.06}]},
	"step_wood": {"total": 0.08, "layers": [{"wave": "square", "freq": 110.0, "slide": -40.0, "vol": 0.1, "dur": 0.06}, {"wave": "noise", "lp": 0.2, "vol": 0.1, "dur": 0.05}]},
	"boss_die": {"total": 1.3, "layers": [{"wave": "noise", "lp": 0.1, "vol": 0.5, "dur": 1.2}, {"wave": "sine", "freq": 150.0, "slide": -140.0, "vol": 0.4, "dur": 1.0}]},
}

## Vòng lặp dài (xem loop_stream). amb_* = không khí từng khu; final_* = lớp nhạc pha cuối chồng lên bài boss.
const LOOPS: Dictionary = {
	"amb_gate": {"total": 6.0, "layers": [{"wave": "noise", "lp": 0.05, "vol": 0.12, "dur": 6.0, "swell": 0.5}, {"wave": "sine", "freq": 70.0, "vol": 0.05, "dur": 6.0, "swell": 0.5}]},
	"amb_catacomb": {"total": 6.0, "layers": [{"wave": "noise", "lp": 0.03, "vol": 0.1, "dur": 6.0, "swell": 0.4}, {"wave": "sine", "freq": 45.0, "slide": -15.0, "vol": 0.06, "dur": 6.0, "swell": 0.5}, {"wave": "sine", "freq": 1400.0, "slide": -600.0, "vol": 0.05, "dur": 0.05, "delay": 2.2}, {"wave": "sine", "freq": 1400.0, "slide": -600.0, "vol": 0.04, "dur": 0.05, "delay": 4.1}]},
	"amb_vault": {"total": 6.0, "layers": [{"wave": "noise", "lp": 0.3, "vol": 0.06, "dur": 6.0, "swell": 0.5}, {"wave": "saw", "freq": 60.0, "vol": 0.04, "dur": 6.0, "swell": 0.5}, {"wave": "noise", "lp": 0.9, "vol": 0.08, "dur": 0.03, "delay": 1.0}, {"wave": "noise", "lp": 0.9, "vol": 0.08, "dur": 0.03, "delay": 2.7}, {"wave": "noise", "lp": 0.9, "vol": 0.08, "dur": 0.03, "delay": 4.4}]},
	"amb_archive": {"total": 6.0, "layers": [{"wave": "sine", "freq": 200.0, "slide": 60.0, "vol": 0.03, "dur": 6.0, "swell": 0.5}, {"wave": "noise", "lp": 0.15, "vol": 0.08, "dur": 6.0, "swell": 0.5}, {"wave": "sine", "freq": 400.0, "slide": 200.0, "vol": 0.05, "dur": 0.1, "delay": 1.3}, {"wave": "sine", "freq": 400.0, "slide": 200.0, "vol": 0.05, "dur": 0.1, "delay": 3.8}]},
	"amb_grove": {"total": 6.0, "layers": [{"wave": "noise", "lp": 0.08, "vol": 0.09, "dur": 6.0, "swell": 0.5}, {"wave": "sine", "freq": 110.0, "slide": 30.0, "vol": 0.04, "dur": 6.0, "swell": 0.5}, {"wave": "sine", "freq": 165.0, "slide": -20.0, "vol": 0.025, "dur": 6.0, "swell": 0.5, "delay": 1.0}]},
	"final_lord": {"total": 2.0, "layers": [{"wave": "sine", "freq": 55.0, "slide": -20.0, "vol": 0.3, "dur": 0.25, "decay": 2.0}, {"wave": "sine", "freq": 55.0, "slide": -20.0, "vol": 0.3, "dur": 0.25, "decay": 2.0, "delay": 0.5}, {"wave": "sine", "freq": 55.0, "slide": -20.0, "vol": 0.3, "dur": 0.25, "decay": 2.0, "delay": 1.0}, {"wave": "sine", "freq": 55.0, "slide": -20.0, "vol": 0.3, "dur": 0.25, "decay": 2.0, "delay": 1.5}, {"wave": "saw", "freq": 110.0, "vol": 0.06, "dur": 2.0, "swell": 0.5}]},
	"final_many": {"total": 3.0, "layers": [{"wave": "sine", "freq": 220.0, "vol": 0.07, "dur": 3.0, "swell": 0.5}, {"wave": "sine", "freq": 311.0, "vol": 0.07, "dur": 3.0, "swell": 0.5}, {"wave": "noise", "lp": 0.2, "vol": 0.06, "dur": 3.0, "swell": 0.5}, {"wave": "sine", "freq": 880.0, "slide": 440.0, "vol": 0.05, "dur": 1.0, "delay": 1.5, "swell": 0.5}]},
}

static func _mix(total: float, layers: Array, looped: bool = false) -> AudioStreamWAV:
	var n: int = int(float(RATE) * total)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for L in layers:
		var start: int = int(float(RATE) * float(L.get("delay", 0.0)))
		var len_s: int = mini(int(float(RATE) * float(L["dur"])), n - start)
		var freq: float = float(L.get("freq", 0.0))
		var slide: float = float(L.get("slide", 0.0))
		var decay: float = float(L.get("decay", 1.0))
		var lp: float = float(L.get("lp", 1.0))
		var swell: float = float(L.get("swell", 0.0))
		var wave: String = String(L.get("wave", "sine"))
		var phase: float = 0.0
		var lp_state: float = 0.0
		for i in maxi(len_s, 0):
			var k: float = float(i) / float(len_s)
			phase += TAU * (freq + slide * k) / float(RATE)
			var v: float
			match wave:
				"sine": v = sin(phase)
				"square": v = 1.0 if sin(phase) > 0.0 else -1.0
				"saw": v = fmod(phase / TAU, 1.0) * 2.0 - 1.0
				_:
					lp_state += lp * (randf_range(-1.0, 1.0) - lp_state)
					v = lp_state * (1.0 + (1.0 - lp) * 1.5)
			var env: float = pow(1.0 - k, decay) * minf(1.0, float(i) / 66.0)
			if swell > 0.0:
				env = minf(1.0, k / swell) * pow(1.0 - k, decay)
			buf[start + i] += v * env * float(L["vol"])
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w
