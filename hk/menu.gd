extends CanvasLayer
## Menu tạm dừng: tab Bản đồ (M), Bùa (E/Tab), Tạm dừng (Esc). Chạy cả khi game đang pause.
const STATE = preload("res://hk/state.gd")
const WorldData = preload("res://hk/world_data.gd")
signal volume_changed
const CELL: float = 26.0
const AREA_COLORS: Dictionary = {"gate": Color(0.35, 0.42, 0.62), "catacomb": Color(0.62, 0.4, 0.45), "vault": Color(0.3, 0.6, 0.65)}

var rooms: Dictionary = {}
var enabled: bool = true
var current_room: String = ""
var player_pos: Vector2 = Vector2.ZERO
var tab: String = ""            # "" = đóng
var sel: int = 0
var _view: Control

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 15

func _ready() -> void:
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	add_child(_view)
	_view.visible = false

func is_open() -> bool:
	return tab != ""

func open(t: String) -> void:
	tab = t
	sel = 0
	get_tree().paused = true
	_view.visible = true
	_view.queue_redraw()

func close() -> void:
	tab = ""
	get_tree().paused = false
	_view.visible = false
	STATE.save()

func _process(_d: float) -> void:
	if tab == "":
		if not enabled:
			return
		if Input.is_action_just_pressed("hk_map"):
			_snapshot()
			open("map")
		elif Input.is_action_just_pressed("hk_charms"):
			open("charms")
		elif Input.is_action_just_pressed("hk_pause"):
			open("pause")
		return
	if Input.is_action_just_pressed("hk_pause") or (tab == "map" and Input.is_action_just_pressed("hk_map")) or (tab == "charms" and Input.is_action_just_pressed("hk_charms")):
		close()
		return
	if Input.is_action_just_pressed("hk_map") and tab != "map":
		_snapshot()
		tab = "map"
	elif Input.is_action_just_pressed("hk_charms") and tab != "charms":
		tab = "charms"
		sel = 0
	if tab == "pause":
		if Input.is_action_just_pressed("hk_down") or Input.is_action_just_pressed("hk_up"):
			sel = 1 - sel
		var step: int = int(Input.is_action_just_pressed("hk_right")) - int(Input.is_action_just_pressed("hk_left"))
		if step != 0:
			if sel == 0:
				STATE.music_vol = clampi(STATE.music_vol + step, 0, 10)
			else:
				STATE.sfx_vol = clampi(STATE.sfx_vol + step, 0, 10)
			volume_changed.emit()
	if tab == "charms":
		var n: int = STATE.CHARMS.size()
		if Input.is_action_just_pressed("hk_down"):
			sel = (sel + 1) % n
		elif Input.is_action_just_pressed("hk_up"):
			sel = (sel - 1 + n) % n
		elif Input.is_action_just_pressed("hk_jump"):
			STATE.toggle_charm(String(STATE.CHARMS.keys()[sel]))
			var pl := get_tree().get_nodes_in_group("hk_player")
			if not pl.is_empty():
				pl[0].health_changed.emit(STATE.hp, STATE.max_hp())
	_view.queue_redraw()

func _snapshot() -> void:
	var w := get_parent()
	if w and w.get("room") and w.room:
		current_room = w.room.id
		player_pos = w.player.global_position

func _draw_view() -> void:
	var v: Control = _view
	var font: Font = ThemeDB.fallback_font
	var sz: Vector2 = v.size
	v.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.03, 0.06, 0.93))
	var tabs: Array = [["map", "MAP (M)"], ["charms", "CHARMS (E)"], ["pause", "PAUSE (Esc)"]]
	for i in tabs.size():
		var col := Color(1, 1, 1) if tab == tabs[i][0] else Color(0.45, 0.5, 0.6)
		v.draw_string(font, Vector2(sz.x * 0.5 - 300 + i * 220, 50), tabs[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, col)
	match tab:
		"map": _draw_map(v, font, sz)
		"charms": _draw_charms(v, font, sz)
		"pause": _draw_pause(v, font, sz)

func _draw_map(v: Control, font: Font, sz: Vector2) -> void:
	if not rooms.has(current_room):
		return
	var cur: Dictionary = rooms[current_room]
	var origin: Vector2 = sz * 0.5 - (cur["map"] + WorldData.map_size(cur) * 0.5) * CELL
	for id in rooms:
		var r: Dictionary = rooms[id]
		var seen: bool = id in STATE.visited
		var linked: bool = false
		if not seen:
			for other in STATE.visited:
				if rooms.has(other):
					for dd in rooms[other]["doors"].values():
						if dd["to"] == id:
							linked = true
		if not seen and not linked:
			continue
		var rect := Rect2(origin + r["map"] * CELL, WorldData.map_size(r) * CELL)
		var base: Color = AREA_COLORS.get(String(r.get("area", "gate")), Color(0.4, 0.4, 0.5))
		if seen:
			v.draw_rect(rect, base.darkened(0.35))
			v.draw_rect(rect, base, false, 2.0)
			for l in r["grid"]:
				if "B" in String(l):
					v.draw_circle(rect.get_center(), 5, Color(1, 0.9, 0.5))
					break
		else:
			v.draw_rect(rect, Color(0.5, 0.5, 0.55, 0.35), false, 1.5)
		if id == current_room:
			v.draw_rect(rect.grow(2.0), Color(1, 1, 1), false, 3.0)
			var tile: float = 32.0
			var pp: Vector2 = rect.position + Vector2(player_pos.x / tile, player_pos.y / tile) / WorldData.MAP_CELL_TILES * CELL
			v.draw_circle(pp, 4, Color(1, 0.3, 0.3))
	v.draw_string(font, Vector2(40, sz.y - 30), "White frame = this room, yellow dot = bench, red dot = you", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.75, 0.85))

func _draw_charms(v: Control, font: Font, sz: Vector2) -> void:
	v.draw_string(font, Vector2(sz.x * 0.5 - 300, 110), "Notches: %d / %d" % [STATE.notches_used(), STATE.notches()], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.9, 0.6))
	var i: int = 0
	for id in STATE.CHARMS:
		var c: Dictionary = STATE.CHARMS[id]
		var y: float = 150.0 + i * 46.0
		var owned: bool = id in STATE.charms_owned
		var on: bool = id in STATE.charms_equipped
		var col := Color(0.4, 0.42, 0.5) if not owned else (Color(0.6, 1, 0.8) if on else Color(0.95, 0.95, 1))
		if i == sel:
			v.draw_rect(Rect2(sz.x * 0.5 - 320, y - 26, 640, 40), Color(1, 1, 1, 0.1))
		var label: String = String(c["name"]) if owned else "???"
		v.draw_string(font, Vector2(sz.x * 0.5 - 300, y), label + ("   [equipped]" if on else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
		v.draw_string(font, Vector2(sz.x * 0.5 + 220, y), "●".repeat(int(c["cost"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
		i += 1
	var ids: Array = STATE.CHARMS.keys()
	var cid: String = String(ids[clampi(sel, 0, ids.size() - 1)])
	var desc: String = String(STATE.CHARMS[cid]["desc"]) if cid in STATE.charms_owned else "Not found yet."
	v.draw_string(font, Vector2(sz.x * 0.5 - 300, sz.y - 70), desc, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.85, 0.9, 1))
	v.draw_string(font, Vector2(sz.x * 0.5 - 300, sz.y - 40), "Up/Down choose   Jump equip/unequip", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.65, 0.75))

func _draw_pause(v: Control, font: Font, sz: Vector2) -> void:
	var lines: Array = [
		"Move: A/D or arrows      Jump: Z or Space (hold = higher)",
		"Nail: X or J (hold Up/Down to aim; hit enemies below you to bounce)",
		"Dash: C or K (needs Shadow Dash)      Focus (hold, heal): V or L",
		"Soul Bolt: F or I      Interact: Up arrow / W (benches, altars, shop)",
		"Map: M      Charms: E or Tab      Close: Esc",
		"",
		"Abilities: " + (", ".join(STATE.abilities.map(func(a): return STATE.ABILITIES[a]["name"])) if not STATE.abilities.is_empty() else "none yet"),
	]
	for i in lines.size():
		v.draw_string(font, Vector2(sz.x * 0.5 - 380, 150.0 + i * 36.0), String(lines[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.9, 0.93, 1))
	var y0: float = 150.0 + lines.size() * 36.0 + 30.0
	var rows: Array = [["Music", STATE.music_vol], ["Effects", STATE.sfx_vol]]
	for i in rows.size():
		var y: float = y0 + i * 40.0
		var col := Color(1, 1, 1) if i == sel else Color(0.6, 0.65, 0.75)
		if i == sel:
			v.draw_rect(Rect2(sz.x * 0.5 - 390, y - 26, 560, 38), Color(1, 1, 1, 0.1))
		v.draw_string(font, Vector2(sz.x * 0.5 - 380, y), String(rows[i][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
		for k in 10:
			v.draw_rect(Rect2(sz.x * 0.5 - 200 + k * 22, y - 18, 18, 20), col if k < int(rows[i][1]) else Color(1, 1, 1, 0.12))
	v.draw_string(font, Vector2(sz.x * 0.5 - 380, y0 + 100), "Up/Down choose   Left/Right change volume", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.65, 0.75))
