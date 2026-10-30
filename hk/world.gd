extends Node2D
## Thế giới: nạp phòng, chuyển cửa, bench, chết/shade, tương tác (bàn thờ, bùa, thương nhân), boss, menu.
const STATE = preload("res://hk/state.gd")
const WorldData = preload("res://hk/world_data.gd")
const InputSetup = preload("res://hk/input.gd")
const FX = preload("res://hk/fx.gd")
const LORE = preload("res://hk/lore.gd")
const MUSIC = preload("res://hk/music.gd")
const SFX = preload("res://hk/sfx.gd")
const BACKDROP = preload("res://hk/backdrop.gd")
const ATMOSPHERE = preload("res://hk/atmosphere.gd")
const BOSS = preload("res://hk/boss.gd")
const RUSH = preload("res://hk/rush.gd")
const DEBUG_BOXES = preload("res://hk/debug_boxes.gd")
const AREA_NAMES: Dictionary = {"gate": "Gate Ruins", "catacomb": "Weeping Catacombs", "vault": "Ashen Vaults", "archive": "Drowned Archive"}
const ZOOM: float = 1.5
const WIDE_BOSSES: Array = ["colossus", "lord", "many_faced", "sovereign"]   # boss lớn: zoom ra khi vào trận

signal ending_reached   # báo lên main sau khi hạ Dungeon Lord
signal rush_finished(time: float, deaths: int, record: bool)   # Boss Rush: hạ boss cuối

var rooms: Dictionary = {}
var room: Node2D
var player: CharacterBody2D
var cam: Camera2D
var hud: Control
var menu: Node
var shop: Node
var music: Node
var sfx: Node
var backdrop: Node
var atmosphere: Node2D
var debug_boxes: Node2D
var busy: bool = false
var entry_spawn: Vector2 = Vector2.ZERO
var boss: Node2D
var _content: Node2D
var _fade: ColorRect
var _last_area: String = ""

func _ready() -> void:
	InputSetup.ensure()
	rooms = WorldData.load_all()
	STATE.rush = STATE.boot == "rush"
	match STATE.boot:
		"rush":
			RUSH.setup(RUSH.has_true_end())
			STATE.bench_room = RUSH.current_room()
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
	music = MUSIC.new()
	add_child(music)
	sfx = SFX.new()
	add_child(sfx)
	backdrop = BACKDROP.new()
	add_child(backdrop)
	atmosphere = ATMOSPHERE.new()
	add_child(atmosphere)
	debug_boxes = DEBUG_BOXES.new()
	debug_boxes.world = self
	add_child(debug_boxes)
	_build_ui()
	player.hit_landed.connect(cam.shake)
	player.health_changed.connect(hud.set_health)
	player.soul_changed.connect(hud.set_soul)
	player.died.connect(_on_player_died)
	player.hazard_hit.connect(_on_hazard)
	player.sfx.connect(sfx.play)
	shop.sfx.connect(sfx.play)
	menu.volume_changed.connect(_on_volume_changed)
	hud.set_health(STATE.hp, STATE.max_hp())
	hud.set_soul(STATE.soul)
	load_room(STATE.bench_room)
	var at_start: bool = STATE.bench_id == "start"
	player.respawn_at(_rush_spawn() if STATE.rush else (room.default_spawn() if at_start else room.bench_spawn()), true)   # Rush: sảnh = bench
	entry_spawn = player.global_position
	cam.global_position = player.global_position
	cam.reset_smoothing()
	_fade.color.a = 1.0   # vào game từ màn đen (title mờ ra đen) rồi sáng dần
	_fade_to(0.0, 0.5)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	hud = Control.new()
	hud.set_script(preload("res://hk/hud.gd"))
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	var vg := CanvasLayer.new()
	vg.layer = 4   # dưới HUD (5), trên thế giới
	add_child(vg)
	var vr := ColorRect.new()
	vr.set_anchors_preset(Control.PRESET_FULL_RECT)
	vr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vsh := Shader.new()
	vsh.code = "shader_type canvas_item;\nvoid fragment() { vec2 d = (UV - 0.5) * vec2(1.0, 0.8); COLOR = vec4(0.0, 0.0, 0.0, smoothstep(0.3, 0.85, length(d)) * 0.6); }"
	var vmat := ShaderMaterial.new()
	vmat.shader = vsh
	vr.material = vmat
	vg.add_child(vr)
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

func _on_volume_changed() -> void:
	music.apply_volume()
	atmosphere.apply()
	sfx.play("buy")

func _process(d: float) -> void:
	if not STATE.rush:
		STATE.play_time += d
	elif RUSH.idx >= 0 and not busy:   # Rush: đồng hồ chỉ chạy lúc đang đánh
		RUSH.time += d
	if Input.is_action_just_pressed("hk_debug"):
		debug_boxes.toggle()
	if is_instance_valid(player):
		cam.global_position = player.global_position
		atmosphere.follow(cam.global_position, player.global_position)
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
	player.ward_ready = true   # Oath Ward: mỗi phòng một lần chặn
	boss = null
	for e in room.entities:
		match String(e["type"]):
			"c", "f", "s", "h", "g", "d", "k", "z", "i", "b":
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
		sh.recovered.connect(func(_a: int): sfx.play("geo"))
		_content.add_child(sh)
	cam.set_bounds(room.bounds())
	cam.zoom_to(cam.base, 0.0, true)   # vào phòng mới luôn về zoom thường
	STATE.visit(id)
	var area: String = String(data.get("area", "gate"))
	if area != _last_area:
		_last_area = area
		hud.banner(AREA_NAMES.get(area, area))
		backdrop.set_area(area)
	atmosphere.set_room(data, room.interactables)
	music.play(String(MUSIC.AREA_TRACK.get(area, "explore_stone")))

func _spawn_enemy(ch: String, pos: Vector2) -> void:
	var kinds: Dictionary = {"c": "crawler", "f": "flyer", "s": "spitter", "h": "charger", "g": "guard", "d": "dropper", "k": "sentry", "z": "reviver", "i": "cinder", "b": "bubbler"}
	var e := CharacterBody2D.new()
	e.set_script(preload("res://hk/enemy.gd"))
	e.kind = kinds[ch]
	e.sfx.connect(sfx.play)
	var h: float = e.body_size(e.kind).y
	e.position = pos - (Vector2(0, h * 0.5) if ch != "f" and ch != "d" else Vector2.ZERO)
	_content.add_child(e)

func _spawn_boss(bid: String, pos: Vector2) -> void:
	boss = CharacterBody2D.new()
	boss.set_script(preload("res://hk/boss.gd"))
	boss.kind = bid
	if bid == "lord" and LORE.count() >= LORE.MEMORIES.size() - 1:   # đã có 5 ký ức kia => Gatekeeper
		boss.empowered = true
		boss.lanterns = LORE.count()
		for k in boss.ECHO_FROM:
			if STATE.flag("boss_" + k):
				boss.echoes.append(String(boss.SKILL[k]))
	boss.position = pos - Vector2(0, boss.body_size(bid).y * 0.5 + 1.0)   # chân boss đứng trên sàn của ô X
	_content.add_child(boss)
	boss.defeated.connect(_on_boss_defeated.bind(bid))
	boss.arena = room.bounds()
	boss.engaged.connect(_on_boss_engaged)
	boss.shake.connect(cam.shake)
	boss.sfx.connect(sfx.play)
	boss.darkness.connect(atmosphere.set_dark)
	boss.tinted.connect(atmosphere.set_tint)
	boss.braziers = _braziers()
	boss.platforms = room.oneways.duplicate()
	boss.shake.connect(_on_boss_shake)

## Chân các lò lửa của phòng hiện tại (đòn lửa của Ash Hexer dùng chúng làm điểm xuất phát).
func _braziers() -> Array:
	var out: Array = []
	for t in room.data.get("torches", []):
		out.append(Vector2((float(t["col"]) + 0.5) * room.TILE, (float(t["row"]) + 1.0) * room.TILE))
	return out

func _on_boss_shake(strength: float) -> void:
	if strength >= 2.0:
		sfx.play("slam")
		cam.punch()

func _on_boss_engaged() -> void:
	room.locked = true
	cam.zoom_to(cam.WIDE if boss.kind in WIDE_BOSSES else cam.ENGAGE)
	sfx.play("roar")
	music.play(String(MUSIC.BOSS_TRACK.get(boss.kind, "boss_warden")))
	hud.banner(boss.title(), LORE.INTRO_GATEKEEPER if boss.empowered else LORE.line(boss.kind, "intro"))

func _on_boss_defeated(bid: String) -> void:
	sfx.play("boss_die")
	cam.zoom_to(cam.base, 2.0)
	if STATE.rush:
		STATE.set_flag("boss_" + bid)   # để Lord thành Gatekeeper khi đã hạ đủ 5 boss kia, như ván thường
		room.locked = false
		await _rush_next(bid)
		return
	if not STATE.flag("boss_" + bid):   # tiền thưởng hạ boss lần đầu
		var bounty: int = int(BOSS.BOUNTY.get(bid, 0))
		STATE.geo += bounty
		if bounty > 0:
			FX.float_text(_content, boss.global_position if is_instance_valid(boss) else player.global_position, "+%d Geo" % bounty, Color(1, 0.9, 0.4))
	STATE.set_flag("boss_" + bid)
	room.locked = false
	music.play(String(MUSIC.AREA_TRACK.get(String(rooms[room.id].get("area", "gate")), "explore_stone")))
	STATE.save()
	hud.banner("%s defeated" % String(boss.title() if is_instance_valid(boss) else bid), LORE.line(bid, "memory"))
	_refresh_unlocks()
	if bid == "many_faced":   # ending bí mật
		STATE.set_flag("ending_true")
		STATE.save()
		busy = true
		player.controls_enabled = false
		cam.zoom_to(cam.WIDE, 0.7)   # kết thúc: zoom ra dần
		await get_tree().create_timer(3.0, true, false, true).timeout
		ending_reached.emit()
	elif bid == "lord":
		STATE.set_flag("ending")
		STATE.save()
		hud.banner("The Dungeon Lord falls", String(LORE.memory("lord")["memory"]))
		busy = true
		player.controls_enabled = false
		cam.zoom_to(cam.WIDE, 0.7)   # kết thúc: zoom ra dần
		await get_tree().create_timer(3.0, true, false, true).timeout
		ending_reached.emit()

## Cờ mở khoá suy ra từ trạng thái ván (không lưu thêm dữ liệu): đủ 6 ký ức -> mở lối tới boss bí mật.
func _refresh_unlocks() -> void:
	if LORE.is_complete():
		STATE.set_flag("sovereign_open")

func _on_door(door_id: String) -> void:
	if busy:
		return
	if STATE.rush and RUSH.idx < 0:   # ra khỏi sảnh = bắt đầu lượt
		RUSH.start()
		await _rush_enter()
		return
	var link: Dictionary = rooms[room.id]["doors"].get(door_id, {})
	if link.is_empty() or not rooms.has(link["to"]):
		return
	_refresh_unlocks()
	var need: String = String(link.get("needs", ""))
	if need != "" and not STATE.flag(need):
		hud.banner("Sealed", "The way answers only to one who remembers everything.")
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
	cam.zoom_to(cam.DEATH, 2.0)   # zoom chậm vào người chơi lúc ngã
	await get_tree().create_timer(0.8, true, false, true).timeout
	if STATE.rush:   # Boss Rush: hồi sinh ngay tại trận đang đánh, tính số lần chết
		RUSH.deaths += 1
		STATE.soul = 0
		player.soul_changed.emit(0)
		await _rush_enter()
		hud.banner("You fall", "Deaths: %d" % RUSH.deaths)
		return
	await _fade_to(1.0, 0.5)
	if STATE.geo > 0:
		STATE.shade = {"room": room.id, "x": player.global_position.x, "y": player.global_position.y - 4.0, "geo": STATE.geo}
		STATE.geo = 0
	STATE.soul = 0
	load_room(STATE.bench_room)
	var spawn: Vector2 = room.default_spawn() if STATE.bench_id == "start" else room.bench_spawn()
	player.respawn_at(spawn, true)
	player.soul_changed.emit(0)
	hud.banner("You fall", LORE.death_line(String(rooms[room.id].get("area", "gate"))))
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
			sfx.play("bench")
			rest()
		"merchant":
			shop.open(player, String(room.data.get("area", "gate")))
		"cache":
			STATE.set_flag("cache_" + String(data["key"]))
			sfx.play("geo")
			var n: int = 25
			STATE.geo += n
			FX.float_text(_content, data["pos"], "+%d Geo" % n, Color(1, 0.9, 0.4))
		"altar":
			sfx.play("ability")
			var aid: String = String(data.get("id", ""))
			STATE.give_ability(aid)
			STATE.set_flag("got_" + aid)
			STATE.save()
			var info: Dictionary = STATE.ABILITIES[aid]
			hud.banner(String(info["name"]), String(info["desc"]))
		"charm":
			sfx.play("charm")
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
	hud.banner("Rested", LORE.bench_line())
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

## Boss Rush: ở sảnh đứng cạnh bench; ở phòng boss đứng ở cửa đầu tiên.
func _rush_spawn() -> Vector2:
	if RUSH.idx < 0:
		return room.bench_spawn()
	var keys: Array = room.doors.keys()
	keys.sort()
	return room.spawn_for_door(String(keys[0])) if not keys.is_empty() else room.default_spawn()

## Nạp (lại) phòng boss của lượt Rush: đầy máu, đứng ở cửa vào.
func _rush_enter() -> void:
	busy = true
	player.controls_enabled = false
	await _fade_to(1.0, 0.4)
	load_room(RUSH.current_room())
	var spawn: Vector2 = _rush_spawn()
	player.respawn_at(spawn, true)
	entry_spawn = spawn
	cam.global_position = spawn
	cam.reset_smoothing()
	await _fade_to(0.0, 0.4)
	player.controls_enabled = true
	busy = false

## Hạ boss trong Rush: hồi đầy máu, chờ 2s, sang boss kế; boss cuối thì báo kết quả lên main.
func _rush_next(bid: String) -> void:
	busy = true
	player.controls_enabled = false
	var seg: float = RUSH.time - RUSH.mark
	RUSH.mark = RUSH.time
	var fresh: bool = RUSH.record_split(bid, seg)
	hud.banner("%s defeated" % String(boss.title() if is_instance_valid(boss) else bid), RUSH.fmt(seg) + ("   NEW BEST" if fresh else ""))
	if RUSH.last():
		var rec: bool = RUSH.submit(RUSH.time)
		await get_tree().create_timer(3.0, true, false, true).timeout
		rush_finished.emit(RUSH.time, RUSH.deaths, rec)
		return
	await get_tree().create_timer(2.0, true, false, true).timeout
	RUSH.idx += 1
	await _rush_enter()
