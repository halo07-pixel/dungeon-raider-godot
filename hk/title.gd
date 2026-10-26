extends CanvasLayer
## Màn hình tiêu đề: Up/Down chọn, Jump/Enter xác nhận. Báo lên cha bằng signal `chosen("new"|"continue")`.
const STATE = preload("res://hk/state.gd")
signal chosen(mode: String)
var _sel: int = 0
var _has_save: bool = false
var _view: Control
var _opened_frame: int = -1

func _ready() -> void:
	layer = 30
	_has_save = FileAccess.file_exists(STATE.save_path)
	_sel = 1 if _has_save else 0
	_opened_frame = Engine.get_process_frames()
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	add_child(_view)

func _items() -> Array:
	return [{"id": "new", "name": "New Game", "on": true}, {"id": "continue", "name": "Continue", "on": _has_save}]

func _process(_d: float) -> void:
	if Engine.get_process_frames() == _opened_frame:
		return
	var n: int = _items().size()
	if Input.is_action_just_pressed("hk_down"):
		_sel = (_sel + 1) % n
	elif Input.is_action_just_pressed("hk_up"):
		_sel = (_sel - 1 + n) % n
	elif Input.is_action_just_pressed("hk_jump") or Input.is_action_just_pressed("ui_accept"):
		var it: Dictionary = _items()[_sel]
		if it["on"]:
			set_process(false)
			chosen.emit(String(it["id"]))
			return
	_view.queue_redraw()

func _draw_view() -> void:
	var v: Control = _view
	var font: Font = ThemeDB.fallback_font
	var sz: Vector2 = v.size
	v.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.02, 0.05))
	v.draw_string(font, Vector2(0, sz.y * 0.28), "DUNGEON RAIDER", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 64, Color(0.92, 0.94, 1.0))
	v.draw_string(font, Vector2(0, sz.y * 0.28 + 40), "Descend. Remember. Rise.", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 20, Color(0.6, 0.65, 0.8))
	var items: Array = _items()
	for i in items.size():
		var it: Dictionary = items[i]
		var y: float = sz.y * 0.55 + i * 52.0
		var col := Color(0.95, 0.95, 1.0) if it["on"] else Color(0.35, 0.35, 0.42)
		if i == _sel:
			v.draw_rect(Rect2(sz.x * 0.5 - 140, y - 30, 280, 42), Color(1, 1, 1, 0.1))
		v.draw_string(font, Vector2(0, y), String(it["name"]), HORIZONTAL_ALIGNMENT_CENTER, sz.x, 28, col)
	v.draw_string(font, Vector2(0, sz.y - 40), "Up/Down choose   Jump/Enter confirm", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 16, Color(0.5, 0.55, 0.65))
