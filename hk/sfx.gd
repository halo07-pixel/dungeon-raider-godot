extends Node
## Âm thanh hiệu ứng tổng hợp bằng code (không cần file .wav), cùng cách làm với game cũ nhưng độc lập autoload.
## Các node báo lên bằng signal `sfx(name)`; world nối signal đó vào `play`. `history` lưu vài tên gần nhất (cho test).
const RATE: int = 22050
const VOLUME_DB: float = -6.0
var history: Array = []
var _sounds: Dictionary = {}

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
	p.volume_db = VOLUME_DB
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

## Mỗi lớp: freq, slide (Hz trượt hết lớp), vol, dur, wave (sine|square|saw|noise), delay, decay, lp (noise 0..1), swell.
const DEFS: Dictionary = {
	"jump": {"total": 0.14, "layers": [{"wave": "sine", "freq": 330.0, "slide": 280.0, "vol": 0.25, "dur": 0.12}]},
	"double_jump": {"total": 0.2, "layers": [{"wave": "sine", "freq": 440.0, "slide": 420.0, "vol": 0.25, "dur": 0.16}, {"wave": "noise", "lp": 0.3, "vol": 0.12, "dur": 0.14}]},
	"wall_jump": {"total": 0.12, "layers": [{"wave": "square", "freq": 260.0, "slide": 200.0, "vol": 0.14, "dur": 0.09}, {"wave": "noise", "lp": 0.4, "vol": 0.15, "dur": 0.08}]},
	"land": {"total": 0.12, "layers": [{"wave": "noise", "lp": 0.15, "vol": 0.4, "dur": 0.1}, {"wave": "sine", "freq": 90.0, "slide": -40.0, "vol": 0.3, "dur": 0.1}]},
	"dash": {"total": 0.22, "layers": [{"wave": "noise", "lp": 0.5, "vol": 0.35, "dur": 0.2, "decay": 1.5}, {"wave": "saw", "freq": 300.0, "slide": -200.0, "vol": 0.08, "dur": 0.18}]},
	"slash": {"total": 0.12, "layers": [{"wave": "noise", "lp": 0.6, "vol": 0.3, "dur": 0.1}, {"wave": "sine", "freq": 500.0, "slide": -350.0, "vol": 0.12, "dur": 0.08}]},
	"hit": {"total": 0.1, "layers": [{"wave": "noise", "lp": 0.9, "vol": 0.4, "dur": 0.06}, {"wave": "square", "freq": 180.0, "slide": -100.0, "vol": 0.2, "dur": 0.08}]},
	"enemy_die": {"total": 0.3, "layers": [{"wave": "noise", "lp": 0.35, "vol": 0.35, "dur": 0.25}, {"wave": "sine", "freq": 200.0, "slide": -150.0, "vol": 0.25, "dur": 0.25}]},
	"hurt": {"total": 0.3, "layers": [{"wave": "square", "freq": 140.0, "slide": -90.0, "vol": 0.3, "dur": 0.25}, {"wave": "noise", "lp": 0.4, "vol": 0.25, "dur": 0.2}]},
	"die": {"total": 0.9, "layers": [{"wave": "sine", "freq": 220.0, "slide": -200.0, "vol": 0.3, "dur": 0.8}, {"wave": "noise", "lp": 0.1, "vol": 0.3, "dur": 0.6}]},
	"spell": {"total": 0.25, "layers": [{"wave": "saw", "freq": 400.0, "slide": 500.0, "vol": 0.18, "dur": 0.2}, {"wave": "sine", "freq": 900.0, "slide": -600.0, "vol": 0.15, "dur": 0.15}]},
	"heal": {"total": 0.35, "layers": [{"wave": "sine", "freq": 520.0, "vol": 0.25, "dur": 0.12}, {"wave": "sine", "freq": 780.0, "vol": 0.25, "dur": 0.22, "delay": 0.1}]},
	"geo": {"total": 0.18, "layers": [{"wave": "sine", "freq": 1200.0, "vol": 0.2, "dur": 0.07}, {"wave": "sine", "freq": 1600.0, "vol": 0.2, "dur": 0.1, "delay": 0.05}]},
	"bench": {"total": 0.6, "layers": [{"wave": "sine", "freq": 330.0, "vol": 0.2, "dur": 0.5, "swell": 0.2}, {"wave": "sine", "freq": 495.0, "vol": 0.15, "dur": 0.5, "delay": 0.1, "swell": 0.2}]},
	"ability": {"total": 0.75, "layers": [{"wave": "sine", "freq": 440.0, "vol": 0.22, "dur": 0.3}, {"wave": "sine", "freq": 550.0, "vol": 0.22, "dur": 0.3, "delay": 0.1}, {"wave": "sine", "freq": 660.0, "vol": 0.22, "dur": 0.3, "delay": 0.2}, {"wave": "sine", "freq": 880.0, "vol": 0.22, "dur": 0.4, "delay": 0.3}]},
	"charm": {"total": 0.35, "layers": [{"wave": "sine", "freq": 700.0, "vol": 0.22, "dur": 0.15}, {"wave": "sine", "freq": 1050.0, "vol": 0.22, "dur": 0.2, "delay": 0.12}]},
	"buy": {"total": 0.25, "layers": [{"wave": "sine", "freq": 900.0, "vol": 0.2, "dur": 0.08}, {"wave": "sine", "freq": 1350.0, "vol": 0.2, "dur": 0.14, "delay": 0.07}]},
	"deny": {"total": 0.15, "layers": [{"wave": "square", "freq": 150.0, "vol": 0.2, "dur": 0.12}]},
	"spit": {"total": 0.15, "layers": [{"wave": "noise", "lp": 0.5, "vol": 0.25, "dur": 0.12}, {"wave": "sine", "freq": 300.0, "slide": -150.0, "vol": 0.15, "dur": 0.1}]},
	"charge": {"total": 0.25, "layers": [{"wave": "saw", "freq": 120.0, "slide": 160.0, "vol": 0.15, "dur": 0.22, "swell": 0.8}]},
	"roar": {"total": 0.8, "layers": [{"wave": "saw", "freq": 90.0, "slide": -30.0, "vol": 0.3, "dur": 0.7, "swell": 0.2}, {"wave": "noise", "lp": 0.12, "vol": 0.3, "dur": 0.7, "swell": 0.2}]},
	"slam": {"total": 0.4, "layers": [{"wave": "noise", "lp": 0.08, "vol": 0.5, "dur": 0.35}, {"wave": "sine", "freq": 60.0, "slide": -30.0, "vol": 0.4, "dur": 0.35}]},
	"boss_die": {"total": 1.3, "layers": [{"wave": "noise", "lp": 0.1, "vol": 0.5, "dur": 1.2}, {"wave": "sine", "freq": 150.0, "slide": -140.0, "vol": 0.4, "dur": 1.0}]},
}

func _mix(total: float, layers: Array) -> AudioStreamWAV:
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
	return w
