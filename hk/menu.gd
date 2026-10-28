extends CanvasLayer
## Menu tạm dừng: tab Bản đồ (M), Bùa (E/Tab), Tạm dừng (Esc). Chạy cả khi game đang pause.
const STATE = preload("res://hk/state.gd")
const WorldData = preload("res://hk/world_data.gd")
const LORE = preload("res://hk/lore.gd")
signal volume_changed
const CELL: float = 26.0
const AREA_COLORS: Dictionary = {"gate": Color(0.35, 0.42, 0.62), "catacomb": Color(0.62, 0.4, 0.45), "vault": Color(0.3, 0.6, 0.65), "archive": Color(0.6, 0.5, 0.8)}

var rooms: Dictionary = {}
var enabled: bool = true
var current_room: String = ""
var player_pos: Vector2 = Vector2.ZERO
var tab: String = ""            # "" = đóng
var sel: int = 0
var _view: Control
var _pan: Vector2 = Vector2.ZERO   # kéo bản đồ bằng phím mũi tên

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
		elif Input.is_action_just_pressed("hk_memories"):
			open("memories")
		elif Input.is_action_just_pressed("hk_pause"):
			open("pause")
		return
	if Input.is_action_just_pressed("hk_pause") or (tab == "map" and Input.is_action_just_pressed("hk_map")) or (tab == "charms" and Input.is_action_just_pressed("hk_charms")) or (tab == "memories" and Input.is_action_just_pressed("hk_memories")):
		close()
		return
	if Input.is_action_just_pressed("hk_map") and tab != "map":
		_snapshot()
		tab = "map"
	elif Input.is_action_just_pressed("hk_charms") and tab != "charms":
		tab = "charms"
		sel = 0
	elif Input.is_action_just_pressed("hk_memories") and tab != "memories":
		tab = "memories"
	if tab == "pause":
		sel = (sel + int(Input.is_action_just_pressed("hk_down")) - int(Input.is_action_just_pressed("hk_up")) + 4) % 4
		var step: int = int(Input.is_action_just_pressed("hk_right")) - int(Input.is_action_just_pressed("hk_left"))
		if step != 0:
			if sel == 0:
				STATE.music_vol = clampi(STATE.music_vol + step, 0, 10)
			elif sel == 1:
				STATE.sfx_vol = clampi(STATE.sfx_vol + step, 0, 10)
			elif sel == 2:
				STATE.shake_on = step > 0
			else:
				STATE.atmosphere_on = step > 0
			volume_changed.emit()
	if tab == "map":
		_pan -= Vector2(Input.get_axis("hk_left", "hk_right"), Input.get_axis("hk_up", "hk_down")) * 420.0 * _d
		if Input.is_action_just_pressed("hk_pin") and rooms.has(current_room):
			STATE.toggle_pin(current_room, player_pos)
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
	_pan = Vector2.ZERO
	var w := get_parent()
	if w and w.get("room") and w.room:
		current_room = w.room.id
		player_pos = w.player.global_position

func _draw_view() -> void:
	var v: Control = _view
	var font: Font = ThemeDB.fallback_font
	var sz: Vector2 = v.size
	v.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.03, 0.06, 0.93))
	var tabs: Array = [["map", "MAP (M)"], ["charms", "CHARMS (E)"], ["memories", "MEMORIES (N)"], ["pause", "PAUSE (Esc)"]]
	for i in tabs.size():
		var col := Color(1, 1, 1) if tab == tabs[i][0] else Color(0.45, 0.5, 0.6)
		v.draw_string(font, Vector2(sz.x * 0.5 - 300 + i * 190, 50), tabs[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, col)
	match tab:
		"map": _draw_map(v, font, sz)
		"charms": _draw_charms(v, font, sz)
		"memories": _draw_memories(v, font, sz)
		"pause": _draw_pause(v, font, sz)

## Biểu tượng trong một phòng đã đến: {k: loại, c: (cột, hàng) theo ô lưới}. Chỉ vật chưa lấy/chưa hạ; cửa dẫn tới phòng chưa đến là "exit".
static func map_icons(room: Dictionary) -> Array:
	var out: Array = []
	var grid: Array = room["grid"]
	for y in grid.size():
		var line: String = String(grid[y])
		for x in line.length():
			var ch: String = line[x]
			var c := Vector2(x, y)
			match ch:
				"B": out.append({"k": "bench", "c": c})
				"M": out.append({"k": "shop", "c": c})
				"A":
					if not STATE.flag("got_" + String(room.get("altar", {}).get("id", ""))):
						out.append({"k": "item", "c": c})
				"C":
					if not STATE.flag("got_" + String(room.get("charm", {}).get("id", ""))):
						out.append({"k": "item", "c": c})
				"X":
					if not STATE.flag("boss_" + String(room.get("boss", {}).get("id", ""))):
						out.append({"k": "boss", "c": c})
				"$":
					if not STATE.flag("cache_%s:%d:%d" % [String(room.get("id", "")), x, y]):
						out.append({"k": "cache", "c": c})
	for dch in room["doors"]:
		if not (String(room["doors"][dch]["to"]) in STATE.visited):
			for y in grid.size():
				var xi: int = String(grid[y]).find(String(dch))
				if xi >= 0:
					out.append({"k": "exit", "c": Vector2(xi, y)})
					break
	return out

func _draw_map(v: Control, font: Font, sz: Vector2) -> void:
	if not rooms.has(current_room):
		return
	var cur: Dictionary = rooms[current_room]
	var origin: Vector2 = sz * 0.5 - (cur["map"] + WorldData.map_size(cur) * 0.5) * CELL + _pan
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
			var rd: Dictionary = r.duplicate()
			rd["id"] = id
			for ic in map_icons(rd):
				_draw_icon(v, rect.position + (ic["c"] + Vector2(0.5, 0.5)) / WorldData.MAP_CELL_TILES * CELL, String(ic["k"]))
		else:
			v.draw_rect(rect, Color(0.5, 0.5, 0.55, 0.35), false, 1.5)
		if id == current_room:
			v.draw_rect(rect.grow(2.0), Color(1, 1, 1), false, 3.0)
			var tile: float = 32.0
			var pp: Vector2 = rect.position + Vector2(player_pos.x / tile, player_pos.y / tile) / WorldData.MAP_CELL_TILES * CELL
			v.draw_circle(pp, 4, Color(1, 0.3, 0.3))
	for p in STATE.pins:
		if rooms.has(p["room"]) and String(p["room"]) in STATE.visited:
			var pr: Dictionary = rooms[p["room"]]
			var pp2: Vector2 = origin + pr["map"] * CELL + Vector2(float(p["x"]), float(p["y"])) / 32.0 / WorldData.MAP_CELL_TILES * CELL
			v.draw_colored_polygon(PackedVector2Array([pp2 + Vector2(0, 7), pp2 + Vector2(-5, -5), pp2 + Vector2(5, -5)]), Color(1, 0.3, 0.9))
	v.draw_string(font, Vector2(40, sz.y - 54), "White frame: this room   red dot: you   yellow: bench   cyan: shop   green: item left   red ring: boss   orange: chest   hollow: unexplored exit", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.7, 0.75, 0.85))
	v.draw_string(font, Vector2(40, sz.y - 28), "Arrows: pan the map   P: place / remove a pin here (%d / %d)" % [STATE.pins.size(), STATE.MAX_PINS], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.7, 0.75, 0.85))

func _draw_icon(v: Control, at: Vector2, kind: String) -> void:
	match kind:
		"bench": v.draw_circle(at, 4, Color(1, 0.9, 0.5))
		"shop": v.draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), Color(0.4, 0.9, 1))
		"item": v.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -5), at + Vector2(4, 0), at + Vector2(0, 5), at + Vector2(-4, 0)]), Color(0.5, 1, 0.6))
		"boss":
			v.draw_arc(at, 6, 0, TAU, 16, Color(1, 0.3, 0.3), 2.0)
			v.draw_circle(at, 2, Color(1, 0.3, 0.3))
		"cache": v.draw_rect(Rect2(at - Vector2(3, 2), Vector2(6, 4)), Color(1, 0.65, 0.2))
		"exit": v.draw_arc(at, 4, 0, TAU, 12, Color(1, 1, 1, 0.9), 1.5)

func _draw_charms(v: Control, font: Font, sz: Vector2) -> void:
	v.draw_string(font, Vector2(sz.x * 0.5 - 300, 110), "Notches: %d / %d" % [STATE.notches_used(), STATE.notches()], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.9, 0.6))
	var i: int = 0
	for id in STATE.CHARMS:
		var c: Dictionary = STATE.CHARMS[id]
		var y: float = 150.0 + i * 34.0
		var owned: bool = id in STATE.charms_owned
		var on: bool = id in STATE.charms_equipped
		var col := Color(0.4, 0.42, 0.5) if not owned else (Color(0.6, 1, 0.8) if on else Color(0.95, 0.95, 1))
		if i == sel:
			v.draw_rect(Rect2(sz.x * 0.5 - 320, y - 24, 640, 32), Color(1, 1, 1, 0.1))
		var label: String = String(c["name"]) if owned else "???"
		v.draw_string(font, Vector2(sz.x * 0.5 - 300, y), label + ("   [equipped]" if on else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
		v.draw_string(font, Vector2(sz.x * 0.5 + 220, y), "●".repeat(int(c["cost"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
		i += 1
	var ids: Array = STATE.CHARMS.keys()
	var cid: String = String(ids[clampi(sel, 0, ids.size() - 1)])
	var desc: String = String(STATE.CHARMS[cid]["desc"]) if cid in STATE.charms_owned else "Not found yet."
	v.draw_string(font, Vector2(sz.x * 0.5 - 300, sz.y - 70), desc, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.85, 0.9, 1))
	v.draw_string(font, Vector2(sz.x * 0.5 - 300, sz.y - 40), "Up/Down choose   Jump equip/unequip", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.65, 0.75))

func _draw_memories(v: Control, font: Font, sz: Vector2) -> void:
	v.draw_string(font, Vector2(sz.x * 0.5 - 380, 118.0), "Memories  %d / %d" % [LORE.count(), LORE.MEMORIES.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.95, 0.9, 0.7))
	for i in LORE.MEMORIES.size():
		var m: Dictionary = LORE.MEMORIES[i]
		var got: bool = LORE.has_memory(String(m["id"]))
		var y: float = 170.0 + i * 70.0
		v.draw_string(font, Vector2(sz.x * 0.5 - 380, y), String(m["title"]) if got else "???", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.95, 0.95, 1) if got else Color(0.4, 0.42, 0.5))
		v.draw_string(font, Vector2(sz.x * 0.5 - 380, y + 28), String(m["memory"]) if got else "A boss still holds this memory.", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.75, 0.82, 0.95) if got else Color(0.4, 0.42, 0.5))
	v.draw_string(font, Vector2(sz.x * 0.5 - 380, sz.y - 40), "N or Esc: close", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.65, 0.75))

func _draw_pause(v: Control, font: Font, sz: Vector2) -> void:
	v.draw_string(font, Vector2(sz.x * 0.5 - 380, 118.0), "Play time  " + STATE.fmt_time(STATE.play_time), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.95, 0.9, 0.7))
	var lines: Array = [
		"Move: A/D or arrows      Jump: Z or Space (hold = higher)",
		"Nail: X or J (hold Up/Down to aim; hit enemies below you to bounce)",
		"Dash: C or K (needs Shadow Dash)      Focus (hold, heal): V or L",
		"Soul Bolt: F or I      Interact: Up arrow / W (benches, altars, shop)",
		"Map: M (arrows pan, P pin)      Charms: E or Tab      Memories: N      Close: Esc",
		"",
		"Abilities: " + (", ".join(STATE.abilities.map(func(a): return STATE.ABILITIES[a]["name"])) if not STATE.abilities.is_empty() else "none yet"),
	]
	for i in lines.size():
		v.draw_string(font, Vector2(sz.x * 0.5 - 380, 150.0 + i * 36.0), String(lines[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.9, 0.93, 1))
	var y0: float = 150.0 + lines.size() * 36.0 + 30.0
	var rows: Array = [["Music", STATE.music_vol], ["Effects", STATE.sfx_vol], ["Screen shake", STATE.shake_on], ["Atmosphere", STATE.atmosphere_on]]
	for i in rows.size():
		var y: float = y0 + i * 40.0
		var col := Color(1, 1, 1) if i == sel else Color(0.6, 0.65, 0.75)
		if i == sel:
			v.draw_rect(Rect2(sz.x * 0.5 - 390, y - 26, 560, 38), Color(1, 1, 1, 0.1))
		v.draw_string(font, Vector2(sz.x * 0.5 - 380, y), String(rows[i][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
		if rows[i][1] is bool:
			v.draw_string(font, Vector2(sz.x * 0.5 - 200, y), "On" if rows[i][1] else "Off", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
			continue
		for k in 10:
			v.draw_rect(Rect2(sz.x * 0.5 - 200 + k * 22, y - 18, 18, 20), col if k < int(rows[i][1]) else Color(1, 1, 1, 0.12))
	v.draw_string(font, Vector2(sz.x * 0.5 - 380, y0 + 160), "Up/Down choose   Left/Right change", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.65, 0.75))
