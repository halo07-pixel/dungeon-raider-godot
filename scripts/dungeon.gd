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

const CELL_W: int = 24
const CELL_H: int = 16
const GRID_W: int = 5
const GRID_H: int = 5
const DIRS = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Thứ tự file ảnh nạp vào atlas tileset — chỉ số (index) khớp với các hằng T_* bên dưới.
const TILE_FILES: Array = [
	"floor_1.png", "floor_2.png", "floor_3.png", "floor_4.png",
	"floor_5.png", "floor_6.png", "floor_7.png", "floor_8.png",
	"wall_top_left.png", "wall_top_mid.png", "wall_top_right.png",
	"wall_left.png", "wall_right.png",
	"wall_edge_bottom_left.png", "wall_edge_bottom_right.png",
	"wall_mid.png", "column.png", "doors_leaf_closed.png",
]
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


func _ready() -> void:
	add_to_group("dungeon")
	var ts: TileSet = _make_tileset()
	floor_layer = TileMapLayer.new()
	floor_layer.tile_set = ts
	add_child(floor_layer)
	door_layer = TileMapLayer.new()
	door_layer.tile_set = ts
	add_child(door_layer)
	triggers = Node2D.new()
	add_child(triggers)
	entities = Node2D.new()
	entities.y_sort_enabled = false
	add_child(entities)
	Global.world = entities


# ------------------------------------------------------------------ TileSet dựng từ asset CC0 (0x72 DungeonTilesetII)
func _make_tileset() -> TileSet:
	var t: int = Global.TILE
	var ts := TileSet.new()
	ts.tile_size = Vector2i(t, t)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, Global.L_WORLD)
	ts.set_physics_layer_collision_mask(0, 0)

	var n: int = TILE_FILES.size()
	var img := Image.create_empty(t * n, t, false, Image.FORMAT_RGBA8)
	for i in n:
		var src_img := Image.new()
		var err := src_img.load("res://assets/dungeon/" + TILE_FILES[i])
		if err != OK:
			push_error("Không tải được asset tile: " + TILE_FILES[i])
			continue
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


# ------------------------------------------------------------------ Sinh tầng
func generate(floor_number: int) -> void:
	_clear()
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

	for c in rooms:
		_build_room(c, rooms[c])
		
	# === BẢO VỆ PHÒNG BẮT ĐẦU: Luôn luôn an toàn, không có quái ===
	current_cell = start_cell
	rooms[start_cell]["type"] = "start"
	rooms[start_cell]["visited"] = true
	rooms[start_cell]["cleared"] = true
	
	# Bổ sung dòng này để đảm bảo cửa phòng Start luôn mở sẵn
	_unlock_doors(rooms[start_cell])
	
	rooms_updated.emit()


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
			_spawn_spike_traps(cell, randi_range(1, 2))
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
			_spawn_boss(cell)
		"treasure":
			room["cleared"] = true
			
			# LỌC VŨ KHÍ THEO CLASS
			var is_brawler = (Global.current_class == "brawler")
			var valid_weapons: Array = []
			for w_id in Global.weapons:
				if Global.weapons[w_id]["is_melee"] == is_brawler:
					valid_weapons.append(w_id)
			
			var cur_id: String = Global.player.weapon_id
			valid_weapons.erase(cur_id)
			if valid_weapons.is_empty():
				valid_weapons.append(cur_id) # Đề phòng lỗi thiếu đồ
				
			var chosen_weapon: String = valid_weapons.pick_random()
			
			# VÒNG QUAY GACHA ĐỘ HIẾM (50 - 30 - 15 - 5)
			var roll = randi() % 100
			var rarity = "common"
			if roll >= 95:
				rarity = "legendary"
			elif roll >= 80:
				rarity = "epic"
			elif roll >= 50:
				rarity = "rare"
				
			# Nối ID vũ khí và độ hiếm bằng dấu ":"
			_spawn_pickup("weapon", chosen_weapon + ":" + rarity, room_center(cell) + Vector2(0.0, -24.0))
			_spawn_chest_decor(room_center(cell) + Vector2(0.0, 10.0))
			Global.message.emit("Phòng Kho Báu!", Color(1.0, 0.85, 0.3))
		_:
			room["cleared"] = true


func _lock_doors(room: Dictionary) -> void:
	for t in room["door_tiles"]:
		door_layer.set_cell(t, 0, T_DOOR)
	Global.sfx("door")


func _unlock_doors(room: Dictionary) -> void:
	for t in room["door_tiles"]:
		door_layer.erase_cell(t)
	Global.sfx("door")


func _pick_kind() -> String:
	var r: float = randf()
	var brute_p: float = 0.0 if Global.floor_num < 2 else 0.18
	var archer_p: float = 0.25
	if r < brute_p:
		return "brute"
	if r < brute_p + archer_p:
		return "archer"
	return "slime"


func _spawn_wave(cell: Vector2i) -> void:
	var count: int = mini(3 + Global.floor_num + randi_range(0, 2), 10)
	var avoid: Vector2 = Global.player.global_position
	for i in count:
		_spawn_enemy(_pick_kind(), _random_floor_pos(cell, avoid, 200.0), cell)


func _spawn_enemy(kind: String, pos: Vector2, cell: Vector2i) -> void:
	var e = ENEMY.instantiate()
	e.setup(kind, 1.0 + 0.18 * float(Global.floor_num - 1))
	e.died.connect(_on_enemy_died.bind(cell))
	entities.add_child(e)
	e.global_position = pos
	alive_enemies += 1


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


func _spawn_boss(cell: Vector2i) -> void:
	var b = BOSS.instantiate()
	b.setup(1.0 + 0.3 * float(Global.floor_num - 1))
	b.died.connect(_on_boss_died.bind(cell))
	b.summon_requested.connect(_on_summon.bind(cell))
	entities.add_child(b)
	b.global_position = room_center(cell)
	if b.has_method("activate_boss"):
		b.activate_boss()
	boss_alive = true
	Global.boss_spawned.emit(b)
	Global.message.emit("PHÒNG TRÙM!", Color(1.0, 0.3, 0.3))


func _on_summon(kind: String, pos: Vector2, cell: Vector2i) -> void:
	var r: Rect2 = _room_rect(cell, 3)
	var p := Vector2(clampf(pos.x, r.position.x, r.end.x), clampf(pos.y, r.position.y, r.end.y))
	_spawn_enemy(kind, p, cell)


func _on_enemy_died(_enemy, cell: Vector2i) -> void:
	alive_enemies -= 1
	alive_enemies = maxi(alive_enemies, 0)
	if alive_enemies <= 0 and not boss_alive:
		_room_cleared.call_deferred(cell)

func _physics_process(_delta: float) -> void:
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
	if room["type"] == "boss":
		_spawn_pickup("portal", "", room_center(cell))
		Global.message.emit("Cổng xuống tầng đã mở!", Color(0.6, 0.6, 1.0))
	else:
		Global.message.emit("Phòng đã dọn sạch!", Color(0.6, 1.0, 0.6))
		if randf() < 0.35:
			_spawn_pickup("heal", "", room_center(cell))


## Rương trang trí (tĩnh, không va chạm) đặt dưới vũ khí trong phòng Kho báu — chỉ để đẹp,
## vật phẩm thật vẫn là Pickup "weapon" phía trên, nhặt theo logic cũ không đổi.
func _spawn_chest_decor(pos: Vector2) -> void:
	var spr := Sprite2D.new()
	var img := Image.new()
	if img.load("res://assets/dungeon/chest_full_open_anim_f0.png") != OK:
		return
	spr.texture = ImageTexture.create_from_image(img)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(2.0, 2.0)
	entities.add_child(spr)
	spr.global_position = pos


## Thùng gỗ trang trí — chỉ tăng đa dạng hình ảnh cho phòng thường, không va chạm,
## không ảnh hưởng gameplay (giống rương trang trí, nhưng dùng vị trí sàn trống ngẫu nhiên).
func _spawn_crate_decor(cell: Vector2i, count: int) -> void:
	for i in count:
		var pos: Vector2 = _random_floor_pos(cell, Vector2(-99999.0, -99999.0), 0.0)
		var spr := Sprite2D.new()
		var img := Image.new()
		if img.load("res://assets/dungeon/crate.png") != OK:
			return
		spr.texture = ImageTexture.create_from_image(img)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.scale = Vector2(1.6, 1.6)
		entities.add_child(spr)
		spr.global_position = pos


## Bẫy gai sàn — xem scripts/spike_trap.gd để biết chu kỳ an toàn/nguy hiểm và sát thương.
func _spawn_spike_traps(cell: Vector2i, count: int) -> void:
	for i in count:
		var pos: Vector2 = _random_floor_pos(cell, Vector2(-99999.0, -99999.0), 0.0)
		var trap := Area2D.new()
		trap.set_script(SpikeTrapScript)
		entities.add_child(trap)
		trap.global_position = pos


func _spawn_pickup(kind: String, extra: String, pos: Vector2) -> void:
	var p = PICKUP.instantiate()
	p.setup(kind, extra)
	entities.add_child(p)
	p.global_position = pos
