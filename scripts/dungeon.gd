extends Node2D
## Sinh bản đồ: RANDOM-WALK trên lưới phòng GRID_W x GRID_H -> các phòng nối nhau bằng cửa.
## Mỗi phòng = 1 ô lưới CELL_W x CELL_H tile, vẽ vào TileMapLayer có physics (tường/cửa).
## Phòng thường: vào là khoá cửa (tile cửa solid) + sinh quái; dọn sạch -> mở cửa.
## Phòng Trùm = phòng xa Start nhất. Phòng Kho Báu = ngõ cụt (nhặt vũ khí).

signal rooms_updated

const ENEMY = preload("res://scenes/enemy.tscn")
const BOSS = preload("res://scenes/boss.tscn")
const PICKUP = preload("res://scenes/pickup.tscn")
const SpikeTrapScript = preload("res://scripts/spike_trap.gd")
const PoisonTileScript = preload("res://scripts/poison_tile.gd")
const SquadDirectorScript = preload("res://scripts/squad_director.gd")
const LavaTileScript = preload("res://scripts/lava_tile.gd")
const IceTileScript = preload("res://scripts/ice_tile.gd")
## Boss ở các tầng chia hết cho số này rơi thêm 1 vũ khí (tối thiểu Rare). Tầng 5, 10, 15...
const BOSS_WEAPON_REWARD_EVERY: int = 5
const LordArenaRuneScript = preload("res://scripts/lord_arena_rune.gd")
const AffixScript = preload("res://scripts/enemy_affix.gd")
const EventRooms = preload("res://scripts/event_rooms.gd")
const EventPropScript = preload("res://scripts/event_prop.gd")

const CELL_W: int = 24
const CELL_H: int = 16
const GRID_W: int = 5
const GRID_H: int = 5
const DIRS = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Tên tile nền/tường DÙNG CHUNG cho mọi biome (chưa gồm hậu tố) — thứ tự khớp
## chính xác với các hằng T_* bên dưới (index 0-7 = floor, 8-15 = tường, 16 = trụ, 17 = cửa).
## Biome 1 (đá, tầng 1-3) dùng file gốc không hậu tố; Biome 2 (đầm lầy, tầng 4-6) thêm
## hậu tố "_swamp"; Biome 3 + tầng Lord (băng, tầng 7+) thêm hậu tố "_ice".
const TILE_BASE_NAMES: Array = [
	"floor_1", "floor_2", "floor_3", "floor_4",
	"floor_5", "floor_6", "floor_7", "floor_8",
	"wall_top_left", "wall_top_mid", "wall_top_right",
	"wall_left", "wall_right",
	"wall_edge_bottom_left", "wall_edge_bottom_right", "wall_mid",
]
## 2 tile dùng chung, KHÔNG đổi theo biome (trụ đá + cửa gỗ, chi tiết nhỏ không ảnh hưởng cảm giác biome).
const TILE_SHARED_NAMES: Array = ["column", "doors_leaf_closed"]


## Trả về danh sách tên file ảnh (đã gồm .png) cho 1 biome, giữ ĐÚNG thứ tự TILE_BASE_NAMES
## để các hằng T_* (toạ độ atlas cố định) luôn khớp bất kể đang ở biome nào.
func _tile_files_for_biome(biome: String) -> Array:
	var suf: String = "" if biome == "stone" else "_" + biome
	var files: Array = []
	for n in TILE_BASE_NAMES:
		files.append(n + suf + ".png")
	for n in TILE_SHARED_NAMES:
		files.append(n + ".png")
	return files


## Biome 1 (Warden, tầng 1-3): đá · Biome 2 (Necromancer, tầng 4-6): đầm lầy ·
## Biome 3 (Frost, tầng 7-9): băng giá · Biome 4 (Lord, tầng 10+): địa ngục.
func _biome_for_floor(floor_num: int) -> String:
	var k: String = _boss_kind_for_floor(floor_num)
	if k == "necromancer":
		return "swamp"
	elif k == "frost":
		return "ice"
	elif k == "lord":
		return "hell"
	return "stone"
const T_FLOOR_VARIANTS: Array = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
	Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0),
]
const T_WALL_TOP_LEFT := Vector2i(8, 0)
const T_WALL_TOP_MID := Vector2i(9, 0)
const T_WALL_TOP_RIGHT := Vector2i(10, 0)
const T_WALL_LEFT := Vector2i(11, 0)
const T_WALL_RIGHT := Vector2i(12, 0)
const T_WALL_BOTTOM_LEFT := Vector2i(13, 0)
const T_WALL_BOTTOM_RIGHT := Vector2i(14, 0)
const T_WALL_MID := Vector2i(15, 0)
const T_PILLAR := Vector2i(16, 0)
const T_DOOR := Vector2i(17, 0)
## Mọi toạ độ atlas được xem là vật cản (có collision) — dùng để lọc vị trí spawn hợp lệ.
const SOLID_TILES: Array = [
	T_WALL_TOP_LEFT, T_WALL_TOP_MID, T_WALL_TOP_RIGHT, T_WALL_LEFT, T_WALL_RIGHT,
	T_WALL_BOTTOM_LEFT, T_WALL_BOTTOM_RIGHT, T_WALL_MID, T_PILLAR, T_DOOR,
]

var floor_layer: TileMapLayer
var door_layer: TileMapLayer
var entities: Node2D
var triggers: Node2D
var rooms: Dictionary = {}
var start_cell: Vector2i = Vector2i(2, 2)
var boss_cell: Vector2i = Vector2i(2, 2)
var current_cell: Vector2i = Vector2i(2, 2)
var alive_enemies: int = 0
var boss_alive: bool = false
var current_biome: String = "" # "" = chưa dựng tileset lần nào -> generate() đầu tiên sẽ ép dựng lại


var squad: Node = null ## Điều phối nhóm quái (squad_director.gd)

func _ready() -> void:
	add_to_group("dungeon")
	squad = Node.new()
	squad.set_script(SquadDirectorScript)
	squad.name = "SquadDirector"
	add_child(squad)
	floor_layer = TileMapLayer.new()
	add_child(floor_layer)
	door_layer = TileMapLayer.new()
	add_child(door_layer)
	triggers = Node2D.new()
	add_child(triggers)
	entities = Node2D.new()
	entities.y_sort_enabled = false
	add_child(entities)
	Global.world = entities
	Global.weapon_drop_requested.connect(_on_weapon_drop_requested)


## Chỉ dựng lại atlas tileset khi ĐỔI biome (giữa các tầng cùng biome thì giữ nguyên,
## tránh dựng lại ảnh atlas mỗi lần sinh tầng mới không cần thiết).
func _ensure_tileset_for_biome(biome: String) -> void:
	if biome == current_biome:
		return
	current_biome = biome
	var ts: TileSet = _make_tileset(biome)
	floor_layer.tile_set = ts
	door_layer.tile_set = ts


# ------------------------------------------------------------------ TileSet dựng từ asset CC0 (0x72 DungeonTilesetII)
# + 2 bộ biome tự vẽ thêm (đầm lầy "_swamp", băng giá "_ice") qua palette-remap + chi tiết tay.
func _make_tileset(biome: String = "stone") -> TileSet:
	var t: int = Global.TILE
	var ts := TileSet.new()
	ts.tile_size = Vector2i(t, t)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, Global.L_WORLD)
	ts.set_physics_layer_collision_mask(0, 0)

	var tile_files: Array = _tile_files_for_biome(biome)
	var n: int = tile_files.size()
	var img := Image.create_empty(t * n, t, false, Image.FORMAT_RGBA8)
	for i in n:
		var src_tex: Texture2D = Global.load_tex("res://assets/dungeon/" + tile_files[i])
		if src_tex == null:
			push_error("Không tải được asset tile: " + tile_files[i])
			continue
		var src_img: Image = src_tex.get_image()
		if src_img.is_compressed():
			src_img.decompress()
		src_img.convert(Image.FORMAT_RGBA8)
		src_img.resize(t, t, Image.INTERPOLATE_NEAREST)
		img.blit_rect(src_img, Rect2i(Vector2i.ZERO, Vector2i(t, t)), Vector2i(i * t, 0))

	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(t, t)
	ts.add_source(src, 0)
	for i in n:
		src.create_tile(Vector2i(i, 0))

	# Mọi tile từ index 8 trở đi (tường/trụ/cửa) đều đặc — gắn collision hình vuông đầy ô
	var h: float = float(t) / 2.0
	var poly := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	for i in range(8, n):
		var td: TileData = src.get_tile_data(Vector2i(i, 0), 0)
		td.add_collision_polygon(0)
		td.set_collision_polygon_points(0, 0, poly)
	return ts


## Tầng 10 (Dungeon Lord) dùng layout CỐ ĐỊNH riêng thay vì random-walk như các tầng khác:
## chỉ 2 phòng — Start (có thương gia, tuyệt đối an toàn) nối thẳng 1 cửa sang phòng Boss,
## KHÔNG có phòng thường nào để cày máu/dọn quái trước — buộc đối mặt Boss ngay, đúng tinh
## thần "1 phòng spawn + thương gia, 1 phòng boss thật khó" người chơi yêu cầu.
func _generate_lord_floor() -> void:
	_clear()
	_ensure_tileset_for_biome(_biome_for_floor(10))
	start_cell = Vector2i(2, 2)
	boss_cell = Vector2i(3, 2)
	rooms[start_cell] = _new_room("start")
	rooms[boss_cell] = _new_room("boss")
	_connect(start_cell, boss_cell)
	for c in rooms:
		_build_room(c, rooms[c])
	current_cell = start_cell
	rooms[start_cell]["type"] = "start"
	rooms[start_cell]["visited"] = true
	rooms[start_cell]["cleared"] = true
	_unlock_doors(rooms[start_cell])
	_build_nav()
	rooms_updated.emit()


## Đấu trường Hội Đồng Bốn Boss: bố cục cố định như tầng Lord (Start an toàn nối thẳng phòng Boss).
## Gọi sau khi Global.in_council = true; tầng vẫn là 15 (không tăng).
func generate_council_floor() -> void:
	Global.floor_started.emit(Global.floor_num)
	_generate_lord_floor()


# ------------------------------------------------------------------ Sinh tầng
func generate(floor_number: int) -> void:
	Global.floor_started.emit(floor_number) # đặt trước nhánh tầng 10 (return sớm) để mọi tầng đều phát
	if floor_number == 10:
		_generate_lord_floor()
		return
	_clear()
	_ensure_tileset_for_biome(_biome_for_floor(floor_number))
	var target: int = mini(5 + floor_number, 11)
	var cur: Vector2i = Vector2i(2, 2)
	start_cell = cur
	rooms[cur] = _new_room("start")
	var guard: int = 0
	while rooms.size() < target and guard < 1000:
		guard += 1
		var d: Vector2i = DIRS.pick_random()
		var nxt: Vector2i = cur + d
		if nxt.x < 0 or nxt.y < 0 or nxt.x >= GRID_W or nxt.y >= GRID_H:
			continue
		if not rooms.has(nxt):
			rooms[nxt] = _new_room("normal")
		_connect(cur, nxt)
		cur = nxt

	# BFS tìm phòng xa Start nhất -> Phòng Trùm
	var dist: Dictionary = {}
	dist[start_cell] = 0
	var queue: Array = [start_cell]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in rooms[c]["doors"]:
			var n: Vector2i = c + d
			if not dist.has(n):
				dist[n] = int(dist[c]) + 1
				queue.append(n)
	var best: int = -1
	for c in dist:
		if int(dist[c]) > best:
			best = int(dist[c])
			boss_cell = c
	rooms[boss_cell]["type"] = "boss"

	# Kho báu: ưu tiên ngõ cụt
	var cands: Array = []
	for c in rooms:
		if c != start_cell and c != boss_cell and rooms[c]["doors"].size() == 1:
			cands.append(c)
	if cands.is_empty():
		for c in rooms:
			if c != start_cell and c != boss_cell:
				cands.append(c)
	if not cands.is_empty():
		var tc: Vector2i = cands.pick_random()
		rooms[tc]["type"] = "treasure"

	_assign_event_rooms(floor_number)

	for c in rooms:
		_build_room(c, rooms[c])
		
	# === BẢO VỆ PHÒNG BẮT ĐẦU: Luôn luôn an toàn, không có quái ===
	current_cell = start_cell
	rooms[start_cell]["type"] = "start"
	rooms[start_cell]["visited"] = true
	rooms[start_cell]["cleared"] = true
	
	# Bổ sung dòng này để đảm bảo cửa phòng Start luôn mở sẵn
	_unlock_doors(rooms[start_cell])
	
	_build_nav()
	rooms_updated.emit()


## Gán loại phòng sự kiện (Altar/Challenge/Rương Bẫy/Phòng Bí Mật) cho vài phòng thường còn lại,
## ưu tiên ngõ cụt. Dữ liệu và xác suất nằm ở event_rooms.gd.
func _assign_event_rooms(floor_number: int) -> void:
	var dead_ends: Array = []
	var others: Array = []
	for c in rooms:
		if rooms[c]["type"] != "normal":
			continue
		if rooms[c]["doors"].size() == 1:
			dead_ends.append(c)
		else:
			others.append(c)
	dead_ends.shuffle()
	others.shuffle()
	var slots: Array = dead_ends + others
	var picks: Array = EventRooms.pick_for_floor(floor_number, slots.size(), _biome_for_floor(floor_number))
	for i in picks.size():
		rooms[slots[i]]["type"] = picks[i]


func _new_room(type: String) -> Dictionary:
	return {"doors": [], "door_tiles": [], "type": type, "visited": false, "cleared": false}


func _connect(a: Vector2i, b: Vector2i) -> void:
	var d: Vector2i = b - a
	if not rooms[a]["doors"].has(d):
		rooms[a]["doors"].append(d)
	if not rooms[b]["doors"].has(-d):
		rooms[b]["doors"].append(-d)


func _clear() -> void:
	for n in entities.get_children():
		n.queue_free()
	for n in triggers.get_children():
		if n is Area2D:
			n.monitoring = false
		n.queue_free()
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	for b in get_tree().get_nodes_in_group("boss"):
		b.queue_free()
	floor_layer.clear()
	door_layer.clear()
	rooms.clear()
	alive_enemies = 0
	boss_alive = false


# ------------------------------------------------------------------ Dựng 1 phòng
func _build_room(cell: Vector2i, room: Dictionary) -> void:
	var o := Vector2i(cell.x * CELL_W, cell.y * CELL_H)
	for x in CELL_W:
		for y in CELL_H:
			var pos: Vector2i = o + Vector2i(x, y)
			var coord: Vector2i
			if x == 0 and y == 0:
				coord = T_WALL_TOP_LEFT
			elif x == CELL_W - 1 and y == 0:
				coord = T_WALL_TOP_RIGHT
			elif x == 0 and y == CELL_H - 1:
				coord = T_WALL_BOTTOM_LEFT
			elif x == CELL_W - 1 and y == CELL_H - 1:
				coord = T_WALL_BOTTOM_RIGHT
			elif y == 0:
				coord = T_WALL_TOP_MID
			elif y == CELL_H - 1:
				coord = T_WALL_MID
			elif x == 0:
				coord = T_WALL_LEFT
			elif x == CELL_W - 1:
				coord = T_WALL_RIGHT
			else:
				coord = T_FLOOR_VARIANTS.pick_random()
			floor_layer.set_cell(pos, 0, coord)
	for d in room["doors"]:
		for t in _door_tiles(cell, d):
			floor_layer.set_cell(t, 0, T_FLOOR_VARIANTS.pick_random())
			room["door_tiles"].append(t)
	if room["type"] == "normal":
		var spots: Array = [Vector2i(5, 3), Vector2i(17, 3), Vector2i(5, 11), Vector2i(17, 11)]
		spots.shuffle()
		for i in randi_range(0, 3):
			for dx in 2:
				for dy in 2:
					floor_layer.set_cell(o + spots[i] + Vector2i(dx, dy), 0, T_PILLAR)
		if randf() < 0.5:
			_spawn_crate_decor(cell, randi_range(1, 2))
		if randf() < 0.4:
			_spawn_hazard_tiles(cell, randi_range(1, 2))
	# Vùng kích hoạt phòng (Area2D + signal body_entered), thụt vào 2 tile để người chơi vào hẳn mới khoá cửa
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = Global.L_PLAYER
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = _room_rect(cell, 2).size
	shape.shape = rect
	area.add_child(shape)
	area.position = room_center(cell)
	area.body_entered.connect(_on_room_body_entered.bind(cell))
	triggers.add_child(area)


func _door_tiles(cell: Vector2i, d: Vector2i) -> Array:
	var o := Vector2i(cell.x * CELL_W, cell.y * CELL_H)
	var out: Array = []
	var mid_y: int = CELL_H / 2
	var mid_x: int = CELL_W / 2
	for k in range(-1, 2):
		if d == Vector2i(1, 0):
			out.append(o + Vector2i(CELL_W - 1, mid_y + k))
		elif d == Vector2i(-1, 0):
			out.append(o + Vector2i(0, mid_y + k))
		elif d == Vector2i(0, 1):
			out.append(o + Vector2i(mid_x + k, CELL_H - 1))
		else:
			out.append(o + Vector2i(mid_x + k, 0))
	return out


func room_center(cell: Vector2i) -> Vector2:
	return Vector2(float(cell.x * CELL_W) + float(CELL_W) * 0.5, float(cell.y * CELL_H) + float(CELL_H) * 0.5) * float(Global.TILE)


func _room_rect(cell: Vector2i, inset: int = 3) -> Rect2:
	var t: float = float(Global.TILE)
	var pos := Vector2(float(cell.x * CELL_W + inset), float(cell.y * CELL_H + inset)) * t
	var sz := Vector2(float(CELL_W - inset * 2), float(CELL_H - inset * 2)) * t
	return Rect2(pos, sz)


# ------------------------------------------------------------------ Vào phòng / khoá cửa / sinh quái
func _on_room_body_entered(_body: Node, cell: Vector2i) -> void:
	_enter_room.call_deferred(cell)   # đổi tilemap/spawn phải chờ hết physics flush


func _enter_room(cell: Vector2i) -> void:
	if not rooms.has(cell):
		return
	# Chống tín hiệu "ma": khi qua tầng/dịch chuyển, vị trí vật lý của Player còn cũ thêm 1
	# nhịp nên vùng kích hoạt của phòng MỚI (trùng ô lưới với chỗ Player vừa đứng) bắn
	# body_entered nhầm -> kéo Player vào góc phòng đó + khoá cửa/sinh quái. Chỉ xử lý nếu
	# Player THỰC SỰ đang nằm trong phòng này tại thời điểm xử lý (call_deferred đã chờ xong).
	var pl = Global.player
	if is_instance_valid(pl) and not _room_rect(cell, 0).has_point(pl.global_position):
		return
	current_cell = cell
	var room: Dictionary = rooms[cell]
	if room["visited"]:
		return
	room["visited"] = true
	rooms_updated.emit()
	
	var p = Global.player
	if is_instance_valid(p):
		var r: Rect2 = _room_rect(cell, 2)
		p.global_position = p.global_position.clamp(r.position, r.end)
		p.knockback = Vector2.ZERO 
		
	match room["type"]:
		"normal":
			_lock_doors(room)
			_spawn_wave(cell)
		"boss":
			_lock_doors(room)
			if Global.in_council:
				_spawn_council(cell)
			elif is_hell_trial_floor(Global.floor_num):
				_start_hell_trial(cell)
			else:
				_spawn_boss(cell)
		"treasure":
			room["cleared"] = true
			
			# Vũ khí mọi class đều dùng được (không còn lọc theo class); tránh trùng với 2 ô đang cầm.
			var rarity: String = Global.roll_weapon_rarity(Global.floor_num)
			_spawn_pickup("weapon", _roll_weapon_drop(rarity), room_center(cell) + Vector2(0.0, -24.0))
			_spawn_chest_decor(room_center(cell) + Vector2(0.0, 10.0))
			Global.message.emit("Treasure Room!", Color(1.0, 0.85, 0.3))
		"altar":
			room["cleared"] = true
			var altar = _spawn_prop("altar", room_center(cell), cell, {"variant": "gold" if randf() < EventRooms.ALTAR_GOLD_CHANCE else "blood"})
			if altar.variant == "gold":
				Global.message.emit("Gold Altar", Color(1.0, 0.85, 0.3))
			else:
				Global.message.emit("Blood Altar", Color(0.8, 0.45, 0.95))
		"trapped_chest":
			room["cleared"] = true
			_spawn_prop("chest", room_center(cell), cell)
			Global.message.emit("A lone chest...", Color(1.0, 0.85, 0.3))
		"poison_font":
			room["cleared"] = true
			_spawn_prop("font", room_center(cell), cell)
			Global.message.emit("Poison Font", Color(0.4, 0.9, 0.3))
		"frozen_chest":
			room["cleared"] = true
			_spawn_prop("frozen_chest", room_center(cell), cell)
			Global.message.emit("A frozen chest...", Color(0.6, 0.85, 1.0))
		"pact":
			room["cleared"] = true
			_spawn_prop("pact", room_center(cell), cell)
			Global.message.emit("A pact awaits...", Color(1.0, 0.35, 0.15))
		"secret":
			room["cleared"] = true
			_spawn_prop("cache", room_center(cell), cell)
			Global.message.emit("Secret Room!", Color(0.4, 0.9, 0.5))
		"challenge":
			# Không khoá cửa cho tới khi bấm đền: người chơi có thể bỏ qua.
			_spawn_prop("shrine", room_center(cell), cell)
			Global.message.emit("Trial Shrine", Color(1.0, 0.55, 0.2))
		_:
			room["cleared"] = true


## Dựng vật thể tương tác của phòng sự kiện; hành động cần biết phòng (thử thách, Mimic) đi qua signal.
func _spawn_prop(kind: String, pos: Vector2, cell: Vector2i, props: Dictionary = {}) -> Node:
	var prop := Node2D.new()
	prop.set_script(EventPropScript)
	prop.setup(kind)
	for k in props:
		prop.set(k, props[k]) # thuộc tính bổ sung (vd altar variant) đặt TRƯỚC khi vào cây
	prop.action_requested.connect(_on_prop_action.bind(cell))
	entities.add_child(prop)
	prop.global_position = pos
	return prop


func _on_prop_action(action: String, pos: Vector2, cell: Vector2i) -> void:
	match action:
		"start_challenge":
			var room: Dictionary = rooms[cell]
			room["waves_left"] = EventRooms.CHALLENGE_WAVES - 1
			_lock_doors(room)
			Global.message.emit("Wave 1/%d" % EventRooms.CHALLENGE_WAVES, Color(1.0, 0.55, 0.2))
			_spawn_wave(cell, _challenge_wave_size())
		"challenge_choice_done":
			_challenge_close_choices()
		"challenge_gamble":
			_challenge_gamble(cell)
		"spawn_mimic":
			var m = _spawn_enemy("mimic", pos, cell, false)
			m.died.connect(_on_mimic_died)


var _challenge_props: Array = []

func _challenge_close_choices() -> void:
	for pr in _challenge_props:
		if is_instance_valid(pr):
			pr.used = true # chọn một thì cái còn lại bị khóa
	_challenge_props = []


func _challenge_gamble(cell: Vector2i) -> void:
	_challenge_close_choices()
	var room: Dictionary = rooms[cell]
	room["gamble_wave"] = true
	_lock_doors(room)
	var count: int = maxi(4, int(round(float(_challenge_wave_size()) * EventRooms.CHALLENGE_BONUS_WAVE_SCALE)))
	_spawn_wave(cell, count)


func _challenge_gamble_cleared(cell: Vector2i) -> void:
	rooms[cell]["gamble_wave"] = false
	_unlock_doors(rooms[cell])
	rooms_updated.emit()
	_spawn_prop("big_reward", room_center(cell), cell)
	Global.message.emit("Bonus wave cleared!", Color(1.0, 0.85, 0.3))


func _on_mimic_died(_enemy) -> void:
	Global.purple_gems += EventRooms.MIMIC_GEM_REWARD
	Global.save_game()
	Global.message.emit("Mimic defeated: +%d Purple Gem" % EventRooms.MIMIC_GEM_REWARD, Color(0.8, 0.3, 0.9))


func _challenge_wave_size() -> int:
	return maxi(3, int(round(float(_wave_size()) * EventRooms.CHALLENGE_WAVE_SCALE)))


func _lock_doors(room: Dictionary) -> void:
	for t in room["door_tiles"]:
		door_layer.set_cell(t, 0, T_DOOR)
		_nav_set_solid(t, true)
	Global.sfx("door")


func _unlock_doors(room: Dictionary) -> void:
	for t in room["door_tiles"]:
		door_layer.erase_cell(t)
		_nav_set_solid(t, false)
	Global.sfx("door")


# ------------------------------------------------------------------ Tìm đường cho quái
## Lưới A* theo ô tile (AStarGrid2D): tường/trụ/cửa khoá/ô trống là vật cản. Quái chỉ hỏi đường khi
## tia nhìn tới người chơi bị chặn (enemy.gd::_chase_dir); còn thấy thẳng thì vẫn đi thẳng như cũ.
var _astar: AStarGrid2D = null
const NAV_NONE := Vector2i(-999999, -999999)

func _build_nav() -> void:
	var rect: Rect2i = floor_layer.get_used_rect()
	if rect.size == Vector2i.ZERO:
		_astar = null
		return
	_astar = AStarGrid2D.new()
	_astar.region = rect
	_astar.cell_size = Vector2(Global.TILE, Global.TILE)
	_astar.offset = Vector2(Global.TILE, Global.TILE) * 0.5
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES # không cắt góc tường
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := Vector2i(x, y)
			var blocked: bool = floor_layer.get_cell_source_id(c) == -1 \
				or SOLID_TILES.has(floor_layer.get_cell_atlas_coords(c)) \
				or door_layer.get_cell_source_id(c) != -1
			if blocked:
				_astar.set_point_solid(c, true)


func _nav_set_solid(c: Vector2i, solid: bool) -> void:
	if _astar != null and _astar.is_in_boundsv(c):
		_astar.set_point_solid(c, solid)


## Điểm mở gần nhất quanh ô c (bán kính tối đa 2 ô); c nếu đã mở; NAV_NONE nếu không có.
func _nav_open_cell(c: Vector2i) -> Vector2i:
	for r in 3:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if _astar.is_in_boundsv(n) and not _astar.is_point_solid(n):
					return n
	return NAV_NONE


## Đường đi (toạ độ thế giới, tâm ô) từ from tới to; rỗng nếu không có đường.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	if _astar == null:
		return PackedVector2Array()
	var a: Vector2i = _nav_open_cell(floor_layer.local_to_map(floor_layer.to_local(from)))
	var b: Vector2i = _nav_open_cell(floor_layer.local_to_map(floor_layer.to_local(to)))
	if a == NAV_NONE or b == NAV_NONE:
		return PackedVector2Array()
	var pts: PackedVector2Array = _astar.get_point_path(a, b)
	for i in pts.size():
		pts[i] = floor_layer.to_global(pts[i])
	return pts


## Chọn loại quái thường sẽ spawn — tách theo current_biome để 3 biome KHÔNG BAO GIỜ
## lẫn quái của nhau (mỗi biome một bộ quái riêng, yêu cầu rõ từ người chơi).
func _pick_kind() -> String:
	match current_biome:
		"swamp": return _pick_kind_swamp()
		"ice": return _pick_kind_ice()
		"hell": return _pick_kind_hell()
		_: return _pick_kind_stone()


func _pick_kind_stone() -> String:
	var r: float = randf()
	var brute_p: float = 0.0 if Global.floor_num < 2 else 0.18
	var archer_p: float = 0.25
	if r < brute_p:
		return "brute"
	if r < brute_p + archer_p:
		return "archer"
	return "slime"


## Biome 2 (Đầm Lầy): Masked Orc (tank) · Orc Shaman (tầm xa) · Chort (phần còn lại, nhanh nhẹn).
func _pick_kind_swamp() -> String:
	var r: float = randf()
	var tank_p: float = 0.18
	var ranged_p: float = 0.22
	if r < tank_p:
		return "masked_orc"
	if r < tank_p + ranged_p:
		return "shaman"
	return "chort"


## Biome 3 (Băng Giá): Frost Big Zombie (tank) · Frost Tinyling (nhanh, tự nổ) ·
## Frost Zombie (phần còn lại, vai cơ bản).
## Địa Ngục (tầng 11+): bộ quái riêng, giới thiệu dần theo tầng (xem hell_weights).
func _pick_kind_hell() -> String:
	var w: Dictionary = hell_weights(Global.floor_num)
	var total: float = 0.0
	for k in w:
		total += float(w[k])
	var r: float = randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return String(k)
	return "chort"


## Tỉ lệ xuất hiện từng loại quái Địa Ngục theo tầng: 11 Imp + Cinder · 12 thêm Ogre · 13 thêm Acolyte ·
## 14+ dày Ogre/Acolyte hơn. Chort là quái cận chiến nền.
static func hell_weights(floor_num: int) -> Dictionary:
	var w: Dictionary = {"hell_imp": 0.45, "cinder_tiny": 0.35, "chort": 0.20}
	if floor_num >= 12:
		w["hell_ogre"] = 0.22 if floor_num >= 14 else 0.18
	if floor_num >= 13:
		w["hell_acolyte"] = 0.16 if floor_num >= 14 else 0.12
	return w


func _pick_kind_ice() -> String:
	var r: float = randf()
	var tank_p: float = 0.16
	var tiny_p: float = 0.30
	if r < tank_p:
		return "frost_big_zombie"
	if r < tank_p + tiny_p:
		return "frost_tiny"
	return "frost_zombie"


func _wave_size() -> int:
	return mini(3 + Global.floor_num + randi_range(0, 2), 10)


func _spawn_wave(cell: Vector2i, count_override: int = -1) -> void:
	var count: int = count_override if count_override > 0 else _wave_size()
	var avoid: Vector2 = Global.player.global_position
	var affixed: int = 0
	for i in count:
		var e = _spawn_enemy(_pick_kind(), _random_floor_pos(cell, avoid, 200.0), cell, affixed < AffixScript.MAX_PER_ROOM)
		if e.affix_id != "":
			affixed += 1


func _spawn_enemy(kind: String, pos: Vector2, cell: Vector2i, allow_affix: bool = false, hp_mult: float = 1.0) -> Node:
	var e = ENEMY.instantiate()
	e.setup(kind, hp_mult, allow_affix) # HP theo tầng do enemy.gd::setup() nhân đúng 1 lần (Global.hp_scale_for_floor)
	e.squad_register.connect(squad.register)
	e.nav = self # quái hỏi đường qua find_path() khi bị tường chặn
	e.died.connect(_on_enemy_died.bind(cell))
	e.summon_requested.connect(_on_affix_summon.bind(cell))
	e.split_requested.connect(_on_affix_split.bind(cell))
	entities.add_child(e)
	e.global_position = pos
	alive_enemies += 1
	return e


## Affix Summoner: dựng 1 quái nhỏ theo biome cạnh quái triệu hồi; gắn meta để đếm và không rơi xu.
## Affix Splitter: tách quái chết thành SPLIT_COUNT quái nhỏ cùng loại. Chạy TRƯỚC khi _on_enemy_died
## trừ bộ đếm (affix nối signal died sớm hơn dungeon) nên phòng không bị tính là đã dọn sạch.
func _on_affix_split(owner_enemy: Node, cell: Vector2i) -> void:
	if not is_instance_valid(owner_enemy):
		return
	var r: Rect2 = _room_rect(cell, 3)
	for i in AffixScript.SPLIT_COUNT:
		var off := Vector2.from_angle(TAU * float(i) / float(AffixScript.SPLIT_COUNT) + randf() * 0.6) * 26.0
		var p: Vector2 = owner_enemy.global_position + off
		p = Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		var c = _spawn_enemy(owner_enemy.kind, p, cell, false, AffixScript.SPLIT_HP_FRACTION)
		c.set_meta("split_child", true)


func _on_affix_summon(owner_enemy: Node, cell: Vector2i) -> void:
	if not is_instance_valid(owner_enemy) or not owner_enemy.alive:
		return
	var minion_kind: String = "slime"
	match current_biome:
		"swamp": minion_kind = "chort"
		"ice": minion_kind = "frost_tiny"
		"hell": minion_kind = "cinder_tiny"
	var r: Rect2 = _room_rect(cell, 3)
	var off := Vector2.from_angle(randf() * TAU) * 44.0
	var p: Vector2 = owner_enemy.global_position + off
	p = Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	var m = _spawn_enemy(minion_kind, p, cell, false)
	m.set_meta("summoner", owner_enemy)


func _random_floor_pos(cell: Vector2i, avoid: Vector2, min_dist: float) -> Vector2:
	var r: Rect2 = _room_rect(cell, 3)
	for i in 40:
		var cand := Vector2(randf_range(r.position.x, r.end.x), randf_range(r.position.y, r.end.y))
		var tile: Vector2i = floor_layer.local_to_map(cand)
		if SOLID_TILES.has(floor_layer.get_cell_atlas_coords(tile)):
			continue
		if cand.distance_to(avoid) < min_dist:
			continue
		return cand
	return r.get_center()


## Biome 1 (tầng 1-3): Dungeon Warden · Biome 2 (4-6): Dark Necromancer ·
## Biome 3 (7-9): Frozen Horror · Tầng 10 trở lên: Dungeon Lord (boss cuối).
func _boss_kind_for_floor(floor_num: int) -> String:
	if floor_num <= 3:
		return "warden"
	elif floor_num <= 6:
		return "necromancer"
	elif floor_num <= 9:
		return "frost"
	return "lord"


func _spawn_boss(cell: Vector2i) -> void:
	var b = BOSS.instantiate()
	var kind: String = _boss_kind_for_floor(Global.floor_num)
	b.setup(1.0, kind) # HP theo tầng do boss.gd::setup() nhân đúng 1 lần
	b.died.connect(_on_boss_died.bind(cell))
	b.summon_requested.connect(_on_summon.bind(cell))
	entities.add_child(b)
	b.global_position = room_center(cell)
	if b.has_method("set_arena_bounds"):
		b.set_arena_bounds(_room_rect(cell, 3))
	if kind == "lord":
		var rune := Node2D.new()
		rune.set_script(LordArenaRuneScript)
		rune.z_index = -1
		entities.add_child(rune)
		rune.global_position = room_center(cell)
	if b.has_method("activate_boss"):
		b.activate_boss()
	boss_alive = true
	Global.boss_spawned.emit(b)
	Global.message.emit("BOSS ROOM!", Color(1.0, 0.3, 0.3))


func _on_summon(kind: String, pos: Vector2, cell: Vector2i) -> void:
	var r: Rect2 = _room_rect(cell, 3)
	var p := Vector2(clampf(pos.x, r.position.x, r.end.x), clampf(pos.y, r.position.y, r.end.y))
	_spawn_enemy(kind, p, cell, false)


func _on_enemy_died(_enemy, cell: Vector2i) -> void:
	alive_enemies -= 1
	alive_enemies = maxi(alive_enemies, 0)
	if alive_enemies <= 0 and not boss_alive:
		if rooms.has(cell) and rooms[cell].get("gamble_wave", false):
			_challenge_gamble_cleared.call_deferred(cell)
		elif rooms.has(cell) and int(rooms[cell].get("trial_waves_left", 0)) > 0:
			_trial_next_wave.call_deferred(cell)
		elif rooms.has(cell) and rooms[cell]["type"] == "challenge" and int(rooms[cell].get("waves_left", 0)) > 0:
			_challenge_next_wave.call_deferred(cell)
		else:
			_room_cleared.call_deferred(cell)

## Số phòng bí mật chưa vào — chỉ báo cho người chơi sau khi đã dọn Boss của tầng (minimap hiện "?").
func unfound_secret_count() -> int:
	if not rooms.has(boss_cell) or not rooms[boss_cell]["cleared"]:
		return 0
	var n: int = 0
	for c in rooms:
		if rooms[c]["type"] == "secret" and not rooms[c]["visited"]:
			n += 1
	return n


## Phòng bí mật chỉ lộ trên minimap khi người chơi ở phòng kề và đứng gần cửa thông sang nó.
func _update_secret_reveal() -> void:
	var pl = Global.player
	if not is_instance_valid(pl):
		return
	for c in rooms:
		var room: Dictionary = rooms[c]
		if room["type"] != "secret" or room.get("revealed", false):
			continue
		for d in room["doors"]:
			if c + d != current_cell:
				continue
			var door_tile: Vector2i = _door_tiles(current_cell, -d)[1]
			var door_pos: Vector2 = (Vector2(door_tile) + Vector2(0.5, 0.5)) * float(Global.TILE)
			if pl.global_position.distance_to(door_pos) <= EventRooms.SECRET_REVEAL_DIST:
				room["revealed"] = true
				rooms_updated.emit()
				Global.message.emit("You sense a hidden room...", Color(0.4, 0.9, 0.5))


func _physics_process(_delta: float) -> void:
	_update_secret_reveal()
	# Cơ chế phòng hộ: Nếu trong nhóm enemies thực tế không còn con nào sống, tự động mở cửa
	if not rooms.is_empty() and rooms.has(current_cell):
		var room = rooms[current_cell]
		if room["type"] == "normal" and not room["cleared"]:
			
			# === THAY THẾ ĐOẠN ĐẾM QUÁI BẰNG LOGIC NÀY ===
			var actual_alive = 0
			for e in get_tree().get_nodes_in_group("enemies"):
				if e.has_method("kill") and e.alive:
					actual_alive += 1
					
			if actual_alive == 0:
				alive_enemies = 0
				_room_cleared(current_cell)
			# ============================================


func _challenge_next_wave(cell: Vector2i) -> void:
	if not rooms.has(cell) or alive_enemies > 0:
		return
	var room: Dictionary = rooms[cell]
	var left: int = int(room.get("waves_left", 0))
	if left <= 0:
		return
	room["waves_left"] = left - 1
	Global.message.emit("Wave %d/%d" % [EventRooms.CHALLENGE_WAVES - left + 1, EventRooms.CHALLENGE_WAVES], Color(1.0, 0.55, 0.2))
	_spawn_wave(cell, _challenge_wave_size())


## --- Thử Thách Địa Ngục (tầng 11-15): phòng cuối tầng thay Boss bằng nhiều đợt quái đội hình ---
const HELL_FIRST_FLOOR: int = 11
const HELL_LAST_FLOOR: int = 15
const TRIAL_WAVES_DEFAULT: int = 2
const TRIAL_WAVES_FINAL: int = 3          # tầng 15: cửa ải
const TRIAL_WAVE_BASE: int = 6            # số quái mỗi đợt = BASE + (tầng - 10), tối đa TRIAL_WAVE_MAX
const TRIAL_WAVE_MAX: int = 10

static func is_hell_trial_floor(floor_num: int) -> bool:
	return floor_num >= HELL_FIRST_FLOOR and floor_num <= HELL_LAST_FLOOR

static func trial_wave_count(floor_num: int) -> int:
	return TRIAL_WAVES_FINAL if floor_num >= HELL_LAST_FLOOR else TRIAL_WAVES_DEFAULT

static func trial_wave_size(floor_num: int) -> int:
	return mini(TRIAL_WAVE_BASE + maxi(0, floor_num - 10), TRIAL_WAVE_MAX)


func _start_hell_trial(cell: Vector2i) -> void:
	var total: int = trial_wave_count(Global.floor_num)
	var room: Dictionary = rooms[cell]
	room["trial_total"] = total
	room["trial_waves_left"] = total - 1
	Global.sfx("trial_horn")
	Global.message.emit("HELL TRIAL! Wave 1/%d" % total, Color(1.0, 0.35, 0.15))
	_spawn_wave(cell, trial_wave_size(Global.floor_num))


func _trial_next_wave(cell: Vector2i) -> void:
	if not rooms.has(cell) or alive_enemies > 0:
		return
	var room: Dictionary = rooms[cell]
	var left: int = int(room.get("trial_waves_left", 0))
	if left <= 0:
		return
	room["trial_waves_left"] = left - 1
	var total: int = int(room.get("trial_total", 2))
	Global.sfx("trial_horn")
	Global.message.emit("Wave %d/%d" % [total - left + 1, total], Color(1.0, 0.35, 0.15))
	_spawn_wave(cell, trial_wave_size(Global.floor_num))


## --- Hội Đồng Bốn Boss (boss_council.gd) ---
const BossCouncilScript = preload("res://scripts/boss_council.gd")
const COUNCIL_CORNER_INSET: float = 0.30   # vị trí 4 boss: 30% / 70% chiều rộng, cao của phòng
const COUNCIL_GEMS: int = 10

static func council_spawn_points(rect: Rect2) -> Array:
	var xs: Array = [rect.position.x + rect.size.x * COUNCIL_CORNER_INSET, rect.position.x + rect.size.x * (1.0 - COUNCIL_CORNER_INSET)]
	var ys: Array = [rect.position.y + rect.size.y * COUNCIL_CORNER_INSET, rect.position.y + rect.size.y * (1.0 - COUNCIL_CORNER_INSET)]
	return [Vector2(xs[0], ys[0]), Vector2(xs[1], ys[0]), Vector2(xs[0], ys[1]), Vector2(xs[1], ys[1])]


func _spawn_council(cell: Vector2i) -> void:
	var arena: Rect2 = _room_rect(cell, 3)
	var points: Array = council_spawn_points(arena)
	var spawned: Array = []
	for i in BossCouncilScript.KINDS.size():
		var b = BOSS.instantiate()
		b.setup(BossCouncilScript.HP_MULT, String(BossCouncilScript.KINDS[i]))
		b.summon_requested.connect(_on_summon.bind(cell))
		entities.add_child(b)
		b.global_position = points[i]
		b.set_arena_bounds(arena)
		spawned.append(b)
	var council := Node.new()
	council.set_script(BossCouncilScript)
	council.name = "BossCouncil"
	entities.add_child(council)
	council.setup(spawned)
	council.all_defeated.connect(_on_council_defeated.bind(cell))
	for b in spawned:
		b.activate_boss()
	boss_alive = true
	var lord = spawned[spawned.size() - 1]
	Global.boss_spawned.emit(lord) # nhạc Lord + hiện thanh máu; HUD đổi sang 4 thanh ngay sau đó
	Global.council_started.emit(spawned)
	Global.message.emit("THE COUNCIL AWAKENS!", Color(1.0, 0.3, 0.3))


func _on_council_defeated(cell: Vector2i) -> void:
	Global.record_council_clear()
	Global.boss_defeated.emit() # đúng một lần: HUD ẩn thanh, nhạc chiến thắng
	_on_boss_died(cell)


func _on_boss_died(cell: Vector2i) -> void:
	boss_alive = false
	for e in get_tree().get_nodes_in_group("enemies"):
		e.kill()
	if alive_enemies <= 0:
		_room_cleared.call_deferred(cell)


func _room_cleared(cell: Vector2i) -> void:
	if not rooms.has(cell):
		return
	var room: Dictionary = rooms[cell]
	if room["cleared"]:
		return
	room["cleared"] = true
	_unlock_doors(room)
	rooms_updated.emit()
	Global.room_cleared.emit()
	if room["type"] == "boss":
		_spawn_pickup("portal", "", room_center(cell))
		Global.message.emit("The stairs down have opened!", Color(0.6, 0.6, 1.0))
		Global.queue_skill_upgrade_for_floor(Global.floor_num) # nâng cấp kỹ năng được mời SAU lượt chọn buff bên dưới
		if Global.in_council:
			# Phần thưởng Hội Đồng: vũ khí Huyền thoại + ngọc tím
			_spawn_pickup("weapon", _roll_weapon_drop("legendary"), room_center(cell) + Vector2(-72.0, 0.0))
			Global.purple_gems += COUNCIL_GEMS
			Global.save_game()
			Global.message.emit("The Council has fallen! Legendary weapon and +%d Purple Gems" % COUNCIL_GEMS, Color(1.0, 0.85, 0.3))
		elif Global.floor_num % BOSS_WEAPON_REWARD_EVERY == 0:
			_spawn_pickup("weapon", _roll_weapon_drop(Global.roll_weapon_rarity(Global.floor_num, "rare")), room_center(cell) + Vector2(-72.0, 0.0))
			Global.message.emit("The boss dropped a weapon!", Color(1.0, 0.85, 0.3))
		if Global.floor_num == HELL_LAST_FLOOR and not Global.in_council:
			_spawn_pickup("council_portal", "", room_center(cell) + Vector2(0.0, 70.0))
			Global.message.emit("A crimson gate opens: the Council awaits", Color(1.0, 0.4, 0.3))
		# Cân bằng lại: trước đây mời chọn buff sau MỌI phòng dọn sạch (quá dễ cày),
		# giờ chỉ 1 lần chọn buff duy nhất mỗi tầng, ngay sau khi hạ Boss.
		Global.request_buff_choice()
	elif room["type"] == "challenge":
		# Hai lựa chọn: nhận thưởng ngay (an toàn) hoặc cược thêm một đợt để lấy thưởng lớn.
		_challenge_props = [
			_spawn_prop("reward", room_center(cell) + Vector2(-48.0, 0.0), cell),
			_spawn_prop("gamble", room_center(cell) + Vector2(48.0, 0.0), cell)]
		Global.message.emit("Trial cleared! Take the reward or gamble", Color(1.0, 0.85, 0.3))
	else:
		Global.message.emit("Room cleared!", Color(0.6, 1.0, 0.6))
		if randf() < 0.35:
			_spawn_pickup("heal", "", room_center(cell))


## Chuỗi "id:rarity" cho một vũ khí rơi mới, tránh trùng id với các ô Player đang cầm.
func _roll_weapon_drop(rarity: String) -> String:
	var held: Array = []
	if is_instance_valid(Global.player):
		for slot in Global.player.weapon_slots:
			if not slot.is_empty():
				held.append(String(slot["id"]))
	return Global.random_weapon_id(held) + ":" + rarity


## Player đổi vũ khí tại chỗ (nhặt bằng E khi đủ ô): đặt vũ khí cũ xuống sàn để còn nhặt lại được.
func _on_weapon_drop_requested(w_id: String, rarity: String, pos: Vector2) -> void:
	_spawn_pickup("weapon", w_id + ":" + rarity, pos)


## Rương trang trí (tĩnh, không va chạm) đặt dưới vũ khí trong phòng Kho báu — chỉ để đẹp,
## vật phẩm thật vẫn là Pickup "weapon" phía trên, nhặt theo logic cũ không đổi.
## Dùng frame f2 (rương đã mở nắp) thay vì f0 (đóng) vì không có cơ chế "mở rương" —
## vật phẩm đã nổi sẵn bên trên nên hiển thị rương đóng sẽ gây hiểu lầm là cần mở khoá.
func _spawn_chest_decor(pos: Vector2) -> void:
	var tex := Global.load_tex("res://assets/dungeon/chest_full_open_anim_f2.png")
	if tex == null:
		return
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(2.0, 2.0)
	entities.add_child(spr)
	spr.global_position = pos


## Thùng gỗ trang trí — chỉ tăng đa dạng hình ảnh cho phòng thường, không va chạm,
## không ảnh hưởng gameplay (giống rương trang trí, nhưng dùng vị trí sàn trống ngẫu nhiên).
func _spawn_crate_decor(cell: Vector2i, count: int) -> void:
	var tex := Global.load_tex("res://assets/dungeon/crate.png")
	if tex == null:
		return
	for i in count:
		var pos: Vector2 = _random_floor_pos(cell, Vector2(-99999.0, -99999.0), 0.0)
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.scale = Vector2(1.6, 1.6)
		entities.add_child(spr)
		spr.global_position = pos


## Sinh bẫy sàn ĐÚNG LOẠI theo biome hiện tại: đá -> bẫy gai (chu kỳ an toàn/nguy hiểm,
## xem spike_trap.gd), đầm lầy -> Ô Độc (sát thương liên tục, xem poison_tile.gd),
## băng giá -> Ô Băng (sát thương nhẹ + trượt mất kiểm soát, xem ice_tile.gd).
func _spawn_hazard_tiles(cell: Vector2i, count: int) -> void:
	var script: Script = SpikeTrapScript
	if current_biome == "swamp":
		script = PoisonTileScript
	elif current_biome == "ice":
		script = IceTileScript
	elif current_biome == "hell":
		script = LavaTileScript
		count = clampi(count, 1, 3)
	for i in count:
		var pos: Vector2 = _random_floor_pos(cell, Vector2(-99999.0, -99999.0), 0.0)
		var trap := Area2D.new()
		trap.set_script(script)
		entities.add_child(trap)
		trap.global_position = pos


func _spawn_pickup(kind: String, extra: String, pos: Vector2) -> void:
	var p = PICKUP.instantiate()
	p.setup(kind, extra)
	entities.add_child(p)
	p.global_position = pos
