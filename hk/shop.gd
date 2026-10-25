extends CanvasLayer
## Cửa hàng của thương nhân: Up/Down chọn, Jump mua, Esc/Nail thoát. Chạy khi game pause.
const STATE = preload("res://hk/state.gd")
var _open: bool = false
var _view: Control
var _sel: int = 0
var _msg: String = ""
var _items: Array = []
var _opened_frame: int = -1   # phím mở shop (Up) còn "just pressed" trong khung này: bỏ qua để không dịch lựa chọn

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 16

func _ready() -> void:
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	add_child(_view)
	_view.visible = false

func is_open() -> bool:
	return _open

func open(_player: Node = null) -> void:
	_items = _stock()
	_sel = 0
	_msg = ""
	_open = true
	_opened_frame = Engine.get_process_frames()
	get_tree().paused = true
	_view.visible = true
	_view.queue_redraw()

func close() -> void:
	_open = false
	get_tree().paused = false
	_view.visible = false
	STATE.save()

## Danh sách hàng còn bán, tính lại mỗi lần mở.
func _stock() -> Array:
	var out: Array = []
	if STATE.hp_bonus < 2:
		out.append({"id": "mask", "name": "Extra Mask", "price": 250 + 200 * STATE.hp_bonus, "desc": "+1 mask permanently."})
	if STATE.notch_bonus < 2:
		out.append({"id": "notch", "name": "Charm Notch", "price": 300 + 250 * STATE.notch_bonus, "desc": "+1 charm notch."})
	for cid in ["swift_edge", "soul_siphon", "fortune"]:
		if not (cid in STATE.charms_owned):
			out.append({"id": cid, "name": "Charm: " + String(STATE.CHARMS[cid]["name"]), "price": 120 + 40 * int(STATE.CHARMS[cid]["cost"]), "desc": String(STATE.CHARMS[cid]["desc"])})
	return out

func _buy(it: Dictionary) -> void:
	if STATE.geo < int(it["price"]):
		_msg = "Not enough Geo."
		return
	STATE.geo -= int(it["price"])
	match String(it["id"]):
		"mask":
			STATE.hp_bonus += 1
			STATE.hp = STATE.max_hp()
		"notch":
			STATE.notch_bonus += 1
		_:
			STATE.give_charm(String(it["id"]))
	_msg = "Thank you."
	_items = _stock()
	_sel = clampi(_sel, 0, maxi(0, _items.size() - 1))
	var pl := get_tree().get_nodes_in_group("hk_player")
	if not pl.is_empty():
		pl[0].health_changed.emit(STATE.hp, STATE.max_hp())

func _process(_d: float) -> void:
	if not _open:
		return
	if Engine.get_process_frames() == _opened_frame:
		return
	if Input.is_action_just_pressed("hk_pause") or Input.is_action_just_pressed("hk_attack"):
		close()
		return
	if not _items.is_empty():
		if Input.is_action_just_pressed("hk_down"):
			_sel = (_sel + 1) % _items.size()
		elif Input.is_action_just_pressed("hk_up"):
			_sel = (_sel - 1 + _items.size()) % _items.size()
		elif Input.is_action_just_pressed("hk_jump"):
			_buy(_items[_sel])
	_view.queue_redraw()

func _draw_view() -> void:
	var v: Control = _view
	var font: Font = ThemeDB.fallback_font
	var sz: Vector2 = v.size
	v.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.03, 0.02, 0.06, 0.93))
	v.draw_string(font, Vector2(sz.x * 0.5 - 300, 80), "Wandering Merchant", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(0.85, 0.75, 1))
	v.draw_string(font, Vector2(sz.x * 0.5 + 100, 80), "Geo: %d" % STATE.geo, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 0.9, 0.5))
	if _items.is_empty():
		v.draw_string(font, Vector2(sz.x * 0.5 - 300, 160), "Nothing left to sell.", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.8, 0.8, 0.9))
	for i in _items.size():
		var y: float = 150.0 + i * 48.0
		if i == _sel:
			v.draw_rect(Rect2(sz.x * 0.5 - 320, y - 28, 640, 42), Color(1, 1, 1, 0.1))
		var it: Dictionary = _items[i]
		var col := Color(0.95, 0.95, 1) if STATE.geo >= int(it["price"]) else Color(0.5, 0.5, 0.6)
		v.draw_string(font, Vector2(sz.x * 0.5 - 300, y), String(it["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
		v.draw_string(font, Vector2(sz.x * 0.5 + 200, y), "%d" % int(it["price"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
	if not _items.is_empty():
		v.draw_string(font, Vector2(sz.x * 0.5 - 300, sz.y - 110), String(_items[_sel]["desc"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.85, 0.9, 1))
	v.draw_string(font, Vector2(sz.x * 0.5 - 300, sz.y - 76), _msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.9, 0.6))
	v.draw_string(font, Vector2(sz.x * 0.5 - 300, sz.y - 40), "Up/Down choose   Jump buy   Esc/Nail leave", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.65, 0.75))
