extends CanvasLayer
## Màn kết thúc sau khi hạ Dungeon Lord. Hiện thống kê, Jump/Enter để về màn hình tiêu đề (signal `finished`).
const STATE = preload("res://hk/state.gd")
const WorldData = preload("res://hk/world_data.gd")
signal finished
var _a: float = 0.0
var _view: Control
var _t: float = 0.0
var _stats: String = ""

func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_stats = "Rooms explored: %d / %d     Charms: %d     Geo: %d     Time: %s" % [STATE.visited.size(), WorldData.load_all().size(), STATE.charms_owned.size(), STATE.geo, STATE.fmt_time(STATE.play_time)]
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	add_child(_view)
	create_tween().tween_property(self, "_a", 1.0, 1.5)

func _process(delta: float) -> void:
	_t += delta
	if _t > 2.5 and (Input.is_action_just_pressed("hk_jump") or Input.is_action_just_pressed("ui_accept")):
		set_process(false)
		finished.emit()
		return
	_view.queue_redraw()

func _draw_view() -> void:
	var v: Control = _view
	var font: Font = ThemeDB.fallback_font
	var sz: Vector2 = v.size
	v.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.02, 0.05, _a))
	v.draw_string(font, Vector2(0, sz.y * 0.36), "The Dungeon Lord has fallen", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 44, Color(1, 1, 1, _a))
	v.draw_string(font, Vector2(0, sz.y * 0.36 + 44), "The vaults fall silent. Thank you for playing.", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 20, Color(0.75, 0.8, 0.95, _a))
	v.draw_string(font, Vector2(0, sz.y * 0.56), _stats, HORIZONTAL_ALIGNMENT_CENTER, sz.x, 20, Color(0.95, 0.9, 0.7, _a))
	if _t > 2.5:
		v.draw_string(font, Vector2(0, sz.y - 50), "Jump/Enter: title", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 16, Color(0.6, 0.65, 0.75, 0.6 + 0.4 * sin(_t * 3.0)))
