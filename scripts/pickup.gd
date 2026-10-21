extends Area2D
## Vật phẩm / cổng: kind = coin | heal | weapon | portal. Xu/bình máu/cổng nhặt bằng signal body_entered;
## VŨ KHÍ thì KHÔNG tự nhặt: đứng gần và bấm "interact" (E). Còn ô trống thì vào ô trống, đủ ô thì đổi với
## vũ khí đang cầm và vũ khí cũ được thả xuống chỗ này (qua Global.weapon_drop_requested).
const WeaponInstance = preload("res://scripts/weapon_instance.gd")

const WeaponInfo = preload("res://scripts/weapon_info.gd")

## Sau khi xuất hiện, vũ khí chưa nhặt được trong khoảng này (giây) — tránh nhặt nhầm ngay vũ khí vừa thả.
const WEAPON_PICKUP_LOCK: float = 0.4
## Số ký tự tối đa mỗi dòng đặc tính trên thẻ so sánh (font 12px, thẻ rộng 280px).
const CARD_WRAP_CHARS: int = 42

@onready var sprite: AnimatedSprite2D = $Sprite

var kind: String = "coin"
var extra: String = ""
var weapon_id: String = ""
var weapon_rarity: String = "common"
## Cây vũ khí mà pickup này đại diện (WeaponInstance) — mã hóa trong `extra` dạng "id:rarity:level:aff1,aff2".
var weapon_inst: Dictionary = {}
var _t: float = 0.0
var _icon_tex: Texture2D
var _near: bool = false
var _lock: float = 0.0
## Khung hình gần nhất có vũ khí được nhặt — chặn 2 vũ khí cùng nhặt trong 1 lần bấm E (khi cách đều Player).
static var _taken_frame: int = -1

func setup(p_kind: String, p_extra: String = "") -> void:
	kind = p_kind
	extra = p_extra
	if kind == "weapon":
		weapon_inst = WeaponInstance.decode(extra)
		if weapon_inst.is_empty():
			weapon_inst = WeaponInstance.make("pistol", "common") # mã hỏng -> vũ khí cơ bản thay vì crash
		weapon_id = String(weapon_inst["id"])
		weapon_rarity = String(weapon_inst["rarity"])
		_icon_tex = Global.load_tex("res://assets/dungeon/weapon_%s.png" % weapon_id)

func _ready() -> void:
	collision_layer = Global.L_PICKUP
	collision_mask = Global.L_PLAYER
	var s := CircleShape2D.new()
	s.radius = 28.0 if (kind == "portal" or kind == "council_portal") else 14.0
	$Shape.shape = s
	body_entered.connect(_on_body_entered)
	if kind == "weapon":
		add_to_group("weapon_pickup")
		_lock = WEAPON_PICKUP_LOCK
		body_exited.connect(_on_body_exited)
	if kind == "portal" or kind == "council_portal":
		set_deferred("monitoring", false)
		get_tree().create_timer(1.0).timeout.connect(_arm)
	_setup_sprite()


## "coin" và "heal" dùng sprite 0x72 thật. "portal" vẫn vẽ hẳn bằng code (hiệu ứng
## cổng không có asset tĩnh tương ứng). "weapon" giờ dùng icon pixel-art thật
## (weapon_<id>.png, vẽ bằng draw_texture_rect trong _draw() bên dưới) nhưng vòng màu
## độ hiếm + tên vũ khí vẫn phải vẽ đè bằng code vì asset tĩnh không mang được thông tin đó.
## Coin là pickup rơi ra nhiều nhất trong game (gần như mỗi quái chết đều rơi) nên
## cache SpriteFrames dùng chung, tránh load lại 4 ảnh từ đĩa mỗi lần rơi 1 đồng xu.
static var _coin_frames: SpriteFrames
static var _heal_frames: SpriteFrames

func _setup_sprite() -> void:
	match kind:
		"coin":
			if _coin_frames == null:
				_coin_frames = SpriteFrames.new()
				_coin_frames.add_animation("spin")
				_coin_frames.set_animation_speed("spin", 8.0)
				_coin_frames.set_animation_loop("spin", true)
				for i in 4:
					var tex := Global.load_tex("res://assets/dungeon/coin_anim_f%d.png" % i)
					if tex:
						_coin_frames.add_frame("spin", tex)
			sprite.sprite_frames = _coin_frames
			sprite.scale = Vector2(1.5, 1.5)
			sprite.play("spin")
		"heal":
			if _heal_frames == null:
				_heal_frames = SpriteFrames.new()
				var tex := Global.load_tex("res://assets/dungeon/flask_red.png")
				if tex:
					_heal_frames.add_frame("default", tex)
			sprite.sprite_frames = _heal_frames
			sprite.scale = Vector2(1.8, 1.8)
			sprite.play("default")
		_:
			sprite.visible = false

func _arm() -> void:
	monitoring = true

func _process(delta: float) -> void:
	_t += delta
	var bob: float = sin(_t * 5.0) * 3.0
	sprite.position.y = bob
	if kind == "weapon":
		_lock = maxf(0.0, _lock - delta)
		if _near and _lock <= 0.0 and Input.is_action_just_pressed("interact"):
			_try_take()
	queue_redraw()

func _on_body_exited(body: Node) -> void:
	if kind == "weapon" and body.is_in_group("player"):
		_near = false

## Vũ khí chỉ nhặt được khi đây là vũ khí GẦN Player nhất trong số các vũ khí đang trong tầm (tránh nhặt nhầm khi có 2 món).
func _is_nearest_candidate(player_pos: Vector2) -> bool:
	var my_d: float = global_position.distance_squared_to(player_pos)
	for other in get_tree().get_nodes_in_group("weapon_pickup"):
		if other == self or not other._near or other._lock > 0.0:
			continue
		if other.global_position.distance_squared_to(player_pos) < my_d:
			return false
	return true

func _try_take() -> void:
	var player: Node = Global.player
	if not is_instance_valid(player) or not player.alive or not player.has_method("equip_weapon"):
		return
	if _taken_frame == Engine.get_process_frames() or not _is_nearest_candidate(player.global_position):
		return
	_taken_frame = Engine.get_process_frames()
	var displaced: Dictionary = player.equip_weapon(weapon_inst)
	if not displaced.is_empty():
		Global.weapon_drop_requested.emit(displaced, global_position)
	Global.sfx("pickup")
	queue_free()

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if kind == "weapon":
		_near = true
		return
	match kind:
		"coin":
			Global.add_coin()
		"heal":
			body.heal(20)
		"portal":
			Global.portal_entered.emit()
		"council_portal":
			Global.council_portal_entered.emit()
	Global.sfx("pickup")
	queue_free()

## Ánh sáng quanh vũ khí theo độ hiếm: Rare/Epic/Legendary có vầng sáng nhấp nháy; Epic/Legendary thêm cột sáng hướng lên.
func _draw_rarity_glow(color: Color, rarity: String, bob: float) -> void:
	var tier: int = ["common", "rare", "epic", "legendary", "mythic"].find(rarity)
	if tier <= 0:
		return
	var pulse: float = 0.5 + 0.5 * sin(_t * 3.0)
	draw_circle(Vector2(0.0, bob), 20.0 + 4.0 * pulse, Color(color, 0.10 + 0.05 * float(tier)))
	draw_circle(Vector2(0.0, bob), 15.0 + 2.0 * pulse, Color(color, 0.16))
	if tier >= 2:
		var h: float = 34.0 + 14.0 * float(tier - 2)
		draw_line(Vector2(0.0, bob - 14.0), Vector2(0.0, bob - 14.0 - h), Color(color, 0.30 + 0.2 * pulse), 4.0)
		draw_line(Vector2(0.0, bob - 14.0), Vector2(0.0, bob - 14.0 - h * 0.7), Color(1.0, 1.0, 1.0, 0.35), 1.5)
	if tier >= 4: # Mythic: thêm vòng xoáy nhấp nháy hai bên
		draw_arc(Vector2(0.0, bob), 24.0 + 3.0 * pulse, _t * 2.0, _t * 2.0 + PI * 1.2, 20, Color(color, 0.7), 2.0)
		draw_arc(Vector2(0.0, bob), 24.0 + 3.0 * pulse, _t * 2.0 + PI, _t * 2.0 + PI * 2.2, 20, Color(color, 0.7), 2.0)

## Thẻ so sánh khi đứng gần: gợi ý phím + DPS / sát thương / tốc độ so với vũ khí đang cầm (xanh = tốt hơn, đỏ = kém hơn) + đặc tính.
func _draw_compare_card() -> void:
	var p = Global.player
	var swap_note: String = "[E] Pick up"
	var cur_inst: Dictionary = {}
	if is_instance_valid(p):
		cur_inst = p.get("weapon_inst")
		if not p.has_free_weapon_slot():
			swap_note = "[E] Swap with %s" % String(p.weapon.get("name", "current"))
	var lines: Array = [{"text": swap_note, "color": Color.WHITE}]
	if not cur_inst.is_empty():
		lines.append({"text": "vs %s (%s)" % [WeaponInstance.display_name(cur_inst), String(Global.rarities[cur_inst["rarity"]]["name"])], "color": Color(0.7, 0.7, 0.78)})
	lines.append_array(WeaponInfo.compare_rows(weapon_inst, cur_inst))
	for t in WeaponInfo.traits(weapon_inst):
		var t_color: Color = Color(1.0, 0.55, 0.6) if String(t).begins_with("MYTHIC") else Color(0.8, 0.85, 1.0)
		for part in _wrap(String(t), CARD_WRAP_CHARS):
			lines.append({"text": part, "color": t_color})
	var line_h: float = 15.0
	var top: float = 30.0
	var panel := Rect2(Vector2(-140.0, top), Vector2(280.0, line_h * float(lines.size()) + 8.0))
	draw_rect(panel, Color(0.05, 0.05, 0.09, 0.82))
	draw_rect(panel, Color(Global.rarities[weapon_rarity]["color"], 0.8), false, 1.5)
	var y: float = top + 15.0
	for L in lines:
		if String(L["text"]) != "":
			draw_string(ThemeDB.fallback_font, Vector2(-132.0, y), String(L["text"]), HORIZONTAL_ALIGNMENT_LEFT, 264.0, 12, L["color"])
		y += line_h

## Ngắt dòng dài theo số ký tự để thẻ so sánh không bị cắt chữ (dòng nối tiếp thụt vào 2 dấu cách).
static func _wrap(text: String, max_chars: int) -> Array:
	var out: Array = []
	var cur: String = ""
	for word in text.split(" "):
		if cur != "" and cur.length() + 1 + word.length() > max_chars:
			out.append(cur)
			cur = "  " + word
		else:
			cur = word if cur == "" else cur + " " + word
	if cur != "":
		out.append(cur)
	return out

func _draw() -> void:
	var bob: float = sin(_t * 5.0) * 3.0
	match kind:
		"weapon":
			var r_data: Dictionary = Global.rarities[weapon_rarity]
			var r_color: Color = r_data["color"]
			var display_name: String = WeaponInstance.display_name(weapon_inst) + " (" + r_data["name"] + ")"
			
			_draw_rarity_glow(r_color, weapon_rarity, bob)
			draw_circle(Vector2(0.0, bob), 13.0, Color(0.1, 0.1, 0.15))
			# Vòng sáng mang màu của độ hiếm
			draw_arc(Vector2(0.0, bob), 13.0, 0.0, TAU, 24, r_color, 3.0)
			# Icon pixel-art thật của vũ khí, phóng to 1.6x cho rõ, căn giữa viên pickup
			if _icon_tex:
				var icon_size: Vector2 = Vector2(_icon_tex.get_width(), _icon_tex.get_height()) * 1.6
				var icon_pos: Vector2 = Vector2(-icon_size.x * 0.5, bob - icon_size.y * 0.5)
				draw_texture_rect(_icon_tex, Rect2(icon_pos, icon_size), false)
			# Text hiển thị Tên Vũ khí + Độ Hiếm
			draw_string(ThemeDB.fallback_font, Vector2(-100.0, bob - 22.0), display_name, HORIZONTAL_ALIGNMENT_CENTER, 200.0, 14, r_color)
			if _near:
				_draw_compare_card()
		"portal":
			var pulse: float = 1.0 + 0.1 * sin(_t * 4.0)
			draw_circle(Vector2.ZERO, 28.0 * pulse, Color(0.3, 0.2, 0.9, 0.35))
			draw_circle(Vector2.ZERO, 18.0 * pulse, Color(0.5, 0.4, 1.0, 0.6))
			draw_circle(Vector2.ZERO, 8.0, Color.WHITE)
			draw_string(ThemeDB.fallback_font, Vector2(-60.0, -38.0), "GO DOWN", HORIZONTAL_ALIGNMENT_CENTER, 120.0, 14, Color.WHITE)
		"council_portal":
			var pulse2: float = 1.0 + 0.12 * sin(_t * 5.0)
			draw_circle(Vector2.ZERO, 30.0 * pulse2, Color(0.9, 0.1, 0.15, 0.35))
			draw_circle(Vector2.ZERO, 19.0 * pulse2, Color(1.0, 0.3, 0.2, 0.6))
			draw_circle(Vector2.ZERO, 8.0, Color(1.0, 0.9, 0.7))
			draw_string(ThemeDB.fallback_font, Vector2(-70.0, -40.0), "THE COUNCIL", HORIZONTAL_ALIGNMENT_CENTER, 140.0, 14, Color(1.0, 0.5, 0.4))
