extends Area2D

## Thân người thương gia dùng sprite "elf_f" (nữ yêu tinh) từ bộ asset 0x72 -
## bộ chưa được dùng cho nhân vật nào khác, giữ phong cách đồng bộ pixel art.
const SPRITE_PREFIX: String = "elf_f"
const SPRITE_SCALE: float = 2.0
const SPRITE_OFFSET_Y: float = -11.0
static var _frames_cache: SpriteFrames

@onready var sprite: AnimatedSprite2D = $Sprite2D

var player_in_range: bool = false
var shop_ui: CanvasLayer

# Các UI Container
var main_container: VBoxContainer
var gacha_container: VBoxContainer
var confirm_box: VBoxContainer
var title: Label
var interact_label: Label

# Các biến phục vụ Vòng quay CS:GO
var wheel_clip: Control
var wheel_strip: HBoxContainer
var win_id: String = ""
var win_rarity: String = ""

func _ready() -> void:
	_setup_sprite()

	# Bắt sự kiện người chơi bước vào/ra khỏi vòng tròn (Dùng to_lower để không phân biệt hoa thường)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Tạo dòng chữ nhắc nhở
	interact_label = Label.new()
	interact_label.text = "[ENTER] Open Shop"
	interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interact_label.position = Vector2(-75, -60)
	_apply_font(interact_label, 14)
	interact_label.add_theme_color_override("font_outline_color", Color.BLACK)
	interact_label.add_theme_constant_override("outline_size", 4)
	interact_label.hide()
	add_child(interact_label)

	_build_shop_ui()


## Nạp sprite idle "elf_f" (dùng chung cache tĩnh vì chỉ có 1 NPC thương gia,
## nhưng theo cùng pattern cache per-kind đã áp dụng cho enemy/pickup).
func _setup_sprite() -> void:
	if _frames_cache == null:
		_frames_cache = SpriteFrames.new()
		_frames_cache.add_animation("idle")
		_frames_cache.set_animation_speed("idle", 6.0)
		_frames_cache.set_animation_loop("idle", true)
		for i in 4:
			var path: String = "res://assets/dungeon/%s_idle_anim_f%d.png" % [SPRITE_PREFIX, i]
			var tex := Global.load_tex(path)
			if tex:
				_frames_cache.add_frame("idle", tex)
	sprite.sprite_frames = _frames_cache
	sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	sprite.offset = Vector2(0.0, SPRITE_OFFSET_Y)
	sprite.play("idle")


func _apply_font(ctrl: Control, size: int) -> void:
	ctrl.add_theme_font_override("font", Global.pixel_font())
	ctrl.add_theme_font_size_override("font_size", size)


# ==========================================
# GIAO DIỆN CỬA HÀNG & GACHA
# ==========================================
func _build_shop_ui() -> void:
	shop_ui = CanvasLayer.new()
	shop_ui.layer = 105
	shop_ui.process_mode = Node.PROCESS_MODE_ALWAYS 
	add_child(shop_ui)
	
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_ui.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_ui.add_child(center)
	
	# 1. MENU CHÍNH
	main_container = VBoxContainer.new()
	main_container.add_theme_constant_override("separation", 20)
	center.add_child(main_container)
	
	# 2. KHU VỰC VÒNG QUAY CS:GO (Ẩn mặc định)
	gacha_container = VBoxContainer.new()
	gacha_container.alignment = BoxContainer.ALIGNMENT_CENTER
	gacha_container.add_theme_constant_override("separation", 15)
	gacha_container.hide()
	center.add_child(gacha_container)
	
	var pointer_top = Label.new()
	pointer_top.text = "▼"
	pointer_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pointer_top.add_theme_font_size_override("font_size", 35)
	pointer_top.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	gacha_container.add_child(pointer_top)
	
	# Ô cửa sổ băng chuyền (Cắt bỏ phần thừa)
	wheel_clip = Control.new()
	wheel_clip.custom_minimum_size = Vector2(800, 160)
	wheel_clip.clip_contents = true
	gacha_container.add_child(wheel_clip)
	
	var wheel_bg = ColorRect.new()
	wheel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	wheel_bg.color = Color(0.0, 0.0, 0.0, 0.5)
	wheel_clip.add_child(wheel_bg)
	
	wheel_strip = HBoxContainer.new()
	wheel_strip.add_theme_constant_override("separation", 10)
	wheel_clip.add_child(wheel_strip)
	
	var pointer_bot = Label.new()
	pointer_bot.text = "▲"
	pointer_bot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pointer_bot.add_theme_font_size_override("font_size", 35)
	pointer_bot.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	gacha_container.add_child(pointer_bot)
	
	# Khu vực Hỏi Ý Kiến (Trang bị hay Bỏ qua)
	confirm_box = VBoxContainer.new()
	confirm_box.alignment = BoxContainer.ALIGNMENT_CENTER
	confirm_box.add_theme_constant_override("separation", 20)
	gacha_container.add_child(confirm_box)
	
	shop_ui.hide()

# ==========================================
# CÔNG CỤ VẼ GIAO DIỆN
# ==========================================
# Tạo Nút bấm Flat 3D xịn xò
func _create_btn(text_val: String, action: Callable, min_size: Vector2, custom_color: Color) -> Button:
	var btn = Button.new()
	btn.text = text_val
	btn.custom_minimum_size = min_size
	_apply_font(btn, 14)
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = custom_color
	style_normal.corner_radius_top_left = 10
	style_normal.corner_radius_top_right = 10
	style_normal.corner_radius_bottom_left = 10
	style_normal.corner_radius_bottom_right = 10
	style_normal.border_width_bottom = 6
	style_normal.border_color = custom_color.darkened(0.4)
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = custom_color.lightened(0.2)
	
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = custom_color.darkened(0.2)
	style_pressed.border_width_bottom = 2
	style_pressed.border_width_top = 4
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	btn.pressed.connect(action)
	return btn

# Tạo 1 ô Vũ khí (Dùng chung cho Băng chuyền & Màn hình So sánh)
func _create_item_panel(w_id: String, r_str: String) -> Control:
	var w_data = Global.weapons[w_id]
	var r_data = Global.rarities[r_str]
	
	var panel = ColorRect.new()
	panel.custom_minimum_size = Vector2(150, 150)
	panel.color = Color(0.12, 0.12, 0.16)
	
	var border = ReferenceRect.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.border_color = r_data["color"]
	border.border_width = 5.0
	border.editor_only = false
	panel.add_child(border)
	
	var lbl = Label.new()
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.text = w_data["name"] + "\n\n" + r_data["name"]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", r_data["color"])
	_apply_font(lbl, 13)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(lbl)
	
	return panel

# ==========================================
# LOGIC TƯƠNG TÁC
# ==========================================
func _on_body_entered(body: Node2D) -> void:
	if body.name.to_lower() == "player":
		player_in_range = true
		interact_label.show()

func _on_body_exited(body: Node2D) -> void:
	if body.name.to_lower() == "player":
		player_in_range = false
		interact_label.hide()
		_close_shop()

func _input(event: InputEvent) -> void:
	if player_in_range and not shop_ui.visible and event.is_action_pressed("ui_accept"):
		_open_shop()
	# CHẶN KHÔNG CHO BẤM ESC NẾU ĐANG QUAY GACHA (Chỉ thoát được khi ở Main Menu)
	elif shop_ui.visible and event.is_action_pressed("ui_cancel") and main_container.visible:
		_close_shop()

func _open_shop() -> void:
	get_tree().paused = true
	_refresh_shop()
	shop_ui.show()

func _close_shop() -> void:
	shop_ui.hide()
	get_tree().paused = false

func _refresh_shop() -> void:
	for c in main_container.get_children(): c.queue_free()
		
	title = Label.new()
	title.text = "GACHA MERCHANT\nGold: %d" % Global.coins
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(title, 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	main_container.add_child(title)

	var sep = Control.new()
	sep.custom_minimum_size = Vector2(0, 15)
	main_container.add_child(sep)

	main_container.add_child(_create_btn("Standard Gacha - 25 Gold\n50% Common / 30% Rare / 15% Epic / 5% Legendary", func(): _roll_gacha(25, false), Vector2(650, 85), Color(0.2, 0.4, 0.6)))
	main_container.add_child(_create_btn("Premium Gacha - 50 Gold\nNo Common. 60% Rare / 30% Epic / 10% Legendary", func(): _roll_gacha(50, true), Vector2(650, 85), Color(0.6, 0.3, 0.6)))
	main_container.add_child(_create_btn("Health Potion - 15 Gold\nInstantly restores 50% Max HP", _buy_heal, Vector2(650, 85), Color(0.2, 0.6, 0.3)))
	main_container.add_child(_create_btn("Leave Shop", _close_shop, Vector2(650, 60), Color(0.5, 0.2, 0.2)))

# ==========================================
# THUẬT TOÁN GACHA & VÒNG QUAY CS:GO
# ==========================================
func _roll_gacha(cost: int, is_premium: bool) -> void:
	if Global.coins < cost:
		title.text = "Not enough gold! Keep grinding!"
		_refresh_ui_delayed()
		return
		
	Global.coins -= cost
	main_container.hide()
	confirm_box.hide()
	gacha_container.show()
	
	# Xác định Độ Hiếm
	var roll = randf() * 100.0
	var r_int = 1
	if is_premium:
		if roll <= 10.0: r_int = 4
		elif roll <= 40.0: r_int = 3
		else: r_int = 2
	else:
		if roll <= 5.0: r_int = 4
		elif roll <= 20.0: r_int = 3
		elif roll <= 50.0: r_int = 2
		else: r_int = 1
		
	var r_list = ["common", "rare", "epic", "legendary"]
	win_rarity = r_list[r_int - 1]
	Global.run_stats["gacha_" + win_rarity] += 1
	
	# Xác định Vũ khí theo Class
	var w_pool = ["pistol", "laser", "shotgun"] if Global.current_class == "ranger" else ["broadsword", "daggers", "hammer"]
	win_id = w_pool.pick_random()
	
	# ----------------------------------------------------
	# XÂY DỰNG BĂNG CHUYỀN CS:GO
	for c in wheel_strip.get_children(): c.queue_free()
	
	var target_index = 35 # Quả chốt nằm ở ô thứ 35
	var item_width = 150
	var item_sep = 10
	
	for i in range(45):
		if i == target_index:
			wheel_strip.add_child(_create_item_panel(win_id, win_rarity))
		else:
			var rand_r = r_list.pick_random()
			if is_premium and rand_r == "common": rand_r = "rare" # Gacha xịn thì rác nhất là Xanh
			var rand_w = w_pool.pick_random()
			wheel_strip.add_child(_create_item_panel(rand_w, rand_r))
			
	wheel_strip.position.x = 0
	
	# Thuật toán tính tọa độ Dừng (Lệch tâm ngẫu nhiên cho tự nhiên)
	var stop_offset = randf_range(-60.0, 60.0) 
	var target_x = 400.0 - (target_index * (item_width + item_sep) + (item_width / 2.0)) + stop_offset
	
	Global.sfx("door")
	
	# Trượt giảm tốc dần (Ease Out, Quartic) trong 3.5 giây
	var tween = create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(wheel_strip, "position:x", target_x, 3.5)
	tween.tween_callback(_on_spin_finished)

# ==========================================
# MÀN HÌNH SO SÁNH & XÁC NHẬN
# ==========================================
func _on_spin_finished() -> void:
	Global.sfx("pickup")
	confirm_box.show()
	for c in confirm_box.get_children(): c.queue_free()
		
	var lbl = Label.new()
	lbl.text = "GACHA RESULT!"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(lbl, 20)
	confirm_box.add_child(lbl)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 60)
	confirm_box.add_child(hbox)
	
	# 1. Lấy thông số súng Cũ
	var cur_id = "pistol"
	var cur_r = "common"
	if is_instance_valid(Global.player):
		cur_id = Global.player.weapon_id
		cur_r = Global.player.weapon_rarity
		
	var v_old = VBoxContainer.new()
	var l_old = Label.new()
	l_old.text = "CURRENTLY EQUIPPED"
	l_old.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(l_old, 12)
	v_old.add_child(l_old)
	v_old.add_child(_create_item_panel(cur_id, cur_r))
	hbox.add_child(v_old)
	
	# 2. Mũi tên >>
	var arrow = Label.new()
	arrow.text = ">>"
	arrow.add_theme_font_size_override("font_size", 45)
	arrow.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	hbox.add_child(arrow)
	
	# 3. Thông số súng Mới
	var v_new = VBoxContainer.new()
	var l_new = Label.new()
	l_new.text = "NEWLY WON"
	l_new.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(l_new, 12)
	l_new.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	v_new.add_child(l_new)
	v_new.add_child(_create_item_panel(win_id, win_rarity))
	hbox.add_child(v_new)
	
	# 4. Nút Quyết định
	var btn_box = HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 40)
	confirm_box.add_child(btn_box)
	
	btn_box.add_child(_create_btn("EQUIP NEW", _equip_new, Vector2(250, 60), Color(0.2, 0.6, 0.3)))
	btn_box.add_child(_create_btn("KEEP CURRENT", _discard_new, Vector2(250, 60), Color(0.7, 0.2, 0.2)))


func _equip_new() -> void:
	if is_instance_valid(Global.player) and Global.player.has_method("set_weapon_with_rarity"):
		Global.player.set_weapon_with_rarity(win_id, win_rarity)
	_reset_to_shop()

func _discard_new() -> void:
	_reset_to_shop()

func _reset_to_shop() -> void:
	gacha_container.hide()
	main_container.show()
	_refresh_shop()


# ==========================================
# CÁC CHỨC NĂNG KHÁC
# ==========================================
func _buy_heal() -> void:
	if Global.coins < 15:
		title.text = "Not enough gold!"
		_refresh_ui_delayed()
		return
	if is_instance_valid(Global.player):
		if Global.player.hp >= Global.player.max_hp:
			title.text = "Your HP is already full!"
			_refresh_ui_delayed()
			return
		Global.coins -= 15
		var heal_amount = int(float(Global.player.max_hp) * 0.5)
		Global.player.heal(heal_amount)
		title.text = "Potion used! Restored %d HP!" % heal_amount
		_refresh_ui_delayed()

func _refresh_ui_delayed() -> void:
	await get_tree().create_timer(1.2).timeout
	if shop_ui.visible and main_container.visible:
		_refresh_shop()
