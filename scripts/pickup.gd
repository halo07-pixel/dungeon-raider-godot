extends Area2D
## Vật phẩm / cổng: kind = coin | heal | weapon | portal. Nhặt bằng signal body_entered.

@onready var sprite: AnimatedSprite2D = $Sprite

var kind: String = "coin"
var extra: String = ""
var weapon_id: String = ""
var weapon_rarity: String = "common"
var _t: float = 0.0
var _icon_tex: Texture2D

func setup(p_kind: String, p_extra: String = "") -> void:
	kind = p_kind
	extra = p_extra
	if kind == "weapon":
		var parts = extra.split(":")
		weapon_id = parts[0]
		if parts.size() > 1:
			weapon_rarity = parts[1]
		_icon_tex = Global.load_tex("res://assets/dungeon/weapon_%s.png" % weapon_id)

func _ready() -> void:
	collision_layer = Global.L_PICKUP
	collision_mask = Global.L_PLAYER
	var s := CircleShape2D.new()
	s.radius = 28.0 if kind == "portal" else 14.0
	$Shape.shape = s
	body_entered.connect(_on_body_entered)
	if kind == "portal":
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
	queue_redraw()

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	match kind:
		"coin":
			Global.add_coin()
		"heal":
			body.heal(20)
		"weapon":
			# Truyền cả ID và Rarity cho Player
			if body.has_method("set_weapon_with_rarity"):
				body.set_weapon_with_rarity(weapon_id, weapon_rarity)
			elif body.has_method("set_weapon"):
				body.set_weapon(weapon_id) # Fallback cũ
		"portal":
			Global.portal_entered.emit()
	Global.sfx("pickup")
	queue_free()

func _draw() -> void:
	var bob: float = sin(_t * 5.0) * 3.0
	match kind:
		"weapon":
			var w: Dictionary = Global.weapons[weapon_id]
			var r_data: Dictionary = Global.rarities[weapon_rarity]
			var r_color: Color = r_data["color"]
			var display_name: String = w["name"] + " (" + r_data["name"] + ")"
			
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
		"portal":
			var pulse: float = 1.0 + 0.1 * sin(_t * 4.0)
			draw_circle(Vector2.ZERO, 28.0 * pulse, Color(0.3, 0.2, 0.9, 0.35))
			draw_circle(Vector2.ZERO, 18.0 * pulse, Color(0.5, 0.4, 1.0, 0.6))
			draw_circle(Vector2.ZERO, 8.0, Color.WHITE)
			draw_string(ThemeDB.fallback_font, Vector2(-60.0, -38.0), "GO DOWN", HORIZONTAL_ALIGNMENT_CENTER, 120.0, 14, Color.WHITE)
