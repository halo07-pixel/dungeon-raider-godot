extends ParallaxBackground
## Nền xa nhiều lớp (cột/vòm tối trôi chậm hơn camera) theo khu. Chỉ trang trí. `set_area` đổi màu và dựng lại.
const COLORS: Dictionary = {
	"gate": {"clear": Color(0.04, 0.045, 0.07), "far": Color(0.07, 0.085, 0.13), "near": Color(0.1, 0.12, 0.18)},
	"catacomb": {"clear": Color(0.05, 0.03, 0.045), "far": Color(0.1, 0.06, 0.08), "near": Color(0.15, 0.09, 0.11)},
	"vault": {"clear": Color(0.02, 0.04, 0.06), "far": Color(0.04, 0.09, 0.12), "near": Color(0.06, 0.13, 0.17)},
	"archive": {"clear": Color(0.04, 0.03, 0.07), "far": Color(0.09, 0.07, 0.15), "near": Color(0.13, 0.10, 0.21)},
}
const PERIOD: float = 2400.0
var _layers: Array = []
var _area: String = "gate"

func _ready() -> void:
	layer = -10
	for k in [0.25, 0.5]:
		var pl := ParallaxLayer.new()
		pl.motion_scale = Vector2(k, 0.15)
		pl.motion_mirroring = Vector2(PERIOD, 0.0)
		var d := Node2D.new()
		d.draw.connect(_draw_layer.bind(d, k))
		pl.add_child(d)
		add_child(pl)
		_layers.append(d)

func set_area(area: String) -> void:
	_area = area if COLORS.has(area) else "gate"
	RenderingServer.set_default_clear_color(COLORS[_area]["clear"])
	for d in _layers:
		d.queue_redraw()

func _draw_layer(d: Node2D, k: float) -> void:
	var col: Color = COLORS[_area]["far" if k < 0.4 else "near"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_area) + int(k * 100.0)
	var x: float = 0.0
	while x < PERIOD:
		var w: float = rng.randf_range(60.0, 150.0) * (1.6 if k < 0.4 else 1.0)
		var h: float = rng.randf_range(500.0, 1500.0)
		d.draw_rect(Rect2(x, 1000.0 - h, w, h + 1200.0), col)
		if rng.randf() < 0.5:   # vòm trên đỉnh cột
			d.draw_circle(Vector2(x + w * 0.5, 1000.0 - h), w * 0.5, col)
		x += w + rng.randf_range(100.0, 320.0) * (1.5 if k < 0.4 else 1.0)
