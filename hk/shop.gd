extends CanvasLayer
## Cửa hàng của thương nhân: Up/Down chọn, Jump mua, Esc/Nail thoát. Chạy khi game pause.
const STATE = preload("res://hk/state.gd")
signal sfx(name: String)
var _open: bool = false
var _view: Control
var _sel: int = 0
var _msg: String = ""
var _items: Array = []
var _area: String = ""   # khu của thương nhân ("" = bán tất cả, dùng cho test)
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

func open(_player: Node = null, area: String = "") -> void:
	_area = area
	_items = _stock(_area)
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

## Hàng theo khu: mỗi thương nhân bán bộ bùa riêng; mặt nạ/ô bùa bán theo cấp (khu sau bán cấp cao hơn).
const AREA_CHARMS: Dictionary = {
	"gate": ["swift_edge", "soul_siphon", "fortune"],
	"vault": ["frugal_soul", "spring_nail"],
	"archive": ["second_wind", "shade_cloak"],
}
const AREA_TIER: Dictionary = {"gate": 1, "vault": 2, "archive": 2}   # mặt nạ/notch tối đa mua được ở khu này

## Giá (đã hạ so với bản cũ 120+40*cost / mặt nạ 250+200n / notch 300+250n vì quái chỉ rơi vài Geo).
static func charm_price(cid: String) -> int:
	return 50 + 30 * int(STATE.CHARMS[cid]["cost"])
static func mask_price() -> int:
	return 120 + 100 * STATE.hp_bonus
static func notch_price() -> int:
	return 150 + 120 * STATE.notch_bonus

## Danh sách hàng còn bán, tính lại mỗi lần mở.
func _stock(area: String = "") -> Array:
	var out: Array = []
	var tier: int = int(AREA_TIER.get(area, 2))
	if STATE.hp_bonus < tier:
		out.append({"id": "mask", "name": "Extra Mask", "price": mask_price(), "desc": "+1 mask permanently."})
	if STATE.notch_bonus < tier:
		out.append({"id": "notch", "name": "Charm Notch", "price": notch_price(), "desc": "+1 charm notch."})
	var list: Array = AREA_CHARMS.get(area, ["swift_edge", "soul_siphon", "fortune", "second_wind", "frugal_soul", "spring_nail", "shade_cloak"])
	for cid in list:
		if not (cid in STATE.charms_owned):
			out.append({"id": cid, "name": "Charm: " + String(STATE.CHARMS[cid]["name"]), "price": charm_price(cid), "desc": String(STATE.CHARMS[cid]["desc"])})
	return out

func _buy(it: Dictionary) -> void:
	if STATE.geo < int(it["price"]):
		_msg = "Not enough Geo."
		sfx.emit("deny")
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
	sfx.emit("buy")
	_items = _stock(_area)
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
