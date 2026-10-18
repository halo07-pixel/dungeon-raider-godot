extends Node2D
## Vật thể tương tác trong phòng sự kiện (bàn thờ, đền thử thách, rương, kho bí mật, rương thưởng).
## Bấm phím "interact" (E) khi đứng gần. Kết quả tự chứa (buff/máu/xu) xử lý tại đây; việc cần
## biết về phòng/dungeon (bắt đầu thử thách, sinh Mimic) phát qua signal `action_requested` lên dungeon
## ("call down, signal up").

const EventRooms = preload("res://scripts/event_rooms.gd")
const PICKUP = preload("res://scenes/pickup.tscn")

signal action_requested(action: String, pos: Vector2)

var kind: String = "altar" # altar | shrine | chest | cache | reward
var variant: String = "blood" # chỉ altar: blood | gold
var used: bool = false
var _near: bool = false
var _t: float = 0.0
var _label: Label
var _tex_closed: Texture2D
var _tex_open: Texture2D

func setup(p_kind: String) -> void:
	kind = p_kind

func _ready() -> void:
	z_index = 5
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = Global.L_PLAYER
	var shape := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = 44.0
	shape.shape = circ
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(func(b): if b.is_in_group("player"): _near = true)
	area.body_exited.connect(func(b): if b.is_in_group("player"): _near = false)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-70.0, -64.0)
	_label.size = Vector2(140.0, 20.0)
	_label.add_theme_font_override("font", Global.pixel_font())
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.text = _prompt()
	_label.hide()
	add_child(_label)
	if kind == "altar":
		_tex_closed = Global.load_tex("res://assets/dungeon/altar_idle.png")
		_tex_open = Global.load_tex("res://assets/dungeon/altar_used.png")
	elif kind == "shrine":
		_tex_closed = Global.load_tex("res://assets/dungeon/shrine_idle.png")
		_tex_open = Global.load_tex("res://assets/dungeon/shrine_used.png")
	elif kind in ["chest", "cache", "reward"]:
		_tex_closed = Global.load_tex("res://assets/dungeon/chest_full_open_anim_f0.png")
		_tex_open = Global.load_tex("res://assets/dungeon/chest_full_open_anim_f2.png")

func _prompt() -> String:
	match kind:
		"altar":
			if variant == "gold":
				return "[E] Offer %d gold" % EventRooms.altar_gold_cost(Global.floor_num)
			return "[E] Offer blood"
		"shrine": return "[E] Begin trial"
		"chest": return "[E] Open chest"
		"cache": return "[E] Open cache"
		"reward": return "[E] Claim reward"
	return "[E]"

func _process(delta: float) -> void:
	_t += delta
	_label.visible = _near and not used
	queue_redraw()
	if _near and not used and Input.is_action_just_pressed("interact"):
		_interact()

func _interact() -> void:
	match kind:
		"altar": _use_altar()
		"shrine": _finish("start_challenge")
		"chest": _use_chest()
		"cache": _use_cache()
		"reward": _use_reward()

func _finish(action: String = "") -> void:
	used = true
	if action != "":
		action_requested.emit(action, global_position)

# ------------------------------------------------------------------ Altar
func _use_altar() -> void:
	var p = Global.player
	if not is_instance_valid(p):
		return
	var gold: bool = variant == "gold"
	var choices: Array = Global.roll_buff_choices(EventRooms.ALTAR_CHOICES, "rare" if gold else "epic")
	if choices.is_empty():
		Global.message.emit("The altar is silent", Color(0.7, 0.7, 0.7))
		Global.sfx("altar_deny")
		return
	if gold:
		var price: int = EventRooms.altar_gold_cost(Global.floor_num)
		if Global.coins < price:
			Global.message.emit("Not enough gold (%d)" % price, Color(1.0, 0.4, 0.4))
			Global.sfx("altar_deny")
			return
		Global.coins -= price
	else:
		var cost: int = maxi(1, int(ceil(float(p.max_hp) * EventRooms.ALTAR_HP_FRACTION)))
		if p.hp <= cost:
			Global.message.emit("Too weak to offer blood", Color(1.0, 0.4, 0.4))
			Global.sfx("altar_deny")
			return
		p.hp -= cost
	used = true
	Global.shake(0.5, 0.3)
	Global.burst(global_position, Color(1.0, 0.8, 0.2) if gold else Color(0.8, 0.2, 0.9), 24, 240.0, 2.0)
	Global.sfx("altar_offer")
	# Phần thưởng là lượt chọn 1 trong N (buff_picker hiện, game tạm dừng tới khi chọn).
	Global.request_buff_choice_of(choices, "GOLD ALTAR: CHOOSE A BUFF" if gold else "BLOOD ALTAR: CHOOSE A BUFF")

# ------------------------------------------------------------------ Rương bẫy
func _use_chest() -> void:
	used = true
	var r: float = randf()
	if r < EventRooms.CHEST_GOOD:
		_pay_coins(EventRooms.CHEST_COINS)
		_spawn_pickup("heal")
		if randf() < EventRooms.CHEST_BUFF_CHANCE:
			Global.request_buff_choice()
		Global.message.emit("Treasure!", Color(1.0, 0.85, 0.3))
	elif r < EventRooms.CHEST_GOOD + EventRooms.CHEST_MIMIC:
		Global.message.emit("It's a Mimic!", Color(1.0, 0.3, 0.3))
		Global.sfx("mimic_reveal")
		action_requested.emit("spawn_mimic", global_position)
	else:
		var p = Global.player
		if is_instance_valid(p):
			p.take_damage(maxi(1, int(float(p.max_hp) * EventRooms.TRAP_HP_FRACTION)), global_position, 200.0)
		Global.burst(global_position, Color(0.9, 0.4, 0.2), 16, 220.0, 2.0)
		Global.message.emit("It was a trap!", Color(1.0, 0.5, 0.2))

# ------------------------------------------------------------------ Kho bí mật / rương thưởng
func _use_cache() -> void:
	used = true
	_pay_coins(EventRooms.SECRET_COINS)
	_spawn_pickup("heal")
	var gems: int = EventRooms.SECRET_GEM_GUARANTEED
	if randf() < EventRooms.SECRET_GEM_CHANCE:
		gems += 1
	Global.purple_gems += gems
	Global.record_secret_found() # lưu luôn cả số gem
	Global.message.emit("Secret found! +%d Purple Gem" % gems, Color(0.8, 0.3, 0.9))
	Global.request_buff_choice_of(Global.roll_buff_choices(EventRooms.SECRET_BUFF_CHOICES, "rare"), "SECRET CACHE: CHOOSE A BUFF")

func _use_reward() -> void:
	used = true
	_pay_coins(EventRooms.CHALLENGE_REWARD_COINS)
	Global.request_buff_choice()
	Global.message.emit("Trial complete!", Color(1.0, 0.85, 0.3))

func _pay_coins(n: int) -> void:
	for i in n:
		_spawn_pickup("coin")

func _spawn_pickup(k: String) -> void:
	var p = PICKUP.instantiate()
	p.setup(k)
	Global.world.add_child(p)
	p.global_position = global_position + Vector2(randf_range(-30.0, 30.0), randf_range(14.0, 44.0))

# ------------------------------------------------------------------ Vẽ
func _draw() -> void:
	match kind:
		"altar": _draw_altar()
		"shrine": _draw_shrine()
		_: _draw_chest()

const PROP_SCALE: float = 3.0 # sprite 16x16 -> 48px

## Vẽ sprite (idle/used) + bóng đổ dưới chân. Phần phát sáng/hạt do hàm gọi vẽ thêm bằng code.
func _draw_prop_sprite() -> void:
	draw_set_transform(Vector2(0, 18), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 22.0, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var tex: Texture2D = _tex_open if used else _tex_closed
	if tex == null:
		return
	var sz: Vector2 = tex.get_size() * PROP_SCALE
	draw_texture_rect(tex, Rect2(Vector2(-sz.x * 0.5, 18.0 - sz.y + 6.0), sz), false)

## Hạt sáng bay lên quanh vật thể (chỉ chạy khi chưa dùng).
func _draw_rising_motes(origin: Vector2, color: Color, count: int, spread: float, height: float) -> void:
	for i in count:
		var ph: float = fmod(_t * 0.55 + float(i) / float(count), 1.0)
		var x: float = sin(float(i) * 2.4 + _t * 1.3) * spread
		var y: float = -ph * height
		var al: float = (1.0 - ph) * 0.9
		draw_rect(Rect2(origin + Vector2(x - 1.0, y - 1.0), Vector2(2, 2)), Color(color.r, color.g, color.b, al))

func _draw_altar() -> void:
	_draw_prop_sprite()
	if used:
		return
	var glow: float = 0.5 + 0.5 * sin(_t * 3.0)
	var bowl := Vector2(0, -11)
	var gold: bool = variant == "gold"
	draw_circle(bowl, 16.0 + 4.0 * glow, Color(0.9, 0.65, 0.1, 0.14 + 0.06 * glow) if gold else Color(0.8, 0.1, 0.25, 0.12 + 0.06 * glow))
	draw_circle(bowl, 9.0 + 2.0 * glow, Color(1.0, 0.8, 0.2, 0.2 + 0.08 * glow) if gold else Color(0.9, 0.2, 0.4, 0.18 + 0.08 * glow))
	_draw_rising_motes(bowl, Color(1.0, 0.85, 0.3) if gold else Color(1.0, 0.45, 0.6), 5, 10.0, 30.0)

func _draw_shrine() -> void:
	_draw_prop_sprite()
	if used:
		return
	var pulse: float = 0.5 + 0.5 * sin(_t * 4.0)
	var rune := Vector2(0, -6)
	draw_circle(rune, 14.0 + 3.0 * pulse, Color(1.0, 0.55, 0.15, 0.14 + 0.08 * pulse))
	draw_arc(rune, 24.0 + 3.0 * pulse, 0.0, TAU, 32, Color(1.0, 0.5, 0.2, 0.35 + 0.2 * pulse), 2.0)
	_draw_rising_motes(Vector2(0, 4), Color(1.0, 0.7, 0.25), 6, 14.0, 34.0)

func _draw_chest() -> void:
	var tex: Texture2D = _tex_open if used else _tex_closed
	if tex == null:
		return
	var tint := Color(1, 1, 1)
	if kind == "cache": tint = Color(0.6, 1.0, 0.7)
	elif kind == "reward": tint = Color(1.0, 0.9, 0.4)
	var sz: Vector2 = tex.get_size() * 2.0
	draw_texture_rect(tex, Rect2(-sz * 0.5 + Vector2(0, 6), sz), false, tint)
