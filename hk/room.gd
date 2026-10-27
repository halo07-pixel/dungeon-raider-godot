extends Node2D
## Một phòng dựng từ lưới ký tự (xem hk/world_data.gd): tường đặc, bục một chiều, gai, cửa, bench, bàn thờ, quái.
## Phòng chỉ phát tín hiệu lên (door_entered / hazard_touched / interacted); world quyết định phải làm gì.
signal door_entered(door_id: String)
signal hazard_touched(from_x: float)
signal interacted(kind: String, data: Dictionary)

const TILE: int = 32
const STATE = preload("res://hk/state.gd")
const SPRITES = preload("res://hk/sprites.gd")
const PLAYER = preload("res://hk/player.gd")
const REACH: float = 28.0   # đệm quanh vật thể tương tác (px): đứng sát hình là tương tác được
const BG_DIM: Dictionary = {"gate": 0.3, "catacomb": 0.13, "vault": 0.3, "archive": 0.25}   # độ sáng gạch nền
const TILESET: Dictionary = {"gate": "", "catacomb": "_hell", "vault": "_ice", "archive": ""}   # hậu tố bộ gạch theo khu
const PALETTES: Dictionary = {
	"gate": {"bg": Color(0.05, 0.06, 0.09), "fill": Color(0.13, 0.15, 0.21), "edge": Color(0.40, 0.45, 0.60), "line": Color(0.09, 0.10, 0.15)},
	"catacomb": {"bg": Color(0.07, 0.05, 0.07), "fill": Color(0.19, 0.14, 0.17), "edge": Color(0.62, 0.45, 0.50), "line": Color(0.12, 0.09, 0.11)},
	"vault": {"bg": Color(0.03, 0.06, 0.08), "fill": Color(0.09, 0.17, 0.20), "edge": Color(0.35, 0.65, 0.70), "line": Color(0.06, 0.12, 0.14)},
	"archive": {"bg": Color(0.05, 0.04, 0.09), "fill": Color(0.14, 0.11, 0.22), "edge": Color(0.55, 0.45, 0.75), "line": Color(0.09, 0.07, 0.15)},
}

var id: String = ""
var data: Dictionary = {}
var cols: int = 0
var rows: int = 0
var solids: Array = []          # Rect2 đã gộp
var oneways: Array = []
var hazards: Array = []         # Rect2
var doors: Dictionary = {}      # char -> Rect2
var entities: Array = []        # {type, pos}
var interactables: Array = []   # {rect, kind, data}
var locked: bool = false        # khoá cửa khi đánh boss
var _cells: Array = []
var _pal: Dictionary
var _player: Node2D
var _door_fired: bool = false

func build(room_id: String, room_data: Dictionary) -> void:
	id = room_id
	data = room_data
	_pal = PALETTES[String(data.get("area", "gate"))]
	var grid: Array = data["grid"]
	rows = grid.size()
	cols = 0
	for line in grid:
		cols = maxi(cols, String(line).length())
	_cells = []
	for y in rows:
		var row: String = String(grid[y]).rpad(cols, "#")
		_cells.append(row)
	_parse()
	_make_bodies()

func bounds() -> Rect2:
	return Rect2(0, 0, cols * TILE, rows * TILE)

func _is_solid(x: int, y: int) -> bool:
	var ch: String = _cell(x, y)
	return ch == "#" or ch == "G"

func _cell(x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= cols or y >= rows:
		return "#"
	return String(_cells[y])[x]

## Vùng tương tác = phần nhìn thấy của vật + đệm REACH hai bên và phía trên, nên đứng sát hình là bấm được.
func _add_interactable(kind: String, vis: Rect2, d: Dictionary) -> void:
	interactables.append({"rect": vis.grow_individual(REACH, REACH, REACH, 4.0), "vis": vis, "kind": kind, "data": d})

func _parse() -> void:
	var door_cells: Dictionary = {}
	for y in rows:
		var ow_start: int = -1
		for x in cols + 1:
			var ch: String = _cell(x, y) if x < cols else "."
			var is_ow: bool = ch == "="
			if is_ow and ow_start < 0:
				ow_start = x
			if not is_ow and ow_start >= 0:
				oneways.append(Rect2(ow_start * TILE, y * TILE, (x - ow_start) * TILE, 8))
				ow_start = -1
			if x >= cols:
				continue
			var pos: Vector2 = Vector2(x * TILE + TILE * 0.5, y * TILE + TILE)
			match ch:
				"^": hazards.append(Rect2(x * TILE + 4, y * TILE + 14, TILE - 8, TILE - 14))
				"c", "f", "s", "h", "g", "d": entities.append({"type": ch, "pos": pos if ch != "f" and ch != "d" else pos - Vector2(0, 16)})
				"B": _add_interactable("bench", Rect2(pos.x - 22.0, pos.y - 14.0, 44.0, 14.0), {"pos": pos})
				"M": _add_interactable("merchant", SPRITES.visible_at("wizard_m_idle_anim", 2.0, pos), {})
				"$": _add_interactable("cache", SPRITES.visible_at("chest_full_open_anim", 2.0, pos), {"key": "%s:%d:%d" % [id, x, y], "pos": pos})
				"A": _add_interactable("altar", SPRITES.visible_at("altar_idle", 2.0, pos), data.get("altar", {}))
				"C": _add_interactable("charm", SPRITES.visible_at("altar_idle", 2.0, pos), data.get("charm", {}))
				"X": entities.append({"type": "boss", "pos": pos})
				"@": entities.append({"type": "spawn", "pos": pos})
			if ch.is_valid_int() and ch != "0":
				door_cells[ch] = door_cells.get(ch, []) + [Vector2i(x, y)]
	# gộp theo chiều dọc: các run giống hệt (x, w) ở hàng liên tiếp thành một hình chữ nhật
	var open: Dictionary = {}
	for y in rows + 1:
		var now: Dictionary = {}
		if y < rows:
			var runs2: Array = []
			var rs: int = -1
			for x in cols + 1:
				var ch2: String = _cell(x, y) if x < cols else "."
				var s2: bool = ch2 == "#" or (ch2 == "G" and not STATE.flag(String(data.get("gate_flag", "-"))))
				if s2 and rs < 0:
					rs = x
				if not s2 and rs >= 0:
					runs2.append([rs, x - rs])
					rs = -1
			for r in runs2:
				var key: String = "%d:%d" % [r[0], r[1]]
				now[key] = open[key] if open.has(key) else y
		for key in open:
			if not now.has(key):
				var parts: PackedStringArray = String(key).split(":")
				solids.append(Rect2(int(parts[0]) * TILE, int(open[key]) * TILE, int(parts[1]) * TILE, (y - int(open[key])) * TILE))
		open = now
	for ch in door_cells:
		var r: Rect2
		var first: bool = true
		for c in door_cells[ch]:
			var cr := Rect2(c.x * TILE, c.y * TILE, TILE, TILE)
			r = cr if first else r.merge(cr)
			first = false
		doors[ch] = r

func _make_bodies() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	add_child(body)
	for r in solids:
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = r.size
		cs.shape = sh
		cs.position = r.position + r.size * 0.5
		body.add_child(cs)
	for r in oneways:
		var cs2 := CollisionShape2D.new()
		var sh2 := RectangleShape2D.new()
		sh2.size = r.size
		cs2.shape = sh2
		cs2.position = r.position + r.size * 0.5
		cs2.one_way_collision = true
		body.add_child(cs2)

## Điểm đứng khi đi vào bằng cửa `door_id`: lùi vào trong phòng, phía sau cửa.
func spawn_for_door(door_id: String) -> Vector2:
	var r: Rect2 = doors[door_id]
	var b: Rect2 = bounds()
	var c: Vector2 = r.get_center()
	var dl: float = c.x - b.position.x
	var dr: float = b.end.x - c.x
	var dt: float = c.y - b.position.y
	var db: float = b.end.y - c.y
	var m: float = minf(minf(dl, dr), minf(dt, db))
	if m == dl or m == dr:
		var x: float = r.end.x + 22.0 if m == dl else r.position.x - 22.0
		return Vector2(x, r.end.y - PLAYER.BODY.y * 0.5 - 1.0)
	if m == dt:
		return Vector2(c.x, r.end.y + 40.0)
	# cửa dưới: đứng trên mép sàn ngay cạnh lỗ khoét (không rơi lại xuống cửa)
	var col: int = int(r.position.x / TILE) - 1
	var row: int = int(r.position.y / TILE)
	while row > 0 and _cell(col, row) == "#":
		row -= 1
	return Vector2(float(col) * TILE + TILE * 0.5, float(row + 1) * TILE - PLAYER.BODY.y * 0.5 - 1.0)

func entry_velocity(door_id: String) -> Vector2:
	var r: Rect2 = doors[door_id]
	var b: Rect2 = bounds()
	var c: Vector2 = r.get_center()
	var m: float = minf(minf(c.x - b.position.x, b.end.x - c.x), minf(c.y - b.position.y, b.end.y - c.y))
	if m == c.x - b.position.x:
		return Vector2(180, 0)
	if m == b.end.x - c.x:
		return Vector2(-180, 0)
	if m == c.y - b.position.y:
		return Vector2(0, 200)
	return Vector2.ZERO

func default_spawn() -> Vector2:
	for e in entities:
		if e["type"] == "spawn":
			return e["pos"] - Vector2(0, PLAYER.BODY.y * 0.5 + 1.0)
	var k: String = String(doors.keys()[0]) if not doors.is_empty() else ""
	return spawn_for_door(k) if k != "" else Vector2(64, 64)

func bench_spawn() -> Vector2:
	for it in interactables:
		if it["kind"] == "bench":
			return it["data"]["pos"] - Vector2(0, PLAYER.BODY.y * 0.5 + 1.0)
	return default_spawn()

func set_player(p: Node2D) -> void:
	_player = p

func _physics_process(_d: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var pr := Rect2(_player.global_position - _player.BODY * 0.5, _player.BODY)
	for r in hazards:
		if pr.intersects(r.grow(-2.0)):
			hazard_touched.emit(r.get_center().x)
			break
	if not locked:
		var inside: String = ""
		for ch in doors:
			if pr.intersects(doors[ch]):
				inside = ch
				break
		if inside != "" and not _door_fired:
			_door_fired = true
			door_entered.emit(inside)
		elif inside == "":
			_door_fired = false
	if Input.is_action_just_pressed("hk_up") and _player.controls_enabled:
		for it in interactables:
			if pr.intersects(it["rect"]) and _visible(it):
				interacted.emit(it["kind"], it["data"])
				break
	queue_redraw()

func _visible(it: Dictionary) -> bool:
	var d: Dictionary = it["data"]
	match it["kind"]:
		"altar", "charm":
			var key: String = "got_" + String(d.get("id", ""))
			if STATE.flag(key):
				return false
			var need: String = String(d.get("needs", ""))
			return need == "" or STATE.flag(need)
		"cache":
			return not STATE.flag("cache_" + String(d["key"]))
	return true

func near_prompt() -> bool:
	if _player == null:
		return false
	var pr := Rect2(_player.global_position - _player.BODY * 0.5, _player.BODY)
	for it in interactables:
		if pr.intersects(it["rect"]) and _visible(it):
			return true
	return false

func _draw() -> void:
	var b: Rect2 = bounds()
	# cột nền mờ cho có chiều sâu
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	for i in int(b.size.x / 160.0):
		var cx: float = rng.randf_range(0.0, b.size.x)
		var w: float = rng.randf_range(30.0, 90.0)
		draw_rect(Rect2(cx, b.position.y, w, b.size.y), Color(_pal["fill"], 0.22))
	var sfx: String = String(TILESET.get(String(data.get("area", "gate")), ""))
	# nền: gạch sẫm ở mọi ô trống
	for y in rows:
		for x in cols:
			if not _is_solid(x, y):
				draw_texture_rect(SPRITES.tex("floor_%d%s" % [1 + (x * 7 + y * 13) % 8, sfx]), Rect2(x * TILE, y * TILE, TILE, TILE), false, Color(1, 1, 1) * float(BG_DIM.get(String(data.get("area", "gate")), 0.3)) + Color(0, 0, 0.05, 0.0))
	for y in rows:
		for x in cols:
			if not _is_solid(x, y):
				continue
			var top: bool = not _is_solid(x, y - 1)
			var name: String = ("wall_mid" + sfx) if top else ("floor_%d%s" % [1 + (x * 5 + y * 11) % 8, sfx])
			draw_texture_rect(SPRITES.tex(name), Rect2(x * TILE, y * TILE, TILE, TILE), false, Color.WHITE if top else Color(0.62, 0.62, 0.7))
			if top:
				draw_rect(Rect2(x * TILE, y * TILE, TILE, 3), _pal["edge"])
	for r in oneways:
		for k in int(r.size.x / TILE):
			# dải nhìn thấy của wall_top_mid nằm ở đáy ảnh (4px gốc = 8px): kéo lên để trùng 8px va chạm ở đỉnh ô
			draw_texture_rect(SPRITES.tex("wall_top_mid" + sfx), Rect2(r.position.x + k * TILE, r.position.y - (TILE - r.size.y), TILE, TILE), false)
	for r in hazards:
		# gai vẽ đúng trong vùng gây sát thương r: 3 tam giác (đỉnh ở mép trên r)
		var sw: float = r.size.x / 3.0
		for k in 3:
			var tri := PackedVector2Array([Vector2(r.position.x + k * sw, r.end.y), Vector2(r.position.x + (k + 0.5) * sw, r.position.y), Vector2(r.position.x + (k + 1) * sw, r.end.y)])
			draw_colored_polygon(tri, Color(0.8, 0.84, 0.92))
			draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2]]), Color(0.12, 0.12, 0.2), 2.0)
	for h in data.get("hints", []):   # chữ gợi ý phím: rõ dần khi người chơi lại gần
		var hpos := Vector2(float(h["col"]) * TILE, float(h["row"]) * TILE)
		var a: float = 0.35
		if _player:
			a = clampf(1.5 - _player.global_position.distance_to(hpos) / 350.0, 0.35, 1.0)
		draw_string(ThemeDB.fallback_font, hpos + Vector2(1, 1), String(h["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0, 0, 0, a))
		draw_string(ThemeDB.fallback_font, hpos, String(h["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.95, 0.9, 0.7, a))
	for ch in doors:
		draw_rect(doors[ch], Color(1, 1, 1, 0.04))
	for it in interactables:
		if not _visible(it):
			continue
		var vis: Rect2 = it["vis"]
		var foot := Vector2(vis.get_center().x, vis.end.y)
		var prompt_y: float = vis.position.y - 8.0
		match it["kind"]:
			"bench":
				draw_rect(Rect2(vis.position.x, vis.position.y, vis.size.x, 8.0), Color(0.55, 0.5, 0.45))
				draw_rect(Rect2(vis.position.x + 4.0, vis.position.y + 8.0, 6.0, 6.0), Color(0.4, 0.35, 0.3))
				draw_rect(Rect2(vis.end.x - 10.0, vis.position.y + 8.0, 6.0, 6.0), Color(0.4, 0.35, 0.3))
			"merchant":
				SPRITES.draw_body(self, "wizard_m_idle_anim", foot, 2.0, false, Color.WHITE, 6.0)
			"altar":
				SPRITES.draw_body(self, "altar_idle", foot, 2.0)
				draw_circle(Vector2(foot.x, vis.position.y - 18.0), 12 + sin(Time.get_ticks_msec() * 0.004) * 2.0, Color(1, 0.85, 0.4))
				prompt_y = vis.position.y - 40.0
			"charm":
				SPRITES.draw_body(self, "altar_idle", foot, 2.0)
				draw_circle(Vector2(foot.x, vis.position.y - 14.0), 9, Color(0.5, 0.9, 0.8))
				prompt_y = vis.position.y - 34.0
			"cache":
				SPRITES.draw_body(self, "chest_full_open_anim", foot, 2.0, false, Color.WHITE, 0.0)
		if _player and Rect2(_player.global_position - _player.BODY * 0.5, _player.BODY).intersects(it["rect"]):
			draw_string(ThemeDB.fallback_font, Vector2(foot.x - 10.0, prompt_y), "^", HORIZONTAL_ALIGNMENT_CENTER, 20, 20, Color(1, 1, 1, 0.9))
