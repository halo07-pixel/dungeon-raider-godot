extends CanvasLayer
## Màn hình tiêu đề: 3 ô save. Up/Down chọn, Jump/Enter chơi (ô trống = ván mới), P hai lần để xoá. Báo lên cha bằng signal `chosen("new"|"continue", slot)`.
const STATE = preload("res://hk/state.gd")
signal chosen(mode: String, slot: int)
var _sel: int = 0
var _info: Array = []           # tóm tắt từng ô save ({} = trống)
var _confirm: int = -1          # ô đang chờ bấm P lần nữa để xoá
var _view: Control
var _opened_frame: int = -1

func _ready() -> void:
	layer = 30
	_refresh()
	for i in STATE.SLOTS:
		if not _info[i].is_empty():
			_sel = i
			break
	_opened_frame = Engine.get_process_frames()
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	add_child(_view)

func _refresh() -> void:
	_info = []
	for i in STATE.SLOTS:
		_info.append(STATE.slot_info(i))

func _process(_d: float) -> void:
	if Engine.get_process_frames() == _opened_frame:
		return
	var n: int = STATE.SLOTS
	if Input.is_action_just_pressed("hk_down"):
		_sel = (_sel + 1) % n
		_confirm = -1
	elif Input.is_action_just_pressed("hk_up"):
		_sel = (_sel - 1 + n) % n
		_confirm = -1
	elif Input.is_action_just_pressed("hk_pin"):
		if _info[_sel].is_empty():
			pass
		elif _confirm == _sel:
			DirAccess.remove_absolute(STATE.slot_path(_sel))
			_confirm = -1
			_refresh()
		else:
			_confirm = _sel
	elif Input.is_action_just_pressed("hk_jump") or Input.is_action_just_pressed("ui_accept"):
		set_process(false)
		chosen.emit("new" if _info[_sel].is_empty() else "continue", _sel)
		return
	_view.queue_redraw()

func _draw_view() -> void:
	var v: Control = _view
	var font: Font = ThemeDB.fallback_font
	var sz: Vector2 = v.size
	v.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.02, 0.05))
	v.draw_string(font, Vector2(0, sz.y * 0.28), "DUNGEON RAIDER", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 64, Color(0.92, 0.94, 1.0))
	v.draw_string(font, Vector2(0, sz.y * 0.28 + 40), "Descend. Remember. Rise.", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 20, Color(0.6, 0.65, 0.8))
	for i in STATE.SLOTS:
		var y: float = sz.y * 0.55 + i * 52.0
		var inf: Dictionary = _info[i]
		var txt: String = "Slot %d   Empty" % (i + 1)
		if _confirm == i:
			txt = "Slot %d   Press P again to erase" % (i + 1)
		elif not inf.is_empty():
			txt = "Slot %d   %s   %d rooms%s" % [i + 1, STATE.fmt_time(float(inf["time"])), int(inf["rooms"]), "   Complete" if inf["done"] else ""]
		var col := Color(0.95, 0.95, 1.0) if not inf.is_empty() else Color(0.6, 0.65, 0.8)
		if i == _sel:
			v.draw_rect(Rect2(sz.x * 0.5 - 260, y - 30, 520, 42), Color(1, 1, 1, 0.1))
		v.draw_string(font, Vector2(0, y), txt, HORIZONTAL_ALIGNMENT_CENTER, sz.x, 26, col)
	v.draw_string(font, Vector2(0, sz.y - 40), "Up/Down choose   Jump/Enter play   P erase slot", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 16, Color(0.5, 0.55, 0.65))
