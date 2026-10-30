extends CanvasLayer
## Màn hình tiêu đề: 3 ô save. Up/Down chọn, Jump/Enter chơi (ô trống = ván mới), P hai lần để xoá. Báo lên cha bằng signal `chosen("new"|"continue", slot)`.
const STATE = preload("res://hk/state.gd")
const RUSH = preload("res://hk/rush.gd")
const BACKDROP = preload("res://hk/backdrop.gd")
signal chosen(mode: String, slot: int)
signal sfx(name: String)   # main nối vào SFX: tick khi đổi mục, buy khi chọn, deny khi mục bị khoá
const PERIOD: float = 2400.0      # chu kỳ lặp của các cột nền (như backdrop.gd)
const DRIFT: float = 14.0         # px/giây của lớp gần nhất; lớp xa trôi chậm hơn
const LEAVE_TIME: float = 0.45    # thời gian mờ dần ra đen trước khi phát chosen
var _sel: int = 0
var _info: Array = []           # tóm tắt từng ô save ({} = trống)
var _rush_ok: bool = false     # Boss Rush mở sau ending (mục thứ SLOTS+1)
var _confirm: int = -1          # ô đang chờ bấm P lần nữa để xoá
var _view: Control
var _opened_frame: int = -1
var _t: float = 0.0                # giây từ lúc mở: logo/phụ đề/menu hiện dần theo đây
var _out: float = -1.0             # >= 0: đang mờ ra đen, xong thì phát _pending
var _pending: Array = []
var _pillars: Array = []           # 3 lớp cột nền: [{k, rects: [x, w, h]}]
var _embers: CPUParticles2D

func _ready() -> void:
	layer = 30
	_refresh()
	_rush_ok = RUSH.unlocked()
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
	_build_backdrop()

## Cột nền xa nhiều lớp (cùng bảng màu khu Gate) + tàn lửa bay lên. Chỉ trang trí; tàn lửa và ánh lò tắt theo Atmosphere.
func _build_backdrop() -> void:
	for k in [0.12, 0.25, 0.5]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7 + int(k * 100.0)
		var rects: Array = []
		var x: float = 0.0
		while x < PERIOD:
			var w: float = rng.randf_range(40.0, 100.0) * (1.6 if k < 0.4 else 1.0)
			rects.append([x, w, rng.randf_range(160.0, 520.0), rng.randf() < 0.5])
			x += w + rng.randf_range(60.0, 200.0) * (1.5 if k < 0.4 else 1.0)
		_pillars.append({"k": k, "rects": rects})
	var sz: Vector2 = get_viewport().get_visible_rect().size
	_embers = CPUParticles2D.new()
	_embers.emitting = STATE.atmosphere_on
	_embers.amount = 36
	_embers.lifetime = 7.0
	_embers.preprocess = 7.0
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_embers.emission_rect_extents = Vector2(sz.x * 0.5, 4.0)
	_embers.position = Vector2(sz.x * 0.5, sz.y + 8.0)
	_embers.direction = Vector2(0, -1)
	_embers.spread = 25.0
	_embers.gravity = Vector2(0, -6)
	_embers.initial_velocity_min = 30.0
	_embers.initial_velocity_max = 80.0
	_embers.scale_amount_min = 1.5
	_embers.scale_amount_max = 3.0
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1.0, 0.7, 0.3, 0.9), Color(1.0, 0.4, 0.15, 0.0)])
	_embers.color_ramp = g
	_view.add_child(_embers)

func _refresh() -> void:
	_info = []
	for i in STATE.SLOTS:
		_info.append(STATE.slot_info(i))

func _process(d: float) -> void:
	_t += d
	if _out >= 0.0:   # đang rời màn: bỏ qua phím, mờ dần rồi báo lên cha
		_out += d / LEAVE_TIME
		if _out >= 1.0:
			set_process(false)
			chosen.emit(String(_pending[0]), int(_pending[1]))
			return
		_view.queue_redraw()
		return
	if Engine.get_process_frames() == _opened_frame:
		return
	var n: int = STATE.SLOTS + 1
	if Input.is_action_just_pressed("hk_down"):
		_sel = (_sel + 1) % n
		_confirm = -1
		sfx.emit("tick")
	elif Input.is_action_just_pressed("hk_up"):
		_sel = (_sel - 1 + n) % n
		_confirm = -1
		sfx.emit("tick")
	elif Input.is_action_just_pressed("hk_pin"):
		if _sel >= STATE.SLOTS or _info[_sel].is_empty():
			pass
		elif _confirm == _sel:
			DirAccess.remove_absolute(STATE.slot_path(_sel))
			_confirm = -1
			_refresh()
		else:
			_confirm = _sel
	elif Input.is_action_just_pressed("hk_jump") or Input.is_action_just_pressed("ui_accept"):
		if _sel >= STATE.SLOTS and not _rush_ok:
			sfx.emit("deny")
			return
		sfx.emit("buy")
		_pending = ["rush", 0] if _sel >= STATE.SLOTS else ["new" if _info[_sel].is_empty() else "continue", _sel]
		_out = 0.0
		return
	_view.queue_redraw()

func _draw_view() -> void:
	var v: Control = _view
	var font: Font = ThemeDB.fallback_font
	var sz: Vector2 = v.size
	var pal: Dictionary = BACKDROP.COLORS["gate"]
	v.draw_rect(Rect2(Vector2.ZERO, sz), pal["clear"])
	for L in _pillars:
		var k: float = L["k"]
		var col: Color = pal["clear"].lerp(pal["far"], 0.5) if k < 0.2 else pal["far" if k < 0.4 else "near"]
		var off: float = fmod(_t * DRIFT * k * 2.0, PERIOD)
		for r in L["rects"]:
			for shift in [0.0, PERIOD]:
				var x: float = float(r[0]) + shift - off
				if x > sz.x or x + float(r[1]) < 0.0:
					continue
				v.draw_rect(Rect2(x, sz.y * 0.92 - float(r[2]), float(r[1]), float(r[2]) + sz.y), col)
				if r[3]:
					v.draw_circle(Vector2(x + float(r[1]) * 0.5, sz.y * 0.92 - float(r[2])), float(r[1]) * 0.5, col)
	if STATE.atmosphere_on:   # ánh lò lửa hai bên, nhấp nháy
		for gx in [0.12, 0.88]:
			var fl: float = 0.85 + 0.15 * sin(_t * 7.0 + gx * 9.0) + 0.05 * sin(_t * 17.0)
			for j in 6:
				v.draw_circle(Vector2(sz.x * gx, sz.y * 0.8), (60.0 + j * 38.0) * fl, Color(1.0, 0.55, 0.2, 0.035))
	var a_logo: float = clampf(_t / 1.2, 0.0, 1.0)
	var a_sub: float = clampf((_t - 1.0) / 0.8, 0.0, 1.0)
	var a_menu: float = clampf((_t - 1.5) / 0.6, 0.0, 1.0)
	var rise: float = (1.0 - a_logo) * 18.0
	v.draw_string(font, Vector2(0, sz.y * 0.28 + rise), "DUNGEON RAIDER", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 64, Color(0.92, 0.94, 1.0, a_logo * (0.92 + 0.08 * sin(_t * 2.3))))
	v.draw_string(font, Vector2(0, sz.y * 0.28 + 40), "Descend. Remember. Rise.", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 20, Color(0.6, 0.65, 0.8, a_sub))
	for i in STATE.SLOTS:
		var y: float = sz.y * 0.55 + i * 52.0
		var inf: Dictionary = _info[i]
		var txt: String = "Slot %d   Empty" % (i + 1)
		if _confirm == i:
			txt = "Slot %d   Press P again to erase" % (i + 1)
		elif not inf.is_empty():
			txt = "Slot %d   %s   %d rooms%s" % [i + 1, STATE.fmt_time(float(inf["time"])), int(inf["rooms"]), ("   True End" if inf["true_end"] else ("   Complete" if inf["done"] else ""))]
		var col := Color(0.95, 0.95, 1.0) if not inf.is_empty() else Color(0.6, 0.65, 0.8)
		col.a = a_menu
		if i == _sel:
			v.draw_rect(Rect2(sz.x * 0.5 - 260, y - 30, 520, 42), Color(1, 1, 1, (0.1 + 0.05 * sin(_t * 4.0)) * a_menu))
		v.draw_string(font, Vector2(0, y), txt, HORIZONTAL_ALIGNMENT_CENTER, sz.x, 26, col)
	var ry: float = sz.y * 0.55 + STATE.SLOTS * 52.0
	var rtxt: String = "Boss Rush   locked: defeat the Dungeon Lord"
	if _rush_ok:
		rtxt = "Boss Rush" + ("   Best %s" % RUSH.fmt(RUSH.best()) if RUSH.best() > 0.0 else "")
	if _sel == STATE.SLOTS:
		v.draw_rect(Rect2(sz.x * 0.5 - 260, ry - 30, 520, 42), Color(1, 1, 1, (0.1 + 0.05 * sin(_t * 4.0)) * a_menu))
	var rcol := Color(1.0, 0.8, 0.55) if _rush_ok else Color(0.45, 0.48, 0.58)
	rcol.a = a_menu
	v.draw_string(font, Vector2(0, ry), rtxt, HORIZONTAL_ALIGNMENT_CENTER, sz.x, 26, rcol)
	v.draw_string(font, Vector2(0, sz.y - 40), "Up/Down choose   Jump/Enter play   P erase slot", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 16, Color(0.5, 0.55, 0.65, a_menu))
	if _out >= 0.0:
		v.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, clampf(_out, 0.0, 1.0)))
