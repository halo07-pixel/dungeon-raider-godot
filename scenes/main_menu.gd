extends Control
## Main Menu: Tự động căn giữa, giao diện bóng bẩy, tích hợp nút Tiếp Tục (Load Game),
## MÀN HÌNH CHỌN CLASS, CẨM NANG TRA CỨU, và CÂY KỸ NĂNG (Tiêu Ngọc Tím).

var ui_layer: CanvasLayer
var main_node: CenterContainer
var index_node: MarginContainer
var class_node: CenterContainer 
var upgrade_node: MarginContainer # Node cho Cây Kỹ Năng

# --- Dữ liệu hệ thống Kỹ năng ---
var upg_data = {
	"hp_boost": {"name": "💪 Thể Lực Hơn Người", "desc": "+10 HP tối đa mỗi cấp.", "max": 10},
	"start_coin": {"name": "💰 Tư Bản Cốt Lõi", "desc": "+10 Xu khởi điểm khi tạo game mới.", "max": 5},
	"mastery": {"name": "⚔️ Thông Thạo Vũ Khí", "desc": "+5% Sát thương gốc.", "max": 5},
	"revive": {"name": "🔥 Phượng Hoàng Lửa", "desc": "Hồi sinh 1 lần với 50% HP khi Game Over.", "max": 1}
}
var upg_ui_elements = {} # Lưu trữ các nút/chữ để tự động cập nhật
var gem_label: Label

func _ready() -> void:
	for c in get_children():
		c.queue_free()
		
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	
	var bg = ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.1, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(bg)
	
	_build_main_menu()
	_build_index_menu()
	_build_class_menu()
	_build_upgrade_menu() # Xây Cây Kỹ Năng
	
	show_main_menu()

# ==========================================
# 1. XÂY DỰNG SẢNH CHÍNH (MAIN MENU)
# ==========================================
func _build_main_menu() -> void:
	main_node = CenterContainer.new()
	main_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(main_node)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_node.add_child(vbox)
	
	var title = Label.new()
	title.text = "DUNGEON RAIDER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 65)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title.add_theme_color_override("font_shadow_color", Color(0.8, 0.2, 0.1))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 12)
	vbox.add_child(title)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)
	
	var has_save = not Global.saved_run.is_empty()
	
	if has_save:
		vbox.add_child(_create_btn("TIẾP TỤC HÀNH TRÌNH", _continue_game, Vector2(400, 60), Color(0.3, 0.8, 0.4)))
		vbox.add_child(_create_btn("TRÒ CHƠI MỚI (XÓA SAVE)", show_class_menu, Vector2(400, 60), Color(0.8, 0.3, 0.3)))
	else:
		vbox.add_child(_create_btn("BẮT ĐẦU TRÒ CHƠI", show_class_menu, Vector2(400, 60)))
		
	vbox.add_child(_create_btn("CÂY KỸ NĂNG", show_upgrade_menu, Vector2(400, 60), Color(0.6, 0.2, 0.8)))
	vbox.add_child(_create_btn("CẨM NANG SINH TỒN", show_index, Vector2(400, 60)))
	vbox.add_child(_create_btn("THOÁT GAME", _quit_game, Vector2(400, 60), Color(0.5, 0.2, 0.2)))

# ==========================================
# 2. XÂY DỰNG MÀN HÌNH CHỌN CLASS
# ==========================================
func _build_class_menu() -> void:
	class_node = CenterContainer.new()
	class_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(class_node)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 40)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	class_node.add_child(vbox)
	
	var title = Label.new()
	title.text = "CHỌN LỚP NHÂN VẬT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 45)
	vbox.add_child(title)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 30)
	vbox.add_child(hbox)
	
	hbox.add_child(_create_btn("🏹 XẠ THỦ\n\nMáu: 100\nVũ khí gốc: Súng Lục", func(): _start_new_game("ranger"), Vector2(300, 200), Color(0.2, 0.5, 0.8)))
	hbox.add_child(_create_btn("⚔️ ĐẤU SĨ\n\nMáu: 200\nVũ khí gốc: Kiếm Dài", func(): _start_new_game("brawler"), Vector2(300, 200), Color(0.8, 0.3, 0.2)))
	
	vbox.add_child(_create_btn("QUAY LẠI", show_main_menu, Vector2(250, 60), Color(0.4, 0.4, 0.4)))
	class_node.hide()

# ==========================================
# 3. XÂY DỰNG CÂY KỸ NĂNG (UPGRADES)
# ==========================================
func _build_upgrade_menu() -> void:
	upgrade_node = MarginContainer.new()
	upgrade_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	upgrade_node.add_theme_constant_override("margin_left", 200)
	upgrade_node.add_theme_constant_override("margin_right", 200)
	upgrade_node.add_theme_constant_override("margin_top", 80)
	upgrade_node.add_theme_constant_override("margin_bottom", 80)
	ui_layer.add_child(upgrade_node)
	
	var panel = Panel.new()
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	p_style.border_width_left = 4; p_style.border_width_right = 4
	p_style.border_width_top = 4; p_style.border_width_bottom = 4
	p_style.border_color = Color(0.7, 0.2, 0.9)
	p_style.corner_radius_top_left = 15; p_style.corner_radius_top_right = 15
	p_style.corner_radius_bottom_left = 15; p_style.corner_radius_bottom_right = 15
	panel.add_theme_stylebox_override("panel", p_style)
	upgrade_node.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	upgrade_node.add_child(vbox)
	
	var header_box = VBoxContainer.new()
	vbox.add_child(header_box)
	
	var title = Label.new()
	title.text = "CÂY KỸ NĂNG"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 45)
	title.add_theme_color_override("font_color", Color(0.8, 0.4, 1.0))
	header_box.add_child(title)
	
	gem_label = Label.new()
	gem_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gem_label.add_theme_font_size_override("font_size", 24)
	gem_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	header_box.add_child(gem_label)
	
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	# Danh sách các kỹ năng
	var list_vbox = VBoxContainer.new()
	list_vbox.add_theme_constant_override("separation", 10)
	vbox.add_child(list_vbox)
	
	for key in upg_data:
		var row = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		list_vbox.add_child(row)
		
		# Thông tin kỹ năng
		var info = Label.new()
		info.custom_minimum_size = Vector2(500, 0)
		info.add_theme_font_size_override("font_size", 20)
		row.add_child(info)
		
		# Nút Nâng cấp
		var btn = _create_btn("Nâng cấp", func(): _buy_upgrade(key), Vector2(180, 50), Color(0.2, 0.6, 0.3))
		btn.add_theme_font_size_override("font_size", 18)
		row.add_child(btn)
		
		upg_ui_elements[key] = {"info": info, "btn": btn}
	
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	
	var center_btn = CenterContainer.new()
	vbox.add_child(center_btn)
	center_btn.add_child(_create_btn("QUAY LẠI", show_main_menu, Vector2(300, 60), Color(0.5, 0.5, 0.5)))
	
	upgrade_node.hide()

func _update_upgrade_ui() -> void:
	gem_label.text = "Đang có: %d Ngọc Tím" % Global.purple_gems
	
	for key in upg_data:
		var current_lv = Global.upgrades[key]
		var max_lv = upg_data[key]["max"]
		var cost = current_lv + 1 # Giá = Cấp hiện tại + 1
		
		var text = "%s (Lv %d/%d)\n[color=#aaaaaa]%s[/color]" % [upg_data[key]["name"], current_lv, max_lv, upg_data[key]["desc"]]
		# Cú pháp RichText để tô màu mô tả, nhưng do dùng Label thường nên ta bỏ tag bbcode, hiện text thường
		upg_ui_elements[key]["info"].text = "%s (Lv %d/%d)\n> %s" % [upg_data[key]["name"], current_lv, max_lv, upg_data[key]["desc"]]
		
		var btn: Button = upg_ui_elements[key]["btn"]
		if current_lv >= max_lv:
			btn.text = "TỐI ĐA"
			btn.disabled = true
			btn.modulate = Color(0.5, 0.5, 0.5)
		elif Global.purple_gems < cost:
			btn.text = "%d Ngọc" % cost
			btn.disabled = true
			btn.modulate = Color(0.5, 0.5, 0.5)
		else:
			btn.text = "%d Ngọc" % cost
			btn.disabled = false
			btn.modulate = Color.WHITE

func _buy_upgrade(key: String) -> void:
	var cost = Global.upgrades[key] + 1
	if Global.purple_gems >= cost and Global.upgrades[key] < upg_data[key]["max"]:
		Global.purple_gems -= cost
		Global.upgrades[key] += 1
		Global.save_game()
		_update_upgrade_ui()


# ==========================================
# 4. XÂY DỰNG TỪ ĐIỂN TRA CỨU (INDEX)
# ==========================================
func _build_index_menu() -> void:
	index_node = MarginContainer.new()
	index_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	index_node.add_theme_constant_override("margin_left", 150)
	index_node.add_theme_constant_override("margin_right", 150)
	index_node.add_theme_constant_override("margin_top", 80)
	index_node.add_theme_constant_override("margin_bottom", 80)
	ui_layer.add_child(index_node)
	
	var panel = Panel.new()
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	p_style.corner_radius_top_left = 15; p_style.corner_radius_top_right = 15
	p_style.corner_radius_bottom_left = 15; p_style.corner_radius_bottom_right = 15
	p_style.border_width_left = 4; p_style.border_width_right = 4
	p_style.border_width_top = 4; p_style.border_width_bottom = 4
	p_style.border_color = Color(0.3, 0.3, 0.4)
	panel.add_theme_stylebox_override("panel", p_style)
	index_node.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	index_node.add_child(vbox)
	
	var title = Label.new()
	title.text = "CẨM NANG SINH TỒN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	vbox.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	var rich_text = RichTextLabel.new()
	rich_text.bbcode_enabled = true
	rich_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rich_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rich_text.add_theme_font_size_override("normal_font_size", 22)
	rich_text.text = _get_index_content()
	scroll.add_child(rich_text)
	
	var center_btn = CenterContainer.new()
	vbox.add_child(center_btn)
	center_btn.add_child(_create_btn("QUAY LẠI", show_main_menu, Vector2(300, 60), Color(0.5, 0.5, 0.5)))
	
	index_node.hide()

func _get_index_content() -> String:
	var t = "[center][b][color=#ffd700]--- BÍ ẨN ĐỘ HIẾM ---[/color][/b][/center]\n\n"
	t += "[b]1. Thường (Trắng)[/b]: Chỉ số gốc.\n[b][color=#44ff44]2. Hiếm (Xanh)[/color][/b]: +25% Sát thương, +2% Hút máu.\n"
	t += "[b][color=#b644ff]3. Sử Thi (Tím)[/color][/b]: +50% Sát thương, +5% Hút máu. Gây hiệu ứng.\n"
	t += "[b][color=#ffd700]4. Huyền Thoại (Vàng)[/color][/b]: +100% Sát thương, +10% Hút máu. Thay đổi cơ chế súng.\n"
	return t

# ==========================================
# CÔNG CỤ & LOGIC CHUYỂN TRANG
# ==========================================
func _create_btn(text_val: String, action: Callable, custom_min_size: Vector2 = Vector2(400, 65), custom_color: Color = Color(0.2, 0.25, 0.35)) -> Button:
	var btn = Button.new()
	btn.text = text_val
	btn.custom_minimum_size = custom_min_size
	btn.add_theme_font_size_override("font_size", 24)
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = custom_color
	style_normal.corner_radius_top_left = 12; style_normal.corner_radius_top_right = 12
	style_normal.corner_radius_bottom_left = 12; style_normal.corner_radius_bottom_right = 12
	style_normal.border_width_bottom = 6
	style_normal.border_color = custom_color.darkened(0.5)
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = custom_color.lightened(0.3)
	
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

func show_main_menu() -> void:
	index_node.hide()
	class_node.hide()
	upgrade_node.hide()
	main_node.show()

func show_index() -> void:
	main_node.hide()
	index_node.show()

func show_class_menu() -> void:
	main_node.hide()
	class_node.show()
	
func show_upgrade_menu() -> void:
	main_node.hide()
	_update_upgrade_ui()
	upgrade_node.show()

func _start_new_game(c_id: String) -> void:
	Global.saved_run.clear() 
	Global.save_game()
	Global.current_class = c_id 
	# ÁP DỤNG KỸ NĂNG: Cấp tiền khởi điểm
	Global.coins = Global.upgrades["start_coin"] * 10
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _continue_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _quit_game() -> void:
	get_tree().quit()
