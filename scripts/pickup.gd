extends Area2D
## Vật phẩm / cổng: kind = coin | heal | weapon | portal. Nhặt bằng signal body_entered.

var kind: String = "coin"
var extra: String = ""
var weapon_id: String = ""
var weapon_rarity: String = "common"
var _t: float = 0.0

func setup(p_kind: String, p_extra: String = "") -> void:
	kind = p_kind
	extra = p_extra
	if kind == "weapon":
		var parts = extra.split(":")
		weapon_id = parts[0]
		if parts.size() > 1:
			weapon_rarity = parts[1]

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

func _arm() -> void:
	monitoring = true

func _process(delta: float) -> void:
	_t += delta
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
		"coin":
			draw_circle(Vector2(0.0, bob), 7.0, Color(1.0, 0.85, 0.2))
			draw_circle(Vector2(0.0, bob), 4.0, Color(1.0, 0.95, 0.5))
		"heal":
			draw_circle(Vector2(0.0, bob), 11.0, Color(0.15, 0.5, 0.2))
			draw_rect(Rect2(-2.5, bob - 7.0, 5.0, 14.0), Color(0.4, 1.0, 0.5))
			draw_rect(Rect2(-7.0, bob - 2.5, 14.0, 5.0), Color(0.4, 1.0, 0.5))
		"weapon":
			var w: Dictionary = Global.weapons[weapon_id]
			var r_data: Dictionary = Global.rarities[weapon_rarity]
			var r_color: Color = r_data["color"]
			var display_name: String = w["name"] + " (" + r_data["name"] + ")"
			
			draw_circle(Vector2(0.0, bob), 13.0, Color(0.1, 0.1, 0.15))
			# Vòng sáng mang màu của độ hiếm
			draw_arc(Vector2(0.0, bob), 13.0, 0.0, TAU, 24, r_color, 3.0)
			# Hình dạng đại diện vũ khí
			draw_line(Vector2(-6.0, bob), Vector2(8.0, bob), r_color, 5.0)
			# Text hiển thị Tên Vũ khí + Độ Hiếm
			draw_string(ThemeDB.fallback_font, Vector2(-100.0, bob - 22.0), display_name, HORIZONTAL_ALIGNMENT_CENTER, 200.0, 14, r_color)
		"portal":
			var pulse: float = 1.0 + 0.1 * sin(_t * 4.0)
			draw_circle(Vector2.ZERO, 28.0 * pulse, Color(0.3, 0.2, 0.9, 0.35))
			draw_circle(Vector2.ZERO, 18.0 * pulse, Color(0.5, 0.4, 1.0, 0.6))
			draw_circle(Vector2.ZERO, 8.0, Color.WHITE)
			draw_string(ThemeDB.fallback_font, Vector2(-60.0, -38.0), "XUỐNG TẦNG", HORIZONTAL_ALIGNMENT_CENTER, 120.0, 14, Color.WHITE)
