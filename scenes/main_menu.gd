extends Control
## Main Menu: nền ghép từ tile hầm ngục thật (asset 0x72), sprite nhân vật chạy idle
## đứng cạnh nút bấm, font pixel riêng (Press Start 2P) thay cho font mặc định + emoji.
## Có nút Tiếp Tục khi có file lưu, màn hình chọn lớp nhân vật, cẩm nang tra cứu,
## và cây kỹ năng vĩnh viễn.

const PIXEL_FONT_PATH: String = "res://assets/fonts/PressStart2P-Regular.ttf"
const BG_SCALE: float = 2.0 # 32px gốc -> 64px trên màn hình

## Ánh xạ lớp nhân vật -> bộ sprite 0x72 dùng làm thân người (khớp với player.gd).
const SPRITE_SET: Dictionary = {
	"ranger": "elf_m",
	"brawler": "knight_m",
}

var ui_layer: CanvasLayer
var main_node: CenterContainer
var index_node: MarginContainer
var class_node: CenterContainer
var upgrade_node: MarginContainer # Node cho Cây Kỹ Năng
var pixel_font: FontFile
var _tile_tex_cache: Dictionary = {}

# --- Dữ liệu hệ thống Kỹ năng ---
var upg_data = {
	"hp_boost": {"name": "Iron Physique", "desc": "+10 Max HP per level.", "max": 10},
	"start_coin": {"name": "Starting Capital", "desc": "+10 starting gold per level.", "max": 5},
	"mastery": {"name": "Weapon Mastery", "desc": "+5% base damage per level.", "max": 5},
	"revive": {"name": "Phoenix Rebirth", "desc": "Revive once with 50% HP on death.", "max": 1}
}
var upg_ui_elements = {} # Lưu trữ các nút/chữ để tự động cập nhật
var gem_label: Label

func _ready() -> void:
	for c in get_children():
		c.queue_free()

	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	pixel_font = _load_pixel_font()

	_build_background()
	_build_main_menu()
	_build_index_menu()
	_build_class_menu()
	_build_upgrade_menu() # Xây Cây Kỹ Năng

	show_main_menu()


## Nạp font .ttf trực tiếp từ byte (giống cách project nạp ảnh bằng Image.load),
## tránh phụ thuộc file .import khi chạy headless/test.
func _load_pixel_font() -> FontFile:
	var f := FontFile.new()
	var bytes := FileAccess.get_file_as_bytes(PIXEL_FONT_PATH)
	if bytes.is_empty():
		push_error("Không tải được pixel font: " + PIXEL_FONT_PATH)
		return f
	f.data = bytes
	return f


func _apply_font(ctrl: Control, size: int) -> void:
	ctrl.add_theme_font_override("font", pixel_font)
	ctrl.add_theme_font_size_override("font_size", size)


func _get_tile_tex(filename: String) -> ImageTexture:
	if _tile_tex_cache.has(filename):
		return _tile_tex_cache[filename]
	var img := Image.new()
	var tex: ImageTexture = null
	if img.load("res://assets/dungeon/" + filename) == OK:
		tex = ImageTexture.create_from_image(img)
	_tile_tex_cache[filename] = tex
	return tex


func _add_tile(parent: Node2D, filename: String, grid_x: int, grid_y: int) -> void:
	var tex := _get_tile_tex(filename)
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.scale = Vector2(BG_SCALE, BG_SCALE)
	var cell: float = 32.0 * BG_SCALE
	s.position = Vector2(float(grid_x) * cell + cell * 0.5, float(grid_y) * cell + cell * 0.5)
	parent.add_child(s)


# ==========================================
# 0. NỀN GHÉP TỪ TILE HẦM NGỤC THẬT
# ==========================================
func _build_background() -> void:
	var bg_root = Node2D.new()
	ui_layer.add_child(bg_root)

	var cell: float = 32.0 * BG_SCALE
	var cols: int = int(ceil(1280.0 / cell)) + 1
	var rows: int = int(ceil(720.0 / cell)) + 1

	var floor_variants := ["floor_1.png", "floor_1.png", "floor_1.png", "floor_2.png", "floor_3.png", "floor_5.png"]

	# Hàng 0: viền tường trên cùng. Hàng 1: mặt tường. Từ hàng 2 trở đi: sàn.
	for x in cols:
		if x == 0:
			_add_tile(bg_root, "wall_top_left.png", x, 0)
		elif x == cols - 1:
			_add_tile(bg_root, "wall_top_right.png", x, 0)
		else:
			_add_tile(bg_root, "wall_top_mid.png", x, 0)
		_add_tile(bg_root, "wall_mid.png", x, 1)

	for y in range(2, rows):
		for x in cols:
			_add_tile(bg_root, floor_variants[randi() % floor_variants.size()], x, y)

	# Vài cây cột trang trí cho có chiều sâu.
	_add_tile(bg_root, "column.png", 3, 3)
	_add_tile(bg_root, "column.png", cols - 4, 3)

	# Phủ tối để chữ/nút bấm luôn rõ, nhưng vẫn thấy nền hầm ngục phía sau.
	var overlay = ColorRect.new()
	overlay.color = Color(0.05, 0.05, 0.08, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(overlay)


## Dựng bộ khung idle animation cho 1 class (dùng chung công thức với player.gd).
func _build_idle_frames(prefix: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 6.0)
	frames.set_animation_loop("idle", true)
	for i in 4:
		var path: String = "res://assets/dungeon/%s_idle_anim_f%d.png" % [prefix, i]
		var img := Image.new()
		if img.load(path) == OK:
			frames.add_frame("idle", ImageTexture.create_from_image(img))
	return frames


func _make_class_preview(prefix: String, box_size: Vector2, sprite_scale: float) -> Control:
	var box := Control.new()
	box.custom_minimum_size = box_size
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = _build_idle_frames(prefix)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(sprite_scale, sprite_scale)
	sprite.position = box_size * 0.5
	box.add_child(sprite)
	sprite.play("idle")
	return box


# ==========================================
# 1. XÂY DỰNG SẢNH CHÍNH (MAIN MENU)
# ==========================================
func _build_main_menu() -> void:
	main_node = CenterContainer.new()
	main_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(main_node)

	var outer_vbox = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 30)
	outer_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_node.add_child(outer_vbox)

	var title = Label.new()
	title.text = "DUNGEON RAIDER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(title, 40)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title.add_theme_color_override("font_shadow_color", Color(0.8, 0.2, 0.1))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 10)
	outer_vbox.add_child(title)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 50)
	outer_vbox.add_child(hbox)

	var prefix: String = SPRITE_SET.get(Global.current_class, "knight_m")
	hbox.add_child(_make_class_preview(prefix, Vector2(180, 220), 4.5))

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(vbox)

	var has_save = not Global.saved_run.is_empty()

	if has_save:
		vbox.add_child(_create_btn("CONTINUE", _continue_game, Vector2(400, 60), Color(0.3, 0.8, 0.4)))
		vbox.add_child(_create_btn("NEW GAME", show_class_menu, Vector2(400, 60), Color(0.8, 0.3, 0.3)))
	else:
		vbox.add_child(_create_btn("START GAME", show_class_menu, Vector2(400, 60)))

	vbox.add_child(_create_btn("SKILL TREE", show_upgrade_menu, Vector2(400, 60), Color(0.6, 0.2, 0.8)))
	vbox.add_child(_create_btn("SURVIVAL GUIDE", show_index, Vector2(400, 60)))
	vbox.add_child(_create_btn("QUIT", _quit_game, Vector2(400, 60), Color(0.5, 0.2, 0.2)))

# ==========================================
# 2. XÂY DỰNG MÀN HÌNH CHỌN CLASS
# ==========================================
func _build_class_menu() -> void:
	class_node = CenterContainer.new()
	class_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(class_node)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 30)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	class_node.add_child(vbox)

	var title = Label.new()
	title.text = "CHOOSE YOUR CLASS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(title, 22)
	vbox.add_child(title)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 40)
	vbox.add_child(hbox)

	hbox.add_child(_build_class_option("elf_m", "RANGER\n\nHP: 100\nWeapon: Pistol", func(): _start_new_game("ranger"), Color(0.2, 0.5, 0.8)))
	hbox.add_child(_build_class_option("knight_m", "BRAWLER\n\nHP: 200\nWeapon: Longsword", func(): _start_new_game("brawler"), Color(0.8, 0.3, 0.2)))

	vbox.add_child(_create_btn("BACK", show_main_menu, Vector2(250, 60), Color(0.4, 0.4, 0.4)))
	class_node.hide()


func _build_class_option(prefix: String, label_text: String, action: Callable, color: Color) -> Control:
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_make_class_preview(prefix, Vector2(140, 150), 3.5))
	col.add_child(_create_btn(label_text, action, Vector2(300, 170), color, 14))
	return col

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
	title.text = "SKILL TREE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(title, 24)
	title.add_theme_color_override("font_color", Color(0.8, 0.4, 1.0))
	header_box.add_child(title)

	gem_label = Label.new()
	gem_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(gem_label, 16)
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
		_apply_font(info, 12)
		row.add_child(info)

		# Nút Nâng cấp
		var btn = _create_btn("Upgrade", func(): _buy_upgrade(key), Vector2(180, 50), Color(0.2, 0.6, 0.3), 12)
		row.add_child(btn)

		upg_ui_elements[key] = {"info": info, "btn": btn}

	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var center_btn = CenterContainer.new()
	vbox.add_child(center_btn)
	center_btn.add_child(_create_btn("BACK", show_main_menu, Vector2(300, 60), Color(0.5, 0.5, 0.5)))

	upgrade_node.hide()

func _update_upgrade_ui() -> void:
	gem_label.text = "Gems: %d" % Global.purple_gems

	for key in upg_data:
		var current_lv = Global.upgrades[key]
		var max_lv = upg_data[key]["max"]
		var cost = current_lv + 1 # Giá = Cấp hiện tại + 1

		upg_ui_elements[key]["info"].text = "%s (Lv %d/%d)\n> %s" % [upg_data[key]["name"], current_lv, max_lv, upg_data[key]["desc"]]

		var btn: Button = upg_ui_elements[key]["btn"]
		if current_lv >= max_lv:
			btn.text = "MAX"
			btn.disabled = true
			btn.modulate = Color(0.5, 0.5, 0.5)
		elif Global.purple_gems < cost:
			btn.text = "%d Gems" % cost
			btn.disabled = true
			btn.modulate = Color(0.5, 0.5, 0.5)
		else:
			btn.text = "%d Gems" % cost
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
	title.text = "SURVIVAL GUIDE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(title, 22)
	title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	vbox.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var rich_text = RichTextLabel.new()
	rich_text.bbcode_enabled = true
	rich_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rich_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rich_text.add_theme_font_override("normal_font", pixel_font)
	rich_text.add_theme_font_override("bold_font", pixel_font)
	rich_text.add_theme_font_size_override("normal_font_size", 14)
	rich_text.add_theme_font_size_override("bold_font_size", 14)
	rich_text.text = _get_index_content()
	scroll.add_child(rich_text)

	var center_btn = CenterContainer.new()
	vbox.add_child(center_btn)
	center_btn.add_child(_create_btn("BACK", show_main_menu, Vector2(300, 60), Color(0.5, 0.5, 0.5)))

	index_node.hide()

func _get_index_content() -> String:
	var t = "[center][b][color=#ffd700]--- RARITY GUIDE ---[/color][/b][/center]\n\n"
	t += "[b]1. Common (White)[/b]: Base stats.\n[b][color=#44ff44]2. Rare (Green)[/color][/b]: +25% Damage, +2% Lifesteal.\n"
	t += "[b][color=#b644ff]3. Epic (Purple)[/color][/b]: +50% Damage, +5% Lifesteal. Applies a special effect.\n"
	t += "[b][color=#ffd700]4. Legendary (Gold)[/color][/b]: +100% Damage, +10% Lifesteal. Changes weapon behavior.\n"
	return t

# ==========================================
# CÔNG CỤ & LOGIC CHUYỂN TRANG
# ==========================================
func _create_btn(text_val: String, action: Callable, custom_min_size: Vector2 = Vector2(400, 65), custom_color: Color = Color(0.2, 0.25, 0.35), font_size: int = 16) -> Button:
	var btn = Button.new()
	btn.text = text_val
	btn.custom_minimum_size = custom_min_size
	_apply_font(btn, font_size)

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
