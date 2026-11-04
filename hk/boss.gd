extends CharacterBody2D
## Boss: warden / lord (đi bộ, chém lao, nhảy đập, triệu hồi, mưa đá) và wraith (bay, bắn quạt, bổ nhào, chớp dịch chuyển).
## Mini-boss: brute (đi bộ, đập đất + chém, như warden nhẹ) và hexer (bay, bắn quạt, chớp dịch chuyển, triệu hồi quỷ nhỏ).
## Boss bí mật many_faced: biến hình (`form`) qua các bộ đòn của boss khác, 3 pha; pha 3 là dạng thật `sovereign`.
## Mỗi đòn có thời gian báo trước (nhấp nháy). Gán `kind` TRƯỚC khi add_child, `arena` sau khi add.
signal engaged
signal defeated
signal shake(strength: float)
signal sfx(name: String)
signal phase_changed(phase: int)   # world nối vào Music (lớp nhạc pha 3)
signal darkness(on: bool)   # Wraith tối phòng; world nối vào Atmosphere
signal tinted(c: Color)     # Many-Faced pha 3 nhuộm màu phòng (tím); Color.WHITE = bỏ nhuộm

const PROJECTILE = preload("res://hk/projectile.gd")
const ENEMY = preload("res://hk/enemy.gd")
const FX = preload("res://hk/fx.gd")
const SPRITES = preload("res://hk/sprites.gd")
const LOOK: Dictionary = {
	"warden": {"anim": "ogre_idle_anim", "scale": 3.0},
	"wraith": {"anim": "necromancer_idle_anim", "scale": 3.0},
	"lord": {"anim": "big_demon_idle_anim", "scale": 3.0},
	"brute": {"anim": "frost_big_zombie_anim", "scale": 2.5},
	"hexer": {"anim": "hell_acolyte_anim", "scale": 3.0},
	"colossus": {"anim": "hell_ogre_idle_anim", "scale": 2.5},
	"grove": {"anim": "ogre_run_anim", "scale": 3.0, "tint": Color(0.7, 1.2, 0.55)},
	"many_faced": {"anim": "ogre_idle_anim", "scale": 3.0},   # hộp ban đầu = dạng warden; hộp thật theo `form`
	"sovereign": {"anim": "big_demon_idle_anim", "scale": 3.6},
}
const FLYERS: Array = ["wraith", "hexer"]
const ZONE = preload("res://hk/zone.gd")
const ECHO_FROM: Array = ["warden", "brute", "colossus", "hexer", "wraith"]   # boss có đòn Echo cho Gatekeeper (Lord và sovereign không tự echo)
## Đòn riêng của mỗi dạng (tương tác với biom của boss): state báo trước -> hàm tung đòn trong `_cast`.
const SKILL: Dictionary = {
	"warden": "wind_pillar", "brute": "wind_fissure", "wraith": "wind_veil", "hexer": "wind_torch",
	"lord": "wind_heat", "sovereign": "wind_heat", "colossus": "wind_tide", "grove": "wind_bloom",
}
const SWEEP_H: float = 36.0       # chiều cao sóng quét của Warden (nhảy qua được)
const SWEEP_SPEED: float = 300.0
const SWEEP_P1: float = 0.5       # xác suất sweep nằm trong danh sách đòn của một lượt ở pha 1
const VINE_GAP: float = 45.0      # pha 2: hàng dây thứ hai lệch nửa bước so với hàng đầu, lấp các khe
const QUAKE_WAVES: Array = [2, 3]   # số sóng của đòn quake theo pha 1 / pha 2+
const RUSH_SPEED: float = 560.0
const P2_REST: float = 0.7        # pha 2: thời gian đi bộ/bay giữa hai đòn nhân hệ số này (nhịp dồn hơn)
const CHAIN: Dictionary = {"wind_tide": "quake", "wind_volley": "quake", "wind_heat": "rain"}   # đòn riêng nối thẳng sang đòn thứ hai (colossus: nước rồi dậm đất; lord/sovereign pha 2: bục nóng rồi mưa đá)
const EARLY_P2: Array = ["grove", "brute", "colossus", "hexer"]   # vào pha 2 ở 66% máu (cũ: grove đã vậy; brute/colossus/hexer 50%)
const TIDE_H: float = 90.0         # nước dâng cao (cũ 80): vẫn thấp hơn mặt bục 96px của arc_5 và nhảy được ra khỏi nước; chỉ khi phòng có bục thì chìm/dòng chảy
const HURL_SPEEDS: Array = [260.0, 340.0, 420.0]   # brute "Bone Hurl": ba xương bay ngang, tới lệch nhau (nhảy qua từng quả hoặc đỡ để phản lại)
const UNDERTOW_PULL: float = 220.0   # colossus "Undertow": px/s kéo người chơi về phía boss trong 1.5s (zone.gd kind undertow)
const EMBER_N: int = 5               # hexer "Ember Rain": số điểm lửa thả xuống sàn quanh người chơi (nằm 2s)
const CAGE_GAP: Array = [90.0, 45.0]   # brute "Bone Cage": gai trồi cách người chơi 90px hai bên, rồi khép vào 45px
const GEYSER_N: int = 4               # colossus "Geyser Line": số cột nước phun lần lượt về phía người chơi
const VOLLEY_N: int = 5               # colossus "Bubble Volley": số bong bóng chậm bắn hình quạt (rồi nối dậm đất)
const GRAVITY: float = 2400.0
const STAGGER_CD: float = 6.0   # mỗi boss chỉ choáng được một lần mỗi chừng này giây (đỡ đòn không thành vòng lặp)
const PERCH_WAIT: float = 1.0   # giây người chơi đứng cao hơn boss trước khi boss nhảy lên

const DATA: Dictionary = {
	"warden": {"title": "Gate Warden", "hp": 220, "color": Color(0.55, 0.62, 0.78), "speed": 95.0},
	"wraith": {"title": "Hollow Wraith", "hp": 260, "color": Color(0.75, 0.82, 0.98), "speed": 200.0},
	"lord": {"title": "Dungeon Lord", "hp": 420, "color": Color(0.82, 0.36, 0.30), "speed": 115.0},
	"brute": {"title": "Bone Brute", "hp": 110, "color": Color(0.55, 0.75, 0.85), "speed": 85.0},
	"hexer": {"title": "Ash Hexer", "hp": 90, "color": Color(0.85, 0.45, 0.35), "speed": 170.0},
	"colossus": {"title": "Drowned Colossus", "hp": 130, "color": Color(0.6, 0.5, 0.8), "speed": 100.0},
	"grove": {"title": "Rotted Warden", "hp": 140, "color": Color(0.5, 0.8, 0.35), "speed": 90.0},
	"many_faced": {"title": "The Many-Faced", "hp": 480, "color": Color(0.7, 0.45, 0.9), "speed": 0.0},
	"sovereign": {"title": "The Many-Faced", "hp": 0, "color": Color(0.7, 0.45, 0.9), "speed": 125.0},
}
## Geo thưởng một lần khi hạ boss lần đầu (cờ boss_<id> chưa đặt).
const BOUNTY: Dictionary = {"warden": 60, "hexer": 40, "brute": 40, "wraith": 80, "colossus": 50, "grove": 60, "lord": 150, "many_faced": 0}
const SHIFT_P1: Array = ["warden", "brute", "wraith", "hexer"]
const SHIFT_P2: Array = ["warden", "brute", "wraith", "hexer", "colossus", "lord"]

var kind: String = "warden"
var form: String = ""             # dạng đang dùng (= kind với boss thường); quyết định bộ đòn, hộp, bay/đi
var _shape: RectangleShape2D
var _form_t: float = 0.0          # còn bao lâu thì đổi dạng (chỉ many_faced)

## Hộp va chạm = phần nhìn thấy của sprite (hk/bodies.gd).
static func body_size(k: String) -> Vector2:
	var look: Dictionary = LOOK[k]
	return SPRITES.BODIES.rect(String(look["anim"]), float(look["scale"])).size
var arena: Rect2 = Rect2(0, 0, 1280, 720)
var hp: int = 100
var max_hp: int = 100
var state: String = "dormant"
var dir: int = -1
var phase: int = 1
var _t: float = 0.0
var _flash: float = 0.0
var _time: float = 0.0
var _combo: int = 0
var _size: Vector2
var _stagger_cd: float = 0.0
var _markers: Array = []       # {x, t}: cảnh báo trước khi rơi đá / bổ nhào
var _rain_t: float = 0.0
var _dive_x: float = 0.0
var _alpha: float = 1.0
var _was_air: bool = false
var _perch_t: float = 0.0
var _prev_state: String = ""
var _twin: int = 0              # brute "Twin Slam": số lần đập nữa sau lần chạm đất hiện tại
var _last_pick: String = ""     # đòn lượt trước (không lặp đòn y hệt hai lượt liền)
var braziers: Array = []     # chân các lò lửa trong phòng (world gán) — nguồn sóng lửa của Hexer
var platforms: Array = []    # Rect2 các bục một chiều trong phòng (world gán) — Lord làm nóng bục
var _dark_t: float = 0.0
var empowered: bool = false  # world gán: Lord khi đã có 5 ký ức kia ("The Gatekeeper": đổi sắc, vầng sáng, đèn ký ức, đòn Echo)
var echoes: Array = []       # world gán: state đòn riêng của mọi boss đã hạ (warden/brute/colossus/hexer/wraith) — Echo dùng lại
var lanterns: int = 0        # world gán: số ký ức đã có (đèn sáng trên tường phòng Lord)
var _tinted: bool = false

func _ready() -> void:
	var d: Dictionary = DATA[kind]
	max_hp = int(d["hp"])
	hp = max_hp
	form = "warden" if kind == "many_faced" else kind
	_form_t = 7.0
	_size = body_size(form)
	collision_layer = 4
	collision_mask = 0 if form in FLYERS else 1
	add_to_group("hk_boss")
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = _size
	_shape = sh
	cs.shape = sh
	add_child(cs)

func title() -> String:
	if empowered:
		return "The Gatekeeper"
	return String(DATA[kind]["title"])

func _player() -> Node2D:
	var ps := get_tree().get_nodes_in_group("hk_player")
	return ps[0] if not ps.is_empty() else null

func _exit_tree() -> void:
	if _tinted:
		tinted.emit(Color.WHITE)
	if _dark_t > 0.0:
		darkness.emit(false)

func _physics_process(delta: float) -> void:
	if _dark_t > 0.0:
		_dark_t -= delta
		if _dark_t <= 0.0:
			darkness.emit(false)
	_time += delta
	_flash = maxf(0.0, _flash - delta)
	_stagger_cd = maxf(0.0, _stagger_cd - delta)
	_t -= delta
	var p := _player()
	if p == null:
		return
	if state == "dormant":
		velocity = Vector2(0, velocity.y)
		if not (form in FLYERS):
			velocity.y = minf(velocity.y + GRAVITY * delta, 900.0)
			move_and_slide()
		if absf(p.global_position.x - global_position.x) < 480.0 and absf(p.global_position.y - global_position.y) < 260.0:
			state = "intro"
			_t = 1.1
			engaged.emit()
		queue_redraw()
		return
	if kind == "many_faced" and state != "wind_shift" and state != "intro":
		_form_t -= delta
	if state == "intro":
		if not (form in FLYERS):
			velocity.y = minf(velocity.y + GRAVITY * delta, 900.0)
			velocity.x = 0.0
			move_and_slide()
		if _t <= 0.0:
			_next()
	elif state == "wind_shift":
		velocity = Vector2(0, minf(velocity.y + GRAVITY * delta, 900.0)) if not (form in FLYERS) else Vector2.ZERO
		if not (form in FLYERS):
			move_and_slide()
		if _t <= 0.0:
			_set_form(_pick_form())
			_next()
	elif state == "stagger":   # bị đỡ đòn: đứng choáng, hết giờ thì chọn đòn mới
		velocity = Vector2(0, minf(velocity.y + GRAVITY * delta, 900.0)) if not (form in FLYERS) else Vector2.ZERO
		if not (form in FLYERS):
			move_and_slide()
		if int(_time * 20.0) % 2 == 0:
			_flash = 0.05
		if _t <= 0.0:
			_next()
	elif form in FLYERS:
		_wraith(delta, p)
	else:
		_ground(delta, p)
	if state != _prev_state and state.begins_with("wind"):   # báo hiệu đòn bằng âm riêng (thay vùng cảnh báo màu)
		sfx.emit("tell_" + state.substr(5))
	_prev_state = state
	_touch_damage(p)
	_update_markers(delta)
	queue_redraw()

func _lordlike() -> bool:
	return form == "lord" or form == "sovereign"

## many_faced: hết giờ dạng thì báo trước ~0.9s (vòng + nhấp nháy, không nhận đòn, không gây chạm) rồi đổi dạng. Pha 3 giữ dạng thật.
func _maybe_shift() -> bool:
	if kind != "many_faced" or phase >= 3 or _form_t > 0.0:
		return false
	state = "wind_shift"
	_t = 0.9
	velocity = Vector2.ZERO
	shake.emit(1.0)
	return true

func _pick_form() -> String:
	var pool: Array = (SHIFT_P1 if phase == 1 else SHIFT_P2).duplicate()
	pool.erase(form)
	return String(pool[randi() % pool.size()])

func _set_form(f: String) -> void:
	var old_h: float = _size.y
	form = f
	_size = body_size(f)
	_shape.set_deferred("size", _size)
	set_deferred("collision_mask", 0 if f in FLYERS else 1)
	global_position.y += (old_h - _size.y) * 0.5   # chân giữ nguyên chỗ khi đổi cỡ hộp
	velocity = Vector2.ZERO
	_alpha = 1.0
	_form_t = (6.5 if phase == 1 else 4.0) + randf_range(0.0, 1.5)

func _face(p: Node2D) -> void:
	dir = 1 if p.global_position.x > global_position.x else -1

func _next() -> void:
	_twin = 0
	state = "hover" if form in FLYERS else "walk"
	_t = (randf_range(1.0, 1.6) if form in FLYERS else randf_range(0.5, 1.0)) * (P2_REST if phase >= 2 else 1.0)

# ------------------------------------------------------------ đi bộ (warden, lord)
func _ground(delta: float, p: Node2D) -> void:
	var speed: float = float(DATA[form]["speed"]) * (1.25 if phase >= 2 else 1.0)
	match state:
		"walk":
			_face(p)
			velocity.x = float(dir) * speed
			_perch_t = _perch_t + delta if (is_on_floor() and p.global_position.y < global_position.y - 90.0) else 0.0
			if _perch_t >= PERCH_WAIT:   # người chơi nấp trên bục cao: boss nhảy lên đuổi (đáp xuống gây sóng đập)
				_perch_t = 0.0
				var dy: float = global_position.y - p.global_position.y
				velocity = Vector2(clampf((p.global_position.x - global_position.x) / 0.9, -360.0, 360.0), -minf(sqrt(2.0 * GRAVITY * (dy + 48.0)), 1400.0))
				state = "air"
				_was_air = false
			elif _t <= 0.0 and not _maybe_shift():
				_pick_attack()
		"wind_slash":
			velocity.x = 0.0
			if _t <= 0.0:
				state = "lunge"
				_t = 0.28
				shake.emit(1.0)
		"lunge":
			velocity.x = float(dir) * 470.0
			if _t <= 0.0:
				state = "recover"
				_t = 0.5
		"recover":
			velocity.x = 0.0
			if _t <= 0.0:
				if _combo > 0:
					_combo -= 1
					_face(p)
					state = "wind_slash"
					_t = 0.3
				else:
					_next()
		"wind_slam":
			velocity.x = 0.0
			if _t <= 0.0:
				state = "air"
				_face(p)
				velocity = Vector2(clampf((p.global_position.x - global_position.x) / 0.75, -320.0, 320.0), -950.0)
				_was_air = false
		"air":
			if not is_on_floor():
				_was_air = true
			elif _was_air:
				_shockwave()
				if _twin > 0:   # Twin Slam: đập lần hai ngay sau lần đầu
					_twin -= 1
					state = "wind_slam"
					_t = 0.3
				else:
					state = "recover"
					_t = 0.8
		"wind_bolt":
			velocity.x = 0.0
			_face(p)
			if _t <= 0.0:
				_fire_fan(p)
				state = "recover"
				_t = 0.6
		"wind_summon":
			velocity.x = 0.0
			if _t <= 0.0:
				_summon()
				state = "recover"
				_t = 0.6
		"wind_quake":   # Colossus: dậm đất liên tiếp, mỗi nhịp một sóng chạy hai bên (nhảy qua từng sóng theo nhịp)
			velocity.x = 0.0
			if _t <= 0.0:
				state = "quake"
				_combo = int(QUAKE_WAVES[0 if phase == 1 else 1])
		"quake":
			velocity.x = 0.0
			if _t <= 0.0:
				_shockwave()
				_combo -= 1
				_t = 0.5
				if _combo <= 0:
					state = "recover"
					_t = 0.9
		"wind_rush":   # Brute (pha 2): lao hết phòng rồi quay lại; KHÔNG đỡ được (báo bằng sắc vàng + âm tell_rush)
			velocity.x = 0.0
			_face(p)
			if _t <= 0.0:
				state = "rush"
				_combo = 2
				_t = 7.0   # giới hạn an toàn: hai lượt hết phòng (~6.5s ở tốc độ 560)
				shake.emit(2.0)
		"rush":
			velocity.x = float(dir) * RUSH_SPEED
			var edge: bool = (dir < 0 and global_position.x <= arena.position.x + 50.5) or (dir > 0 and global_position.x >= arena.end.x - 50.5) or (is_on_wall() and get_wall_normal().x * float(dir) < 0.0)   # chỉ tính bờ đang lao tới (không quay hai lần ở cùng một bờ)
			if edge:
				_combo -= 1
				dir = -dir
				shake.emit(2.0)
			if _combo <= 0 or _t <= 0.0:
				state = "recover"
				_t = 1.0
		"wind_pillar", "wind_fissure", "wind_heat", "wind_tide", "wind_torch", "wind_veil", "wind_bloom", "wind_vine", "wind_sweep", "wind_hurl", "wind_undertow", "wind_cage", "wind_geyser", "wind_volley":   # torch/veil: chỉ dùng khi Lord echo (boss bay có khối riêng)
			velocity.x = 0.0
			_face(p)
			if _t <= 0.0:
				var from: String = state
				_cast(p)
				if CHAIN.has(from) and (from == "wind_tide" or from == "wind_volley" or phase >= 2) and (from != "wind_heat" or not platforms.is_empty()):
					_chain(String(CHAIN[from]))
				else:
					state = "recover"
					_t = 0.9
		"rain":
			velocity.x = 0.0
			_rain_t -= delta
			if _rain_t <= 0.0:
				_rain_t = 0.4
				var rx: float = randf_range(arena.position.x + 70.0, arena.end.x - 70.0)
				_markers.append({"x": rx, "t": 0.8})
				FX.burst(get_parent(), Vector2(rx, arena.position.y + 36.0), Color(0.6, 0.55, 0.5), 5, 60.0)   # bụi rơi từ trần báo hiệu đá sắp rụng
				sfx.emit("rumble")
			if _t <= 0.0:
				state = "recover"
				_t = 0.7
	velocity.y = minf(velocity.y + GRAVITY * delta, 900.0)
	move_and_slide()
	global_position.x = clampf(global_position.x, arena.position.x + 50.0, arena.end.x - 50.0)

## Nối đòn: bục nóng -> mưa đá ngắn (2s), nước dâng -> dậm đất.
func _chain(to: String) -> void:
	if to == "rain":
		state = "rain"
		_t = 2.0
		_rain_t = 0.1
	else:
		state = "wind_quake"
		_t = 0.6

func _pick_attack() -> void:
	var opts: Array = ["slash", "slam"]
	if form == "brute":   # nhiều đập đất hơn chém: đòn chậm, báo trước dài
		opts = ["slam", "slam", "slash"]
		if phase >= 2:
			opts.append("combo")
			opts.append("rush")
	elif _lordlike():
		opts.append("summon")
		if phase >= 2:
			opts.append("rain")
			opts.append("rain")
	elif phase >= 2:
		opts.append("combo")
	if form == "colossus" or form == "brute":   # brute: dậm đất có sóng cả hai pha
		opts.append("quake")
	if form == "brute":
		if phase == 1 or randf() < 0.5:   # lồng xương (không đỡ được); pha 2 chỉ nửa số lượt để đòn không đỡ được ≤1/3 bộ đòn
			opts.append("cage")
		if phase >= 2:
			opts.append("twin")   # đập đôi (đỡ được)
		opts.append("hurl")   # ném xương: một trong ~5-7 lựa chọn mỗi lượt (≤1/4)
	if form == "colossus":
		opts.append("geyser")   # hàng mạch nước (không đỡ được)
		opts.append("volley")   # mưa bong bóng chậm rồi dậm đất
	if form == "colossus" and not platforms.is_empty():
		opts.append("undertow")   # xoáy nước kéo về phía boss: chỉ khi phòng có bục để thoát lên
	if form == "warden" and (phase >= 2 or randf() < SWEEP_P1):   # quét sàn: đòn không đỡ được của Warden (nhảy hoặc dash qua); pha 1 chỉ thỉnh thoảng
		opts.append("sweep")
	if form == "grove":   # dây leo: đòn thứ hai của Rotted Warden (nhiều hơn ở pha 2)
		opts.append("vine")
		if phase >= 2:
			opts.append("vine")
	if SKILL.has(form):   # đòn riêng của dạng này (nhiều hơn ở pha 2)
		opts.append("skill")
		if phase >= 2:
			opts.append("skill")
	if empowered and phase >= 2 and not echoes.is_empty():   # Echo: Lord dùng lại đòn riêng của boss đã hạ (tối đa một đòn mỗi lượt, như mọi đòn khác)
		opts.append("echo")
	if kind == "many_faced" and phase >= 2:   # đòn lai: mọi dạng đi bộ biết bắn quạt từ pha 2
		opts.append("bolt")
		if form == "sovereign":
			opts.append("bolt")
	var pick: String = String(opts[randi() % opts.size()])
	if pick == _last_pick and opts.size() > 1:   # không lặp đòn: bốc lại một lần
		pick = String(opts[randi() % opts.size()])
	_last_pick = pick
	match pick:
		"slash":
			state = "wind_slash"
			_t = 0.5
		"combo":
			_combo = 2
			state = "wind_slash"
			_t = 0.5
		"slam":
			state = "wind_slam"
			_t = 0.45
		"summon":
			state = "wind_summon"
			_t = 1.0
		"bolt":
			state = "wind_bolt"
			_t = 0.55
		"quake":
			state = "wind_quake"
			_t = 0.7
		"vine":
			state = "wind_vine"
			_t = 0.8
		"sweep":
			state = "wind_sweep"
			_t = 0.8
		"cage":
			state = "wind_cage"
			_t = 0.7
		"twin":
			state = "wind_slam"
			_t = 0.45
			_twin = 1
		"geyser":
			state = "wind_geyser"
			_t = 0.7
		"volley":
			state = "wind_volley"
			_t = 0.7
		"hurl":
			state = "wind_hurl"
			_t = 0.7
		"undertow":
			state = "wind_undertow"
			_t = 0.7
		"rush":
			state = "wind_rush"
			_t = 0.8
		"rain":
			state = "rain"
			_t = 3.0
			_rain_t = 0.1
		"skill":
			state = String(SKILL[form])
			_t = 0.8
		"echo":
			var pool: Array = echoes.duplicate()
			if _dark_t > 0.0:
				pool.erase("wind_veil")   # đang tối thì không tối lại
			state = String(pool[randi() % pool.size()]) if not pool.is_empty() else "wind_slash"
			_t = 0.8

# ------------------------------------------------------------ đòn riêng theo biom
func _floor_y() -> float:
	return global_position.y + _size.y * 0.5 if not (form in FLYERS) else arena.end.y - 64.0

func _zone(k: String, r: Rect2, delay: float, life: float, v: Vector2 = Vector2.ZERO) -> Node2D:
	var z := Node2D.new()
	z.set_script(ZONE)
	z.kind = k
	z.rect = r
	z.delay = delay
	z.life = life
	z.vel = v
	z.fx_parent = get_parent()
	add_child.call_deferred(z)
	return z

func _dust(pos: Vector2) -> void:   # tín hiệu thay vùng cảnh báo: bụi/tia lửa + âm rung tại chỗ sắp có đòn
	FX.burst(get_parent(), pos, Color(0.6, 0.55, 0.5), 6, 70.0)
	sfx.emit("rumble")

func _cast(p: Node2D) -> void:
	var fy: float = _floor_y()
	match state:
		"wind_pillar":   # Gate Warden: đập sập cột ngay chỗ người chơi; rơi gây sát thương, đáp xuống thành vật cản/chỗ nấp 6s
			var x: float = clampf(p.global_position.x, arena.position.x + 60.0, arena.end.x - 60.0)
			_dust(Vector2(x, arena.position.y + 40.0))
			_zone("pillar", Rect2(x - 16.0, arena.position.y + 40.0, 32.0, 96.0), 0.7, 6.0).floor_y = fy
		"wind_fissure":   # Bone Brute: nền nứt, gai xương trồi lên quanh người chơi và tồn tại 3.5s
			for dx in ([-240.0, -120.0, 0.0, 120.0, 240.0] if phase >= 2 else [-120.0, 0.0, 120.0]):   # pha 2: 5 cụm (cũ 3)
				var x2: float = clampf(p.global_position.x + dx, arena.position.x + 60.0, arena.end.x - 60.0)
				_dust(Vector2(x2, fy))
				_zone("spikes", Rect2(x2 - 20.0, fy - 44.0, 40.0, 44.0), 0.6, 3.5)
			shake.emit(2.0)
		"wind_bloom":   # Rotted Warden: năm cụm bào tử nở quanh người chơi, tồn tại 4s (đứng ngoài cụm hoặc dash với Spore Ward)
			for dx in ([-300.0, -200.0, -100.0, 0.0, 100.0, 200.0, 300.0] if phase >= 2 else [-200.0, -100.0, 0.0, 100.0, 200.0]):   # pha 2: phủ rộng hơn
				var xb: float = clampf(p.global_position.x + dx, arena.position.x + 60.0, arena.end.x - 60.0)
				_dust(Vector2(xb, fy))
				var zb: Node2D = _zone("spore", Rect2(xb - 40.0, fy - 70.0, 80.0, 70.0), 0.7, 4.0)
				zb.period = 0.0
			for dxr in ([-250.0, -150.0, -50.0, 50.0, 150.0, 250.0] if phase >= 2 else [0.0]):   # đợt hai nở muộn (1.9s) lệch chỗ: đứng yên ở chỗ an toàn của đợt một sẽ bị trúng
				var xr: float = clampf(p.global_position.x + dxr, arena.position.x + 60.0, arena.end.x - 60.0)
				var zr: Node2D = _zone("spore", Rect2(xr - 40.0, fy - 70.0, 80.0, 70.0), 1.9, 2.5)
				zr.period = 0.0
		"wind_vine":   # Rotted Warden: dây leo trồi lên thành hàng từ boss tới người chơi, từng cụm một (không đỡ được); pha 2: hàng thứ hai lấp các khe sau khi hàng đầu tàn (pha 1: chỉ 3 dây đầu)
			var sgn: float = 1.0 if p.global_position.x >= global_position.x else -1.0
			for i in 6:
				var xv: float = clampf(global_position.x + sgn * (90.0 + 90.0 * float(i)), arena.position.x + 40.0, arena.end.x - 40.0)
				_dust(Vector2(xv, fy))
				_zone("vine", Rect2(xv - 22.0, fy - 64.0, 44.0, 64.0), 0.3 + 0.18 * float(i), 0.9)
				if phase >= 2 or i < 3:   # pha 1: hàng thứ hai nhẹ (3 dây đầu)
					_zone("vine", Rect2(xv + sgn * VINE_GAP - 22.0, fy - 64.0, 44.0, 64.0), 1.2 + 0.18 * float(i), 0.9)
			shake.emit(2.0)
		"wind_sweep":   # Gate Warden (pha 2): sóng đá thấp quét sàn về phía người chơi, KHÔNG đỡ được (nháy vàng + tell_sweep); nhảy hoặc dash qua
			var sg: float = 1.0 if p.global_position.x >= global_position.x else -1.0
			var edge: float = arena.end.x - 20.0 if sg > 0.0 else arena.position.x + 20.0
			var dist: float = absf(edge - global_position.x)
			_dust(Vector2(global_position.x + sg * 50.0, fy))
			_zone("sweep", Rect2(global_position.x + sg * 50.0 - 20.0, fy - SWEEP_H, 40.0, SWEEP_H), 0.1, dist / SWEEP_SPEED, Vector2(sg * SWEEP_SPEED, 0.0))
			if phase >= 2:   # sóng hồi: từ bờ xa quét ngược lại ngay khi sóng đầu tới nơi (nhảy hai lần)
				_zone("sweep", Rect2(edge - 20.0, fy - SWEEP_H, 40.0, SWEEP_H), dist / SWEEP_SPEED + 0.15, dist / SWEEP_SPEED, Vector2(-sg * SWEEP_SPEED, 0.0))
			shake.emit(2.0)
		"wind_torch":   # Ash Hexer: nhóm lửa từ các lò chạy dọc sàn vào giữa phòng
			var src: Array = braziers if not braziers.is_empty() else [Vector2(arena.position.x + 60.0, fy), Vector2(arena.end.x - 60.0, fy)]
			for b in src:
				var dirx: float = 1.0 if float(b.x) < arena.get_center().x else -1.0
				FX.burst(get_parent(), Vector2(b.x, b.y - 20.0), Color(1.0, 0.6, 0.2), 10, 120.0)
				_zone("firewave", Rect2(float(b.x) - 20.0, float(b.y) - 48.0, 40.0, 48.0), 0.5, 3.2, Vector2(dirx * 230.0, 0.0))
		"wind_veil":   # Hollow Wraith: tắt đèn phòng, biến mất rồi hiện sau lưng người chơi
			_dark_t = 5.0
			darkness.emit(true)
			if form in FLYERS:   # dạng đi bộ (Lord echo) chỉ tối phòng, không dịch chuyển
				state = "fade_out"
				_t = 0.3
		"wind_heat":   # Dungeon Lord: một số bục nóng đỏ gây sát thương, buộc phải đổi chỗ đứng
			if platforms.is_empty():
				_summon()
				return
			var pool: Array = platforms.duplicate()
			pool.shuffle()
			for i in maxi(1, int(ceil(pool.size() * 0.6))):
				var r: Rect2 = pool[i]
				_dust(Vector2(r.get_center().x, r.position.y))
				_zone("heat", Rect2(r.position.x, r.position.y - 40.0, r.size.x, 44.0), 0.9, 3.0)
		"wind_hurl":   # Bone Brute: ném ba xương ngang sàn/ngang ngực về phía người chơi, tốc độ lệch nhau (đạn nên đỡ được, bị đỡ thì phản lại)
			var hs: float = 1.0 if p.global_position.x >= global_position.x else -1.0
			for i in HURL_SPEEDS.size():
				var s := Area2D.new()
				s.set_script(PROJECTILE)
				s.friendly = false
				s.radius = 11.0
				s.life = 3.0
				s.color = Color(0.9, 0.88, 0.78)
				s.vel = Vector2(hs * float(HURL_SPEEDS[i]), 0.0)
				get_parent().add_child.call_deferred(s)
				s.position = Vector2(global_position.x + hs * 40.0, fy - (14.0 if i != 1 else 30.0))
			shake.emit(1.5)
		"wind_cage":   # Bone Brute: gai xương trồi hai bên người chơi rồi khép lại; nhảy lên hoặc dash ra ngoài (không đỡ được)
			for g in CAGE_GAP.size():
				for sgc in [-1.0, 1.0]:
					var xc: float = clampf(p.global_position.x + sgc * float(CAGE_GAP[g]), arena.position.x + 60.0, arena.end.x - 60.0)
					_dust(Vector2(xc, fy))
					_zone("spikes", Rect2(xc - 20.0, fy - 44.0, 40.0, 44.0), 0.6 + 0.7 * float(g), 2.5)
			shake.emit(2.0)
		"wind_geyser":   # Drowned Colossus: cột nước phun lần lượt từ chân boss về phía người chơi (không đỡ được); nhảy qua khe hoặc dash
			var sgg: float = 1.0 if p.global_position.x >= global_position.x else -1.0
			for i in GEYSER_N:
				var xg: float = clampf(global_position.x + sgg * (110.0 + 90.0 * float(i)), arena.position.x + 40.0, arena.end.x - 40.0)
				_dust(Vector2(xg, fy))
				_zone("geyser", Rect2(xg - 20.0, fy - 110.0, 40.0, 110.0), 0.3 + 0.25 * float(i), 0.7)
			shake.emit(1.5)
		"wind_volley":   # Drowned Colossus: bong bóng chậm bắn quạt (không sát thương, chạm thì chậm 2s), sau đó dậm đất
			var base: Vector2 = (p.global_position - global_position).normalized()
			for i in VOLLEY_N:
				var sb := Area2D.new()
				sb.set_script(PROJECTILE)
				sb.friendly = false
				sb.slows = true
				sb.radius = 12.0
				sb.life = 4.0
				sb.color = Color(0.5, 0.8, 1.0, 0.7)
				sb.vel = base.rotated((float(i) - float(VOLLEY_N - 1) * 0.5) * 0.22) * 170.0
				sb.popped.connect(func(): sfx.emit("pop"))
				get_parent().add_child.call_deferred(sb)
				sb.position = position
		"wind_undertow":   # Drowned Colossus: xoáy nước 1.5s quanh boss kéo người chơi vào (không sát thương; chạm boss mới đau); nhảy lên bục hoặc dash ra
			sfx.emit("rumble")
			var ut: Node2D = _zone("undertow", Rect2(global_position.x - 260.0, fy - 120.0, 520.0, 120.0), 0.2, 1.5)
			ut.pull_x = global_position.x
		"wind_ember":   # Ash Hexer: thả tàn lửa xuống sàn quanh người chơi, mỗi điểm nằm 2s
			for i in EMBER_N:
				var xe: float = clampf(p.global_position.x + randf_range(-260.0, 260.0), arena.position.x + 60.0, arena.end.x - 60.0)
				FX.burst(get_parent(), Vector2(xe, global_position.y), Color(1.0, 0.55, 0.2), 4, 80.0)
				_zone("flame", Rect2(xe - 20.0, fy - 28.0, 40.0, 28.0), 0.5 + 0.12 * float(i), 2.0)
			shake.emit(1.0)
		"wind_tide":   # Drowned Colossus: nước dâng (TIDE_H, hoặc 80px khi phòng không có bục) trong 0.8s, giữ rồi rút; làm chậm, có bục thì chìm (mất mặt nạ sau 2s) + dòng chảy kéo về phía boss; bục cao thì an toàn
			sfx.emit("rumble")
			var safe: bool = not platforms.is_empty()   # có bục để trú thì nước nguy hiểm (chìm + dòng chảy), không thì như cũ (80px, chỉ làm chậm)
			var th: float = TIDE_H if safe else 80.0
			_dust(Vector2(arena.position.x + 48.0, fy))   # sóng dâng từ hai bờ báo trước
			_dust(Vector2(arena.end.x - 48.0, fy))
			var zt: Node2D = _zone("water", Rect2(arena.position.x + 32.0, fy - th, arena.size.x - 64.0, th), 0.6, 4.5)
			zt.drown = safe
			zt.pull_x = global_position.x
			shake.emit(1.5)

func _shockwave() -> void:
	shake.emit(3.0)
	var speed: float = 360.0 if phase == 1 else 440.0
	for sgn in [-1.0, 1.0]:
		var s := Area2D.new()
		s.set_script(PROJECTILE)
		s.friendly = false
		s.radius = 14.0
		s.life = 1.8
		s.color = Color(1.0, 0.75, 0.4)
		s.vel = Vector2(float(sgn) * speed, 0.0)
		get_parent().add_child.call_deferred(s)
		s.position = Vector2(global_position.x + float(sgn) * 40.0, global_position.y + _size.y * 0.5 - 14.0)

## Hexer triệu một quỷ bay nhỏ cạnh mình (tối đa 3 con sống cùng lúc).
func _conjure() -> void:
	if get_tree().get_nodes_in_group("hk_enemy").size() >= 3:
		return
	var e := CharacterBody2D.new()
	e.set_script(ENEMY)
	e.kind = "flyer"
	get_parent().add_child.call_deferred(e)
	e.position = _clamp_arena(global_position + Vector2(float(-dir) * 70.0, 20.0))
	FX.burst(get_parent(), global_position, DATA[kind]["color"], 10, 180.0)

func _summon() -> void:
	var alive: int = get_tree().get_nodes_in_group("hk_enemy").size()
	for sgn in [-1.0, 1.0]:
		if alive >= 4:
			break
		var e := CharacterBody2D.new()
		e.set_script(ENEMY)
		e.kind = "crawler"
		get_parent().add_child.call_deferred(e)
		e.position = Vector2(clampf(global_position.x + float(sgn) * 150.0, arena.position.x + 60.0, arena.end.x - 60.0), global_position.y + _size.y * 0.5 - 12.0)
		alive += 1
	FX.burst(get_parent(), global_position, Color(0.8, 0.3, 0.3), 14, 200.0)

# ------------------------------------------------------------ bay (wraith)
func _wraith(delta: float, p: Node2D) -> void:
	var speed: float = float(DATA[form]["speed"]) * (1.3 if phase >= 2 else 1.0)
	match state:
		"hover":
			_face(p)
			var target := Vector2(p.global_position.x + sin(_time * 1.3) * 200.0, p.global_position.y - 140.0)   # cũ 150 với hộp 70 cao; hộp mới thấp hơn nên hạ 10 để đáy giữ nguyên tầm nhảy-chém (~-115)
			target = _clamp_arena(target)
			velocity = (target - global_position).limit_length(speed)
			if _t <= 0.0 and not _maybe_shift():
				var r: int = randi() % 3
				if form == "hexer" and r == 1:   # hexer không bổ nhào: thay bằng triệu hồi
					r = 3
				if SKILL.has(form) and _dark_t <= 0.0 and randf() < (0.45 if phase >= 2 else 0.3):   # đòn riêng
					r = 4
				elif form == "hexer" and randf() < 0.25:   # mưa tàn lửa: ≤1/4 mỗi lượt
					r = 5
				if r == 0:
					state = "wind_bolt"
					_t = 0.55
					_combo = 1 if (form == "hexer" and (phase >= 2 or randf() < 0.4)) else 0   # hexer: quạt đôi
				elif r == 1:
					state = "wind_dive"
					_t = 0.75
					_dive_x = p.global_position.x
					_markers.append({"x": _dive_x, "t": 0.75})
				elif r == 4:
					state = String(SKILL[form])
					_t = 0.8
				elif r == 5:
					state = "wind_ember"
					_t = 0.7
				elif r == 3:
					state = "wind_conjure"
					_t = 0.8
				else:
					state = "fade_out"
					_t = 0.3
		"wind_conjure":
			velocity = Vector2.ZERO
			_face(p)
			if _t <= 0.0:
				_conjure()
				state = "hover"
				_t = 1.4
		"wind_torch", "wind_veil", "wind_ember":
			velocity = Vector2.ZERO
			_face(p)
			if _t <= 0.0:
				_cast(p)
				if state != "fade_out":
					state = "hover"
					_t = 1.4
		"wind_bolt":
			velocity = Vector2.ZERO
			_face(p)
			if _t <= 0.0:
				_fire_fan(p)
				if _combo > 0:
					_combo -= 1
					_t = 0.45   # quạt thứ hai ngay sau quạt đầu (state giữ wind_bolt)
				else:
					state = "hover"
					_t = 1.3
		"wind_dive":
			velocity = Vector2.ZERO
			if _t <= 0.0:
				state = "dive"
				_t = 1.5
		"dive":
			var tx: float = move_toward(global_position.x, _dive_x, 500.0 * delta)
			global_position.x = tx
			velocity = Vector2(0, 820.0)
			if global_position.y > arena.end.y - 90.0 or _t <= 0.0 or _hits_floor():
				shake.emit(2.0)
				state = "dive_land"
				_t = 0.5
				velocity = Vector2.ZERO
		"dive_land":
			velocity = Vector2.ZERO
			if _t <= 0.0:
				if randf() < (0.65 if phase >= 2 else 0.25):   # bổ nhào lần hai: pha 1 cũng có (cũ: chỉ pha 2, 0.5)
					_dive_x = p.global_position.x
					_markers.append({"x": _dive_x, "t": 0.5})
					state = "wind_dive"
					_t = 0.5
					global_position.y = arena.position.y + 120.0
				else:
					state = "hover"
					_t = 1.0
		"fade_out":
			velocity = Vector2.ZERO
			_alpha = clampf(_t / 0.3, 0.0, 1.0)
			if _t <= 0.0:
				var side: float = -1.0 if p.global_position.x > arena.get_center().x else 1.0
				global_position = _clamp_arena(Vector2(arena.get_center().x + side * minf(arena.size.x * 0.3, 380.0), p.global_position.y - 120.0))
				state = "fade_in"
				_t = 0.3
		"fade_in":
			_alpha = clampf(1.0 - _t / 0.3, 0.0, 1.0)
			if _t <= 0.0:
				_alpha = 1.0
				state = "wind_bolt"
				_t = 0.4
	global_position += velocity * delta
	global_position = _clamp_arena(global_position)

func _hits_floor() -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2(0, _size.y * 0.5 + 6.0), 1)
	return not get_world_2d().direct_space_state.intersect_ray(q).is_empty()

func _clamp_arena(v: Vector2) -> Vector2:
	return Vector2(clampf(v.x, arena.position.x + 60.0, arena.end.x - 60.0), clampf(v.y, arena.position.y + 70.0, arena.end.y - 60.0))

func _fire_fan(p: Node2D) -> void:
	var n: int = 3 if phase == 1 else 5
	var base: Vector2 = (p.global_position - global_position).normalized()
	for i in n:
		var ang: float = (float(i) - float(n - 1) * 0.5) * 0.28
		var s := Area2D.new()
		s.set_script(PROJECTILE)
		s.friendly = false
		s.radius = 10.0
		s.life = 2.2
		s.color = Color(0.7, 0.85, 1.0)
		s.vel = base.rotated(ang) * 330.0
		get_parent().add_child.call_deferred(s)
		s.position = position

# ------------------------------------------------------------ chung
func _update_markers(delta: float) -> void:
	for m in _markers:
		m["t"] = float(m["t"]) - delta
	for m in _markers.duplicate():
		if float(m["t"]) <= 0.0:
			_markers.erase(m)
			if _lordlike():
				var s := Area2D.new()
				s.set_script(PROJECTILE)
				s.friendly = false
				s.radius = 16.0
				s.life = 2.5
				s.color = Color(0.6, 0.5, 0.45)
				s.vel = Vector2(0, 720.0)
				get_parent().add_child.call_deferred(s)
				s.position = Vector2(float(m["x"]), arena.position.y + 40.0)

func body_rect() -> Rect2:
	return Rect2(global_position - _size * 0.5, _size)

func attack_rect() -> Rect2:
	return _attack_rect()

func _attack_rect() -> Rect2:
	if state == "lunge":
		return Rect2(global_position + Vector2(float(dir) * (_size.x * 0.5 + 45.0) - 45.0, -_size.y * 0.4), Vector2(90, _size.y * 0.8))
	return Rect2()

func _touch_damage(p: Node2D) -> void:
	if state == "dormant" or state == "intro" or state == "wind_shift" or state == "stagger" or _alpha < 0.9:
		return
	var pr := Rect2(p.global_position - p.BODY * 0.5, p.BODY)
	var body := Rect2(global_position - _size * 0.5, _size)
	if pr.intersects(body) or (state == "lunge" and pr.intersects(_attack_rect())):
		p.take_damage(global_position.x, 1, state != "rush")

## Người chơi đỡ trúng đòn của boss: choáng `sec` giây, tối đa một lần mỗi STAGGER_CD; không áp dụng lúc ngủ/giới thiệu/đổi dạng.
func stagger(sec: float) -> void:
	if hp <= 0 or _stagger_cd > 0.0 or state in ["dormant", "intro", "wind_shift", "stagger"]:
		return
	_stagger_cd = STAGGER_CD
	state = "stagger"
	_t = sec
	_alpha = 1.0
	_markers.clear()
	velocity = Vector2.ZERO

func take_hit(dmg: int, _from: Vector2) -> bool:   # luôn true (không có khiên); thống nhất chữ ký với enemy.take_hit
	if hp <= 0 or state == "dormant" or state == "intro" or state == "wind_shift":
		return true
	hp -= dmg
	_flash = 0.08
	var want: int = phase
	if kind == "many_faced":   # 3 pha: 66% và 33% máu
		want = 3 if hp * 3 <= max_hp else (2 if hp * 3 <= max_hp * 2 else 1)
	elif kind in EARLY_P2 and hp * 3 <= max_hp * 2:   # mini-boss hạ trong ~7-9s vào pha 2 sớm hơn (66% thay vì 50%) để thấy pha 2
		want = 2
	elif hp <= max_hp / 2:
		want = 2
	if want > phase:
		phase = want
		phase_changed.emit(phase)
		state = "intro"
		_t = 0.7
		shake.emit(3.0)
		_markers.clear()
		if kind == "many_faced":
			if phase == 3:
				_set_form("sovereign")
				_tinted = true
				tinted.emit(Color(0.9, 0.78, 1.0))
			else:
				_form_t = 0.0
	if hp <= 0:
		FX.death(get_parent(), global_position, DATA[kind]["color"], true)
		shake.emit(5.0)
		defeated.emit()
		queue_free()
	return true

## Báo hiệu "đổi dạng" của many_faced: vòng nở quanh người (không phải vùng cảnh báo đòn đánh; các vùng/vạch đỏ đã bỏ).
func _draw_shift_ring(h: Vector2) -> void:
	if state == "wind_shift":
		var ks: float = 1.0 - clampf(_t / 0.9, 0.0, 1.0)
		draw_arc(Vector2.ZERO, lerpf(24.0, maxf(h.x, h.y) + 50.0, ks), 0.0, TAU, 32, Color(0.75, 0.5, 1.0, 0.3 + 0.5 * ks), 3.0)

## Sắc riêng của hai boss cuối để phân biệt: Gatekeeper (Lord đủ ký ức) trắng-vàng, dạng sovereign tím. Chỉ vẽ.
func _look_tint() -> Color:
	if empowered:
		return Color(1.55, 1.5, 1.15)
	if form == "sovereign":
		return Color(1.0, 0.8, 1.35)
	return LOOK[form].get("tint", Color.WHITE)

func _draw_aura(h: Vector2) -> void:
	var r: float = maxf(h.x, h.y)
	if empowered:   # vầng sáng + 6 đèn ký ức trên đầu boss (sáng = ký ức đã có; đèn cuối là ký ức của chính Lord)
		draw_circle(Vector2.ZERO, r * 1.15, Color(1.0, 0.92, 0.6, 0.16 + 0.05 * sin(_time * 3.0)))
		draw_arc(Vector2.ZERO, r * 1.15, 0.0, TAU, 48, Color(1.0, 0.95, 0.7, 0.55), 2.0)
		for k in 6:   # hàng đèn lơ lửng trên đầu boss (luôn nằm trong khung hình, trên thanh máu)
			var c: Vector2 = Vector2((float(k) - 2.5) * 36.0, -h.y - 60.0)
			var lit: bool = k < lanterns
			draw_circle(c, 14.0 if lit else 8.0, Color(0.4, 0.9, 1.0, 0.18) if lit else Color(0.3, 0.35, 0.45, 0.12))
			draw_circle(c, 6.0 if lit else 4.0, Color(0.6, 0.95, 1.0, 0.95) if lit else Color(0.35, 0.4, 0.5, 0.7))
	elif form == "sovereign":   # sáu "gương mặt" nhạt xoay quanh thân
		for k in 6:
			var a: float = _time * 0.8 + TAU * float(k) / 6.0
			var c: Vector2 = Vector2(cos(a), sin(a) * 0.7) * (r * 1.05 + 18.0)
			draw_circle(c, 11.0, Color(0.8, 0.65, 1.0, 0.55))
			draw_circle(c + Vector2(-3.5, -2.0), 1.8, Color(0.1, 0.05, 0.2))
			draw_circle(c + Vector2(3.5, -2.0), 1.8, Color(0.1, 0.05, 0.2))

func _draw() -> void:
	var tint := _look_tint()
	if _flash > 0.0:
		tint = Color(3, 3, 3, _alpha)
	elif (state == "wind_rush" or state == "rush" or state == "wind_sweep") and int(_time * 30.0) % 2 == 0:
		tint = Color(1.8, 1.5, 0.4, _alpha)   # vàng = không đỡ được, phải né
	elif (state.begins_with("wind") or state == "fade_out") and int(_time * 30.0) % 2 == 0:
		tint = Color(1.6, 0.8, 0.8, _alpha)
	else:
		tint.a = _alpha
	var h: Vector2 = _size * 0.5
	_draw_aura(h)
	var look: Dictionary = LOOK[form]
	SPRITES.draw_body(self, String(look["anim"]), Vector2(0, h.y), float(look["scale"]), dir < 0, tint, 6.0)
	if not (form in FLYERS) and state == "lunge":
		draw_rect(Rect2(float(dir) * (h.x + 45.0) - 45.0, -h.y * 0.8, 90, _size.y * 0.8), Color(1, 1, 1, 0.55))
	_draw_shift_ring(h)
	if state != "dormant":
		var w: float = clampf(_size.x * 1.6, 120.0, 220.0)   # thanh máu ngay trên đỉnh phần nhìn thấy, rộng theo cỡ boss
		draw_rect(Rect2(-w * 0.5, -h.y - 18, w, 8), Color(0.05, 0.05, 0.1, 0.85))
		draw_rect(Rect2(-w * 0.5 + 1.0, -h.y - 17, (w - 2.0) * float(hp) / float(max_hp), 6), Color(0.95, 0.4, 0.35))
