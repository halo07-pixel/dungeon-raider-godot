extends Node2D
## Thế giới: nạp phòng, chuyển cửa, bench, chết/shade, tương tác (bàn thờ, bùa, thương nhân), boss, menu.
const STATE = preload("res://hk/state.gd")
const WorldData = preload("res://hk/world_data.gd")
const InputSetup = preload("res://hk/input.gd")
const FX = preload("res://hk/fx.gd")
const AREA_NAMES: Dictionary = {"gate": "Gate Ruins", "catacomb": "Weeping Catacombs", "vault": "Ashen Vaults"}
const ZOOM: float = 1.5

var rooms: Dictionary = {}
var room: Node2D
var player: CharacterBody2D
var cam: Camera2D
var hud: Control
var menu: Node
var shop: Node
var busy: bool = false
var entry_spawn: Vector2 = Vector2.ZERO
var boss: Node2D
var _content: Node2D
var _fade: ColorRect
var _last_area: String = ""

func _ready() -> void:
	InputSetup.ensure()
	rooms = WorldData.load_all()
	match STATE.boot:
		"new":
			STATE.reset()
			STATE.delete_save()
		"continue":
			if not STATE.load_save():
				STATE.reset()
	STATE.boot = "keep"
	if not rooms.has(STATE.bench_room):
		STATE.bench_room = STATE.START_ROOM
		STATE.bench_id = "start"
	player = CharacterBody2D.new()
	player.set_script(preload("res://hk/player.gd"))
	add_child(player)
	cam = Camera2D.new()
	cam.set_script(preload("res://hk/camera.gd"))
	cam.zoom = Vector2(ZOOM, ZOOM)
	add_child(cam)
	cam.make_current()
	_build_ui()
	player.hit_landed.connect(cam.shake)
	player.health_changed.connect(hud.set_health)
	player.soul_changed.connect(hud.set_soul)
	player.died.connect(_on_player_died)
	player.hazard_hit.connect(_on_hazard)
	hud.set_health(STATE.hp, STATE.max_hp())
	hud.set_soul(STATE.soul)
	load_room(STATE.bench_room)
	var at_start: bool = STATE.bench_id == "start"
	player.respawn_at(room.default_spawn() if at_start else room.bench_spawn(), true)
	entry_spawn = player.global_position
	cam.global_position = player.global_position
	cam.reset_smoothing()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	hud = Control.new()
	hud.set_script(preload("res://hk/hud.gd"))
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	var fl := CanvasLayer.new()
	fl.layer = 20
	add_child(fl)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.add_child(_fade)
	menu = preload("res://hk/menu.gd").new()
	menu.rooms = rooms
	add_child(menu)
	shop = preload("res://hk/shop.gd").new()
	add_child(shop)

func _process(_d: float) -> void:
	if is_instance_valid(player):
		cam.global_position = player.global_position
	menu.enabled = not busy and not shop.is_open() and not player.is_dead()

func _fade_to(a: float, dur: float = 0.2) -> void:
	var t := create_tween()
	t.tween_property(_fade, "color:a", a, dur)
	await t.finished

## Nạp phòng `id`: dựng phòng, quái, boss, shade. Người chơi được chuyển sang node mới. Không tự đặt vị trí người chơi.
func load_room(id: String) -> void:
	var old: Node2D = _content
	_content = Node2D.new()
	add_child(_content)
	player.reparent(_content)
	if old:
		old.queue_free()
	var data: Dictionary = rooms[id]
	room = Node2D.new()
	room.set_script(preload("res://hk/room.gd"))
	_content.add_child(room)
	room.build(id, data)
	room.set_player(player)
	room.door_entered.connect(_on_door)
	room.hazard_touched.connect(_on_hazard_touch)
	room.interacted.connect(_on_interacted)
	player.z_index = 5
	boss = null
	for e in room.entities:
		match String(e["type"]):
			"c", "f", "s", "h":
				_spawn_enemy(String(e["type"]), e["pos"])
			"boss":
				var bid: String = String(data.get("boss", {}).get("id", ""))
				if bid != "" and not STATE.flag("boss_" + bid):
					_spawn_boss(bid, e["pos"])
	if STATE.shade.get("room", "") == id:
		var sh := StaticBody2D.new()
		sh.set_script(preload("res://hk/shade.gd"))
		sh.amount = int(STATE.shade.get("geo", 0))
		sh.position = Vector2(float(STATE.shade.get("x", 100)), float(STATE.shade.get("y", 100)))
		_content.add_child(sh)
	cam.set_bounds(room.bounds())
	STATE.visit(id)
	var area: String = String(data.get("area", "gate"))
	if area != _last_area:
		_last_area = area
		hud.banner(AREA_NAMES.get(area, area))

func _spawn_enemy(ch: String, pos: Vector2) -> void:
	var kinds: Dictionary = {"c": "crawler", "f": "flyer", "s": "spitter", "h": "charger"}
	var e := CharacterBody2D.new()
	e.set_script(preload("res://hk/enemy.gd"))
	e.kind = kinds[ch]
	var h: float = float(e.DATA[e.kind]["size"].y)
	e.position = pos - (Vector2(0, h * 0.5) if ch != "f" else Vector2.ZERO)
	_content.add_child(e)

func _spawn_boss(bid: String, pos: Vector2) -> void:
	boss = CharacterBody2D.new()
	boss.set_script(preload("res://hk/boss.gd"))
	boss.kind = bid
	boss.position = pos - Vector2(0, 50)
	_content.add_child(boss)
	boss.defeated.connect(_on_boss_defeated.bind(bid))
	boss.arena = room.bounds()
	boss.engaged.connect(_on_boss_engaged)
	boss.shake.connect(cam.shake)

func _on_boss_engaged() -> void:
	room.locked = true
	hud.banner(boss.title())

func _on_boss_defeated(bid: String) -> void:
	STATE.set_flag("boss_" + bid)
	room.locked = false
	STATE.save()
	hud.banner("%s defeated" % String(boss.title() if is_instance_valid(boss) else bid), "")
	if bid == "lord":
		STATE.set_flag("ending")
		hud.banner("The Dungeon Lord falls", "Thank you for playing")

func _on_door(door_id: String) -> void:
	if busy:
		return
	var link: Dictionary = rooms[room.id]["doors"].get(door_id, {})
	if link.is_empty() or not rooms.has(link["to"]):
		return
	await transition(String(link["to"]), String(link["door"]))

func transition(to_room: String, door_id: String) -> void:
	busy = true
	player.controls_enabled = false
	await _fade_to(1.0, 0.15)
	load_room(to_room)
	var spawn: Vector2 = room.spawn_for_door(door_id)
	player.respawn_at(spawn)
	entry_spawn = spawn
	cam.global_position = spawn
	cam.reset_smoothing()
	await _fade_to(0.0, 0.2)
	player.controls_enabled = true
	player.velocity = room.entry_velocity(door_id)
	busy = false

func _on_hazard_touch(from_x: float) -> void:
	if not busy:
		player.hazard_damage(from_x)

func _on_hazard() -> void:
	if busy:
		return
	busy = true
	player.controls_enabled = false
	await _fade_to(1.0, 0.2)
	player.respawn_at(entry_spawn)
	await _fade_to(0.0, 0.2)
	player.controls_enabled = true
	busy = false

func _on_player_died() -> void:
	busy = true
	player.controls_enabled = false
	await get_tree().create_timer(0.8, true, false, true).timeout
	await _fade_to(1.0, 0.5)
	if STATE.geo > 0:
		STATE.shade = {"room": room.id, "x": player.global_position.x, "y": player.global_position.y - 4.0, "geo": STATE.geo}
		STATE.geo = 0
	STATE.soul = 0
	load_room(STATE.bench_room)
	var spawn: Vector2 = room.default_spawn() if STATE.bench_id == "start" else room.bench_spawn()
	player.respawn_at(spawn, true)
	player.soul_changed.emit(0)
	entry_spawn = spawn
	cam.global_position = spawn
	cam.reset_smoothing()
	await _fade_to(0.0, 0.5)
	player.controls_enabled = true
	busy = false

func _on_interacted(kind: String, data: Dictionary) -> void:
	if busy:
		return
	match kind:
		"bench":
			rest()
		"merchant":
			shop.open(player)
		"cache":
			STATE.set_flag("cache_" + String(data["key"]))
			var n: int = 25
			STATE.geo += n
			FX.float_text(_content, data["pos"], "+%d Geo" % n, Color(1, 0.9, 0.4))
		"altar":
			var aid: String = String(data.get("id", ""))
			STATE.give_ability(aid)
			STATE.set_flag("got_" + aid)
			STATE.save()
			var info: Dictionary = STATE.ABILITIES[aid]
			hud.banner(String(info["name"]), String(info["desc"]))
		"charm":
			var cid: String = String(data.get("id", ""))
			STATE.give_charm(cid)
			STATE.set_flag("got_" + cid)
			STATE.save()
			hud.banner("Charm: " + String(STATE.CHARMS[cid]["name"]), String(STATE.CHARMS[cid]["desc"]))

func rest() -> void:
	busy = true
	player.controls_enabled = false
	STATE.hp = STATE.max_hp()
	STATE.bench_room = room.id
	STATE.bench_id = "bench"
	STATE.save()
	hud.banner("Rested")
	await _fade_to(1.0, 0.3)
	load_room(room.id)
	var spawn: Vector2 = room.bench_spawn()
	player.respawn_at(spawn, true)
	entry_spawn = spawn
	cam.global_position = spawn
	cam.reset_smoothing()
	await _fade_to(0.0, 0.3)
	player.controls_enabled = true
	busy = false
